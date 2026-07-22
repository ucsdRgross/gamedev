// The picker's variant registry (PLAN §9) — fifteen ways to arrange one palette so that
// neighbouring cells look alike, all scored on the same objective so they can be ranked.
//
// Every variant is a pure `(ctx) => Int32Array` returning one entry index per grid cell.
// The shared context carries the grid, the OKLab vectors, the blob-size budget and a
// seeded PRNG, so a variant only has to decide *arrangement*. Coverage and blob sizing
// come out of `assignByCapacity`/`fillRuns` rather than being each variant's problem.

import { makeRng } from '../rng.js';
import { Grid } from './grid.js';
import { blobWeights, coverage, deltaMatrix, entryLabs, scoreLayout, targetCounts } from './score.js';
import { buildAnneal } from './anneal.js';
import { buildGrow } from './grow.js';
import { buildHilbert } from './hilbert.js';
import { buildMesh } from './mesh.js';
import { buildSom } from './som.js';
import { buildRampRows, buildSphere, buildSpiral, buildTreemap, buildWheel } from './structural.js';
import { buildLloyd, buildVoronoi } from './voronoi.js';

// Grid resolution is a straight trade against build time, which scales worse than
// linearly. 96×64 is the point where blob edges are fine enough that render-time
// smoothing produces clean curves rather than rounded-off staircases, and the slowest
// variant still builds in about a second.
const DEFAULT_SIZE = { w: 96, h: 64 };
const DISC_SIZE = { w: 80, h: 80 };

/**
 * The fifteen layouts. `optimized` marks the ones held to beating the ramp-rows baseline
 * in `test/layout.test.js`; the rest are structural views that trade score for legibility
 * (a hue wheel is useful even when it ranks low, because you can predict where a colour
 * will be). Two classifications are worth knowing about because they are measurements, not
 * intentions — see ARCHITECTURE §11:
 *
 * - **Hilbert (6) is structural.** A serpentine fill turns every colour into a strip
 *   spanning the grid, and strips lose to blocks on perimeter no matter how good the
 *   ordering is. Its 3-D ordering is genuinely strong; it is the 1-D commit that costs it.
 *   The 2-D Hilbert traversal that *does* have that locality is what seeds the annealer.
 * - **Treemap (13) is structural but scores well.** Rectangles tile a rectangle perfectly,
 *   so it wins on perimeter while still being addressable by hue family.
 *
 * `rectilinear: true` marks the layouts whose straight edges *are* the information — rows,
 * runs and tiles. Render-time boundary smoothing is skipped for those: rounding the corners
 * off a treemap does not make it prettier, it makes it wrong.
 */
export const VARIANTS = [
  { n: 1, id: 'som-rect', title: 'SOM — rectangular', topology: 'rect', optimized: true, build: buildSom },
  { n: 2, id: 'som-torus', title: 'SOM — toroidal', topology: 'torus', optimized: true, build: buildSom },
  { n: 3, id: 'som-hex', title: 'SOM — hexagonal', topology: 'hex', optimized: true, build: buildSom },
  { n: 4, id: 'som-disc', title: 'SOM — disc', topology: 'disc', size: DISC_SIZE, optimized: true, build: buildSom },
  { n: 5, id: 'anneal', title: 'Simulated annealing', topology: 'rect', optimized: true, build: buildAnneal },
  { n: 6, id: 'hilbert', title: 'Hilbert-curve sort', topology: 'rect', optimized: false, rectilinear: true, build: buildHilbert },
  { n: 7, id: 'voronoi', title: 'MDS projection — Voronoi', topology: 'rect', optimized: true, build: buildVoronoi },
  { n: 8, id: 'lloyd', title: 'Lloyd-relaxed Voronoi', topology: 'rect', optimized: true, build: buildLloyd },
  { n: 9, id: 'grow', title: 'Organic region growth', topology: 'rect', optimized: true, build: buildGrow },
  { n: 10, id: 'wheel', title: 'Polar hue wheel', topology: 'disc', size: DISC_SIZE, optimized: false, build: buildWheel },
  { n: 11, id: 'ramp-rows', title: 'Ramp rows (baseline)', topology: 'rect', optimized: false, rectilinear: true, build: buildRampRows },
  { n: 12, id: 'spiral', title: 'Value-sorted spiral', topology: 'rect', optimized: false, rectilinear: true, build: buildSpiral },
  { n: 13, id: 'treemap', title: 'Squarified treemap', topology: 'rect', optimized: false, rectilinear: true, build: buildTreemap },
  { n: 14, id: 'sphere', title: 'Sphere unwrap (Lambert)', topology: 'rect', optimized: false, build: buildSphere },
  { n: 15, id: 'mesh', title: 'Delaunay mesh', topology: 'rect', optimized: true, build: buildMesh },
];

/** The layout every optimized variant is measured against (PLAN §9, task 4.8). */
export const BASELINE_ID = 'ramp-rows';

/**
 * Palette sizes at which the arrangement problem is non-trivial, and so the sizes the
 * baseline comparison is asserted over. Below roughly 24 colours the baseline is close to
 * optimal — there are few enough colours that hue-ordered blocks tile the grid almost
 * perfectly — and only the annealer beats it. That is a property of the problem, not a
 * gap in the variants; `test/layout.test.js` asserts it explicitly rather than hiding it.
 */
export const BASELINE_SIZES = [32, 48, 64];

/** Look a variant up by its string id. */
export const VARIANT_BY_ID = new Map(VARIANTS.map((v) => [v.id, v]));

/** Stable 32-bit hash of a seed string, so a palette's seed can drive the PRNG. */
export function hashSeed(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/**
 * Build one layout. `usage` is optional per-entry pixel counts from the gallery scenes,
 * used only by the `usage` blob mode.
 */
export function buildLayout(palette, {
  variant = 'som-rect', blobMode = 'isolation', usage = null, size = null, seed = null,
} = {}) {
  const spec = typeof variant === 'string' ? VARIANT_BY_ID.get(variant) : variant;
  if (!spec) throw new Error(`unknown layout variant: ${variant}`);

  const dims = size ?? spec.size ?? DEFAULT_SIZE;
  const grid = new Grid(dims.w, dims.h, spec.topology);
  const labs = entryLabs(palette);
  const matrix = deltaMatrix(labs);
  const weights = blobWeights(palette, blobMode, { usage, matrix });
  const counts = targetCounts(weights, grid.count);
  const rng = makeRng(hashSeed(String(seed ?? palette.seed ?? 'PAL1')));

  const ctx = { palette, grid, labs, matrix, weights, counts, rng, blobMode };
  const cells = spec.build(ctx);
  const layout = {
    id: spec.id, title: spec.title, variant: spec.n, optimized: !!spec.optimized,
    rectilinear: !!spec.rectilinear, grid, cells, blobMode, counts,
  };
  layout.score = scoreLayout(layout, labs, matrix);
  layout.coverage = coverage(layout, labs.length);
  return layout;
}

/** Build every variant for a palette, best mean-neighbour ΔE first. */
export function rankLayouts(palette, opts = {}) {
  return VARIANTS
    .map((v) => buildLayout(palette, { ...opts, variant: v.id }))
    .sort((a, b) => a.score.mean - b.score.mean);
}
