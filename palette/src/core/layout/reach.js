// The reachable-colour set (PLAN §9.3) — what the palette can express *with dithering*, as
// opposed to what it literally contains.
//
// Every other view in this directory answers a question about the palette's own colours. This
// one answers the question an artist asks when a palette feels short: **is this colour actually
// missing, or can I dither my way to it?** Mixing two or more palette colours in one area
// produces a new perceived colour, so the set of colours a palette can reach is far larger than
// the palette — and it is computable exactly, not approximately.
//
// Three things decide whether the answer is honest:
//
// 1. **Optical mixing is linear-light.** A 50/50 checkerboard averages *photons*, so the blend
//    colour is the weighted mean of the constituents' linear-light sRGB, converted to OKLab
//    afterwards. Averaging in gamma-encoded sRGB (too dark) or in OKLab (too light) makes every
//    reachability claim quietly wrong by several ΔE, and it would still pass any test that only
//    checks "the blend is between the two colours". `test/reach.test.js` asserts against an
//    independently computed linear average with the two wrong answers as negative controls.
// 2. **The pattern does not change the colour, only the texture.** A blend is fully described by
//    *which* entries and *what integer share* of the tile each takes. Which pattern draws it —
//    Bayer, halftone, blue noise, scanlines — changes how it reads up close and nothing else.
//    So the reachable set is enumerated over (entries, weights) and a pattern is chosen for
//    display, rather than multiplying the search space by fourteen for no colours gained.
// 3. **Coverage is reported, never faked.** Same rule the colour-space maps live under
//    (ARCHITECTURE §11): a region no blend reaches is marked as unreached, and the gap analysis
//    says which colour to add rather than pretending the gap is not there.

import {
  deltaEOK, linearRgbToOklab, linearToSrgb, oklabToOklch, rgb8ToSrgb, srgbToLinear, srgbToRgb8,
  rgb8ToHex, srgbToOklab,
} from '../oklch.js';
import { entryLabs, deltaMatrix } from './score.js';
import { DEFAULT_SATURATIONS, mapSample } from './colorspace.js';
import { okhslCached } from '../okhsl.js';
import { DITHER_PATTERNS } from '../patterns.js';
import { makeRealize } from '../generate.js';
import { makeRng } from '../rng.js';

// The dither view — and, since 2026-07-24, every picker map — lays colour out in **OKHSL**
// (`okhsl.js`), not HSL. HSL is not perceptually uniform, so an even sweep of pixels is an uneven
// sweep of colour, which bands the reference colormap; OKHSL runs lightness through OKLab and
// normalises saturation to the gamut, giving a smooth, band-free gradient with full sRGB coverage.
// `okhslCached` memoises the per-hue cusp solve.

/**
 * Every blend's weights sum to this. Sixteen is the 4×4 tile an artist actually hand-places, so
 * a ratio is a whole number of cells in the standard tile and nothing rounds. Patterns with a
 * larger tile scale up by an integer factor; the 2×2 expresses the quarters and honestly
 * declines the rest.
 */
export const BLEND_DENOM = 16;

/** Above this ΔE between a target colour and the nearest blend, a gradient bands visibly. */
export const BANDING_DE = 2;

/**
 * Roughness buckets — how a patch reads, given how far apart its constituents are.
 *
 * The boundaries are measured, not chosen. Two *adjacent steps of one ramp* are the canonical
 * case of a pair that dithers into a convincing intermediate shade, and across every palette
 * size and the first twelve presets those sit at a median of 15.9 ΔE (p25 15.1, p75 22.1). A
 * first cut put the boundary at 10, which classified the everyday case as "texture" and was
 * caught by a test asserting the ramp catalogue contains at least one cleanly-blending pair.
 */
export const ROUGHNESS_BANDS = [
  { max: 18, id: 'smooth', label: 'BLENDS CLEANLY' },
  { max: 35, id: 'textured', label: 'READS AS TEXTURE' },
  { max: Infinity, id: 'rough', label: 'VISIBLE DITHER' },
];

/** Which bucket a roughness falls in. */
export function roughnessBand(roughness) {
  return ROUGHNESS_BANDS.find((b) => roughness <= b.max);
}

const DEFAULTS = {
  maxArity: 4,
  // Sampling resolution of the colour-space volume used for coverage and for ranking. Coarser
  // than the map it is compared against, because it is a statistic over a smooth field.
  sampleSize: { w: 64, h: 32 },
  saturations: DEFAULT_SATURATIONS,
  // Three or four colours whose constituents are further apart than this average to something a
  // pair already reaches while reading as noise, so they are not worth enumerating. Pairs are
  // NOT pruned — a high-contrast pair is a legitimate way to reach a colour and the catalogue
  // labels it as texture rather than hiding it.
  spreadCap: 40,
  // How many N-way blends survive ranking. Generous, because they are cheap once found.
  nWayBudget: 4000,
  // OKLab edge length of a dedupe voxel. 0.008 is 0.8 ΔE — below the just-noticeable
  // difference, so collapsing a voxel never merges colours an eye could tell apart.
  dedupeCell: 0.008,
  suggestions: 3,
  // Random convex combinations used to estimate the theoretical floor. Set to 0 to skip it.
  // The estimate converges *downward* with more trials (a sparse sample can only overstate the
  // distance to the hull), so it is an upper bound on the floor and is labelled an estimate.
  // 400k costs about 600 ms and is where the curve has flattened to a few hundredths of a ΔE.
  hullTrials: 400000,
  seed: 0x5EED,
};

// ---------------------------------------------------------------------------
// Blend colour
// ---------------------------------------------------------------------------

/** Each palette entry's colour as linear-light sRGB — the space optical mixing happens in. */
export function entryLinears(palette) {
  return palette.entries.map((e) => {
    const s = rgb8ToSrgb(e.rgb8);
    return [srgbToLinear(s[0]), srgbToLinear(s[1]), srgbToLinear(s[2])];
  });
}

