// Structural layouts — picker variants 10–14 (PLAN §9).
//
// These arrange by a property the artist already has a mental model of (hue angle, ramp,
// value, hue family) instead of by the neighbour-ΔE objective. They score worse than the
// optimized variants and that is the point: a hue wheel is worth having even when a blob
// field beats it, because you can *predict* where a colour will be. Ramp-rows is the
// explicit baseline the optimized layouts have to beat.

import { oklchToOklab } from '../oklch.js';
import { assignByCapacity, ensureCoverage, fillRuns, spiralOrder } from './assign.js';

const WHEEL_BANDS = 3;

/** Entries grouped into ramps (layer + hue), each sorted dark→light, hue-ordered. */
function rampGroups(palette) {
  const groups = new Map();
  palette.entries.forEach((e, i) => {
    const key = `${e.layer}_h${e.hueIndex}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push({ i, e });
  });
  const out = [...groups.values()].map((members) => {
    members.sort((a, b) => a.e.step - b.e.step || a.e.actual.L - b.e.actual.L);
    const chromatic = members.filter((m) => m.e.actual.C > 0.02);
    return {
      indices: members.map((m) => m.i),
      // Hueless groups (neutrals, anchors) sort by lightness after the coloured ones.
      hue: chromatic.length ? meanHue(chromatic.map((m) => m.e.actual.h)) : Infinity,
      light: members.reduce((a, m) => a + m.e.actual.L, 0) / members.length,
    };
  });
  out.sort((a, b) => a.hue - b.hue || a.light - b.light);
  return out;
}

/** Circular mean of hue angles in degrees. */
function meanHue(hues) {
  let x = 0;
  let y = 0;
  for (const h of hues) {
    x += Math.cos((h * Math.PI) / 180);
    y += Math.sin((h * Math.PI) / 180);
  }
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

/**
 * Variant 10 — polar hue wheel: angle is hue, radius is lightness, and chroma steps up
 * in concentric bands. Built on a disc so the shape says what the mapping is.
 */
export function buildWheel(ctx) {
  const { grid, palette, labs, counts } = ctx;
  const ls = palette.entries.map((e) => e.actual.L);
  const lMin = Math.min(...ls);
  const lMax = Math.max(...ls);
  const cMax = Math.max(...palette.entries.map((e) => e.actual.C), 0.02);
  const cx = (grid.spanX - 1) / 2;
  const cy = (grid.spanY - 1) / 2;
  const maxR = Math.min(cx, cy) || 1;

  const targets = Array.from(grid.active, (i) => {
    const dx = grid.px[i] - cx;
    const dy = grid.py[i] - cy;
    const r = Math.min(1, Math.hypot(dx, dy) / maxR);
    const hue = ((Math.atan2(dy, dx) * 180) / Math.PI + 360) % 360;
    const band = Math.min(WHEEL_BANDS, Math.floor(r * WHEEL_BANDS) + 1);
    return oklchToOklab(lMax - r * (lMax - lMin), (cMax * band) / WHEEL_BANDS, hue);
  });
  return assignByCapacity(grid, targets, labs, counts);
}

/**
 * Variant 11 — ramp rows: one ramp per row band, hue-ordered, each step a column span.
 * The organised layout an artist would build by hand, and the baseline to beat.
 */
export function buildRampRows(ctx) {
  const { grid, palette, counts } = ctx;
  const groups = rampGroups(palette);
  const cells = new Int32Array(grid.w * grid.h).fill(-1);

  const budget = groups.map((g) => g.indices.reduce((a, i) => a + counts[i], 0));
  const rows = apportion(budget, grid.h);
  let row = 0;
  for (let g = 0; g < groups.length; g++) {
    const members = groups[g].indices;
    const cols = apportion(members.map((i) => counts[i]), grid.w);
    for (let r = 0; r < rows[g]; r++, row++) {
      let x = 0;
      members.forEach((entry, m) => {
        for (let c = 0; c < cols[m]; c++, x++) {
          const cell = row * grid.w + x;
          if (grid.mask[cell]) cells[cell] = entry;
        }
      });
      for (; x < grid.w; x++) if (grid.mask[row * grid.w + x]) cells[row * grid.w + x] = members[members.length - 1];
    }
  }
  for (const i of grid.active) if (cells[i] < 0) cells[i] = cells[i - grid.w] ?? 0;
  return ensureCoverage(cells, grid, palette.entries.length);
}

/** Variant 12 — value spiral: darkest at the centre, spiralling out to the lightest. */
export function buildSpiral(ctx) {
  const order = ctx.palette.entries
    .map((e, i) => ({ i, L: e.actual.L }))
    .sort((a, b) => a.L - b.L || a.i - b.i)
    .map((x) => x.i);
  return fillRuns(ctx.grid, spiralOrder(ctx.grid), order, ctx.counts);
}

/** Variant 13 — squarified treemap: one tile per hue family, subdivided by colour. */
export function buildTreemap(ctx) {
  const { grid, palette, counts } = ctx;
  const groups = rampGroups(palette);
  const cells = new Int32Array(grid.w * grid.h).fill(-1);

  const outer = squarify(
    groups.map((g) => g.indices.reduce((a, i) => a + counts[i], 0)),
    { x: 0, y: 0, w: grid.w, h: grid.h },
  );
  groups.forEach((g, gi) => {
    const inner = squarify(g.indices.map((i) => counts[i]), outer[gi]);
    g.indices.forEach((entry, mi) => paint(cells, grid, inner[mi], entry));
  });
  for (const i of grid.active) if (cells[i] < 0) cells[i] = 0;
  return ensureCoverage(cells, grid, palette.entries.length);
}

/**
 * Variant 14 — sphere unwrap: the palette's OKLab spread mapped onto a sphere and opened
 * out with a Lambert cylindrical projection, which is equal-area, so no region of colour
 * space is quietly given more of the surface than another.
 */
export function buildSphere(ctx) {
  const { grid, labs, counts } = ctx;
  const mean = [0, 1, 2].map((d) => labs.reduce((a, p) => a + p[d], 0) / labs.length);
  const spread = [0, 1, 2].map((d) => {
    const v = labs.reduce((a, p) => a + (p[d] - mean[d]) ** 2, 0) / labs.length;
    return Math.max(Math.sqrt(v), 1e-4);
  });

  const targets = Array.from(grid.active, (i) => {
    const x = grid.px[i] / grid.spanX;
    const y = grid.py[i] / grid.spanY;
    const lambda = 2 * Math.PI * x - Math.PI;
    const phi = Math.asin(Math.min(1, Math.max(-1, 2 * y - 1)));
    const dir = [Math.sin(phi), Math.cos(phi) * Math.cos(lambda), Math.cos(phi) * Math.sin(lambda)];
    return [0, 1, 2].map((d) => mean[d] + dir[d] * spread[d] * Math.SQRT2);
  });
  return assignByCapacity(grid, targets, labs, counts);
}

/** Split `total` across weights, every share at least 1, summing exactly to `total`. */
function apportion(weights, total) {
  const k = weights.length;
  const sum = weights.reduce((a, b) => a + b, 0) || k;
  const out = weights.map((w) => Math.max(1, Math.floor((total * w) / sum)));
  let used = out.reduce((a, b) => a + b, 0);
  while (used > total) {
    let big = 0;
    for (let i = 1; i < k; i++) if (out[i] > out[big]) big = i;
    if (out[big] <= 1) break;
    out[big]--;
    used--;
  }
  while (used < total) {
    let small = 0;
    for (let i = 1; i < k; i++) if (weights[i] / out[i] > weights[small] / out[small]) small = i;
    out[small]++;
    used++;
  }
  return out;
}

/** Paint a float rectangle into the cell grid. */
function paint(cells, grid, r, entry) {
  const x0 = Math.round(r.x);
  const y0 = Math.round(r.y);
  const x1 = Math.max(x0 + 1, Math.round(r.x + r.w));
  const y1 = Math.max(y0 + 1, Math.round(r.y + r.h));
  for (let y = y0; y < Math.min(grid.h, y1); y++) {
    for (let x = x0; x < Math.min(grid.w, x1); x++) {
      const i = y * grid.w + x;
      if (grid.mask[i]) cells[i] = entry;
    }
  }
}

/**
 * Squarified treemap (Bruls, Huizing & van Wijk): lay areas out as rows along the shorter
 * side, extending a row only while doing so improves its worst aspect ratio.
 */
function squarify(values, rect) {
  const total = values.reduce((a, b) => a + b, 0) || 1;
  const items = values.map((v, i) => ({ i, area: (v / total) * rect.w * rect.h }));
  const out = new Array(values.length);
  let free = { ...rect };
  let row = [];

  const worst = (candidate, side) => {
    const sum = candidate.reduce((a, b) => a + b.area, 0);
    const min = Math.min(...candidate.map((c) => c.area));
    const max = Math.max(...candidate.map((c) => c.area));
    const s2 = side * side;
    return Math.max((s2 * max) / (sum * sum), (sum * sum) / (s2 * min));
  };

  const flush = () => {
    const side = Math.min(free.w, free.h);
    const sum = row.reduce((a, b) => a + b.area, 0);
    const thick = sum / Math.max(side, 1e-9);
    let at = 0;
    for (const item of row) {
      const len = item.area / Math.max(thick, 1e-9);
      out[item.i] = free.w >= free.h
        ? { x: free.x, y: free.y + at, w: thick, h: len }
        : { x: free.x + at, y: free.y, w: len, h: thick };
      at += len;
    }
    free = free.w >= free.h
      ? { x: free.x + thick, y: free.y, w: free.w - thick, h: free.h }
      : { x: free.x, y: free.y + thick, w: free.w, h: free.h - thick };
    row = [];
  };

  for (const item of items) {
    const side = Math.min(free.w, free.h);
    if (row.length && worst([...row, item], side) > worst(row, side)) flush();
    row.push(item);
  }
  if (row.length) flush();
  return out;
}
