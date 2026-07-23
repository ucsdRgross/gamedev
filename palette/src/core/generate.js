// The generation pipeline (PLAN §2.7).
//
//   parameters + seed
//     -> hue set          (hues.js)
//     -> budget allocation (allocate.js)
//     -> per-slot OKLCH    (ramp.js)
//     -> gamut map         (gamut.js)
//     -> bit-depth quantise (quantize.js)
//     -> repair / dedupe   (repair.js)
//     -> apply locks and manual overrides
//     -> stable role ordering (roles.js)
//     -> Palette
//
// The order is fixed. In particular repair runs AFTER quantisation, because
// quantisation can collapse two distinct colours onto the same legal grid point.

import { snapParams } from './params.js';
import { makeRng } from './rng.js';
import { buildHues, hueGapCenters, lerpHue } from './hues.js';
import { allocate, buildSlots, effectiveHueCount } from './allocate.js';
import { buildRamp, rampBounds, applyGlobalTemperature } from './ramp.js';
import { gamutMap, gamutCusp } from './gamut.js';
import { quantizeSrgb } from './quantize.js';
import { repairPalette, residualViolations } from './repair.js';
import { roleName, assignSemanticRoles } from './roles.js';
import { encodeSeed } from './seed.js';
import {
  oklchToOklab, oklabToOklch, rgb8ToOklab, rgb8ToHex, hexToRgb8, normHue, clamp,
} from './oklch.js';

export { makeRng };

/**
 * Build the function that turns a requested OKLCH into a final, displayable entry.
 * Memoised: repair evaluates the same candidate positions again on every sweep, and
 * gamut mapping is a binary search, so the cache is worth far more than it costs.
 */
export function makeRealize(params) {
  const cache = new Map();
  return function realize(oklch) {
    const L = clamp(oklch.L, 0, 1);
    const C = Math.max(0, oklch.C);
    const h = normHue(oklch.h);
    const key = `${Math.round(L * 1e5)},${Math.round(C * 1e5)},${Math.round(h * 1e3)}`;
    const hit = cache.get(key);
    if (hit) return { ...hit, oklch: { ...hit.oklch } };
    const mapped = gamutMap(L, C, h, params.gamut_map_mode);
    const q = quantizeSrgb(mapped, params.bits_r, params.bits_g, params.bits_b, params.quantize_mode);
    const rgb8 = [Math.round(q[0] * 255), Math.round(q[1] * 255), Math.round(q[2] * 255)];
    const lab = rgb8ToOklab(rgb8);
    const out = {
      oklch: { L, C, h },
      actual: oklabToOklch(lab[0], lab[1], lab[2]),
      rgb8, lab, hex: rgb8ToHex(rgb8),
    };
    cache.set(key, out);
    return { ...out, oklch: { ...out.oklch } };
  };
}

/** Build an entry directly from a fixed hex, bypassing gamut mapping and quantisation. */
function realizeFixed(hex) {
  const rgb8 = hexToRgb8(hex);
  const lab = rgb8ToOklab(rgb8);
  const lch = oklabToOklch(lab[0], lab[1], lab[2]);
  return { oklch: { ...lch }, actual: lch, rgb8, lab, hex: rgb8ToHex(rgb8) };
}

/** Blend two OKLCH colours through OKLab, which keeps the result perceptually sane. */
function mixOklch(a, b, t) {
  const la = oklchToOklab(a.L, a.C, a.h);
  const lb = oklchToOklab(b.L, b.C, b.h);
  return oklabToOklch(
    la[0] + (lb[0] - la[0]) * t,
    la[1] + (lb[1] - la[1]) * t,
    la[2] + (lb[2] - la[2]) * t,
  );
}

/** Build the neutral ramp: stone, metal, UI chrome. */
function neutralRamp(count, hue, params, bounds) {
  const out = [];
  for (let k = 0; k < count; k++) {
    const t = count > 1 ? k / (count - 1) : 0.5;
    const L = clamp(0.5 - params.neutral_l_spread + t * 2 * params.neutral_l_spread, bounds[0], bounds[1]);
    const g = applyGlobalTemperature(params.neutral_chroma, hue, params.global_temperature);
    out.push({ L, C: g.C, h: g.h });
  }
  return out;
}