/**
 * The colour `weights` parts of `entries` resolve to when viewed from far enough away that the
 * pattern is not resolved — the weighted mean in **linear-light** sRGB.
 *
 * Returns `{ lab, rgb8 }`. `lab` is authoritative (it is what every distance is measured in);
 * `rgb8` is the flat chip the sheet draws beside the tile, and is the one deliberately
 * non-palette colour in the whole picker.
 */
export function blendColor(linears, entries, weights, denom = BLEND_DENOM) {
  let r = 0;
  let g = 0;
  let b = 0;
  for (let i = 0; i < entries.length; i++) {
    const c = linears[entries[i]];
    const w = weights[i];
    r += c[0] * w;
    g += c[1] * w;
    b += c[2] * w;
  }
  r /= denom;
  g /= denom;
  b /= denom;
  return {
    lab: linearRgbToOklab(r, g, b),
    rgb8: srgbToRgb8([linearToSrgb(r), linearToSrgb(g), linearToSrgb(b)]),
  };
}

/**
 * ΔE between two palette entries. `deltaMatrix` (`score.js`) is a **flat** `Float64Array` of
 * `k×k`, so it is read through this rather than as `matrix[i][j]` — which silently yields
 * `undefined` and poisons every comparison downstream with `NaN`.
 */
function de(matrix, k, i, j) {
  return matrix[i * k + j];
}

/** How far apart a blend's constituents are — the max pairwise ΔE, so 2 and 4 colours compare. */
function spreadOf(matrix, k, entries) {
  let worst = 0;
  for (let i = 0; i < entries.length; i++) {
    for (let j = i + 1; j < entries.length; j++) {
      const d = de(matrix, k, entries[i], entries[j]);
      if (d > worst) worst = d;
    }
  }
  return worst;
}

// ---------------------------------------------------------------------------
// Patterns for a set of weights
// ---------------------------------------------------------------------------

/**
 * The weights scaled to a pattern's tile, or `null` if that tile cannot express them exactly.
 *
 * A 4×4 tile is the canonical denominator, so 8×8 and 16×16 scale up by 4 and 16. A 2×2 tile has
 * only four cells, so it can express quarters and refuses everything else — declining is the
 * right answer, because rounding would silently change the colour the patch claims.
 */
export function patternWeights(pattern, weights, denom = BLEND_DENOM) {
  const total = pattern.n * pattern.n;
  if (total >= denom) {
    if (total % denom) return null;
    const k = total / denom;
    return weights.map((w) => w * k);
  }
  const k = denom / total;
  if (denom % total || weights.some((w) => w % k)) return null;
  return weights.map((w) => w / k);
}

/** Every pattern that can draw these weights exactly, in registry order. */
export function patternsFor(weights, denom = BLEND_DENOM) {
  return DITHER_PATTERNS.filter((p) => patternWeights(p, weights, denom) !== null);
}

/**
 * The pattern a blend is drawn with by default: the smallest tile that expresses it exactly.
 *
 * Smallest is right because a small tile keeps its texture legible over a small sprite, and it
 * makes the obvious cases come out obvious — 8:8 reduces to a 2×2 at 2:2, which *is* the plain
 * checkerboard an artist would reach for, rather than a 4×4 Bayer that happens to look like one.
 */
export function preferredPattern(weights, denom = BLEND_DENOM) {
  let best = null;
  for (const p of DITHER_PATTERNS) {
    if (patternWeights(p, weights, denom) === null) continue;
    if (!best || p.n < best.n) best = p;
  }
  return best;
}

// ---------------------------------------------------------------------------
// The voxel index — nearest reachable colour, without a linear scan
// ---------------------------------------------------------------------------

/** Points per leaf. Small enough to prune well, large enough that the scan stays a tight loop. */
const LEAF_SIZE = 12;

/**
 * A 3-D k-d tree over OKLab with exact nearest-neighbour search.
 *
 * This is what makes the view affordable rather than a nice-to-have. The reachable set runs to
 * tens of thousands of colours and the map is a quarter of a million pixels across its slices,
 * so a linear scan is 10¹⁰ distance evaluations.
 *
 * **A uniform voxel grid was tried first and is the wrong structure here** — worth recording,
 * because it is the obvious choice and it fails for a non-obvious reason. Binning by colour and
 * walking rings outward is fine when the query lands near the data, and most of these queries do
 * not: the map deliberately samples the *whole* HSL space, including the saturated regions no
 * palette can reach, so a query is routinely tens of ΔE from the nearest blend. The ring search
 * then has to walk out dozens of rings at O(r²) voxels each, almost all empty, before it finds
 * anything to bound with. Shrinking the cell to fix the bucket density made it worse, not
 * better. A k-d tree prunes on the actual data distribution and is indifferent to how far away
 * the query is.
 *
 * Storage is flat typed arrays with an implicit node layout — no per-node objects, because
 * building one per point for a few hundred thousand points is most of the cost.
 */
