// Indexed remap (PLAN §19.1) — the recolour path for pixel art.
//
// **Per-pixel nearest matching is the wrong algorithm here.** It decides every pixel
// independently, so one source colour can land on different target colours in different
// places, which shreds outlines, anti-aliasing seams and ramp continuity — exactly the
// things that make expert pixel art good (ARCHITECTURE §12.2). So the mapping is decided
// once, on the *source's palette*, and applied as a lookup. The property that matters is
// asserted directly in the tests: a source colour maps to the same target colour everywhere.

import { deltaEOK, rgb8ToOklab } from '../oklch.js';
import { mapColors, uniqueColors } from './image.js';

/** How the source palette is matched to the target palette. */
export const REMAP_MATCH = ['delta-e', 'lightness-rank', 'optimal'];

/** What happens when the source has more colours than the target. */
export const REMAP_OVERFLOW = ['share', 'merge'];

const MERGE_ITERATIONS = 12;

/**
 * Recolour an image by remapping its palette. Returns
 * `{ image, mapping, sourceColors, targets }`, where `mapping` is source-colour key →
 * target entry index — the assignment itself, exposed because it is the thing worth testing.
 */
export function recolorIndexed(image, entries, {
  match = 'delta-e', preserveOrder = false, overflow = 'share',
} = {}) {
  const { colors } = uniqueColors(image);
  const mapping = buildIndexedMapping(colors, entries, { match, preserveOrder, overflow });
  const rgbs = entries.map((t) => t.rgb8);
  return {
    image: mapColors(image, (key) => rgbs[mapping.get(key)]),
    mapping,
    sourceColors: colors,
    targets: entries.length,
  };
}

/**
 * Decide source colour → target index for every source colour. Split out from the pixel
 * work because every interesting property of a remap — stability, monotonicity, whether a
 * target was reused — is a property of this map and nothing else.
 */
export function buildIndexedMapping(colors, entries, {
  match = 'delta-e', preserveOrder = false, overflow = 'share',
} = {}) {
  const k = entries.length;
  if (!k) throw new Error('recolorIndexed: the target palette is empty');

  // `merge` clusters the source down to the target's size *first*, so the assignment sees
  // a palette it can actually cover one-to-one. `share` skips that and lets targets repeat.
  const groups = overflow === 'merge' && colors.length > k ? clusterColors(colors, k) : null;
  const src = groups
    ? groups.map((g) => ({ lab: g.lab, count: g.count }))
    : colors.map((c) => ({ lab: rgb8ToOklab(c.rgb), count: c.count }));

  const assignment = assign(src, entries, { match, preserveOrder });

  const out = new Map();
  if (groups) {
    groups.forEach((g, gi) => {
      for (const key of g.keys) out.set(key, assignment[gi]);
    });
  } else {
    colors.forEach((c, i) => out.set(c.key, assignment[i]));
  }
  return out;
}

/** One target index per source colour, by the chosen strategy. */
function assign(src, entries, { match, preserveOrder }) {
  const labs = entries.map((t) => t.lab);

  // `lightness-rank` is positional by construction, so it is already monotonic in L —
  // `preserveOrder` has nothing left to enforce and is deliberately a no-op for it.
  if (match === 'lightness-rank') return byLightnessRank(src, labs);

  const cost = costMatrix(src, labs);
  if (preserveOrder) {
    // The constraint subsumes the strategy: a minimum-cost *monotone* mapping is a single
    // global optimisation either way. What still differs is reuse — `optimal` keeps its
    // promise that no target repeats while unused ones remain, so its mapping is strictly
    // increasing whenever the source fits inside the target.
    const strict = match === 'optimal' && src.length <= labs.length;
    return monotoneAssign(src, labs, cost, strict);
  }
  if (match === 'optimal') return optimalAssign(src, labs, cost);
  return src.map((_, i) => argmin(cost, i, labs.length));
}

