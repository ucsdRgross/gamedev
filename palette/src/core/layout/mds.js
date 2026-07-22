// Projecting the palette from 3-D OKLab down to the 2-D plane the picker draws on.
//
// ΔE_OK is plain Euclidean distance in OKLab, so classical (metric) MDS on that distance
// matrix is exactly PCA on the points themselves — same subspace, same coordinates up to
// sign. So this is one implementation serving both names: the two leading principal axes,
// found by deterministic power iteration on a 3×3 covariance matrix.
//
// Used by the projection/Voronoi variants, to seed organic growth, and to give the SOM a
// non-random starting codebook.

const POWER_ITERATIONS = 64;

/**
 * Project OKLab points onto their two principal axes.
 * Returns unit-square coordinates plus the axes and centroid, for mapping back.
 */
export function projectLabs(labs) {
  const n = labs.length;
  const mean = [0, 0, 0];
  for (const p of labs) for (let d = 0; d < 3; d++) mean[d] += p[d] / n;
  const centred = labs.map((p) => [p[0] - mean[0], p[1] - mean[1], p[2] - mean[2]]);

  const cov = covariance(centred);
  const e1 = dominantAxis(cov, [0.577, 0.577, 0.577]);
  const e2 = dominantAxis(deflate(cov, e1), orthogonalTo(e1));

  const raw = centred.map((p) => [dot(p, e1), dot(p, e2)]);
  const { points, minX, minY, span } = normalize(raw);
  /** Map a unit-square coordinate back to the OKLab plane the palette lives on. */
  const unproject = (u, v) => {
    const x = u * span + minX;
    const y = v * span + minY;
    return [
      mean[0] + x * e1[0] + y * e2[0],
      mean[1] + x * e1[1] + y * e2[1],
      mean[2] + x * e1[2] + y * e2[2],
    ];
  };
  return { points, axes: [e1, e2], mean, unproject };
}

/**
 * One site position per palette entry, spread across the grid's extent. Each projected
 * axis is stretched to its own range: the picker wants the whole surface used, and the
 * blobs are sized by budget anyway, so preserving the projection's aspect buys nothing.
 */
export function projectSites(grid, labs) {
  const { points } = projectLabs(labs);
  const axis = (d, extent) => {
    const vs = points.map((p) => p[d]);
    const lo = Math.min(...vs);
    const span = Math.max(...vs) - lo;
    if (span < 1e-9) return vs.map(() => extent / 2);
    return vs.map((v) => 0.5 + ((v - lo) / span) * (extent - 1));
  };
  const xs = axis(0, grid.spanX);
  const ys = axis(1, grid.spanY);
  return points.map((_, i) => [xs[i], ys[i]]);
}

/** 3×3 covariance of already-centred points, as a flat row-major array. */
function covariance(points) {
  const c = new Float64Array(9);
  for (const p of points) {
    for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) c[i * 3 + j] += p[i] * p[j];
  }
  for (let i = 0; i < 9; i++) c[i] /= Math.max(1, points.length);
  return c;
}

/** Leading eigenvector by power iteration, sign-fixed so the result is reproducible. */
function dominantAxis(m, start) {
  let v = start.slice();
  for (let it = 0; it < POWER_ITERATIONS; it++) {
    const nv = [
      m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
      m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
      m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    ];
    const len = Math.hypot(...nv);
    if (len < 1e-12) return start.slice();
    v = nv.map((x) => x / len);
  }
  // Pin the sign to the largest-magnitude component so runs never flip the picture.
  let big = 0;
  for (let i = 1; i < 3; i++) if (Math.abs(v[i]) > Math.abs(v[big])) big = i;
  return v[big] < 0 ? v.map((x) => -x) : v;
}

/** Remove an axis's contribution so power iteration finds the next one down. */
function deflate(m, v) {
  const out = new Float64Array(9);
  // λ = vᵀMv for a unit v; subtracting λvvᵀ leaves the remaining spectrum intact.
  const mv = [
    m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
    m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
    m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
  ];
  const lambda = dot(mv, v);
  for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) out[i * 3 + j] = m[i * 3 + j] - lambda * v[i] * v[j];
  return out;
}

/** Any unit vector perpendicular to v, chosen deterministically. */
function orthogonalTo(v) {
  const a = Math.abs(v[0]) < 0.9 ? [1, 0, 0] : [0, 1, 0];
  const c = [
    a[1] * v[2] - a[2] * v[1],
    a[2] * v[0] - a[0] * v[2],
    a[0] * v[1] - a[1] * v[0],
  ];
  const len = Math.hypot(...c) || 1;
  return c.map((x) => x / len);
}

function dot(a, b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

/** Fit points into the unit square, keeping the aspect ratio of the projection. */
function normalize(points) {
  const xs = points.map((p) => p[0]);
  const ys = points.map((p) => p[1]);
  const minX = Math.min(...xs);
  const minY = Math.min(...ys);
  const span = Math.max(Math.max(...xs) - minX, Math.max(...ys) - minY, 1e-9);
  return { points: points.map(([x, y]) => [(x - minX) / span, (y - minY) / span]), minX, minY, span };
}
