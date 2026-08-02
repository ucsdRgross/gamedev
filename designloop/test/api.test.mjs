// PLAN S3 + S5–S8 — the JSON API of §4.8, driven end to end over HTTP against a throwaway design.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ROOT = await mkdtemp(join(tmpdir(), 'designloop-repo-'));
process.env.DESIGNLOOP_ROOT = ROOT;
const { createDevServer, listenFrom } = await import('../src/server.mjs');
const { readJson } = await import('../src/store.mjs');

const DIR = join(ROOT, 'demoproject', 'design', 'demo');

/** A four-question design: one ⚑gate, one section gated on it, one plain question — and a chart. */
const DOC = `# Demo

## 0. Flowchart A — the demo loop

\`\`\`mermaid
flowchart TD
  A1["open the design"] --> A2{"any question left?"}
  A2 -- yes --> A3["NEW: answer it"]
  A3 --> A2
  A2 -- no --> A4["hand back to the agent"]
\`\`\`

- **A3** is what **Q2** decides.

## 1 roots

- **QR1** \`[root]\` ⚑gate — Which path? · **(a)** wide — opens the detail — **→ next:** the detail questions · **(b)** narrow — skips them — **→ next:** nothing more · *default* (a)
- **Q1** \`[root]\` — A plain one · **(a)** yes · **(b)** no · *default* (a)

## 2 detail \`[QR1=a]\`

- **Q2** \`[root]\` — Detail one · **(a)** yes · **(b)** no · *default* (a)
- **Q3** \`[root]\` — Detail two · **(a)** yes · **(b)** no · *default* (a)
`;

async function fixture() {
  await rm(DIR, { recursive: true, force: true });
  await mkdir(DIR, { recursive: true });
  await writeFile(join(DIR, 'DESIGN.md'), DOC, 'utf8');
  await writeFile(join(DIR, 'meta.json'), JSON.stringify({
    slug: 'demo', title: 'A demo design', projects: ['demoproject'], doc: 'DESIGN.md',
    created: '2026-08-01T00:00:00Z', rounds: 1, confirmed_version: null,
  }, null, 2), 'utf8');
}

