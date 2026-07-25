// The Randomize button (src/ui/randomize.js).
//
// The property that matters — and that the repo owner was bitten by — is that Randomize
// rerolls the palette but leaves the reference-recolouring settings (dither, downscale,
// remap mode, …) exactly where they were. Asserted directly, and by group so a recolour
// parameter added later cannot silently start being randomized.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  RANDOMIZE_SKIP, VARY_HOLD, VARY_STRENGTHS,
  isRandomizable, isVariable, randomizeParams, varyParams, paramDistance,
} from '../src/ui/randomize.js';
import { PARAMS, PARAM_BY_NAME, ANGULAR_PARAMS, defaultParams } from '../src/core/params.js';
import { makeRng } from '../src/core/rng.js';
import { presetParams } from '../src/core/presets.js';

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

// --- Vary (UX_PLAN U3.1 — item 5) -----------------------------------------
// Vary is what Randomize should be once you have a palette you half-like: a variation, not a
// replacement. The properties below are exactly what "variation" has to mean.

test('a variation stays near the palette it came from, and a stronger one goes further', () => {
  const base = presetParams('autumn-forest');
  const distanceAt = (strength) => {
    let total = 0;
    for (let i = 0; i < 40; i++) total += paramDistance(base, varyParams(base, makeRng(i + 1), { strength }));
    return total / 40;
  };
  const subtle = distanceAt('subtle');
  const moderate = distanceAt('moderate');
  const wild = distanceAt('wild');
  assert.ok(subtle < moderate, `subtle ${subtle} should be nearer than moderate ${moderate}`);
  assert.ok(moderate < wild, `moderate ${moderate} should be nearer than wild ${wild}`);
  // And all of them nearer than a full reroll, which is the whole point.
  let random = 0;
  for (let i = 0; i < 40; i++) random += paramDistance(base, randomizeParams(base, makeRng(i + 1)));
  assert.ok(wild < random / 40, `even a wild variation (${wild}) should beat a reroll (${random / 40})`);
});

test('a variation holds the decisions you have already made', () => {
  const base = presetParams('snes');
  for (let i = 0; i < 30; i++) {
    const out = varyParams(base, makeRng(i + 1), { strength: 'wild' });
    for (const name of VARY_HOLD) assert.equal(out[name], base[name], `${name} must be held`);
    for (const name of RANDOMIZE_SKIP) assert.equal(out[name], base[name], `${name} must be held`);
    for (const spec of PARAMS.filter((p) => p.group === 'recolor')) {
      assert.equal(out[spec.name], base[spec.name], `${spec.name} must be held`);
    }
  }
});

test('includeStructure lets the scheme and family count move too', () => {
  const base = defaultParams();
  let moved = 0;
  for (let i = 0; i < 40; i++) {
    const out = varyParams(base, makeRng(i + 1), { strength: 'wild', includeStructure: true });
    if (VARY_HOLD.has('hue_scheme') && out.hue_scheme !== base.hue_scheme) moved++;
  }
  assert.ok(moved > 0, 'with includeStructure, the hue scheme should sometimes change');
});

test('a fixed list is honoured exactly', () => {
  const base = defaultParams();
  const fixed = ['chroma_base', 'l_mid_base', 'seed'];
  for (let i = 0; i < 20; i++) {
    const out = varyParams(base, makeRng(i + 1), { strength: 'wild', fixed });
    for (const name of fixed) assert.equal(out[name], base[name], `${name} was pinned`);
  }
});

test('no single variation step can jump a parameter across its whole range', () => {
  // The bug this pins: `l_variance_per_hue` and `chroma_variance_per_hue` end in "_hue" but
  // are not angles. Wrapping them at 360 turned a small negative step into 359.98, which then
  // clamped to the parameter's maximum — so a *gentle* variation slammed the per-hue variance
  // to its ceiling. Only the true hue angles may wrap.
  const base = defaultParams();
  const width = VARY_STRENGTHS.moderate;
  for (let i = 0; i < 200; i++) {
    const out = varyParams(base, makeRng(i + 1), { strength: 'moderate' });
    for (const spec of PARAMS) {
      if (spec.type === 'enum' || spec.type === 'bool' || spec.name === 'seed') continue;
      if (ANGULAR_PARAMS.has(spec.name)) continue; // these legitimately wrap
      const span = spec.max - spec.min;
      const moved = Math.abs(out[spec.name] - base[spec.name]);
      // The gaussian is bounded at ±3, plus a step of rounding slack for ints.
      const limit = 3 * width * span + Math.max(spec.step || 0, 1e-9);
      assert.ok(moved <= limit, `${spec.name} moved ${moved}, more than ${limit}`);
    }
  }
});

test('hue angles wrap, and only hue angles', () => {
  for (const name of ANGULAR_PARAMS) {
    const spec = PARAM_BY_NAME.get(name);
    assert.ok(spec, `${name} is not a parameter`);
    assert.equal(spec.min, 0, `${name} should be a full circle`);
    assert.equal(spec.max, 360, `${name} should be a full circle`);
  }
  // Named explicitly rather than by suffix, so these two stay out.
  assert.equal(ANGULAR_PARAMS.has('l_variance_per_hue'), false);
  assert.equal(ANGULAR_PARAMS.has('chroma_variance_per_hue'), false);
  assert.equal(ANGULAR_PARAMS.has('hue_span'), false, 'a span is a width, not a position');
});

test('vary is deterministic and always in range', () => {
  const base = presetParams('pastel-cozy');
  assert.deepEqual(varyParams(base, makeRng(5)), varyParams(base, makeRng(5)));
  for (const strength of Object.keys(VARY_STRENGTHS)) {
    const out = varyParams(base, makeRng(3), { strength });
    for (const spec of PARAMS) {
      const v = out[spec.name];
      if (spec.type === 'enum') assert.ok(spec.options.includes(v), `${spec.name} = ${v}`);
      else if (spec.type === 'bool') assert.equal(typeof v, 'boolean');
      else assert.ok(v >= spec.min && v <= spec.max, `${spec.name} = ${v} out of range at ${strength}`);
    }
  }
});

test('vary excludes exactly what randomize excludes, plus the held structure', () => {
  for (const spec of PARAMS) {
    if (!isRandomizable(spec)) assert.equal(isVariable(spec), false, `${spec.name}`);
    if (VARY_HOLD.has(spec.name)) {
      assert.equal(isVariable(spec), false, `${spec.name} is held by default`);
      assert.equal(isVariable(spec, { includeStructure: true }), true, `${spec.name} moves when asked`);
    }
  }
});
