// Drawing a layout. Lives in core so the browser picker and `tools/render.mjs` render the
// same pixels from the same code — the contact sheet inspected at the gate is the image
// the user is looking at in the app.
//
// **Optimise coarse, render fine.** The variants arrange colours on a 48×32 cell grid,
// which is all the resolution the *arrangement* needs and the only size that is affordable
// (build cost scales roughly quadratically with cell count — a 192×128 grid takes seconds).
// But a cell grid painted as solid blocks gives blob edges that can only ever step along
// that grid, which reads as a staircase. So rendering upsamples the assignment to display
// resolution and then relaxes the boundaries there:
//
//   coarse cells -> upsample to scale× -> curvature flow -> paint
//
// The relaxation is a mode (majority) filter, which is discrete curvature flow: a pixel
// joins whichever blob most surrounds it, so protrusions erode and notches fill, and the
// staircases become curves. Small radius, iterated — a big radius costs (2r+1)² per pixel
// and buys nothing a few more cheap passes do not.

import { oklabToOklch, oklchToOklab, deltaEOK } from '../oklch.js';
import { Raster } from '../raster.js';

const SHEET_BG = [22, 22, 28];
const SHEET_INK = [225, 225, 232];
const SHEET_DIM = [128, 128, 140];
const WARN_INK = [230, 140, 100];
const SEAM = [18, 18, 22];
const LABEL_H = 14;
const STRIP_W = 78; // width reserved for the "no slice reaches" swatch strip

const SMOOTH_RADIUS = 2;
const AREA_FLOOR = 0.35; // a blob may not be eroded below this fraction of its area

/** How blob boundaries are drawn. */
export const EDGE_MODES = ['none', 'shade', 'seam'];

/**
 * Render a layout at `scale` output pixels per cell, with smoothed boundaries.
 * Returns the pixels *and* the label map, so hit-testing matches what is on screen.
 */
export function renderLayout(layout, palette, {
  scale = 6, edges = 'none', smooth = null, background = SHEET_BG,
} = {}) {
  const { labels, w, h } = labelMap(layout, scale);
  const relaxing = smooth ?? !layout.rectilinear;
  if (relaxing && scale > 1) relax(labels, w, h, iterationsFor(scale), palette.entries.length);

  const raster = paintLabels(labels, w, h, palette, background);
  if (edges !== 'none') drawEdges(raster, labels, w, h, palette, edges);

  return { raster, labels, w, h, scale };
}

/**
 * Paint a label map into a fresh Raster: one palette colour per labelled pixel, `background`
 * where the label is -1. The only place labels become pixels, so both the arrangement
 * layouts and the colour-space maps are guaranteed to emit palette colours and nothing else.
 */
export function paintLabels(labels, w, h, palette, background = SHEET_BG) {
  const raster = new Raster(w, h, background);
  for (let i = 0; i < labels.length; i++) {
    if (labels[i] < 0) continue;
    const p = i * 3;
    const rgb = palette.entries[labels[i]].rgb8;
    raster.data[p] = rgb[0];
    raster.data[p + 1] = rgb[1];
    raster.data[p + 2] = rgb[2];
  }
  return raster;
}

/** Render a layout straight to a Raster, for callers that only want the pixels. */
export function layoutRaster(layout, palette, opts = {}) {
  return renderLayout(layout, palette, opts).raster;
}

/** Which palette entry is under a pixel of a rendered layout, or -1 outside it. */
export function pickAt(rendered, px, py) {
  const x = Math.floor(px);
  const y = Math.floor(py);
  if (x < 0 || y < 0 || x >= rendered.w || y >= rendered.h) return -1;
  return rendered.labels[y * rendered.w + x];
}

/** Enough passes to erode a staircase whose steps are `scale` pixels tall. */
function iterationsFor(scale) {
  return Math.max(2, Math.round(scale / SMOOTH_RADIUS));
}

/**
 * Upsample the cell assignment to display resolution. Round layouts get their disc mask
 * re-tested per output pixel rather than per cell, so the rim is a smooth circle instead
 * of a staircase of cell corners.
 */
