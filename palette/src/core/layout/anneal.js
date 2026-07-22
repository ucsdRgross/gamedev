// Simulated-annealing swap grid — picker variant 5 (PLAN §9).
//
// Every other variant reaches a good arrangement by describing the palette some other way
// and hoping the objective follows. This one attacks the objective directly: start from
// the Hilbert layout, then swap pairs of cells, keeping improvements and — early on —
// some worsenings, so the search can climb out of local minima.
//
// Swapping preserves how many cells each colour owns, so blob sizes and full coverage
// survive the whole run for free. Every random draw comes from the seeded PRNG, so a
// given palette and seed always produce the same grid; that is asserted in the tests.

import { compactSwaps, fillRuns } from './assign.js';
import { hilbertCellOrder, hilbertOrder } from './hilbert.js';

const PROPOSALS_PER_CELL = 120;
const T_START = 4;
const T_END = 0.02;
const WINDOW_END = 3;

/** Sum of neighbour ΔE at one cell — the only term a swap involving that cell changes. */
function localCost(cells, grid, matrix, k, cell) {
  const a = cells[cell];
  let sum = 0;
  const base = cell * 6;
  for (let n = 0; n < grid.nbrCount[cell]; n++) {
    const b = cells[grid.nbr[base + n]];
    if (b !== a) sum += matrix[a * k + b];
  }
  return sum;
}

/** Build the layout for variant 5: anneal swaps down from a Hilbert start. */
export function buildAnneal(ctx) {
  const { grid, matrix, labs, rng } = ctx;
  const k = labs.length;
  // Colours in Hilbert order laid along a 2-D Hilbert traversal: consecutive colours land
  // in compact regions, so the annealer starts with blobs and only has to refine borders.
  const cells = fillRuns(grid, hilbertCellOrder(grid), hilbertOrder(labs), ctx.counts);
  const n = grid.count;
  const proposals = n * PROPOSALS_PER_CELL;
  const window0 = Math.max(grid.spanX, grid.spanY) / 2;

  for (let step = 0; step < proposals; step++) {
    const t = step / proposals;
    const temp = T_START * (T_END / T_START) ** t;
    const win = Math.max(WINDOW_END, window0 * (WINDOW_END / window0) ** t);

    const i = pickBoundary(cells, grid, rng);
    if (i < 0) continue;
    const j = pickNearby(grid, i, win, rng);
    if (j < 0 || cells[i] === cells[j]) continue;

    const before = localCost(cells, grid, matrix, k, i) + localCost(cells, grid, matrix, k, j);
    const tmp = cells[i];
    cells[i] = cells[j];
    cells[j] = tmp;
    const after = localCost(cells, grid, matrix, k, i) + localCost(cells, grid, matrix, k, j);
    const delta = after - before;
    // The shared edge, if i and j touch, is counted twice on both sides and cancels.
    if (delta > 0 && rng() >= Math.exp(-delta / temp)) {
      cells[j] = cells[i];
      cells[i] = tmp;
    }
  }

  return compactSwaps(cells, grid, matrix, k);
}

/**
 * A random cell that touches a differently-coloured neighbour. Interior cells of a blob
 * are already at zero local cost, so proposing them is wasted work.
 */
function pickBoundary(cells, grid, rng) {
  for (let tries = 0; tries < 8; tries++) {
    const i = grid.active[(rng() * grid.count) | 0];
    const base = i * 6;
    for (let nb = 0; nb < grid.nbrCount[i]; nb++) {
      if (cells[grid.nbr[base + nb]] !== cells[i]) return i;
    }
  }
  return -1;
}

/** A random active cell within `win` of `from`, or -1 if the draws all missed. */
function pickNearby(grid, from, win, rng) {
  const x = from % grid.w;
  const y = (from / grid.w) | 0;
  for (let tries = 0; tries < 4; tries++) {
    const r = Math.max(1, Math.round(win));
    let nx = x + ((rng() * (2 * r + 1)) | 0) - r;
    let ny = y + ((rng() * (2 * r + 1)) | 0) - r;
    if (grid.wraps) {
      nx = ((nx % grid.w) + grid.w) % grid.w;
      ny = ((ny % grid.h) + grid.h) % grid.h;
    } else if (nx < 0 || ny < 0 || nx >= grid.w || ny >= grid.h) {
      continue;
    }
    const j = ny * grid.w + nx;
    if (grid.mask[j] && j !== from) return j;
  }
  return -1;
}
