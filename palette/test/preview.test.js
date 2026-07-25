import test from 'node:test';
import assert from 'node:assert/strict';
import { PARAM_BY_NAME, defaultParams } from '../src/core/params.js';
import {
  sweepValues, valueLabel, paramSweep, sweepPalettes, sizeSweep, SIZE_SWEEP,
  paramEffect, findClamp, decidesColor, FRAMING_PARAMS,
} from '../src/core/preview.js';
import { PARAMS } from '../src/core/params.js';
import { generatePalette, paletteHexes } from '../src/core/generate.js';

test('a float sweep spans the whole range, in order', () => {
  const spec = PARAM_BY_NAME.get('chroma_base');
  const values = sweepValues(spec, 5);
  assert.equal(values.length, 5);
  assert.equal(values[0], spec.min);
  assert.equal(values[values.length - 1], spec.max);
  for (let i = 1; i < values.length; i++) assert.ok(values[i] > values[i - 1], 'sweep must ascend');
});

test('an int sweep rounds and deduplicates rather than repeating a value', () => {
  const spec = PARAM_BY_NAME.get('bg_ramp_length'); // range 1..3, so 5 samples collapse
  const values = sweepValues(spec, 5);
  assert.deepEqual(values, [1, 2, 3]);
  assert.equal(new Set(values).size, values.length);
});

test('enum and bool sweeps are the options themselves', () => {
  const scheme = PARAM_BY_NAME.get('hue_scheme');
  assert.deepEqual(sweepValues(scheme, 5), scheme.options);
  assert.deepEqual(sweepValues(PARAM_BY_NAME.get('neutral_split'), 5), [false, true]);
});

test('a sweep changes exactly one field and marks where you are', () => {
  const params = defaultParams();
  const steps = paramSweep(params, 'l_mid_base', 5);
  assert.equal(steps.length, 5);
  for (const step of steps) {
    for (const [name, value] of Object.entries(params)) {
      if (name === 'l_mid_base') continue;
      assert.equal(step.params[name], value, `${name} must be held while sweeping l_mid_base`);
    }
  }
  assert.equal(steps.filter((s) => s.current).length, 1, 'exactly one step is the current one');
  // The default (0.56) is nearer the middle of 0.3..0.92 than either end.
  const currentAt = steps.findIndex((s) => s.current);
  assert.ok(currentAt > 0 && currentAt < steps.length - 1, `expected an interior step, got ${currentAt}`);
});

test('an unknown parameter sweeps to nothing rather than throwing', () => {
  assert.deepEqual(paramSweep(defaultParams(), 'not_a_parameter'), []);
});

