import test from 'node:test';
import assert from 'node:assert/strict';
import {
  midIndex,
  easeCurve,
  anchorMargin,
  rampBounds,
  rampLightness,
  chromaAt,
  applyEarthiness,
  applyGlobalTemperature,
  familyTargets,
  shiftHue,
  buildRamp,
} from '../src/core/ramp.js';
import { defaultParams } from '../src/core/params.js';
import { hueDelta } from '../src/core/oklch.js';

const CURVES = ['ease-dark', 'linear', 'ease-light', 's-curve'];

test('mid index puts the midtone where the allocator expects it', () => {
  assert.equal(midIndex(1), 0);
  assert.equal(midIndex(2), 1);
  assert.equal(midIndex(3), 1);
  assert.equal(midIndex(4), 2);
  assert.equal(midIndex(5), 2);
  for (let n = 1; n <= 30; n++) {
    const m = midIndex(n);
    assert.ok(m >= 0 && m < n, `midIndex(${n}) = ${m}`);
  }
});

test('every easing curve is monotonic and pinned at both ends', () => {
  for (const curve of CURVES) {
    assert.ok(Math.abs(easeCurve(0, curve)) < 1e-12, curve);
    assert.ok(Math.abs(easeCurve(1, curve) - 1) < 1e-12, curve);
    let prev = -1;
    for (let t = 0; t <= 1.0001; t += 0.01) {
      const v = easeCurve(t, curve);
      assert.ok(v >= prev - 1e-12, `${curve} not monotonic at ${t}`);
      prev = v;
    }
  }
});

test('ramps stay inside the anchor bounds and rise monotonically', () => {
  for (const curve of CURVES) {
    for (let n = 1; n <= 8; n++) {
      for (const lMid of [0.2, 0.35, 0.56, 0.75]) {
        for (const step of [0.05, 0.15, 0.4]) {
          const p = { ...defaultParams(), l_curve: curve, l_step: step };
          const bounds = rampBounds(p);
          const ls = rampLightness(n, p, lMid, bounds);
          assert.equal(ls.length, n);
          for (const L of ls) {
            assert.ok(L >= bounds[0] - 1e-9 && L <= bounds[1] + 1e-9, `${L} outside ${bounds}`);
          }
          for (let j = 1; j < n; j++) {
            assert.ok(ls[j] >= ls[j - 1] - 1e-12, `${curve} n=${n} not monotonic`);
          }
        }
      }
    }
  }
});

test('anchor margin keeps shadows clear of the universal dark', () => {
  const p = { ...defaultParams(), min_delta_e: 8 };
  assert.ok(anchorMargin(p) >= 0.12);
  const [lo] = rampBounds(p);
  assert.ok(lo > p.l_dark_anchor, 'ramp floor must sit above the dark anchor');
});

test('lightness compression squeezes toward mid-grey', () => {
  const base = { ...defaultParams(), l_range_compress: 0 };
  const squeezed = { ...defaultParams(), l_range_compress: 0.8 };
  const a = rampLightness(5, base, 0.56, rampBounds(base));
  const b = rampLightness(5, squeezed, 0.56, rampBounds(squeezed));
  assert.ok(a[4] - a[0] > b[4] - b[0], 'compressed ramp should span less');
  for (const L of b) assert.ok(Math.abs(L - 0.5) < 0.15);
});

test('dither evenness pulls step sizes toward uniform', () => {
  const eased = { ...defaultParams(), l_curve: 'ease-dark', dither_evenness: 0 };
  const even = { ...defaultParams(), l_curve: 'ease-dark', dither_evenness: 1 };
  const spread = (p) => {
    const ls = rampLightness(5, p, 0.56, rampBounds(p));
    const deltas = ls.slice(1).map((L, i) => L - ls[i]);
    return Math.max(...deltas) - Math.min(...deltas);
  };
  assert.ok(spread(even) < spread(eased) - 1e-6, 'evenness should flatten the step spread');
  assert.ok(spread(even) < 1e-9, 'full evenness should give uniform steps');
});

test('chroma peaks at chroma_peak_l and respects the cap', () => {
  const p = { ...defaultParams(), chroma_falloff_light: 0, chroma_falloff_dark: 0 };
  const peak = chromaAt(p.chroma_peak_l, 0.2, 0.56, p);
  for (let L = 0.05; L < 1; L += 0.05) {
    assert.ok(chromaAt(L, 0.2, 0.56, p) <= peak + 1e-12, `chroma exceeded the peak at L=${L}`);
  }
  const capped = { ...p, chroma_cap: 0.08 };
  for (let L = 0.05; L < 1; L += 0.05) {
    const c = chromaAt(L, 0.35, 0.56, capped);
    assert.ok(c >= 0 && c <= 0.08 + 1e-12, `chroma ${c} broke the cap`);
  }
});

test('negative dark falloff boosts shadow chroma', () => {
  const flat = { ...defaultParams(), chroma_falloff_dark: 0, chroma_cap: 0.37 };
  const boosted = { ...flat, chroma_falloff_dark: -0.05 };
  const L = 0.3;
  assert.ok(chromaAt(L, 0.15, 0.56, boosted) > chromaAt(L, 0.15, 0.56, flat));
});

