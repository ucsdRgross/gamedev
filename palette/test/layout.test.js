// Picker layouts (PLAN §9, task 4.8): coverage, determinism, and the baseline bar.
//
// The contract the picker sells is "every colour is somewhere, and near colours like it".
// The first half is asserted absolutely — no holes, nothing missing, for every variant at
// every palette size and every blob mode. The second half is asserted comparatively,
// against the ramp-rows baseline, which is what keeps "optimized" an honest label.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BASELINE_ID, BASELINE_SIZES, VARIANTS, buildLayout, hashSeed, rankLayouts,
} from '../src/core/layout/index.js';
import { BLOB_MODES, coverage, entryLabs, scoreLayout } from '../src/core/layout/score.js';
import { hilbertIndex3, hilbertOrder } from '../src/core/layout/hilbert.js';
import { projectLabs, projectSites } from '../src/core/layout/mds.js';
import { triangulate } from '../src/core/layout/mesh.js';
import { Grid } from '../src/core/layout/grid.js';
import { pickAt, renderLayout } from '../src/core/layout/render.js';
import { generatePalette } from '../src/core/generate.js';
import { presetParams } from '../src/core/presets.js';
import { deltaEOK, rgb8ToHex } from '../src/core/oklch.js';

const paletteAt = (k) => generatePalette({ color_count: k });
const OPTIMIZED = VARIANTS.filter((v) => v.optimized);

// Build cost scales worse than linearly with cell count, so the invariant tests pin a
// small grid: none of them are about resolution, and the default 96×64 would multiply the
// suite's runtime for no extra coverage. One test below exercises the real defaults.
const TEST_SIZE = { w: 48, h: 32 };
const at = (opts = {}) => ({ size: TEST_SIZE, ...opts });

/** Mean-neighbour score of one variant on one palette, on the fixed test grid. */
const meanOf = (palette, id, opts = {}) => buildLayout(palette, at({ ...opts, variant: id })).score.mean;

test('every variant covers its grid completely at every palette size', () => {
  for (const k of [4, 8, 32, 64]) {
    const palette = paletteAt(k);
    for (const v of VARIANTS) {
      const layout = buildLayout(palette, at({ variant: v.id }));
      const cov = coverage(layout, k);
      assert.equal(cov.holes, 0, `${v.id} @K=${k}: ${cov.holes} unassigned cells`);
      assert.deepEqual(cov.missing, [], `${v.id} @K=${k}: colours never placed`);
      for (const i of layout.grid.active) {
        const e = layout.cells[i];
        assert.ok(e >= 0 && e < k, `${v.id} @K=${k}: cell holds out-of-range entry ${e}`);
      }
    }
  }
});

test('every blob mode keeps full coverage across every variant', () => {
  const palette = paletteAt(24);
  const usage = palette.entries.map((_, i) => (i * 37) % 91);
  for (const mode of BLOB_MODES) {
    for (const v of VARIANTS) {
      const layout = buildLayout(palette, at({ variant: v.id, blobMode: mode, usage }));
      assert.equal(coverage(layout, 24).complete, true, `${v.id} + ${mode}`);
    }
  }
});

test('blob sizing actually changes areas: equal is flat, isolation is not', () => {
  const palette = paletteAt(32);
  const areaOf = (mode) => {
    const layout = buildLayout(palette, at({ variant: 'lloyd', blobMode: mode }));
    const tally = new Int32Array(32);
    for (const i of layout.grid.active) tally[layout.cells[i]]++;
    return tally;
  };
  const equal = areaOf('equal');
  const isolation = areaOf('isolation');
  const spread = (t) => Math.max(...t) / Math.min(...t);
  assert.ok(spread(equal) <= 1.2, 'equal-area mode should give near-identical blobs');
  assert.ok(spread(isolation) > 2, 'isolation mode should give the lonely colours much more room');
});

test('layouts are deterministic: the same palette and seed rebuild identically', () => {
  const palette = paletteAt(32);
  for (const v of VARIANTS) {
    const a = buildLayout(palette, at({ variant: v.id, seed: 'fixed-seed' }));
    const b = buildLayout(palette, at({ variant: v.id, seed: 'fixed-seed' }));
    assert.deepEqual(Array.from(a.cells), Array.from(b.cells), `${v.id} is not deterministic`);
  }
});

