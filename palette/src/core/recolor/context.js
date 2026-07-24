// Context-aware recolouring: give the recolour a sense of what each colour is FOR.
//
// The recolour pipeline is otherwise purely colorimetric — it reads `rgb8 / lab / hex` and
// nothing else (ARCHITECTURE §12.5), so a source background colour lands wherever the ΔE
// happens to be smallest, which is regularly a target *foreground* slot. That throws away
// `fg_bg_separation_min`, the one hard constraint repair enforces between the two sets
// (PLAN §2.3): the source's foreground and background can arrive on top of each other.
//
// **The target side is free.** Every generated entry already carries `layer`, so the pools
// below are read off the generator's own structure rather than invented.
//
// **The source side is not, and this file does not pretend otherwise.** `inferContexts` is
// a heuristic over spatial statistics, and its accuracy was measured rather than assumed —
// see the honest numbers in `ARCHITECTURE.md` §12.8. It is right on art with a clear
// backdrop and wrong on full illustrations that have no foreground/background distinction to
// find. That is why the whole feature is **off by default** and why `contextOf` accepts
// caller-supplied overrides: the inference is a starting point a human corrects, not an
// authority.

import { deltaEOK, rgb8ToOklab } from '../oklch.js';

/**
 * The contexts a colour can belong to, as a **strictly disjoint** partition of the palette.
 *
 * Disjointness is the whole mechanism, and it is where this deliberately parts company with
 * `MAP_CONTEXTS` in `layout/colorspace.js`. Those overlap on purpose — sprites and scenery
 * both keep the anchors, because a *chart* should show a colour everywhere it is usable. Here
 * an overlap silently destroys the guarantee: if a source-fg and a source-bg colour can both
 * reach the same shared neutral, they can still collide, and measured on the gallery scenes
 * the overlapping pools recovered almost none of the lost separation (3.21 → 3.54 ΔE) while
 * the disjoint ones recovered all of it (3.21 → 10.29 ΔE). So the taxonomy is shared with the
 * picker; the partition is not.
 *
 * `layer` already partitions the palette, so this is a grouping of layers and cannot overlap
 * by construction — asserted in `test/recolor-context.test.js`.
 */
export const RECOLOR_CONTEXTS = [
  {
    id: 'anchor',
    title: 'OUTLINE & ANCHOR',
    usage: 'OUTLINES, THE DARKEST DARK AND LIGHTEST LIGHT',
    layers: ['anchor'],
  },
  {
    id: 'sprite',
    title: 'SPRITES & PROPS',
    usage: 'CHARACTERS, ENEMIES, ITEMS - THE FOREGROUND SIDE',
    layers: ['fg'],
  },
  {
    id: 'scenery',
    title: 'BACKGROUNDS & TERRAIN',
    usage: 'GROUND, WALLS, SKY, PARALLAX - KEEP THESE OFF SPRITES',
    layers: ['bg'],
  },
  {
    id: 'accent',
    title: 'FX & ACCENTS',
    usage: 'PARTICLES, GLOWS, ALERTS - THE HIGH-CHROMA END',
    layers: ['accent'],
  },
  {
    id: 'neutral',
    title: 'NEUTRALS & BRIDGES',
    usage: 'GREYS, METAL, STONE, UI CHROME',
    layers: ['neutral', 'neutral-warm', 'bridge'],
  },
];

/** Context ids, in declaration order. */
export const CONTEXT_IDS = RECOLOR_CONTEXTS.map((c) => c.id);

const LAYER_TO_CONTEXT = new Map();
for (const c of RECOLOR_CONTEXTS) for (const l of c.layers) LAYER_TO_CONTEXT.set(l, c.id);

/**
 * Target entry indices grouped by context, or **null** when the target palette carries no
 * layers at all.
 *
 * Null is the meaningful case, not a defensive shrug: a palette extracted from an image
 * (`swatches.js`) is deliberately just `{ rgb8, lab, hex }` — no params, no seed, no roles —
 * so there is no structure to map onto and the caller must fall back to the layer-blind path.
 * Returning null says that explicitly rather than handing back five empty pools that would
 * silently penalise every target equally.
 */
export function targetPools(entries) {
  const pools = new Map(CONTEXT_IDS.map((id) => [id, []]));
  let known = 0;
  entries.forEach((e, idx) => {
    const id = LAYER_TO_CONTEXT.get(e.layer);
    if (id === undefined) return;
    pools.get(id).push(idx);
    known++;
  });
  return known ? pools : null;
}

