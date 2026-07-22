// Colour-space maps (PLAN §9.1) — the picker's default view, and a completely different
// mechanism from the arrangement layouts in this directory (ARCHITECTURE §11).
//
// Take a standard HSL picker geometry, work out which colour each output pixel *represents*,
// and paint the nearest palette colour to it. Nothing is arranged and nothing is optimised,
// so position means exactly what it means in any other colour picker: you always know where
// to look. There is no cell grid, so boundaries are exact at whatever resolution the map is
// sampled at — no upsampling, no curvature flow, and **no outlines, ever**.
//
// The honest cost is coverage: a colour only appears where it is some pixel's nearest
// neighbour, so a colour hemmed in by its neighbours can occupy a sliver or be absent from a
// slice entirely. That is reported (`shownCount / total`), never faked — forcing a colour in
// would make position stop meaning what it says, which is the only thing the map has over
// the arrangement layouts.

import { deltaEOK, normHue, srgbToOklab } from '../oklch.js';

/** The two picker geometries: a hue×lightness rectangle and a round painter's wheel. */
export const MAP_GEOMETRIES = ['rect', 'polar'];

/**
 * The saturation slices shown together by default. A palette's colours do not all live at
 * one saturation, so one slice can never be the whole story; these run from fully saturated
 * to nearly neutral, and the last one is what surfaces the greys.
 */
export const DEFAULT_SATURATIONS = [1, 0.7, 0.4, 0.12];

/** Default sampling resolution per geometry — the rect is 2:1 because hue is the long axis. */
export const DEFAULT_MAP_SIZE = { rect: { w: 384, h: 192 }, polar: { w: 240, h: 240 } };

/** Convert HSL (hue in degrees, s and l in 0..1) to gamma-encoded sRGB floats in 0..1. */
export function hslToSrgb(h, s, l) {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = normHue(h) / 60;
  const x = c * (1 - Math.abs((hp % 2) - 1));
  const m = l - c / 2;
  if (hp < 1) return [c + m, x + m, m];
  if (hp < 2) return [x + m, c + m, m];
  if (hp < 3) return [m, c + m, x + m];
  if (hp < 4) return [m, x + m, c + m];
  if (hp < 5) return [x + m, m, c + m];
  return [c + m, m, x + m];
}

/**
 * The HSL colour a map position represents, or `null` for pixels outside the shape.
 *
 * **rect** — x is hue and y is lightness, white along the top edge and black along the
 * bottom. Hue spans the *inclusive* range 0–360, so the leftmost and rightmost columns are
 * literally the same hue and the map reads as wrapping (asserted in `test/colorspace.test.js`).
 *
 * **polar** — angle is hue, radius is lightness: white at the centre, black at the rim, so
 * lightness falls away from the start of the axis exactly as it does down the rectangle.
 * Hue 0 points straight up and increases clockwise, the conventional wheel orientation.
 */
export function mapSample(geometry, x, y, w, h, saturation) {
  if (geometry === 'rect') {
    return { h: w > 1 ? (360 * x) / (w - 1) : 0, s: saturation, l: h > 1 ? 1 - y / (h - 1) : 1 };
  }
  const radius = Math.min(w, h) / 2;
  const dx = x - (w - 1) / 2;
  const dy = y - (h - 1) / 2;
  const r = Math.sqrt(dx * dx + dy * dy);
  if (r > radius) return null;
  const angle = normHue(Math.atan2(dx, -dy) * (180 / Math.PI));
  return { h: angle, s: saturation, l: 1 - Math.min(1, r / radius) };
}

/**
 * Paint one saturation slice: a label per pixel naming the nearest palette entry, plus an
 * honest account of which palette colours the slice actually shows.
 *
 * Returns `{ geometry, saturation, w, h, labels, shown, missing, shownCount, total }`.
 * `labels` is -1 outside the shape (the corners of a polar map) and a palette index
 * everywhere else — never an outline, because there are none.
 */
