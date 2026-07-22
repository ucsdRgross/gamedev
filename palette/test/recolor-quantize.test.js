// Per-pixel quantization and mode selection (PLAN §19.1, tasks 5.5 and 5.6).
//
// `quant_lightness_weight` is the one knob here that could plausibly do nothing and still
// look fine, so it is asserted as a *trade*: raising it must measurably improve value
// accuracy and measurably worsen hue accuracy. An assertion that it merely changes the
// output would pass on a knob wired to the wrong thing entirely.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { QUANT_DITHER, recolorQuantize } from '../src/core/recolor/quantize.js';
import { RECOLOR_MODES, chooseMode, recolorImage } from '../src/core/recolor/index.js';
import { countUniqueColors } from '../src/core/recolor/image.js';
import { Raster } from '../src/core/raster.js';
import { generatePalette } from '../src/core/generate.js';
import { oklabToOklch, rgb8ToHex, rgb8ToOklab } from '../src/core/oklch.js';

const palette = (k) => generatePalette({ color_count: k });

/** A synthetic photograph: a smooth two-axis gradient with a lot of distinct colours. */
function photo(w = 48, h = 32) {
  const img = new Raster(w, h, null);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const u = x / (w - 1);
      const v = y / (h - 1);
      img.set(x, y, [
        Math.round(30 + 200 * u),
        Math.round(60 + 150 * v),
        Math.round(200 - 120 * u * v),
      ]);
    }
  }
  return img;
}

/** A flat-coloured pixel-art sprite: few colours, hard edges. */
function sprite(w = 16, h = 16) {
  const cols = [[20, 18, 30], [200, 60, 70], [240, 220, 180], [60, 130, 90]];
  const img = new Raster(w, h, null);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) img.set(x, y, cols[(Math.floor(x / 4) + Math.floor(y / 4)) % cols.length]);
  }
  return img;
}

/** Every distinct hex in an image. */
function hexes(image) {
  const out = new Set();
  for (let i = 0; i < image.data.length; i += 3) {
    out.add(rgb8ToHex([image.data[i], image.data[i + 1], image.data[i + 2]]));
  }
  return out;
}

/** Mean lightness error and mean chroma-plane error between a source and its recolour. */
function errors(src, out) {
  let dL = 0;
  let dC = 0;
  let n = 0;
  for (let i = 0; i < src.data.length; i += 3) {
    const a = rgb8ToOklab([src.data[i], src.data[i + 1], src.data[i + 2]]);
    const b = rgb8ToOklab([out.data[i], out.data[i + 1], out.data[i + 2]]);
    dL += Math.abs(a[0] - b[0]);
    dC += Math.hypot(a[1] - b[1], a[2] - b[2]);
    n++;
  }
  return { L: dL / n, C: dC / n };
}

test('every dither mode emits only target-palette colours', () => {
  const p = palette(16);
  const allowed = new Set(p.entries.map((e) => e.hex));
  const src = photo();
  for (const dither of QUANT_DITHER) {
    const out = recolorQuantize(src, p.entries, { dither }).image;
    for (const hex of hexes(out)) assert.ok(allowed.has(hex), `${dither}: foreign colour ${hex}`);
    assert.equal(out.w, src.w);
    assert.equal(out.h, src.h);
  }
});

test('dithering is deterministic', () => {
  const p = palette(12);
  const src = photo();
  for (const dither of QUANT_DITHER) {
    const a = recolorQuantize(src, p.entries, { dither }).image;
    const b = recolorQuantize(src, p.entries, { dither }).image;
    assert.deepEqual([...a.data], [...b.data], `${dither} is not deterministic`);
  }
});

test('dithering breaks up bands that plain nearest matching leaves flat', () => {
  const p = palette(8);
  const src = photo(64, 8);
  const plain = recolorQuantize(src, p.entries, { dither: 'none' }).image;
  for (const dither of ['floyd-steinberg', 'bayer4', 'bayer8']) {
    const out = recolorQuantize(src, p.entries, { dither }).image;
    assert.ok(hexes(out).size >= hexes(plain).size, `${dither} used fewer colours than no dither`);
    assert.notDeepEqual([...out.data], [...plain.data], `${dither} changed nothing`);
  }
});

test('dither strength 0 collapses to plain nearest matching', () => {
  const p = palette(10);
  const src = photo();
  const plain = recolorQuantize(src, p.entries, { dither: 'none' }).image;
  for (const dither of ['floyd-steinberg', 'bayer4', 'bayer8']) {
    const off = recolorQuantize(src, p.entries, { dither, strength: 0 }).image;
    assert.deepEqual([...off.data], [...plain.data], `${dither} at strength 0 should be plain`);
  }
});