export function buildColorIndex(labs) {
  const n = labs.length;
  const xs = new Float64Array(n);
  const ys = new Float64Array(n);
  const zs = new Float64Array(n);
  for (let i = 0; i < n; i++) { xs[i] = labs[i][0]; ys[i] = labs[i][1]; zs[i] = labs[i][2]; }
  const axisOf = [xs, ys, zs];

  const order = new Int32Array(n);
  for (let i = 0; i < n; i++) order[i] = i;

  // Node arrays, grown as the tree is built. A leaf has axis -1 and covers order[lo, hi).
  const axis = [];
  const split = [];
  const lo = [];
  const hi = [];
  const left = [];
  const right = [];

  /** Partition order[a, b) about the k-th element on `ax` (quickselect, in place). */
  function select(a, b, k, ax) {
    const values = axisOf[ax];
    let l = a;
    let r = b - 1;
    while (l < r) {
      const pivot = values[order[(l + r) >> 1]];
      let i = l;
      let j = r;
      while (i <= j) {
        while (values[order[i]] < pivot) i++;
        while (values[order[j]] > pivot) j--;
        if (i <= j) {
          const t = order[i]; order[i] = order[j]; order[j] = t;
          i++; j--;
        }
      }
      if (k <= j) r = j;
      else if (k >= i) l = i;
      else break;
    }
  }

  function build(a, b) {
    const node = axis.length;
    axis.push(-1); split.push(0); lo.push(a); hi.push(b); left.push(-1); right.push(-1);
    if (b - a <= LEAF_SIZE) return node;

    // Split on the widest axis of this node's own points, which is what keeps the tree shallow
    // for a colour set that is a thin curved sheet rather than a filled box.
    let bestAxis = 0;
    let bestSpread = -1;
    for (let d = 0; d < 3; d++) {
      const values = axisOf[d];
      let mn = Infinity;
      let mx = -Infinity;
      for (let i = a; i < b; i++) {
        const v = values[order[i]];
        if (v < mn) mn = v;
        if (v > mx) mx = v;
      }
      if (mx - mn > bestSpread) { bestSpread = mx - mn; bestAxis = d; }
    }
    if (bestSpread <= 0) return node; // every point identical: a leaf, however many there are

    const mid = (a + b) >> 1;
    select(a, b, mid, bestAxis);
    axis[node] = bestAxis;
    split[node] = axisOf[bestAxis][order[mid]];
    left[node] = build(a, mid);
    right[node] = build(mid, b);
    return node;
  }

  const root = n ? build(0, n) : -1;

  /** Nearest stored point to an OKLab colour, as `{ index, dist }` with `dist` in ΔE units. */
  function nearest(L, a, b) {
    let best = -1;
    let bestSq = Infinity;
    const query = [L, a, b];

    const visit = (node) => {
      const ax = axis[node];
      if (ax < 0) {
        for (let i = lo[node]; i < hi[node]; i++) {
          const p = order[i];
          const dL = L - xs[p];
          const da = a - ys[p];
          const db = b - zs[p];
          const d = dL * dL + da * da + db * db;
          if (d < bestSq) { bestSq = d; best = p; }
        }
        return;
      }
      const delta = query[ax] - split[node];
      const near = delta < 0 ? left[node] : right[node];
      const far = delta < 0 ? right[node] : left[node];
      visit(near);
      // The far side can only hold something better if the splitting plane itself is closer
      // than the incumbent.
      if (delta * delta < bestSq) visit(far);
    };

    if (root >= 0) visit(root);
    return { index: best, dist: best < 0 ? Infinity : 100 * Math.sqrt(bestSq) };
  }

  return { nearest, size: n, nodes: axis.length };
}

// ---------------------------------------------------------------------------
// The colour-space sample set
// ---------------------------------------------------------------------------

/**
 * The colour-space volume coverage is measured over: the same HSL geometry the maps draw, at a
 * coarser resolution, across every saturation slice.
 *
 * Sampling the *map's own* space rather than, say, a uniform OKLab box is deliberate — the
 * figure reported has to describe the thing on screen, and a uniform box would be dominated by
 * colours no display can show.
 */
export function colorSpaceSamples({ size = DEFAULTS.sampleSize, saturations = DEFAULTS.saturations } = {}) {
  const labs = [];
  const groups = [];
  for (const saturation of saturations) {
    const start = labs.length;
    for (let y = 0; y < size.h; y++) {
      for (let x = 0; x < size.w; x++) {
        const hsl = mapSample('rect', x, y, size.w, size.h, saturation);
        if (!hsl) continue;
        labs.push(srgbToOklab(okhslCached(hsl.h, hsl.s, hsl.l)));
      }
    }
    groups.push({ saturation, start, end: labs.length });
  }
  return { labs, groups };
}

/**
 * The best any dithering could *ever* do with this palette — the theoretical floor.
 *
 * Optical mixing is a convex combination in linear-light sRGB, so the colours a palette can
 * reach are exactly its convex hull there, whatever pattern or arity is used. That hull is not
 * convex once mapped into OKLab (the map is non-linear), so it is estimated by densely sampling
 * random convex combinations rather than solved: random subsets of up to eight entries with
 * Dirichlet-ish weights, at a continuous ratio no tile could actually express.
 *
 * This number earns its cost twice over. It tells an artist whether a gap is the *dithering's*
 * fault or the *palette's* — the whole difference between "try a different pattern" and "you
 * need another colour" — and it is a self-check on the enumeration above: if the arity-4
 * catalogue lands far short of the floor, the restriction to four is costing real colours and
 * should be said out loud rather than discovered later.
 */
export function hullFloor(palette, samples, { trials = 200000, seed = DEFAULTS.seed } = {}) {
  const linears = entryLinears(palette);
  const k = linears.length;
  const rng = makeRng(seed);
  const labs = new Array(trials);
  const maxParts = Math.min(8, k);
  for (let t = 0; t < trials; t++) {
    const parts = 1 + Math.floor(rng() * maxParts);
    let r = 0;
    let g = 0;
    let b = 0;
    let total = 0;
    for (let p = 0; p < parts; p++) {
      const e = Math.min(k - 1, Math.floor(rng() * k));
      const w = rng();
      const c = linears[e];
      r += c[0] * w;
      g += c[1] * w;
      b += c[2] * w;
      total += w;
    }
    labs[t] = total > 0
      ? linearRgbToOklab(r / total, g / total, b / total)
      : linearRgbToOklab(0, 0, 0);
  }
  return strip(coverageAgainst(buildColorIndex(labs), samples));
}

/** Mean ΔE to the nearest indexed colour and the share within the banding threshold. */
function coverageAgainst(index, samples) {
  let sum = 0;
  let within = 0;
  let worst = 0;
  const residual = new Float64Array(samples.length);
  for (let i = 0; i < samples.length; i++) {
    const { dist } = index.nearest(samples[i][0], samples[i][1], samples[i][2]);
    residual[i] = dist;
    sum += dist;
    if (dist <= BANDING_DE) within++;
    if (dist > worst) worst = dist;
  }
  return { mean: sum / samples.length, within: within / samples.length, worst, residual };
}

