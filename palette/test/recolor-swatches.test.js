// Extracting a palette from an image (the external-palette feature).
//
// The one property that matters and is easy to get wrong is anti-aliasing removal: a swatch
// strip drawn with blended edges must extract to the swatch colours and *not* the blend
// colours between them. That is asserted directly, on a strip built with real AA seams.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { extractPalette, externalPalette } from '../src/core/recolor/swatches.js';
import { recolorImage } from '../src/core/recolor/index.js';
import { Raster } from '../src/core/raster.js';
import { rgb8ToHex } from '../src/core/oklch.js';

/** A horizontal strip of `cols` flat swatches, each `sw` wide and `h` tall. */
function strip(cols, { sw = 12, h = 20 } = {}) {
  const img = new Raster(cols.length * sw, h, null);
  cols.forEach((c, i) => img.rect(i * sw, 0, sw, h, c));
  return img;
}

/** The same, but with a one-pixel anti-aliased seam (the average of the two) between swatches. */
function stripWithAA(cols, { sw = 12, h = 20 } = {}) {
  const img = strip(cols, { sw, h });
  for (let i = 1; i < cols.length; i++) {
    const a = cols[i - 1];
    const b = cols[i];
    const mid = [0, 1, 2].map((k) => Math.round((a[k] + b[k]) / 2));
    for (let y = 0; y < h; y++) img.set(i * sw, y, mid);
  }
  return img;
}

const SWATCHES = [
  [255, 255, 240], [255, 120, 110], [220, 0, 0], [140, 0, 0], [230, 170, 30],
  [190, 100, 0], [110, 60, 0], [150, 200, 100], [70, 150, 40], [40, 100, 20],
  [40, 190, 240], [20, 130, 230], [0, 90, 150], [250, 150, 210], [200, 40, 180],
  [130, 20, 110], [190, 190, 190], [120, 120, 120], [30, 30, 30],
];

/** Every distinct hex in an image. */
function hexes(image) {
  const out = new Set();
  for (let i = 0; i < image.data.length; i += 3) {
    out.add(rgb8ToHex([image.data[i], image.data[i + 1], image.data[i + 2]]));
  }
  return out;
}

test('a clean swatch strip extracts to exactly its swatches', () => {
  const got = extractPalette(strip(SWATCHES));
  assert.equal(got.kept, SWATCHES.length);
  assert.deepEqual(
    new Set(got.colors.map((c) => c.hex)),
    hexes(strip(SWATCHES)),
  );
});

test('anti-aliased seams are dropped, not extracted as their own colours', () => {
  // Realistic proportions: wide swatches, 1px seams — so a seam is a tiny fraction of the
  // image, which is exactly what the coverage floor keys on. (A pathologically narrow-swatch
  // strip can leak seams; the 1px designed-strip path is the clean input, tested above.)
  const img = stripWithAA(SWATCHES, { sw: 48, h: 40 });
  const drawn = hexes(img);
  // The AA really is in the image — otherwise the test proves nothing.
  assert.ok(drawn.size > SWATCHES.length, 'the fixture should contain seam colours');

  const got = extractPalette(img);
  const swatchHexes = new Set(SWATCHES.map((c) => rgb8ToHex(c)));
  assert.equal(got.kept, SWATCHES.length, `expected ${SWATCHES.length} swatches, got ${got.kept}`);
  for (const c of got.colors) {
    assert.ok(swatchHexes.has(c.hex), `extracted a seam colour ${c.hex}`);
  }
});

test('a 1px-tall palette strip (the lospec shape) reads every entry, in order, no drops', () => {
  const img = new Raster(SWATCHES.length, 1, null);
  SWATCHES.forEach((c, i) => img.set(i, 0, c));
  const got = extractPalette(img);
  assert.equal(got.designed, true);
  assert.equal(got.kept, SWATCHES.length);
  // Left-to-right order is preserved, and nothing is merged even where two entries are close.
  assert.deepEqual(got.colors.map((c) => c.hex), SWATCHES.map((c) => rgb8ToHex(c)));
});

test('a designed strip keeps intentional near-duplicate and white entries', () => {
  // Two entries 1px apart in one channel (below the merge ΔE) and a white block: on a strip
  // these are all deliberate and must all survive, unlike in a rendered image.
  const cols = [[255, 255, 255], [40, 40, 40], [41, 40, 40], [255, 0, 0]];
  const img = new Raster(cols.length, 1, null);
  cols.forEach((c, i) => img.set(i, 0, c));
  const got = extractPalette(img);
  assert.equal(got.kept, 4, 'no merging on a designed strip');
  assert.deepEqual(got.colors.map((c) => c.hex), cols.map((c) => rgb8ToHex(c)));
});

test('near-duplicate compression noise merges into the swatch it surrounds', () => {
  // A big flat swatch with a few pixels of ±1 noise around its colour. The noise must fold
  // in, not survive as extra entries.
  const img = new Raster(40, 20, [60, 120, 200]);
  img.set(0, 0, [61, 121, 199]);
  img.set(1, 0, [59, 119, 201]);
  img.set(2, 0, [60, 121, 200]);
  const got = extractPalette(img);
  assert.equal(got.kept, 1);
  assert.deepEqual(got.colors[0].rgb8, [60, 120, 200], 'the anchor is the dominant exact colour');
});

test('grabbing a palette from a many-colour image caps at maxColors, most-covered first', () => {
  // A smooth gradient: hundreds of distinct colours, no flat swatches.
  const img = new Raster(128, 64, null);
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 128; x++) img.set(x, y, [x * 2, y * 4, 128]);
  }
  const got = extractPalette(img, { maxColors: 16 });
  assert.ok(got.distinct > 100, `fixture should be rich, got ${got.distinct}`);
  assert.equal(got.kept, 16);
  // Ranked by coverage, descending.
  for (let i = 1; i < got.colors.length; i++) {
    assert.ok(got.colors[i].coverage <= got.colors[i - 1].coverage);
  }
});

test('extraction is deterministic', () => {
  const img = stripWithAA(SWATCHES);
  const a = extractPalette(img);
  const b = extractPalette(img);
  assert.deepEqual(a.colors.map((c) => c.hex), b.colors.map((c) => c.hex));
});

test('a single-colour image still yields one colour', () => {
  const got = extractPalette(new Raster(10, 10, [12, 34, 56]));
  assert.equal(got.kept, 1);
  assert.deepEqual(got.colors[0].rgb8, [12, 34, 56]);
});

test('an extracted palette drives the recolour pipeline like any other', () => {
  const target = externalPalette('test-strip', extractPalette(strip(SWATCHES)));
  assert.ok(target.entries.length === SWATCHES.length);
  assert.ok(target.entries.every((e) => e.rgb8 && e.lab && e.hex));

  // A source image recolours into it, emitting only the external palette's colours.
  const source = new Raster(24, 16, null);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 24; x++) source.set(x, y, [x * 10, y * 15, 90]);
  const out = recolorImage(source, target, { mode: 'quantize' }).image;
  const allowed = new Set(target.entries.map((e) => e.hex));
  for (const hex of hexes(out)) assert.ok(allowed.has(hex), `foreign colour ${hex}`);
});
