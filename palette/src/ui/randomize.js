// Randomize and Vary — the two ways the app moves a palette without you naming a number.
// Kept DOM-free so both are unit-testable (app.js is not).
//
// **Randomize** (`randomizeParams`) draws every eligible parameter uniformly across its whole
// range. That is the right tool exactly once — at the start, when you have no palette yet and
// want to be surprised — and the wrong tool from then on, because it throws away whatever
// character the current palette had.
//
// **Vary** (`varyParams`, UX_PLAN U3.1 — item 5) is the tool for every other moment: it
// perturbs *around* the current values with a gaussian whose width is a fraction of each
// parameter's range, so a variant is recognisably the same palette. It also holds the
// decisions you have already made — the colour count, the hue scheme, how many hue families —
// because rerolling those does not give you a variation, it gives you a different palette.
//
// Both leave three sorts of parameter alone:
//
//  - **Structure/hardware/quality** (`RANDOMIZE_SKIP`) — changing these would move slots
//    around or invalidate the swatch grid, so locked colours would jump.
//  - **The whole `recolor` group** (`RANDOMIZE_SKIP_GROUP`) — dither, downscale, remap mode
//    and friends decide how *reference images* are re-rendered. That is an output/workflow
//    choice set deliberately, not part of the palette's look, so rerolling it on every press
//    is just something to undo (the repo owner hit exactly this). Excluded by group, so any
//    recolour parameter added later is covered for free.
//  - **`seed`** — set explicitly at the end to a fresh value; it is what actually rerolls.

import { PARAMS, PARAM_BY_NAME, coerceParam, isAngularParam } from '../core/params.js';
import { rngInt, rngRange, rngPick } from '../core/rng.js';

/** Parameters Randomize never touches, by name — structure, hardware and quality. */
export const RANDOMIZE_SKIP = new Set([
  'color_count', 'fg_ramp_length', 'bg_ramp_length',
  'bits_r', 'bits_g', 'bits_b', 'quantize_mode', 'gamut_map_mode',
  'min_delta_e', 'min_anchor_contrast', 'force_unique_hex', 'dither_evenness',
]);

/** Parameter group Randomize never touches — the reference-recolouring output settings. */
export const RANDOMIZE_SKIP_GROUP = 'recolor';

/**
 * What Vary additionally holds still: the decisions that define *which* palette this is
 * rather than how it looks. Vary is "another version of this", not "another palette".
 */
export const VARY_HOLD = new Set(['hue_scheme', 'hue_count', 'tier_priority']);

/** How wide a variant's gaussian is, as a fraction of each parameter's range. */
export const VARY_STRENGTHS = { subtle: 0.05, moderate: 0.13, wild: 0.3 };

/** True when Randomize is allowed to reroll `spec`. */
export function isRandomizable(spec) {
  return !RANDOMIZE_SKIP.has(spec.name)
    && spec.group !== RANDOMIZE_SKIP_GROUP
    && spec.name !== 'seed';
}

/** True when Vary is allowed to move `spec`. */
export function isVariable(spec, { includeStructure = false, fixed = null } = {}) {
  if (!isRandomizable(spec)) return false;
  if (fixed && fixed.has(spec.name)) return false;
  return includeStructure || !VARY_HOLD.has(spec.name);
}

/** Draw a random in-range value for one parameter spec. */
function randomValue(spec, rng) {
  if (spec.type === 'bool') return rng() < 0.5;
  if (spec.type === 'enum') return rngPick(rng, spec.options);
  if (spec.type === 'int') return rngInt(rng, spec.min, spec.max);
  return coerceParam(spec, rngRange(rng, spec.min, spec.max));
}

/** Roughly-standard-normal from three uniforms — the same trick `fit.js` uses. */
function gaussian(rng) {
  return (rng() + rng() + rng() - 1.5) * 2;
}

/** Hue angles wrap at 360 instead of clamping; everything else clamps (see ANGULAR_PARAMS). */
const isHue = isAngularParam;

/**
 * A value near `current`, at a distance drawn from a gaussian `strength` fractions of the
 * parameter's range wide. Enums and bools cannot be "near" anything, so they flip with a
 * probability that scales with strength.
 */
function nearbyValue(spec, current, rng, strength) {
  if (spec.type === 'bool') return rng() < strength ? !current : current;
  if (spec.type === 'enum') {
    if (rng() >= strength) return current;
    const others = spec.options.filter((o) => o !== current);
    return others.length ? rngPick(rng, others) : current;
  }
  const span = spec.max - spec.min;
  let v = Number(current) + gaussian(rng) * strength * span;
  if (isHue(spec.name)) v = ((v % 360) + 360) % 360;
  else v = Math.min(spec.max, Math.max(spec.min, v));
  return spec.type === 'int' ? Math.round(v) : v;
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

/**
 * A *variation* of `current` — the same palette, moved.
 *
 * `strength` is either a name from `VARY_STRENGTHS` or a number (the gaussian's width as a
 * fraction of each parameter's range). `includeStructure` lets it reroll the hue scheme and
 * family count as well; `fixed` is a list of parameter names to hold exactly (locked-in
 * decisions, or the parameter the user is currently dragging).
 */
export function varyParams(current, rng, opts = {}) {
  const { strength = 'moderate', includeStructure = false, fixed = [] } = opts;
  const width = typeof strength === 'number' ? strength : (VARY_STRENGTHS[strength] ?? VARY_STRENGTHS.moderate);
  const held = new Set(fixed);
  const next = { ...current };
  for (const spec of PARAMS) {
    if (!isVariable(spec, { includeStructure, fixed: held })) continue;
    next[spec.name] = coerceParam(spec, nearbyValue(spec, current[spec.name], rng, width));
  }
  // The seed only selects which wobble the three randomness knobs produce, so rerolling it is
  // part of "another version of this" rather than a change of look.
  if (!held.has('seed')) next.seed = rngInt(rng, 0, 65535);
  return next;
}

/**
 * How far two parameter sets are apart, as the mean fraction-of-range moved over the
 * parameters Vary is allowed to touch. Used by the tests to assert that a stronger setting
 * really does move further, and available to the UI as a "distance from where you were".
 */
export function paramDistance(a, b) {
  let sum = 0;
  let n = 0;
  for (const spec of PARAMS) {
    if (!isVariable(spec, { includeStructure: true })) continue;
    const x = a[spec.name];
    const y = b[spec.name];
    if (spec.type === 'enum' || spec.type === 'bool') sum += x === y ? 0 : 1;
    else {
      const span = spec.max - spec.min;
      const d = Math.abs(Number(y) - Number(x));
      sum += isHue(spec.name) ? Math.min(d, 360 - d) / span : d / span;
    }
    n++;
  }
  return n ? sum / n : 0;
}

/** The spec for a name, for callers that want to explain a variation. */
export const specOf = (name) => PARAM_BY_NAME.get(name);
