import test from 'node:test';
import assert from 'node:assert/strict';
import { gamutMap, gamutMapToOklch, inSrgb, maxChromaFor, gamutCusp } from '../src/core/gamut.js';
import {
  oklchToSrgb,
  srgbToOklch,
  srgbToOklab,
  oklchToOklab,
  deltaEOK,
  hueDelta,
  clamp,
} from '../src/core/oklch.js';

/** Sweep a coarse but wide OKLCH grid, including deliberately out-of-gamut chroma. */
function* grid() {
  for (let L = 0.05; L <= 0.96; L += 0.05) {
    for (let C = 0; C <= 0.37; C += 0.04) {
      for (let h = 0; h < 360; h += 15) yield [L, C, h];
    }
  }
}

test('every mapped colour is displayable', () => {
  for (const [L, C, h] of grid()) {
    const rgb = gamutMap(L, C, h);
    for (const v of rgb) {
      assert.ok(Number.isFinite(v), `non-finite channel at ${L},${C},${h}`);
      assert.ok(v >= -1e-9 && v <= 1 + 1e-9, `channel ${v} out of range at ${L},${C},${h}`);
    }
  }
});

test('gamut mapping preserves lightness and hue', () => {
  let worstL = 0;
  let worstH = 0;
  let worstDE = 0;
  for (const [L, C, h] of grid()) {
    const out = gamutMapToOklch(L, C, h);
    worstL = Math.max(worstL, Math.abs(out.L - L));
    // Distance to the ideal colour at the chroma actually achieved: this is the
    // bound that holds at every chroma, including near-neutral.
    worstDE = Math.max(worstDE, deltaEOK(srgbToOklab(out.rgb), oklchToOklab(L, out.C, h)));
    // Hue angle is only a meaningful measure once there is chroma to carry it.
    if (out.C > 0.04 && C > 0.04) worstH = Math.max(worstH, Math.abs(hueDelta(out.h, h)));
  }
  assert.ok(worstL < 0.01, `worst lightness drift ${worstL}`);
  assert.ok(worstH < 2.0, `worst hue drift ${worstH} degrees`);
  assert.ok(worstDE < 0.5, `worst deltaE from the ideal ${worstDE}`);
});

test('naive channel clipping fails the hue/lightness preservation test', () => {
  // This is the artifact chroma-reduction exists to avoid; if `clip` ever starts
  // passing, the sample below stopped being out of gamut and the test is stale.
  let worstL = 0;
  let worstH = 0;
  for (const [L, C, h] of grid()) {
    if (inSrgb(L, C, h)) continue;
    const rgb = gamutMap(L, C, h, 'clip');
    const out = srgbToOklch([clamp(rgb[0], 0, 1), clamp(rgb[1], 0, 1), clamp(rgb[2], 0, 1)]);
    worstL = Math.max(worstL, Math.abs(out.L - L));
    if (out.C > 0.02) worstH = Math.max(worstH, Math.abs(hueDelta(out.h, h)));
  }
  assert.ok(worstL > 0.05, `clip should distort lightness, worst was ${worstL}`);
  assert.ok(worstH > 5, `clip should distort hue, worst was ${worstH} degrees`);
});

test('in-gamut colours pass through untouched', () => {
  for (const [L, C, h] of grid()) {
    if (!inSrgb(L, C, h)) continue;
    // "Untouched" up to the float noise scrubbed off colours that sit exactly on the
    // gamut boundary — the mapper must not reduce chroma for anything displayable.
    const direct = oklchToSrgb(L, C, h).map((v) => clamp(v, 0, 1));
    const mapped = gamutMap(L, C, h);
    for (let i = 0; i < 3; i++) {
      assert.ok(Math.abs(direct[i] - mapped[i]) < 1e-9, `passthrough at ${L},${C},${h}`);
    }
  }
});

test('chroma is only ever reduced, never increased', () => {
  for (const [L, C, h] of grid()) {
    const out = gamutMapToOklch(L, C, h);
    assert.ok(out.C <= C + 1e-3, `chroma grew from ${C} to ${out.C} at ${L},${h}`);
  }
});

test('degenerate lightness maps to black and white', () => {
  assert.deepEqual(gamutMap(0, 0.2, 140), [0, 0, 0]);
  assert.deepEqual(gamutMap(1, 0.2, 140), [1, 1, 1]);
});

test('maxChromaFor bounds the displayable region', () => {
  for (let h = 0; h < 360; h += 23) {
    for (let L = 0.1; L < 1; L += 0.1) {
      const c = maxChromaFor(L, h);
      assert.ok(inSrgb(L, c, h), `max chroma ${c} should be in gamut at L=${L} h=${h}`);
      assert.ok(!inSrgb(L, c + 0.005, h), `chroma just past max should be out of gamut`);
    }
  }
});

test('gamut cusp is the widest point of the hue leaf', () => {
  for (let h = 0; h < 360; h += 37) {
    const cusp = gamutCusp(h);
    for (let L = 0.05; L < 1; L += 0.05) {
      assert.ok(maxChromaFor(L, h) <= cusp.C + 1e-3, `cusp not maximal at h=${h}, L=${L}`);
    }
  }
});

test('reduce-l-adjust stays in gamut and keeps lightness close', () => {
  for (const [L, C, h] of grid()) {
    const out = gamutMapToOklch(L, C, h, 'reduce-l-adjust');
    for (const v of out.rgb) assert.ok(v >= -1e-9 && v <= 1 + 1e-9);
    assert.ok(Math.abs(out.L - L) <= 0.021, `lightness drifted ${Math.abs(out.L - L)}`);
  }
});