async function serve() {
  const server = createDevServer();
  const port = await listenFrom(server, 0);
  const url = `http://127.0.0.1:${port}`;
  return {
    url,
    get: (p) => fetch(`${url}/api/designs/demoproject/demo${p}`).then((r) => r.json()),
    post: (p, body) => fetch(`${url}/api/designs/demoproject/demo${p}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
    }).then(async (r) => ({ status: r.status, body: await r.json() })),
    close: () => new Promise((r) => { server.closeAllConnections?.(); server.close(r); }),
  };
}

test('the index lists a design under every project it touches', async () => {
  await fixture();
  const s = await serve();
  try {
    const list = await fetch(`${s.url}/api/designs`).then((r) => r.json());
    const demo = list.find((d) => d.key === 'demoproject/demo');
    assert.ok(demo, 'the scan finds <project>/design/<slug>/meta.json');
    assert.equal(demo.title, 'A demo design');
    assert.equal(demo.owner.state, 'answering');
    assert.equal(demo.agent.state, 'idle');
    assert.equal(demo.answered, 0);
    assert.ok(demo.touched, 'last touched is reported');
  } finally {
    await s.close();
  }
});

test('a round runs to the end and hands the turn to the agent', async () => {
  await fixture();
  const s = await serve();
  try {
    assert.equal((await s.get('/next')).question.id, 'QR1', 'roots come first');

    let r = await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'a' });
    assert.equal(r.status, 200);
    assert.equal(r.body.owner.state, 'answering');
    assert.equal(r.body.next.id, 'Q2', 'the gated section is heavier than the ungated one (§5.5)');

    await s.post('/answer', { id: 'Q2', state: 'defaulted', option: 'a' });
    await s.post('/answer', { id: 'Q3', state: 'not_relevant', option: 'a' });
    r = await s.post('/answer', { id: 'Q1', state: 'chosen', option: 'b' });
    assert.equal(r.body.done, true);
    assert.equal(r.body.owner.state, 'done');
    assert.equal(r.body.owner.reason, 'complete');

    const next = await s.get('/next');
    assert.equal(next.done, true);
    assert.deepEqual((await readJson(join(DIR, 'status.owner.json'))).reason, 'complete');
  } finally {
    await s.close();
  }
});

test('answering the gate the other way prunes the section entirely', async () => {
  await fixture();
  const s = await serve();
  try {
    const r = await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'b' });
    assert.equal(r.body.next.id, 'Q1', 'Q2 and Q3 are gone, not merely later');
    await s.post('/answer', { id: 'Q1', state: 'chosen', option: 'a' });
    assert.equal((await s.get('/next')).done, true);
  } finally {
    await s.close();
  }
});

test('re-answering previews its blast radius before applying, then strands and restores', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'a' });
    await s.post('/answer', { id: 'Q2', state: 'chosen', option: 'a', note: 'typed by hand' });
    await s.post('/answer', { id: 'Q3', state: 'chosen', option: 'b' });

    const preview = await s.post('/reanswer?preview=1', { id: 'QR1', state: 'chosen', option: 'b' });
    assert.deepEqual(preview.body.strand.map((x) => x.id), ['Q2', 'Q3']);
    assert.equal(preview.body.preview, true);
    assert.equal((await readJson(join(DIR, 'answers.json'))).answers.Q2.active, true, 'a preview writes nothing');

    const applied = await s.post('/reanswer', { id: 'QR1', state: 'chosen', option: 'b' });
    assert.deepEqual(applied.body.strand, ['Q2', 'Q3']);
    let saved = (await readJson(join(DIR, 'answers.json'))).answers;
    assert.equal(saved.Q2.active, false);
    assert.equal(saved.Q2.note, 'typed by hand', 'kept, not deleted (Q35)');

    const back = await s.post('/reanswer', { id: 'QR1', state: 'chosen', option: 'a' });
    assert.deepEqual(back.body.restore, ['Q2', 'Q3']);
    saved = (await readJson(join(DIR, 'answers.json'))).answers;
    assert.equal(saved.Q2.active, true);
    assert.equal(saved.Q2.note, 'typed by hand');
    assert.equal(saved.Q3.option, 'b', 'and it comes back as the answer it was');
  } finally {
    await s.close();
  }
});

test('free text at a ⚑gate ends the round immediately (chart B2)', async () => {
  await fixture();
  const s = await serve();
  try {
    const r = await s.post('/answer', {
      id: 'QR1', state: 'chosen', override: true, note: 'neither — I want a third thing',
    });
    assert.equal(r.body.owner.state, 'done');
    assert.equal(r.body.owner.reason, 'new_branch_needed');
    // The asymmetry that matters: reachable questions remain, and the round has ended anyway.
    assert.equal((await s.get('/next')).done, false, 'questions remain — the UI stops on the status');
    const saved = (await readJson(join(DIR, 'answers.json'))).answers.QR1;
    assert.equal(saved.override, true);
    assert.equal(saved.option, null);
    assert.equal(saved.note, 'neither — I want a third thing');
  } finally {
    await s.close();
  }
});

test('free text on an ORDINARY question is an override that keeps the round going', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'a' });
    const r = await s.post('/answer', { id: 'Q2', state: 'chosen', override: true, note: 'something else' });
    assert.equal(r.body.owner.state, 'answering');
    assert.equal(r.body.next.id, 'Q3');
  } finally {
    await s.close();
  }
});

test('the round-2 handshake: agent ready, then the UI takes the turn back', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'b' });
    await s.post('/answer', { id: 'Q1', state: 'chosen', option: 'a' });
    assert.equal((await s.get('')).owner.state, 'done');

    // The agent half — written by the agent, never by the UI.
    await writeFile(join(DIR, 'status.agent.json'), JSON.stringify({
      state: 'ready', mode: 'questions', round: 2, at: '2026-08-01T00:00:00Z',
      summary: 'Your answer to QR1 opened these',
    }, null, 2), 'utf8');

    const seen = await s.get('');
    assert.equal(seen.agent.state, 'ready');
    assert.equal(seen.agent.summary, 'Your answer to QR1 opened these');

    const resumed = await s.post('/resume');
    assert.equal(resumed.body.owner.state, 'answering');
    assert.equal(resumed.body.owner.round, 2);
    assert.equal(resumed.body.owner.reason, null);
  } finally {
    await s.close();
  }
});

test('history is in answer order and says what each answer was', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'a' });
    await s.post('/answer', { id: 'Q2', state: 'defaulted', option: 'a' });
    const history = await s.get('/history');
    assert.deepEqual(history.map((h) => h.id), ['QR1', 'Q2']);
    assert.equal(history[0].isGate, true);
    assert.equal(history[0].label, 'wide');
    assert.equal(history[1].state, 'defaulted');
  } finally {
    await s.close();
  }
});

test('a bad answer is refused, and nothing is written', async () => {
  await fixture();
  const s = await serve();
  try {
    assert.equal((await s.post('/answer', { id: 'Q99', option: 'a' })).status, 400);
    assert.equal((await s.post('/answer', { id: 'QR1', option: 'z' })).status, 400);
    assert.equal(await readJson(join(DIR, 'answers.json')), null, 'nothing on disk');
  } finally {
    await s.close();
  }
});

test('the browser can fetch the document it parses with the shared module', async () => {
  await fixture();
  const s = await serve();
  try {
    const text = await fetch(`${s.url}/api/designs/demoproject/demo/doc`).then((r) => r.text());
    assert.equal(text, DOC);
  } finally {
    await s.close();
  }
});

// --- the canvas half (PLAN S11–S14, §4.8) --------------------------------------------------------

test('GET /graph ingests the document and writes graph.json beside it', async () => {
  await fixture();
  const s = await serve();
  try {
    const graph = await s.get('/graph');
    assert.deepEqual(graph.charts.map((c) => c.id), ['A']);
    assert.equal(graph.charts[0].title, 'the demo loop');
    assert.equal(graph.nodes.A3.new, true, 'the NEW: marker survives');
    assert.deepEqual(graph.nodes.A3.decidedBy, ['Q2'], 'and the prose after the chart maps it to a question');
    assert.equal(graph.nodes.A2.shape, 'decision');
    assert.deepEqual(graph.errors, []);

    const onDisk = await readJson(join(DIR, 'graph.json'));
    assert.equal(onDisk.doc_hash, graph.doc_hash, 'the generated artefact is really on disk (§4.6)');
  } finally {
    await s.close();
  }
});

test('a chart outside the §6 subset fails loudly, naming the file and the line', async () => {
  await fixture();
  await writeFile(join(DIR, 'DESIGN.md'), DOC.replace('A3 --> A2', 'A3 -.-> A2'), 'utf8');
  const s = await serve();
  try {
    const res = await fetch(`${s.url}/api/designs/demoproject/demo/graph`);
    assert.equal(res.status, 422);
    const body = await res.json();
    assert.match(body.error, /DESIGN\.md:9/);
    assert.match(body.error, /outside the subset/);
  } finally {
    await s.close();
  }
});

test('annotations and flags round-trip through /annotate and /approve (§4.5, Q56, Q59)', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/annotate', { target: 'node', key: 'A3', text: 'split this into two steps' });
    await s.post('/annotate', { target: 'edge', key: 'A2->A3', text: 'this should be conditional' });
    await s.post('/approve', { target: 'node', key: 'A4', state: 'flagged' });

    const review = await s.get('/review');
    assert.equal(review.annotations.nodes.A3[0].text, 'split this into two steps');
    assert.equal(review.annotations.edges['A2->A3'][0].text, 'this should be conditional');
    assert.ok(review.annotations.flagged.A4, 'unflagged is "not objected to"; flagged is the mark');

    await s.post('/approve', { target: 'node', key: 'A4', state: null });
    assert.equal((await s.get('/review')).annotations.flagged.A4, undefined, 'and a flag can be cleared');
  } finally {
    await s.close();
  }
});

test('/review lists assumptions from all three sources and derives what is out of scope', async () => {
  await fixture();
  await writeFile(join(DIR, 'ASSUMPTIONS.md'), [
    '| Date | Step | Assumption | Why |', '|---|---|---|---|',
    '| 2026-08-01 | S1 | the port is 5273 | one constant |',
  ].join('\n'), 'utf8');
  await writeFile(join(DIR, 'DESIGN.md'), `${DOC}\n## 9 out of scope\n\n`
    + '- **Q9** `[root]` — Multi-user? · **(a)** out of scope · **(b)** in scope · *default* (a)\n', 'utf8');
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'a' });
    await s.post('/answer', { id: 'Q2', state: 'defaulted', option: 'a' });
    await s.post('/answer', { id: 'Q3', state: 'not_relevant', option: 'a' });
    await s.post('/answer', { id: 'Q9', state: 'chosen', option: 'a' });

    const review = await s.get('/review');
    const sources = review.assumptions.map((a) => a.source);
    assert.ok(sources.includes('agent'), 'what the agent declared');
    assert.ok(sources.includes('defaulted'), 'what was Enter-defaulted');
    assert.ok(sources.includes('not_relevant'), 'and what was waved through (Q116=a)');
    assert.equal(review.assumptions.find((a) => a.source === 'agent').text, 'the port is 5273');
    assert.deepEqual(review.out_of_scope.map((o) => o.id), ['Q9']);
  } finally {
    await s.close();
  }
});