// --- Source-side signals ---------------------------------------------------

/**
 * Per-colour spatial and colorimetric statistics for one or more images.
 *
 * Taken **across** all frames at once for the same reason `recolorFrames` builds one mapping
 * from the combined colours: a colour whose share of the picture changes between frames must
 * not change context between frames, or the palette flickers.
 *
 * Returns one record per distinct colour, most frequent first:
 * - `coverage`    — fraction of all pixels
 * - `borderShare` — fraction of the outer ring it owns (a backdrop reaches the frame edge)
 * - `edginess`    — perimeter ÷ area (low = one flat field, high = thin scattered detail)
 * - `neighbours`  — how many distinct colours it abuts (an outline touches everything)
 * - `L`, `C`      — OKLab lightness and chroma
 */
export function colorSignals(images) {
  const list = Array.isArray(images) ? images : [images];
  const stats = new Map();
  let total = 0;
  let ring = 0;

  for (const image of list) {
    const { w, h, data } = image;
    if (!w || !h) continue;
    total += w * h;
    ring += Math.max(1, 2 * (w + h) - 4);
    const keyAt = (x, y) => {
      const p = (y * w + x) * 3;
      return (data[p] << 16) | (data[p + 1] << 8) | data[p + 2];
    };
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const key = keyAt(x, y);
        let s = stats.get(key);
        if (!s) {
          s = { key, count: 0, border: 0, boundary: 0, nbrs: new Set() };
          stats.set(key, s);
        }
        s.count++;
        if (x === 0 || y === 0 || x === w - 1 || y === h - 1) s.border++;
        let edge = false;
        if (x > 0) { const k = keyAt(x - 1, y); if (k !== key) { s.nbrs.add(k); edge = true; } }
        if (x < w - 1) { const k = keyAt(x + 1, y); if (k !== key) { s.nbrs.add(k); edge = true; } }
        if (y > 0) { const k = keyAt(x, y - 1); if (k !== key) { s.nbrs.add(k); edge = true; } }
        if (y < h - 1) { const k = keyAt(x, y + 1); if (k !== key) { s.nbrs.add(k); edge = true; } }
        if (edge) s.boundary++;
      }
    }
  }

  const out = [];
  for (const s of stats.values()) {
    const rgb = [(s.key >> 16) & 255, (s.key >> 8) & 255, s.key & 255];
    const lab = rgb8ToOklab(rgb);
    out.push({
      key: s.key,
      count: s.count,
      coverage: total ? s.count / total : 0,
      borderShare: ring ? s.border / ring : 0,
      edginess: s.count ? s.boundary / s.count : 0,
      neighbours: s.nbrs.size,
      L: lab[0],
      C: Math.hypot(lab[1], lab[2]),
    });
  }
  // Ties break on the colour key, so the order is a property of the images alone.
  return out.sort((a, b) => b.count - a.count || a.key - b.key);
}

// A backdrop owns a serious share of the frame edge and is *flat* — one big region rather
// than scattered detail. Both halves are needed: a dithered sky reaches the border too, but
// its perimeter-to-area ratio gives it away as texture.
const BACKDROP_BORDER = 0.25;
const BACKDROP_EDGINESS = 0.5;
// An outline is at the dark end, thin, and abuts more colours than anything else does.
const OUTLINE_L_BAND = 0.06;
const OUTLINE_EDGINESS = 0.35;
// An accent is small and the most saturated thing present.
const ACCENT_COVERAGE = 0.02;
const NEUTRAL_CHROMA = 0.02;

/**
 * Guess a context for every source colour. **Every colour gets one** — this deliberately does
 * not abstain on images where the answer is unclear, because a partly-assigned image would
 * mix two different mapping regimes in one picture and read worse than either alone. The
 * repo owner's call: apply it everywhere and accept that some images come out wrong.
 *
 * Measured accuracy and the reason it cannot be better are in ARCHITECTURE §12.8. Callers
 * that know better should pass `overrides`.
 */