/** Full ΔE cost matrix, source-major. */
function costMatrix(src, labs) {
  const cost = new Float64Array(src.length * labs.length);
  for (let i = 0; i < src.length; i++) {
    for (let j = 0; j < labs.length; j++) cost[i * labs.length + j] = deltaEOK(src[i].lab, labs[j]);
  }
  return cost;
}

/** Index of the cheapest target for source row `i`. */
function argmin(cost, i, k) {
  let best = 0;
  let bestV = Infinity;
  for (let j = 0; j < k; j++) {
    const v = cost[i * k + j];
    if (v < bestV) { bestV = v; best = j; }
  }
  return best;
}

/**
 * Sort both palettes by lightness and match by position. Hue is ignored entirely, which is
 * the point: it is the mode that survives a target palette with nothing in common with the
 * source, because the eye reads value structure first.
 */
function byLightnessRank(src, labs) {
  const srcOrder = order(src.map((s) => s.lab[0]));
  const tgtOrder = order(labs.map((l) => l[0]));
  const out = new Array(src.length);
  srcOrder.forEach((si, rank) => {
    const t = src.length === 1 ? 0 : Math.round((rank * (labs.length - 1)) / (src.length - 1));
    out[si] = tgtOrder[Math.min(labs.length - 1, t)];
  });
  return out;
}

/** Indices sorted by their value, ties broken by index so the order is deterministic. */
function order(values) {
  return values.map((v, i) => i).sort((a, b) => values[a] - values[b] || a - b);
}

/**
 * Minimum-total-ΔE assignment with no target reused while unused ones remain.
 *
 * When the source fits inside the target this is a plain rectangular assignment. When it
 * does not, the roles are swapped — every *target* claims a distinct source first, so the
 * whole target palette is guaranteed to appear — and the sources left over take their
 * nearest, which is the only thing left to do once every target is spoken for.
 */
function optimalAssign(src, labs, cost) {
  const n = src.length;
  const k = labs.length;
  if (n <= k) return [...hungarian(cost, n, k)];

  const flipped = new Float64Array(k * n);
  for (let j = 0; j < k; j++) for (let i = 0; i < n; i++) flipped[j * n + i] = cost[i * k + j];
  const targetToSource = hungarian(flipped, k, n);

  const out = new Array(n).fill(-1);
  targetToSource.forEach((si, j) => { out[si] = j; });
  for (let i = 0; i < n; i++) if (out[i] < 0) out[i] = argmin(cost, i, k);
  return out;
}

/**
 * Minimum-cost mapping that never moves backwards in lightness: sort both palettes by L,
 * then choose target ranks that only ever increase. This is `remap_preserve_order`, and it
 * is the knob that matters most in practice — it is what lets a palette with completely
 * different hues still read correctly, because the source's value structure survives intact.
 *
 * A dynamic program, not a repair pass: `dp[j]` is the best cost for the sources placed so
 * far with the last one at target rank ≤ j (or < j when repeats are forbidden).
 */
function monotoneAssign(src, labs, cost, strict) {
  const n = src.length;
  const k = labs.length;
  const srcOrder = order(src.map((s) => s.lab[0]));
  const tgtOrder = order(labs.map((l) => l[0]));

  const INF = Infinity;
  // `prevBest[j]` / `prevArg[j]`: cheapest way to place the previous source at rank ≤ j,
  // and the rank that achieved it. Prefix-minimised, so each step below is O(1).
  let prevBest = null;
  let prevArg = null;
  const from = [];

  for (let i = 0; i < n; i++) {
    const row = new Float64Array(k).fill(INF);
    const back = new Int32Array(k).fill(-1);
    for (let j = 0; j < k; j++) {
      const c = cost[srcOrder[i] * k + tgtOrder[j]];
      if (i === 0) {
        row[j] = c;
      } else if (strict) {
        // No target may repeat, so the previous source must sit strictly lower.
        if (j > 0 && prevBest[j - 1] < INF) { row[j] = prevBest[j - 1] + c; back[j] = prevArg[j - 1]; }
      } else if (prevBest[j] < INF) {
        row[j] = prevBest[j] + c;
        back[j] = prevArg[j];
      }
    }
    const best = new Float64Array(k);
    const bestArg = new Int32Array(k);
    let m = INF;
    let mi = 0;
    for (let j = 0; j < k; j++) {
      if (row[j] < m) { m = row[j]; mi = j; }
      best[j] = m;
      bestArg[j] = mi;
    }
    from.push(back);
    prevBest = best;
    prevArg = bestArg;
  }

  // Walk back from the cheapest end state.
  const out = new Array(n);
  let j = prevArg[k - 1];
  for (let i = n - 1; i >= 0; i--) {
    out[srcOrder[i]] = tgtOrder[j];
    j = from[i][j];
  }
  return out;
}

