// The Randomize button (src/ui/randomize.js).
//
// The property that matters — and that the repo owner was bitten by — is that Randomize
// rerolls the palette but leaves the reference-recolouring settings (dither, downscale,
// remap mode, …) exactly where they were. Asserted directly, and by group so a recolour
// parameter added later cannot silently start being randomized.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RANDOMIZE_SKIP, isRandomizable, randomizeParams } from '../src/ui/randomize.js';
import { PARAMS, defaultParams } from '../src/core/params.js';
import { makeRng } from '../src/core/rng.js';

test('Randomize never touches any reference-recolouring parameter', () => {
  const base = defaultParams();
  const recolor = PARAMS.filter((p) => p.group === 'recolor').map((p) => p.name);
  assert.ok(recolor.length >= 10, 'the recolour group should exist');

  // Many rerolls, since a single one could leave a value unchanged by luck.
  for (let i = 0; i < 50; i++) {
    const out = randomizeParams(base, makeRng(i + 1));
    for (const name of recolor) {
      assert.equal(out[name], base[name], `Randomize changed recolour param ${name}`);
    }
  }
});

test('the recolour group is excluded by group, not an explicit name list', () => {
  // Guards the future: a new recolour parameter must be excluded automatically.
  for (const spec of PARAMS) {
    if (spec.group === 'recolor') assert.equal(isRandomizable(spec), false, `${spec.name} should be excluded`);
  }
});

test('structure, hardware and quality parameters are still left alone', () => {
  const base = defaultParams();
  const out = randomizeParams(base, makeRng(7));
  for (const name of RANDOMIZE_SKIP) assert.equal(out[name], base[name], `${name} should not be randomized`);
});

test('Randomize does reroll the palette look and the seed', () => {
  const base = defaultParams();
  const out = randomizeParams(base, makeRng(123));
  const changed = PARAMS.filter((p) => isRandomizable(p) && out[p.name] !== base[p.name]);
  assert.ok(changed.length > 5, 'most look parameters should change');
  assert.notEqual(out.seed, base.seed, 'the seed should be rerolled');
});

test('randomize is deterministic for a fixed rng seed', () => {
  const base = defaultParams();
  assert.deepEqual(randomizeParams(base, makeRng(42)), randomizeParams(base, makeRng(42)));
});

test('every randomized value is valid for its spec', () => {
  const out = randomizeParams(defaultParams(), makeRng(9));
  for (const spec of PARAMS) {
    const v = out[spec.name];
    if (spec.type === 'enum') assert.ok(spec.options.includes(v), `${spec.name} = ${v}`);
    else if (spec.type === 'bool') assert.equal(typeof v, 'boolean');
    else assert.ok(v >= spec.min && v <= spec.max, `${spec.name} = ${v} out of [${spec.min}, ${spec.max}]`);
  }
});
