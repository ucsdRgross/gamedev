// The Design Loop local server (PLAN S1, §4.8). Static hosting for `web/` and `src/` plus the
// JSON API the browser answers questions through. Zero dependencies; modelled on
// `palette/tools/serve.mjs`, including its ping/shutdown port-reclaim pattern.
//
//   GET  /                     -> redirect to /web/index.html
//   GET  /web/... /src/...     -> static files (the browser imports src/grammar.mjs directly)
//   GET  /api/ping             -> { app: 'designloop', pid, port }
//   POST /api/shutdown         -> stops this server (loopback callers only)
//
// The design API of §4.8 is added by the steps that need it; `routes()` below is the one place
// it grows, so there is never a second router.
//
// Path traversal is refused: a resolved request path that escapes the tool directory is a 403.

import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve, extname, normalize, sep } from 'node:path';
import { spawn } from 'node:child_process';

import { parseDocument, reachability, nextQuestion, blastRadius } from './grammar.mjs';
import { parseCharts, validate as validateGraph } from './graph.mjs';
import {
  load, answer as writeAnswer, hashDoc, readJson, writeJsonAtomic, annotate, mark, materialiseShape,
} from './store.mjs';
import { discover, find, writeOwnerStatus, touch, readAssumptions } from './registry.mjs';
import {
  readGaps, countGaps, scopedQuestions, nextGapQuestion, readPlanSteps, staleFor, promoteAssumption,
} from './gaps.mjs';
import { listVersions, readVersion, diffGraphs, freeze } from './versions.mjs';

/** designloop/ — the tool directory, and the static root. */
export const TOOL_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
/**
 * The repo root, which is what the registry scans for `<project>/design/<slug>/`.
 * `DESIGNLOOP_ROOT` overrides it so the API tests can point at a throwaway tree instead of
 * writing fixture projects into the repo they are testing.
 */
export const REPO_ROOT = resolve(process.env.DESIGNLOOP_ROOT || resolve(TOOL_ROOT, '..'));

/** Only these two directories are ever served; everything else 404s even if it exists. */
const STATIC_DIRS = ['web', 'src'];

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.md': 'text/plain; charset=utf-8',
};