function labelMap(layout, scale) {
  const { grid, cells } = layout;
  const hex = grid.topology === 'hex';
  const offset = hex ? Math.floor(scale / 2) : 0;
  const w = grid.w * scale + offset;
  const h = grid.h * scale;
  const labels = new Int32Array(w * h).fill(-1);

  const disc = grid.topology === 'disc';
  const cx = (w - 1) / 2;
  const cy = (h - 1) / 2;
  const r2 = (Math.min(w, h) / 2) ** 2;

  for (let y = 0; y < h; y++) {
    const gy = Math.min(grid.h - 1, Math.floor(y / scale));
    const shift = hex && gy & 1 ? offset : 0;
    for (let x = 0; x < w; x++) {
      if (disc && (x - cx) ** 2 + (y - cy) ** 2 > r2) continue;
      const gx = clamp(Math.floor((x - shift) / scale), 0, grid.w - 1);
      const cell = nearestActive(grid, gx, gy);
      if (cell >= 0) labels[y * w + x] = cells[cell];
    }
  }
  return { labels, w, h };
}

/** The cell itself if it is active, else the closest active cell in its 3×3 block. */
function nearestActive(grid, gx, gy) {
  const own = gy * grid.w + gx;
  if (grid.mask[own]) return own;
  for (let dy = -1; dy <= 1; dy++) {
    for (let dx = -1; dx <= 1; dx++) {
      const x = gx + dx;
      const y = gy + dy;
      if (x < 0 || y < 0 || x >= grid.w || y >= grid.h) continue;
      const i = y * grid.w + x;
      if (grid.mask[i]) return i;
    }
  }
  return -1;
}

/**
 * Discrete curvature flow over the label map: each pixel takes the label that most of its
 * neighbourhood holds, ties going to the label it already has. Updates are synchronous, so
 * the result does not depend on scan order.
 *
 * A blob may not be eroded below `AREA_FLOOR` of its area. Without that a one-cell colour
 * can be smoothed out of existence, and "every colour is somewhere" is the picker's whole
 * promise — a colour you cannot find is worse than a slightly rough edge.
 */
function relax(labels, w, h, iterations, k) {
  const original = tally(labels, k);
  const floor = new Int32Array(k);
  for (let e = 0; e < k; e++) floor[e] = Math.max(1, Math.floor(original[e] * AREA_FLOOR));

  const counts = new Int32Array(k);
  const touched = new Int32Array(k);
  let prev = labels;
  let next = new Int32Array(labels.length);

  for (let pass = 0; pass < iterations; pass++) {
    next.set(prev);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const at = y * w + x;
        const own = prev[at];
        if (own < 0) continue;
        let n = 0;
        let best = own;
        let bestCount = 0;
        for (let dy = -SMOOTH_RADIUS; dy <= SMOOTH_RADIUS; dy++) {
          const py = y + dy;
          if (py < 0 || py >= h) continue;
          for (let dx = -SMOOTH_RADIUS; dx <= SMOOTH_RADIUS; dx++) {
            const px = x + dx;
            if (px < 0 || px >= w) continue;
            const lab = prev[py * w + px];
            if (lab < 0) continue;
            if (counts[lab] === 0) touched[n++] = lab;
            counts[lab]++;
            // Ties go to the incumbent: `>` not `>=`, and `own` seeds the comparison.
            if (counts[lab] > bestCount || (counts[lab] === bestCount && lab === own)) {
              bestCount = counts[lab];
              best = lab;
            }
          }
        }
        for (let q = 0; q < n; q++) counts[touched[q]] = 0;
        next[at] = best;
      }
    }

    // Undo the pass for any colour it shrank past the floor, leaving the rest smoothed.
    const after = tally(next, k);
    for (let e = 0; e < k; e++) {
      if (after[e] >= floor[e]) continue;
      for (let i = 0; i < prev.length; i++) if (prev[i] === e) next[i] = e;
    }

    const swap = prev;
    prev = next;
    next = swap;
  }
  if (prev !== labels) labels.set(prev);
}

function tally(labels, k) {
  const out = new Int32Array(k);
  for (let i = 0; i < labels.length; i++) if (labels[i] >= 0) out[labels[i]]++;
  return out;
}

