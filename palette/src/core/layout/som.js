// Kohonen self-organizing map — picker variants 1–4 (PLAN §9).
//
// The SOM is the closest thing to what an artist's palette actually is: a continuous
// colour field laid over a surface, with the palette's structure emerging as regions.
// Training pulls each grid node toward the palette colours it is nearest to, dragging its
// spatial neighbours along, so neighbouring nodes end up holding neighbouring colours.
// That is the objective the picker is scored on, arrived at from the topology side.
//
// The four variants differ only in the grid they train on: rectangular, toroidal (no edge
// distortion, because there is no edge), hexagonal (six-way neighbourhoods), and a disc
// (a round painter's palette). Nothing else changes — `Grid` carries the topology, and
// the neighbourhood kernel just uses `grid.dist2`.

import { compactSwaps } from './assign.js';
import { centroidOf } from './grid.js';
import { projectLabs } from './mds.js';
import { relaxSites } from './voronoi.js';

const EPOCHS = 40;
const RADIUS_END = 1.0;
const INIT_JITTER = 0.01;
const SHAPE_ROUNDS = 4; // Lloyd rounds used to round off the map's territories

/**
 * Train a SOM over the grid and return one OKLab codebook vector per active cell.
 *
 * This is the *batch* Kohonen update, not the online one: each epoch finds every palette
 * colour's best-matching node, then rewrites every node as the kernel-weighted mean of the
 * colours whose winners are near it. A palette is only a few dozen samples, so the online
 * rule spends its late, small-radius steps memorising individual colours and leaves the
 * field speckled — measurably worse than the projection it started from. The batch rule
 * has no learning rate to decay and stays smooth all the way down.
 */
function somField(grid, labs, weights, rng, { epochs = EPOCHS, radiusEnd = RADIUS_END } = {}) {
  const n = grid.count;
  const k = labs.length;
  const book = new Float64Array(n * 3);

  // Start from the palette's own principal plane rather than from noise: the map then
  // only has to fold, not to unfold. The jitter is what makes the seed matter.
  const { unproject } = projectLabs(labs);
  for (let a = 0; a < n; a++) {
    const i = grid.active[a];
    const lab = unproject(grid.px[i] / grid.spanX, grid.py[i] / grid.spanY);
    for (let d = 0; d < 3; d++) book[a * 3 + d] = lab[d] + (rng() - 0.5) * INIT_JITTER;
  }

  const radius0 = Math.max(grid.spanX, grid.spanY) / 2;
  const bmu = new Int32Array(k);
  const num = new Float64Array(n * 3);
  const den = new Float64Array(n);

  for (let epoch = 0; epoch < epochs; epoch++) {
    const radius = radius0 * (radiusEnd / radius0) ** (epoch / Math.max(1, epochs - 1));
    const denom = 2 * radius * radius;

    for (let j = 0; j < k; j++) {
      let best = Infinity;
      for (let a = 0; a < n; a++) {
        const dl = book[a * 3] - labs[j][0];
        const da = book[a * 3 + 1] - labs[j][1];
        const db = book[a * 3 + 2] - labs[j][2];
        const d = dl * dl + da * da + db * db;
        if (d < best) { best = d; bmu[j] = a; }
      }
    }

    num.fill(0);
    den.fill(0);
    for (let j = 0; j < k; j++) {
      const winner = grid.active[bmu[j]];
      for (let a = 0; a < n; a++) {
        const h = weights[j] * Math.exp(-grid.dist2(winner, grid.active[a]) / denom);
        if (h < 1e-6) continue;
        den[a] += h;
        num[a * 3] += h * labs[j][0];
        num[a * 3 + 1] += h * labs[j][1];
        num[a * 3 + 2] += h * labs[j][2];
      }
    }
    for (let a = 0; a < n; a++) {
      if (den[a] <= 0) continue;
      for (let d = 0; d < 3; d++) book[a * 3 + d] = num[a * 3 + d] / den[a];
    }
  }

  return Array.from({ length: n }, (_, a) => [book[a * 3], book[a * 3 + 1], book[a * 3 + 2]]);
}

/**
 * Build the layout for SOM variants 1–4: train the map, read each colour's territory off
 * it, then shape the blobs spatially around those territories.
 *
 * Committing the field directly — every cell to its nearest entry, capped by budget —
 * looks obvious and scores badly. A trained map is a smooth gradient, so a colour's
 * nearest-cells form a wide band rather than a patch, and the budget cap then scatters the
 * overflow across the whole band. Taking the centroid of each colour's territory as a site
 * and assigning cells by *distance on the grid* keeps the arrangement the SOM found while
 * giving every colour one compact blob of exactly the size the blob mode asked for.
 */
export function buildSom(ctx) {
  const { grid, labs, counts } = ctx;
  const field = somField(grid, labs, ctx.weights, ctx.rng);
  const sites = territoryCentroids(grid, field, labs);
  const cells = relaxSites(grid, sites, counts, SHAPE_ROUNDS);
  return compactSwaps(cells, grid, ctx.matrix, labs.length);
}

/** Where each colour ended up on the trained map: the centroid of the nodes it owns. */
function territoryCentroids(grid, field, labs) {
  const k = labs.length;
  const owner = new Int32Array(grid.count);
  for (let a = 0; a < grid.count; a++) {
    let best = 0;
    let bestD = Infinity;
    for (let j = 0; j < k; j++) {
      let d = 0;
      for (let q = 0; q < 3; q++) d += (field[a][q] - labs[j][q]) ** 2;
      if (d < bestD) { bestD = d; best = j; }
    }
    owner[a] = best;
  }

  return Array.from({ length: k }, (_, j) => {
    const owned = [];
    for (let a = 0; a < grid.count; a++) if (owner[a] === j) owned.push(grid.active[a]);
    // A colour can win no node at all when two palette entries are nearly identical.
    return centroidOf(grid, owned, nearestNode(grid, field, labs[j]));
  });
}

/** Grid position of the single node closest to a colour. */
function nearestNode(grid, field, lab) {
  let best = 0;
  let bestD = Infinity;
  for (let a = 0; a < grid.count; a++) {
    let d = 0;
    for (let q = 0; q < 3; q++) d += (field[a][q] - lab[q]) ** 2;
    if (d < bestD) { bestD = d; best = a; }
  }
  const cell = grid.active[best];
  return [grid.px[cell], grid.py[cell]];
}
