// The recolour front door (PLAN §19.1): pick a mode, run it, report what it did.
//
// `auto` exists because the two paths are not interchangeable and the right one is decided
// by the *source*, not by taste (ARCHITECTURE §12.2). Pixel art has a palette worth
// preserving and outlines that per-pixel matching shreds; a photograph has neither and wants
// dithering instead. The unique-colour count separates them cleanly, so `auto` counts.

import { Raster } from '../raster.js';
import { countUniqueColors, uniqueColorsAcross } from './image.js';
import { buildIndexedMapping, recolorIndexed } from './indexed.js';
import { recolorQuantize } from './quantize.js';

/** How a source image is recoloured. */
export const RECOLOR_MODES = ['auto', 'indexed', 'quantize'];

/**
 * Which mode `auto` would choose, and why. Split out so the decision can be shown in the
 * gallery next to each image rather than being an invisible branch.
 */
export function chooseMode(image, options = {}) {
  return decideMode(countUniqueColors(image), options);
}

/** The same decision from a colour count already in hand, so it is never counted twice. */
function decideMode(unique, { mode = 'auto', indexedMax = 256 } = {}) {
  if (mode !== 'auto') return { mode, unique, reason: 'set explicitly' };
  return unique <= indexedMax
    ? { mode: 'indexed', unique, reason: `${unique} colours ≤ ${indexedMax}` }
    : { mode: 'quantize', unique, reason: `${unique} colours > ${indexedMax}` };
}

/**
 * Recolour one image into a palette. Returns
 * `{ image, mode, unique, reason }` plus whatever the chosen path reports.
 */
export function recolorImage(image, palette, {
  mode = 'auto', indexedMax = 256,
  match = 'delta-e', preserveOrder = false, overflow = 'share',
  dither = 'floyd-steinberg', ditherStrength = 1, lightnessWeight = 1, downscaleTo = 0,
} = {}) {
  const chosen = chooseMode(image, { mode, indexedMax });
  const result = chosen.mode === 'indexed'
    ? recolorIndexed(image, palette.entries, { match, preserveOrder, overflow })
    : recolorQuantize(image, palette.entries, {
      dither, strength: ditherStrength, lightnessWeight, downscaleTo,
    });
  return { ...result, ...chosen };
}

/**
 * Recolour every frame of an animation with **one** decision shared across all of them.
 *
 * This is the whole reason it is not a `map` over `recolorImage`: deciding per frame lets a
 * colour that shifts rank between frames land on a different target in each, which reads as
 * the palette flickering. The mapping is built from the frames' *combined* colours and then
 * applied to each — so a source colour is the same target colour in every frame, which is
 * the animated form of the property the indexed path exists to guarantee.
 */
export function recolorFrames(frames, palette, options = {}) {
  if (!frames.length) return { frames: [], mode: 'indexed', unique: 0, reason: 'no frames' };
  // Tallied across the frames in place — never concatenated. A long animation is tens of
  // millions of pixels and joining them into one buffer first costs hundreds of megabytes.
  const { colors } = uniqueColorsAcross(frames.map((f) => f.image));
  const chosen = decideMode(colors.length, options);

  if (chosen.mode === 'indexed') {
    const { match = 'delta-e', preserveOrder = false, overflow = 'share' } = options;
    const lookup = buildIndexedMapping(colors, palette.entries, { match, preserveOrder, overflow });
    const rgbs = palette.entries.map((e) => e.rgb8);
    return {
      ...chosen,
      frames: frames.map((f) => ({ ...f, image: applyMapping(f.image, lookup, rgbs) })),
    };
  }
  return {
    ...chosen,
    frames: frames.map((f) => ({ ...f, image: recolorImage(f.image, palette, { ...options, mode: 'quantize' }).image })),
  };
}

/** Apply a prebuilt source-colour → target-index mapping to one frame. */
function applyMapping(image, mapping, rgbs) {
  const out = new Raster(image.w, image.h, null);
  for (let i = 0; i < image.data.length; i += 3) {
    const key = (image.data[i] << 16) | (image.data[i + 1] << 8) | image.data[i + 2];
    const rgb = rgbs[mapping.get(key)];
    out.data[i] = rgb[0];
    out.data[i + 1] = rgb[1];
    out.data[i + 2] = rgb[2];
  }
  return out;
}