/** Build the high-chroma UI/FX accents. */
function accentColors(count, hues, params, bounds) {
  if (count <= 0) return [];
  let angles;
  if (params.accent_hue_mode === 'spectral-gap') {
    angles = hueGapCenters(hues, count);
  } else if (params.accent_hue_mode === 'complementary') {
    angles = Array.from({ length: count }, (_, k) => normHue(params.root_hue + 180 + k * 30));
  } else {
    angles = Array.from({ length: count }, (_, k) => normHue(params.root_hue + 150 + k * 40));
  }
  const C = Math.min(0.37, params.chroma_base + params.accent_chroma_boost);
  return angles.map((h, k) => {
    const L = clamp(params.accent_l + (k - (count - 1) / 2) * 0.07, bounds[0], bounds[1]);
    const g = applyGlobalTemperature(C, h, params.global_temperature);
    return { L, C: g.C, h: g.h };
  });
}

/** Pull a background colour toward the atmospheric hue — aerial perspective. */
function applyAtmosphere(color, params) {
  if (params.atmosphere_strength <= 0) return color;
  const target = {
    L: color.L,
    C: Math.min(color.C, params.chroma_base * params.bg_chroma_mult * 0.6),
    h: params.atmosphere_hue,
  };
  return mixOklch(color, target, params.atmosphere_strength * 0.5);
}

/**
 * How far `hue_lightness_follow: 1` pulls a hue's midtone toward its gamut cusp lightness.
 * Capped below 1 so even full follow leaves a step of highlight headroom under the light
 * anchor — the cusp for yellow/green sits ~0.9, and going all the way there would leave no
 * room for a brighter step. Tuned by eye against the reference render and the crayon fit.
 */
const HUE_L_FOLLOW_GAIN = 0.6;

/**
 * Midtone lightness for a hue: `l_mid_base`, biased toward the lightness where that hue can
 * actually hold chroma in sRGB (its gamut cusp). Yellow/green/cyan cusps sit high, so their
 * ramps ride up into the saturated zone instead of going olive at mid grey; blue/red/purple
 * cusps already sit near mid grey, so they barely move. `hue_lightness_follow` scales it.
 */
function hueMidLightness(params, hue) {
  const cuspL = gamutCusp(hue).L;
  const follow = params.hue_lightness_follow * HUE_L_FOLLOW_GAIN;
  return params.l_mid_base + (cuspL - params.l_mid_base) * follow;
}

/** Compute the requested OKLCH for every slot, before gamut mapping. */
function slotColors(params, plan, hues, rng) {
  const bounds = rampBounds(params);
  const lVar = [];
  const cVar = [];
  for (let i = 0; i < plan.hueCount; i++) {
    lVar.push((rng() * 2 - 1) * params.l_variance_per_hue);
    cVar.push((rng() * 2 - 1) * params.chroma_variance_per_hue);
  }

  const fg = [];
  const bg = [];
  for (let i = 0; i < plan.hueCount; i++) {
    const lMid = clamp(hueMidLightness(params, hues[i]) + lVar[i], 0.05, 0.95);
    const cBase = Math.max(0, params.chroma_base + cVar[i]);
    fg.push(buildRamp({
      hue: hues[i], steps: plan.fgLen[i], params, lMid, chromaBase: cBase, bounds,
    }));
    const bgHue = lerpHue(hues[i], params.atmosphere_hue, params.bg_hue_shift, 'shortest');
    bg.push(buildRamp({
      hue: bgHue, steps: plan.bgLen[i], params, lMid, chromaBase: cBase, bounds,
      chromaScale: params.bg_chroma_mult, lOffset: params.bg_lightness_offset,
    }).map((c) => applyAtmosphere(c, params)));
  }

  const neutrals = neutralRamp(plan.neutrals, params.neutral_temperature, params, bounds);
  const warmNeutrals = neutralRamp(
    plan.warmNeutrals, normHue(params.neutral_temperature + 180), params, bounds,
  );
  const accents = accentColors(plan.accents, hues, params, bounds);

  const bridges = [];
  for (let k = 0; k < plan.bridges; k++) {
    const a = fg[k % plan.hueCount];
    const b = fg[(k + 1) % plan.hueCount];
    if (!a?.length || !b?.length) {
      bridges.push({ L: params.l_mid_base, C: params.chroma_base, h: hues[k % plan.hueCount] });
      continue;
    }
    bridges.push(mixOklch(a[Math.min(a.length - 1, a[0].mid)], b[Math.min(b.length - 1, b[0].mid)], 0.5));
  }

  const anchorDark = {
    L: params.l_dark_anchor,
    C: Math.min(0.06, params.neutral_chroma * 2 + 0.02),
    h: params.shadow_hue_target,
  };
  const anchorLight = {
    L: params.l_light_anchor,
    C: Math.min(0.05, params.neutral_chroma * 1.5 + 0.012),
    h: params.highlight_hue_target,
  };

  return { fg, bg, neutrals, warmNeutrals, accents, bridges, anchorDark, anchorLight, bounds };
}

