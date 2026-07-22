// Raster surface tests: bounds safety, primitives, scaling, and the two export shapes.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Raster, toRgb } from '../src/core/raster.js';

test('a fresh raster is filled and reads back the fill colour', () => {
  const r = new Raster(4, 3, [10, 20, 30]);
  assert.equal(r.w, 4);
  assert.equal(r.h, 3);
  assert.deepEqual(r.get(0, 0), [10, 20, 30]);
  assert.deepEqual(r.get(3, 2), [10, 20, 30]);
});

test('out-of-bounds set is ignored; get is edge-clamped', () => {
  const r = new Raster(2, 2, [0, 0, 0]);
  assert.doesNotThrow(() => r.set(-1, -1, [255, 0, 0]));
  assert.doesNotThrow(() => r.set(99, 99, [255, 0, 0]));
  r.set(0, 0, [1, 2, 3]);
  assert.deepEqual(r.get(-5, -5), [1, 2, 3]); // clamps to (0,0)
});

test('rect fills only the clipped region', () => {
  const r = new Raster(5, 5, [0, 0, 0]);
  r.rect(1, 1, 2, 2, [9, 9, 9]);
  assert.deepEqual(r.get(1, 1), [9, 9, 9]);
  assert.deepEqual(r.get(2, 2), [9, 9, 9]);
  assert.deepEqual(r.get(0, 0), [0, 0, 0]);
  assert.deepEqual(r.get(3, 3), [0, 0, 0]);
});

test('outline touches the border but not the interior', () => {
  const r = new Raster(4, 4, [0, 0, 0]);
  r.outline(0, 0, 4, 4, [5, 5, 5]);
  assert.deepEqual(r.get(0, 0), [5, 5, 5]);
  assert.deepEqual(r.get(3, 3), [5, 5, 5]);
  assert.deepEqual(r.get(1, 1), [0, 0, 0]);
});

test('line draws its endpoints', () => {
  const r = new Raster(8, 8, [0, 0, 0]);
  r.line(0, 0, 7, 7, [1, 1, 1]);
  assert.deepEqual(r.get(0, 0), [1, 1, 1]);
  assert.deepEqual(r.get(7, 7), [1, 1, 1]);
  assert.deepEqual(r.get(4, 4), [1, 1, 1]);
});

test('scaled() enlarges by an integer factor with nearest-neighbour blocks', () => {
  const r = new Raster(2, 2, [0, 0, 0]);
  r.set(0, 0, [200, 0, 0]);
  const s = r.scaled(3);
  assert.equal(s.w, 6);
  assert.equal(s.h, 6);
  for (let y = 0; y < 3; y++) for (let x = 0; x < 3; x++) assert.deepEqual(s.get(x, y), [200, 0, 0]);
  assert.deepEqual(s.get(3, 0), [0, 0, 0]);
});

test('blit copies a sub-raster at an offset', () => {
  const dst = new Raster(6, 6, [0, 0, 0]);
  const src = new Raster(2, 2, [7, 7, 7]);
  dst.blit(src, 2, 2);
  assert.deepEqual(dst.get(2, 2), [7, 7, 7]);
  assert.deepEqual(dst.get(3, 3), [7, 7, 7]);
  assert.deepEqual(dst.get(1, 1), [0, 0, 0]);
});

test('toImageData yields RGBA with opaque alpha; rows() yields h×w triples', () => {
  const r = new Raster(2, 1, [4, 5, 6]);
  const rgba = r.toImageData();
  assert.equal(rgba.length, 2 * 1 * 4);
  assert.deepEqual([...rgba.slice(0, 4)], [4, 5, 6, 255]);
  const rows = r.rows();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].length, 2);
  assert.deepEqual(rows[0][0], [4, 5, 6]);
});

test('toRgb coerces hex, entry, and array forms', () => {
  assert.deepEqual(toRgb('#FF0000'), [255, 0, 0]);
  assert.deepEqual(toRgb([1, 2, 3]), [1, 2, 3]);
  assert.deepEqual(toRgb({ rgb8: [9, 8, 7] }), [9, 8, 7]);
  assert.deepEqual(toRgb({ hex: '#00FF00' }), [0, 255, 0]);
});
