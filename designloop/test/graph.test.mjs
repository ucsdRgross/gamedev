// PLAN S11 / §6 — the mermaid subset, one case per construct, one case per refusal, plus THE
// acceptance gate: every chart in both real design documents ingesting with zero unknown
// constructs. §6 says it in one line — "if the subset cannot express them, the subset is wrong".

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { parseCharts, validate, GraphError } from '../src/graph.mjs';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Wrap chart lines in a fenced mermaid block, which is the only place a chart is ever read from. */
function chart(...lines) {
  return ['```mermaid', 'flowchart TD', ...lines.map((l) => `  ${l}`), '```'].join('\n');
}

const one = (...lines) => parseCharts(chart(...lines), { file: 'T.md' });

test('a box node and a decision node', () => {
  const g = one('A1["a box"]', 'A2{"a decision"}', 'A1 --> A2');
  assert.equal(g.nodes.A1.shape, 'box');
  assert.equal(g.nodes.A2.shape, 'decision');
  assert.equal(g.nodes.A1.label, 'a box');
});

test('a plain edge', () => {
  const g = one('A1["one"] --> A2["two"]');
  assert.deepEqual(g.edges.map((e) => [e.from, e.to, e.label]), [['A1', 'A2', '']]);
  assert.equal(g.edges[0].key, 'A1->A2');
});

test('a labelled edge, quoted and bare', () => {
  const g = one('A1["one"] -- "no cards above" --> A2["two"]', 'A2 -- yes --> A3["three"]');
  assert.deepEqual(g.edges.map((e) => e.label), ['no cards above', 'yes']);
});

test('an inline declaration on an edge line declares both ends', () => {
  const g = one('A1["left"] --> A2["right"]');
  assert.equal(g.nodes.A2.label, 'right');
});

test('a quoted label spanning source lines joins with a single space', () => {
  const g = parseCharts([
    '```mermaid',
    'flowchart TD',
    '  A1["anything that could change activation:',
    '      board mutation / prop tick / resume"] --> A2["check()"]',
    '```',
  ].join('\n'), { file: 'T.md' });
  assert.equal(g.nodes.A1.label, 'anything that could change activation: board mutation / prop tick / resume');
});

test('first declaration wins and a later bare reference reuses it', () => {
  const g = one('A1["kept"] --> A2["x"]', 'A2 --> A1');
  assert.equal(g.nodes.A1.label, 'kept');
  assert.equal(g.edges.length, 2);
});

test('a conflicting re-declaration is an error naming the first line', () => {
  assert.throws(() => one('A1["one"] --> A2["x"]', 'A1["two"] --> A2'), (err) => {
    assert.ok(err instanceof GraphError);
    assert.match(err.message, /A1 is declared twice with different labels \(first on line 3\)/);
    assert.equal(err.file, 'T.md');
    assert.equal(err.line, 4);
    return true;
  });
});

test('an unquoted node label is refused rather than guessed at', () => {
  assert.throws(() => one('A1[plain text] --> A2["x"]'), /a node label must be quoted/);
});