/** Look up the requested OKLCH for one slot. */
function colorForSlot(slot, colors) {
  switch (slot.layer) {
    case 'anchor': return slot.kind === 'dark' ? colors.anchorDark : colors.anchorLight;
    case 'fg': return colors.fg[slot.hueIndex][slot.step];
    case 'bg': return colors.bg[slot.hueIndex][slot.step];
    case 'neutral': return colors.neutrals[slot.step];
    case 'neutral-warm': return colors.warmNeutrals[slot.step];
    case 'accent': return colors.accents[slot.step];
    case 'bridge': return colors.bridges[slot.hueIndex];
    default: throw new Error(`unknown slot layer ${slot.layer}`);
  }
}

/**
 * Generate a palette from a parameter set. Pure: same params, locks and overrides
 * always yield byte-identical output.
 */
export function generatePalette(inputParams, { locks = {}, overrides = {} } = {}) {
  // Snapped, not merely normalised: the palette must correspond exactly to the seed
  // string it reports, and seed payloads quantise every parameter to 16 bits.
  const params = snapParams(inputParams);
  const rng = makeRng(params.seed);
  const hueCount = effectiveHueCount(params);
  const hues = buildHues(params, hueCount, rng);
  const plan = allocate(params);
  const slots = buildSlots(plan);
  const colors = slotColors(params, plan, hues, rng);
  const realize = makeRealize(params);

  const entries = slots.map((slot) => {
    const forced = overrides[slot.id] ?? locks[slot.id];
    const base = forced ? realizeFixed(forced) : realize(colorForSlot(slot, colors));
    // Only the anchors may occupy the extremes; repair keeps everything else inside
    // the ramp window, so `universal_light` stays the lightest colour by construction.
    const anchor = slot.layer === 'anchor';
    return {
      id: slot.id,
      role: roleName(slot),
      layer: slot.layer,
      hueIndex: slot.hueIndex ?? -1,
      step: slot.step ?? 0,
      steps: slot.steps ?? 1,
      lMin: anchor ? 0.005 : colors.bounds[0],
      lMax: anchor ? 0.995 : colors.bounds[1],
      locked: Object.prototype.hasOwnProperty.call(locks, slot.id),
      overridden: Object.prototype.hasOwnProperty.call(overrides, slot.id),
      fixed: Boolean(forced),
      ...base,
    };
  });

  const { warnings } = repairPalette(entries, params, realize);

  // Re-assert locks and overrides last: repair must never have the final say over a
  // colour the user chose explicitly.
  for (const e of entries) {
    const forced = overrides[e.id] ?? locks[e.id];
    if (forced) Object.assign(e, realizeFixed(forced));
  }

  const semantics = assignSemanticRoles(entries);
  return {
    params,
    hues,
    plan,
    entries,
    semantics,
    warnings,
    seed: encodeSeed(params, locks, overrides),
    locks: { ...locks },
    overrides: { ...overrides },
  };
}

/** Palette colours as `#RRGGBB` strings in stable slot order. */
export function paletteHexes(palette) {
  return palette.entries.map((e) => e.hex);
}

/** Look up a palette entry by slot id or semantic role name. */
export function entryFor(palette, key) {
  const id = palette.semantics[key] ?? key;
  return palette.entries.find((e) => e.id === id) ?? palette.entries[0];
}

/** Pairs still violating the palette's own distance constraints, worst first. */
export function paletteViolations(palette) {
  return residualViolations(palette.entries, palette.params);
}
