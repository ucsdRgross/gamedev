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
export function buildColorMap(palette, {
  geometry = 'rect', saturation = 1, size = null, entries = null,
} = {}) {
  if (!MAP_GEOMETRIES.includes(geometry)) throw new Error(`unknown map geometry: ${geometry}`);
  const dims = size ?? DEFAULT_MAP_SIZE[geometry];
  const { w, h } = dims;
  // `entries` restricts which palette slots may be painted — that is what turns this into a
  // per-context chart. The geometry is untouched, so a colour sits in the same place it does
  // on the full map; only the set competing for each pixel changes.
  const pool = entries ?? palette.entries.map((_, i) => i);
  const labs = flatLabs(palette, pool);
  const k = pool.length;
  const labels = new Int32Array(w * h).fill(-1);

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const hsl = mapSample(geometry, x, y, w, h, saturation);
      if (!hsl) continue;
      const lab = srgbToOklab(hslToSrgb(hsl.h, hsl.s, hsl.l));
      // nearestEntry indexes the pool; map it back to a real palette index so every label in
      // the buffer means the same thing everywhere in the picker.
      labels[y * w + x] = k ? pool[nearestEntry(labs, k, lab[0], lab[1], lab[2])] : -1;
    }
  }

  return { geometry, saturation, w, h, labels, pool, ...coverageOf(palette, labels, pool) };
}

/**
 * Build every saturation slice of one geometry, with the union of what they show.
 *
 * Returns `{ geometry, slices, shown, missing, shownCount, total }`, where `missing` is the
 * set of colours no slice reaches. Those are what the slice sheet draws as a swatch strip
 * beside the maps, so nothing is unreachable from the default view.
 */
export function buildMapSlices(palette, {
  geometry = 'rect', saturations = DEFAULT_SATURATIONS, size = null, entries = null,
} = {}) {
  const pool = entries ?? palette.entries.map((_, i) => i);
  const slices = saturations.map((saturation) => buildColorMap(palette, { geometry, saturation, size, entries: pool }));
  const union = new Set();
  for (const slice of slices) for (const i of slice.shown) union.add(i);
  const shown = [...union].sort((a, b) => a - b);
  const missing = pool.filter((i) => !union.has(i));
  return { geometry, slices, pool, shown, missing, shownCount: shown.length, total: pool.length };
}

/**
 * The contexts a palette gets picked *for*, each as the subset of the palette that belongs in
 * that job. Rendered as ordinary hue×lightness maps, so a colour keeps its position while the
 * chart answers the question the full map cannot: **what may I use here?**
 *
 * The sets are derived from the generator's own structure rather than invented. `fg` and `bg`
 * are two deliberately disjoint sets with `fg_bg_separation_min` enforced between them
 * (PLAN §2.3), so the sprite and scenery charts are near-complements — that separation is the
 * point, not an oversight. `anchor`, `neutral` and `bridge` are the genuinely shared tiers and
 * appear in most contexts. Where a semantic role says more than a layer does (UI states, fire
 * and gold for effects) the role is used, which is what `palette.semantics` is for.
 *
 * `includes(entry, facts)` receives palette-derived facts so a context can be relative to the
 * palette (the aerial band is "the lighter half of the backgrounds", not a fixed lightness).
 */
export const MAP_CONTEXTS = [
  {
    id: 'all',
    title: 'EVERYTHING',
    usage: 'THE WHOLE PALETTE - THE REFERENCE VIEW',
    includes: () => true,
  },
  {
    id: 'sprites',
    title: 'SPRITES & PROPS',
    usage: 'CHARACTERS, ENEMIES, ITEMS - THE FOREGROUND SIDE',
    includes: (e) => ['anchor', 'fg', 'bridge', 'neutral', 'neutral-warm'].includes(e.layer),
  },
  {
    id: 'scenery',
    title: 'BACKGROUNDS & TERRAIN',
    usage: 'GROUND, WALLS, PARALLAX - KEEP THESE OFF SPRITES',
    includes: (e) => ['anchor', 'bg', 'bridge', 'neutral'].includes(e.layer),
  },
  {
    id: 'sky',
    title: 'SKY & ATMOSPHERE',
    usage: 'GRADIENTS, HAZE, DISTANCE - THE AERIAL BAND',
    // Backgrounds are already pulled toward `atmosphere_hue`, so the aerial band is their
    // lighter half plus the light anchor — what a sky gradient is actually built from.
    includes: (e, f) => e.id === LIGHT_ANCHOR
      || (['bg', 'neutral'].includes(e.layer) && e.actual.L >= f.bgMidL),
  },
  {
    id: 'ui',
    title: 'UI & HUD',
    usage: 'PANELS, TEXT, BARS, ICONS - LEGIBILITY FIRST',
    includes: (e, f) => ['anchor', 'neutral', 'neutral-warm', 'accent'].includes(e.layer)
      || f.uiRoles.has(e.id),
  },
  {
    id: 'fx',
    title: 'FX & EMISSIVE',
    usage: 'PARTICLES, GLOWS, MAGIC, FIRE - THE BRIGHT END',
    // Effects read as light sources: the accents, the light anchor, the top half of every
    // foreground ramp, and whatever the palette assigned to fire/gold.
    includes: (e, f) => e.layer === 'accent'
      || e.id === LIGHT_ANCHOR
      || (e.layer === 'fg' && e.steps > 1 && e.step >= (e.steps - 1) / 2)
      || f.fxRoles.has(e.id),
  },
];

