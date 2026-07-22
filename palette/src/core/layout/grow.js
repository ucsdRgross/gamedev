// Organic region growth — picker variant 9 (PLAN §9).
//
// The variant closest to a physical palette: blobs of paint that spread until they meet,
// with irregular painterly edges rather than the straight seams a Voronoi diagram leaves.
//
// It is a multi-source Dijkstra. Each colour starts at its projected position and spreads
// outward, paying more to advance where it would have to border a colour it clashes with,
// and paying a seeded per-cell jitter that makes the boundaries wander instead of running
// straight. A region stops when it has spent its cell budget.

import { assignByCapacity, compactSwaps } from './assign.js';
import { MinHeap } from './heap.js';
import { projectSites } from './mds.js';

const CLASH_SCALE = 40; // ΔE at which bordering a foreign colour doubles the step cost
const JITTER = 0.9; // how far step costs wander — the whole source of the ragged edges

/** Build the layout for variant 9: ΔE-weighted region growth from projected seeds. */
export function buildGrow(ctx) {
  const { grid, labs, matrix, counts, rng } = ctx;
  const k = labs.length;
  const cells = new Int32Array(grid.w * grid.h).fill(-1);
  const left = Int32Array.from(counts);

  const jitter = new Float64Array(grid.w * grid.h);
  for (const i of grid.active) jitter[i] = 1 + JITTER * rng();

  const heap = new MinHeap((a, b) => a.cost - b.cost || a.region - b.region || a.cell - b.cell);
  for (const [region, cell] of seedCells(grid, labs).entries()) {
    if (cell >= 0) heap.push({ cost: 0, cell, region });
  }

  while (heap.size) {
    const { cost, cell, region } = heap.pop();
    if (cells[cell] >= 0 || left[region] <= 0) continue;
    cells[cell] = region;
    left[region]--;
    if (left[region] <= 0) continue;
    const base = cell * 6;
    for (let n = 0; n < grid.nbrCount[cell]; n++) {
      const next = grid.nbr[base + n];
      if (cells[next] >= 0) continue;
      heap.push({ cost: cost + stepCost(cells, grid, matrix, k, next, region, jitter), cell: next, region });
    }
  }

  fillStragglers(cells, grid, labs, left, counts);
  return compactSwaps(cells, grid, matrix, k);
}

/** Cost of advancing into a cell: jitter, scaled up by how badly it clashes with what it would touch. */
function stepCost(cells, grid, matrix, k, cell, region, jitter) {
  let clash = 0;
  const base = cell * 6;
  for (let n = 0; n < grid.nbrCount[cell]; n++) {
    const other = cells[grid.nbr[base + n]];
    if (other >= 0 && other !== region) clash = Math.max(clash, matrix[region * k + other]);
  }
  return jitter[cell] * (1 + clash / CLASH_SCALE);
}

/** One starting cell per colour, at its projected position, never two on the same cell. */
function seedCells(grid, labs) {
  const sites = projectSites(grid, labs);
  const taken = new Set();
  return sites.map(([sx, sy]) => {
    let best = -1;
    let bestD = Infinity;
    for (const i of grid.active) {
      if (taken.has(i)) continue;
      const dx = grid.px[i] - sx;
      const dy = grid.py[i] - sy;
      const d = dx * dx + dy * dy;
      if (d < bestD) { bestD = d; best = i; }
    }
    if (best >= 0) taken.add(best);
    return best;
  });
}

/**
 * A region walled in by its neighbours can run out of room before it spends its budget,
 * which leaves both stray cells and unspent colours. Settle both at once, nearest-first.
 */
function fillStragglers(cells, grid, labs, left, counts) {
  const stray = [];
  for (const i of grid.active) if (cells[i] < 0) stray.push(i);
  if (stray.length === 0) return;
  // Aim each leftover cell at the average colour of whatever already surrounds it.
  const targets = stray.map((i) => {
    const acc = [0, 0, 0];
    let n = 0;
    const base = i * 6;
    for (let q = 0; q < grid.nbrCount[i]; q++) {
      const e = cells[grid.nbr[base + q]];
      if (e < 0) continue;
      for (let d = 0; d < 3; d++) acc[d] += labs[e][d];
      n++;
    }
    return n ? acc.map((v) => v / n) : labs[0];
  });
  const remaining = Int32Array.from(counts, (_, e) => left[e]);
  assignByCapacity(grid, targets, labs, remaining, { subset: Int32Array.from(stray), into: cells });
}