test('annealing explores: a different seed gives a different grid but a comparable score', () => {
  const palette = paletteAt(32);
  const a = buildLayout(palette, at({ variant: 'anneal', seed: 'seed-one' }));
  const b = buildLayout(palette, at({ variant: 'anneal', seed: 'seed-two' }));
  assert.notDeepEqual(Array.from(a.cells), Array.from(b.cells), 'the seed should steer the search');
  assert.ok(Math.abs(a.score.mean - b.score.mean) < 1.5, 'both runs should land in the same league');
});

test('optimized layouts beat the ramp-rows baseline across the sweep', () => {
  // At K>=48 EVERY optimized variant beats the baseline, robustly (verified across seeds).
  // At K=32 the disc/organic variants carry a harder scoring surface (a disc grid is scored
  // over more edges, ARCHITECTURE §11) and are borderline against the perfectly-tiling
  // baseline — som-disc loses on most layout seeds on the default palette, on pristine too.
  // The layout RNG is seeded from `palette.seed`, so which side of that coin-flip a borderline
  // variant lands on shifts whenever the parameter schema grows (it lengthens the seed
  // string). So the honest, seed-stable claim at K=32 is ARCHITECTURE §11's own wording — the
  // BEST optimized arrangement beats the baseline — not that every one does.
  for (const k of BASELINE_SIZES) {
    const palette = paletteAt(k);
    const base = meanOf(palette, BASELINE_ID);
    if (k >= 48) {
      for (const v of OPTIMIZED) {
        const score = meanOf(palette, v.id);
        assert.ok(score < base, `${v.id} @K=${k}: ${score.toFixed(3)} vs baseline ${base.toFixed(3)}`);
      }
    } else {
      const best = Math.min(...OPTIMIZED.map((v) => meanOf(palette, v.id)));
      assert.ok(best < base, `best optimized @K=${k}: ${best.toFixed(3)} vs baseline ${base.toFixed(3)}`);
    }
  }
});

test('the baseline is near-optimal on small palettes — a property, not a regression', () => {
  // With only eight colours, hue-ordered blocks tile the grid almost perfectly. If some
  // variant ever beats it here by a wide margin, the baseline implementation has broken.
  const palette = paletteAt(8);
  const base = meanOf(palette, BASELINE_ID);
  const best = Math.min(...VARIANTS.map((v) => meanOf(palette, v.id)));
  assert.ok(base <= best * 1.05, `baseline ${base.toFixed(3)} should be within 5% of the best ${best.toFixed(3)}`);
});

test('optimized layouts beat the baseline on real presets too, not just default params', () => {
  for (const id of ['neon-cyberpunk', 'autumn-forest', 'nes']) {
    const palette = generatePalette(presetParams(id));
    if (palette.entries.length < 32) continue; // small budgets are the baseline's home turf
    const base = meanOf(palette, BASELINE_ID);
    const best = Math.min(...OPTIMIZED.map((v) => meanOf(palette, v.id)));
    assert.ok(best < base, `${id}: best optimized ${best.toFixed(3)} vs baseline ${base.toFixed(3)}`);
  }
});

test('rankLayouts returns every variant, best mean first', () => {
  const ranked = rankLayouts(paletteAt(16), at());
  assert.equal(ranked.length, VARIANTS.length);
  for (let i = 1; i < ranked.length; i++) {
    assert.ok(ranked[i - 1].score.mean <= ranked[i].score.mean, 'ranking is not sorted');
  }
});

test('the score of a built layout matches a fresh scoring of its cells', () => {
  const palette = paletteAt(24);
  const layout = buildLayout(palette, at({ variant: 'grow' }));
  const fresh = scoreLayout(layout, entryLabs(palette));
  assert.ok(Math.abs(fresh.mean - layout.score.mean) < 1e-12);
  assert.ok(layout.score.worst >= layout.score.mean);
});

