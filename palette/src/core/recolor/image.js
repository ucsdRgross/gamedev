// The image contract every recolour function speaks (PLAN §19, task 5.1).
//
// **Core takes pixels, not files.** Nothing in `src/core/recolor/` knows about PNG, JPEG,
// GIF or the DOM — decoding happens at the edges (ARCHITECTURE §12.1), so `node --test`
// exercises the real algorithm rather than a mock of it.
//
// The buffer *is* a `Raster` (`{ w, h, data }`, RGB8, row-major). ARCHITECTURE §12.1
// described it as `{ width, height, data }`; using the existing Raster instead is a
// deliberate deviation, because `dither.js` — which task 5.4 is required to reuse — already
// takes a Raster, as do the scenes, the PNG exporters and `tools/render.mjs`. A second
// image type differing only in two property names would need an adapter at every boundary
// and buy nothing.

import { rgb8ToHex } from '../oklch.js';
import { Raster } from '../raster.js';

/** Turn a 24-bit colour key — the identity a source colour is tracked by — back into `[r, g, b]`. */
function keyToRgb(key) {
  return [(key >> 16) & 255, (key >> 8) & 255, key & 255];
}

/**
 * Every distinct colour in an image, most frequent first, with its pixel count.
 * Returns `{ colors: [{ key, rgb, hex, count }], index: Map<key, position> }` — the
 * frequency order is what `merge` overflow and the `auto` mode decision both run on.
 */
export function uniqueColors(image) {
  return uniqueColorsAcross([image]);
}

/**
 * The same, tallied over several images at once — the colours of a whole animation.
 *
 * Counting in place rather than concatenating the frames first is not a micro-optimisation:
 * a 189-frame 512×512 GIF is 49 million pixels, and materialising that as one buffer costs
 * 147 MB for no reason.
 */
export function uniqueColorsAcross(images) {
  const counts = new Map();
  for (const image of images) {
    for (let i = 0; i < image.data.length; i += 3) {
      const key = (image.data[i] << 16) | (image.data[i + 1] << 8) | image.data[i + 2];
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }
  const colors = [...counts.entries()]
    // Ties break on the colour key, so the order is a property of the image alone.
    .sort((a, b) => b[1] - a[1] || a[0] - b[0])
    .map(([key, count]) => ({ key, rgb: keyToRgb(key), hex: rgb8ToHex(keyToRgb(key)), count }));
  const index = new Map(colors.map((c, i) => [c.key, i]));
  return { colors, index };
}

/** How many distinct colours an image holds — the number `recolor_mode: auto` decides on. */
export function countUniqueColors(image) {
  const seen = new Set();
  for (let i = 0; i < image.data.length; i += 3) {
    seen.add((image.data[i] << 16) | (image.data[i + 1] << 8) | image.data[i + 2]);
  }
  return seen.size;
}

/** A copy of an image with every pixel replaced by `lookup(key)`, an `[r, g, b]`. */
export function mapColors(image, lookup) {
  const out = new Raster(image.w, image.h, null);
  const cache = new Map();
  for (let i = 0; i < image.data.length; i += 3) {
    const key = (image.data[i] << 16) | (image.data[i + 1] << 8) | image.data[i + 2];
    let rgb = cache.get(key);
    if (!rgb) {
      rgb = lookup(key);
      cache.set(key, rgb);
    }
    out.data[i] = rgb[0];
    out.data[i + 1] = rgb[1];
    out.data[i + 2] = rgb[2];
  }
  return out;
}

/**
 * Box-filter downscale to at most `maxW` wide, preserving aspect. Averaging rather than
 * point-sampling because a photograph destined for a small palette wants its detail
 * *merged*, not thrown away — point sampling keeps one arbitrary pixel per cell and makes
 * dithering fight noise that the average would have removed.
 */
export function downscale(image, maxW) {
  if (!maxW || image.w <= maxW) return image;
  const w = Math.max(1, Math.round(maxW));
  const h = Math.max(1, Math.round((image.h * w) / image.w));
  const out = new Raster(w, h, null);
  for (let y = 0; y < h; y++) {
    const y0 = Math.floor((y * image.h) / h);
    const y1 = Math.max(y0 + 1, Math.floor(((y + 1) * image.h) / h));
    for (let x = 0; x < w; x++) {
      const x0 = Math.floor((x * image.w) / w);
      const x1 = Math.max(x0 + 1, Math.floor(((x + 1) * image.w) / w));
      let r = 0;
      let g = 0;
      let b = 0;
      let n = 0;
      for (let sy = y0; sy < y1; sy++) {
        for (let sx = x0; sx < x1; sx++) {
          const p = (sy * image.w + sx) * 3;
          r += image.data[p];
          g += image.data[p + 1];
          b += image.data[p + 2];
          n++;
        }
      }
      const p = (y * w + x) * 3;
      out.data[p] = Math.round(r / n);
      out.data[p + 1] = Math.round(g / n);
      out.data[p + 2] = Math.round(b / n);
    }
  }
  return out;
}
