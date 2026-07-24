// The recolour front door (PLAN §19.1): pick a mode, run it, report what it did.
//
// `auto` exists because the two paths are not interchangeable and the right one is decided
// by the *source*, not by taste (ARCHITECTURE §12.2). Pixel art has a palette worth
// preserving and outlines that per-pixel matching shreds; a photograph has neither and wants
// dithering instead. The unique-colour count separates them cleanly, so `auto` counts.

import { Raster } from '../raster.js';
import { sourceContexts, targetPools } from './context.js';
import { countUniqueColors, uniqueColorsAcross } from './image.js';
import { buildIndexedMapping, recolorIndexed } from './indexed.js';
import { recolorQuantize } from './quantize.js';

/** How a source image is recoloured. */
export const RECOLOR_MODES = ['auto', 'indexed', 'quantize'];

/** Whether the indexed remap knows what each colour is for, and where it gets that from. */
export const RECOLOR_CONTEXT_MODES = ['off', 'suggest', 'manual'];

/**
 * Work out the context inputs for one recolour, or `null` if it is not context-aware.
 *
 * Returns null — meaning "run exactly as before" — whenever the feature is off, the bias is
 * zero, or the **target has no layers** (a palette extracted from an image is just colours,
 * ARCHITECTURE §12.6, so there is no structure to map onto).
 *
 * `images` is every frame, not one: the contexts have to be decided across the whole
 * animation for the same reason the mapping is, or a colour changes job between frames.
 */
function contextInputs(images, palette, {
  recolorContext = 'off', contextBias = 1, contextOverrides = null, preserveOrder = false,
  contextOrder = true,
} = {}) {
  if (recolorContext === 'off' || contextBias <= 0) return null;
  // `remap_context_order` off means preserve_order wins outright and context stands down.
  if (preserveOrder && !contextOrder) return null;
  const pools = targetPools(palette.entries);
  if (!pools) return null;
  const overrides = recolorContext === 'manual' ? contextOverrides : null;
  return { pools, contexts: sourceContexts(images, overrides), contextBias };
}

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
export function recolorImage(image, palette, options = {}) {
  const {
    mode = 'auto', indexedMax = 256,
    match = 'delta-e', preserveOrder = false, overflow = 'share',
    dither = 'floyd-steinberg', ditherStrength = 1, lightnessWeight = 1, downscaleTo = 0,
  } = options;
  const chosen = chooseMode(image, { mode, indexedMax });
  if (chosen.mode !== 'indexed') {
    return {
      ...recolorQuantize(image, palette.entries, {
        dither, strength: ditherStrength, lightnessWeight, downscaleTo,
      }),
      ...chosen,
    };
  }
  // Context is an indexed-path feature only. The photo path decides every pixel on its own,
  // so there is no per-colour decision for a context to steer (ARCHITECTURE §12.2).
  const ctx = contextInputs([image], palette, options);
  return {
    ...recolorIndexed(image, palette.entries, {
      match, preserveOrder, overflow, ...(ctx ?? {}),
    }),
    ...chosen,
    context: ctx ? { applied: true, bias: ctx.contextBias } : { applied: false },
  };
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
    // Decided once over every frame, exactly like the mapping itself — a colour that changes
    // context between frames would change target between frames.
    const ctx = contextInputs(frames.map((f) => f.image), palette, options);
    const lookup = buildIndexedMapping(colors, palette.entries, {
      match, preserveOrder, overflow, ...(ctx ?? {}),
    });
    const rgbs = palette.entries.map((e) => e.rgb8);
    return {
      ...chosen,
      context: ctx ? { applied: true, bias: ctx.contextBias } : { applied: false },
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