test('every step of a sweep generates a real palette', () => {
  const steps = sweepPalettes(defaultParams(), 'chroma_base', 5);
  assert.equal(steps.length, 5);
  for (const step of steps) {
    assert.equal(step.palette.entries.length, 32);
    assert.equal(step.hexes.length, 32);
    for (const hex of step.hexes) assert.match(hex, /^#[0-9A-F]{6}$/);
  }
  // Sweeping saturation must actually change the colours, or the preview is a lie.
  assert.notDeepEqual(steps[0].hexes, steps[steps.length - 1].hexes);
});

test('locks are honoured inside a preview, so it shows what you would get', () => {
  const params = defaultParams();
  const locks = { fg_h0_1: '#123456' };
  for (const step of sweepPalettes(params, 'chroma_base', 3, { locks })) {
    const entry = step.palette.entries.find((e) => e.id === 'fg_h0_1');
    assert.equal(entry.hex, '#123456');
  }
});

test('the size sweep offers the sizes palettes are actually made at', () => {
  const steps = sizeSweep({ ...defaultParams(), color_count: 32 });
  assert.deepEqual(steps.map((s) => s.value), SIZE_SWEEP);
  for (const step of steps) assert.equal(step.palette.entries.length, step.value);
  assert.equal(steps.filter((s) => s.current).length, 1);
  assert.equal(steps.find((s) => s.current).value, 32);
});

// ---- Dead controls (U7.3 — item 35) ---------------------------------------

test('a parameter that moves the palette is not called clamped', () => {
  const params = defaultParams();
  for (const name of ['chroma_base', 'l_step', 'root_hue', 'color_count', 'hue_scheme', 'seed']) {
    const effect = paramEffect(params, name);
    assert.ok(effect.applies, `${name} decides colour`);
    assert.ok(effect.moves, `${name} should change the palette`);
    assert.ok(effect.up || effect.down, name);
  }
});

test('a control whose effect is being swallowed is called clamped, and only then', () => {
  const params = defaultParams();
  // `chroma_cap` is a ceiling well above where `chroma_base` sits, so it decides nothing.
  const capped = paramEffect(params, 'chroma_cap');
  assert.equal(capped.moves, false);
  // Raise the master saturation into it and the same control comes back to life.
  const biting = paramEffect({ ...params, chroma_base: 0.37 }, 'chroma_cap');
  assert.equal(biting.moves, true);
});

test('the end of a range is reported as its own thing, not as a hidden constraint', () => {
  const spec = PARAM_BY_NAME.get('chroma_base');
  const atFloor = paramEffect({ ...defaultParams(), chroma_base: spec.min }, 'chroma_base');
  assert.equal(atFloor.atMin, true);
  assert.equal(atFloor.atMax, false);
  assert.equal(atFloor.down, false, 'there is nowhere below the minimum to go');
});

test('the recolour parameters are exempt: they decide no palette colour by design', () => {
  const params = defaultParams();
  const recolour = PARAMS.filter((p) => p.group === 'recolor');
  assert.ok(recolour.length >= 10, 'the recolour block should be substantial');
  for (const spec of recolour) {
    assert.equal(decidesColor(spec.name), false, spec.name);
    // …and the claim is true: changing one really does leave every colour alone.
    const other = spec.type === 'enum' ? spec.options.find((o) => o !== params[spec.name])
      : spec.type === 'bool' ? !params[spec.name] : spec.max;
    assert.deepEqual(
      paletteHexes(generatePalette({ ...params, [spec.name]: other })),
      paletteHexes(generatePalette(params)),
      `${spec.name} must not move a palette colour`,
    );
    // The check reports them as live rather than as clamped, so the panel says nothing.
    assert.equal(paramEffect(params, spec.name).applies, false, spec.name);
  }
});

test('findClamp names a culprit only when changing it revives the control', () => {
  const params = defaultParams();
  const found = findClamp(params, 'chroma_cap');
  assert.ok(found, 'something must be holding the chroma ceiling down');
  assert.deepEqual(found.set.map((s) => s.name), ['chroma_base']);
  // The claim is verifiable: with the culprit at that value, the control moves again.
  const released = { ...params, [found.set[0].name]: found.set[0].value };
  assert.equal(paramEffect(released, 'chroma_cap').moves, true);
});

test('findClamp finds a pair when one knob alone is not enough', () => {
  // A pinned hue does nothing until the scheme is `custom` AND a pin count has been set —
  // naming either one on its own would send somebody to a knob that changes nothing.
  const params = defaultParams();
  assert.equal(paramEffect(params, 'custom_hue_1').moves, false);
  const found = findClamp(params, 'custom_hue_1');
  assert.ok(found, 'the pair should be found');
  assert.deepEqual(found.set.map((s) => s.name).sort(), ['custom_hue_count', 'hue_scheme']);
  const released = { ...params };
  for (const s of found.set) released[s.name] = s.value;
  assert.equal(paramEffect(released, 'custom_hue_1').moves, true);
});

test('findClamp reaches outside the parameter group', () => {
  // `dither_evenness` (quality) blends the lightness curve toward linear, so with `l_curve`
  // already linear it does nothing — a culprit two panels away from the control it holds.
  const params = defaultParams();
  assert.equal(paramEffect(params, 'dither_evenness').moves, false);
  const found = findClamp(params, 'dither_evenness');
  assert.deepEqual(found?.set.map((s) => s.name), ['l_curve']);
});

test('every framing parameter is a real parameter that decides colour', () => {
  for (const name of FRAMING_PARAMS) {
    assert.ok(PARAM_BY_NAME.has(name), `${name} is not in the schema`);
    assert.equal(decidesColor(name), true, name);
  }
});

test('values are labelled at a sensible precision', () => {
  assert.equal(valueLabel(PARAM_BY_NAME.get('color_count'), 32), '32');
  assert.equal(valueLabel(PARAM_BY_NAME.get('hue_scheme'), 'triadic'), 'triadic');
  assert.equal(valueLabel(PARAM_BY_NAME.get('neutral_split'), true), 'on');
  assert.equal(valueLabel(PARAM_BY_NAME.get('chroma_base'), 0.145), '0.145');
  assert.equal(valueLabel(PARAM_BY_NAME.get('bg_hue_shift'), 0.3), '0.30');
});