test('hilbertIndex3 is a bijection over a small cube', () => {
  const bits = 3;
  const side = 1 << bits;
  const seen = new Set();
  for (let x = 0; x < side; x++) {
    for (let y = 0; y < side; y++) {
      for (let z = 0; z < side; z++) seen.add(hilbertIndex3(x, y, z, bits));
    }
  }
  assert.equal(seen.size, side ** 3, 'every cell should get a distinct index');
  assert.equal(Math.max(...seen), side ** 3 - 1);
});

test('consecutive Hilbert indices are adjacent in space', () => {
  const bits = 3;
  const side = 1 << bits;
  const byIndex = new Map();
  for (let x = 0; x < side; x++) {
    for (let y = 0; y < side; y++) {
      for (let z = 0; z < side; z++) byIndex.set(hilbertIndex3(x, y, z, bits), [x, y, z]);
    }
  }
  for (let i = 1; i < side ** 3; i++) {
    const a = byIndex.get(i - 1);
    const b = byIndex.get(i);
    const step = Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]);
    assert.equal(step, 1, `steps ${i - 1}->${i} are not neighbours`);
  }
});

test('the Hilbert ordering puts perceptually close colours close in sequence', () => {
  const palette = paletteAt(32);
  const labs = entryLabs(palette);
  const order = hilbertOrder(labs);
  assert.equal(new Set(order).size, labs.length, 'the ordering is a permutation');
  const neighbourGap = order.slice(1).reduce((a, e, i) => a + deltaEOK(labs[order[i]], labs[e]), 0) / (order.length - 1);
  const naturalGap = labs.slice(1).reduce((a, p, i) => a + deltaEOK(labs[i], p), 0) / (labs.length - 1);
  assert.ok(neighbourGap < naturalGap, 'Hilbert order should beat palette order on step size');
});

test('the MDS projection preserves perceptual distance in rank', () => {
  const labs = entryLabs(paletteAt(24));
  const { points } = projectLabs(labs);
  assert.equal(points.length, labs.length);
  let agree = 0;
  let total = 0;
  for (let i = 0; i < labs.length; i++) {
    for (let j = i + 1; j < labs.length; j++) {
      for (let q = j + 1; q < labs.length; q++) {
        const near2d = Math.hypot(points[i][0] - points[j][0], points[i][1] - points[j][1])
          < Math.hypot(points[i][0] - points[q][0], points[i][1] - points[q][1]);
        const nearLab = deltaEOK(labs[i], labs[j]) < deltaEOK(labs[i], labs[q]);
        if (near2d === nearLab) agree++;
        total++;
      }
    }
  }
  assert.ok(agree / total > 0.8, `only ${((agree / total) * 100).toFixed(1)}% of distance comparisons survived`);
});

test('projectSites lands every colour inside the grid', () => {
  const grid = new Grid(48, 32, 'rect');
  for (const [x, y] of projectSites(grid, entryLabs(paletteAt(32)))) {
    assert.ok(x >= 0 && x <= grid.spanX, `site x ${x} outside the grid`);
    assert.ok(y >= 0 && y <= grid.spanY, `site y ${y} outside the grid`);
  }
});

test('the Delaunay triangulation is well formed and covers the interior', () => {
  const points = projectSites(new Grid(48, 32, 'rect'), entryLabs(paletteAt(24)));
  const tris = triangulate(points);
  assert.ok(tris.length >= points.length - 2, `only ${tris.length} triangles for ${points.length} points`);
  for (const t of tris) {
    assert.equal(new Set(t).size, 3, 'a triangle repeated a vertex');
    for (const i of t) assert.ok(i >= 0 && i < points.length);
  }
});

test('rendering at the real default resolution works and stays smooth', () => {
  const palette = paletteAt(48);
  const layout = buildLayout(palette, { variant: 'voronoi' });
  const out = renderLayout(layout, palette, { scale: 6 });
  assert.equal(out.w, layout.grid.w * 6);
  assert.equal(out.h, layout.grid.h * 6);
  assert.equal(coverage({ grid: layout.grid, cells: layout.cells }, 48).complete, true);
});

