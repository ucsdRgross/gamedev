// Dither tests: outputs use only palette colours, are deterministic, and behave sanely
// on flat fields and gradients.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  floydSteinberg, orderedDither, quantizeRaster, nearestIndex, paletteLabs, BAYER4, BAYER8,
} from '../src/core/dither.js';
import { Raster } from '../src/core/raster.js';

const PALETTE = [[0, 0, 0], [255, 255, 255], [200, 40, 40], [40, 80, 200]];

/** The set of distinct colours a raster actually contains. */
function colorsUsed(raster) {
  const set = new Set();
  for (let i = 0; i < raster.data.length; i += 3) {
    set.add(`${raster.data[i]},${raster.data[i + 1]},${raster.data[i + 2]}`);
  }
  return set;
}

/** Every pixel of `raster` is one of `palette`. */
function onlyPaletteColors(raster, palette) {
  const allowed = new Set(palette.map((c) => c.join(',')));
  for (const key of colorsUsed(raster)) if (!allowed.has(key)) return false;
  return true;
}

test('Bayer matrices are the right size and cover their full value range', () => {
  assert.equal(BAYER4.length, 4);
  assert.equal(BAYER8.length, 8);
  assert.deepEqual([...new Set(BAYER4.flat())].sort((a, b) => a - b)[0], 0);
  assert.equal(Math.max(...BAYER8.flat()), 63);
});

test('nearestIndex picks the perceptually closest entry', () => {
  const labs = paletteLabs(PALETTE);
  assert.equal(nearestIndex([250, 250, 250], labs), 1); // white
  assert.equal(nearestIndex([190, 50, 50], labs), 2); // red
});

test('Floyd–Steinberg output uses only palette colours', () => {
  const src = new Raster(16, 16, null);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) src.set(x, y, [x * 16, y * 16, 128]);
  const out = floydSteinberg(src, PALETTE);
  assert.ok(onlyPaletteColors(out, PALETTE));
});

test('ordered dither (4×4 and 8×8) uses only palette colours', () => {
  const src = new Raster(16, 16, null);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) src.set(x, y, [x * 16, x * 16, x * 16]);
  for (const size of [4, 8]) {
    const out = orderedDither(src, PALETTE, { size });
    assert.ok(onlyPaletteColors(out, PALETTE), `size ${size} strayed off palette`);
  }
});

test('a flat field of a palette colour survives Floyd–Steinberg unchanged', () => {
  const src = new Raster(8, 8, [200, 40, 40]);
  const out = floydSteinberg(src, PALETTE);
  assert.equal(colorsUsed(out).size, 1);
  assert.deepEqual(out.get(0, 0), [200, 40, 40]);
});

test('a black→white gradient dithers into more than one palette colour', () => {
  const src = new Raster(32, 4, null);
  for (let y = 0; y < 4; y++) for (let x = 0; x < 32; x++) src.set(x, y, [x * 8, x * 8, x * 8]);
  assert.ok(colorsUsed(floydSteinberg(src, PALETTE)).size >= 2);
  assert.ok(colorsUsed(orderedDither(src, PALETTE, { size: 4 })).size >= 2);
});

test('dithering is deterministic', () => {
  const src = new Raster(12, 12, null);
  for (let y = 0; y < 12; y++) for (let x = 0; x < 12; x++) src.set(x, y, [x * 20, y * 20, 100]);
  const a = floydSteinberg(src, PALETTE);
  const b = floydSteinberg(src, PALETTE);
  assert.deepEqual([...a.data], [...b.data]);
});

test('quantizeRaster maps to nearest palette colour with no diffusion', () => {
  const src = new Raster(2, 1, null);
  src.set(0, 0, [250, 250, 250]);
  src.set(1, 0, [190, 50, 50]);
  const out = quantizeRaster(src, PALETTE);
  assert.deepEqual(out.get(0, 0), [255, 255, 255]);
  assert.deepEqual(out.get(1, 0), [200, 40, 40]);
});
