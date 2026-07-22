import test from 'node:test';
import assert from 'node:assert/strict';
import {
  channelLevels,
  legalValues,
  quantizeChannel,
  quantizeSrgb,
  quantizeToRgb8,
  isOnGrid,
  gridSize,
} from '../src/core/quantize.js';
import { srgbToOklab, deltaEOK } from '../src/core/oklch.js';

const MODES = ['round', 'floor', 'error-weighted'];

test('level counts follow 2^bits', () => {
  for (let b = 1; b <= 8; b++) assert.equal(channelLevels(b), 2 ** b);
  assert.equal(legalValues(1).length, 2);
  assert.deepEqual(legalValues(1), [0, 255]);
  assert.deepEqual(legalValues(2), [0, 85, 170, 255]);
  assert.equal(legalValues(8).length, 256);
  assert.deepEqual(legalValues(8).slice(0, 3), [0, 1, 2]);
});

test('output lands on the legal grid for every R/G/B bit combination', () => {
  const samples = [];
  for (let i = 0; i < 24; i++) {
    samples.push([((i * 37) % 100) / 99, ((i * 61) % 100) / 99, ((i * 13) % 100) / 99]);
  }
  for (let br = 1; br <= 8; br++) {
    for (let bg = 1; bg <= 8; bg++) {
      for (let bb = 1; bb <= 8; bb++) {
        for (const mode of MODES) {
          for (const s of samples) {
            const out = quantizeToRgb8(s, br, bg, bb, mode);
            assert.ok(
              isOnGrid(out, br, bg, bb),
              `${out} off grid at ${br}/${bg}/${bb} mode=${mode} sample=${s}`,
            );
          }
        }
      }
    }
  }
});

test('8-bit depth is a pass-through for round mode', () => {
  for (let v = 0; v < 256; v++) {
    const out = quantizeToRgb8([v / 255, v / 255, v / 255], 8, 8, 8, 'round');
    assert.deepEqual(out, [v, v, v]);
  }
});

test('endpoints are exactly reachable at every depth', () => {
  for (let b = 1; b <= 8; b++) {
    assert.equal(quantizeChannel(0, b), 0);
    assert.equal(quantizeChannel(1, b), 1);
  }
});

test('floor never rounds up and round never strays more than half a step', () => {
  for (let b = 1; b <= 8; b++) {
    const step = 1 / (channelLevels(b) - 1);
    for (let i = 0; i <= 100; i++) {
      const v = i / 100;
      const f = quantizeChannel(v, b, 'floor');
      const r = quantizeChannel(v, b, 'round');
      assert.ok(f <= v + 1e-12, `floor ${f} > ${v} at ${b} bits`);
      assert.ok(v - f < step + 1e-12);
      assert.ok(Math.abs(r - v) <= step / 2 + 1e-12);
    }
  }
});

test('error-weighted is never worse than round at low bit depth', () => {
  let improved = 0;
  for (let i = 0; i < 400; i++) {
    const s = [((i * 37) % 251) / 250, ((i * 97) % 251) / 250, ((i * 173) % 251) / 250];
    const ideal = srgbToOklab(s);
    for (const [br, bg, bb] of [[2, 2, 2], [3, 3, 3], [4, 2, 3], [5, 5, 5]]) {
      const er = deltaEOK(srgbToOklab(quantizeSrgb(s, br, bg, bb, 'error-weighted')), ideal);
      const rr = deltaEOK(srgbToOklab(quantizeSrgb(s, br, bg, bb, 'round')), ideal);
      assert.ok(er <= rr + 1e-9, `error-weighted ${er} worse than round ${rr}`);
      if (er < rr - 1e-9) improved++;
    }
  }
  assert.ok(improved > 0, 'error-weighted never beat round — the search is not doing anything');
});

test('grid size reports the expressible colour count', () => {
  assert.equal(gridSize(8, 8, 8), 16777216);
  assert.equal(gridSize(5, 5, 5), 32768);
  assert.equal(gridSize(1, 1, 1), 8);
  assert.equal(gridSize(4, 2, 3), 16 * 4 * 8);
});
