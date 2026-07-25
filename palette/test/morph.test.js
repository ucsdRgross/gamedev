// The morph between two parameter sets. The endpoints must be exact and the angles must take
// the short way round; everything else is monotone travel.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { morphParams, morphSnapPoints } from '../src/core/morph.js';
import { defaultParams, normalizeParams, PARAMS } from '../src/core/params.js';
import { presetParams, PRESETS } from '../src/core/presets.js';
import { generatePalette } from '../src/core/generate.js';

test('the endpoints are exactly the endpoints', () => {
  const a = presetParams('neon-cyberpunk');
  const b = presetParams('frozen-tundra');
  assert.deepEqual(morphParams(a, b, 0), normalizeParams(a));
  assert.deepEqual(morphParams(a, b, 1), normalizeParams(b));
  // Out-of-range and junk clamp rather than throw.
  assert.deepEqual(morphParams(a, b, -1), normalizeParams(a));
  assert.deepEqual(morphParams(a, b, 5), normalizeParams(b));
  assert.deepEqual(morphParams(a, b, NaN), normalizeParams(a));
});

test('numbers travel monotonically and land halfway at the halfway point', () => {
  const a = { ...defaultParams(), l_mid_base: 0.4, chroma_base: 0.05, color_count: 16 };
  const b = { ...defaultParams(), l_mid_base: 0.8, chroma_base: 0.25, color_count: 48 };
  const mid = morphParams(a, b, 0.5);
  assert.ok(Math.abs(mid.l_mid_base - 0.6) < 0.01, mid.l_mid_base);
  assert.ok(Math.abs(mid.chroma_base - 0.15) < 0.01, mid.chroma_base);
  assert.equal(mid.color_count, 32, 'an int lands on an int');
  let prev = -Infinity;
  for (let t = 0; t <= 1.0001; t += 0.1) {
    const v = morphParams(a, b, t).l_mid_base;
    assert.ok(v >= prev - 1e-9, `t=${t.toFixed(1)} went backwards`);
    prev = v;
  }
});

test('angles take the short way round instead of walking the whole wheel', () => {
  const a = { ...defaultParams(), root_hue: 350 };
  const b = { ...defaultParams(), root_hue: 10 };
  // The short way is 350 → 0 → 10, so halfway is 0, not 180.
  const mid = morphParams(a, b, 0.5).root_hue;
  assert.ok(Math.min(mid, 360 - mid) < 1, `halfway should be near 0/360, got ${mid}`);
  // Every step stays in the 20° arc between the two, never crossing into the far side.
  for (let t = 0; t <= 1.0001; t += 0.05) {
    const h = morphParams(a, b, t).root_hue;
    assert.ok(h >= 349 || h <= 11, `t=${t.toFixed(2)} left the short arc at ${h}`);
  }
});

test('enums and bools snap at the halfway point rather than inventing a value', () => {
  const a = { ...defaultParams(), hue_scheme: 'triadic', neutral_split: false, l_curve: 'ease-dark' };
  const b = { ...defaultParams(), hue_scheme: 'complementary', neutral_split: true, l_curve: 's-curve' };
  assert.equal(morphParams(a, b, 0.49).hue_scheme, 'triadic');
  assert.equal(morphParams(a, b, 0.5).hue_scheme, 'complementary');
  assert.equal(morphParams(a, b, 0.49).neutral_split, false);
  assert.equal(morphParams(a, b, 0.5).neutral_split, true);
  assert.equal(morphParams(a, b, 0.49).l_curve, 'ease-dark');
});

test('the seed snaps, because walking it would re-roll the jitter at every step', () => {
  const a = { ...defaultParams(), seed: 100 };
  const b = { ...defaultParams(), seed: 60000 };
  assert.equal(morphParams(a, b, 0.25).seed, 100);
  assert.equal(morphParams(a, b, 0.75).seed, 60000);
  // Everything else being equal, a morph between two seeds has exactly two distinct results.
  const seen = new Set();
  for (let t = 0; t <= 1.0001; t += 0.05) seen.add(generatePalette(morphParams(a, b, t)).seed);
  assert.equal(seen.size, 2, 'a seed-only morph should not shimmer through intermediate seeds');
});

test('every step of a morph is a parameter set that generates', () => {
  for (const [x, y] of [['nes', 'pastel-cozy'], ['gameboy', 'neon-cyberpunk'], ['c64', 'frozen-tundra']]) {
    const a = presetParams(x);
    const b = presetParams(y);
    for (let t = 0; t <= 1.0001; t += 0.125) {
      const palette = generatePalette(morphParams(a, b, t));
      assert.ok(palette.entries.length >= 4, `${x}→${y} at ${t.toFixed(3)}`);
      for (const e of palette.entries) assert.match(e.hex, /^#[0-9A-F]{6}$/);
    }
  }
});

test('a morph covers every parameter, so nothing is silently left at A', () => {
  const a = defaultParams();
  const b = presetParams('blood-moon');
  const mid = morphParams(a, b, 1);
  for (const spec of PARAMS) assert.ok(spec.name in mid, `${spec.name} missing from the morph`);
});

test('snap points name what will jump, and say nothing when nothing will', () => {
  const a = presetParams('nes');
  assert.deepEqual(morphSnapPoints(a, a), [], 'a morph to itself has no discontinuity');
  const b = { ...a, hue_scheme: a.hue_scheme === 'triadic' ? 'even' : 'triadic' };
  const snaps = morphSnapPoints(a, b);
  assert.equal(snaps.length, 1);
  assert.equal(snaps[0].t, 0.5);
  assert.ok(snaps[0].names.includes('hue_scheme'));
  // Across real presets, whatever is reported as snapping is genuinely different.
  for (const preset of PRESETS.slice(0, 6)) {
    const from = normalizeParams(defaultParams());
    const to = presetParams(preset.id);
    for (const point of morphSnapPoints(from, to)) {
      for (const name of point.names) assert.notEqual(from[name], to[name], `${preset.id}/${name}`);
    }
  }
});
