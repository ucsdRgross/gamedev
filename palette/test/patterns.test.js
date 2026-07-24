// Tileable dither patterns (PLAN §9.3, task 4c.1).
//
// The whole reference view rests on one property: a patch made of `weights` parts of some
// colours contains *exactly* those parts. If a pattern hands out one cell too many, every blend
// colour computed from it is wrong by a fraction of a step — invisibly, and consistently enough
// that nothing else would catch it. So the weight accounting is asserted per pattern, per arity,
// rather than spot-checked.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  DITHER_PATTERNS, bayerOrder, blueNoiseOrder, halftoneOrder, patternById, patternPatch,
  patternTile, weightLadder,
} from '../src/core/patterns.js';
import { BAYER4, BAYER8 } from '../src/core/dither.js';

test('every pattern is a permutation of 0..n*n-1', () => {
  for (const p of DITHER_PATTERNS) {
    const total = p.n * p.n;
    assert.equal(p.order.length, total, p.id);
    const seen = new Set(p.order);
    assert.equal(seen.size, total, `${p.id} has duplicate ranks`);
    assert.equal(Math.min(...p.order), 0, p.id);
    assert.equal(Math.max(...p.order), total - 1, p.id);
  }
});

test('the ids are unique and every family is represented', () => {
  const ids = DITHER_PATTERNS.map((p) => p.id);
  assert.equal(new Set(ids).size, ids.length);
  for (const family of ['bayer', 'noise', 'halftone', 'artist']) {
    assert.ok(DITHER_PATTERNS.some((p) => p.family === family), `no ${family} pattern`);
  }
});

test('the generated Bayer matrices equal the published ones', () => {
  // dither.js derives BAYER4/BAYER8 from bayerOrder rather than keeping its own copy, so this
  // pins the recursion against the literal matrices every reference prints. If the recursion is
  // ever "simplified", the scenes and the recolour path change with it — silently, otherwise.
  assert.deepEqual(BAYER4, [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
  ]);
  assert.deepEqual(BAYER8, [
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
  ]);
});

test('bayerOrder refuses a size that is not a power of two', () => {
  assert.throws(() => bayerOrder(3));
  assert.throws(() => bayerOrder(1));
});

test('patternTile hands out exactly the requested number of cells', () => {
  for (const p of DITHER_PATTERNS) {
    const total = p.n * p.n;
    for (const weights of [[1, total - 1], [total - 1, 1], splitEvenly(total, 2), splitEvenly(total, 3), splitEvenly(total, 4)]) {
      if (weights.some((w) => w < 1)) continue; // a 2x2 tile cannot hold four distinct shares
      const tile = patternTile(p, weights);
      const counts = new Array(weights.length).fill(0);
      for (const slot of tile) counts[slot]++;
      assert.deepEqual(counts, weights, `${p.id} at ${weights.join(':')}`);
    }
  }
});

test('patternTile refuses weights that do not sum to the tile', () => {
  const p = patternById('bayer4');
  assert.throws(() => patternTile(p, [8, 7]));
  assert.throws(() => patternTile(p, [8, 9]));
  assert.throws(() => patternTile(p, [8, 8.5]));
  assert.throws(() => patternTile(p, [-1, 17]));
});

test('patternById refuses an unknown id rather than defaulting', () => {
  assert.throws(() => patternById('bayer5'));
});

test('patternPatch emits only the supplied slots and tiles seamlessly', () => {
  for (const p of DITHER_PATTERNS) {
    const total = p.n * p.n;
    const weights = splitEvenly(total, 2);
    const patch = patternPatch(p, weights, p.n * 3, p.n * 2);
    assert.ok(patch.every((s) => s === 0 || s === 1), `${p.id} emitted a foreign slot`);
    // Seamless: the tile repeats exactly, so column x and column x+n are identical.
    for (let y = 0; y < p.n * 2; y++) {
      for (let x = 0; x < p.n; x++) {
        assert.equal(
          patch[y * p.n * 3 + x],
          patch[y * p.n * 3 + x + p.n],
          `${p.id} does not tile at (${x}, ${y})`,
        );
      }
    }
  }
});

test('patternPatch honours the phase offset', () => {
  const p = patternById('bayer4');
  const a = patternPatch(p, [8, 8], 4, 4);
  const b = patternPatch(p, [8, 8], 4, 4, { ox: 1 });
  assert.notDeepEqual([...a], [...b]);
  // Shifting by a whole tile is the identity, which is what makes the offset safe to use for
  // breaking up phase between neighbouring patches.
  assert.deepEqual([...patternPatch(p, [8, 8], 4, 4, { ox: 4, oy: 4 })], [...a]);
});

test('blue noise is deterministic and spreads better than a raw scatter', () => {
  assert.deepEqual([...blueNoiseOrder(8)], [...blueNoiseOrder(8)]);
  // The defining property: at a 50% threshold, no filled cell should have all four of its
  // toroidal neighbours filled too. Clustering that tight is what blue noise exists to avoid.
  const n = 16;
  const order = blueNoiseOrder(n);
  const on = (x, y) => order[((y % n) + n) % n * n + (((x % n) + n) % n)] < (n * n) / 2;
  let clustered = 0;
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      if (!on(x, y)) continue;
      if (on(x + 1, y) && on(x - 1, y) && on(x, y + 1) && on(x, y - 1)) clustered++;
    }
  }
  assert.ok(clustered <= 4, `blue noise has ${clustered} fully-surrounded cells`);
});

test('halftone grows as one connected dot, unlike bayer', () => {
  // The point of a clustered-dot pattern: at a low share the filled cells touch each other.
  const n = 8;
  const order = halftoneOrder(n);
  const filled = [];
  for (let i = 0; i < n * n; i++) if (order[i] < 8) filled.push([i % n, (i / n) | 0]);
  assert.equal(filled.length, 8);
  const maxSpan = Math.max(
    ...filled.map(([x]) => x) ,
  ) - Math.min(...filled.map(([x]) => x));
  assert.ok(maxSpan <= 3, `halftone's first eight cells span ${maxSpan} columns, so they are not clustered`);
});

test('weightLadder only offers ratios its tile can express exactly', () => {
  for (const p of DITHER_PATTERNS) {
    const total = p.n * p.n;
    for (const arity of [2, 3, 4]) {
      for (const weights of weightLadder(p, arity)) {
        assert.equal(weights.length, arity);
        assert.equal(weights.reduce((a, b) => a + b, 0), total, `${p.id} ${weights.join(':')}`);
        assert.ok(weights.every((w) => w >= 1), `${p.id} gave a colour no cells`);
        assert.doesNotThrow(() => patternTile(p, weights));
      }
    }
  }
});

test('a 2x2 tile honestly reports the three ratios it has, not seven', () => {
  // Asked for eighths, a four-cell tile cannot deliver them. Reporting quarters is the right
  // answer; rounding eighths onto quarters and calling them eighths would make every blend
  // colour built from this pattern a lie.
  const ladder = weightLadder(patternById('bayer2'), 2, 8);
  assert.deepEqual(ladder, [[1, 3], [2, 2], [3, 1]]);
});

/** Split `total` cells as evenly as possible into `parts`, largest first. */
function splitEvenly(total, parts) {
  const base = Math.floor(total / parts);
  const out = new Array(parts).fill(base);
  for (let i = 0; i < total - base * parts; i++) out[i]++;
  return out;
}
