// Picker foundations: grid topology and adjacency, the neighbour-ΔE objective, the
// blob-sizing modes, and the capacity assignment every layout variant commits through.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Grid, TOPOLOGIES } from '../src/core/layout/grid.js';
import {
  BLOB_MODES, blobWeights, coverage, deltaMatrix, entryLabs, scoreLayout, targetCounts,
} from '../src/core/layout/score.js';
import {
  assignByCapacity, boustrophedon, fillRuns, spiralOrder,
} from '../src/core/layout/assign.js';
import { generatePalette } from '../src/core/generate.js';
import { deltaEOK } from '../src/core/oklch.js';

const palette = generatePalette({ color_count: 24 });
const labs = entryLabs(palette);

/** A layout wrapper of the shape scoreLayout/coverage expect. */
const layoutOf = (grid, cells) => ({ grid, cells });

test('rect adjacency: interior cells have four neighbours, corners two', () => {
  const g = new Grid(5, 4, 'rect');
  assert.equal(g.count, 20);
  assert.equal(g.nbrCount[2 * 5 + 2], 4);
  assert.equal(g.nbrCount[0], 2);
  assert.equal(g.edges.length / 2, 5 * 3 + 4 * 4);
});

test('torus wraps: every cell has four neighbours and distance takes the short way', () => {
  const g = new Grid(6, 6, 'torus');
  for (const i of g.active) assert.equal(g.nbrCount[i], 4);
  assert.equal(g.edges.length / 2, 2 * 36);
  assert.equal(g.dist2(0, 5), 1, 'column 0 and column 5 are adjacent across the seam');
});

test('hex adjacency is six-way in the interior and symmetric', () => {
  const g = new Grid(7, 7, 'hex');
  assert.equal(g.nbrCount[3 * 7 + 3], 6);
  for (const i of g.active) {
    for (const j of g.neighbors(i)) {
      assert.ok(g.neighbors(j).includes(i), `hex adjacency not symmetric for ${i}/${j}`);
    }
  }
});

test('disc masks the corners and never links a live cell to a dead one', () => {
  const g = new Grid(16, 16, 'disc');
  assert.equal(g.mask[0], 0, 'corner is outside the disc');
  assert.ok(g.count < 16 * 16 && g.count > 0.6 * 16 * 16);
  for (const i of g.active) for (const j of g.neighbors(i)) assert.equal(g.mask[j], 1);
});

test('every topology builds a usable grid', () => {
  for (const t of TOPOLOGIES) {
    const g = new Grid(12, 10, t);
    assert.ok(g.count > 0 && g.edges.length > 0, t);
  }
});

test('a one-colour layout scores 0 and a checkerboard scores that pair exactly', () => {
  const g = new Grid(8, 8, 'rect');
  const flat = layoutOf(g, new Int32Array(64).fill(3));
  assert.equal(scoreLayout(flat, labs).mean, 0);
  assert.equal(scoreLayout(flat, labs).crossings, 0);

  const checker = new Int32Array(64);
  for (let i = 0; i < 64; i++) checker[i] = ((i % 8) + Math.floor(i / 8)) % 2 ? 1 : 0;
  const s = scoreLayout(layoutOf(g, checker), labs);
  const d = deltaEOK(labs[0], labs[1]);
  assert.ok(Math.abs(s.mean - d) < 1e-9, 'every edge crosses the same pair');
  assert.ok(Math.abs(s.worst - d) < 1e-9);
  assert.equal(s.crossings, 1);
});

test('coverage reports holes and missing colours', () => {
  const g = new Grid(4, 4, 'rect');
  const cells = new Int32Array(16).fill(0);
  const bad = coverage(layoutOf(g, cells), 3);
  assert.equal(bad.holes, 0);
  assert.deepEqual(bad.missing, [1, 2]);
  assert.equal(bad.complete, false);

  cells[1] = 1;
  cells[2] = 2;
  cells[3] = -1;
  const holed = coverage(layoutOf(g, cells), 3);
  assert.equal(holed.holes, 1);
  assert.equal(holed.complete, false);
});