test('quant_lightness_weight trades hue accuracy for value accuracy', () => {
  const p = palette(12);
  const src = photo(64, 48);
  const neutral = errors(src, recolorQuantize(src, p.entries, { dither: 'none', lightnessWeight: 1 }).image);
  const valueLed = errors(src, recolorQuantize(src, p.entries, { dither: 'none', lightnessWeight: 6 }).image);

  assert.ok(valueLed.L < neutral.L, `value error should fall: ${valueLed.L} vs ${neutral.L}`);
  assert.ok(valueLed.C > neutral.C, `chroma error should rise: ${valueLed.C} vs ${neutral.C}`);
});

test('quant_downscale shrinks the source before matching', () => {
  const p = palette(16);
  const src = photo(64, 32);
  const out = recolorQuantize(src, p.entries, { dither: 'none', downscaleTo: 16 });
  assert.equal(out.image.w, 16);
  assert.equal(out.image.h, 8);
  assert.equal(out.downscaled, true);
  assert.equal(recolorQuantize(src, p.entries, { downscaleTo: 999 }).downscaled, false);
});

test('an empty target palette is refused', () => {
  assert.throws(() => recolorQuantize(photo(), [], {}), /target palette is empty/);
});

test('auto picks indexed for pixel art and quantize for a photograph', () => {
  const art = sprite();
  const pic = photo(64, 64);
  assert.ok(countUniqueColors(art) < 16, 'the sprite fixture should be flat');
  assert.ok(countUniqueColors(pic) > 256, `the photo fixture should be rich, got ${countUniqueColors(pic)}`);

  assert.equal(chooseMode(art).mode, 'indexed');
  assert.equal(chooseMode(pic).mode, 'quantize');
  // The threshold is the decision, and it is honoured in both directions.
  assert.equal(chooseMode(art, { indexedMax: 2 }).mode, 'quantize');
  assert.equal(chooseMode(pic, { indexedMax: 1e6 }).mode, 'indexed');
});

test('an explicit mode overrides the automatic choice', () => {
  const p = palette(16);
  const art = sprite();
  for (const mode of RECOLOR_MODES) {
    const out = recolorImage(art, p, { mode });
    assert.equal(out.mode, mode === 'auto' ? 'indexed' : mode);
    const allowed = new Set(p.entries.map((e) => e.hex));
    for (const hex of hexes(out.image)) assert.ok(allowed.has(hex));
  }
  assert.equal(recolorImage(art, p, { mode: 'quantize' }).reason, 'set explicitly');
});

test('recolorImage reports the colour count it decided on', () => {
  const p = palette(16);
  const art = sprite();
  const out = recolorImage(art, p, {});
  assert.equal(out.unique, countUniqueColors(art));
  assert.match(out.reason, /colours/);
});

test('per-pixel matching really does split a source colour, which is why indexed exists', () => {
  // The negative control for `test/recolor-indexed.test.js`: flat pixel art pushed through
  // the quantize path does *not* keep one source colour on one target colour. This is the
  // failure the indexed path exists to prevent, demonstrated rather than asserted about.
  const p = palette(8);
  const src = sprite(32, 32);
  for (const dither of ['floyd-steinberg', 'bayer8']) {
    const out = recolorQuantize(src, p.entries, { dither }).image;
    const seen = new Map();
    let split = 0;
    for (let i = 0; i < src.data.length; i += 3) {
      const from = (src.data[i] << 16) | (src.data[i + 1] << 8) | src.data[i + 2];
      const to = rgb8ToHex([out.data[i], out.data[i + 1], out.data[i + 2]]);
      if (!seen.has(from)) seen.set(from, to);
      else if (seen.get(from) !== to) split++;
    }
    assert.ok(split > 0, `${dither}: expected per-pixel matching to split a source colour`);
  }

  // …and the indexed path on the same image does not, which is the pair that matters.
  const indexed = recolorImage(src, p, { mode: 'indexed' }).image;
  const stable = new Map();
  for (let i = 0; i < src.data.length; i += 3) {
    const from = (src.data[i] << 16) | (src.data[i + 1] << 8) | src.data[i + 2];
    const to = rgb8ToHex([indexed.data[i], indexed.data[i + 1], indexed.data[i + 2]]);
    if (!stable.has(from)) stable.set(from, to);
    else assert.equal(stable.get(from), to, 'the indexed path split a source colour');
  }
});

test('the recoloured hues stay inside the palette, not just the RGB values', () => {
  // A cheap guard against a future "optimisation" that blends or interpolates: every hue in
  // the output must be one the palette actually contains.
  const p = palette(12);
  const hues = new Set(p.entries.map((e) => Math.round(oklabToOklch(...e.lab).h)));
  const out = recolorQuantize(photo(), p.entries, { dither: 'bayer8' }).image;
  for (let i = 0; i < out.data.length; i += 3) {
    const h = Math.round(oklabToOklch(...rgb8ToOklab([out.data[i], out.data[i + 1], out.data[i + 2]])).h);
    assert.ok(hues.has(h), `hue ${h} is not in the palette`);
  }
});
