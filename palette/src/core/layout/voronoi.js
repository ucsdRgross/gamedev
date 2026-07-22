// Projection blobs — picker variants 7 and 8 (PLAN §9).
//
// Project the palette from OKLab to the plane (mds.js), plant one site per colour at its
// projected position, and let the cells fall to their nearest site. Colours that are close
// perceptually end up as touching blobs, because that is what the projection preserves.
//
// Variant 7 uses the projection as-is, so blob *positions* carry meaning but the shapes
// are ragged wherever sites are crowded. Variant 8 runs Lloyd relaxation — repeatedly move
// each site to the centroid of the cells it won — which trades a little of that positional
// fidelity for round, evenly spread blobs that are far easier to aim at.

import { assignByCapacity, compactSwaps, spatialMetric } from './assign.js';
import { centroidOf } from './grid.js';
import { projectSites } from './mds.js';

const LLOYD_ROUNDS = 8;

/** Assign cells to the nearest site, capped at each site's cell budget. */
function voronoiCells(grid, sites, counts) {
  const cellPts = Array.from(grid.active, (i) => [grid.px[i], grid.py[i]]);
  return assignByCapacity(grid, cellPts, sites, counts, { metric: spatialMetric(grid) });
}

/**
 * Move each site to the centroid of the cells it holds, reassign, repeat. Shared with the
 * SOM variants, which use it to round off the territories the map hands them.
 */
export function relaxSites(grid, sites, counts, rounds) {
  let current = sites;
  let cells = voronoiCells(grid, current, counts);
  for (let round = 0; round < rounds; round++) {
    const owned = current.map(() => []);
    for (const i of grid.active) owned[cells[i]].push(i);
    current = current.map((p, e) => centroidOf(grid, owned[e], p));
    cells = voronoiCells(grid, current, counts);
  }
  return cells;
}

/** Build the layout for variant 7: MDS/PCA projection with capacity-capped Voronoi blobs. */
export function buildVoronoi(ctx) {
  const cells = voronoiCells(ctx.grid, projectSites(ctx.grid, ctx.labs), ctx.counts);
  return compactSwaps(cells, ctx.grid, ctx.matrix, ctx.labs.length);
}

/** Build the layout for variant 8: the same, with the sites Lloyd-relaxed to centroids. */
export function buildLloyd(ctx) {
  const sites = projectSites(ctx.grid, ctx.labs);
  const cells = relaxSites(ctx.grid, sites, ctx.counts, LLOYD_ROUNDS);
  return compactSwaps(cells, ctx.grid, ctx.matrix, ctx.labs.length);
}
