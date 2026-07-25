import test from 'node:test';
import assert from 'node:assert/strict';
import { PARAM_BY_NAME, defaultParams } from '../src/core/params.js';
import {
  sweepValues, valueLabel, paramSweep, sweepPalettes, sizeSweep, SIZE_SWEEP,
} from '../src/core/preview.js';

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

test('values are labelled at a sensible precision', () => {
  assert.equal(valueLabel(PARAM_BY_NAME.get('color_count'), 32), '32');
  assert.equal(valueLabel(PARAM_BY_NAME.get('hue_scheme'), 'triadic'), 'triadic');
  assert.equal(valueLabel(PARAM_BY_NAME.get('neutral_split'), true), 'on');
  assert.equal(valueLabel(PARAM_BY_NAME.get('chroma_base'), 0.145), '0.145');
  assert.equal(valueLabel(PARAM_BY_NAME.get('bg_hue_shift'), 0.3), '0.30');
});
