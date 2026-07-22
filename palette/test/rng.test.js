import test from 'node:test';
import assert from 'node:assert/strict';
import { makeRng, rngRange, rngInt, rngPick } from '../src/core/rng.js';

test('same seed produces the same stream', () => {
  const a = makeRng(4242);
  const b = makeRng(4242);
  for (let i = 0; i < 500; i++) assert.equal(a(), b());
});

test('different seeds diverge immediately', () => {
  const a = makeRng(1);
  const b = makeRng(2);
  let same = 0;
  for (let i = 0; i < 100; i++) if (a() === b()) same++;
  assert.equal(same, 0);
});

test('output stays in [0,1) and is roughly uniform', () => {
  const rng = makeRng(7);
  const bins = new Array(10).fill(0);
  const n = 100000;
  for (let i = 0; i < n; i++) {
    const v = rng();
    assert.ok(v >= 0 && v < 1, `out of range: ${v}`);
    bins[Math.floor(v * 10)]++;
  }
  for (const b of bins) {
    assert.ok(Math.abs(b - n / 10) < n / 100, `bin skew: ${b} vs ${n / 10}`);
  }
});

test('seed 0 still produces a live stream', () => {
  const rng = makeRng(0);
  const seen = new Set();
  for (let i = 0; i < 100; i++) seen.add(rng());
  assert.ok(seen.size > 90, 'seed 0 degenerated');
});

test('range helpers respect their bounds', () => {
  const rng = makeRng(11);
  for (let i = 0; i < 1000; i++) {
    const v = rngRange(rng, -3, 5);
    assert.ok(v >= -3 && v < 5);
    const n = rngInt(rng, 2, 4);
    assert.ok(n >= 2 && n <= 4 && Number.isInteger(n));
    assert.ok(['a', 'b', 'c'].includes(rngPick(rng, ['a', 'b', 'c'])));
  }
});