test('earthiness lowers chroma and pulls hue toward ochre', () => {
  const plain = applyEarthiness(0.2, 220, 0);
  assert.deepEqual(plain, { C: 0.2, h: 220 });
  const earthy = applyEarthiness(0.2, 220, 1);
  assert.ok(earthy.C < 0.2);
  assert.ok(Math.abs(hueDelta(earthy.h, 55)) < Math.abs(hueDelta(220, 55)));
});

test('global temperature biases hue warm or cool', () => {
  assert.deepEqual(applyGlobalTemperature(0.2, 180, 0), { C: 0.2, h: 180 });
  const warm = applyGlobalTemperature(0.2, 180, 1);
  const cool = applyGlobalTemperature(0.2, 180, -1);
  assert.ok(Math.abs(hueDelta(warm.h, 60)) < Math.abs(hueDelta(180, 60)));
  assert.ok(Math.abs(hueDelta(cool.h, 250)) < Math.abs(hueDelta(180, 250)));
});

test('family targets cover the whole circle', () => {
  for (let h = 0; h < 360; h += 7) {
    const t = familyTargets(h);
    assert.ok(Number.isFinite(t.light) && Number.isFinite(t.shadow), `no target at ${h}`);
  }
});

test('highlights move toward the highlight target under the attractor models', () => {
  for (const model of ['global-attractor', 'relative-rotation']) {
    for (const dir of ['shortest', 'always-cw', 'always-ccw']) {
      const p = { ...defaultParams(), shift_model: model, shift_direction: dir, temperature_split: 0.75 };
      for (let base = 0; base < 360; base += 13) {
        if (Math.abs(hueDelta(base, p.highlight_hue_target)) < 1) continue;
        const hi = shiftHue(base, 1, p);
        const mid = shiftHue(base, 0, p);
        assert.equal(mid, base % 360, `midtone must not shift (${model}/${dir})`);
        if (dir === 'shortest') {
          assert.ok(
            Math.abs(hueDelta(hi, p.highlight_hue_target)) <=
              Math.abs(hueDelta(base, p.highlight_hue_target)) + 1e-9,
            `${model}/${dir} highlight at base ${base} moved away from the target`,
          );
        } else {
          assert.notEqual(hi, base % 360, `${model}/${dir} should rotate at base ${base}`);
        }
      }
    }
  }
});

test('shadows move toward the shadow target under the attractor model', () => {
  const p = { ...defaultParams(), shift_model: 'global-attractor', temperature_split: 0.75 };
  for (let base = 0; base < 360; base += 11) {
    if (Math.abs(hueDelta(base, p.shadow_hue_target)) < 1) continue;
    const lo = shiftHue(base, -1, p);
    assert.ok(
      Math.abs(hueDelta(lo, p.shadow_hue_target)) <
        Math.abs(hueDelta(base, p.shadow_hue_target)) + 1e-9,
      `shadow at base ${base} moved away from the target`,
    );
  }
});

test('inverting temperature_split swaps light and shadow drift', () => {
  const normal = { ...defaultParams(), shift_model: 'global-attractor', temperature_split: 1 };
  const inverted = { ...normal, temperature_split: 0 };
  const base = 200;
  const hiNormal = shiftHue(base, 1, normal);
  const hiInverted = shiftHue(base, 1, inverted);
  assert.ok(
    Math.abs(hueDelta(hiNormal, normal.highlight_hue_target)) <
      Math.abs(hueDelta(base, normal.highlight_hue_target)),
  );
  assert.ok(
    Math.abs(hueDelta(hiInverted, normal.shadow_hue_target)) <
      Math.abs(hueDelta(base, normal.shadow_hue_target)),
    'inverted split should send highlights toward the shadow target',
  );
});

test('buildRamp emits well-formed monotonic ramps', () => {
  const p = defaultParams();
  for (let n = 1; n <= 6; n++) {
    const ramp = buildRamp({
      hue: 140, steps: n, params: p, lMid: p.l_mid_base, chromaBase: p.chroma_base,
      bounds: rampBounds(p),
    });
    assert.equal(ramp.length, n);
    for (let j = 0; j < n; j++) {
      const c = ramp[j];
      assert.ok(Number.isFinite(c.L) && c.L >= 0 && c.L <= 1);
      assert.ok(Number.isFinite(c.C) && c.C >= 0 && c.C <= 0.37);
      assert.ok(Number.isFinite(c.h) && c.h >= 0 && c.h < 360);
      if (j > 0) assert.ok(c.L >= ramp[j - 1].L - 1e-12, 'ramp lightness must not fall');
    }
  }
});

test('background scaling desaturates and darkens without breaking the ramp', () => {
  const p = defaultParams();
  const bounds = rampBounds(p);
  const fg = buildRamp({ hue: 140, steps: 3, params: p, lMid: p.l_mid_base, chromaBase: p.chroma_base, bounds });
  const bg = buildRamp({
    hue: 140, steps: 3, params: p, lMid: p.l_mid_base, chromaBase: p.chroma_base, bounds,
    chromaScale: p.bg_chroma_mult, lOffset: p.bg_lightness_offset,
  });
  for (let j = 0; j < 3; j++) assert.ok(bg[j].C < fg[j].C, 'background must be less saturated');
  assert.ok(bg[1].L < fg[1].L, 'negative offset should darken the background');
});