/**
 * Draw blob boundaries. `shade` is what a pixel artist would do — the edge is a darker,
 * hue-shifted colour *taken from the palette itself*, so the outline still reads as part
 * of the picture. `seam` is the flat dark line, kept only for diagrams.
 */
function drawEdges(raster, labels, w, h, palette, mode) {
  const shades = mode === 'shade' ? new Map() : null;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const at = y * w + x;
      const own = labels[at];
      if (own < 0) continue;
      const right = x + 1 < w ? labels[at + 1] : own;
      const down = y + 1 < h ? labels[at + w] : own;
      const other = right !== own ? right : (down !== own ? down : -1);
      if (other < 0) continue;
      const rgb = mode === 'seam' ? SEAM : shadeBetween(shades, palette, own, other);
      const p = at * 3;
      raster.data[p] = rgb[0];
      raster.data[p + 1] = rgb[1];
      raster.data[p + 2] = rgb[2];
    }
  }
}

/**
 * The palette colour that best reads as the shadow between two blobs: their midpoint,
 * darkened and shifted toward the cool end of the hue circle — the same move that makes
 * hand-drawn pixel shading look lit rather than dimmed.
 */
function shadeBetween(cache, palette, a, b) {
  const key = a < b ? a * 4096 + b : b * 4096 + a;
  const hit = cache.get(key);
  if (hit) return hit;

  const la = palette.entries[a].lab;
  const lb = palette.entries[b].lab;
  const mid = [0, 1, 2].map((d) => (la[d] + lb[d]) / 2);
  const { L, C, h } = oklabToOklch(mid[0], mid[1], mid[2]);
  const target = oklchToOklab(Math.max(0, L - 0.12), C * 0.9, (h + 20) % 360);

  let best = palette.entries[a];
  let bestD = Infinity;
  for (const e of palette.entries) {
    const d = deltaEOK(e.lab, target);
    if (d < bestD) { bestD = d; best = e; }
  }
  cache.set(key, best.rgb8);
  return best.rgb8;
}

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

/**
 * The default picker view: every saturation slice side by side, each labelled with how many
 * palette colours it actually shows, and the colours **no** slice shows drawn as a swatch
 * strip beside them.
 *
 * That strip is the whole reason the coverage trade is acceptable. A map may legitimately
 * fail to reach a colour (ARCHITECTURE §11) and forcing one in would break the only thing
 * the map has over the arrangement layouts — so the unreachable colours are shown *outside*
 * the geometry instead, where they cost the map's meaning nothing.
 */
export function mapSheet(sliceSet, palette, {
  columns = 0, pad = 10, scale = 1, background = SHEET_BG,
} = {}) {
  const f = Math.max(1, scale | 0);
  const sw = Math.max(...sliceSet.slices.map((s) => s.w)) * f;
  const sh = Math.max(...sliceSet.slices.map((s) => s.h)) * f;
  const cols = columns > 0 ? columns : sliceSet.slices.length;
  const rows = Math.ceil(sliceSet.slices.length / cols);
  const cellW = sw + pad;
  const cellH = sh + LABEL_H + pad;
  const stripW = sliceSet.missing.length ? STRIP_W * f : 0;

  const w = pad + cols * cellW + stripW;
  const h = pad + 22 + rows * cellH;
  const labels = new Int32Array(w * h).fill(-1);

  // The sheet is composed in *label* space and painted once, so hover, click-to-copy and
  // export all read the same buffer — and no drawing step can introduce a foreign colour.
  sliceSet.slices.forEach((s, i) => {
    const ox = pad + (i % cols) * cellW;
    const oy = pad + 22 + Math.floor(i / cols) * cellH + LABEL_H;
    for (let y = 0; y < sh; y++) {
      const sy = Math.floor(y / f);
      if (sy >= s.h) break;
      for (let x = 0; x < sw; x++) {
        const sx = Math.floor(x / f);
        if (sx >= s.w) break;
        labels[(oy + y) * w + ox + x] = s.labels[sy * s.w + sx];
      }
    }
  });

  const strip = stripW
    ? stripSwatches(labels, w, h, sliceSet.missing, w - stripW + pad, pad + 22, h - pad - 22, f)
    : [];

  const sheet = paintLabels(labels, w, h, palette, background);

  // Text goes on last, over background pixels only, so it never claims a label.
  // ASCII only: the pixel font draws anything else as a box (`src/core/pixelfont.js`).
  sheet.text(`${sliceSet.geometry.toUpperCase()} COLOUR-SPACE MAP - SHOWS ${sliceSet.shownCount}/${sliceSet.total}`, pad, 6, f, SHEET_INK);
  sliceSet.slices.forEach((s, i) => {
    const x = pad + (i % cols) * cellW;
    const y = pad + 22 + Math.floor(i / cols) * cellH;
    sheet.text(`SAT ${s.saturation.toFixed(2)}  ${s.shownCount}/${s.total}`, x, y, f, SHEET_DIM);
  });
  if (stripW) {
    sheet.text('NO SLICE', w - stripW + pad, pad + 22, f, WARN_INK);
    sheet.text('REACHES', w - stripW + pad, pad + 22 + 7 * f, f, WARN_INK);
    for (const s of strip) sheet.text(palette.entries[s.entry].hex.slice(1), s.x + s.size + 3 * f, s.y + Math.max(0, (s.size - 5 * f) >> 1), f, SHEET_DIM);
  }

  return { raster: sheet, labels, w, h };
}

