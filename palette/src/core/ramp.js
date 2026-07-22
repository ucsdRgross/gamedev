// Ramp construction: lightness curves, the chroma Gaussian, and the three hue-shift
// models (PLAN §4). Everything here is pure OKLCH — gamut mapping happens later.

import { clamp, hueDelta, normHue } from './oklch.js';
import { lerpHue } from './hues.js';

/** Blend two numbers. */
const lerp = (a, b, t) => a + (b - a) * t;

/** Smallest lightness gap a ramp will leave between adjacent steps. */
const MIN_RAMP_STEP = 0.005;

/** Index of the "midtone" step within a ramp of `n` steps. */
export function midIndex(n) {
  if (n <= 1) return 0;
  if (n <= 3) return 1;
  return Math.max(2, Math.round((n - 1) * 0.4));
}

/** Lightness easing curve; all four are monotonically increasing on [0,1]. */
export function easeCurve(t, curve) {
  switch (curve) {
    case 'ease-dark': return t * t;
    case 'ease-light': return 1 - (1 - t) * (1 - t);
    case 's-curve': return t * t * (3 - 2 * t);
    default: return t;
  }
}

/**
 * Lightness headroom kept between ramp extremes and the universal anchors.
 * Flooring shadows exactly at the anchor collapses dark bases into duplicates of it.
 */
export function anchorMargin(params) {
  return Math.max(0.02, (params.min_delta_e / 100) * 1.5);
}

/** The [low, high] lightness window ramps are allowed to occupy. */
export function rampBounds(params) {
  const m = anchorMargin(params);
  const lo = params.l_dark_anchor + m;
  const hi = params.l_light_anchor - m;
  return hi - lo < 0.05 ? [lo, lo + 0.05] : [lo, hi];
}

/** Lightness values for an `n`-step ramp centred on `lMid`, clamped inside the anchors. */
export function rampLightness(n, params, lMid, bounds) {
  const [lo, hi] = bounds;
  if (n <= 0) return [];
  if (n === 1) return [clamp(lerp(clamp(lMid, lo, hi), 0.5, params.l_range_compress), 0, 1)];

  const m = midIndex(n);
  let span = (n - 1) * params.l_step;
  if (span > hi - lo) span = hi - lo;
  let low = clamp(lMid, lo, hi) - (m / (n - 1)) * span;
  if (low < lo) low = lo;
  if (low + span > hi) low = hi - span;

  const out = new Array(n);
  for (let j = 0; j < n; j++) {
    const t = j / (n - 1);
    const eased = lerp(easeCurve(t, params.l_curve), t, params.dither_evenness);
    const L = low + eased * span;
    // Re-clamp into the anchor window, not into [0,1]. `l_range_compress` pulls toward the
    // mid grey, and when the anchors sit on one side of it — a "dark" anchor above 0.5, say
    // — that pull can drag a ramp step straight past the anchor it is supposed to stay
    // inside. Only the anchors may occupy the extremes (see generate.js).
    out[j] = clamp(lerp(L, 0.5, params.l_range_compress), lo, hi);
  }

  // Heavy range compression (or a tiny step) can collapse several steps onto the same
  // lightness, which leaves the repair pass no room to separate them and stops the
  // ramp being a ramp. Re-spread to a strictly increasing minimum.
  const need = (n - 1) * MIN_RAMP_STEP;
  if (out[n - 1] - out[0] < need) {
    const width = Math.min(need, hi - lo);
    const centre = (out[0] + out[n - 1]) / 2;
    const from = clamp(centre - width / 2, lo, Math.max(lo, hi - width));
    for (let j = 0; j < n; j++) out[j] = from + (j / (n - 1)) * width;
  }
  return out;
}

/** Chroma at a lightness: Gaussian peak plus directional falloff (PLAN §4). */
export function chromaAt(L, base, lMid, params) {
  const d = L - params.chroma_peak_l;
  const g = Math.exp(-(d * d) / (2 * params.chroma_curve_width * params.chroma_curve_width));
  const step = Math.max(0.01, params.l_step);
  let C = base * g;
  C -= (params.chroma_falloff_light * Math.max(0, L - lMid)) / step;
  C -= (params.chroma_falloff_dark * Math.max(0, lMid - L)) / step;
  return clamp(C, 0, params.chroma_cap);
}