test('Confirm freezes a version with the layout on screen, and the next Confirm diffs against it', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'b' });
    await s.post('/annotate', { target: 'node', key: 'A1', text: 'looks right' });

    const bare = await s.post('/confirm', {});
    assert.equal(bare.status, 400, 'Confirm without a layout is refused — Q115=b needs it');

    const layoutJson = {
      engine: 'layered-v1',
      positions: { A1: { x: 0, y: 0 }, A2: { x: 0, y: 100 }, A3: { x: 0, y: 200 }, A4: { x: 0, y: 300 } },
      collapsed: ['A'],
      viewport: { x: 12, y: 34, zoom: 0.5 },
    };
    const first = await s.post('/confirm', { layout: layoutJson });
    assert.equal(first.status, 200);
    assert.equal(first.body.version, 1);
    assert.equal((await readJson(join(DIR, 'meta.json'))).confirmed_version, 1);

    const frozen = await s.get('/versions/1');
    assert.deepEqual(frozen.layout.collapsed, ['A']);
    assert.deepEqual(frozen.layout.viewport, { x: 12, y: 34, zoom: 0.5 });
    assert.equal(frozen.annotations.nodes.A1[0].text, 'looks right');
    assert.equal(frozen.answers.answers.QR1.option, 'b');

    // The document changes, and the second version says exactly what moved.
    await writeFile(join(DIR, 'DESIGN.md'), DOC.replace('"hand back to the agent"', '"hand back, with a summary"'), 'utf8');
    const second = await s.post('/confirm', { layout: layoutJson });
    assert.equal(second.body.version, 2);
    const diff = await s.get('/diff?a=1&b=2');
    assert.deepEqual(diff.added, []);
    assert.deepEqual(diff.removed, []);
    assert.deepEqual(diff.changed.map((c) => [c.id, c.fields]), [['A4', ['label']]]);

    const list = await s.get('/versions');
    assert.deepEqual(list.versions.map((v) => v.n), [1, 2]);
    assert.equal(list.confirmed, 2, 'meta.json now points at the newest frozen version');
  } finally {
    await s.close();
  }
});