/**
 * The same figures per saturation slice.
 *
 * The aggregate alone is misleading and the breakdown is the useful artefact: a normal palette
 * covers the muted slices almost completely and cannot come near the fully-saturated one, so a
 * single number reads as "poor coverage" when the truth is "complete, except for neon".
 */
function coverageBySlice(residual, groups) {
  return groups.map(({ saturation, start, end }) => {
    let sum = 0;
    let within = 0;
    for (let i = start; i < end; i++) {
      sum += residual[i];
      if (residual[i] <= BANDING_DE) within++;
    }
    const n = Math.max(1, end - start);
    return { saturation, mean: sum / n, within: within / n };
  });
}

// ---------------------------------------------------------------------------
// Enumerating blends
// ---------------------------------------------------------------------------

/** All integer weight splits of `denom` into `arity` positive parts, in steps of `step`. */
function compositions(denom, arity, step) {
  const out = [];
  const walk = (left, parts) => {
    if (parts.length === arity - 1) {
      if (left >= step) out.push([...parts, left]);
      return;
    }
    for (let w = step; w <= left - step * (arity - 1 - parts.length); w += step) {
      walk(left - w, [...parts, w]);
    }
  };
  walk(denom, []);
  return out;
}

function makeBlend(id, linears, matrix, k, entries, weights) {
  const { lab, rgb8 } = blendColor(linears, entries, weights);
  return {
    id,
    entries,
    weights,
    arity: entries.length,
    lab,
    rgb8,
    hex: rgb8ToHex(rgb8),
    roughness: spreadOf(matrix, k, entries),
  };
}

/**
 * Build the reachable set.
 *
 * Pairs are **exhaustive** — every pair of palette colours at every sixteenth — because that is
 * the arity an artist reaches for and 496 pairs at K=32 is a real, showable catalogue. Triples
 * and quads cannot be: K=64 gives 41,664 triples and 635,376 quads *before* ratios. They are
 * generated where they can actually help instead, then ranked, which is the honest form of "show
 * the combinations that unlock a colour you do not otherwise have":
 *
 *   1. Find the sample points the pairs still miss.
 *   2. Around each, take the palette colours nearest it and enumerate their N-way combinations.
 *   3. Keep the ones that measurably improve the nearest-reachable distance, best first.
 *
 * A blind sweep would spend all its time on combinations that land where a pair already sits.
 * This spends it where the palette is actually short — and if it comes back empty, that is a
 * finding worth reporting, not a failure.
 */
export function buildReach(palette, options = {}) {
  const opts = { ...DEFAULTS, ...options };
  const labs = entryLabs(palette);
  const matrix = deltaMatrix(labs);
  const linears = entryLinears(palette);
  const k = palette.entries.length;
  const { labs: samples, groups } = colorSpaceSamples(opts);

  const blends = [];
  const push = (entries, weights) => {
    blends.push(makeBlend(blends.length, linears, matrix, k, entries, weights));
  };

  // Arity 1: the palette itself. A flat colour is a blend with one constituent and zero
  // roughness, which makes "the palette already has this" fall out of the same ranking instead
  // of being a special case everywhere downstream.
  for (let i = 0; i < k; i++) push([i], [BLEND_DENOM]);
  const flatCount = blends.length;

  // Arity 2: exhaustive, every pair at every sixteenth.
  for (let i = 0; i < k; i++) {
    for (let j = i + 1; j < k; j++) {
      for (let w = 1; w < BLEND_DENOM; w++) push([i, j], [w, BLEND_DENOM - w]);
    }
  }

  const flat = dedupe(blends.slice(0, flatCount), opts.dedupeCell);
  const pairSet = dedupe(blends, opts.dedupeCell);
  const pairIndex = buildColorIndex(pairSet.map((b) => b.lab));
  const pairCoverage = coverageAgainst(pairIndex, samples);

  const nWay = opts.maxArity >= 3
    ? findNWayBlends(palette, { linears, matrix, samples, pairIndex, pairCoverage, opts })
    : [];
  for (const b of nWay) { b.id = blends.length; blends.push(b); }

  const kept = dedupe(blends, opts.dedupeCell);
  kept.forEach((b, i) => { b.id = i; });
  const index = buildColorIndex(kept.map((b) => b.lab));

  const flatIndex = buildColorIndex(flat.map((b) => b.lab));
  const flatCoverage = coverageAgainst(flatIndex, samples);
  const ditherCoverage = coverageAgainst(index, samples);

  const suggestions = suggestColors(palette, {
    samples, residual: ditherCoverage.residual, linears, matrix, index, blends: kept, opts,
  });

  const floor = opts.hullTrials === 0 ? null : hullFloor(palette, samples, { trials: opts.hullTrials, seed: opts.seed });

  return {
    palette,
    blends: kept,
    index,
    samples,
    groups,
    residual: ditherCoverage.residual,
    suggestions,
    stats: {
      k,
      candidates: blends.length,
      distinct: kept.length,
      byArity: countBy(kept, (b) => b.arity),
      flat: strip(flatCoverage),
      pairs: strip(pairCoverage),
      dithered: strip(ditherCoverage),
      // The best any dithering could do with these colours. When `dithered` is close to it the
      // remaining banding is the palette's to fix, not the dithering's — which is exactly what
      // the suggestions below are for.
      floor,
      flatBySlice: coverageBySlice(flatCoverage.residual, groups),
      ditheredBySlice: coverageBySlice(ditherCoverage.residual, groups),
    },
  };
}

function strip({ mean, within, worst }) {
  return { mean, within, worst };
}

function countBy(items, key) {
  const out = {};
  for (const item of items) {
    const k = key(item);
    out[k] = (out[k] ?? 0) + 1;
  }
  return out;
}

