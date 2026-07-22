import test from 'node:test';
import assert from 'node:assert/strict';
import { repairPalette, residualViolations, LAYER_PRIORITY, FG_BG_SEP_SCALE } from '../src/core/repair.js';
import { makeRealize } from '../src/core/generate.js';
import { defaultParams } from '../src/core/params.js';
import { roleName, assignSemanticRoles, semanticsBySlot, SEMANTIC_TARGETS } from '../src/core/roles.js';
import { deltaEOK, contrastRatio } from '../src/core/oklch.js';

/** Build a repair-ready entry from an OKLCH triple. */
function entry(id, layer, oklch, params, extra = {}) {
  const realize = makeRealize(params);
  return {
    id, layer, hueIndex: 0, step: 0, steps: 1, lMin: 0.05, lMax: 0.95,
    fixed: false, ...realize(oklch), ...extra,
  };
}

test('near-duplicate colours are pushed apart', () => {
  const params = { ...defaultParams(), min_delta_e: 6 };
  const realize = makeRealize(params);
  const entries = [
    entry('fg_h0_0', 'fg', { L: 0.5, C: 0.12, h: 140 }, params),
    entry('bridge_0', 'bridge', { L: 0.505, C: 0.12, h: 140 }, params),
  ];
  assert.ok(deltaEOK(entries[0].lab, entries[1].lab) < 6, 'setup should start in violation');
  const { warnings } = repairPalette(entries, params, realize);
  assert.deepEqual(warnings, []);
  assert.ok(deltaEOK(entries[0].lab, entries[1].lab) >= 6);
});

test('the lower-priority slot is the one that moves', () => {
  const params = { ...defaultParams(), min_delta_e: 6 };
  const realize = makeRealize(params);
  const fg = entry('fg_h0_0', 'fg', { L: 0.5, C: 0.12, h: 140 }, params);
  const bg = entry('bg_h0_0', 'bg', { L: 0.505, C: 0.12, h: 140 }, params);
  const fgBefore = fg.hex;
  const bgBefore = bg.hex;
  repairPalette([fg, bg], { ...params, fg_bg_separation_min: 0 }, realize);
  assert.equal(fg.hex, fgBefore, 'foreground outranks background and should stay put');
  assert.notEqual(bg.hex, bgBefore);
  assert.ok(LAYER_PRIORITY.bg > LAYER_PRIORITY.fg);
});

test('fixed slots are never moved, and their neighbours move instead', () => {
  const params = { ...defaultParams(), min_delta_e: 8 };
  const realize = makeRealize(params);
  const locked = entry('bridge_0', 'bridge', { L: 0.5, C: 0.12, h: 140 }, params, { fixed: true });
  const free = entry('fg_h0_0', 'fg', { L: 0.51, C: 0.12, h: 140 }, params);
  const lockedBefore = locked.hex;
  repairPalette([locked, free], params, realize);
  assert.equal(locked.hex, lockedBefore, 'a pinned slot must never be relocated');
  assert.ok(deltaEOK(locked.lab, free.lab) >= 8);
});

test('two pinned slots in conflict are reported rather than silently moved', () => {
  const params = { ...defaultParams(), min_delta_e: 10, force_unique_hex: false };
  const realize = makeRealize(params);
  const a = entry('a', 'fg', { L: 0.5, C: 0.12, h: 140 }, params, { fixed: true });
  const b = entry('b', 'fg', { L: 0.505, C: 0.12, h: 140 }, params, { fixed: true });
  const before = [a.hex, b.hex];
  const { warnings } = repairPalette([a, b], params, realize);
  assert.deepEqual([a.hex, b.hex], before);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /still closer than the requested minimum/);
});

