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
import { patternPatch } from '../patterns.js';
import { DEFAULT_SATURATIONS as DEFAULT_MAP_SATS } from './colorspace.js';
import {
  BANDING_DE, buildReachSlices, buildReferenceSlice, catalogueSections, patternWeights,
  preferredPattern, roughnessBand,
} from './reach.js';

const SHEET_BG = [22, 22, 28];
const SHEET_INK = [225, 225, 232];
const SHEET_DIM = [128, 128, 140];
const WARN_INK = [230, 140, 100];
const SEAM = [18, 18, 22];
const LABEL_H = 14;
const STRIP_W = 78; // width reserved for the "no slice reaches" swatch strip
const BAND_SWATCH = 20; // swatch size in the "which colours go where" layer bands
const BAND_TITLE_H = 7; // one line of the 3x5 pixel font plus leading

/**
 * The palette's layers in the order an artist reaches for them, and what each is for.
 *
 * The colour-space map answers "where is this colour"; it cannot answer "which colour belongs
 * in this job", because position there means hue/lightness and nothing else. The layers are
 * not decoration: `bg` is generated desaturated and pulled toward `atmosphere_hue`, and
 * `fg_bg_separation_min` is a hard constraint the repair pass enforces between the two sets
 * (PLAN §2.3). Painting a sprite in a background colour spends exactly the readability that
 * constraint bought. Anchors and neutrals are the ones legitimately shared by both.
 *
 * ASCII only — the pixel font draws anything else as a box glyph.
 */
const LAYER_GUIDE = [
  ['anchor', 'ANCHOR', 'OUTLINES + TOP HIGHLIGHT, SHARED BY EVERYTHING'],
  ['fg', 'FOREGROUND', 'CHARACTERS, ENEMIES, PROPS - HIGH CHROMA'],
  ['bg', 'BACKGROUND', 'TERRAIN, PARALLAX, SCENERY - KEEP OFF SPRITES'],
  ['neutral', 'NEUTRAL', 'STONE, METAL, UI CHROME'],
  ['neutral-warm', 'NEUTRAL WARM', 'SKIN, WOOD, PARCHMENT'],
  ['accent', 'ACCENT', 'UI POPS AND FX'],
  ['bridge', 'BRIDGE', 'TRANSITIONS BETWEEN ADJACENT RAMPS'],
];

/**
 * Palette entry indices grouped by layer, in artist-facing order, skipping layers this
 * palette does not have. Drives the "which colours go where" bands under the map.
 */
export function layerBands(palette) {
  return LAYER_GUIDE
    .map(([id, title, usage]) => ({
      id,
      title,
      usage,
      entries: palette.entries.reduce((acc, e, i) => (e.layer === id ? (acc.push(i), acc) : acc), []),
    }))
    .filter((b) => b.entries.length > 0);
}

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

  // "Which colours go where" bands sit under the slices: the map shows where a colour lives,
  // these show what it is *for*, which is the question the geometry cannot answer.
  const bands = layerBands(palette);
  const bandsH = bandsHeight(bands, f);

  const w = pad + cols * cellW + stripW;
  const h = pad + 22 + rows * cellH + bandsH;
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
    ? stripSwatches(labels, w, h, sliceSet.missing, w - stripW + pad, pad + 22, pad + 22 + rows * cellH, f)
    : [];

  // Band swatches are written into the same label buffer as everything else, so they hover
  // and click-to-copy exactly like the map does.
  const bandTop = pad + 22 + rows * cellH;
  writeBandLabels(labels, w, bands, bandTop, pad, f);

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
  drawBandText(sheet, bands, bandTop, pad, f);

  return { raster: sheet, labels, w, h };
}

/** Vertical space the "which colours go where" bands need. */
function bandsHeight(bands, f) {
  return bands.length ? 16 * f + bands.length * (BAND_TITLE_H + BAND_SWATCH + 6) * f : 0;
}

/** Write the band swatches into a label buffer so they hit-test like the maps do. */
function writeBandLabels(labels, w, bands, top, pad, f) {
  const rowH = (BAND_TITLE_H + BAND_SWATCH + 6) * f;
  const size = BAND_SWATCH * f;
  bands.forEach((b, bi) => {
    const y = top + 16 * f + bi * rowH + BAND_TITLE_H * f;
    let x = pad;
    for (const entry of b.entries) {
      if (x + size > w - pad) break;
      for (let py = y; py < y + size; py++) {
        for (let px = x; px < x + size; px++) labels[py * w + px] = entry;
      }
      x += size + f;
    }
  });
}

