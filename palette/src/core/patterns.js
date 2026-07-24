// Tileable dither patterns (PLAN §9.3, the dithering reference view).
//
// **One representation for every ordered pattern.** Bayer, clustered-dot halftone, blue
// noise, scanlines, brick, hand-placed checkerboards — all of them are an `n×n` grid whose
// cells have been put in *some order*, and the pattern is entirely determined by that order.
// So every pattern here is a permutation of `0 … n²−1` and nothing else. That makes arity and
// ratio free parameters of one function rather than a special case per pattern: to mix three
// colours at 6:6:4 in a 4×4 tile you hand out the first 6 ranks to the first colour, the next
// 6 to the second and the last 4 to the third. The result is exact — a ratio is quantised to
// `k/n²` and nothing rounds — which is what lets the reference view claim a blend colour
// rather than approximate one.
//
// This is deliberately *not* `dither.js`. That module maps a source image onto a palette
// (error diffusion, threshold matching); this one describes patterns in the abstract, with no
// source image anywhere. `dither.js` derives its Bayer matrices from here so the two can
// never disagree.

import { makeRng } from './rng.js';

/** Families, in the order the reference sheet groups them. */
export const PATTERN_FAMILIES = ['bayer', 'noise', 'halftone', 'artist'];

/**
 * Bayer ordering, generated recursively: `B₂ₙ = 4·Bₙ + [[0,2],[3,1]]`.
 *
 * Returns a flat `Int32Array` of rank per cell. The recursion is the definition, so 2/4/8/16
 * come from one place and `dither.js`'s published 4×4 and 8×8 matrices are checked against it
 * rather than maintained beside it.
 */
export function bayerOrder(n) {
  if (n < 2 || (n & (n - 1)) !== 0) throw new Error(`bayer size must be a power of two >= 2, got ${n}`);
  let size = 1;
  let m = new Int32Array([0]);
  while (size < n) {
    const next = new Int32Array(size * size * 4);
    const w = size * 2;
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const base = 4 * m[y * size + x];
        next[y * w + x] = base;
        next[y * w + x + size] = base + 2;
        next[(y + size) * w + x] = base + 3;
        next[(y + size) * w + x + size] = base + 1;
      }
    }
    m = next;
    size = w;
  }
  return m;
}

/**
 * Clustered-dot halftone: rank by distance from the tile centre, so a growing share fills as
 * one solid dot rather than dispersing. This is what print halftones and the "blobby" pixel-art
 * dithers do, and it survives being viewed close up where Bayer reads as a grid.
 *
 * The tie-break is the cell index, so the ordering is a pure function of `n`.
 */
export function halftoneOrder(n) {
  const c = (n - 1) / 2;
  const cells = [];
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      // Offset the centre by a half cell on one axis so the four cells nearest the middle do
      // not all tie, which would make the first four ranks an artefact of the tie-break.
      const dx = x - c;
      const dy = y - c + 0.5;
      cells.push([y * n + x, dx * dx + dy * dy]);
    }
  }
  cells.sort((a, b) => a[1] - b[1] || a[0] - b[0]);
  const out = new Int32Array(n * n);
  cells.forEach(([cell], rank) => { out[cell] = rank; });
  return out;
}

/**
 * Void-and-cluster blue noise. Ranks cells so that at *every* threshold the filled set is as
 * evenly spread as possible with no repeating grid — the property Bayer lacks, and the reason
 * blue noise reads as texture rather than as a visible weave.
 *
 * Deterministic: the initial scatter comes from `makeRng`, never `Math.random` (the codebase
 * rule), so a pattern is the same in the browser, under `node --test` and in the renderer.
 */