test('every blob mode yields one positive weight per entry', () => {
  for (const mode of BLOB_MODES) {
    const w = blobWeights(palette, mode, { usage: palette.entries.map((_, i) => i * 10) });
    assert.equal(w.length, palette.entries.length, mode);
    for (const v of w) assert.ok(v > 0 && Number.isFinite(v), `${mode} produced ${v}`);
  }
});

test('isolation weighting gives the loneliest colour more area than a crowded one', () => {
  // A tight cluster of four plus one colour far away: the outlier must weigh the most.
  const fake = {
    entries: [
      { lab: [0.5, 0.0, 0.0], layer: 'fg', actual: { C: 0 } },
      { lab: [0.5, 0.005, 0.0], layer: 'fg', actual: { C: 0 } },
      { lab: [0.5, 0.0, 0.005], layer: 'fg', actual: { C: 0 } },
      { lab: [0.505, 0.0, 0.0], layer: 'fg', actual: { C: 0 } },
      { lab: [0.1, 0.2, -0.2], layer: 'fg', actual: { C: 0.3 } },
    ],
  };
  const w = blobWeights(fake, 'isolation');
  assert.ok(w[4] > w[0] * 5, 'the outlier should be given a much bigger target');
});

test('targetCounts fills the grid exactly and starves nobody', () => {
  for (const n of [24, 100, 1536]) {
    const w = blobWeights(palette, 'isolation');
    const c = targetCounts(w, n);
    assert.equal(c.reduce((a, b) => a + b, 0), n, `total for n=${n}`);
    for (const v of c) assert.ok(v >= 1, `every colour gets a cell (n=${n})`);
  }
  assert.throws(() => targetCounts([1, 1, 1], 2), /cannot hold/);
});

test('targetCounts is monotonic: a heavier colour never gets less area', () => {
  const c = targetCounts([1, 2, 8], 100);
  assert.ok(c[2] > c[1] && c[1] > c[0]);
});

test('capacity assignment hits the target counts exactly with no holes', () => {
  const g = new Grid(24, 16, 'rect');
  const counts = targetCounts(blobWeights(palette, 'isolation'), g.count);
  // Target field: a smooth left-to-right, top-to-bottom sweep through OKLab.
  const cellLabs = Array.from(g.active, (i) => {
    const x = (i % g.w) / (g.w - 1);
    const y = Math.floor(i / g.w) / (g.h - 1);
    return [y, x * 0.3 - 0.15, y * 0.3 - 0.15];
  });
  const cells = assignByCapacity(g, cellLabs, labs, counts);
  const seen = new Int32Array(labs.length);
  for (const i of g.active) seen[cells[i]]++;
  assert.deepEqual(Array.from(seen), Array.from(counts));
  assert.equal(coverage(layoutOf(g, cells), labs.length).complete, true);
});

test('fill orders visit every active cell exactly once', () => {
  for (const t of TOPOLOGIES) {
    const g = new Grid(13, 11, t);
    for (const [name, order] of [['boustrophedon', boustrophedon(g)], ['spiral', spiralOrder(g)]]) {
      assert.equal(order.length, g.count, `${name}/${t} length`);
      assert.equal(new Set(order).size, g.count, `${name}/${t} has no repeats`);
      for (const i of order) assert.equal(g.mask[i], 1, `${name}/${t} stays inside the mask`);
    }
  }
});

test('fillRuns lays contiguous runs and covers the whole grid', () => {
  const g = new Grid(10, 10, 'rect');
  const counts = targetCounts(blobWeights(palette, 'equal'), g.count);
  const order = palette.entries.map((_, i) => i);
  const cells = fillRuns(g, boustrophedon(g), order, counts);
  assert.equal(coverage(layoutOf(g, cells), labs.length).complete, true);
});

test('the delta matrix is symmetric with a zero diagonal', () => {
  const m = deltaMatrix(labs);
  const k = labs.length;
  for (let i = 0; i < k; i++) {
    assert.equal(m[i * k + i], 0);
    for (let j = 0; j < k; j++) assert.equal(m[i * k + j], m[j * k + i]);
  }
});