export function buildColorMap(palette, { geometry = 'rect', saturation = 1, size = null } = {}) {
  if (!MAP_GEOMETRIES.includes(geometry)) throw new Error(`unknown map geometry: ${geometry}`);
  const dims = size ?? DEFAULT_MAP_SIZE[geometry];
  const { w, h } = dims;
  const labs = flatLabs(palette);
  const k = palette.entries.length;
  const labels = new Int32Array(w * h).fill(-1);

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const hsl = mapSample(geometry, x, y, w, h, saturation);
      if (!hsl) continue;
      const lab = srgbToOklab(hslToSrgb(hsl.h, hsl.s, hsl.l));
      labels[y * w + x] = nearestEntry(labs, k, lab[0], lab[1], lab[2]);
    }
  }

  return { geometry, saturation, w, h, labels, ...coverageOf(palette, labels) };
}

/**
 * Build every saturation slice of one geometry, with the union of what they show.
 *
 * Returns `{ geometry, slices, shown, missing, shownCount, total }`, where `missing` is the
 * set of colours no slice reaches. Those are what the slice sheet draws as a swatch strip
 * beside the maps, so nothing is unreachable from the default view.
 */
export function buildMapSlices(palette, { geometry = 'rect', saturations = DEFAULT_SATURATIONS, size = null } = {}) {
  const slices = saturations.map((saturation) => buildColorMap(palette, { geometry, saturation, size }));
  const union = new Set();
  for (const slice of slices) for (const i of slice.shown) union.add(i);
  const shown = [...union].sort((a, b) => a - b);
  const missing = palette.entries.map((_, i) => i).filter((i) => !union.has(i));
  return { geometry, slices, shown, missing, shownCount: shown.length, total: palette.entries.length };
}

/** Which palette entry is under a pixel of a map, or -1 outside its shape. */
export function mapPickAt(map, px, py) {
  const x = Math.floor(px);
  const y = Math.floor(py);
  if (x < 0 || y < 0 || x >= map.w || y >= map.h) return -1;
  return map.labels[y * map.w + x];
}

/** Palette entries as one flat Float64Array of OKLab triples — the inner loop's working set. */
function flatLabs(palette) {
  const out = new Float64Array(palette.entries.length * 3);
  palette.entries.forEach((e, i) => {
    out[i * 3] = e.lab[0];
    out[i * 3 + 1] = e.lab[1];
    out[i * 3 + 2] = e.lab[2];
  });
  return out;
}

/**
 * Index of the nearest palette entry to an OKLab colour. Compares squared distance — the
 * ordering is identical and this runs once per output pixel — and breaks ties toward the
 * lower index, so a map is a pure function of its palette.
 */
function nearestEntry(labs, k, L, a, b) {
  let best = 0;
  let bestD = Infinity;
  for (let i = 0, p = 0; i < k; i++, p += 3) {
    const dL = L - labs[p];
    const da = a - labs[p + 1];
    const db = b - labs[p + 2];
    const d = dL * dL + da * da + db * db;
    if (d < bestD) { bestD = d; best = i; }
  }
  return best;
}

/**
 * Which palette colours a label map shows. Counted by *colour*, not by slot: a palette may
 * hold the same hex twice (`force_unique_hex` is best-effort, ARCHITECTURE §6) and only the
 * lower index can ever win the nearest-colour tie, so counting slots would under-report what
 * is visibly on screen.
 */
function coverageOf(palette, labels) {
  const hexes = new Set();
  for (let i = 0; i < labels.length; i++) if (labels[i] >= 0) hexes.add(palette.entries[labels[i]].hex);
  const shown = [];
  const missing = [];
  palette.entries.forEach((e, i) => (hexes.has(e.hex) ? shown : missing).push(i));
  return { shown, missing, shownCount: shown.length, total: palette.entries.length };
}

/**
 * Mean ΔE between a map position's true colour and the palette colour painted there — how
 * much the map is lying, in the units everything else in the picker is measured in.
 */
export function mapFidelity(map, palette, step = 3) {
  let sum = 0;
  let n = 0;
  for (let y = 0; y < map.h; y += step) {
    for (let x = 0; x < map.w; x += step) {
      const entry = map.labels[y * map.w + x];
      if (entry < 0) continue;
      const hsl = mapSample(map.geometry, x, y, map.w, map.h, map.saturation);
      sum += deltaEOK(srgbToOklab(hslToSrgb(hsl.h, hsl.s, hsl.l)), palette.entries[entry].lab);
      n++;
    }
  }
  return n ? sum / n : 0;
}
