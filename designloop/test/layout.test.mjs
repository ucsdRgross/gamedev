// PLAN S12 / §4.7 — the hand-rolled layered layout: deterministic, non-overlapping, and fast
// enough at Spotlight's size that the dependency the plan would have allowed is not needed.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { parseCharts } from '../src/graph.mjs';
import { layout, edgeGeometry, linkGeometry, wrapLabel, METRICS, ENGINE } from '../src/layout.mjs';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SPOTLIGHT = parseCharts(readFileSync(resolve(REPO, 'solatro/design/spotlight/DESIGN.md'), 'utf8'), { file: 'S.md' });

function chart(...lines) {
  return parseCharts(['```mermaid', 'flowchart TD', ...lines.map((l) => `  ${l}`), '```'].join('\n'), { file: 'T.md' });
}

test('a label wraps to the node width, breaks a word too long for it, and is capped', () => {
  const fits = Math.floor((METRICS.nodeWidth - 2 * METRICS.padX) / METRICS.charWidth);
  const lines = wrapLabel('one two three four five six seven eight nine ten eleven twelve');
  assert.ok(lines.every((l) => l.length <= fits), 'every line fits the node');
  assert.ok(lines.length > 1);
  assert.ok(wrapLabel('Supercalifragilistic'.repeat(6)).every((l) => l.length <= fits), 'a long word is broken');
  assert.equal(wrapLabel('word '.repeat(200)).length, METRICS.maxLines, 'and the label is capped');
  assert.match(wrapLabel('word '.repeat(200)).at(-1), /…$/);
});

test('the same graph always lays out identically — a frozen version must reproduce', () => {
  const a = layout(SPOTLIGHT);
  const b = layout(SPOTLIGHT);
  assert.equal(JSON.stringify(a.positions), JSON.stringify(b.positions));
  assert.equal(a.engine, ENGINE);
});

test('no two nodes in a chart overlap', () => {
  const laid = layout(SPOTLIGHT);
  const ids = Object.keys(laid.positions);
  for (let i = 0; i < ids.length; i++) {
    for (let j = i + 1; j < ids.length; j++) {
      const a = { ...laid.positions[ids[i]], ...laid.sizes[ids[i]] };
      const b = { ...laid.positions[ids[j]], ...laid.sizes[ids[j]] };
      const apart = a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y;
      assert.ok(apart, `${ids[i]} overlaps ${ids[j]}`);
    }
  }
});

test('every node sits inside its own chart frame', () => {
  const laid = layout(SPOTLIGHT);
  for (const [id, p] of Object.entries(laid.positions)) {
    const frame = laid.charts[SPOTLIGHT.nodes[id].chart];
    const size = laid.sizes[id];
    assert.ok(p.x >= frame.x && p.x + size.w <= frame.x + frame.w, `${id} escapes its frame sideways`);
    assert.ok(p.y >= frame.y && p.y + size.h <= frame.y + frame.h, `${id} escapes its frame vertically`);
  }
});

test('every edge points down a layer, except the loops the ranking had to cut', () => {
  const laid = layout(SPOTLIGHT);
  const back = new Set(laid.backEdges);
  for (const edge of SPOTLIGHT.edges) {
    const geo = edgeGeometry(edge, laid);
    if (!geo) continue;
    if (back.has(edge.key)) continue;
    assert.ok(geo.y2 >= geo.y1, `${edge.key} runs upward but was not recorded as a back edge`);
  }
  assert.ok(back.size > 0, 'Spotlight has real loops — C10→C8, I10→I5 — and they are found');
});

test('collapsing a chart removes its nodes and shrinks the page', () => {
  const open = layout(SPOTLIGHT);
  const shut = layout(SPOTLIGHT, { collapsed: ['D'] });
  const chartD = SPOTLIGHT.charts.find((c) => c.id === 'D');
  for (const id of chartD.nodes) assert.equal(shut.positions[id], undefined);
  assert.equal(shut.charts.D.collapsed, true);
  assert.equal(shut.charts.D.h, METRICS.collapsedHeight + 3 * METRICS.chartPad);
  assert.ok(shut.bounds.h < open.bounds.h, 'the tallest chart folded, so the page got shorter');
  assert.deepEqual(shut.collapsed, ['D'], 'and the collapse state is recorded for Q115=b');
});

test('one chart on its own is the only thing laid out (Q52, the picker)', () => {
  const laid = layout(SPOTLIGHT, { only: 'A' });
  assert.deepEqual(Object.keys(laid.charts), ['A']);
  assert.equal(Object.keys(laid.positions).length, SPOTLIGHT.charts.find((c) => c.id === 'A').nodes.length);
});