export function blueNoiseOrder(n, seed = 0x8DEF) {
  const total = n * n;
  const rng = makeRng(seed);
  const filled = new Uint8Array(total);
  // Energy field: how "clustered" each cell currently is. A cell's energy is the sum of a
  // gaussian falloff from every filled cell, wrapped toroidally so the tile stays seamless.
  const energy = new Float64Array(total);
  const sigma2 = 2 * 1.5 * 1.5;
  const kernel = [];
  const reach = Math.min(n - 1, 6);
  for (let dy = -reach; dy <= reach; dy++) {
    for (let dx = -reach; dx <= reach; dx++) {
      if (!dx && !dy) continue;
      kernel.push([dx, dy, Math.exp(-(dx * dx + dy * dy) / sigma2)]);
    }
  }
  const stamp = (cell, sign) => {
    const cx = cell % n;
    const cy = (cell / n) | 0;
    for (const [dx, dy, k] of kernel) {
      const x = (cx + dx + n) % n;
      const y = (cy + dy + n) % n;
      energy[y * n + x] += sign * k;
    }
  };
  const pickExtreme = (wantFilled, wantMax) => {
    let best = -1;
    let bestE = wantMax ? -Infinity : Infinity;
    for (let i = 0; i < total; i++) {
      if (!!filled[i] !== wantFilled) continue;
      const e = energy[i];
      if (best < 0 || (wantMax ? e > bestE : e < bestE)) { best = i; bestE = e; }
    }
    return best;
  };

  // 1. Scatter a tenth of the cells at random.
  const initial = Math.max(1, Math.round(total / 10));
  for (let placed = 0; placed < initial;) {
    const cell = Math.min(total - 1, Math.floor(rng() * total));
    if (filled[cell]) continue;
    filled[cell] = 1;
    stamp(cell, 1);
    placed++;
  }

  // 2. Relax it: repeatedly move the tightest cluster's member into the largest void, until
  //    doing so would just undo itself. That is what turns a random scatter into blue noise.
  for (let guard = 0; guard < total * 8; guard++) {
    const tightest = pickExtreme(true, true);
    filled[tightest] = 0;
    stamp(tightest, -1);
    const emptiest = pickExtreme(false, false);
    if (emptiest === tightest) { filled[tightest] = 1; stamp(tightest, 1); break; }
    filled[emptiest] = 1;
    stamp(emptiest, 1);
  }

  const order = new Int32Array(total).fill(-1);
  // 3. Rank the initial set downward: remove the tightest cluster member each time, and it
  //    takes the highest rank among the initial cells.
  const snapshot = Uint8Array.from(filled);
  let count = initial;
  while (count > 0) {
    const tightest = pickExtreme(true, true);
    filled[tightest] = 0;
    stamp(tightest, -1);
    order[tightest] = --count;
  }
  // 4. Rank the rest upward: fill the largest void each time.
  filled.set(snapshot);
  energy.fill(0);
  for (let i = 0; i < total; i++) if (filled[i]) stamp(i, 1);
  for (let rank = initial; rank < total; rank++) {
    const emptiest = pickExtreme(false, false);
    filled[emptiest] = 1;
    stamp(emptiest, 1);
    order[emptiest] = rank;
  }
  return order;
}

/** Rank cells by a key function, ties broken by cell index so the result is a pure function. */
function orderBy(n, key) {
  const cells = [];
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) cells.push([y * n + x, key(x, y)]);
  cells.sort((a, b) => a[1] - b[1] || a[0] - b[0]);
  const out = new Int32Array(n * n);
  cells.forEach(([cell], rank) => { out[cell] = rank; });
  return out;
}

/**
 * The patterns an artist can actually hand-place. Each is just a different ordering, which is
 * the whole point of the one-representation decision: a 50% checkerboard is `bayer2` at 2/4,
 * and scanlines are the same object with the cells ranked by row instead of by Bayer rank.
 */
const CHECKER = orderBy(4, (x, y) => ((x + y) % 2) * 16 + ((x * 5 + y * 3) % 8));
const HLINES = orderBy(4, (x, y) => y * 4 + ((x * 3) % 4));
const VLINES = orderBy(4, (x, y) => x * 4 + ((y * 3) % 4));
const DIAGONAL = orderBy(4, (x, y) => ((x + y) % 4) * 4 + ((x * 2 + y) % 4));
const BRICK = orderBy(4, (x, y) => (y % 2 ? (x + 2) % 4 : x) + (y % 2) * 4 + (y >> 1) * 8);
const SPARSE = orderBy(8, (x, y) => {
  // Widely spaced single pixels first — the "stipple" a pixel artist uses for a faint tint.
  const cx = (x * 5 + y * 3) % 8;
  const cy = (y * 5 + x * 3) % 8;
  return cx * 8 + cy;
});

/**
 * Every pattern the reference view offers, in sheet order.
 *
 * `n` is the tile edge, so `n²` is the number of ratio steps the pattern can express: a 2×2
 * tile gives quarters and nothing finer, a 16×16 gives 256ths. That is the real trade between
 * them — a big tile reaches more colours but its texture is coarser over a small sprite.
 */