/**
 * Collapse blends that land on the same perceived colour, keeping the one that reads cleanest.
 *
 * Many different recipes reach the same colour — 8:8 of A and B, and 4:4:4:4 of four things
 * between them. Showing all of them would bury the useful answer, so the survivor is the lowest
 * roughness, then the lowest arity: **the simplest way to get that colour**. A palette entry
 * (roughness 0, arity 1) therefore always beats a dither that imitates it, which is what makes
 * "you already have this colour" the answer whenever it is true.
 */
function dedupe(blends, cell) {
  const best = new Map();
  for (const b of blends) {
    const key = `${Math.round(b.lab[0] / cell)},${Math.round(b.lab[1] / cell)},${Math.round(b.lab[2] / cell)}`;
    const hit = best.get(key);
    if (!hit
      || b.roughness < hit.roughness
      || (b.roughness === hit.roughness && b.arity < hit.arity)) best.set(key, b);
  }
  return [...best.values()].sort((a, b) => a.arity - b.arity || a.roughness - b.roughness || a.id - b.id);
}

/** How many palette colours around a gap are considered as N-way constituents. */
const NEIGHBOURHOOD = 6;

/**
 * Triples and quads, generated where the pairs fall short and ranked by how much they close the
 * gap. See `buildReach` for why this is targeted rather than exhaustive.
 */