/** Captions for the bands, drawn after painting so no text pixel claims a label. */
function drawBandText(sheet, bands, top, pad, f) {
  if (!bands.length) return;
  const rowH = (BAND_TITLE_H + BAND_SWATCH + 6) * f;
  sheet.text('WHICH COLOURS GO WHERE', pad, top + 5 * f, f, SHEET_INK);
  bands.forEach((b, bi) => {
    sheet.text(`${b.title} - ${b.usage}`, pad, top + 16 * f + bi * rowH, f, SHEET_DIM);
  });
}

/**
 * The by-context view: one row per context, the saturation slices across it, in the same
 * hue×lightness style as the default map — because that spatial grouping (similar colours
 * adjacent, position meaning hue and lightness) is exactly what makes a map readable. The only
 * thing that changes per row is which colours are allowed to compete for a pixel, so a chart
 * answers "what may I use *here*" while keeping every colour where you already expect it.
 *
 * Composed in label space like every other sheet, so hover and click-to-copy work throughout.
 */
export function contextSheet(contextMaps, palette, { pad = 10, scale = 1, background = SHEET_BG } = {}) {
  const f = Math.max(1, scale | 0);
  const mw = Math.max(...contextMaps.map((c) => Math.max(...c.slices.map((s) => s.w)))) * f;
  const mh = Math.max(...contextMaps.map((c) => Math.max(...c.slices.map((s) => s.h)))) * f;
  const nSat = Math.max(...contextMaps.map((c) => c.slices.length));
  const rowTitleH = 18 * f;
  const rowH = rowTitleH + mh + pad;

  const bands = layerBands(palette);
  const bandTop = pad + 22 + contextMaps.length * rowH;
  const w = pad + nSat * (mw + pad);
  const h = bandTop + bandsHeight(bands, f);
  const labels = new Int32Array(w * h).fill(-1);

  contextMaps.forEach((c, ci) => {
    const oy = pad + 22 + ci * rowH + rowTitleH;
    c.slices.forEach((s, si) => {
      const ox = pad + si * (mw + pad);
      for (let y = 0; y < mh; y++) {
        const sy = Math.floor(y / f);
        if (sy >= s.h) break;
        for (let x = 0; x < mw; x++) {
          const sx = Math.floor(x / f);
          if (sx >= s.w) break;
          labels[(oy + y) * w + ox + x] = s.labels[sy * s.w + sx];
        }
      }
    });
  });

  writeBandLabels(labels, w, bands, bandTop, pad, f);
  const sheet = paintLabels(labels, w, h, palette, background);

  sheet.text(`${contextMaps[0]?.geometry.toUpperCase() ?? 'RECT'} MAPS BY CONTEXT - WHAT EACH JOB MAY USE`, pad, 6, f, SHEET_INK);
  contextMaps.forEach((c, ci) => {
    const y = pad + 22 + ci * rowH;
    sheet.text(`${c.context.title}  (${c.total} COLOURS, ${c.shownCount} SHOWN)`, pad, y, f, SHEET_INK);
    sheet.text(c.context.usage, pad, y + 7 * f, f, SHEET_DIM);
  });
  drawBandText(sheet, bands, bandTop, pad, f);

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

// ---------------------------------------------------------------------------
// The dither reference sheet
// ---------------------------------------------------------------------------

const PATCH_FLAT = 24; // the 1x tile — what it looks like at the size it will be used
const PATCH_ZOOM = 32; // the same tile magnified until the pattern is legible
const PATCH_CHIP = 12; // the flat optical average, for checking the 1x tile against
const PATCH_GAP = 2;
const PATCH_W = PATCH_FLAT + PATCH_GAP + PATCH_ZOOM + PATCH_GAP + PATCH_CHIP;
const PATCH_H = PATCH_ZOOM;
const CELL_GAP = 6;
const ROW_LABEL_H = 8;
const SECTION_HEAD_H = 18;

/**
 * The reach map is drawn at two resolutions, high above standard, because the same query at more
 * pixels resolves finer dither patterns and lands on more distinct blends — the low-resolution
 * map genuinely hides colours the palette can reach. The high tier is an exact 2× of the standard
 * tile so the two read as the same picture at two magnifications.
 */
const MAP_TIERS = [
  { id: 'hi', size: { w: 512, h: 256 }, title: 'HIGH RESOLUTION 2X - FINER DITHER, MORE DISTINCT COLOURS', reference: false },
  { id: 'lo', size: { w: 256, h: 128 }, title: 'STANDARD RESOLUTION - COMPLETE COLORMAP REFERENCE BESIDE WHAT THIS PALETTE REACHES', reference: true },
];
const MAP_LABEL_H = 9; // one caption line above each map panel
const MAP_TIER_HEAD = 11; // the tier heading

/**
 * Colours the reach-map overlay draws in, none of them palette colours — which is exactly why
 * they live in the declared `overlay` layer (see the `ditherSheet` doc). White for the outline
 * because it reads as a selection marquee over the mid-saturated boundary it traces, and it never
 * obscures a colour: it is one pixel on the *reachable* side, so every colour stays pickable
 * underneath, which is the whole reason it replaced the hatch.
 */
const REACH_OUTLINE = [245, 245, 250];

/** Advance per character of the 3×5 pixel font at scale 1 — glyph plus its 1px spacing. */
const GLYPH_ADVANCE = 4;

/** Width a caption will occupy, so the sheet can be sized to hold it instead of clipping it. */
function textWidth(str, scale = 1) {
  return String(str).length * GLYPH_ADVANCE * scale;
}

/**
 * The dithering reference view (PLAN §9.3): everything this palette can reach by mixing, and
 * every way to mix it.
 *
 * Two halves, answering two different questions.
 *
 * **The reach map** is the headline, and it is drawn as a *comparison* rather than a single
 * picture, because the one question it has to answer — is a colour missing, or can I dither to it?
 * — is only answerable against a reference. So each saturation slice appears as up to three panels
 * side by side:
 *
 *   * **COMPLETE** — the true, palette-agnostic colormap at that saturation: what a perfect palette
 *     would show. This is the reference the other two are read against.
 *   * **REACHABLE** — every pixel painted with the *dither pattern* of the nearest reachable blend,
 *     so it is a literal bandless colormap made of nothing but palette colours. Left plain, with no
 *     marks at all, so any colour on it can be picked even where the palette is stretching to reach
 *     it.
 *   * **REACHABLE, OUTLINED** — the same map with a white contour around the regions that are
 *     within a just-noticeable difference of their true colour. The outline *selects the available
 *     area* without covering a single colour, which the old diagonal hatch could not do.
 *
 * The whole map is drawn at two resolutions, high above standard, because the same nearest-colour
 * query at more pixels resolves finer dither and lands on more distinct blends — the low-resolution
 * map genuinely hides colours the palette can reach.
 *
 * **The catalogue** is the comprehensive half: every pattern, every ratio, the smooth pairs, the
 * contrasting pairs and the three- and four-colour blends, each drawn three ways — at 1×, zoomed
 * until the tile is legible, and as the flat colour it optically averages to.
 *
 * Composed in label space like every other sheet in this file, so hover, click-to-copy and export
 * are the one `pickAt` path. Two buffers ride alongside it:
 *
 *   * `patches` — a patch id per pixel into `patchTable`, so a hover can report the whole recipe
 *     (which colours, what ratio, which pattern) instead of just the one colour under the cursor.
 *     A dither patch is 2–4 entries and the label buffer only holds one; this is that gap closed.
 *   * `overlay` — packed RGB, applied *after* `paintLabels`. It holds the three kinds of pixel that
 *     are deliberately **not** palette colours: the flat average chips, the palette-agnostic
 *     reference colormaps, and the white selection outline. Keeping them in one declared layer is
 *     what lets the test assert that every *other* pixel is a palette colour, so the exception is
 *     visible and bounded rather than able to spread.
 */
export function ditherSheet(reach, {
  pad = 10, background = SHEET_BG, sections = null,
} = {}) {
  const { palette, stats } = reach;
  const cat = sections ?? catalogueSections(reach);

  // Build the reachable maps once per tier; plain and outlined share the same computed slice.
  const tierData = MAP_TIERS.map((tier) => ({
    tier,
    slices: buildReachSlices(reach, { geometry: 'rect', size: tier.size }).slices,
    refs: tier.reference
      ? DEFAULT_MAP_SATS.map((saturation) => buildReferenceSlice({ saturation, size: tier.size }))
      : null,
  }));

  // --- the captions, built before measuring so the sheet is wide enough for them ------------
  const pct = (v) => `${Math.round(v * 100)}%`;
  const title = 'DITHER REFERENCE - EVERY COLOUR THIS PALETTE CAN REACH BY MIXING';
  const headLines = [
    ['', SHEET_DIM],
    [`FLAT PALETTE      MEAN dE ${stats.flat.mean.toFixed(2)}   BAND-FREE ${pct(stats.flat.within)}`, SHEET_DIM],
    [`WITH DITHERING    MEAN dE ${stats.dithered.mean.toFixed(2)}   BAND-FREE ${pct(stats.dithered.within)}`, SHEET_INK],
    stats.floor
      ? [`BEST POSSIBLE     MEAN dE ${stats.floor.mean.toFixed(2)}   BAND-FREE ${pct(stats.floor.within)}`
        + '   (EST. - THE LIMIT OF THESE COLOURS AT ANY PATTERN AND ANY ARITY)', SHEET_DIM]
      : null,
    [`${stats.distinct} DISTINCT REACHABLE COLOURS FROM ${stats.k} - `
      + Object.entries(stats.byArity).map(([a, n]) => `${n} x${a}-WAY`).join(', '), SHEET_DIM],
    ['WHITE OUTLINE = REACHABLE WITHIN 2 dE. COMPARE "REACHABLE" AGAINST "COMPLETE" TO SEE WHAT IS MISSING', SHEET_DIM],
  ].filter(Boolean);

  // Columns per tier: a reference tier gets COMPLETE + REACHABLE + OUTLINED, the high-res tier
  // just the two reachable maps (its reference is the standard tier's, one scroll away).
  const colsOf = (tier) => (tier.reference ? 3 : 2);
  const tierWidth = (tier) => colsOf(tier) * (tier.size.w + pad) - pad;
  const tierHeight = (tier) => MAP_TIER_HEAD + DEFAULT_MAP_SATS.length * (MAP_LABEL_H + tier.size.h + pad);

  // --- measure --------------------------------------------------------------
  const cellW = PATCH_W + CELL_GAP;
  const widest = Math.max(...cat.map((s) => Math.max(...s.rows.map((r) => r.cells.length), 0)), 1);
  // The captions are as much a part of the sheet as the pictures. Measuring them here rather
  // than trusting them to fit is what stops a note being silently cut off at the right edge —
  // which is exactly what happened the first time this was rendered and read.
  const captions = [title, ...headLines.map(([s]) => s), ...cat.flatMap((s) => [s.title, s.note, ...s.rows.map((r) => r.label)])];
  const w = Math.max(
    pad * 2 + Math.max(...MAP_TIERS.map(tierWidth)),
    pad * 2 + widest * cellW,
    pad * 2 + Math.max(...captions.map((s) => textWidth(s))),
  );

  const headH = 8 + headLines.length * 7 + 4; // title plus the coverage block
  const mapsH = MAP_TIERS.reduce((a, t) => a + tierHeight(t) + pad, 0);
  const gapsH = 18 + (reach.suggestions.length ? PATCH_FLAT + 14 : 8);
  const sectionH = (s) => SECTION_HEAD_H + 8 + s.rows.reduce((a, r) => a + ROW_LABEL_H + PATCH_H + CELL_GAP, 0) + pad;
  const h = pad + headH + mapsH + gapsH + cat.reduce((a, s) => a + sectionH(s), 0) + pad;

  const labels = new Int32Array(w * h).fill(-1);
  const patches = new Int32Array(w * h).fill(-1);
  const overlay = new Int32Array(w * h).fill(-1);
  const patchTable = [];
  const tiles = new Map(); // blend id -> the pattern tile that draws it
  let unreachable = 0; // reach-map pixels a blend cannot bring within the banding threshold

  /** Paint one reachable slice at (ox, oy); `outline` adds the selection contour. */
  const paintReach = (slice, ox, oy, outline) => {
    for (let sy = 0; sy < slice.h; sy++) {
      for (let sx = 0; sx < slice.w; sx++) {
        const p = sy * slice.w + sx;
        const id = slice.ids[p];
        if (id < 0) continue;
        const at = (oy + sy) * w + ox + sx;
        // Paint the *dither*, not a flat approximation: the palette colour this blend's tile
        // holds at this position. So the map is the real thing, made of palette colours only.
        const tile = tileFor(tiles, reach.blends[id]);
        labels[at] = tile.entries[tile.slots[(sy % tile.n) * tile.n + (sx % tile.n)]];
        patches[at] = patchIdFor(patchTable, reach, id);
        if (outline && onReachBoundary(slice, sx, sy)) overlay[at] = pack(REACH_OUTLINE);
      }
    }
  };

  /** Paint a palette-agnostic reference colormap into the overlay at (ox, oy). */
  const paintReference = (ref, ox, oy) => {
    for (let sy = 0; sy < ref.h; sy++) {
      for (let sx = 0; sx < ref.w; sx++) {
        const c = ref.rgb[sy * ref.w + sx];
        if (c >= 0) overlay[(oy + sy) * w + ox + sx] = c;
      }
    }
  };

  // --- the reach map --------------------------------------------------------
  const mapLabels = []; // {text, x, y} captions drawn after painting
  let y = pad + headH;
  for (const { tier, slices, refs } of tierData) {
    mapLabels.push({ text: tier.title, x: pad, y, ink: SHEET_INK });
    const rowW = tier.size.w + pad;
    slices.forEach((slice, i) => {
      const rowTop = y + MAP_TIER_HEAD + i * (MAP_LABEL_H + tier.size.h + pad);
      let col = 0;
      const place = (label) => {
        const ox = pad + col * rowW;
        mapLabels.push({ text: label, x: ox, y: rowTop, ink: SHEET_DIM });
        col += 1;
        return { ox, oy: rowTop + MAP_LABEL_H };
      };
      const flat = stats.flatBySlice[i];
      if (refs) {
        const ref = place(`SAT ${slice.saturation.toFixed(2)}  COMPLETE - THE REFERENCE`);
        paintReference(refs[i], ref.ox, ref.oy);
      }
      const plain = place(`SAT ${slice.saturation.toFixed(2)}  REACHABLE  ${pct(flat.within)} -> ${pct(slice.within)} BAND-FREE`);
      paintReach(slice, plain.ox, plain.oy, false);
      const outlined = place(`SAT ${slice.saturation.toFixed(2)}  REACHABLE - OUTLINED`);
      paintReach(slice, outlined.ox, outlined.oy, true);
      if (tier.id === 'lo') {
        for (let p = 0; p < slice.error.length; p++) if (slice.ids[p] >= 0 && slice.error[p] > BANDING_DE) unreachable++;
      }
    });
    y += tierHeight(tier) + pad;
  }

  // --- the gap report -------------------------------------------------------
  const gapsTop = y;
  const suggestionX = (i) => pad + i * (PATCH_FLAT + 96);
  reach.suggestions.forEach((s, i) => {
    fillRect(overlay, w, suggestionX(i), gapsTop + 18, PATCH_FLAT, PATCH_FLAT, pack(s.rgb8));
  });
  y += gapsH;

  // --- the catalogue --------------------------------------------------------
  const sectionTops = [];
  for (const section of cat) {
    sectionTops.push(y);
    let ry = y + SECTION_HEAD_H + 8;
    for (const row of section.rows) {
      row.cells.forEach((cellData, i) => {
        drawPatch(
          { labels, patches, overlay, w },
          cellData,
          pad + i * cellW,
          ry + ROW_LABEL_H,
          patchIdForCell(patchTable, reach, cellData),
        );
      });
      ry += ROW_LABEL_H + PATCH_H + CELL_GAP;
    }
    y += sectionH(section);
  }

  // --- paint ----------------------------------------------------------------
  const sheet = paintLabels(labels, w, h, palette, background);
  for (let i = 0; i < overlay.length; i++) {
    if (overlay[i] < 0) continue;
    const p = i * 3;
    sheet.data[p] = (overlay[i] >> 16) & 255;
    sheet.data[p + 1] = (overlay[i] >> 8) & 255;
    sheet.data[p + 2] = overlay[i] & 255;
  }

  // --- text (last, over background pixels only, ASCII only) -----------------
  sheet.text(title, pad, 6, 1, SHEET_INK);
  headLines.forEach(([str, ink], n) => { if (str) sheet.text(str, pad, 6 + (n + 1) * 7, 1, ink); });
  for (const m of mapLabels) sheet.text(m.text, m.x, m.y, 1, m.ink);

  sheet.text(unreachable
    ? 'WHERE "REACHABLE" IS DARKER THAN "COMPLETE" AND OUTSIDE THE OUTLINE, NO BLEND REACHES THAT COLOUR AT ALL'
    : 'EVERY SAMPLED COLOUR IS REACHABLE WITHIN 2 dE - THE OUTLINE ENCLOSES THE WHOLE MAP', pad, gapsTop, 1, unreachable ? WARN_INK : SHEET_DIM);
  if (reach.suggestions.length) {
    sheet.text('ADD ONE OF THESE TO CLOSE THE REST:', pad, gapsTop + 9, 1, SHEET_INK);
    reach.suggestions.forEach((s, i) => {
      const x = suggestionX(i) + PATCH_FLAT + 4;
      sheet.text(s.hex, x, gapsTop + 22, 1, SHEET_INK);
      sheet.text(`dE ${stats.dithered.mean.toFixed(2)} -> ${s.after.mean.toFixed(2)}`, x, gapsTop + 31, 1, SHEET_DIM);
    });
  } else {
    sheet.text('NO COLOUR WORTH ADDING - WHAT REMAINS IS OUTSIDE ANY REACHABLE RANGE', pad, gapsTop + 9, 1, SHEET_DIM);
  }

  cat.forEach((section, si) => {
    const top = sectionTops[si];
    sheet.text(section.title, pad, top + 2, 1, SHEET_INK);
    sheet.text(section.note, pad, top + 10, 1, SHEET_DIM);
    let ry = top + SECTION_HEAD_H + 8;
    for (const row of section.rows) {
      sheet.text(row.label, pad, ry, 1, SHEET_DIM);
      ry += ROW_LABEL_H + PATCH_H + CELL_GAP;
    }
  });

  // `overlay` is returned, not just consumed: it *is* the declaration of where non-palette
  // colours are allowed, so `test/reach.test.js` can assert that every pixel outside it is a
  // palette colour. An undeclared exception is one that spreads. `unreachable` counts the
  // standard-tier pixels no blend brings within the banding threshold — zero on a palette that
  // covers colour space, which is what the greyscale honesty test keys on.
  return { raster: sheet, labels, patches, patchTable, overlay, w, h, tierData, unreachable };
}

/** The tile that draws a blend, cached per blend so a map pixel is one array lookup. */
function tileFor(cache, blend) {
  const hit = cache.get(blend.id);
  if (hit) return hit;
  const pattern = preferredFor(blend);
  const scaled = patternWeights(pattern, blend.weights);
  const made = {
    n: pattern.n,
    entries: blend.entries,
    slots: patternPatch(pattern, scaled, pattern.n, pattern.n),
  };
  cache.set(blend.id, made);
  return made;
}

/**
 * A blend's display pattern.
 *
 * Catalogue cells arrive with one already chosen (the PATTERNS section deliberately shows the
 * same colours in fourteen different ones); everything else falls back to `preferredPattern`, so
 * the "smallest tile that expresses these weights exactly" rule lives in `reach.js` alone.
 */
function preferredFor(blend) {
  return blend.pattern ?? preferredPattern(blend.weights);
}

/** Register a blend in the patch table once, returning its row index. */
function patchIdFor(table, reach, blendId) {
  const blend = reach.blends[blendId];
  if (blend.patchId === undefined) {
    // eslint-disable-next-line no-param-reassign
    blend.patchId = table.length;
    table.push(rowFor(reach, blend));
  }
  return blend.patchId;
}

function patchIdForCell(table, reach, cellData) {
  table.push(rowFor(reach, cellData));
  return table.length - 1;
}

function rowFor(reach, blend) {
  return {
    entries: [...blend.entries],
    weights: [...blend.weights],
    pattern: preferredFor(blend).id,
    patternTitle: preferredFor(blend).title,
    hex: blend.hex,
    rgb8: blend.rgb8,
    arity: blend.entries.length,
    roughness: blend.roughness,
    roughnessLabel: roughnessBand(blend.roughness).label,
    hexes: blend.entries.map((e) => reach.palette.entries[e].hex),
  };
}

/**
 * One catalogue patch: the tile at 1×, the same tile magnified until the pattern is legible, and
 * the flat colour it optically averages to.
 *
 * The chip is the part that earns its keep. A 1× tile and its average *should* be
 * indistinguishable at arm's length, so putting them side by side makes a wrong blend
 * calculation immediately visible by eye — which is the one thing no assertion in the test file
 * can check for you.
 */
function drawPatch(buffers, cell, x, y, patchId) {
  const { labels, patches, overlay, w } = buffers;
  const pattern = preferredFor(cell);
  const scaled = patternWeights(pattern, cell.weights);
  const { n } = pattern;

  // 1x — the tile repeated at the size it would actually be used.
  const flat = patternPatch(pattern, scaled, PATCH_FLAT, PATCH_FLAT);
  const flatTop = y + ((PATCH_H - PATCH_FLAT) >> 1);
  for (let py = 0; py < PATCH_FLAT; py++) {
    for (let px = 0; px < PATCH_FLAT; px++) {
      const at = (flatTop + py) * w + x + px;
      labels[at] = cell.entries[flat[py * PATCH_FLAT + px]];
      patches[at] = patchId;
    }
  }

  // Zoomed — one tile blown up to fill the block, so the pattern itself is readable.
  const zoom = Math.max(1, Math.floor(PATCH_ZOOM / n));
  const side = n * zoom;
  const zx = x + PATCH_FLAT + PATCH_GAP;
  const zy = y + ((PATCH_H - side) >> 1);
  const tile = patternPatch(pattern, scaled, n, n);
  for (let py = 0; py < side; py++) {
    for (let px = 0; px < side; px++) {
      const at = (zy + py) * w + zx + px;
      labels[at] = cell.entries[tile[((py / zoom) | 0) * n + ((px / zoom) | 0)]];
      patches[at] = patchId;
    }
  }

  // The flat optical average — the one non-palette colour, in the overlay layer.
  const cx = x + PATCH_FLAT + PATCH_GAP + PATCH_ZOOM + PATCH_GAP;
  const cy = y + ((PATCH_H - PATCH_CHIP) >> 1);
  fillRect(overlay, w, cx, cy, PATCH_CHIP, PATCH_CHIP, pack(cell.rgb8));
  for (let py = 0; py < PATCH_CHIP; py++) {
    for (let px = 0; px < PATCH_CHIP; px++) patches[(cy + py) * w + cx + px] = patchId;
  }
}

function fillRect(buffer, w, x, y, rw, rh, value) {
  for (let py = y; py < y + rh; py++) {
    for (let px = x; px < x + rw; px++) buffer[py * w + px] = value;
  }
}

function pack(rgb) {
  return (rgb[0] << 16) | (rgb[1] << 8) | rgb[2];
}

/**
 * Whether a slice pixel sits on the boundary of the reachable region: itself within the banding
 * threshold, with at least one in-shape 4-neighbour outside it (or at the very edge of the shape).
 *
 * Drawing the contour on the *reachable* side means the outline hugs the available area from
 * inside, so it never lands on — and never hides — an unreachable colour the artist might still
 * want to pick from.
 */
function onReachBoundary(slice, sx, sy) {
  const { w, h, error, ids } = slice;
  const at = sy * w + sx;
  if (ids[at] < 0 || error[at] > BANDING_DE) return false;
  for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
    const nx = sx + dx;
    const ny = sy + dy;
    if (nx < 0 || ny < 0 || nx >= w || ny >= h) return true; // the shape's own edge
    const ni = ny * w + nx;
    if (ids[ni] < 0 || error[ni] > BANDING_DE) return true; // borders unreachable / outside
  }
  return false;
}

/** The recipe under a pixel of a rendered dither sheet, or null. */
export function pickPatchAt(rendered, px, py) {
  const x = Math.floor(px);
  const y = Math.floor(py);
  if (!rendered.patches || x < 0 || y < 0 || x >= rendered.w || y >= rendered.h) return null;
  const id = rendered.patches[y * rendered.w + x];
  return id >= 0 ? rendered.patchTable[id] : null;
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