/** Send a JSON response with the given status. */
export function sendJson(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

/** Read a full request body as text, capped so a runaway upload cannot exhaust memory. */
export function readBody(req, limit = 1 << 20) {
  return new Promise((resolvePromise, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(new Error('body too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolvePromise(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

/** Resolve a URL path to a file under one of STATIC_DIRS, or null if it escapes. */
function resolveStatic(pathname) {
  const clean = decodeURIComponent(pathname.split('?')[0]);
  const rel = normalize(clean).replace(/^(\.\.[/\\])+/, '').replace(/^[/\\]+/, '');
  const top = rel.split(/[/\\]/)[0];
  if (!STATIC_DIRS.includes(top)) return null;
  const abs = resolve(TOOL_ROOT, rel);
  if (!abs.startsWith(TOOL_ROOT + sep)) return null;
  return abs;
}

/** Serve a static file, falling back to index.html for a bare directory request. */
async function handleStatic(req, res, pathname) {
  let file = resolveStatic(pathname);
  if (!file) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404 Not Found');
    return;
  }
  try {
    const info = await stat(file);
    if (info.isDirectory()) file = join(file, 'index.html');
    const data = await readFile(file);
    res.writeHead(200, {
      'Content-Type': MIME[extname(file).toLowerCase()] || 'application/octet-stream',
      'Content-Length': data.length,
      'Cache-Control': 'no-store',
    });
    res.end(req.method === 'HEAD' ? undefined : data);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404 Not Found');
  }
}

/** Only a caller on this machine may reach the API at all (Q93: localhost only). */
export function isLoopback(req) {
  const addr = req.socket.remoteAddress || '';
  return addr === '127.0.0.1' || addr === '::1' || addr === '::ffff:127.0.0.1';
}

/**
 * Everything a question screen needs, in one payload: the design, its answers, and the parsed
 * document. Parsing on every request is deliberate — the document is the source of truth (QR7=a)
 * and the owner may be editing it in another window; a cache would be a second copy.
 */
async function openDesign(rawKey) {
  const design = await find(REPO_ROOT, rawKey);
  if (!design) return null;
  const markdown = await readFile(design.docPath, 'utf8').catch(() => null);
  if (markdown === null) return { design, missingDoc: true };
  const parsed = parseDocument(markdown);
  const state = await load(design.dir, { slug: design.slug });
  // The gaps come along on every request (S15). They are a handful of small files, and a scoped
  // round answers them through the same routes as the questionnaire — one answer path, not two.
  const gaps = await readGaps(design.dir);
  return { design, parsed, state, gaps, docHash: hashDoc(markdown) };
}

/** Strip the fields the question screen must never see. Q26=a: nothing indicates progress. */
function forScreen(question, sections) {
  if (!question) return null;
  const section = sections.find((s) => s.index === question.section);
  return {
    id: question.id,
    text: question.text,
    options: question.options,
    default: question.default,
    defaultNote: question.defaultNote,
    notes: question.notes,
    isGate: question.isGate,
    hint: question.hint,
    gate: question.gate,
    effectiveGate: question.effectiveGate,
    section: section ? { title: section.title, gate: section.gate } : null,
    // A gap question carries the report it came out of, so the screen stays self-contained (rule 4)
    // without the owner going to find the file. Absent on an ordinary question.
    gap: question.gap || null,
    context: question.context || null,
  };
}

/**
 * The design graph (§4.6), ingested from the document's ```mermaid blocks.
 *
 * `graph.json` is a generated artefact: the document is the source of truth (QR7=a) and the canvas
 * renders the same file an implementation agent consumes (Q64=a, no mocks). It is rewritten only
 * when the document's hash moves, so an agent reading it off disk gets a real file rather than a
 * cache that only exists while the server is up.
 */
async function buildGraph(design, markdown, docHash) {
  const graph = parseCharts(markdown, { file: design.doc });
  graph.doc_hash = docHash;
  const path = join(design.dir, 'graph.json');
  const existing = await readJson(path);
  if (!existing || existing.doc_hash !== docHash) await writeJsonAtomic(path, graph);
  return graph;
}

/**
 * The three assumption sources the review panel lists, visually distinguished (Q58=c, Q116=a):
 * what the agent declared, what was Enter-defaulted, and what was waved through as not relevant.
 * Listing only the first would hide exactly the answers nobody thought about.
 */
async function assumptionsFor(design, parsed, answers) {
  const out = await readAssumptions(design.dir);
  for (const q of parsed.questions) {
    const a = answers[q.id];
    if (!a || a.active === false) continue;
    if (a.state !== 'defaulted' && a.state !== 'not_relevant') continue;
    const option = q.options.find((o) => o.letter === a.option);
    out.push({
      source: a.state,
      id: q.id,
      text: `${q.text} — took (${a.option}) ${option ? option.label : ''}`,
      why: a.state === 'defaulted' ? 'accepted with Enter, unread' : 'marked not worth answering',
    });
  }
  return out;
}

/**
 * The out-of-scope list (chart F3, Q57=a). Derived, not authored: a question is out of scope when
 * its section says so or when the answer it took is literally an exclusion. Best-effort by design —
 * the same standing as `decidedBy` in §4.6 — and both design documents end with exactly such a
 * section, which is the convention the flowchart-design skill asks for.
 */
function outOfScopeFor(parsed, answers) {
  const out = [];
  for (const q of parsed.questions) {
    const a = answers[q.id];
    if (!a || a.active === false || a.override) continue;
    const option = q.options.find((o) => o.letter === a.option);
    if (!option) continue;
    const section = parsed.sections.find((s) => s.index === q.section);
    const bySection = /out of scope/i.test(section?.title || '');
    const byAnswer = /^out of scope\b/i.test(option.label);
    if (bySection || byAnswer) out.push({ id: q.id, text: q.text, answer: option.label });
  }
  return out;
}

/**
 * Who the owner's turn passes to after an answer (§4.2, charts B15/E2).
 * `new_branch_needed` is the free-text-at-a-gate case and is the only ending that can arrive with
 * reachable questions still unanswered (chart B2).
 */
async function settleOwnerStatus(design, parsed, answers, { override = false, question = null, gaps = [] } = {}) {
  if (override && question?.isGate) {
    return writeOwnerStatus(design.dir, { state: 'done', reason: 'new_branch_needed' });
  }
  // A scoped gap round ends on its own terms (chart J12/J15): it never asks the questionnaire
  // again, so the questionnaire's reachable set says nothing about whether it is finished. Its
  // ending is what wakes the agent to write design version N+1.
  if (question?.gap) {
    const left = nextGapQuestion(gaps, answers);
    return writeOwnerStatus(design.dir, left
      ? { state: 'answering', reason: null }
      : { state: 'done', reason: 'gaps_answered' });
  }
  const { reachable } = reachability(parsed.questions, answers);
  if (!reachable.length) return writeOwnerStatus(design.dir, { state: 'done', reason: 'complete' });
  return writeOwnerStatus(design.dir, { state: 'answering', reason: null });
}

/** The `/api/designs…` routes of §4.8. */
async function handleDesignApi(req, res, pathname, query) {
  if (pathname === '/api/designs' || pathname === '/api/designs/') {
    const designs = await discover(REPO_ROOT);
    sendJson(res, 200, designs.map((d) => ({
      key: d.key, slug: d.slug, title: d.title, projects: d.projects, archived: d.archived,
      owner: d.owner, agent: d.agent, answered: d.answered,
      // Q89b=c badges the open ones; Q96b=a keeps the closed ones, and the card is where "kept"
      // is visible without opening a directory.
      gaps: d.gaps, gaps_closed: d.gaps_closed, gaps_total: d.gaps_total,
      touched: d.touched, rounds: d.rounds, confirmed_version: d.confirmed_version,
      // GAP-001=b: a document that parses with warnings is answerable, but the defect is the
      // authoring agent's to fix, so it is on the card rather than only in `run check`.
      errors: d.errors, warnings: d.warnings, doc_missing: d.doc_missing,
    })));
    return;
  }

  const rest = pathname.slice('/api/designs/'.length).split('/');
  const rawKey = rest.slice(0, 2).join('/');
  const action = rest[2] || '';
  const opened = await openDesign(rawKey);
  if (!opened) {
    sendJson(res, 404, { error: 'no such design' });
    return;
  }
  const { design } = opened;
  if (opened.missingDoc) {
    sendJson(res, 500, { error: `cannot read ${design.doc}`, key: design.key });
    return;
  }
  const { parsed, state, gaps, docHash } = opened;
  const answers = state.answers;

  if (action === '' && req.method === 'GET') {
    await touch(design.dir);
    sendJson(res, 200, {
      key: design.key, slug: design.slug, title: design.title, projects: design.projects,
      doc: design.doc, rounds: design.rounds, confirmed_version: design.confirmed_version,
      archived: design.archived, owner: design.owner, agent: design.agent,
      errors: parsed.errors.map((e) => e.message),
      warnings: parsed.warnings.map((e) => e.message),
      doc_hash: docHash,
      doc_changed: !!(state.doc_hash && state.doc_hash !== docHash),
    });
    return;
  }

  // The browser parses the document with the same module the server does (PLAN §2), so it needs
  // the source. Serving it here rather than statically keeps the doc's location an implementation
  // detail of `meta.json` — it may sit anywhere the design directory points.
  if (action === 'doc' && req.method === 'GET') {
    const text = await readFile(design.docPath, 'utf8');
    res.writeHead(200, {
      'Content-Type': 'text/plain; charset=utf-8',
      'Content-Length': Buffer.byteLength(text),
      'Cache-Control': 'no-store',
    });
    res.end(text);
    return;
  }

  // §4.8 GET /graph. A chart outside the §6 subset throws, and the message names the file and the
  // line — the canvas shows it as plain text rather than failing silently or drawing half a graph.
  if (action === 'graph' && req.method === 'GET') {
    try {
      const graph = await buildGraph(design, await readFile(design.docPath, 'utf8'), docHash);
      sendJson(res, 200, { ...graph, errors: validateGraph(graph).map((e) => e.message) });
    } catch (err) {
      sendJson(res, 422, { error: String(err.message || err), key: design.key });
    }
    return;
  }

  // Everything the review panel needs that §4.8 has no route for: the annotations back out again,
  // and the two derived lists (assumptions, out-of-scope) that only the server can compute.
  if (action === 'review' && req.method === 'GET') {
    sendJson(res, 200, {
      annotations: (await readJson(join(design.dir, 'annotations.json')))
        || { nodes: {}, edges: {}, approved: {}, flagged: {} },
      assumptions: await assumptionsFor(design, parsed, answers),
      out_of_scope: outOfScopeFor(parsed, answers),
      confirmed_version: design.confirmed_version,
    });
    return;
  }

  // F10 — "Review again": the owner hands the graph back with their annotations on it. §4.2 gives
  // the owner half no `reason` for this transition; `review_again` is the addition (ASSUMPTIONS.md).
  if (action === 'review' && req.method === 'POST') {
    const status = await writeOwnerStatus(design.dir, { state: 'done', reason: 'review_again' });
    sendJson(res, 200, { ok: true, owner: status });
    return;
  }

  // §4.8 GET /gaps — open AND closed (Q96b=a), each with its own draft question, plus the plan
  // steps the open ones make stale (chart J16, Q92b=a). The whole gap surface is this one payload:
  // the index badge, the scoped round and the stale-step report all read it.
  if (action === 'gaps' && req.method === 'GET') {
    const steps = await readPlanSteps(design.dir);
    sendJson(res, 200, {
      key: design.key,
      counts: countGaps(gaps),
      gaps: gaps.map(({ text, question, ...rest }) => ({
        ...rest, question: forScreen(question, parsed.sections),
        answer: answers[rest.id] || null,
      })),
      scoped: scopedQuestions(gaps).map((q) => q.id),
      stale: staleFor(gaps, steps),
      steps: steps.length,
    });
    return;
  }

  // Q95b=a — the owner takes back the licence to assume something. The gap is filed with no
  // options (the tool does not author questions, Q94=a) and every step that relied on it is stale
  // from this moment, which the `stale` list above reports without anything else being written.
  if (action === 'promote' && req.method === 'POST') {
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      sendJson(res, 400, { error: 'body must be valid JSON' });
      return;
    }
    if (!body.assumption) {
      sendJson(res, 400, { error: 'name the assumption being promoted' });
      return;
    }
    const filed = await promoteAssumption(design.dir, {
      assumption: String(body.assumption),
      step: String(body.step || ''),
      nodes: Array.isArray(body.nodes) ? body.nodes : [],
      why: String(body.why || ''),
    });
    sendJson(res, 200, { ok: true, ...filed });
    return;
  }

  if (action === 'versions' && req.method === 'GET') {
    if (rest[3]) {
      const version = await readVersion(design.dir, Number(rest[3]));
      if (!version) {
        sendJson(res, 404, { error: `no version ${rest[3]}` });
        return;
      }
      sendJson(res, 200, version);
      return;
    }
    sendJson(res, 200, { versions: await listVersions(design.dir), confirmed: design.confirmed_version });
    return;
  }

  // Q62=a — node-level added / changed / removed between two frozen versions.
  if (action === 'diff' && req.method === 'GET') {
    const a = await readVersion(design.dir, Number(query.get('a')));
    const b = await readVersion(design.dir, Number(query.get('b')));
    if (!a || !b) {
      sendJson(res, 404, { error: 'both versions must exist' });
      return;
    }
    sendJson(res, 200, { a: a.n, b: b.n, ...diffGraphs(a.graph, b.graph) });
    return;
  }

  if ((action === 'annotate' || action === 'approve') && req.method === 'POST') {
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      sendJson(res, 400, { error: 'body must be valid JSON' });
      return;
    }
    // §4.8 spells the approve body `{node}`; Q59 needs edges and a state, so both are accepted.
    const target = body.target || (body.node ? 'node' : 'edge');
    const markKey = body.key || body.node;
    if (!markKey) {
      sendJson(res, 400, { error: 'name the node or edge' });
      return;
    }
    const written = action === 'annotate'
      ? await annotate(design.dir, target, markKey, String(body.text ?? ''))
      : await mark(design.dir, markKey, body.state ?? 'approved', { version: design.confirmed_version ?? 0 });
    sendJson(res, 200, { ok: true, annotations: written });
    return;
  }

  // F11 / G2 — Confirm freezes the next version, layout and collapse state included (Q115=b).
  if (action === 'confirm' && req.method === 'POST') {
    let body = {};
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      body = {};
    }
    if (!body.layout?.positions) {
      sendJson(res, 400, { error: 'confirm needs the layout that is on screen (Q115=b)' });
      return;
    }
    const graph = await buildGraph(design, await readFile(design.docPath, 'utf8'), docHash);
    const frozen = await freeze(design.dir, {
      design,
      graph,
      questions: parsed.questions,
      answers: materialiseShape(state),
      annotations: (await readJson(join(design.dir, 'annotations.json')))
        || { nodes: {}, edges: {}, approved: {}, flagged: {} },
      layout: body.layout,
      assumptions: await assumptionsFor(design, parsed, answers),
      outOfScope: outOfScopeFor(parsed, answers),
      gaps: gaps.map(({ text, question, ...g }) => g),
    });
    // `meta.json` is the agent's file, but Confirm is an owner action and the agent is idle while
    // the owner reviews (Q24=a), so there is no second writer to race. Recorded in ASSUMPTIONS.md.
    const meta = (await readJson(join(design.dir, 'meta.json'))) || {};
    await writeJsonAtomic(join(design.dir, 'meta.json'), { ...meta, confirmed_version: frozen.version });
    sendJson(res, 200, { ok: true, version: frozen.version, versions: await listVersions(design.dir) });
    return;
  }

  if (action === 'next' && req.method === 'GET') {
    // `?scope=gaps` is the scoped round (Q90b=b, chart J12): the open gaps' own questions and
    // nothing else. Never the whole questionnaire again — that is the promise of a gap round.
    const scoped = query.get('scope') === 'gaps';
    const question = scoped
      ? nextGapQuestion(gaps, answers)
      : nextQuestion(parsed.questions, answers, parsed.sections);
    if (!question) {
      sendJson(res, 200, {
        done: true, owner: design.owner, agent: design.agent, scope: scoped ? 'gaps' : null,
        reason: design.owner.reason, round: design.agent.round,
      });
      return;
    }
    sendJson(res, 200, {
      done: false,
      question: forScreen(question, parsed.sections),
      answer: answers[question.id] || null,
      round: design.agent.round,
      answered: state.order.filter((id) => answers[id]?.active !== false).length,
    });
    return;
  }

  // The last leg of the §4.2 handshake: the agent set `ready`, the UI takes the turn back. The
  // owner half is UI-owned, so this transition can only be written from here.
  if (action === 'resume' && req.method === 'POST') {
    const status = await writeOwnerStatus(design.dir, {
      state: 'answering', reason: null, round: design.agent.round,
    });
    sendJson(res, 200, { ...design, owner: status, dir: undefined, docPath: undefined });
    return;
  }

  if (action === 'history' && req.method === 'GET') {
    // Gap answers are answers: they go in the same file (§4.3) and belong in the same history, or
    // BACK from a scoped round would have nowhere to go.
    const map = new Map([...parsed.questions, ...scopedQuestions(gaps)].map((q) => [q.id, q]));
    sendJson(res, 200, state.order.filter((id) => map.has(id)).map((id) => {
      const q = map.get(id);
      const a = answers[id];
      const picked = q.options.find((o) => o.letter === a.option);
      return {
        id, text: q.text, state: a.state, option: a.option, note: a.note,
        override: a.override, active: a.active !== false, isGate: q.isGate,
        label: picked ? picked.label : null,
      };
    }));
    return;
  }

  if ((action === 'answer' || action === 'reanswer') && req.method === 'POST') {
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      sendJson(res, 400, { error: 'body must be valid JSON' });
      return;
    }
    const question = parsed.questions.find((q) => q.id === body.id)
      || scopedQuestions(gaps).find((q) => q.id === body.id);
    if (!question || question.retired) {
      sendJson(res, 400, { error: `no such question: ${body.id}` });
      return;
    }
    const override = body.override === true;
    const option = override ? null : (body.option || question.default);
    if (!override && !question.options.some((o) => o.letter === option)) {
      sendJson(res, 400, { error: `${question.id} has no option (${option})` });
      return;
    }
    const record = {
      id: question.id,
      state: body.state === 'not_relevant' || body.state === 'defaulted' ? body.state : 'chosen',
      option,
      note: typeof body.note === 'string' ? body.note : '',
      override,
      round: design.agent.round,
    };
    const radius = blastRadius(parsed.questions, answers, question.id, { option, override });

    // Q34=a: a re-answer that strands other answers is previewed before it applies, never after.
    if (query.get('preview') === '1') {
      const map = new Map(parsed.questions.map((q) => [q.id, q]));
      sendJson(res, 200, {
        preview: true,
        strand: radius.strand.map((id) => ({ id, text: map.get(id)?.text || '' })),
        restore: radius.restore.map((id) => ({ id, text: map.get(id)?.text || '' })),
      });
      return;
    }

    // §4.4: log, fsync, materialise, fsync — and only then a 200. If this throws, the UI does not
    // advance, which is the whole of chart I7.
    const written = await writeAnswer(design.dir, record, {
      strand: radius.strand, restore: radius.restore, slug: design.slug, docHash,
    });
    const status = await settleOwnerStatus(design, parsed, written.answers, { override, question, gaps });
    const next = question.gap
      ? nextGapQuestion(gaps, written.answers)
      : nextQuestion(parsed.questions, written.answers, parsed.sections);
    sendJson(res, 200, {
      ok: true,
      strand: radius.strand,
      restore: radius.restore,
      owner: status,
      done: !next,
      next: forScreen(next, parsed.sections),
    });
    return;
  }

  sendJson(res, 404, { error: 'no such endpoint' });
}

/**
 * Build the HTTP server without binding it — the test harness listens on port 0.
 * `onShutdown` is what `POST /api/shutdown` calls; without it the route does not exist,
 * so a server embedded in a test cannot be told to stop.
 */
export function createDevServer({ onShutdown = null } = {}) {
  return createServer(async (req, res) => {
    try {
      const pathname = (req.url || '/').split('?')[0];

      if (pathname === '/api/ping') {
        sendJson(res, 200, { app: 'designloop', pid: process.pid, port: req.socket.localPort });
        return;
      }
      if (pathname === '/api/shutdown') {
        if (!onShutdown) sendJson(res, 404, { error: 'not found' });
        else if (req.method !== 'POST') sendJson(res, 405, { error: 'method not allowed' });
        else if (!isLoopback(req)) sendJson(res, 403, { error: 'forbidden' });
        else {
          sendJson(res, 200, { ok: true, stopping: true });
          // Reply first, then stand down, so the caller knows it was heard.
          setTimeout(onShutdown, 20);
        }
        return;
      }
      if (pathname.startsWith('/api/')) {
        if (!isLoopback(req)) {
          sendJson(res, 403, { error: 'forbidden' });
          return;
        }
        if (pathname === '/api/designs' || pathname.startsWith('/api/designs/')) {
          const query = new URL(req.url, 'http://localhost').searchParams;
          await handleDesignApi(req, res, pathname, query);
          return;
        }
        sendJson(res, 404, { error: 'no such endpoint' });
        return;
      }

      if (pathname === '/' || pathname === '/index.html') {
        res.writeHead(302, { Location: '/web/index.html' });
        res.end();
        return;
      }
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        sendJson(res, 405, { error: 'method not allowed' });
        return;
      }
      await handleStatic(req, res, pathname);
    } catch (err) {
      sendJson(res, 500, { error: String(err && err.message ? err.message : err) });
    }
  });
}

