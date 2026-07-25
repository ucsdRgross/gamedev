// Parameter sweeps — "what does this knob actually do" (UX_PLAN U2.1).
//
// The generator is pure and fast, so the honest answer to "which way should I push this?" is
// not a sentence, it is five palettes. `paramSweep` walks one parameter across its range with
// everything else held; the panel draws the result under the slider, and the same function
// backs the colour-count size sweep and any future "show me the alternatives" view.
//
// DOM-free and deterministic: the sweep of a parameter is a function of the parameter set, so
// the UI can cache it per (name, params) and throw the cache away on the next edit.

import { PARAM_BY_NAME, PARAMS, coerceParam, isAngularParam } from './params.js';
import { generatePalette, paletteHexes } from './generate.js';

/** The colour counts the size sweep offers — the sizes real palettes are actually made at. */
export const SIZE_SWEEP = [8, 16, 24, 32, 48, 64];

/**
 * The values one parameter is swept across.
 *   enum -> every option, in schema order (the options ARE the sweep)
 *   bool -> [false, true]
 *   int  -> up to `n` distinct values across the range, deduplicated after rounding
 *   float-> `n` values from min to max inclusive
 */
export function sweepValues(spec, n = 5) {
  if (spec.type === 'enum') return [...spec.options];
  if (spec.type === 'bool') return [false, true];
  const count = Math.max(2, n);
  const out = [];
  for (let k = 0; k < count; k++) {
    const v = spec.min + ((spec.max - spec.min) * k) / (count - 1);
    out.push(spec.type === 'int' ? Math.round(v) : v);
  }
  return spec.type === 'int' ? [...new Set(out)] : out;
}

/** How a swept value is labelled under its strip. */
export function valueLabel(spec, value) {
  if (spec.type === 'enum') return String(value);
  if (spec.type === 'bool') return value ? 'on' : 'off';
  if (spec.type === 'int') return String(Math.round(value));
  const decimals = spec.step && spec.step < 0.01 ? 3 : 2;
  return Number(value).toFixed(decimals);
}

/**
 * `n` parameter sets that differ from `params` in exactly one field.
 * Each entry carries the swept value, its label, and whether it is the one closest to where
 * the parameter currently sits — which is what lets the panel mark "you are here".
 */
export function paramSweep(params, name, n = 5) {
  const spec = PARAM_BY_NAME.get(name);
  if (!spec) return [];
  const values = sweepValues(spec, n);
  const current = params[name];
  let nearest = 0;
  if (spec.type === 'enum' || spec.type === 'bool') {
    const at = values.indexOf(current);
    nearest = at >= 0 ? at : 0;
  } else {
    let best = Infinity;
    values.forEach((v, k) => {
      const d = Math.abs(Number(v) - Number(current));
      if (d < best) { best = d; nearest = k; }
    });
  }
  return values.map((value, k) => ({
    value,
    label: valueLabel(spec, value),
    current: k === nearest,
    params: { ...params, [name]: value },
  }));
}

/**
 * `paramSweep`, with each step's palette generated. Locks and overrides are passed through so
 * a preview shows the palette the user would actually get, pinned colours and all.
 */
export function sweepPalettes(params, name, n = 5, opts = {}) {
  return paramSweep(params, name, n).map((step) => {
    const palette = generatePalette(step.params, opts);
    return { ...step, palette, hexes: paletteHexes(palette) };
  });
}

// ---------------------------------------------------------------------------
// Dead controls (UX_PLAN U7.3 — item 35)
// ---------------------------------------------------------------------------

/**
 * How far a probe moves a numeric parameter, as a fraction of its range.
 *
 * One `step` is not enough on its own: a step below the seed's own u16 resolution changes
 * nothing for reasons that have nothing to do with a constraint, and calling that "clamped"
 * would be crying wolf. A tenth of the range is unambiguous — if that does nothing in either
 * direction, something is genuinely swallowing the control.
 */
const PROBE_FRACTION = 0.1;