function findNWayBlends(palette, { linears, matrix, samples, pairIndex, pairCoverage, opts }) {
  const k = palette.entries.length;
  const labs = entryLabs(palette);

  // The gaps, worst first, deduped so one wide gap does not claim the whole budget.
  const gaps = [];
  const seen = new Set();
  const order = [...samples.keys()].sort((a, b) => pairCoverage.residual[b] - pairCoverage.residual[a]);
  for (const i of order) {
    if (pairCoverage.residual[i] <= BANDING_DE / 2) break;
    const lab = samples[i];
    const key = `${Math.round(lab[0] / 0.03)},${Math.round(lab[1] / 0.03)},${Math.round(lab[2] / 0.03)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    gaps.push({ lab, residual: pairCoverage.residual[i] });
    if (gaps.length >= 400) break;
  }
  if (!gaps.length) return [];

  const triples = compositions(BLEND_DENOM, 3, 2);
  const quads = opts.maxArity >= 4 ? compositions(BLEND_DENOM, 4, 2) : [];
  const found = new Map();

  for (const gap of gaps) {
    const near = nearestEntries(labs, gap.lab, Math.min(NEIGHBOURHOOD, k));
    for (const [combo, weightSets] of comboSets(near, triples, quads, opts.maxArity)) {
      if (spreadOf(matrix, k, combo) > opts.spreadCap) continue;
      for (const weights of weightSets) {
        const { lab, rgb8 } = blendColor(linears, combo, weights);
        const gain = gap.residual - deltaEOK(lab, gap.lab);
        if (gain <= 0) continue;
        const key = `${combo.join('.')}:${weights.join('.')}`;
        const hit = found.get(key);
        if (hit) { hit.gain = Math.max(hit.gain, gain); continue; }
        found.set(key, {
          entries: combo,
          weights,
          arity: combo.length,
          lab,
          rgb8,
          hex: rgb8ToHex(rgb8),
          roughness: spreadOf(matrix, k, combo),
          gain,
        });
      }
    }
  }

  return [...found.values()]
    .sort((a, b) => b.gain - a.gain)
    .slice(0, opts.nWayBudget)
    .map((b, i) => ({ ...b, id: -1 - i }));
}

/** The `n` palette entries nearest an OKLab colour. */
function nearestEntries(labs, lab, n) {
  return labs
    .map((l, i) => [i, deltaEOK(l, lab)])
    .sort((a, b) => a[1] - b[1])
    .slice(0, n)
    .map(([i]) => i);
}

/** Every 3- and 4-subset of a small neighbourhood, paired with its weight ladder. */
function* comboSets(near, triples, quads, maxArity) {
  const n = near.length;
  for (let a = 0; a < n; a++) {
    for (let b = a + 1; b < n; b++) {
      for (let c = b + 1; c < n; c++) {
        yield [[near[a], near[b], near[c]], triples];
        if (maxArity < 4) continue;
        for (let d = c + 1; d < n; d++) yield [[near[a], near[b], near[c], near[d]], quads];
      }
    }
  }
}

// ---------------------------------------------------------------------------
// What to add when dithering still cannot reach it
// ---------------------------------------------------------------------------

/**
 * The colours that would most close the remaining gaps if added to the palette.
 *
 * Weighted k-means over the still-uncovered sample points (weight = how badly they are missed),
 * seeded k-means++ style from the seeded PRNG. Each centroid is put through `makeRealize` from
 * the generator, so a suggestion is a **legal** colour on this palette's bit-depth grid and
 * gamut-mapping mode rather than an ideal that could not be produced.
 *
 * The improvement figure is recomputed against the reachable set the addition would actually
 * create — including every new blend the added colour makes possible, since that is most of what
 * adding a colour buys. Estimating it would be the easy way to overstate it.
 */
export function suggestColors(palette, { samples, residual, linears, matrix, blends, opts }) {
  const n = opts.suggestions;
  if (!n) return [];
  const picked = [];
  for (let i = 0; i < samples.length; i++) if (residual[i] > BANDING_DE) picked.push(i);
  if (picked.length < n) return [];

  const rng = makeRng(opts.seed);
  const centroids = kmeans(picked.map((i) => samples[i]), picked.map((i) => residual[i]), n, rng);
  const realize = makeRealize(palette.params);

  return centroids.map((c) => {
    const { L, C, h } = oklabToOklch(c[0], c[1], c[2]);
    const made = realize({ L, C, h });
    // What the palette would reach with this colour in it: every existing blend, plus every
    // pair between the new colour and each existing entry, at every sixteenth.
    const extraLinears = [...linears];
    const newIndex = extraLinears.length;
    const s = rgb8ToSrgb(made.rgb8);
    extraLinears.push([srgbToLinear(s[0]), srgbToLinear(s[1]), srgbToLinear(s[2])]);
    const extended = blends.map((b) => b.lab);
    extended.push(made.lab);
    for (let i = 0; i < linears.length; i++) {
      for (let w = 1; w < BLEND_DENOM; w++) {
        extended.push(blendColor(extraLinears, [i, newIndex], [w, BLEND_DENOM - w]).lab);
      }
    }
    const after = coverageAgainst(buildColorIndex(extended), samples);
    return { hex: made.hex, rgb8: made.rgb8, lab: made.lab, oklch: made.actual, after: strip(after) };
  }).sort((a, b) => a.after.mean - b.after.mean);
}

/** Weighted k-means in OKLab, k-means++ seeded from the supplied PRNG. */
function kmeans(points, weights, k, rng, iterations = 12) {
  const centroids = [points[Math.min(points.length - 1, Math.floor(rng() * points.length))]];
  while (centroids.length < k) {
    const d2 = points.map((p, i) => {
      let best = Infinity;
      for (const c of centroids) {
        const d = (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2;
        if (d < best) best = d;
      }
      return best * weights[i];
    });
    // Weighted pick proportional to squared distance — k-means++ without the bias of taking the
    // single furthest point, which lands on outliers.
    const total = d2.reduce((a, b) => a + b, 0);
    let t = rng() * total;
    let chosen = points.length - 1;
    for (let i = 0; i < points.length; i++) { t -= d2[i]; if (t <= 0) { chosen = i; break; } }
    centroids.push(points[chosen]);
  }

  let current = centroids.map((c) => [...c]);
  for (let it = 0; it < iterations; it++) {
    const sums = current.map(() => [0, 0, 0, 0]);
    for (let i = 0; i < points.length; i++) {
      let best = 0;
      let bestD = Infinity;
      for (let c = 0; c < current.length; c++) {
        const d = (points[i][0] - current[c][0]) ** 2
          + (points[i][1] - current[c][1]) ** 2
          + (points[i][2] - current[c][2]) ** 2;
        if (d < bestD) { bestD = d; best = c; }
      }
      const w = weights[i];
      sums[best][0] += points[i][0] * w;
      sums[best][1] += points[i][1] * w;
      sums[best][2] += points[i][2] * w;
      sums[best][3] += w;
    }
    current = sums.map((s, c) => (s[3] > 0 ? [s[0] / s[3], s[1] / s[3], s[2] / s[3]] : current[c]));
  }
  return current;
}

// ---------------------------------------------------------------------------
// The reach map
// ---------------------------------------------------------------------------

/**
 * One saturation slice of the reachable-colour map: the same `mapSample` hue×lightness geometry as
 * `buildColorMap`, but coloured in **OKHSL** (see the note at the top of this file) and painted with
 * the nearest *reachable* colour instead of the nearest palette colour.
 *
 * OKHSL is what makes the reference beside it band-free; the reachable map shares it so the two
 * panels — and the outlined third — are the same colour at the same position, and the comparison is
 * exact. Every picker map uses OKHSL now (`colorspace.js` too, since 2026-07-24), so a colour also
 * keeps its position when flipping to the `map-rect`/`map-polar` views.
 *
 * Returns per-pixel blend ids and the per-pixel ΔE, so the sheet can mark the regions that are still
 * out of reach instead of claiming them.
 */
export function buildReachMap(reach, { geometry = 'rect', saturation = 1, size = null } = {}) {
  const dims = size ?? { w: 384, h: 192 };
  const { w, h } = dims;
  const ids = new Int32Array(w * h).fill(-1);
  const error = new Float32Array(w * h);
  let sum = 0;
  let count = 0;
  let within = 0;
  const shown = new Set();

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const hsl = mapSample(geometry, x, y, w, h, saturation);
      if (!hsl) continue;
      const lab = srgbToOklab(okhslCached(hsl.h, hsl.s, hsl.l));
      const { index, dist } = reach.index.nearest(lab[0], lab[1], lab[2]);
      const at = y * w + x;
      ids[at] = index;
      error[at] = dist;
      shown.add(index);
      sum += dist;
      count++;
      if (dist <= BANDING_DE) within++;
    }
  }

  return {
    geometry,
    saturation,
    w,
    h,
    ids,
    error,
    shown,
    mean: count ? sum / count : 0,
    within: count ? within / count : 0,
  };
}

/**
 * The **complete** colormap at one saturation, painted with the true colour of every position —
 * palette-agnostic, the ideal the reach map is measured against.
 *
 * This is the reference an artist compares the reachable map to. Where the reach map is dark and
 * this is bright, the palette is genuinely short there; where the two agree, dithering has closed
 * the gap. It depends only on the geometry and saturation, never on the palette, so the same
 * reference sits beside every palette's map — and it is drawn in **OKHSL** (see the note at the top
 * of this file), so it is a smooth, band-free gradient rather than the ridged HSL one.
 *
 * Returns packed RGB per pixel (`(r<<16)|(g<<8)|b`), or -1 outside the shape.
 */
export function buildReferenceSlice({ geometry = 'rect', saturation = 1, size }) {
  const { w, h } = size;
  const rgb = new Int32Array(w * h).fill(-1);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const hsl = mapSample(geometry, x, y, w, h, saturation);
      if (!hsl) continue;
      const c = srgbToRgb8(okhslCached(hsl.h, hsl.s, hsl.l));
      rgb[y * w + x] = (c[0] << 16) | (c[1] << 8) | c[2];
    }
  }
  return { geometry, saturation, w, h, rgb };
}

/** Every default saturation slice of one geometry. */
export function buildReachSlices(reach, { geometry = 'rect', saturations = DEFAULT_SATURATIONS, size = null } = {}) {
  const slices = saturations.map((saturation) => buildReachMap(reach, { geometry, saturation, size }));
  const shown = new Set();
  for (const s of slices) for (const id of s.shown) shown.add(id);
  return {
    geometry,
    slices,
    shown,
    mean: slices.reduce((a, s) => a + s.mean, 0) / slices.length,
    within: slices.reduce((a, s) => a + s.within, 0) / slices.length,
  };
}

// ---------------------------------------------------------------------------
// The catalogue — every dithering option, laid out to be read rather than searched
// ---------------------------------------------------------------------------

/**
 * The palette's ramps: entries sharing a layer and a hue family, in lightness-step order.
 *
 * Derived from `step`/`steps` on the entries rather than from `src/scenes/util.js`, because
 * `src/core/` may not import `src/scenes/` (ARCHITECTURE §11).
 */
export function rampsOf(palette) {
  const groups = new Map();
  palette.entries.forEach((e, i) => {
    if (e.steps <= 1) return;
    const key = `${e.layer}:${e.hueIndex}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(i);
  });
  return [...groups.entries()]
    .map(([key, entries]) => ({
      key,
      layer: key.split(':')[0],
      entries: entries.sort((a, b) => palette.entries[a].step - palette.entries[b].step),
    }))
    .filter((r) => r.entries.length >= 2);
}

