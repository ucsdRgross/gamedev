// Delaunay mesh with barycentric blending — picker variant 15 (PLAN §9).
//
// Triangulate the projected palette, then read a colour off the mesh at every cell by
// blending the three corner colours barycentrically and snapping the result to the nearest
// entry. Unlike Voronoi, which hands a cell wholly to one site, the blend makes the field
// vary continuously across each triangle — so the snapped boundaries land where two
// colours are genuinely equidistant, and clusters of similar colours interleave.

import { assignByCapacity, compactSwaps } from './assign.js';
import { projectSites } from './mds.js';

/** Build the layout for variant 15: barycentric mesh colours, snapped to the palette. */
export function buildMesh(ctx) {
  const { grid, labs, counts } = ctx;
  const sites = spreadDuplicates(projectSites(grid, labs));
  const tris = triangulate(sites);

  const targets = Array.from(grid.active, (i) => {
    const p = [grid.px[i], grid.py[i]];
    for (const t of tris) {
      const bc = barycentric(p, sites[t[0]], sites[t[1]], sites[t[2]]);
      if (!bc) continue;
      return [0, 1, 2].map((d) => bc[0] * labs[t[0]][d] + bc[1] * labs[t[1]][d] + bc[2] * labs[t[2]][d]);
    }
    return labs[nearestSite(p, sites)]; // outside the hull: the nearest corner colour
  });
  const cells = assignByCapacity(grid, targets, labs, counts);
  return compactSwaps(cells, grid, ctx.matrix, labs.length);
}

/**
 * Bowyer–Watson triangulation. Returns index triples; an empty result means the points
 * were degenerate (collinear), and the caller then falls back to nearest-site colouring.
 */
export function triangulate(points) {
  if (points.length < 3) return [];
  const xs = points.map((p) => p[0]);
  const ys = points.map((p) => p[1]);
  const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
  const cy = (Math.min(...ys) + Math.max(...ys)) / 2;
  const span = Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys), 1) * 20;

  // Three fictitious vertices enclosing everything; their triangles are dropped at the end.
  const pts = [...points, [cx - span, cy - span], [cx + span, cy - span], [cx, cy + span]];
  const superFrom = points.length;
  let tris = [[superFrom, superFrom + 1, superFrom + 2]];

  for (let p = 0; p < points.length; p++) {
    const bad = [];
    const kept = [];
    for (const t of tris) (inCircumcircle(pts[p], pts[t[0]], pts[t[1]], pts[t[2]]) ? bad : kept).push(t);
    // The cavity's boundary is every edge belonging to exactly one bad triangle.
    const counts = new Map();
    for (const t of bad) {
      for (const [a, b] of [[t[0], t[1]], [t[1], t[2]], [t[2], t[0]]]) {
        const key = a < b ? `${a},${b}` : `${b},${a}`;
        counts.set(key, (counts.get(key) ?? 0) + 1);
      }
    }
    tris = kept;
    for (const [key, n] of counts) {
      if (n !== 1) continue;
      const [a, b] = key.split(',').map(Number);
      tris.push([a, b, p]);
    }
  }
  return tris.filter((t) => t.every((i) => i < points.length));
}

/** True if p lies inside the circumcircle of a/b/c (the Delaunay in-circle predicate). */
function inCircumcircle(p, a, b, c) {
  const ax = a[0] - p[0];
  const ay = a[1] - p[1];
  const bx = b[0] - p[0];
  const by = b[1] - p[1];
  const cx = c[0] - p[0];
  const cy = c[1] - p[1];
  const det = (ax * ax + ay * ay) * (bx * cy - by * cx)
    - (bx * bx + by * by) * (ax * cy - ay * cx)
    + (cx * cx + cy * cy) * (ax * by - ay * bx);
  // Sign depends on winding, so normalise by the triangle's orientation.
  const orient = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  return orient > 0 ? det > 0 : det < 0;
}

/** Barycentric coordinates of p in triangle a/b/c, or null when p is outside it. */
function barycentric(p, a, b, c) {
  const d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1]);
  if (Math.abs(d) < 1e-12) return null;
  const u = ((b[1] - c[1]) * (p[0] - c[0]) + (c[0] - b[0]) * (p[1] - c[1])) / d;
  const v = ((c[1] - a[1]) * (p[0] - c[0]) + (a[0] - c[0]) * (p[1] - c[1])) / d;
  const w = 1 - u - v;
  if (u < -1e-9 || v < -1e-9 || w < -1e-9) return null;
  return [u, v, w];
}

/** Index of the site nearest to p. */
function nearestSite(p, sites) {
  let best = 0;
  let bestD = Infinity;
  for (let i = 0; i < sites.length; i++) {
    const d = (sites[i][0] - p[0]) ** 2 + (sites[i][1] - p[1]) ** 2;
    if (d < bestD) { bestD = d; best = i; }
  }
  return best;
}

/** Nudge coincident sites apart — a duplicate point makes the triangulation degenerate. */
function spreadDuplicates(sites) {
  const seen = new Map();
  return sites.map((p, i) => {
    const key = `${p[0].toFixed(6)},${p[1].toFixed(6)}`;
    const n = seen.get(key) ?? 0;
    seen.set(key, n + 1);
    if (n === 0) return p;
    const angle = (i * 2.399963) % (2 * Math.PI); // golden-angle spiral, deterministic
    return [p[0] + 1e-3 * n * Math.cos(angle), p[1] + 1e-3 * n * Math.sin(angle)];
  });
}
