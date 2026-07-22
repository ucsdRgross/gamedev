// Per-pixel quantization (PLAN §19.1) — the recolour path for photographs.
//
// The mirror image of `indexed.js`: here each pixel *should* be decided on its own, because
// a photograph has no palette to preserve and no outlines to break. What it has instead is
// gradients, which is why dithering matters — a smooth sky mapped to a 32-colour palette
// bands horribly without it.
//
// All the pixel work is `src/core/dither.js`, which the gallery scenes already use. This
// module only turns the §19.1 parameters into the calls that module wants.

import { floydSteinberg, orderedDither, quantizeRaster } from '../dither.js';
import { downscale } from './image.js';

/** Dithering modes offered by `quant_dither`. */
export const QUANT_DITHER = ['none', 'floyd-steinberg', 'bayer4', 'bayer8'];

// Bayer nudges in sRGB units, so its strength needs a scale; Floyd–Steinberg's is a
// fraction of the error it propagates. One knob, 0..1, drives both through these.
const BAYER_MAX_NUDGE = 64;

/**
 * Recolour an image by matching every pixel to the nearest palette colour.
 * Returns `{ image, dither, downscaled }`.
 */
export function recolorQuantize(image, entries, {
  dither = 'floyd-steinberg', strength = 1, lightnessWeight = 1, downscaleTo = 0,
} = {}) {
  if (!entries.length) throw new Error('recolorQuantize: the target palette is empty');
  const src = downscaleTo ? downscale(image, downscaleTo) : image;
  const rgbs = entries.map((e) => e.rgb8);
  const clamped = Math.min(1, Math.max(0, strength));

  let out;
  if (dither === 'floyd-steinberg') {
    out = floydSteinberg(src, rgbs, { lightnessWeight, strength: clamped });
  } else if (dither === 'bayer4' || dither === 'bayer8') {
    out = orderedDither(src, rgbs, {
      size: dither === 'bayer8' ? 8 : 4,
      strength: clamped * BAYER_MAX_NUDGE,
      lightnessWeight,
    });
  } else {
    out = quantizeRaster(src, rgbs, { lightnessWeight });
  }
  return { image: out, dither, downscaled: src !== image };
}