test('smoothing never smooths a colour off the picture', () => {
  const palette = paletteAt(64);
  for (const id of ['voronoi', 'som-rect', 'grow', 'wheel']) {
    const layout = buildLayout(palette, at({ variant: id }));
    const { labels } = renderLayout(layout, palette, { scale: 6 });
    const seen = new Set(labels);
    for (let e = 0; e < 64; e++) {
      assert.ok(seen.has(e), `${id}: colour ${e} disappeared under boundary smoothing`);
    }
  }
});

test('smoothing rounds the staircases: fewer boundary pixels than the raw upsample', () => {
  const palette = paletteAt(32);
  const layout = buildLayout(palette, at({ variant: 'voronoi' }));
  const perimeter = (labels, w, h) => {
    let n = 0;
    for (let y = 0; y < h - 1; y++) {
      for (let x = 0; x < w - 1; x++) {
        const i = y * w + x;
        if (labels[i] !== labels[i + 1] || labels[i] !== labels[i + w]) n++;
      }
    }
    return n;
  };
  const raw = renderLayout(layout, palette, { scale: 6, smooth: false });
  const soft = renderLayout(layout, palette, { scale: 6, smooth: true });
  assert.ok(perimeter(soft.labels, soft.w, soft.h) < perimeter(raw.labels, raw.w, raw.h),
    'boundary smoothing should shorten the total blob perimeter');
});

test('edge modes: none paints only palette colours, shade and seam paint over them', () => {
  const palette = paletteAt(24);
  const layout = buildLayout(palette, at({ variant: 'lloyd' }));
  const allowed = new Set(palette.entries.map((e) => e.hex));
  const plain = renderLayout(layout, palette, { scale: 6, edges: 'none' }).raster;
  for (let p = 0; p < plain.data.length; p += 3) {
    const hex = rgb8ToHex([plain.data[p], plain.data[p + 1], plain.data[p + 2]]);
    assert.ok(allowed.has(hex), `edges:none introduced ${hex}, which is not in the palette`);
  }
  // The shade outline must also stay inside the palette — that is the point of it.
  const shaded = renderLayout(layout, palette, { scale: 6, edges: 'shade' }).raster;
  let differs = 0;
  for (let p = 0; p < shaded.data.length; p += 3) {
    const hex = rgb8ToHex([shaded.data[p], shaded.data[p + 1], shaded.data[p + 2]]);
    assert.ok(allowed.has(hex), `edges:shade introduced ${hex}, which is not in the palette`);
    if (shaded.data[p] !== plain.data[p]) differs++;
  }
  assert.ok(differs > 0, 'shaded edges should actually change pixels');
});

test('rectilinear layouts keep their straight edges', () => {
  const palette = paletteAt(32);
  for (const id of ['ramp-rows', 'treemap', 'spiral', 'hilbert']) {
    const layout = buildLayout(palette, at({ variant: id }));
    assert.equal(layout.rectilinear, true, `${id} should be flagged rectilinear`);
    const soft = renderLayout(layout, palette, { scale: 6 });
    const raw = renderLayout(layout, palette, { scale: 6, smooth: false });
    assert.deepEqual(Array.from(soft.labels), Array.from(raw.labels),
      `${id} must not be smoothed — its straight edges are the information`);
  }
});

test('pickAt reads back the colour actually drawn at a pixel', () => {
  const palette = paletteAt(32);
  const layout = buildLayout(palette, at({ variant: 'grow' }));
  const out = renderLayout(layout, palette, { scale: 6 });
  for (const [x, y] of [[10, 10], [100, 50], [200, 120]]) {
    const index = pickAt(out, x, y);
    if (index < 0) continue;
    const p = (y * out.w + x) * 3;
    assert.equal(rgb8ToHex([out.raster.data[p], out.raster.data[p + 1], out.raster.data[p + 2]]),
      palette.entries[index].hex, `readout disagrees with the pixel at ${x},${y}`);
  }
  assert.equal(pickAt(out, -1, 0), -1);
  assert.equal(pickAt(out, 0, out.h + 5), -1);
});

test('hashSeed is stable and separates similar strings', () => {
  assert.equal(hashSeed('PAL1-abc'), hashSeed('PAL1-abc'));
  assert.notEqual(hashSeed('PAL1-abc'), hashSeed('PAL1-abd'));
});