/** Reduce chroma and pull hue toward ochre — earth tones, not dead grey. */
export function applyEarthiness(C, h, earthiness) {
  if (earthiness <= 0) return { C, h };
  return {
    C: C * (1 - 0.6 * earthiness),
    h: lerpHue(h, 55, 0.35 * earthiness),
  };
}

/** Bias a colour warm or cool across the whole palette. */
export function applyGlobalTemperature(C, h, gt) {
  if (gt === 0) return { C, h };
  const target = gt > 0 ? 60 : 250;
  return { C: C * (1 + Math.abs(gt) * 0.06), h: lerpHue(h, target, Math.abs(gt) * 0.2) };
}

/** Light and shadow hue targets per colour family — closest to how painters work. */
export function familyTargets(h) {
  const a = normHue(h);
  if (a < 45) return { light: 55, shadow: 320 };
  if (a < 105) return { light: 95, shadow: 25 };
  if (a < 170) return { light: 110, shadow: 200 };
  if (a < 260) return { light: 190, shadow: 265 };
  if (a < 310) return { light: 300, shadow: 275 };
  return { light: 355, shadow: 300 };
}

/** Maximum rotation, in degrees, that relative-rotation applies at full strength. */
const MAX_ROTATION = 60;

/**
 * Shift a base hue toward light or shadow.
 * `u` is the signed, normalised position in the ramp: +1 is the brightest step, -1 the
 * darkest, 0 the midtone.
 */
export function shiftHue(base, u, params) {
  // temperature_split scales the split and, below 0.25, inverts it: cool lights and
  // warm shadows, which is what makes toxic/alien palettes read as deliberately wrong.
  const uu = u * (2 * params.temperature_split - 0.5);
  if (uu === 0) return normHue(base);
  const toLight = uu > 0;
  const strength = toLight ? params.highlight_shift_strength : params.shadow_shift_strength;
  const w = clamp(strength * Math.min(1, Math.abs(uu)), 0, 1);
  if (w === 0) return normHue(base);

  let target;
  if (params.shift_model === 'per-family') {
    const t = familyTargets(base);
    target = toLight ? t.light : t.shadow;
  } else {
    target = toLight ? params.highlight_hue_target : params.shadow_hue_target;
  }

  if (params.shift_model === 'relative-rotation') {
    const d = hueDelta(base, target);
    let sigma;
    if (params.shift_direction === 'always-cw') sigma = 1;
    else if (params.shift_direction === 'always-ccw') sigma = -1;
    else sigma = d === 0 ? 1 : Math.sign(d);
    // Never overshoot the target: rotating past it would move the highlight further
    // from the attractor than the midtone, breaking the shift-direction invariant.
    const limit = params.shift_direction === 'shortest' ? Math.abs(d) : 360;
    return normHue(base + sigma * Math.min(w * MAX_ROTATION, limit));
  }

  return lerpHue(base, target, w, params.shift_direction);
}

/**
 * Build one ramp in OKLCH.
 * `chromaScale` and `lOffset` are how background ramps differ from foreground ones.
 */
export function buildRamp({
  hue,
  steps,
  params,
  lMid,
  chromaBase,
  bounds,
  chromaScale = 1,
  lOffset = 0,
}) {
  const ls = rampLightness(steps, params, lMid + lOffset, bounds);
  const m = midIndex(steps);
  const below = Math.max(1, m);
  const above = Math.max(1, steps - 1 - m);
  return ls.map((L, j) => {
    const u = j === m ? 0 : j < m ? (j - m) / below : (j - m) / above;
    let C = chromaAt(L, chromaBase, lMid, params) * chromaScale;
    let h = shiftHue(hue, u, params);
    ({ C, h } = applyEarthiness(C, h, params.earthiness));
    ({ C, h } = applyGlobalTemperature(C, h, params.global_temperature));
    return { L, C: clamp(C, 0, 0.37), h: normHue(h), step: j, mid: m };
  });
}