test('a chart that is one long chain lays out as one column', () => {
  const g = chart('A1["one"] --> A2["two"]', 'A2 --> A3["three"]', 'A3 --> A4["four"]');
  const laid = layout(g);
  const xs = new Set(Object.values(laid.positions).map((p) => p.x));
  assert.equal(xs.size, 1, 'a chain is straightened, not staircased');
  const ys = Object.values(laid.positions).map((p) => p.y).sort((a, b) => a - b);
  assert.equal(new Set(ys).size, 4, 'one layer each');
});

// --- derived cross-chart links (S12, design F13; GAP-002 = b) ---

test('a link runs from its node to the target chart frame, ending on both borders', () => {
  const laid = layout(SPOTLIGHT);
  const link = SPOTLIGHT.links.find((l) => l.key === 'K14~>I');
  const geo = linkGeometry(link, laid);
  const node = { ...laid.positions.K14, ...laid.sizes.K14 };
  const frame = laid.charts.I;

  // The start is ON the source node's border — outside it would float, inside would run under it.
  const onBorder = (x, y, r) => Math.abs(x - r.x) < 1 || Math.abs(x - (r.x + r.w)) < 1
    || Math.abs(y - r.y) < 1 || Math.abs(y - (r.y + r.h)) < 1;
  assert.ok(onBorder(geo.x1, geo.y1, { x: node.x, y: node.y, w: node.w, h: node.h }));
  assert.ok(onBorder(geo.x2, geo.y2, frame), 'and it lands on the chart, not on a node inside it');
  assert.equal(geo.folded, false);
});

test('a link from a collapsed chart starts at the collapsed box (F8)', () => {
  const laid = layout(SPOTLIGHT, { collapsed: ['K'] });
  const geo = linkGeometry(SPOTLIGHT.links.find((l) => l.key === 'K14~>I'), laid);
  assert.equal(geo.folded, true, 'K14 has no position of its own, so the fold is the source');
  assert.equal(laid.positions.K14, undefined);
  const frame = laid.charts.K;
  assert.ok(geo.x1 >= frame.x - 1 && geo.x1 <= frame.x + frame.w + 1);
});

test('a link always bows, even when both ends sit on the same row', () => {
  // Collapse everything and the charts shelf-pack into one row: same y at both ends, which is
  // exactly where a bow computed from the vertical drop would be flat and the link would lie along
  // the row, through every box between its ends.
  const laid = layout(SPOTLIGHT, { collapsed: SPOTLIGHT.charts.map((c) => c.id) });
  const geos = SPOTLIGHT.links.map((l) => [l.key, linkGeometry(l, laid)]);
  assert.ok(geos.some(([, g]) => Math.abs(g.y1 - g.y2) < 1), 'the same-row case really occurs');
  for (const [key, g] of geos) {
    const off = Math.hypot(g.cx - (g.x1 + g.x2) / 2, g.cy - (g.y1 + g.y2) / 2);
    assert.ok(off >= 26, `${key} is flat: its control point sits on the chord (${off.toFixed(1)})`);
  }
});

test('links never move a node — the layout is computed from edges alone', () => {
  const withLinks = layout(SPOTLIGHT);
  const withoutLinks = layout({ ...SPOTLIGHT, links: [] });
  assert.deepEqual(withLinks.positions, withoutLinks.positions);
  assert.deepEqual(withLinks.bounds, withoutLinks.bounds);
});

test('MEASUREMENT — Spotlight lays out fast enough that no layout dependency is needed', () => {
  for (let i = 0; i < 3; i++) layout(SPOTLIGHT);           // warm
  const runs = [];
  for (let i = 0; i < 5; i++) {
    const start = process.hrtime.bigint();
    layout(SPOTLIGHT);
    runs.push(Number(process.hrtime.bigint() - start) / 1e6);
  }
  const best = Math.min(...runs);
  // ⚠ A FLOOR, not equality: Spotlight is a living document and this measurement is about SPEED,
 // not about how many nodes it happens to have today (it was 176 on 2026-08-01 and 268 by
 // 2026-08-03). Asserting the count made an ordinary design edit fail a performance test.
  assert.ok(Object.keys(SPOTLIGHT.nodes).length >= 176);
  // The gate is generous on purpose — this pins "interactive", not a benchmark. Measured on the
 // owner's machine 2026-08-01: 1.8 ms for 176 nodes and 182 edges. PLAN §9 asked for the number.
  assert.ok(best < 250, `layout took ${best.toFixed(1)} ms`);
});