const LIGHT_ANCHOR = 'universal_light';

/** Palette-derived facts the context predicates close over. */
function contextFacts(palette) {
  const bgL = palette.entries.filter((e) => e.layer === 'bg').map((e) => e.actual.L).sort((a, b) => a - b);
  const sem = palette.semantics ?? {};
  return {
    bgMidL: bgL.length ? bgL[Math.floor(bgL.length / 2)] : 0,
    uiRoles: new Set([sem.ui_good, sem.ui_bad, sem.ui_neutral].filter(Boolean)),
    fxRoles: new Set([sem.fire, sem.gold, sem.blood].filter(Boolean)),
  };
}

/** Palette entry indices belonging to one context. */
export function contextEntries(palette, context) {
  const facts = contextFacts(palette);
  const out = [];
  palette.entries.forEach((e, i) => { if (context.includes(e, facts)) out.push(i); });
  return out;
}

/** Fewer colours than this and a chart is a couple of solid blocks, so it is not drawn. */
const MIN_CONTEXT_COLOURS = 3;

/**
 * A slice set per context.
 *
 * Two contexts are dropped rather than drawn. **Too small** (under `MIN_CONTEXT_COLOURS`): at
 * K=8 there are no backgrounds at all, so "sky" is one colour and charting it says nothing.
 * **Duplicate**: a small palette may not reach the background rounds, which makes "sprites"
 * literally the whole palette — drawing it twice under two headings would imply a distinction
 * the palette does not have. First definition in `MAP_CONTEXTS` order wins.
 */
export function buildContextMaps(palette, {
  geometry = 'rect', saturations = DEFAULT_SATURATIONS, size = null, contexts = MAP_CONTEXTS,
} = {}) {
  const seen = new Set();
  return contexts
    .map((context) => ({ context, entries: contextEntries(palette, context) }))
    .filter((c) => {
      if (c.entries.length < MIN_CONTEXT_COLOURS) return false;
      const key = c.entries.join(',');
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .map((c) => ({ ...c, ...buildMapSlices(palette, { geometry, saturations, size, entries: c.entries }) }));
}

/** Which palette entry is under a pixel of a map, or -1 outside its shape. */
export function mapPickAt(map, px, py) {
  const x = Math.floor(px);
  const y = Math.floor(py);
  if (x < 0 || y < 0 || x >= map.w || y >= map.h) return -1;
  return map.labels[y * map.w + x];
}

/** Palette entries as one flat Float64Array of OKLab triples — the inner loop's working set. */
function flatLabs(palette, pool) {
  const out = new Float64Array(pool.length * 3);
  pool.forEach((entry, i) => {
    const lab = palette.entries[entry].lab;
    out[i * 3] = lab[0];
    out[i * 3 + 1] = lab[1];
    out[i * 3 + 2] = lab[2];
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
function coverageOf(palette, labels, pool) {
  const hexes = new Set();
  for (let i = 0; i < labels.length; i++) if (labels[i] >= 0) hexes.add(palette.entries[labels[i]].hex);
  const shown = [];
  const missing = [];
  // Counted against the pool, not the whole palette: a context chart cannot be blamed for
  // failing to show a colour that does not belong in that context.
  for (const i of pool) (hexes.has(palette.entries[i].hex) ? shown : missing).push(i);
  return { shown, missing, shownCount: shown.length, total: pool.length };
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