export const DITHER_PATTERNS = [
  { id: 'bayer2', title: 'Bayer 2x2', family: 'bayer', n: 2, order: bayerOrder(2) },
  { id: 'bayer4', title: 'Bayer 4x4', family: 'bayer', n: 4, order: bayerOrder(4) },
  { id: 'bayer8', title: 'Bayer 8x8', family: 'bayer', n: 8, order: bayerOrder(8) },
  { id: 'bayer16', title: 'Bayer 16x16', family: 'bayer', n: 16, order: bayerOrder(16) },
  { id: 'bluenoise8', title: 'Blue noise 8x8', family: 'noise', n: 8, order: blueNoiseOrder(8) },
  { id: 'bluenoise16', title: 'Blue noise 16x16', family: 'noise', n: 16, order: blueNoiseOrder(16) },
  { id: 'halftone4', title: 'Halftone 4x4', family: 'halftone', n: 4, order: halftoneOrder(4) },
  { id: 'halftone8', title: 'Halftone 8x8', family: 'halftone', n: 8, order: halftoneOrder(8) },
  { id: 'checker', title: 'Checkerboard', family: 'artist', n: 4, order: CHECKER },
  { id: 'hlines', title: 'Horizontal lines', family: 'artist', n: 4, order: HLINES },
  { id: 'vlines', title: 'Vertical lines', family: 'artist', n: 4, order: VLINES },
  { id: 'diagonal', title: 'Diagonal lines', family: 'artist', n: 4, order: DIAGONAL },
  { id: 'brick', title: 'Brick / offset', family: 'artist', n: 4, order: BRICK },
  { id: 'sparse', title: 'Sparse stipple', family: 'artist', n: 8, order: SPARSE },
];

/** Look a pattern up by id. Throws rather than defaulting — a typo must not silently work. */
export function patternById(id) {
  const found = DITHER_PATTERNS.find((p) => p.id === id);
  if (!found) throw new Error(`unknown dither pattern: ${id}`);
  return found;
}

/**
 * Which colour slot each of the `n²` tile cells takes, given integer `weights` summing to `n²`.
 *
 * A cell of rank `r` takes the slot whose cumulative share `r` falls inside, so every slot gets
 * *exactly* its weight in cells — the property that makes a patch's blend colour computable
 * rather than measured.
 */
export function patternTile(pattern, weights) {
  const total = pattern.n * pattern.n;
  let sum = 0;
  for (const w of weights) {
    if (!Number.isInteger(w) || w < 0) throw new Error(`weights must be non-negative integers, got ${w}`);
    sum += w;
  }
  if (sum !== total) throw new Error(`weights must sum to ${total} for ${pattern.id}, got ${sum}`);

  // rank -> slot, via the cumulative shares.
  const slotOfRank = new Int32Array(total);
  let rank = 0;
  weights.forEach((w, slot) => { for (let i = 0; i < w; i++) slotOfRank[rank++] = slot; });

  const out = new Int32Array(total);
  for (let cell = 0; cell < total; cell++) out[cell] = slotOfRank[pattern.order[cell]];
  return out;
}

/**
 * A `w×h` patch of slot indices, the tile repeated. `ox`/`oy` shift the tile's phase, which
 * matters when several patches sit side by side: leaving them all in phase makes an accidental
 * larger pattern across the whole row.
 */
export function patternPatch(pattern, weights, w, h, { ox = 0, oy = 0 } = {}) {
  const tile = patternTile(pattern, weights);
  const { n } = pattern;
  const out = new Int32Array(w * h);
  for (let y = 0; y < h; y++) {
    const ty = (((y + oy) % n) + n) % n;
    for (let x = 0; x < w; x++) {
      const tx = (((x + ox) % n) + n) % n;
      out[y * w + x] = tile[ty * n + tx];
    }
  }
  return out;
}

/**
 * The integer weight splits a pattern can express for `arity` colours, at a requested
 * granularity.
 *
 * `steps` is how many even divisions of the tile to consider (7 gives eighths for a pair:
 * 1:7 … 7:1), which is the ratio ladder the reference sheet walks. Splits that do not divide
 * into the tile exactly are rounded to the tile and de-duplicated, so a 2×2 tile asked for
 * eighths honestly reports the three ratios it actually has instead of pretending to seven.
 */
export function weightLadder(pattern, arity, steps = 8) {
  const total = pattern.n * pattern.n;
  const seen = new Set();
  const out = [];
  const emit = (fractions) => {
    // Largest-remainder rounding, so the weights always sum to exactly `total`.
    const raw = fractions.map((f) => f * total);
    const w = raw.map(Math.floor);
    let left = total - w.reduce((a, b) => a + b, 0);
    const order = raw
      .map((r, i) => [i, r - Math.floor(r)])
      .sort((a, b) => b[1] - a[1] || a[0] - b[0]);
    for (let i = 0; left > 0; i = (i + 1) % order.length, left--) w[order[i][0]]++;
    if (w.some((v) => v === 0)) return; // a colour that gets no cells is not part of the blend
    const key = w.join(',');
    if (seen.has(key)) return;
    seen.add(key);
    out.push(w);
  };

  if (arity === 2) {
    for (let k = 1; k < steps; k++) emit([k / steps, 1 - k / steps]);
    return out;
  }
  // Three or four colours: equal shares, plus each colour in turn taking a dominant half.
  emit(new Array(arity).fill(1 / arity));
  for (let d = 0; d < arity; d++) {
    emit(new Array(arity).fill(0).map((_, i) => (i === d ? 0.5 : 0.5 / (arity - 1))));
  }
  return out;
}
