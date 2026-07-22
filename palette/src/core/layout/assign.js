// Turning a colour *field* into a legal layout.
//
// Most variants describe the palette spatially — a SOM codebook, a Voronoi diagram, a
// polar wheel — and then have to commit each cell to an actual palette entry. Two things
// make that non-trivial: every entry must appear (no colour may be unfindable), and the
// blob-size mode says how much area each one is owed.
//
// `assignByCapacity` solves both at once: entries are hard-capped at their target cell
// counts, so coverage and blob sizing are guaranteed by construction rather than checked
// afterwards. It is the classic greedy transportation heuristic — take the globally
// cheapest (cell, entry) pair that still fits, repeat — run off a heap so it stays near
// linear instead of sorting N×K pairs.

import { MinHeap } from './heap.js';

const RESCUE_SWEEPS = 3;
const RESCUE_BUDGET = 48; // cells allowed to search the whole grid for a home, per sweep

/**
 * Squared Euclidean distance. On OKLab triples that is monotonic in ΔE_OK, so ordering
 * by it is the same ordering; the projection layouts pass 2-D points through instead.
 */
function dist2(a, b) {
  let sum = 0;
  for (let d = 0; d < a.length; d++) {
    const v = a[d] - b[d];
    sum += v * v;
  }
  return sum;
}

/**
 * Assign cells to palette entries, nearest-first, respecting per-entry cell budgets.
 * `cellLabs` holds one target vector per cell of `subset` (the whole grid by default);
 * pass `into` to fill an existing, partly-assigned cells array.
 */
export function assignByCapacity(grid, cellLabs, labs, counts, { subset = null, into = null, metric = dist2 } = {}) {
  const k = labs.length;
  const targets = subset ?? grid.active;
  const n = targets.length;
  const cells = into ?? new Int32Array(grid.w * grid.h).fill(-1);
  const left = Int32Array.from(counts);

  // Each cell's entries ordered by distance, so we can walk down its preference list.
  const pref = new Array(n);
  for (let a = 0; a < n; a++) {
    const idx = Array.from({ length: k }, (_, i) => i);
    const d = idx.map((i) => metric(cellLabs[a], labs[i]));
    idx.sort((x, y) => d[x] - d[y] || x - y);
    pref[a] = { order: Int32Array.from(idx), d };
  }

  const heap = new MinHeap((x, y) => x.cost - y.cost || x.a - y.a || x.e - y.e);
  for (let a = 0; a < n; a++) {
    const e = pref[a].order[0];
    heap.push({ cost: pref[a].d[e], a, p: 0, e });
  }

  let placed = 0;
  while (placed < n && heap.size) {
    const item = heap.pop();
    if (cells[targets[item.a]] >= 0) continue;
    if (left[item.e] > 0) {
      cells[targets[item.a]] = item.e;
      left[item.e]--;
      placed++;
      continue;
    }
    const p = item.p + 1;
    if (p < k) {
      const e = pref[item.a].order[p];
      heap.push({ cost: pref[item.a].d[e], a: item.a, p, e });
    }
  }
  return cells;
}

/**
 * Lay entries down as contiguous runs along a cell traversal — the fill used by the
 * layouts whose whole idea is a 1-D ordering (Hilbert, value spiral, ramp rows).
 */
export function fillRuns(grid, cellOrder, entryOrder, counts) {
  const cells = new Int32Array(grid.w * grid.h).fill(-1);
  let at = 0;
  for (const e of entryOrder) {
    for (let n = 0; n < counts[e] && at < cellOrder.length; n++) cells[cellOrder[at++]] = e;
  }
  // Any tail left by rounding takes the last entry rather than staying a hole.
  const last = entryOrder[entryOrder.length - 1];
  while (at < cellOrder.length) cells[cellOrder[at++]] = last;
  return cells;
}

/**
 * Squared distance on the grid's own surface — wrapped when the topology is a torus, so a
 * site near the seam still owns the cells on the far side that are genuinely next to it.
 */
export function spatialMetric(grid) {
  if (!grid.wraps) return dist2;
  const spans = [grid.spanX, grid.spanY];
  return (a, b) => {
    let sum = 0;
    for (let d = 0; d < 2; d++) {
      const span = spans[d];
      let v = Math.abs(a[d] - b[d]) % span;
      if (v > span / 2) v = span - v;
      sum += v * v;
    }
    return sum;
  };
}

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

/**
 * Sweep every adjacent pair and swap it when — and only when — that strictly lowers the
 * total neighbour ΔE. Swapping preserves cell counts, so blob sizes and coverage survive.
 *
 * Capacity assignment is greedy: the last cells to be placed take whatever budget is still
 * free, which strands a scatter of singletons inside otherwise clean blobs. This is the
 * repair for that, and every field-based variant runs it as its commit step. It is a
 * descent, not a search — it cannot escape a local minimum, which is what still separates
 * these variants from the annealer.
 */
export function compactSwaps(cells, grid, matrix, k, sweeps = 8) {
  for (let sweep = 0; sweep < sweeps; sweep++) {
    // Outlier rescue is a repair, not a refinement: the strandings it fixes are created
    // by the initial assignment, so it earns its keep in the first passes and not after.
    const rescue = sweep < RESCUE_SWEEPS ? relocateOutliers(cells, grid, matrix, k) : 0;
    const moved = neighborSweep(cells, grid, matrix, k) + rescue;
    if (!moved) break;
  }
  return cells;
}