/** The candidate values a probe tries either side of where a parameter currently sits. */
function probeValues(spec, value) {
  if (spec.type === 'bool') return { up: !value, down: !value };
  if (spec.type === 'enum') {
    const at = Math.max(0, spec.options.indexOf(value));
    return {
      up: spec.options[(at + 1) % spec.options.length],
      down: spec.options[(at - 1 + spec.options.length) % spec.options.length],
    };
  }
  const jump = Math.max(spec.step, (spec.max - spec.min) * PROBE_FRACTION);
  const wrap = (v) => (isAngularParam(spec.name) ? ((v % 360) + 360) % 360 : v);
  return {
    up: coerceParam(spec, wrap(Number(value) + jump)),
    down: coerceParam(spec, wrap(Number(value) - jump)),
  };
}

/**
 * Groups whose parameters decide no palette colour, by design.
 *
 * The reference-recolouring block is seed-encoded like everything else so that a pasted seed
 * reproduces the whole view, but it decides how *images* are re-rendered, not what colours the
 * palette holds. Measuring those controls against the palette would report fourteen dead
 * sliders that are working exactly as documented, which is how a warning stops being read.
 */
const PALETTE_BLIND_GROUPS = new Set(['recolor']);

/** True when this parameter is one that can change a palette colour at all. */
export function decidesColor(name) {
  const spec = PARAM_BY_NAME.get(name);
  return Boolean(spec) && !PALETTE_BLIND_GROUPS.has(spec.group);
}

/** Two parameter sets that generate the same colours. */
function sameColors(a, b, opts) {
  return paletteHexes(generatePalette(a, opts)).join() === paletteHexes(generatePalette(b, opts)).join();
}

/**
 * Whether moving one parameter changes the palette at all, from where it currently sits.
 *
 * This is the measurement behind "clamped" (item 35, and the single most frustrating class of
 * bug in any parameter UI): `l_mid_base` raised while the ramp is already pressed against
 * `l_light_anchor` moves nothing, and today the slider gives no sign of it. A control is called
 * dead only when a *tenth of its range* in **both** directions leaves every hex identical —
 * being at the end of its own range is reported separately, because that is the user's doing
 * and not a hidden constraint.
 *
 * Four palette generations, about 8 ms at K=32.
 */
export function paramEffect(params, name, opts = {}) {
  const spec = PARAM_BY_NAME.get(name);
  if (!spec) return { applies: false, moves: true, up: true, down: true, atMin: false, atMax: false };
  const numeric = spec.type === 'float' || spec.type === 'int';
  const atMin = numeric && Number(params[name]) <= spec.min + 1e-9;
  const atMax = numeric && Number(params[name]) >= spec.max - 1e-9;
  const applies = decidesColor(name);
  if (!applies) return { applies, moves: true, up: true, down: true, atMin, atMax };
  const probes = probeValues(spec, params[name]);
  const moved = (value) => value !== params[name]
    && !sameColors(params, { ...params, [name]: value }, opts);
  const up = moved(probes.up);
  const down = moved(probes.down);
  return { applies, moves: up || down, up, down, atMin, atMax };
}

/**
 * Parameters that are known to box other parameters in — the first place to look when a
 * control has gone dead. The lightness anchors are the documented case (PROGRESS.md: raising
 * `l_mid_base` alone does not lift the midtone, because the ramp is clamped inside the anchor
 * window); the rest are the other hard limits the pipeline applies after a value is read.
 */
export const FRAMING_PARAMS = [
  'l_dark_anchor', 'l_light_anchor', 'l_range_compress', 'l_step',
  'chroma_cap', 'chroma_base', 'color_count', 'hue_count', 'min_delta_e',
  'bits_r', 'bits_g', 'bits_b', 'gamut_map_mode',
];

/** How many palette generations `findClamp` may spend before giving up. */
const CLAMP_BUDGET = 900;

/** The values worth trying on a suspect: both ends of its range, or every other option. */
function releaseValues(spec, current) {
  if (spec.type === 'bool') return [!current];
  if (spec.type === 'enum') return spec.options.filter((o) => o !== current);
  return [spec.min, spec.max].filter((v) => Math.abs(v - Number(current)) > 1e-9);
}

