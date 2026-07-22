import test from 'node:test';
import assert from 'node:assert/strict';
import { HUE_LANDMARKS, perceptualToHue, lerpHue, buildHues, hueGapCenters } from '../src/core/hues.js';
import { makeRng } from '../src/core/rng.js';
import { defaultParams } from '../src/core/params.js';
import { hueDelta, normHue } from '../src/core/oklch.js';

const SCHEMES = ['even', 'analogous', 'complementary', 'split-comp', 'triadic', 'tetradic', 'custom'];

test('landmarks are the sRGB primaries and secondaries in ascending order', () => {
  assert.equal(HUE_LANDMARKS.length, 6);
  for (let i = 1; i < 6; i++) {
    assert.ok(HUE_LANDMARKS[i] > HUE_LANDMARKS[i - 1], `landmark ${i} out of order`);
  }
  // Red sits near 29 degrees and blue near 264 in OKLCH.
  assert.ok(Math.abs(HUE_LANDMARKS[0] - 29.23) < 0.1, `red at ${HUE_LANDMARKS[0]}`);
  assert.ok(Math.abs(HUE_LANDMARKS[4] - 264.05) < 0.2, `blue at ${HUE_LANDMARKS[4]}`);
});

test('perceptual warp pins landmarks to evenly spaced positions', () => {
  for (let k = 0; k < 6; k++) {
    const even = normHue(HUE_LANDMARKS[0] + k * 60);
    const got = perceptualToHue(even);
    assert.ok(Math.abs(hueDelta(got, HUE_LANDMARKS[k])) < 1e-6, `landmark ${k}: ${got}`);
  }
});

test('perceptual warp is a continuous bijection of the circle', () => {
  let prev = perceptualToHue(0);
  let total = 0;
  for (let p = 1; p <= 360; p++) {
    const cur = perceptualToHue(p % 360);
    const step = normHue(cur - prev);
    assert.ok(step >= 0 && step < 5, `discontinuity at ${p}: step ${step}`);
    total += step;
    prev = cur;
  }
  assert.ok(Math.abs(total - 360) < 1e-6, `warp covers ${total} degrees`);
});

test('lerpHue honours every shift direction', () => {
  assert.ok(Math.abs(lerpHue(10, 350, 1, 'shortest') - 350) < 1e-9);
  assert.ok(Math.abs(lerpHue(10, 350, 0.5, 'shortest') - 0) < 1e-9);
  assert.ok(Math.abs(lerpHue(10, 350, 0.5, 'always-cw') - 180) < 1e-9);
  assert.ok(Math.abs(lerpHue(10, 350, 0.5, 'always-ccw') - 0) < 1e-9);
  assert.ok(Math.abs(lerpHue(100, 200, 0, 'shortest') - 100) < 1e-9);
  assert.ok(Math.abs(lerpHue(100, 200, 1, 'always-ccw') - 200) < 1e-9);
});

test('lerpHue with a fixed direction has no antipode discontinuity', () => {
  // Base hues either side of the target must move the same way under always-cw.
  const a = lerpHue(279, 280, 0.5, 'always-cw');
  const b = lerpHue(281, 280, 0.5, 'always-cw');
  assert.ok(hueDelta(279, a) > 0, 'below the target should still rotate clockwise');
  assert.ok(hueDelta(281, b) > 0, 'above the target should still rotate clockwise');
});

test('every scheme produces the requested number of distinct hues', () => {
  const rng = makeRng(1);
  for (const scheme of SCHEMES) {
    for (let n = 1; n <= 8; n++) {
      const p = { ...defaultParams(), hue_scheme: scheme };
      const hues = buildHues(p, n, makeRng(n * 7 + scheme.length));
      assert.equal(hues.length, n, `${scheme} n=${n}`);
      for (const h of hues) {
        assert.ok(Number.isFinite(h) && h >= 0 && h < 360, `${scheme} produced ${h}`);
      }
      if (n > 1) {
        for (let a = 0; a < n; a++) {
          for (let b = a + 1; b < n; b++) {
            const d = Math.abs(hueDelta(hues[a], hues[b]));
            assert.ok(d > 1, `${scheme} n=${n} hues ${a},${b} collapsed (${d} deg apart)`);
          }
        }
      }
    }
  }
  rng();
});

test('hue generation is deterministic for a given seed', () => {
  const p = defaultParams();
  const a = buildHues(p, 5, makeRng(99));
  const b = buildHues(p, 5, makeRng(99));
  const c = buildHues(p, 5, makeRng(100));
  assert.deepEqual(a, b);
  assert.notDeepEqual(a, c);
});

test('zero jitter with zero warp reproduces the raw scheme angles', () => {
  const p = { ...defaultParams(), hue_scheme: 'even', hue_jitter: 0, perceptual_hue_spacing: 0, root_hue: 40 };
  const hues = buildHues(p, 4, makeRng(1));
  assert.deepEqual(hues.map((h) => Math.round(h)), [40, 130, 220, 310]);
});

test('triadic places hues on 120-degree poles', () => {
  const p = {
    ...defaultParams(), hue_scheme: 'triadic', hue_jitter: 0, perceptual_hue_spacing: 0, root_hue: 0,
  };
  const hues = buildHues(p, 3, makeRng(1));
  assert.deepEqual(hues.map((h) => Math.round(h)), [0, 120, 240]);
});

test('analogous keeps every hue inside the span', () => {
  const p = {
    ...defaultParams(), hue_scheme: 'analogous', hue_jitter: 0, perceptual_hue_spacing: 0,
    root_hue: 100, hue_span: 60,
  };
  const hues = buildHues(p, 5, makeRng(1));
  for (const h of hues) assert.ok(h >= 69.9 && h <= 130.1, `${h} outside the span`);
});

test('gap centres land in the largest holes', () => {
  const centers = hueGapCenters([0, 90], 1);
  assert.equal(centers.length, 1);
  assert.ok(Math.abs(centers[0] - 225) < 1e-6, `got ${centers[0]}`);
  const two = hueGapCenters([0, 90], 2);
  assert.equal(two.length, 2);
  assert.notEqual(two[0], two[1]);
  assert.deepEqual(hueGapCenters([], 2).length, 2);
});