/**
 * Label the swatches for the colours no slice reaches. They are labelled like any other
 * pixel, so the unreachable colours are hoverable and copyable rather than merely visible.
 */
function stripSwatches(labels, w, h, missing, x, y, bottom, f) {
  const top = y + 18 * f;
  const size = Math.max(6 * f, Math.min(18 * f, Math.floor((bottom - top) / Math.max(1, missing.length)) - f));
  const out = [];
  missing.forEach((entry, n) => {
    const sy = top + n * (size + f);
    if (sy + size > bottom) return;
    for (let py = sy; py < sy + size; py++) {
      for (let px = x; px < x + size; px++) labels[py * w + px] = entry;
    }
    out.push({ entry, x, y: sy, size });
  });
  return out;
}

/**
 * Contact sheet: every layout side by side under its title and score, so the whole set can
 * be compared at a glance — the image PLAN §9 asks for and GATE 4 is read against.
 */
export function contactSheet(layouts, palette, { scale = 3, edges = 'none', columns = 4, pad = 10 } = {}) {
  const tiles = layouts.map((l) => ({ layout: l, img: layoutRaster(l, palette, { scale, edges }) }));
  const cols = Math.min(columns, tiles.length);
  const rows = Math.ceil(tiles.length / cols);
  const cellW = Math.max(...tiles.map((t) => t.img.w)) + pad;
  const rowHs = [];
  for (let r = 0; r < rows; r++) {
    const slice = tiles.slice(r * cols, r * cols + cols);
    rowHs.push(Math.max(...slice.map((t) => t.img.h)) + LABEL_H * 2 + pad);
  }

  const width = pad + cols * cellW;
  const height = pad + 22 + rowHs.reduce((a, b) => a + b, 0);
  const sheet = new Raster(width, height, SHEET_BG);
  sheet.text('PICKER LAYOUTS — MEAN / WORST NEIGHBOUR DELTA-E', pad, 6, 1, SHEET_INK);

  tiles.forEach((t, idx) => {
    const col = idx % cols;
    const row = Math.floor(idx / cols);
    const x = pad + col * cellW;
    const y = pad + 22 + rowHs.slice(0, row).reduce((a, b) => a + b, 0);
    const label = `${t.layout.variant}. ${t.layout.title}`.toUpperCase();
    sheet.text(label.slice(0, Math.floor(cellW / 4)), x, y, 1, SHEET_INK);
    const score = `MEAN ${t.layout.score.mean.toFixed(2)}  WORST ${t.layout.score.worst.toFixed(1)}`;
    sheet.text(score, x, y + 7, 1, t.layout.optimized ? SHEET_DIM : [150, 120, 90]);
    sheet.blit(t.img, x, y + LABEL_H);
  });
  return sheet;
}
