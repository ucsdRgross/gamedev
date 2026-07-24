// Dithering (PLAN §8 scenes 27–29, §8 scene 33). Floyd–Steinberg error diffusion and
// Bayer 4×4 / 8×8 ordered dithering, both mapping an arbitrary source Raster onto a fixed
// palette. Pure and DOM-free. Nearest-colour matching is perceptual (ΔE_OK), so the
// chosen colour is the one that actually looks closest, not the closest in RGB.

import { rgb8ToOklab, deltaEOK, clamp } from './oklch.js';
import { Raster } from './raster.js';
import { bayerOrder } from './patterns.js';

/** A flat rank array from `patterns.js` as the square matrix this module's callers expect. */
function bayerMatrix(n) {
  const flat = bayerOrder(n);
  return Array.from({ length: n }, (_, y) => Array.from({ length: n }, (_, x) => flat[y * n + x]));
}

/**
 * 4×4 and 8×8 Bayer threshold matrices, values 0–15 and 0–63.
 *
 * Derived from `patterns.js` rather than written out, so the reference view's patterns and the
 * dithering the scenes and the recolour path actually use can never drift apart. The literal
 * published matrices are asserted against these in `test/patterns.test.js`.
 */
export const BAYER4 = bayerMatrix(4);
export const BAYER8 = bayerMatrix(8);

/** Precompute OKLab for every palette colour so matching is one loop of ΔE. */
export function paletteLabs(paletteRgb) {
  return paletteRgb.map((c) => rgb8ToOklab(c));
}

/**
 * Index of the perceptually nearest palette colour to an `[r,g,b]`.
 *
 * `lightnessWeight` scales the L term of the distance, which is `quant_lightness_weight`
 * (PLAN §19.1): above 1 the match protects the value structure and lets hue drift, below 1
 * it does the opposite. At 1 — the default, and what every scene uses — this is exactly
 * ΔE_OK, so raising the knob is the only way to change existing behaviour.
 */
export function nearestIndex(rgb8, labs, lightnessWeight = 1) {
  const lab = rgb8ToOklab([clamp(rgb8[0], 0, 255), clamp(rgb8[1], 0, 255), clamp(rgb8[2], 0, 255)]);
  let best = 0;
  let bestD = Infinity;
  for (let i = 0; i < labs.length; i++) {
    const d = lightnessWeight === 1 ? deltaEOK(lab, labs[i]) : weightedDelta(lab, labs[i], lightnessWeight);
    if (d < bestD) { bestD = d; best = i; }
  }
  return best;
}

/** ΔE_OK with the lightness axis scaled — the metric `quant_lightness_weight` selects. */
function weightedDelta(a, b, w) {
  const dL = (a[0] - b[0]) * w;
  const da = a[1] - b[1];
  const db = a[2] - b[2];
  return 100 * Math.sqrt(dL * dL + da * da + db * db);
}

/** Map every pixel to its nearest palette colour with no dithering (a baseline). */
export function quantizeRaster(source, paletteRgb, { lightnessWeight = 1 } = {}) {
  const labs = paletteLabs(paletteRgb);
  const out = new Raster(source.w, source.h, null);
  for (let i = 0; i < source.data.length; i += 3) {
    const idx = nearestIndex([source.data[i], source.data[i + 1], source.data[i + 2]], labs, lightnessWeight);
    const c = paletteRgb[idx];
    out.data[i] = c[0]; out.data[i + 1] = c[1]; out.data[i + 2] = c[2];
  }
  return out;
}

/**
 * Floyd–Steinberg error diffusion onto a palette. Error is diffused in sRGB space (the
 * classic behaviour) while the colour choice is perceptual, which keeps gradients smooth
 * without the hue drift naive RGB matching causes.
 */
export function floydSteinberg(source, paletteRgb, { lightnessWeight = 1, strength = 1 } = {}) {
  const { w, h } = source;
  const labs = paletteLabs(paletteRgb);
  // Working buffer of floats so diffused error can push a pixel across a palette boundary.
  const buf = Float32Array.from(source.data);
  const out = new Raster(w, h, null);
  const add = (x, y, ch, err, k) => {
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    buf[(y * w + x) * 3 + ch] += err * k;
  };
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 3;
      const cur = [buf[i], buf[i + 1], buf[i + 2]];
      const idx = nearestIndex(cur, labs, lightnessWeight);
      const chosen = paletteRgb[idx];
      out.data[i] = chosen[0]; out.data[i + 1] = chosen[1]; out.data[i + 2] = chosen[2];
      for (let ch = 0; ch < 3; ch++) {
        // `strength` scales how much error is passed on: 0 is plain nearest-colour, 1 the
        // textbook filter. Anything above 1 amplifies error and is not offered.
        const err = (cur[ch] - chosen[ch]) * strength;
        add(x + 1, y, ch, err, 7 / 16);
        add(x - 1, y + 1, ch, err, 3 / 16);
        add(x, y + 1, ch, err, 5 / 16);
        add(x + 1, y + 1, ch, err, 1 / 16);
      }
    }
  }
  return out;
}

/**
 * Bayer ordered dithering onto a palette. Each pixel is nudged by its threshold-matrix
 * offset before matching, so flat regions between two palette levels resolve into a
 * stable checkerboard rather than a hard band. `strength` is the nudge amplitude in sRGB.
 */
export function orderedDither(source, paletteRgb, { size = 4, strength = 48, lightnessWeight = 1 } = {}) {
  const { w, h } = source;
  const matrix = size === 8 ? BAYER8 : BAYER4;
  const n = matrix.length;
  const denom = n * n;
  const labs = paletteLabs(paletteRgb);
  const out = new Raster(w, h, null);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 3;
      const offset = (matrix[y % n][x % n] / denom - 0.5) * strength;
      const nudged = [source.data[i] + offset, source.data[i + 1] + offset, source.data[i + 2] + offset];
      const c = paletteRgb[nearestIndex(nudged, labs, lightnessWeight)];
      out.data[i] = c[0]; out.data[i + 1] = c[1]; out.data[i + 2] = c[2];
    }
  }
  return out;
}