test('Review again hands the turn back with the annotations on it (F10)', async () => {
  await fixture();
  const s = await serve();
  try {
    const r = await s.post('/review', {});
    assert.equal(r.body.owner.state, 'done');
    assert.equal(r.body.owner.reason, 'review_again');
  } finally {
    await s.close();
  }
});

test('the index card carries the parse warnings, so an under-specified gate is visible (GAP-001=b)', async () => {
  await fixture();
  await writeFile(join(DIR, 'DESIGN.md'),
    DOC.replace(' — **→ next:** nothing more', ''), 'utf8');
  const s = await serve();
  try {
    const list = await fetch(`${s.url}/api/designs`).then((r) => r.json());
    const demo = list.find((d) => d.key === 'demoproject/demo');
    assert.equal(demo.errors, 0, 'it still parses — the owner is not blocked');
    assert.equal(demo.warnings, 1, 'and the badge names the shortfall for whoever can fix it');
  } finally {
    await s.close();
  }
});

// --- S15, the gap surface -----------------------------------------------------------------------

/** A gap filed by hand, in the SKILL.md template, exactly as an executing agent would write it. */
const GAP = `# GAP-009 — the empty case at A2 is not covered
status: open
raised: 2026-08-02, during execution plan step S4
severity: GAP

**What the design says** — A2 asks whether a question is left.

**What it does not say** — what A2 does when there was never a question at all.

**Why it blocks** — two defensible choices differ in what the owner sees.

**Options I can see** — **(a)** show the DONE screen — an empty design is a finished one ·
**(b)** say the design is empty — it is a different thing from finished ·
*my recommendation* (b)

**Blast radius** — plan steps S4; design nodes A2

**Meanwhile** — parked the empty-design thread; everything else continued.
`;