/** The ratio ladder the catalogue walks: every other sixteenth, so a row is seven patches. */
export const CATALOGUE_RATIOS = [2, 4, 6, 8, 10, 12, 14];

const CELL_LIMIT = 8; // patches per catalogue row — wider than this and the sheet stops fitting

/**
 * Every dithering option, grouped so an artist can *find* one rather than scroll past it.
 *
 * This is the deliberately comprehensive half of the view, and it is separate from the reach map
 * on purpose. The map only ever shows the blend that best reaches a colour, so it hides the
 * fourteen patterns and the dozen ratios that reach *nearly* the same place — which are exactly
 * what someone choosing a texture wants to compare. The sections answer different questions:
 *
 *   * **PATTERNS** — what does each pattern family look like, at every ratio it can express.
 *   * **RAMP BLENDS** — the everyday case: adjacent shades of one ramp, which is where dithering
 *     buys smooth shading rather than a new hue.
 *   * **CONTRAST BLENDS** — the far-apart pairs. Included on purpose and labelled honestly: these
 *     reach colours nothing else can, and they read as texture rather than as a flat tone.
 *   * **THREE AND FOUR COLOURS** — multicolour blends in one space, both inside a ramp and across
 *     hue families.
 *   * **UNLOCKS** — the N-way blends that measurably reach a colour no pair does. Often a short
 *     list, which is itself the finding: pairs already reach most of what the palette can.
 */
export function catalogueSections(reach, { ratios = CATALOGUE_RATIOS, maxRows = 10 } = {}) {
  const { palette, blends } = reach;
  const linears = entryLinears(palette);
  const labs = entryLabs(palette);
  const matrix = deltaMatrix(labs);
  const k = palette.entries.length;

  const cell = (entries, weights, pattern = null) => {
    const { lab, rgb8 } = blendColor(linears, entries, weights);
    return {
      entries,
      weights,
      pattern: pattern ?? preferredPattern(weights),
      arity: entries.length,
      lab,
      rgb8,
      hex: rgb8ToHex(rgb8),
      roughness: spreadOf(matrix, k, entries),
    };
  };

  const sections = [];

  // --- PATTERNS ------------------------------------------------------------
  // One pair, every pattern, every ratio that pattern can express. The pair is chosen for
  // legibility rather than beauty: the pattern is the subject, so the two colours have to be far
  // enough apart to see the tile at 1x.
  const showcase = mostSeparatedPair(matrix, k);
  sections.push({
    id: 'patterns',
    title: 'EVERY PATTERN',
    note: `${palette.entries[showcase[0]].hex} + ${palette.entries[showcase[1]].hex} - `
      + 'THE SAME TWO COLOURS IN EVERY PATTERN. THE COLOUR IS IDENTICAL DOWN EACH COLUMN; ONLY THE TEXTURE CHANGES',
    rows: DITHER_PATTERNS.map((pattern) => ({
      label: `${pattern.title.toUpperCase()} (${pattern.n}x${pattern.n})`,
      cells: ratios
        .filter((w) => patternWeights(pattern, [w, BLEND_DENOM - w]) !== null)
        .slice(0, CELL_LIMIT)
        .map((w) => cell(showcase, [w, BLEND_DENOM - w], pattern)),
    })),
  });

  // --- RAMP BLENDS ---------------------------------------------------------
  const ramps = rampsOf(palette).slice(0, maxRows);
  if (ramps.length) {
    sections.push({
      id: 'ramps',
      title: 'RAMP BLENDS - SMOOTH SHADING',
      note: 'ADJACENT STEPS OF ONE RAMP. THIS IS WHERE DITHERING BUYS EXTRA SHADES RATHER THAN NEW HUES',
      rows: ramps.map((ramp) => {
        const cells = [];
        for (let s = 0; s + 1 < ramp.entries.length && cells.length < CELL_LIMIT; s++) {
          const pair = [ramp.entries[s], ramp.entries[s + 1]];
          for (const w of [4, 8, 12]) {
            if (cells.length >= CELL_LIMIT) break;
            cells.push(cell(pair, [w, BLEND_DENOM - w]));
          }
        }
        return { label: `${ramp.layer.toUpperCase()} RAMP ${ramp.key.split(':')[1]}`, cells };
      }),
    });
  }

  // --- CONTRAST BLENDS -----------------------------------------------------
  const contrast = topPairs(matrix, k, maxRows, (a, b) => de(matrix, k, b[0], b[1]) - de(matrix, k, a[0], a[1]));
  sections.push({
    id: 'contrast',
    title: 'CONTRAST BLENDS - FAR-APART PAIRS',
    note: 'THE PAIRS NOTHING ELSE REACHES. THESE READ AS VISIBLE TEXTURE, NOT AS A FLAT TONE - USE THEM FOR GRIT, RUST AND NOISE',
    rows: contrast.map(([i, j]) => ({
      label: `${palette.entries[i].hex} + ${palette.entries[j].hex}  dE ${de(matrix, k, i, j).toFixed(0)}`,
      cells: ratios.slice(0, CELL_LIMIT).map((w) => cell([i, j], [w, BLEND_DENOM - w])),
    })),
  });

  // --- THREE AND FOUR COLOURS ----------------------------------------------
  const multi = multicolourRows(palette, ramps, maxRows);
  if (multi.length) {
    sections.push({
      id: 'multicolour',
      title: 'THREE AND FOUR COLOURS IN ONE SPACE',
      note: 'MORE THAN TWO COLOURS PER TILE. FOUR IS THE PRACTICAL CEILING - BEYOND IT A TILE READS AS NOISE, NOT AS A COLOUR',
      rows: multi.map(({ label, combos }) => ({
        label,
        cells: combos.slice(0, CELL_LIMIT).map(({ entries, weights }) => cell(entries, weights)),
      })),
    });
  }

  // --- UNLOCKS -------------------------------------------------------------
  const unlocks = blends.filter((b) => b.arity >= 3 && b.gain > 0).sort((a, b) => b.gain - a.gain);
  sections.push({
    id: 'unlocks',
    title: 'WHAT MULTICOLOUR UNLOCKS',
    note: unlocks.length
      ? 'THESE THREE- AND FOUR-WAY BLENDS REACH A COLOUR NO PAIR DOES. BEST FIRST'
      : 'NOTHING. EVERY COLOUR THREE OR FOUR WAYS CAN REACH, A PAIR ALREADY REACHES - WHICH IS THE USUAL RESULT',
    rows: chunk(unlocks.slice(0, maxRows * CELL_LIMIT), CELL_LIMIT).map((group, n) => ({
      label: `RANK ${n * CELL_LIMIT + 1}-${n * CELL_LIMIT + group.length}`,
      cells: group.map((b) => cell(b.entries, b.weights)),
    })),
  });

  return sections.filter((s) => s.rows.some((r) => r.cells.length));
}

