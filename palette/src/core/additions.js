// Adding a colour the palette cannot reach (UX_PLAN U7.4 — item 15).
//
// The dither reference already computes the answer: `suggestColors` in `layout/reach.js` runs a
// weighted k-means over the colour-space samples that *no blend of this palette* comes close
// to, and reports legal colours — realized through the palette's own bit depth and gamut mode —
// that would close the widest of those gaps. It is the most directly actionable number the
// whole tool produces, and until now it lived two tabs deep behind a Rebuild button.
//
// This module is the bridge: a cheap configuration of that search, and the one edit that turns
// a suggestion into a palette. Both are core, both are tested; the palette pane only draws them.

import { buildReach } from './layout/reach.js';
import { generatePalette } from './generate.js';
import { PARAM_BY_NAME, coerceParam } from './params.js';
import { hexToRgb8, rgb8ToOklab, deltaEOK } from './oklch.js';

/**
 * Reach options for the palette pane's version of the search.
 *
 * The picker's full build spends most of its time on the hull estimate — 400,000 random convex
 * combinations, to say what the *best possible* dithering would be — which is a statistic about
 * the palette rather than an answer to "what should I add". Dropping it takes the search from
 * about 800 ms to about 200 ms at K=32 and changes none of the suggestions, because they are
 * computed from the residual coverage and not from the floor.
 */
export const SUGGEST_OPTIONS = { hullTrials: 0, suggestions: 3 };

/**
 * The colours that would most close this palette's remaining gaps, best first.
 *
 * Each carries `after` — the coverage the palette would have *with that colour in it*, blends
 * and all, recomputed rather than estimated. An empty array is a real answer: it means nothing
 * is far enough from what dithering already reaches to be worth a slot.
 */
export function suggestAdditions(palette, options = {}) {
  return buildReach(palette, { ...SUGGEST_OPTIONS, ...options }).suggestions;
}

/** The entry whose colour is nearest an OKLab, or null for an empty list. */
function nearest(entries, lab) {
  let best = null;
  let bestD = Infinity;
  for (const e of entries) {
    const d = deltaEOK(e.lab, lab);
    if (d < bestD) { bestD = d; best = e; }
  }
  return best;
}

/**
 * Grow the palette by one slot and pin `hex` into it.
 *
 * Returns `{ params, locks, slotId }` to apply, or **null** when `color_count` is already at
 * its ceiling — a colour cannot be added to a palette that has no room, and quietly replacing
 * an existing one instead would be an edit nobody asked for.
 *
 * Which slot gets the colour is decided by measurement, not by position: raising the count
 * re-runs the whole budget allocation, so the slots that appear are wherever the extra colour
 * was spent. The new colour goes into the *new* slot nearest to it, which is the one whose
 * displacement costs the palette least. If the allocation reshuffles so completely that no slot
 * id is new — possible at small sizes, where one more colour lengthens a ramp instead of adding
 * one — the nearest unpinned slot takes it instead.
 */
export function addColorSlot(params, hex, { locks = {}, overrides = {} } = {}) {
  const spec = PARAM_BY_NAME.get('color_count');
  const count = coerceParam(spec, Number(params.color_count) + 1);
  if (count === params.color_count) return null;

  const before = new Set(generatePalette(params, { locks, overrides }).entries.map((e) => e.id));
  const next = { ...params, color_count: count };
  const grown = generatePalette(next, { locks, overrides });
  const lab = rgb8ToOklab(hexToRgb8(hex));
  const fresh = grown.entries.filter((e) => !before.has(e.id));
  const slot = nearest(fresh.length ? fresh : grown.entries.filter((e) => !e.fixed), lab);
  if (!slot) return null;
  return {
    params: next,
    locks: { ...locks, [slot.id]: String(hex).toUpperCase() },
    slotId: slot.id,
  };
}