const PLAN = `# PLAN
**S4 — the store.** *(implements A2, B12)*
**S12 — canvas render.** *(implements F2)*
`;

test('a hand-written gap is a badge, a scoped round, and a stale plan step (S15)', async () => {
  await fixture();
  await mkdir(join(DIR, 'gaps'), { recursive: true });
  await writeFile(join(DIR, 'gaps', 'GAP-009.md'), GAP, 'utf8');
  await writeFile(join(DIR, 'PLAN.md'), PLAN, 'utf8');
  const s = await serve();
  try {
    // Q89b=c — the badge. The index says a gap exists without being asked.
    const card = (await fetch(`${s.url}/api/designs`).then((r) => r.json()))
      .find((d) => d.key === 'demoproject/demo');
    assert.equal(card.gaps, 1);
    assert.equal(card.gaps_closed, 0);
    assert.equal(card.gaps_total, 1);

    // J16 — the plan step that cites A2 is stale; the one that does not is untouched.
    const gaps = await s.get('/gaps');
    assert.deepEqual(gaps.counts, { open: 1, closed: 0, total: 1 });
    assert.deepEqual(gaps.stale.map((x) => [x.id, x.gap, x.because]), [['S4', 'GAP-009', ['A2']]]);
    assert.equal(gaps.steps, 2, 'both steps were read; only one of them is stale');
    assert.equal(gaps.gaps[0].question.options.length, 2);
    assert.equal(gaps.gaps[0].question.default, 'b');

    // Q90b=b / J12 — the scoped round: this gap, and NOT the questionnaire.
    const next = await s.get('/next?scope=gaps');
    assert.equal(next.question.id, 'GAP-009');
    assert.equal(next.question.gap, 'GAP-009');
    assert.ok(next.question.context.some((c) => c.label === 'Why it blocks'), 'the report comes with it');
    assert.equal((await s.get('/next')).question.id, 'QR1', 'the main round is untouched (Q88b=a)');

    // Answering it goes down the same durable path as any other answer (§4.4)…
    const r = await s.post('/answer', { id: 'GAP-009', state: 'chosen', option: 'a', note: 'the empty design is finished' });
    assert.equal(r.status, 200);
    assert.equal(r.body.done, true, 'that was the only open gap');
    // …and the scoped round's ending is what wakes the agent to write design version N+1 (J15).
    assert.equal(r.body.owner.state, 'done');
    assert.equal(r.body.owner.reason, 'gaps_answered');

    const stored = (await readJson(join(DIR, 'answers.json'))).answers['GAP-009'];
    assert.equal(stored.option, 'a');
    assert.equal(stored.note, 'the empty design is finished');
    assert.ok((await s.get('/history')).some((h) => h.id === 'GAP-009'), 'and it is in the history');

    // The gap file itself is never rewritten — a gap is closed by a new design version, not by an
    // answer landing on it.
    assert.equal(await readFile(join(DIR, 'gaps', 'GAP-009.md'), 'utf8'), GAP);
    assert.equal((await s.get('/gaps')).gaps[0].answer.option, 'a');
  } finally {
    await s.close();
  }
});

test('promoting an assumption from the canvas files an open gap (Q95b=a)', async () => {
  await fixture();
  await writeFile(join(DIR, 'PLAN.md'), PLAN, 'utf8');
  const s = await serve();
  try {
    assert.equal((await s.get('/gaps')).counts.total, 0);
    const r = await s.post('/promote', {
      assumption: 'the empty case shows the DONE screen', step: 'S4 / §4.3', nodes: ['A2'],
    });
    assert.equal(r.status, 200);
    assert.equal(r.body.id, 'GAP-001');

    const gaps = await s.get('/gaps');
    assert.deepEqual(gaps.counts, { open: 1, closed: 0, total: 1 });
    assert.equal(gaps.gaps[0].question, null, 'no options: the owner asked for a say, not for one');
    assert.deepEqual(gaps.stale.map((x) => x.id), ['S4'], 'and the step that relied on it is stale');
    assert.equal((await s.post('/promote', {})).status, 400, 'a promotion must name its assumption');
  } finally {
    await s.close();
  }
});

test.after(async () => {
  await rm(ROOT, { recursive: true, force: true });
});