test('a node shape outside the subset is refused by name', () => {
  assert.throws(() => one('A1("round") --> A2["x"]'), /expected an edge at "\("round"\)/);
  assert.throws(() => one('A1>"flag"] --> A2["x"]'), /expected an edge at ">"flag"\]/);
});

test('other arrow kinds are refused, naming the file and the line', () => {
  for (const arrow of ['-.->', '==>', '<-->', '---']) {
    assert.throws(() => one('A1["a"] --> A2["b"]', `A2 ${arrow} A1`), (err) => {
      assert.equal(err.line, 4);
      assert.match(err.message, /T\.md:4/);
      assert.match(err.message, /outside the subset|expected an edge/);
      return true;
    });
  }
});

test('subgraphs, styling and class defs are errors, not silently dropped', () => {
  for (const line of ['subgraph inner', 'classDef hot fill:#f00', 'style A1 fill:#f00', 'A1:::hot']) {
    assert.throws(() => one('A1["a"] --> A2["b"]', line), GraphError);
  }
});

test('only "flowchart TD" is accepted as a header', () => {
  const wrong = ['```mermaid', 'graph LR', '  A1["a"] --> A2["b"]', '```'].join('\n');
  assert.throws(() => parseCharts(wrong, { file: 'T.md' }), /"graph LR" is not a chart header/);
});

test('a chart mixing node prefixes is an error — one chart, one prefix', () => {
  assert.throws(() => one('A1["a"] --> B2["b"]'), /mixes node prefixes/);
});

test('two charts cannot share a prefix', () => {
  const md = `${chart('A1["a"] --> A2["b"]')}\n\n${chart('A3["c"] --> A4["d"]')}`;
  assert.throws(() => parseCharts(md, { file: 'T.md' }), /a second chart uses the "A" prefix/);
});

test('a chain of edges on one line is outside the subset', () => {
  assert.throws(() => one('A1["a"] --> A2["b"] --> A3["c"]'), /one edge per line/);
});

test('several edges between the same pair are keyed #1, #2 in source order (§4.5)', () => {
  const g = one('A1{"q"} -- "no cards above" --> A9["yes"]', 'A1 -- "none block" --> A9', 'A1 -- "blocked" --> A8["no"]');
  assert.deepEqual(g.edges.map((e) => e.key), ['A1->A9#1', 'A1->A9#2', 'A1->A8']);
});

test('the NEW: marker sets `new`', () => {
  const g = one('A1["NEW: is this card forced?"] --> A2["existing behaviour"]');
  assert.equal(g.nodes.A1.new, true);
  assert.equal(g.nodes.A2.new, false);
});

test('decidedBy comes from the label and from the prose after the chart (§4.6)', () => {
  const md = [
    chart('A1["types / stamps — see Q10"] --> A2{"which set?"}'),
    '',
    '- **A2 — what is in the set?** Whole line versus meld only.',
    '  **Q31, Q32.**',
    '- unrelated prose that names no node',
  ].join('\n');
  const g = parseCharts(md, { file: 'T.md' });
  assert.deepEqual(g.nodes.A1.decidedBy, ['Q10']);
  assert.deepEqual(g.nodes.A2.decidedBy, ['Q31', 'Q32']);
});

test('the chart title is the heading above it, without its numbering or "Flowchart X —"', () => {
  const md = ['## 6. Flowchart D — ONE LINE\'S SPOTLIGHT PHASE', '', chart('D1["a"] --> D2["b"]')].join('\n');
  assert.equal(parseCharts(md, { file: 'T.md' }).charts[0].title, "ONE LINE'S SPOTLIGHT PHASE");
});

test('validate reports what parses but is still wrong', () => {
  const g = one('A1["a"] --> A2["b"]');
  g.nodes.A3 = { chart: 'B', label: '', shape: 'box', new: false, decidedBy: [] };
  g.edges.push({ key: 'A1->A3', from: 'A1', to: 'A3', label: '', chart: 'A' });
  g.edges.push({ key: 'A1->A1', from: 'A1', to: 'A1', label: '', chart: 'A' });
  g.edges.push({ key: 'A1->A9', from: 'A1', to: 'A9', label: '', chart: 'A' });
  const messages = validate(g).map((e) => e.reason);
  assert.ok(messages.some((m) => /A3 is referenced but never given a label/.test(m)));
  assert.ok(messages.some((m) => /crosses charts/.test(m)));
  assert.ok(messages.some((m) => /points at itself/.test(m)));
  assert.ok(messages.some((m) => /which no chart declares/.test(m)));
});

// --- THE ACCEPTANCE GATE (PLAN §6, S11) ----------------------------------------------------------
//
// Every chart in both real design documents, ingested with zero unknown constructs. PLAN §6 says
// 24 charts (14 + 10); `DESIGN.md` actually holds 11 — chart B2 is a chart of its own, with its own
// P-prefixed IDs — so the corpus is 25. Neither document may be edited to make this pass.

const CORPUS = [
  { file: 'solatro/design/spotlight/DESIGN.md', charts: 14, nodes: 176, edges: 182,
    ids: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N'] },
  { file: 'designloop/design/designloop/DESIGN.md', charts: 11, nodes: 128, edges: 133,
    ids: ['A', 'B', 'P', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'I'] },
];

for (const expect of CORPUS) {
  test(`ACCEPTANCE — every chart in ${expect.file} ingests`, () => {
    const markdown = readFileSync(resolve(REPO, expect.file), 'utf8');
    const graph = parseCharts(markdown, { file: expect.file });

    assert.equal(graph.charts.length, expect.charts);
    assert.deepEqual(graph.charts.map((c) => c.id), expect.ids);
    assert.equal(Object.keys(graph.nodes).length, expect.nodes);
    assert.equal(graph.edges.length, expect.edges);
    assert.deepEqual(validate(graph), []);

    // Every chart has a title, every node has a label and belongs to its chart's ID.
    for (const c of graph.charts) {
      assert.ok(c.title.length > 0, `${c.id} has no title`);
      assert.ok(c.nodes.length > 0);
      for (const id of c.nodes) assert.equal(graph.nodes[id].chart, c.id);
    }
    for (const [id, node] of Object.entries(graph.nodes)) {
      assert.ok(node.label.length > 0, `${id} has no label`);
      assert.ok(node.shape === 'box' || node.shape === 'decision');
    }
  });
}

test('ACCEPTANCE — the ingest is a pure function of the text (a frozen version reproduces)', () => {
  const markdown = readFileSync(resolve(REPO, 'solatro/design/spotlight/DESIGN.md'), 'utf8');
  const a = parseCharts(markdown, { file: 'x' });
  const b = parseCharts(markdown, { file: 'x' });
  assert.equal(JSON.stringify(a), JSON.stringify(b));
});