/** The two palette colours furthest apart — the pair that makes a pattern easiest to read. */
function mostSeparatedPair(matrix, k) {
  let best = [0, Math.min(1, k - 1)];
  let bestD = -1;
  for (let i = 0; i < k; i++) {
    for (let j = i + 1; j < k; j++) {
      const d = de(matrix, k, i, j);
      if (d > bestD) { bestD = d; best = [i, j]; }
    }
  }
  return best;
}

/** The `n` pairs that come first under `compare`, no colour used more than twice. */
function topPairs(matrix, k, n, compare) {
  const all = [];
  for (let i = 0; i < k; i++) for (let j = i + 1; j < k; j++) all.push([i, j]);
  all.sort(compare);
  const used = new Map();
  const out = [];
  for (const pair of all) {
    if (out.length >= n) break;
    // Spread the rows across the palette instead of showing one loud colour ten times.
    if ((used.get(pair[0]) ?? 0) >= 2 || (used.get(pair[1]) ?? 0) >= 2) continue;
    used.set(pair[0], (used.get(pair[0]) ?? 0) + 1);
    used.set(pair[1], (used.get(pair[1]) ?? 0) + 1);
    out.push(pair);
  }
  return out;
}

/**
 * Multicolour rows: three consecutive steps of each ramp (the smooth case), then cross-hue
 * triples and quads built from one step of each of the first few ramps (the case that produces a
 * colour no single ramp holds).
 */
function multicolourRows(palette, ramps, maxRows) {
  const rows = [];
  const triples = compositions(BLEND_DENOM, 3, 2).filter((w) => w.every((v) => v >= 4));
  const quads = [[4, 4, 4, 4], [8, 4, 2, 2], [2, 8, 4, 2], [2, 2, 8, 4], [6, 6, 2, 2]];

  for (const ramp of ramps) {
    if (rows.length >= maxRows) break;
    if (ramp.entries.length < 3) continue;
    const trio = ramp.entries.slice(0, 3);
    rows.push({
      label: `${ramp.layer.toUpperCase()} RAMP ${ramp.key.split(':')[1]} - 3 STEPS`,
      combos: triples.map((weights) => ({ entries: trio, weights })),
    });
  }

  // Cross-hue: one mid step from each ramp, taken in order, so the combination spans hue families
  // rather than lightness — the multicolour case a single ramp cannot produce.
  const mids = ramps.map((r) => r.entries[Math.floor(r.entries.length / 2)]);
  if (mids.length >= 3 && rows.length < maxRows) {
    rows.push({
      label: 'CROSS-HUE - 3 COLOURS',
      combos: triples.slice(0, CELL_LIMIT).map((weights) => ({ entries: mids.slice(0, 3), weights })),
    });
  }
  if (mids.length >= 4 && rows.length < maxRows) {
    rows.push({
      label: 'CROSS-HUE - 4 COLOURS',
      combos: quads.map((weights) => ({ entries: mids.slice(0, 4), weights })),
    });
  }
  return rows;
}

function chunk(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/** A blend as the one-line recipe the picker shows on hover. */
export function recipeText(reach, blend) {
  const { palette } = reach;
  const parts = blend.entries.map((e, i) => {
    const pct = Math.round((blend.weights[i] / BLEND_DENOM) * 100);
    return `${pct}% ${palette.entries[e].hex}`;
  });
  if (blend.arity === 1) return `${palette.entries[blend.entries[0]].hex} - PALETTE COLOUR, NO DITHER NEEDED`;
  const pattern = preferredPattern(blend.weights);
  return `${parts.join(' + ')} - ${pattern.title.toUpperCase()} = ${blend.hex} - ${roughnessBand(blend.roughness).label}`;
}
