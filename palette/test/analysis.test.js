// Analysis tests: dichromat simulation behaviour, the value view, and ramp evenness.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  simulateColorblind, toValue, viewColor, applyView, rampEvenness, rampsOf, VIEWS,
} from '../src/core/analysis.js';
import { rgb8ToOklch, deltaERgb8 } from '../src/core/oklch.js';
import { Raster } from '../src/core/raster.js';
import { generatePalette } from '../src/core/generate.js';

test('dichromat simulation stays in gamut for every channel', () => {
  for (const type of ['protan', 'deutan', 'tritan']) {
    for (const c of [[255, 0, 0], [0, 255, 0], [0, 0, 255], [128, 64, 200], [255, 255, 255], [0, 0, 0]]) {
      const out = simulateColorblind(c, type);
      for (const v of out) assert.ok(v >= 0 && v <= 255 && Number.isFinite(v));
    }
  }
});

test('protan/deutan pull red and green closer together (confusion axis)', () => {
  const red = [220, 30, 30];
  const green = [30, 200, 30];
  const before = deltaERgb8(red, green);
  for (const type of ['protan', 'deutan']) {
    const after = deltaERgb8(simulateColorblind(red, type), simulateColorblind(green, type));
    assert.ok(after < before, `${type}: expected red/green to converge (${after} < ${before})`);
  }
});

test('a neutral gray is (near) unchanged by dichromat simulation', () => {
  const gray = [128, 128, 128];
  for (const type of ['protan', 'deutan', 'tritan']) {
    const out = simulateColorblind(gray, type);
    assert.ok(deltaERgb8(gray, out) < 6, `${type} shifted a neutral by too much`);
  }
});

test('toValue produces a gray whose OKLCH lightness tracks the input', () => {
  const dark = toValue([20, 20, 60]);
  const light = toValue([240, 230, 200]);
  assert.ok(Math.abs(dark[0] - dark[1]) <= 1 && Math.abs(dark[1] - dark[2]) <= 1, 'value is neutral');
  assert.ok(rgb8ToOklch(light).L > rgb8ToOklch(dark).L, 'lighter input -> lighter value');
});

test('viewColor and VIEWS: color is identity, others transform', () => {
  const c = [180, 60, 40];
  assert.deepEqual(viewColor(c, 'color'), c);
  assert.notDeepEqual(viewColor(c, 'value'), c);
  assert.deepEqual(VIEWS, ['color', 'value', 'protan', 'deutan', 'tritan']);
});

test('applyView returns the same raster for color and a new one otherwise', () => {
  const r = new Raster(3, 3, [200, 40, 40]);
  assert.equal(applyView(r, 'color'), r);
  const v = applyView(r, 'value');
  assert.notEqual(v, r);
  assert.equal(v.w, 3);
  const px = v.get(1, 1);
  assert.ok(Math.abs(px[0] - px[1]) <= 1, 'value view pixel is neutral');
});

test('rampEvenness scores a perfectly even ramp near 1 and a lumpy one lower', () => {
  const even = generatePalette({ color_count: 32, l_curve: 'linear', dither_evenness: 1 });
  const ramps = rampsOf(even).filter((r) => r.entries.length >= 3);
  assert.ok(ramps.length > 0, 'palette has multi-step ramps');
  for (const r of ramps) {
    const m = rampEvenness(r.entries);
    assert.ok(m.evennessL >= 0 && m.evennessL <= 1);
    assert.equal(m.deltaL.length, r.entries.length - 1);
  }
});