test('foreground/background threshold is stricter than the base minimum', () => {
  const params = { ...defaultParams(), min_delta_e: 2, fg_bg_separation_min: 0.5 };
  const realize = makeRealize(params);
  const entries = [
    entry('fg_h0_0', 'fg', { L: 0.5, C: 0.12, h: 140 }, params),
    entry('bg_h0_0', 'bg', { L: 0.52, C: 0.1, h: 145 }, params),
  ];
  repairPalette(entries, params, realize);
  assert.ok(
    deltaEOK(entries[0].lab, entries[1].lab) >= 0.5 * FG_BG_SEP_SCALE,
    'fg/bg pair should clear the separation floor, not just min_delta_e',
  );
});

test('anchor contrast is raised until it clears the floor', () => {
  const params = { ...defaultParams(), min_anchor_contrast: 12, min_delta_e: 0, force_unique_hex: false };
  const realize = makeRealize(params);
  const entries = [
    entry('universal_dark', 'anchor', { L: 0.4, C: 0.02, h: 280 }, params),
    entry('universal_light', 'anchor', { L: 0.6, C: 0.02, h: 90 }, params),
  ];
  const { warnings } = repairPalette(entries, params, realize);
  assert.deepEqual(warnings, []);
  assert.ok(contrastRatio(entries[0].rgb8, entries[1].rgb8) >= 12);
});

test('residualViolations reports pairs worst-first', () => {
  const params = { ...defaultParams(), min_delta_e: 20 };
  const entries = [
    entry('a', 'fg', { L: 0.5, C: 0.12, h: 140 }, params),
    entry('b', 'fg', { L: 0.52, C: 0.12, h: 140 }, params),
    entry('c', 'fg', { L: 0.62, C: 0.12, h: 140 }, params),
  ];
  const v = residualViolations(entries, params);
  assert.ok(v.length >= 2);
  for (let i = 1; i < v.length; i++) assert.ok(v[i].deltaE >= v[i - 1].deltaE);
});

test('role names describe the slot position', () => {
  assert.equal(roleName({ layer: 'anchor', kind: 'dark' }), 'universal_dark');
  assert.equal(roleName({ layer: 'anchor', kind: 'light' }), 'universal_light');
  assert.equal(roleName({ layer: 'fg', hueIndex: 2, step: 1, steps: 3 }), 'fg_h2_mid');
  assert.equal(roleName({ layer: 'fg', hueIndex: 0, step: 0, steps: 3 }), 'fg_h0_shadow');
  assert.equal(roleName({ layer: 'fg', hueIndex: 0, step: 2, steps: 3 }), 'fg_h0_light');
  assert.equal(roleName({ layer: 'fg', hueIndex: 1, step: 0, steps: 5 }), 'fg_h1_deep');
  assert.equal(roleName({ layer: 'fg', hueIndex: 1, step: 4, steps: 5 }), 'fg_h1_bright');
  assert.equal(roleName({ layer: 'bg', hueIndex: 3, step: 1, steps: 2 }), 'bg_h3_mid');
  assert.equal(roleName({ layer: 'neutral', step: 2 }), 'neutral_2');
  assert.equal(roleName({ layer: 'neutral-warm', step: 0 }), 'neutral_warm_0');
  assert.equal(roleName({ layer: 'accent', step: 1 }), 'accent_1');
  assert.equal(roleName({ layer: 'bridge', hueIndex: 4 }), 'bridge_4');
});

test('semantic assignment covers every role and inverts cleanly', () => {
  const params = defaultParams();
  const entries = [
    entry('a', 'fg', { L: 0.45, C: 0.14, h: 140 }, params),
    entry('b', 'fg', { L: 0.72, C: 0.08, h: 45 }, params),
    entry('c', 'neutral', { L: 0.5, C: 0.01, h: 230 }, params),
    entry('d', 'bg', { L: 0.75, C: 0.05, h: 240 }, params),
  ];
  const assigned = assignSemanticRoles(entries);
  assert.equal(Object.keys(assigned).length, SEMANTIC_TARGETS.length);
  assert.equal(assigned.foliage, 'a');
  assert.equal(assigned.stone, 'c');
  assert.equal(assigned.sky, 'd');
  const inverted = semanticsBySlot(assigned);
  assert.ok(inverted.get('a').includes('foliage'));
});
