// Does this document parse? (PLAN S10.) The authoring agent's check before it hands over a URL:
// a question the parser cannot read is a question the owner never sees.
//
//   npm --prefix designloop run check -- solatro/spotlight
//   npm --prefix designloop run check -- path/to/DESIGN.md
//   npm --prefix designloop run check -- solatro/spotlight charts     one line per mermaid chart
//   npm --prefix designloop run check -- solatro/spotlight answers    every answer given in PROSE
//   npm --prefix designloop run check -- solatro/spotlight answer Q16 one answer + every restatement

import { readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseDocument, reachability, nextQuestion, longestPath, auditGates } from './grammar.mjs';
import { parseCharts, validate as validateGraph, describeGraph } from './graph.mjs';
import { find } from './registry.mjs';
import { readJson } from './store.mjs';
import { readPlanSteps } from './gaps.mjs';
import { softAnswers, quoteAudit, contractAudit, restatementsOf } from './provenance.mjs';

const TOOL_ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const REPO_ROOT = resolve(process.env.DESIGNLOOP_ROOT || resolve(TOOL_ROOT, '..'));

/** Parse a document and describe it the way the authoring agent needs to hear it. */
export function describe(markdown, file = 'DESIGN.md') {
  const parsed = parseDocument(markdown);
  const live = parsed.questions.filter((q) => !q.retired);
  const { reachable, pending } = reachability(live, {});

  // The charts are half the document (S11). A chart the canvas cannot ingest is a chart the owner
  // never reviews, so it is reported here, before a URL is handed over, not after.
  let graph = null;
  let graphError = null;
  try {
    graph = parseCharts(markdown, { file });
  } catch (err) {
    graphError = err;
  }

  // The DAG audits (grammar.auditGates): three defects that leave a document parsing, validating and
  // answering perfectly while silently withholding questions from the owner. They are the ones that
  // have actually cost rounds, and none of them shows up in any other check.
  const audit = auditGates(parsed.questions, parsed.sections);

  return {
    parsed,
    graph,
    graphError,
    audit,
    lines: [
      `questions   ${live.length} live, ${parsed.questions.length - live.length} retired`,
      `gates       ${live.filter((q) => q.isGate).length} ⚑gate, ${live.filter((q) => q.isContract).length} ⚑contract, ${live.filter((q) => q.notes).length} marked notes`,
      `at the top  ${reachable.length} askable now, ${pending.length} waiting on a gate`,
      `opens at    ${nextQuestion(live, {}, parsed.sections)?.id ?? '(nothing)'}`,
      `longest     ${longestPath(live)} questions on one path`,
      `charts      ${graph ? `${graph.charts.length} ingested, ${Object.keys(graph.nodes).length} nodes, ${graph.edges.length} edges` : 'FAILED — see below'}`,
      `links       ${graph ? `${graph.links.length} derived, ${graph.warnings.length} unresolved` : '—'}`,
      `errors      ${parsed.errors.length}`,
      `warnings    ${parsed.warnings.length}`,
      `dag audit   ${audit.length} — defects that prune questions SILENTLY (listed below)`,
      `skipped     ${parsed.ignored.length} bullet(s) that name a question ID but are not questions`,
    ],
  };
}

/** One line of a long note, for a report that must stay scannable. */
function clip(text, max = 120) {
  const one = String(text ?? '').replace(/\s+/g, ' ').trim();
  return one.length <= max ? one : `${one.slice(0, max - 1)}…`;
}

