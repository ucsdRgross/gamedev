// Hilbert-curve sort — picker variant 6 (PLAN §9).
//
// The Hilbert curve is the standard answer to "order points in 3-D so that neighbours in
// the ordering are neighbours in space". Feeding it OKLab gives a 1-D colour ordering with
// strong locality, which a boustrophedon fill then folds onto the grid. It is the only
// variant with no stochastic component at all, so it doubles as the deterministic
// heuristic the annealer starts from.

import { boustrophedon, fillRuns } from './assign.js';

const BITS = 10; // 1024 steps per axis — far finer than any palette needs

/**
 * Index of a point along a 3-D Hilbert curve (Skilling's transpose algorithm).
 * Coordinates are integers in [0, 2^bits).
 */
export function hilbertIndex3(x, y, z, bits = BITS) {
  const X = [x | 0, y | 0, z | 0];
  const M = 1 << (bits - 1);

  // Inverse undo: walk the levels from coarse to fine, reflecting and exchanging axes.
  for (let Q = M; Q > 1; Q >>= 1) {
    const P = Q - 1;
    for (let i = 0; i < 3; i++) {
      if (X[i] & Q) {
        X[0] ^= P;
      } else {
        const t = (X[0] ^ X[i]) & P;
        X[0] ^= t;
        X[i] ^= t;
      }
    }
  }

  // Gray-encode, then undo the excess work the encoding leaves on the trailing axis.
  for (let i = 1; i < 3; i++) X[i] ^= X[i - 1];
  let t = 0;
  for (let Q = M; Q > 1; Q >>= 1) if (X[2] & Q) t ^= Q - 1;
  for (let i = 0; i < 3; i++) X[i] ^= t;

  // Interleave the transpose back into a single index, most significant bit first.
  let index = 0;
  for (let bit = bits - 1; bit >= 0; bit--) {
    for (let i = 0; i < 3; i++) index = index * 2 + ((X[i] >> bit) & 1);
  }
  return index;
}

/** Palette entry indices ordered along the Hilbert curve through their OKLab positions. */
export function hilbertOrder(labs) {
  const scale = 2 ** BITS - 1;
  // Normalise on the palette's own bounding box so the curve's resolution is all used.
  const lo = [Infinity, Infinity, Infinity];
  const hi = [-Infinity, -Infinity, -Infinity];
  for (const p of labs) {
    for (let d = 0; d < 3; d++) {
      lo[d] = Math.min(lo[d], p[d]);
      hi[d] = Math.max(hi[d], p[d]);
    }
  }
  const span = [0, 1, 2].map((d) => Math.max(hi[d] - lo[d], 1e-9));

  const keyed = labs.map((p, i) => {
    const c = [0, 1, 2].map((d) => Math.round(((p[d] - lo[d]) / span[d]) * scale));
    return { i, key: hilbertIndex3(c[0], c[1], c[2]) };
  });
  keyed.sort((a, b) => a.key - b.key || a.i - b.i);
  return keyed.map((e) => e.i);
}

/** Build the layout for variant 6: Hilbert ordering laid down boustrophedon. */
export function buildHilbert(ctx) {
  return fillRuns(ctx.grid, boustrophedon(ctx.grid), hilbertOrder(ctx.labs), ctx.counts);
}

/**
 * Active cells in 2-D Hilbert-curve order. Consecutive runs of this order are compact
 * regions rather than strips, which is why the annealer starts from it rather than from
 * the boustrophedon fill of variant 6.
 */
export function hilbertCellOrder(grid) {
  let side = 1;
  while (side < Math.max(grid.w, grid.h)) side *= 2;
  const out = [];
  for (let d = 0; d < side * side; d++) {
    const [x, y] = curveToXY(side, d);
    if (x < grid.w && y < grid.h && grid.mask[y * grid.w + x]) out.push(y * grid.w + x);
  }
  return Int32Array.from(out);
}

/** Position along a 2-D Hilbert curve of the given power-of-two side. */
function curveToXY(side, d) {
  let t = d;
  let x = 0;
  let y = 0;
  for (let s = 1; s < side; s *= 2) {
    const rx = 1 & (t >> 1);
    const ry = 1 & (t ^ rx);
    if (ry === 0) {
      if (rx === 1) {
        x = s - 1 - x;
        y = s - 1 - y;
      }
      const swap = x;
      x = y;
      y = swap;
    }
    x += s * rx;
    y += s * ry;
    t >>= 2;
  }
  return [x, y];
}
