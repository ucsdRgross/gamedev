// PLAN S14 / §4.7 — Confirm freezes a version, a second Confirm leaves the first alone, the diff
// names exactly what changed, and the generated DESIGN.md re-ingests to the graph it was made from.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseCharts } from '../src/graph.mjs';
import { parseDocument } from '../src/grammar.mjs';
import { layout } from '../src/layout.mjs';
import { freeze, listVersions, readVersion, diffGraphs, renderChart, renderDesignMarkdown } from '../src/versions.mjs';

const DOC = `# Demo

## 2. Flowchart A — the loop

\`\`\`mermaid
flowchart TD
  A1["start the act"] --> A2{"any line left?"}
  A2 -- yes --> A3["NEW: score it"]
  A3 --> A2
  A2 -- no --> A4["stop"]
\`\`\`

- **A3** is what **Q1** decides.

## 3 questions

- **Q1** \`[root]\` — Score how? · **(a)** all at once — one sweep · **(b)** one at a time · *default* (a)
- **Q2** \`[root]\` — Multi-user? · **(a)** out of scope · **(b)** in scope · *default* (a)
`;

const DESIGN = { slug: 'demo', title: 'A demo design', dir: null };

/** Everything `freeze` needs, built the way the server builds it. */
function payload(dir, graph, { answers = {}, annotations = {} } = {}) {
  const parsed = parseDocument(DOC);
  const laid = layout(graph);
  return {
    design: { ...DESIGN, dir },
    graph,
    questions: parsed.questions,
    answers: { slug: 'demo', doc_hash: 'sha256:x', updated: '2026-08-01T00:00:00Z', answers },
    annotations: { nodes: {}, edges: {}, approved: {}, flagged: {}, ...annotations },
    layout: {
      engine: laid.engine, positions: laid.positions, collapsed: ['A'], viewport: { x: 10, y: 20, zoom: 0.75 },
    },
    assumptions: [{ source: 'defaulted', id: 'Q1', text: 'Score how? — took (a) all at once', why: 'accepted with Enter, unread' }],
    outOfScope: [{ id: 'Q2', text: 'Multi-user?', answer: 'out of scope' }],
    gaps: [{ id: 'GAP-001', title: 'a gate with no preview', status: 'resolved' }],
  };
}

test('Confirm freezes every file §4.7 lists, plus the transcript Q72 asks for', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'designloop-v-'));
  try {
    const graph = parseCharts(DOC, { file: 'DESIGN.md' });
    const { version, path } = await freeze(dir, payload(dir, graph, {
      answers: { Q1: { state: 'defaulted', option: 'a', note: '', override: false, active: true, round: 1 } },
    }));
    assert.equal(version, 1);
    const files = (await readdir(path)).sort();
    assert.deepEqual(files, ['DESIGN.md', 'annotations.json', 'answers.json', 'changelog.md', 'graph.json', 'layout.json', 'transcript.md']);

    const frozen = await readVersion(dir, 1);
    assert.equal(frozen.layout.engine, 'layered-v1');
    assert.deepEqual(frozen.layout.collapsed, ['A'], 'the collapse state is frozen (Q115=b)');
    assert.deepEqual(frozen.layout.viewport, { x: 10, y: 20, zoom: 0.75 }, 'and so is the viewport');
    assert.ok(frozen.layout.positions.A1, 'and every position');

    const rendered = await readFile(join(path, 'DESIGN.md'), 'utf8');
    assert.match(rendered, /Never hand-edit it/);
    assert.match(rendered, /\| Q1 \| \(a\) all at once/, 'the decisions are in it');
    assert.match(rendered, /Multi-user\?/, 'and the out-of-scope list');
    assert.match(rendered, /defaulted/, 'and the assumptions, labelled by source');

    const transcript = await readFile(join(path, 'transcript.md'), 'utf8');
    assert.match(transcript, /### Q1 — Score how\?/);
    assert.match(transcript, /recorded as `defaulted`/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('a second Confirm makes version 2 and does not touch version 1', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'designloop-v-'));
  try {
    const graph = parseCharts(DOC, { file: 'DESIGN.md' });
    await freeze(dir, payload(dir, graph));
    const before = await readFile(join(dir, 'versions', '001', 'graph.json'), 'utf8');

    const changed = parseCharts(DOC.replace('"stop"', '"stop, and tidy up"').replace('  A2 -- no --> A4', '  A2 -- no --> A5["NEW: a new step"]\n  A5 --> A4'), { file: 'DESIGN.md' });
    const second = await freeze(dir, payload(dir, changed));
    assert.equal(second.version, 2);
    assert.equal(await readFile(join(dir, 'versions', '001', 'graph.json'), 'utf8'), before, 'version 1 is immutable');

    const list = await listVersions(dir);
    assert.deepEqual(list.map((v) => v.n), [1, 2]);
    assert.deepEqual(list[1].collapsed, ['A']);

    const changelog = await readFile(join(dir, 'versions', '002', 'changelog.md'), 'utf8');
    assert.match(changelog, /Against version 1/);
    assert.match(changelog, /\*\*A5\*\*/, 'the changelog names the added node');
    assert.match(changelog, /GAP-001/, 'and the gaps closed since');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('the diff is node-level: added, changed, removed (Q62=a)', () => {
  const before = parseCharts(DOC, { file: 'x' });
  const after = parseCharts(DOC.replace('"stop"', '"halt"').replace('  A3 --> A2\n', '  A3 --> A2\n  A3 --> A9["a new one"]\n'), { file: 'x' });
  const diff = diffGraphs(before, after);
  assert.deepEqual(diff.added.map((n) => n.id), ['A9']);
  assert.deepEqual(diff.removed, []);
  assert.deepEqual(diff.changed.find((c) => c.id === 'A4')?.fields, ['label']);
  assert.deepEqual(diff.changed.find((c) => c.id === 'A3')?.fields, ['edges'], 'a new edge changes the node it leaves');
});

test('the generated markdown round-trips: re-ingesting it reproduces the same graph', () => {
  const graph = parseCharts(DOC, { file: 'DESIGN.md' });
  const again = parseCharts(renderChart(graph, graph.charts[0]), { file: 'generated' });
  assert.deepEqual(Object.keys(again.nodes), Object.keys(graph.nodes));
  for (const id of Object.keys(graph.nodes)) {
    assert.equal(again.nodes[id].label, graph.nodes[id].label);
    assert.equal(again.nodes[id].shape, graph.nodes[id].shape);
  }
  assert.deepEqual(again.edges.map((e) => `${e.from}-${e.label}->${e.to}`),
    graph.edges.map((e) => `${e.from}-${e.label}->${e.to}`));
});

test('the whole Spotlight design round-trips through the render (24 charts, not a toy)', async () => {
  const { readFileSync } = await import('node:fs');
  const { fileURLToPath } = await import('node:url');
  const { dirname, resolve } = await import('node:path');
  const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const graph = parseCharts(readFileSync(resolve(repo, 'solatro/design/spotlight/DESIGN.md'), 'utf8'), { file: 'S.md' });
  const markdown = renderDesignMarkdown({
    design: DESIGN, version: 1, graph, questions: [], answers: { answers: {} },
    annotations: { nodes: {} }, assumptions: [], outOfScope: [],
  });
  const again = parseCharts(markdown, { file: 'generated' });
  assert.equal(again.charts.length, graph.charts.length);
  assert.equal(Object.keys(again.nodes).length, Object.keys(graph.nodes).length);
  assert.equal(again.edges.length, graph.edges.length);
});
