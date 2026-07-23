// The Randomize button's logic, kept DOM-free so it is unit-testable (app.js is not).
//
// Randomize varies the palette's *look* and nothing else. It deliberately leaves three sorts
// of parameter alone:
//
//  - **Structure/hardware/quality** (`RANDOMIZE_SKIP`) — changing these would move slots
//    around or invalidate the swatch grid, so locked colours would jump.
//  - **The whole `recolor` group** (`RANDOMIZE_SKIP_GROUP`) — dither, downscale, remap mode
//    and friends decide how *reference images* are re-rendered. That is an output/workflow
//    choice set deliberately, not part of the palette's look, so rerolling it on every press
//    is just something to undo (the repo owner hit exactly this). Excluded by group, so any
//    recolour parameter added later is covered for free.
//  - **`seed`** — set explicitly at the end to a fresh value; it is what actually rerolls.

import { PARAMS, coerceParam } from '../core/params.js';
import { rngInt, rngRange, rngPick } from '../core/rng.js';

/** Parameters Randomize never touches, by name — structure, hardware and quality. */
export const RANDOMIZE_SKIP = new Set([
  'color_count', 'fg_ramp_length', 'bg_ramp_length',
  'bits_r', 'bits_g', 'bits_b', 'quantize_mode', 'gamut_map_mode',
  'min_delta_e', 'min_anchor_contrast', 'force_unique_hex', 'dither_evenness',
]);

/** Parameter group Randomize never touches — the reference-recolouring output settings. */
export const RANDOMIZE_SKIP_GROUP = 'recolor';

/** True when Randomize is allowed to reroll `spec`. */
export function isRandomizable(spec) {
  return !RANDOMIZE_SKIP.has(spec.name)
    && spec.group !== RANDOMIZE_SKIP_GROUP
    && spec.name !== 'seed';
}

/** Draw a random in-range value for one parameter spec. */
function randomValue(spec, rng) {
  if (spec.type === 'bool') return rng() < 0.5;
  if (spec.type === 'enum') return rngPick(rng, spec.options);
  if (spec.type === 'int') return rngInt(rng, spec.min, spec.max);
  return coerceParam(spec, rngRange(rng, spec.min, spec.max));
}

/**
 * A randomized copy of `current`: every randomizable parameter gets a fresh value, the rest
 * are carried through untouched, and `seed` is rerolled last.
 */
export function randomizeParams(current, rng) {
  const next = { ...current };
  for (const spec of PARAMS) {
    if (isRandomizable(spec)) next[spec.name] = randomValue(spec, rng);
  }
  next.seed = rngInt(rng, 0, 65535);
  return next;
}
