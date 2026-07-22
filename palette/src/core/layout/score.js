// Objective function and blob sizing for the picker layouts (PLAN §9).
//
// The picker exists because a colour is hard to find when its neighbours look nothing
// like it. So the objective is literal: the mean ΔE_OK between spatially adjacent cells,
// with the worst adjacent pair reported alongside it. Every variant reports both, which
// is what lets them be ranked objectively instead of eyeballed.
//
// Two colours can occupy many cells each, so a layout is scored over grid *edges*, not
// over palette pairs — a big smooth blob contributes a pile of zero-ΔE edges and only its
// perimeter costs anything. That is exactly the shape we want to reward.

import { deltaEOK } from '../oklch.js';

/** How much grid area a colour gets, before normalisation. */
export const BLOB_MODES = ['isolation', 'equal', 'role', 'usage', 'chroma'];

/** Relative area weight per layer for the `role` blob mode — anchors matter most. */
const ROLE_IMPORTANCE = {
  anchor: 3,
  fg: 2.2,
  accent: 2,
  neutral: 1.4,
  'neutral-warm': 1.4,
  bg: 1.2,
  bridge: 0.8,
};

/** OKLab triples for every entry, in palette order — the vectors all layouts work on. */
export function entryLabs(palette) {
  return palette.entries.map((e) => e.lab);
}

/** Full K×K ΔE_OK matrix, computed once and shared by scoring, assignment and annealing. */
export function deltaMatrix(labs) {
  const k = labs.length;
  const m = new Float64Array(k * k);
  for (let i = 0; i < k; i++) {
    for (let j = i + 1; j < k; j++) {
      const d = deltaEOK(labs[i], labs[j]);
      m[i * k + j] = d;
      m[j * k + i] = d;
    }
  }
  return m;
}

/**
 * Mean and worst neighbour ΔE over a layout's grid edges, plus the fraction of edges
 * that cross a blob boundary at all.
 */
export function scoreLayout(layout, labs, matrix = deltaMatrix(labs)) {
  const k = labs.length;
  const { cells, grid } = layout;
  const { edges } = grid;
  let sum = 0;
  let worst = 0;
  let crossings = 0;
  const n = edges.length / 2;
  for (let e = 0; e < n; e++) {
    const a = cells[edges[e * 2]];
    const b = cells[edges[e * 2 + 1]];
    if (a < 0 || b < 0) continue; // an unassigned cell is a hole; coverage() reports it
    const d = a === b ? 0 : matrix[a * k + b];
    sum += d;
    if (d > worst) worst = d;
    if (a !== b) crossings++;
  }
  return { mean: n ? sum / n : 0, worst, edges: n, crossings: n ? crossings / n : 0 };
}

/** Unassigned active cells and palette entries that never appear — both must be empty. */
export function coverage(layout, k) {
  const seen = new Uint8Array(k);
  let holes = 0;
  for (const i of layout.grid.active) {
    const v = layout.cells[i];
    if (v < 0 || v >= k) holes++;
    else seen[v] = 1;
  }
  const missing = [];
  for (let i = 0; i < k; i++) if (!seen[i]) missing.push(i);
  return { holes, missing, complete: holes === 0 && missing.length === 0 };
}

/**
 * Per-entry area weights for a blob-sizing mode. `usage` is per-entry pixel counts
 * gathered from the gallery scenes by the caller (core may not import src/scenes/).
 */
export function blobWeights(palette, mode = 'isolation', { usage = null, matrix = null } = {}) {
  const entries = palette.entries;
  const k = entries.length;
  let raw;
  switch (mode) {
    case 'equal':
      raw = entries.map(() => 1);
      break;
    case 'role':
      raw = entries.map((e) => ROLE_IMPORTANCE[e.layer] ?? 1);
      break;
    case 'chroma':
      raw = entries.map((e) => 0.02 + e.actual.C);
      break;
    case 'usage':
      raw = usage && usage.length === k ? Array.from(usage, (u) => Math.sqrt(Math.max(0, u))) : entries.map(() => 1);
      break;
    case 'isolation':
    default:
      raw = isolationWeights(entries, matrix ?? deltaMatrix(entryLabs(palette)));
      break;
  }
  // No colour may vanish to a sliver: floor every weight at a twentieth of the largest.
  const max = Math.max(...raw, 1e-9);
  return raw.map((w) => Math.max(w, max * 0.05));
}

/** Mean ΔE to a colour's three nearest palette neighbours — its perceptual isolation. */
function isolationWeights(entries, matrix) {
  const k = entries.length;
  const m = Math.min(3, k - 1);
  const out = [];
  for (let i = 0; i < k; i++) {
    const ds = [];
    for (let j = 0; j < k; j++) if (j !== i) ds.push(matrix[i * k + j]);
    ds.sort((a, b) => a - b);
    let s = 0;
    for (let n = 0; n < m; n++) s += ds[n];
    out.push(m ? s / m : 1);
  }
  return out;
}

/**
 * Apportion `n` cells across weighted entries: proportional, every entry guaranteed at
 * least one cell, and the total exactly `n` (largest-remainder, ties by index).
 */
export function targetCounts(weights, n) {
  const k = weights.length;
  if (n < k) throw new Error(`grid of ${n} cells cannot hold ${k} colours`);
  const total = weights.reduce((a, b) => a + b, 0);
  const counts = new Int32Array(k);
  const rema = [];
  let used = 0;
  for (let i = 0; i < k; i++) {
    const quota = (n * weights[i]) / total;
    const floor = Math.max(1, Math.floor(quota));
    counts[i] = floor;
    used += floor;
    rema.push({ i, frac: quota - Math.floor(quota) });
  }
  // Hand out the remainder to the biggest fractions; claw back from the biggest blobs.
  rema.sort((a, b) => b.frac - a.frac || a.i - b.i);
  let p = 0;
  while (used < n) {
    counts[rema[p % k].i]++;
    used++;
    p++;
  }
  while (used > n) {
    let big = 0;
    for (let i = 1; i < k; i++) if (counts[i] > counts[big]) big = i;
    if (counts[big] <= 1) break; // every blob is already a single cell
    counts[big]--;
    used--;
  }
  return counts;
}