async function main() {
  const target = process.argv.slice(2).filter((a) => a !== '--' && a !== 'charts')[0];
  if (!target) {
    process.stdout.write('usage: npm --prefix designloop run check -- <project>/<slug> | <path to DESIGN.md>\n');
    process.exit(2);
  }
  let path = resolve(REPO_ROOT, target);
  if (!target.endsWith('.md')) {
    const design = await find(REPO_ROOT, target);
    if (!design) {
      process.stdout.write(`no design at "${target}"\n`);
      process.exit(1);
    }
    path = design.docPath;
  }
  const markdown = await readFile(path, 'utf8');
  const { parsed, graph, graphError, audit, lines } = describe(markdown, target);
  process.stdout.write(`\n${path}\n${lines.map((l) => `  ${l}`).join('\n')}\n`);
  for (const e of parsed.errors) process.stdout.write(`  ERROR   line ${e.line ?? '?'}: ${e.message}\n`);
  for (const w of parsed.warnings) process.stdout.write(`  warning line ${w.line ?? '?'}: ${w.message}\n`);
  // ⚠ These do not block. Each has a legitimate shape too, so the judgement is the author's — but
  // being TOLD is not optional: every one of them is invisible from the owner's side of the screen.
  for (const a of audit) process.stdout.write(`  DAG     line ${a.line ?? '?'}: ${a.message}\n`);
  if (graphError) process.stdout.write(`  CHART   ${graphError.message}\n`);
  // §6.1: a label naming a chart that does not exist is the author's defect and only the author can
  // fix it, so it is named here and never blocks (GAP-001's rule, applied to links).
  for (const w of graph?.warnings ?? []) process.stdout.write(`  link    ${w.message}\n`);
  const graphErrors = graph ? validateGraph(graph) : [];
  for (const e of graphErrors) process.stdout.write(`  CHART   ${e.message}\n`);

  // STALE CHARTS — the fourth silent defect, and the only one that needs the ANSWERS to see.
  //
  // ⚠ A chart node that still poses an ANSWERED question as an open fork is a lie to the reviewer,
  // and it is invisible from every other angle: the document parses, the DAG is sound, the round
  // reports complete, and the canvas cheerfully draws "do they glow? Q141" long after Q141 was
  // answered. Measured on solatro/spotlight 2026-08-03: **20 nodes across 11 charts** had gone stale
  // over four rounds, including a whole chart still offering three models one of which had already
  // been chosen. The owner found them by eye — which is exactly the review attention this tool
  // exists to protect.
  //
  // ⚠ THE SHAPE IS "THE ID IS THE LAST THING SAID", and narrowing it to that is what makes this
  // usable. A node that CITES an answered question mid-sentence is almost always explaining the
  // decision — `"Q207 — between 2 and 4, and it is a KNOB"` states an answer, it does not ask one —
  // and reporting those buried the three real hits under false positives on the first run. A node
  // that *poses* a question ends on the ID: `"do they glow? Q141"`, `"— see Q109"`, `"— Q246"}`.
  // That is the whole tell, and it is how every one of the twenty stale nodes actually read.
  if (graph && !target.endsWith('.md')) {
    const design = await find(REPO_ROOT, target);
    const answers = design ? (await readJson(join(design.dir, 'answers.json')))?.answers : null;
    if (answers) {
      // trailing ID (optionally after a dash), a `see Qnnn`, or `Qnnn?`
      const OPEN = /(?:see\s+(QR?\d+)\b)|(?:[—-]?\s*(QR?\d+)\s*$)|(?:(QR?\d+)\s*\?)/g;
      const stale = [];
      for (const [nodeId, node] of Object.entries(graph.nodes)) {
        const label = String(node.label || '').trim();
        for (const m of label.matchAll(OPEN)) {
          const q = m[1] || m[2] || m[3];
          const a = q && answers[q];
          if (!a || a.active === false) continue;
          if (new RegExp(`${q}\\s*=`).test(label)) continue;
          stale.push(`${nodeId} poses ${q} as an open fork — it is answered (${a.option || 'free text'})`);
        }
      }
      process.stdout.write(`  stale       ${stale.length} chart node(s) posing an ANSWERED question as open\n`);
      for (const line of stale) process.stdout.write(`  STALE   ${line}\n`);
    }

    // THE PLAN'S OWN TRACEABILITY, once a PLAN.md exists.
    //
    // ⚠ The gap protocol's whole blast-radius mechanism is `(implements …)`: a step that cites
    // nothing can never be reported stale when the design node it was built on changes, and a step
    // citing an ID that does not exist is a citation nobody will ever match. Both were checked by
    // hand on Spotlight with a throwaway script — which is exactly the kind of check that gets run
    // once and then never again. It runs here now.
    const steps = design ? await readPlanSteps(design.dir) : [];
    if (steps.length) {
      const known = new Set([
        ...Object.keys(graph.nodes),
        ...parsed.questions.map((q) => q.id),
      ]);
      const unknown = [];
      const uncited = [];
      for (const step of steps) {
        const bad = step.cites.filter((c) => !known.has(c));
        if (bad.length) unknown.push(`${step.id} cites ${bad.join(', ')} — no such design node or question`);
        if (!step.cites.length) uncited.push(`${step.id} cites nothing — it can never be reported stale`);
      }
      process.stdout.write(
        `  plan        ${steps.length} step(s), ${unknown.length} bad citation(s), ${uncited.length} uncited\n`,
      );
      for (const line of [...unknown, ...uncited]) process.stdout.write(`  PLAN    ${line}\n`);
    }

    // PROVENANCE — the distance between an ANSWER and what the documents say it was.
    //
    // ⚠ These cost a round of the owner's time on Spotlight, and nothing above can see them: the
    // document parses, the DAG is sound, every citation resolves, the round reports complete — and
    // two normative documents quietly disagree about one answer because both paraphrased it. The
    // incident is written up at the head of src/provenance.mjs.
    const planText = design
      ? await readFile(join(design.dir, 'PLAN.md'), 'utf8').catch(() => '')
      : '';
    const docs = [{ name: design?.doc || 'DESIGN.md', text: markdown }];
    if (planText) docs.push({ name: 'PLAN.md', text: planText });

    if (answers) {
      // 1. ANSWERED IN PROSE. Not a defect in itself — it is how the owner corrects a premise, and
      // it is where the best answers come from. The defect is leaving it there, with no letter for
      // a gate to read and no option for a document to cite.
      const soft = softAnswers(answers, parsed.questions);
      const open = soft.filter((s) => !s.promoted);
      process.stdout.write(
        `  in prose    ${soft.length} answered with no option (${open.length} not promoted to one)\n`,
      );
      for (const s of open) {
        const flag = s.provisional ? 'PROVISIONAL, reads as thinking aloud' : 'no option carries it';
        process.stdout.write(`  PROSE   ${s.id}: ${flag} — "${clip(s.note)}"\n`);
      }

      // 2. A document RELIES on a free-text answer and quotes none of it.
      const unquoted = quoteAudit(answers, parsed.questions, docs);
      process.stdout.write(`  unquoted    ${unquoted.length} document(s) paraphrasing a free-text answer\n`);
      for (const u of unquoted) {
        const where = `${u.lines.slice(0, 6).join(', ')}${u.lines.length > 6 ? ', …' : ''}`;
        process.stdout.write(
          `  QUOTE   ${u.id} is relied on in ${u.doc} (line${u.lines.length > 1 ? 's' : ''} ${where})`
          + ` but none of the owner's words appear there — paste the note, do not summarise it\n`,
        );
      }
    }

    // 3. CONTRACTS. A normative block in PLAN §1 that no ⚑contract question authorises is a
    // contract the executor will follow and the owner never saw.
    if (planText) {
      const contracts = contractAudit(parsed.questions, planText);
      process.stdout.write(
        `  contracts   ${contracts.blocks.length} normative block(s) in PLAN §1, `
        + `${contracts.unauthorised.length} unauthorised, ${contracts.uncontracted.length} uncontracted\n`,
      );
      for (const b of contracts.unauthorised) {
        process.stdout.write(
          `  CONTRACT PLAN.md:${b.line} (${clip(b.heading, 60)}) cites `
          + `${b.cites.length ? b.cites.join(', ') : 'no question'}, none ⚑contract`
          + ` — is this contract an ANSWER, or an invention?\n`,
        );
      }
      for (const id of contracts.uncontracted) {
        process.stdout.write(`  CONTRACT ${id} is ⚑contract but no PLAN §1 block cites it\n`);
      }
    }

    // `answer Q16` — the RESTATEMENT INDEX. Every place one answer is spoken for, side by side,
    // so a divergence is one screen instead of three greps. This is the report that would have
    // ended GAP-002 before it was filed.
    const wanted = process.argv.slice(2).find((a) => /^QR?\d+[a-z]?$/.test(a));
    if (wanted && answers) {
      const a = answers[wanted];
      process.stdout.write(`\n  ${wanted} — ${a ? (a.option ? `(${a.option})` : 'free text, no option') : 'UNANSWERED'}\n`);
      if (a?.note) process.stdout.write(`  note    ${a.note}\n`);
      for (const r of restatementsOf(wanted, docs)) {
        process.stdout.write(`  ${r.doc}:${r.line}  ${clip(r.text, 150)}\n`);
      }
    }
  }
  // A bare word, not a flag: `npm run check -- <design> charts`. npm eats unknown `--flags` before
  // the script ever sees them and then exits non-zero, which looks like a failure that never was.
  if (graph && process.argv.slice(2).includes('charts')) {
    process.stdout.write(`${describeGraph(graph).map((l) => `  ${l}`).join('\n')}\n`);
  }
  process.stdout.write('\n');
  process.exit(parsed.errors.length || graphError || graphErrors.length ? 1 : 0);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