/** Open a URL in the user's browser, so `start.cmd` can be a double-click rather than a command. */
function openBrowser(url) {
  const [cmd, args] = process.platform === 'win32'
    ? ['cmd', ['/c', 'start', '', url]]
    : process.platform === 'darwin' ? ['open', [url]] : ['xdg-open', [url]];
  try {
    spawn(cmd, args, { detached: true, stdio: 'ignore' }).unref();
  } catch {
    process.stdout.write('could not open a browser automatically\n');
  }
}

/** Ask whoever holds a port to identify itself. `null` means nothing answered. */
async function probe(port) {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/api/ping`, { signal: AbortSignal.timeout(600) });
    return res.ok ? await res.json() : {};
  } catch {
    return null;
  }
}

/** Ask a previous instance to stand down, and wait for it to actually let go of the port. */
async function replaceExisting(port) {
  const existing = await probe(port);
  if (existing?.app !== 'designloop') {
    // Either the port is free, or something that is not us has it. Never stop a stranger's
    // server just because it picked the same port — the listen retry moves us instead.
    return existing === null;
  }
  process.stdout.write(`replacing the design loop server already on port ${port} (pid ${existing.pid})\n`);
  try {
    await fetch(`http://127.0.0.1:${port}/api/shutdown`, { method: 'POST', signal: AbortSignal.timeout(1000) });
  } catch {
    // An older build with no shutdown route. Fall through: the retry finds another port.
  }
  for (let i = 0; i < 20; i++) {
    if (await probe(port) === null) return true;
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
}

