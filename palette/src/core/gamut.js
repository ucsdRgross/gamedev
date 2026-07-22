// CSS Color 4 style gamut mapping: hold L and h, binary-search C downward (PLAN §2.4).
//
// Independent per-channel clamping is NOT gamut mapping — it moves hue and lightness
// unpredictably and invalidates every ramp invariant the generator relies on. The
// `clip` mode below exists only so the artifact can be demonstrated in the UI.

import {
  oklchToSrgb, oklchToOklab, oklabToLinearRgb, srgbToOklab, deltaEOK, clamp,
} from './oklch.js';

/**
 * Tolerance for accepting an early clipped result, in deltaEOK (x100) units.
 * CSS Color 4 suggests 2.0 (one JND); we run an order of magnitude tighter because
 * the generator's hue-shift invariants are asserted in degrees, and at low chroma a
 * fixed deltaE budget buys a large angular error.
 */
const JND = 0.1;

const EPS = 1e-6;

/** Largest lightness shift `reduce-l-adjust` may spend to recover chroma. */
const MAX_L_ADJUST = 0.02;

/**
 * True when OKLCH(L, C, h) is displayable in sRGB.
 * Tested against the linear-light values: the transfer function is monotonic and maps
 * [0,1] onto [0,1], so this is equivalent to checking the encoded values and skips
 * three `Math.pow` calls — and this runs inside the mapper's binary search.
 */
export function inSrgb(L, C, h) {
  const lab = oklchToOklab(L, C, h);
  const lin = oklabToLinearRgb(lab[0], lab[1], lab[2]);
  return (
    lin[0] >= -EPS && lin[0] <= 1 + EPS &&
    lin[1] >= -EPS && lin[1] <= 1 + EPS &&
    lin[2] >= -EPS && lin[2] <= 1 + EPS
  );
}

/**
 * Clamp sRGB floats into [0,1].
 * Two uses only: the mapper's accept test, and scrubbing float noise off a result that
 * is already in gamut. It is never how a colour is BROUGHT into gamut.
 */
function clip(rgb) {
  return [clamp(rgb[0], 0, 1), clamp(rgb[1], 0, 1), clamp(rgb[2], 0, 1)];
}

/** Largest displayable chroma at a given lightness and hue, to 1e-4. */
export function maxChromaFor(L, h) {
  if (L <= 0 || L >= 1) return 0;
  if (inSrgb(L, 0.4, h)) return 0.4;
  let lo = 0;
  let hi = 0.4;
  while (hi - lo > 1e-4) {
    const mid = (lo + hi) / 2;
    if (inSrgb(L, mid, h)) lo = mid;
    else hi = mid;
  }
  return lo;
}

const cuspCache = new Map();

/** Lightness and chroma of the sRGB gamut cusp for a hue (memoised per whole degree). */
export function gamutCusp(h) {
  const key = Math.round(((h % 360) + 360) % 360);
  const hit = cuspCache.get(key);
  if (hit) return hit;
  let bestL = 0.5;
  let bestC = 0;
  for (let i = 1; i < 40; i++) {
    const L = i / 40;
    const C = maxChromaFor(L, key);
    if (C > bestC) {
      bestC = C;
      bestL = L;
    }
  }
  for (let i = -10; i <= 10; i++) {
    const L = clamp(bestL + i * 0.0025, 0.001, 0.999);
    const C = maxChromaFor(L, key);
    if (C > bestC) {
      bestC = C;
      bestL = L;
    }
  }
  const cusp = { L: bestL, C: bestC };
  cuspCache.set(key, cusp);
  return cusp;
}

/** Chroma-reduction gamut map: preserves L and h exactly, sacrifices only saturation. */
function chromaReduce(L, C, h) {
  if (L >= 1) return [1, 1, 1];
  if (L <= 0) return [0, 0, 0];
  if (inSrgb(L, C, h)) return clip(oklchToSrgb(L, C, h));

  let lo = 0;
  let hi = C;
  while (hi - lo > 1e-4) {
    const mid = (lo + hi) / 2;
    if (inSrgb(L, mid, h)) {
      lo = mid;
    } else {
      const clipped = clip(oklchToSrgb(L, mid, h));
      const ideal = oklchToOklab(L, mid, h);
      if (deltaEOK(srgbToOklab(clipped), ideal) < JND) return clipped;
      hi = mid;
    }
  }
  return clip(oklchToSrgb(L, lo, h));
}

/**
 * Map an OKLCH colour into displayable sRGB floats [0,1].
 * `mode` is one of `chroma-reduce` (default, correct), `clip` (naive, demo only),
 * or `reduce-l-adjust` (chroma-reduce that trades a little lightness back for chroma).
 */
export function gamutMap(L, C, h, mode = 'chroma-reduce') {
  const Lc = clamp(L, 0, 1);
  const Cc = Math.max(0, C);
  if (mode === 'clip') return clip(oklchToSrgb(Lc, Cc, h));
  if (mode === 'reduce-l-adjust') return reduceWithLightnessAdjust(Lc, Cc, h);
  return chromaReduce(Lc, Cc, h);
}

/** Chroma-reduce, but pull L toward the hue's cusp when reduction was severe. */
function reduceWithLightnessAdjust(L, C, h) {
  const direct = chromaReduce(L, C, h);
  const achieved = maxChromaFor(L, h);
  if (achieved >= C * 0.6 || C <= 0) return direct;
  const cusp = gamutCusp(h);
  // Trade a sliver of lightness for chroma, hard-capped: this mode is the only one that
  // does not preserve L exactly, and a larger budget lets it reorder a ramp whose steps
  // are separated mostly in chroma.
  const L2 = L + clamp((cusp.L - L) * 0.15, -MAX_L_ADJUST, MAX_L_ADJUST);
  return chromaReduce(L2, C, h);
}

/** Convenience: gamut-map and report the OKLCH actually achieved. */
export function gamutMapToOklch(L, C, h, mode = 'chroma-reduce') {
  const rgb = gamutMap(L, C, h, mode);
  const lab = srgbToOklab(rgb);
  const Cout = Math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
  let hout = Cout < 1e-9 ? h : (Math.atan2(lab[2], lab[1]) * 180) / Math.PI;
  if (hout < 0) hout += 360;
  return { rgb, L: lab[0], C: Cout, h: hout };
}
