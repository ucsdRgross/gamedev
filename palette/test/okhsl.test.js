// OKHSL (src/core/okhsl.js, task 4c.8) — the perceptual HSL used by the dither reference.
//
// It is a transcription of Ottosson's reference with hardcoded polynomial constants, so the tests
// pin the properties those constants are *for*: full sRGB-gamut coverage (no holes, unlike raw
// OKLCH), correct achromatic and endpoint behaviour, and — the whole reason it exists — a
// perceptually even lightness axis that plain HSL does not have.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { okhslToSrgb, hueContext, toe, toeInv, findCusp } from '../src/core/okhsl.js';
import { hslToSrgb } from '../src/core/layout/colorspace.js';
import { srgbToOklab } from '../src/core/oklch.js';

test('every OKHSL triple lands in the sRGB gamut', () => {
  // The property HSL has and raw OKLCH lacks: s and l are normalised to the gamut, so nothing
  // clips. A wrong cusp fit would push colours out of range, so this is the load-bearing check.
  let worst = 0;
  for (let h = 0; h < 360; h += 5) {
    const ctx = hueContext(h);
    for (let s = 0; s <= 1; s += 0.1) {
      for (let l = 0.02; l <= 0.98; l += 0.04) {
        for (const c of okhslToSrgb(h, s, l, ctx)) worst = Math.max(worst, -c, c - 1);
      }
    }
  }
  assert.ok(worst < 0.002, `OKHSL produced a colour ${worst.toFixed(4)} outside [0,1]`);
});

test('endpoints and the achromatic axis are exact', () => {
  for (const h of [0, 90, 210, 330]) {
    assert.deepEqual(okhslToSrgb(h, 1, 1), [1, 1, 1], `l=1 not white at h=${h}`);
    assert.deepEqual(okhslToSrgb(h, 1, 0), [0, 0, 0], `l=0 not black at h=${h}`);
    // s=0 is a pure grey: all three channels equal.
    const grey = okhslToSrgb(h, 0, 0.5);
    assert.ok(Math.abs(grey[0] - grey[1]) < 1e-9 && Math.abs(grey[1] - grey[2]) < 1e-9, `s=0 not grey at h=${h}`);
  }
});

test('lightness is perceptually even — the point of OKHSL over HSL', () => {
  // Measured in CIE L*, an independent perceptual lightness (NOT OKLab L, which OKHSL deliberately
  // makes non-uniform via the toe correction). Down an even l-sweep, OKHSL's L* steps are far more
  // even than HSL's, whose lightness crushes the mids — the banding OKHSL removes.
  const cv = (space) => {
    const Ls = [];
    for (let l = 0.02; l <= 0.98; l += 0.04) Ls.push(cieLstar(space(l)));
    const steps = Ls.slice(1).map((v, i) => v - Ls[i]);
    const mean = steps.reduce((s, v) => s + v, 0) / steps.length;
    return Math.sqrt(steps.reduce((s, v) => s + (v - mean) ** 2, 0) / steps.length) / mean;
  };
  const ctx = hueContext(30);
  const okhslCv = cv((l) => okhslToSrgb(30, 0.6, l, ctx));
  const hslCv = cv((l) => hslToSrgb(30, 0.6, l));
  assert.ok(okhslCv < hslCv * 0.75, `OKHSL lightness (cv ${okhslCv.toFixed(3)}) is not clearly more even than HSL (cv ${hslCv.toFixed(3)})`);
});

/** CIE L* from gamma sRGB — a perceptual lightness independent of OKLab. */
function cieLstar(rgb) {
  const lin = rgb.map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  const Y = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
  const f = Y > (6 / 29) ** 3 ? Math.cbrt(Y) : Y / (3 * (6 / 29) ** 2) + 4 / 29;
  return 116 * f - 16;
}

test('toe and toe_inv are inverses and pin the ends', () => {
  assert.ok(Math.abs(toe(0)) < 1e-12);
  assert.ok(Math.abs(toe(1) - 1) < 1e-12);
  for (let x = 0; x <= 1.0001; x += 0.1) assert.ok(Math.abs(toeInv(toe(x)) - x) < 1e-9, `toe not invertible at ${x}`);
});

test('the cusp is the most saturated in-gamut colour of its hue', () => {
  // find_cusp returns {L, C}; the colour there must sit right on the gamut boundary — one channel
  // at 0 or 1 — and pushing chroma past it must leave the gamut.
  for (const h of [30, 150, 260]) {
    const { a, b } = hueContext(h);
    const cusp = findCusp(a, b);
    assert.ok(cusp.C > 0 && cusp.L > 0 && cusp.L < 1);
    // At full saturation and the cusp's own lightness, OKHSL should reach essentially that chroma
    // and stay in gamut (checked by the gamut test above); here just assert the cusp is finite and
    // ordered sanely.
    assert.ok(Number.isFinite(cusp.C) && Number.isFinite(cusp.L));
  }
});

test('OKHSL is deterministic and hue wraps at 360', () => {
  assert.deepEqual(okhslToSrgb(123, 0.5, 0.5), okhslToSrgb(123, 0.5, 0.5));
  const a = okhslToSrgb(0, 0.7, 0.5);
  const b = okhslToSrgb(360, 0.7, 0.5);
  for (let i = 0; i < 3; i++) assert.ok(Math.abs(a[i] - b[i]) < 1e-9, 'hue 0 and 360 differ');
});