/**
 * Listen on `port`, stepping to the next one if something else already has it.
 *
 * Bound to the loopback address, never to every interface: Q93 is localhost only, and `isLoopback`
 * guards `/api/*` alone — `/api/ping`, `/web/…` and `/src/…` answer before it. On a shared network
 * an all-interfaces bind is what turns "the owner's tool" into "a service on the LAN".
 */
export function listenFrom(server, port, attempts = 20, host = '127.0.0.1') {
  return new Promise((resolvePromise, reject) => {
    let current = port;
    let left = attempts;
    const onError = (err) => {
      if (err.code !== 'EADDRINUSE' || left-- <= 0) {
        reject(err);
        return;
      }
      current += 1;
      server.listen(current, host);
    };
    server.on('error', onError);
    server.once('listening', () => {
      server.off('error', onError);
      // Ask the socket, not the request: port 0 means "any free port", and only the socket knows.
      resolvePromise(server.address().port);
    });
    server.listen(current, host);
  });
}

/** Start listening. Only runs when invoked directly, not when imported by a test. */
async function main() {
  const port = Number(process.env.PORT) || 5273;

  if (process.argv.includes('--replace')) await replaceExisting(port);

  let server;
  const stop = () => {
    // `close` releases the listening socket at once — what the replacement waits for — but its
    // callback only fires once every open connection has finished, and a keep-alive socket would
    // hold it open. `closeAllConnections` drops those; the timer is a backstop, because a process
    // being replaced must not outlive the handover.
    server.close(() => process.exit(0));
    server.closeAllConnections?.();
    setTimeout(() => process.exit(0), 500);
  };
  server = createDevServer({ onShutdown: stop });

  const bound = await listenFrom(server, port);
  const url = `http://localhost:${bound}`;
  if (bound !== port) process.stdout.write(`port ${port} is taken by something else\n`);
  process.stdout.write(`design loop → ${url}\n`);
  if (process.argv.includes('--open')) openBrowser(url);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
