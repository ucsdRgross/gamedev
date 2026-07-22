import test from 'node:test';
import assert from 'node:assert/strict';
import {
  oklchToOklab,
  oklabToOklch,
  oklabToLinearRgb,
  linearRgbToOklab,
  linearToSrgb,
  srgbToLinear,
  oklchToSrgb,
  srgbToOklch,
  srgbToRgb8,
  rgb8ToOklab,
  rgb8ToOklch,
  rgb8ToHex,
  hexToRgb8,
  deltaEOK,
  deltaERgb8,
  relativeLuminance,
  contrastRatio,
  hueDelta,
  normHue,
} from '../src/core/oklch.js';

test('published OKLab reference values for sRGB primaries', () => {
  // Values from Björn Ottosson's OKLab reference article.
  const cases = [
    [[255, 255, 255], [1.0, 0.0, 0.0]],
    [[0, 0, 0], [0.0, 0.0, 0.0]],
    [[255, 0, 0], [0.6279554, 0.2248631, 0.1258463]],
    [[0, 255, 0], [0.8664396, -0.2338874, 0.1794985]],
    [[0, 0, 255], [0.4520137, -0.0324454, -0.3115281]],
  ];
  for (const [rgb, expected] of cases) {
    const lab = rgb8ToOklab(rgb);
    for (let i = 0; i < 3; i++) {
      assert.ok(
        Math.abs(lab[i] - expected[i]) < 1e-4,
        `${rgb} component ${i}: got ${lab[i]}, want ${expected[i]}`,
      );
    }
  }
});

test('OKLab <-> linear sRGB round-trips on a dense grid', () => {
  for (let r = 0; r <= 1.0001; r += 0.1) {
    for (let g = 0; g <= 1.0001; g += 0.1) {
      for (let b = 0; b <= 1.0001; b += 0.1) {
        const lab = linearRgbToOklab(r, g, b);
        const back = oklabToLinearRgb(lab[0], lab[1], lab[2]);
        for (let i = 0; i < 3; i++) {
          assert.ok(Math.abs(back[i] - [r, g, b][i]) < 1e-6, `linear round-trip at ${r},${g},${b}`);
        }
      }
    }
  }
});

test('OKLCH <-> OKLab round-trips', () => {
  for (let L = 0.05; L <= 0.95; L += 0.1) {
    for (let C = 0.0; C <= 0.3; C += 0.05) {
      for (let h = 0; h < 360; h += 17) {
        const lab = oklchToOklab(L, C, h);
        const lch = oklabToOklch(lab[0], lab[1], lab[2]);
        assert.ok(Math.abs(lch.L - L) < 1e-9);
        assert.ok(Math.abs(lch.C - C) < 1e-9);
        if (C > 1e-6) {
          assert.ok(Math.abs(hueDelta(lch.h, h)) < 1e-6, `hue round-trip at ${h}`);
        }
      }
    }
  }
});

test('sRGB transfer function round-trips', () => {
  for (let v = 0; v <= 1.0001; v += 0.005) {
    assert.ok(Math.abs(linearToSrgb(srgbToLinear(v)) - v) < 1e-9);
  }
});

test('every 8-bit colour round-trips through OKLCH within one code value', () => {
  let worst = 0;
  for (let r = 0; r < 256; r += 7) {
    for (let g = 0; g < 256; g += 11) {
      for (let b = 0; b < 256; b += 13) {
        const lch = rgb8ToOklch([r, g, b]);
        const back = srgbToRgb8(oklchToSrgb(lch.L, lch.C, lch.h));
        for (let i = 0; i < 3; i++) worst = Math.max(worst, Math.abs(back[i] - [r, g, b][i]));
      }
    }
  }
  assert.ok(worst <= 1, `worst 8-bit round-trip error ${worst}`);
});

test('hex parse and format round-trip', () => {
  assert.equal(rgb8ToHex([0, 0, 0]), '#000000');
  assert.equal(rgb8ToHex([255, 255, 255]), '#FFFFFF');
  assert.equal(rgb8ToHex([18, 52, 86]), '#123456');
  assert.deepEqual(hexToRgb8('#123456'), [18, 52, 86]);
  assert.deepEqual(hexToRgb8('123456'), [18, 52, 86]);
  assert.deepEqual(hexToRgb8('#abc'), [170, 187, 204]);
  assert.throws(() => hexToRgb8('#12345'), /bad hex/);
  assert.throws(() => hexToRgb8('nope'), /bad hex/);
  for (let i = 0; i < 256; i += 3) {
    const c = [i, (i * 3) % 256, (i * 7) % 256];
    assert.deepEqual(hexToRgb8(rgb8ToHex(c)), c);
  }
});

test('deltaEOK is zero for identical colours and symmetric', () => {
  assert.equal(deltaEOK([0.5, 0.1, -0.1], [0.5, 0.1, -0.1]), 0);
  const a = [12, 200, 90];
  const b = [200, 12, 90];
  assert.ok(Math.abs(deltaERgb8(a, b) - deltaERgb8(b, a)) < 1e-12);
  assert.ok(deltaERgb8(a, b) > 10);
  assert.ok(deltaERgb8([100, 100, 100], [101, 100, 100]) < 1);
});

test('WCAG luminance and contrast match known values', () => {
  assert.ok(Math.abs(relativeLuminance([255, 255, 255]) - 1) < 1e-9);
  assert.ok(Math.abs(relativeLuminance([0, 0, 0])) < 1e-9);
  assert.ok(Math.abs(contrastRatio([255, 255, 255], [0, 0, 0]) - 21) < 1e-9);
  assert.equal(contrastRatio([120, 30, 90], [120, 30, 90]), 1);
  // #777777 on white is a widely cited 4.48:1 pair.
  assert.ok(Math.abs(contrastRatio([119, 119, 119], [255, 255, 255]) - 4.48) < 0.01);
  // Contrast is order-independent.
  assert.equal(
    contrastRatio([10, 20, 30], [200, 210, 220]),
    contrastRatio([200, 210, 220], [10, 20, 30]),
  );
});

test('hue helpers wrap correctly', () => {
  assert.equal(normHue(-10), 350);
  assert.equal(normHue(370), 10);
  assert.equal(hueDelta(10, 20), 10);
  assert.equal(hueDelta(350, 10), 20);
  assert.equal(hueDelta(10, 350), -20);
  assert.equal(hueDelta(0, 180), -180);
  assert.ok(Math.abs(hueDelta(279, 280) - 1) < 1e-9);
});