/**
 * A gate: a parameter with few enough settings that trying it in combination with another is
 * affordable. Enums, booleans and the small counts are what actually switch whole blocks of
 * the pipeline on and off, and a control is sometimes held down by two of them at once.
 */
function isGate(spec) {
  return spec.type === 'enum' || spec.type === 'bool'
    || (spec.type === 'int' && spec.max - spec.min <= 8);
}

/** Suspects in the order worth trying: the known framers, then the neighbours, then the rest. */
function suspectOrder(spec) {
  const rank = (p) => (FRAMING_PARAMS.includes(p.name) ? 0 : p.group === spec.group ? 1 : 2);
  return PARAMS
    .filter((p) => p.name !== spec.name && p.name !== 'seed' && decidesColor(p.name))
    .sort((a, b) => rank(a) - rank(b));
}

/**
 * Which other parameter (or pair) is swallowing a dead control, or null.
 *
 * Verified rather than inferred, the same way a report-card fix is: a suspect is named only if
 * *changing it brings the dead control back to life*. The test isolates the control — both
 * palettes in the comparison are generated with the suspect already at its trial value — so a
 * suspect that merely changes the palette on its own is never mistaken for the culprit.
 *
 * Pairs are searched after singles because some controls are held down by two gates at once:
 * `custom_hue_1` does nothing until `hue_scheme` is Custom **and** `custom_hue_count` is above
 * zero, and naming only one of them would send somebody to a knob that changes nothing.
 *
 * Costs up to `CLAMP_BUDGET` generations (about two seconds at K=32) and usually far fewer, so
 * it is separate from `paramEffect`: the panel calls it when somebody asks why, not on every
 * edit.
 */
export function findClamp(params, name, opts = {}) {
  const spec = PARAM_BY_NAME.get(name);
  if (!spec || !decidesColor(name)) return null;
  const probes = probeValues(spec, params[name]);
  let budget = CLAMP_BUDGET;

  /** Does the control move once `base` is in force? Charged against the budget. */
  const revives = (base) => [probes.up, probes.down].some((v) => {
    if (v === params[name] || budget <= 0) return false;
    budget -= 2;
    return !sameColors(base, { ...base, [name]: v }, opts);
  });

  const suspects = suspectOrder(spec);
  for (const suspect of suspects) {
    for (const trial of releaseValues(suspect, params[suspect.name])) {
      if (budget <= 0) return null;
      if (revives({ ...params, [suspect.name]: trial })) {
        return { set: [{ name: suspect.name, label: suspect.label, value: trial }] };
      }
    }
  }

  const gates = suspects.filter(isGate);
  // Same-group pairs first: two knobs that gate each other almost always sit together in the
  // panel, and the budget is spent where the answer is likeliest to be.
  const pairs = [];
  for (let i = 0; i < gates.length; i++) {
    for (let j = i + 1; j < gates.length; j++) pairs.push([gates[i], gates[j]]);
  }
  pairs.sort((a, b) => (
    (a[0].group === spec.group && a[1].group === spec.group ? 0 : 1)
    - (b[0].group === spec.group && b[1].group === spec.group ? 0 : 1)
  ));
  for (const [a, b] of pairs) {
    for (const va of releaseValues(a, params[a.name])) {
      for (const vb of releaseValues(b, params[b.name])) {
        if (budget <= 0) return null;
        if (revives({ ...params, [a.name]: va, [b.name]: vb })) {
          return {
            set: [
              { name: a.name, label: a.label, value: va },
              { name: b.name, label: b.label, value: vb },
            ],
          };
        }
      }
    }
  }
  return null;
}

/** The same sweep, over the colour counts a palette is usually made at (item 31). */
export function sizeSweep(params, opts = {}) {
  return SIZE_SWEEP.map((size) => {
    const next = { ...params, color_count: size };
    const palette = generatePalette(next, opts);
    return {
      value: size,
      label: String(size),
      current: Math.abs(params.color_count - size) < 0.5,
      params: next,
      palette,
      hexes: paletteHexes(palette),
    };
  });
}
