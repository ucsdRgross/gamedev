// Parameter sweeps — "what does this knob actually do" (UX_PLAN U2.1).
//
// The generator is pure and fast, so the honest answer to "which way should I push this?" is
// not a sentence, it is five palettes. `paramSweep` walks one parameter across its range with
// everything else held; the panel draws the result under the slider, and the same function
// backs the colour-count size sweep and any future "show me the alternatives" view.
//
// DOM-free and deterministic: the sweep of a parameter is a function of the parameter set, so
// the UI can cache it per (name, params) and throw the cache away on the next edit.

import { PARAM_BY_NAME } from './params.js';
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