/**
 * Weighted k-means in OKLab, seeded with the most frequent source colours and iterated to a
 * fixed count rather than to convergence, so it is deterministic. This is `remap_overflow:
 * merge` — clustering the source down before matching, instead of letting several source
 * colours share one target after it.
 */
function clusterColors(colors, k) {
  const labs = colors.map((c) => rgb8ToOklab(c.rgb));
  const centers = colors.slice(0, k).map((_, i) => labs[i].slice());
  const owner = new Int32Array(colors.length);

  for (let pass = 0; pass < MERGE_ITERATIONS; pass++) {
    let moved = false;
    for (let i = 0; i < labs.length; i++) {
      let best = 0;
      let bestD = Infinity;
      for (let c = 0; c < centers.length; c++) {
        const d = deltaEOK(labs[i], centers[c]);
        if (d < bestD) { bestD = d; best = c; }
      }
      if (owner[i] !== best) { owner[i] = best; moved = true; }
    }
    const sums = centers.map(() => [0, 0, 0, 0]);
    for (let i = 0; i < labs.length; i++) {
      const s = sums[owner[i]];
      const wgt = colors[i].count;
      s[0] += labs[i][0] * wgt; s[1] += labs[i][1] * wgt; s[2] += labs[i][2] * wgt; s[3] += wgt;
    }
    // An empty cluster keeps its seed rather than being dropped: the target it would have
    // claimed is one the recoloured image still needs somewhere to put.
    sums.forEach((s, c) => {
      if (s[3] > 0) centers[c] = [s[0] / s[3], s[1] / s[3], s[2] / s[3]];
    });
    if (!moved && pass > 0) break;
  }

  const groups = centers.map((lab) => ({ lab, keys: [], count: 0 }));
  colors.forEach((c, i) => {
    groups[owner[i]].keys.push(c.key);
    groups[owner[i]].count += c.count;
  });
  return groups;
}

/**
 * Rectangular assignment problem, O(n²m) shortest-augmenting-path (Jonker–Volgenant form).
 * `rows <= cols`; returns the column assigned to each row, minimizing the total cost.
 */
export function hungarian(cost, rows, cols) {
  const u = new Float64Array(rows + 1);
  const v = new Float64Array(cols + 1);
  const p = new Int32Array(cols + 1);
  const way = new Int32Array(cols + 1);

  for (let i = 1; i <= rows; i++) {
    p[0] = i;
    let j0 = 0;
    const minv = new Float64Array(cols + 1).fill(Infinity);
    const used = new Uint8Array(cols + 1);
    do {
      used[j0] = 1;
      const i0 = p[j0];
      let delta = Infinity;
      let j1 = 0;
      for (let j = 1; j <= cols; j++) {
        if (used[j]) continue;
        const cur = cost[(i0 - 1) * cols + (j - 1)] - u[i0] - v[j];
        if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
        if (minv[j] < delta) { delta = minv[j]; j1 = j; }
      }
      for (let j = 0; j <= cols; j++) {
        if (used[j]) { u[p[j]] += delta; v[j] -= delta; } else minv[j] -= delta;
      }
      j0 = j1;
    } while (p[j0] !== 0);
    do {
      const j1 = way[j0];
      p[j0] = p[j1];
      j0 = j1;
    } while (j0);
  }

  const out = new Int32Array(rows);
  for (let j = 1; j <= cols; j++) if (p[j] > 0) out[p[j] - 1] = j - 1;
  return out;
}