export function inferContexts(signals, overrides = null) {
  const out = new Map();
  if (!signals.length) return out;

  const chroma = signals.map((s) => s.C).sort((a, b) => a - b);
  const medianC = chroma[Math.floor(chroma.length / 2)];
  const maxC = chroma[chroma.length - 1];
  const darkest = signals.reduce((a, b) => (a.L <= b.L ? a : b)).L;
  const mostNeighbours = signals.reduce((a, b) => (a.neighbours >= b.neighbours ? a : b)).neighbours;

  for (const s of signals) {
    const override = overrides?.get(s.key);
    if (override && CONTEXT_IDS.includes(override)) { out.set(s.key, override); continue; }

    let id;
    if (s.L <= darkest + OUTLINE_L_BAND && s.edginess > OUTLINE_EDGINESS
      && s.neighbours >= mostNeighbours * 0.5) {
      id = 'anchor';
    } else if (s.borderShare > BACKDROP_BORDER && s.edginess < BACKDROP_EDGINESS) {
      id = 'scenery';
    } else if (s.coverage < ACCENT_COVERAGE && s.C > Math.max(medianC * 1.6, maxC * 0.6)) {
      id = 'accent';
    } else if (s.C < NEUTRAL_CHROMA) {
      id = 'neutral';
    } else {
      id = 'sprite';
    }
    out.set(s.key, id);
  }
  return out;
}

/**
 * The whole source-side step in one call: statistics, then a context per colour.
 * `overrides` is a `Map<colourKey, contextId>` of human corrections and always wins.
 */
export function sourceContexts(images, overrides = null) {
  return inferContexts(colorSignals(images), overrides);
}

// --- Applying it to the assignment ----------------------------------------

/**
 * How far out of its way the assignment will go to keep a colour in its own pool, as a ΔE
 * surcharge on every out-of-pool target. `bias` is the user-facing 0–1 knob:
 *
 * - **0** — no surcharge. Byte-identical to the layer-blind path, which is what makes
 *   `recolor_context` safe to leave wired up while off.
 * - **between** — a weighted preference, `bias × SOFT_PENALTY` **on the ΔE scale**. The
 *   assignment may still cross pools, but only when the colour match is better by more than
 *   the surcharge.
 * - **1** — `HARD_PENALTY`, far beyond any real ΔE, so crossing a pool happens only when
 *   nothing else is legal.
 *
 * **The soft range has to be scaled to ΔE, and getting that wrong makes the knob a placebo.**
 * The first cut interpolated straight to `HARD_PENALTY`, so even bias 0.2 was a 200 ΔE
 * surcharge — already unpayable, since `deltaEOK` is reported ×100 and black to white is only
 * 100. Every setting from 0.2 to 1.0 produced identical output, which the sweep caught and no
 * unit test would have. `SOFT_PENALTY` is 60 because that is the span real palette-internal
 * distances actually cover (5–50), so the knob buys a genuine preference across its range and
 * approaches the hard end smoothly.
 *
 * `HARD_PENALTY` is finite rather than `Infinity` on purpose: the Hungarian solver subtracts
 * duals from costs, and `Infinity - Infinity` is `NaN`, which would silently corrupt the
 * assignment instead of failing loudly.
 */
export const HARD_PENALTY = 1000;
export const SOFT_PENALTY = 25;

/**
 * Add the surcharge to a source-major ΔE cost matrix, in place. `srcContexts` is an array of
 * context ids aligned with the matrix's rows — one per source colour, in the same order.
 *
 * Expressing context as a cost rather than as a separate per-pool assignment is what keeps it
 * orthogonal to everything else in `indexed.js`: `delta-e`, `optimal` and the monotone
 * `remap_preserve_order` dynamic program all read this one matrix, so all three respect the
 * pools without any of them learning what a pool is.
 *
 * A source colour whose context has an empty pool is left alone — penalising every target
 * equally would change nothing but the numbers, and a palette with no accents should not push
 * its accents somewhere arbitrary.
 */
export function applyContextPenalty(cost, srcContexts, pools, k, bias) {
  if (!pools || !srcContexts || bias <= 0) return cost;
  const penalty = bias >= 1 ? HARD_PENALTY : bias * SOFT_PENALTY;

  const allowed = new Map();
  for (const [id, idx] of pools) {
    if (!idx.length) continue;
    const set = new Uint8Array(k);
    for (const j of idx) set[j] = 1;
    allowed.set(id, set);
  }

  srcContexts.forEach((id, i) => {
    const set = allowed.get(id);
    if (!set) return;
    for (let j = 0; j < k; j++) if (!set[j]) cost[i * k + j] += penalty;
  });
  return cost;
}
