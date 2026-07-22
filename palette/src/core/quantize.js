// Per-channel bit-depth reduction for retro hardware targets (PLAN §2.6).
// 5/5/5 is roughly SNES, 3/3/3 Genesis, 2/2/2 EGA-ish; asymmetric setups like 4/2/3
// are expressible because each channel has its own depth.

import { srgbToOklab, srgbToLinear, linearRgbToOklab, deltaEOK, clamp } from './oklch.js';

/** Number of distinct values a channel of the given bit depth can hold. */
export function channelLevels(bits) {
  return 1 << clamp(Math.round(bits), 1, 8);
}

/** Every legal 8-bit code value for a channel of the given bit depth, ascending. */
export function legalValues(bits) {
  const levels = channelLevels(bits);
  const out = new Array(levels);
  for (let k = 0; k < levels; k++) out[k] = Math.round((k / (levels - 1)) * 255);
  return out;
}

/** Snap one sRGB channel (0..1) to its bit-depth grid using round or floor. */
export function quantizeChannel(v, bits, mode = 'round') {
  const levels = channelLevels(bits);
  const scaled = clamp(v, 0, 1) * (levels - 1);
  const k = mode === 'floor' ? Math.floor(scaled) : Math.round(scaled);
  return clamp(k, 0, levels - 1) / (levels - 1);
}

/** The two grid neighbours bracketing a channel value, as grid indices. */
function bracket(v, levels) {
  const scaled = clamp(v, 0, 1) * (levels - 1);
  const lo = clamp(Math.floor(scaled), 0, levels - 1);
  const hi = clamp(Math.ceil(scaled), 0, levels - 1);
  return lo === hi ? [lo] : [lo, hi];
}

/**
 * Snap an sRGB colour to the per-channel bit-depth grid.
 * `error-weighted` evaluates the eight bracketing grid points and keeps the one with
 * the lowest deltaEOK to the ideal colour — clearly better than rounding at low depths.
 */
export function quantizeSrgb(rgb, bitsR, bitsG, bitsB, mode = 'round') {
  const lr = channelLevels(bitsR);
  const lg = channelLevels(bitsG);
  const lb = channelLevels(bitsB);
  if (mode !== 'error-weighted') {
    return [
      quantizeChannel(rgb[0], bitsR, mode),
      quantizeChannel(rgb[1], bitsG, mode),
      quantizeChannel(rgb[2], bitsB, mode),
    ];
  }
  const ideal = srgbToOklab(rgb);
  // Linearise the (at most six) candidate channel values once rather than per
  // combination: this is the inner loop of every colour the generator emits.
  const cr = bracket(rgb[0], lr).map((k) => [k / (lr - 1), srgbToLinear(k / (lr - 1))]);
  const cg = bracket(rgb[1], lg).map((k) => [k / (lg - 1), srgbToLinear(k / (lg - 1))]);
  const cb = bracket(rgb[2], lb).map((k) => [k / (lb - 1), srgbToLinear(k / (lb - 1))]);
  let best = null;
  let bestErr = Infinity;
  for (const r of cr) {
    for (const g of cg) {
      for (const b of cb) {
        const err = deltaEOK(linearRgbToOklab(r[1], g[1], b[1]), ideal);
        if (err < bestErr) {
          bestErr = err;
          best = [r[0], g[0], b[0]];
        }
      }
    }
  }
  return best;
}

/** Quantise and return the final 8-bit code values. */
export function quantizeToRgb8(rgb, bitsR, bitsG, bitsB, mode = 'round') {
  const q = quantizeSrgb(rgb, bitsR, bitsG, bitsB, mode);
  return [Math.round(q[0] * 255), Math.round(q[1] * 255), Math.round(q[2] * 255)];
}

/** True when every channel of an 8-bit colour sits on its bit-depth grid. */
export function isOnGrid(rgb8, bitsR, bitsG, bitsB) {
  const sets = [legalValues(bitsR), legalValues(bitsG), legalValues(bitsB)];
  return rgb8.every((v, i) => sets[i].includes(v));
}

/** Total number of distinct colours expressible at the given per-channel depths. */
export function gridSize(bitsR, bitsG, bitsB) {
  return channelLevels(bitsR) * channelLevels(bitsG) * channelLevels(bitsB);
}
