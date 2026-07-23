// Extract a palette from an image (the "recolour into an external palette" feature).
//
// The mode chosen for this is **every distinct colour** — so the same code reads a clean
// lospec strip *and* grabs a palette out of a finished art piece. There are two paths,
// because those two inputs are not the same kind of thing:
//
//  - **A designed strip** (`≤ 2px` tall — the lospec/1px shape) is *authoritative*: every
//    pixel is a colour someone chose, there are no transition pixels, and the white blocks
//    on the ends are deliberate. So every distinct colour is taken, in left-to-right order,
//    with no merging and no thresholding. Nothing is second-guessed.
//
//  - **Anything taller** (a rendered swatch sheet, or a whole art piece) has anti-aliasing,
//    and that is what would otherwise ruin the result. Two passes remove it:
//     1. **Merge near-duplicates** within a tight ΔE — folds in compression noise and the
//        one-step wobble around a flat colour, without touching two swatches that are close
//        but deliberately distinct (those sit well above the threshold).
//     2. **Drop anything below a coverage floor** — the transition pixels along an edge are a
//        blend of two neighbours, far from both (so pass 1 leaves them), but *thin*, so they
//        never clear the floor. This is what actually removes the aliasing.
//    Whatever survives is ranked by coverage and capped, so an art piece reduces to its
//    dominant colours rather than its accidental thousands.
//
// DOM-free: it takes a `Raster` (`src/core/` may not touch the DOM), so `node --test`
// exercises the real extraction and the browser decodes at the edge.

import { deltaEOK, rgb8ToHex, rgb8ToOklab } from '../oklch.js';
import { uniqueColors } from './image.js';

// At or below this height an image is a designed strip: every distinct colour is a real
// entry and there is no aliasing to clean up. A 1px lospec strip is the canonical case.
const DESIGNED_STRIP_MAX_H = 2;
// Tight on purpose: OKLab 0.015 catches noise and AA-adjacent wobble but not two distinct
// swatches. Aliasing proper is handled by coverage, not by merging.
const MERGE_DELTA_E = 1.5;
// A real swatch in a rendered sheet covers far more than this; an AA edge never does.
const MIN_COVERAGE = 0.0025;
const MAX_COLORS = 64;
// A GIF colour table holds at most 256, so a recoloured animation cannot exceed it. Designed
// strips are capped here rather than at MAX_COLORS — a 200-swatch strip is all real entries.
const HARD_MAX_COLORS = 256;

/**
 * Extract a palette from one image. Returns
 * `{ colors: [{ rgb8, hex, lab, count, coverage }], distinct, kept, designed }`, ranked
 * most-covered first (or left-to-right for a designed strip) — `distinct` is how many colours
 * the source held, `kept` how many survived.
 */
export function extractPalette(image, {
  mergeDeltaE = MERGE_DELTA_E, minCoverage = MIN_COVERAGE, maxColors = MAX_COLORS,
} = {}) {
  const total = image.w * image.h;
  if (!total) return { colors: [], distinct: 0, kept: 0, designed: false };

  if (image.h <= DESIGNED_STRIP_MAX_H) return designedStrip(image);

  const { colors } = uniqueColors(image); // most frequent first

  // Nearest-anchor merge. Because the source is processed most-frequent-first, every cluster
  // is anchored at the dominant exact colour of a region — a swatch, not a blend — and the
  // rarer variants around it fold in. The anchor's own rgb8 is kept, never an average, so the
  // extracted colour is a colour that is genuinely in the image.
  const clusters = [];
  for (const c of colors) {
    const lab = rgb8ToOklab(c.rgb);
    let best = -1;
    let bestD = Infinity;
    for (let i = 0; i < clusters.length; i++) {
      const d = deltaEOK(lab, clusters[i].lab);
      if (d < bestD) { bestD = d; best = i; }
    }
    if (best >= 0 && bestD <= mergeDeltaE) clusters[best].count += c.count;
    else clusters.push({ lab, rgb8: c.rgb, count: c.count });
  }

  let kept = clusters.filter((cl) => cl.count / total >= minCoverage);
  // A flat single-colour image (or one so noisy nothing clears the floor) still has to yield
  // something, or the caller has no palette at all.
  if (!kept.length) kept = clusters.slice(0, 1);
  kept.sort((a, b) => b.count - a.count);
  if (kept.length > maxColors) kept = kept.slice(0, maxColors);

  return { ...pack(kept, total), distinct: colors.length, designed: false };
}

/**
 * Every distinct colour of a designed strip, in first-appearance (left-to-right) order.
 * No merging and no coverage floor: a strip is a list of chosen colours, not a picture with
 * regions to clean up, and the white end-blocks are as intentional as any other entry.
 */
function designedStrip(image) {
  const seen = new Map(); // key -> { rgb8, count }
  const order = [];
  for (let i = 0; i < image.data.length; i += 3) {
    const rgb = [image.data[i], image.data[i + 1], image.data[i + 2]];
    const key = (rgb[0] << 16) | (rgb[1] << 8) | rgb[2];
    let e = seen.get(key);
    if (!e) { e = { rgb8: rgb, count: 0 }; seen.set(key, e); order.push(e); }
    e.count++;
  }
  const kept = order.slice(0, HARD_MAX_COLORS);
  return { ...pack(kept, image.w * image.h), distinct: order.length, designed: true };
}

/** Turn kept clusters into the returned colour list. */
function pack(kept, total) {
  return {
    colors: kept.map((cl) => ({
      rgb8: cl.rgb8,
      hex: rgb8ToHex(cl.rgb8),
      lab: rgb8ToOklab(cl.rgb8),
      count: cl.count,
      coverage: cl.count / total,
    })),
    kept: kept.length,
  };
}

/**
 * Wrap extracted colours as a minimal palette the recolour pipeline accepts. It uses only
 * `entries[].rgb8 / lab / hex`, so an external palette needs nothing the generated one has
 * beyond those — no params, no seed, no roles.
 */
export function externalPalette(name, extraction) {
  return {
    name,
    external: true,
    entries: extraction.colors.map((c) => ({ rgb8: c.rgb8, lab: c.lab, hex: c.hex })),
  };
}