/** Try every adjacent pair; keep the swap only when it lowers the total. */
function neighborSweep(cells, grid, matrix, k) {
  let moved = 0;
  for (const i of grid.active) {
    const base = i * 6;
    for (let nb = 0; nb < grid.nbrCount[i]; nb++) {
      const j = grid.nbr[base + nb];
      if (cells[i] === cells[j]) continue;
      if (trySwap(cells, grid, matrix, k, i, j)) moved++;
    }
  }
  return moved;
}

/**
 * Rescue the stranded cells: a lone near-white cell marooned inside a dark blob is the
 * single worst thing this picker can do, and adjacent swaps cannot fix it — getting it
 * home takes a chain of moves, and every individual link makes the score worse.
 *
 * So the cells paying the most in neighbour ΔE get to propose a swap with *any* cell on
 * the grid, not just a neighbour. The proposer count is a fixed budget, not a fraction of
 * the grid: strandings are a handful of cells however large the grid is, and a fraction
 * would make this the quadratic term that decides how fine a grid the picker can afford.
 */
function relocateOutliers(cells, grid, matrix, k) {
  const ranked = Array.from(grid.active, (i) => ({ i, cost: localCost(cells, grid, matrix, k, i) }))
    .filter((c) => c.cost > 0)
    .sort((a, b) => b.cost - a.cost || a.i - b.i)
    .slice(0, RESCUE_BUDGET);

  let moved = 0;
  for (const { i } of ranked) {
    let best = -1;
    let bestGain = 0;
    for (const j of grid.active) {
      if (cells[j] === cells[i]) continue;
      const before = localCost(cells, grid, matrix, k, i) + localCost(cells, grid, matrix, k, j);
      swap(cells, i, j);
      const gain = before - (localCost(cells, grid, matrix, k, i) + localCost(cells, grid, matrix, k, j));
      swap(cells, i, j);
      if (gain > bestGain) { bestGain = gain; best = j; }
    }
    if (best >= 0) {
      swap(cells, i, best);
      moved++;
    }
  }
  return moved;
}

/** Swap two cells, keeping the change only if it strictly lowers the total. */
function trySwap(cells, grid, matrix, k, i, j) {
  const before = localCost(cells, grid, matrix, k, i) + localCost(cells, grid, matrix, k, j);
  swap(cells, i, j);
  if (localCost(cells, grid, matrix, k, i) + localCost(cells, grid, matrix, k, j) < before) return true;
  swap(cells, i, j);
  return false;
}

function swap(cells, i, j) {
  const tmp = cells[i];
  cells[i] = cells[j];
  cells[j] = tmp;
}

/**
 * Guarantee every colour appears at least once, taking a cell from the largest blob for
 * each one that got rounded away. The rasterised layouts (treemap, wheel) can lose a
 * single-cell colour to rounding; the picker's whole promise is that nothing is missing.
 */
export function ensureCoverage(cells, grid, k) {
  const tally = new Int32Array(k);
  for (const i of grid.active) if (cells[i] >= 0) tally[cells[i]]++;
  for (let e = 0; e < k; e++) {
    if (tally[e] > 0) continue;
    let big = 0;
    for (let q = 1; q < k; q++) if (tally[q] > tally[big]) big = q;
    // Take from the middle of the donor run so the hole is visible rather than an edge nick.
    const owned = grid.active.filter((i) => cells[i] === big);
    const victim = owned[Math.floor(owned.length / 2)];
    cells[victim] = e;
    tally[big]--;
    tally[e]++;
  }
  return cells;
}

/** Active cells row by row, alternating direction — the boustrophedon fill order. */
export function boustrophedon(grid) {
  const out = [];
  for (let y = 0; y < grid.h; y++) {
    for (let n = 0; n < grid.w; n++) {
      const x = y & 1 ? grid.w - 1 - n : n;
      const i = y * grid.w + x;
      if (grid.mask[i]) out.push(i);
    }
  }
  return Int32Array.from(out);
}

/** Active cells ordered outward from the centre in a square spiral. */
export function spiralOrder(grid) {
  const out = [];
  const cx = Math.floor((grid.w - 1) / 2);
  const cy = Math.floor((grid.h - 1) / 2);
  let x = cx;
  let y = cy;
  let step = 1;
  let dir = 0;
  const dirs = [[1, 0], [0, 1], [-1, 0], [0, -1]];
  const push = (px, py) => {
    if (px >= 0 && py >= 0 && px < grid.w && py < grid.h && grid.mask[py * grid.w + px]) {
      out.push(py * grid.w + px);
    }
  };
  push(x, y);
  const limit = grid.w * grid.h * 4;
  for (let guard = 0; out.length < grid.count && guard < limit; ) {
    for (let twice = 0; twice < 2; twice++) {
      const [dx, dy] = dirs[dir];
      for (let s = 0; s < step; s++) {
        x += dx;
        y += dy;
        push(x, y);
        guard++;
      }
      dir = (dir + 1) % 4;
    }
    step++;
  }
  return Int32Array.from(out);
}
