import test from 'node:test';
import assert from 'node:assert/strict';
import {
  PARAMS,
  PARAM_BY_NAME,
  PARAM_GROUPS,
  defaultParams,
  normalizeParams,
  coerceParam,
  paramToU16,
  u16ToParam,
  snapParams,
} from '../src/core/params.js';

test('schema is well-formed and covers the documented parameter set', () => {
  assert.ok(PARAMS.length >= 50, `expected ~50+ parameters, got ${PARAMS.length}`);
  const seen = new Set();
  for (const p of PARAMS) {
    assert.ok(p.name && !seen.has(p.name), `duplicate or missing name: ${p.name}`);
    seen.add(p.name);
    assert.ok(p.group, `${p.name} has no group`);
    assert.ok(p.doc && p.doc.length > 20, `${p.name} needs a real doc string`);
    if (p.type === 'float' || p.type === 'int') {
      assert.ok(p.max > p.min, `${p.name} has an empty range`);
      assert.ok(p.default >= p.min && p.default <= p.max, `${p.name} default out of range`);
      assert.ok(p.step > 0, `${p.name} needs a step`);
    } else if (p.type === 'enum') {
      assert.ok(p.options.length >= 2, `${p.name} needs options`);
      assert.ok(p.options.includes(p.default), `${p.name} default not in options`);
    } else {
      assert.equal(p.type, 'bool');
      assert.equal(typeof p.default, 'boolean');
    }
  }
});

test('every parameter named in the plan is present', () => {
  const required = [
    'color_count', 'hue_count', 'hue_scheme', 'root_hue', 'hue_span', 'hue_jitter',
    'perceptual_hue_spacing', 'fg_ramp_length', 'bg_ramp_length', 'neutral_count',
    'accent_count', 'tier_priority',
    'l_dark_anchor', 'l_light_anchor', 'l_mid_base', 'l_step', 'l_curve',
    'l_range_compress', 'l_variance_per_hue',
    'chroma_base', 'chroma_peak_l', 'chroma_curve_width', 'chroma_falloff_light',
    'chroma_falloff_dark', 'chroma_variance_per_hue', 'earthiness', 'chroma_cap',
    'highlight_hue_target', 'highlight_shift_strength', 'shadow_hue_target',
    'shadow_shift_strength', 'shift_model', 'shift_direction', 'global_temperature',
    'temperature_split',
    'bg_chroma_mult', 'bg_lightness_offset', 'bg_hue_shift', 'atmosphere_hue',
    'atmosphere_strength', 'fg_bg_separation_min',
    'neutral_temperature', 'neutral_chroma', 'neutral_split', 'neutral_l_spread',
    'accent_chroma_boost', 'accent_hue_mode', 'accent_l',
    'bits_r', 'bits_g', 'bits_b', 'quantize_mode', 'gamut_map_mode',
    'min_delta_e', 'min_anchor_contrast', 'dither_evenness', 'force_unique_hex',
    'seed',
  ];
  for (const name of required) assert.ok(PARAM_BY_NAME.has(name), `missing parameter ${name}`);
});

test('groups are stable and non-empty', () => {
  // `recolor` is last because field order is the seed payload's order and appending is the
  // only safe edit — see the header of params.js.
  assert.deepEqual(PARAM_GROUPS, [
    'structure', 'lightness', 'chroma', 'shift', 'background',
    'neutrals', 'accents', 'hardware', 'quality', 'meta', 'recolor',
  ]);
});

test('the recolour parameters are present and appended after the palette ones', () => {
  const names = PARAMS.map((p) => p.name);
  const required = [
    'recolor_mode', 'recolor_indexed_max', 'remap_match', 'remap_preserve_order',
    'remap_overflow', 'quant_dither', 'quant_dither_strength', 'quant_lightness_weight',
    'quant_downscale', 'gif_frame',
  ];
  for (const name of required) assert.ok(PARAM_BY_NAME.has(name), `missing parameter ${name}`);
  // Every one of them sits after `seed`, so old PAL1 seeds still decode (§6).
  const seedAt = names.indexOf('seed');
  for (const name of required) assert.ok(names.indexOf(name) > seedAt, `${name} must be appended, not inserted`);
});

test('defaults normalise to themselves', () => {
  assert.deepEqual(normalizeParams(defaultParams()), defaultParams());
  assert.deepEqual(normalizeParams({}), defaultParams());
});

test('coercion clamps out-of-range and rejects bad enums', () => {
  assert.equal(coerceParam(PARAM_BY_NAME.get('color_count'), 999), 64);
  assert.equal(coerceParam(PARAM_BY_NAME.get('color_count'), -5), 4);
  assert.equal(coerceParam(PARAM_BY_NAME.get('color_count'), 12.6), 13);
  assert.equal(coerceParam(PARAM_BY_NAME.get('color_count'), NaN), 32);
  assert.equal(coerceParam(PARAM_BY_NAME.get('hue_scheme'), 'nonsense'), 'analogous');
  assert.equal(coerceParam(PARAM_BY_NAME.get('force_unique_hex'), 0), false);
});

test('u16 quantisation round-trips within one step for every parameter', () => {
  for (const p of PARAMS) {
    const samples =
      p.type === 'enum' ? p.options
      : p.type === 'bool' ? [true, false]
      : Array.from({ length: 21 }, (_, k) => p.min + ((p.max - p.min) * k) / 20);
    for (const v of samples) {
      const back = u16ToParam(p, paramToU16(p, v));
      if (p.type === 'enum' || p.type === 'bool') {
        assert.equal(back, v, `${p.name} enum/bool round-trip`);
      } else if (p.type === 'int') {
        assert.equal(back, Math.round(v), `${p.name} int round-trip of ${v}`);
      } else {
        assert.ok(
          Math.abs(back - v) <= (p.max - p.min) / 65535,
          `${p.name} float round-trip of ${v} gave ${back}`,
        );
      }
    }
  }
});

test('snapping to the seed grid is idempotent and stays in range', () => {
  const snapped = snapParams(defaultParams());
  assert.deepEqual(snapParams(snapped), snapped);
  for (const p of PARAMS) {
    if (p.type === 'float') {
      assert.ok(Math.abs(snapped[p.name] - p.default) <= (p.max - p.min) / 65535, p.name);
    } else {
      assert.equal(snapped[p.name], p.default, p.name);
    }
  }
  assert.deepEqual(snapParams({}), snapped);
});

test('u16 payload values stay inside 16 bits', () => {
  for (const p of PARAMS) {
    const v = p.type === 'enum' ? p.options[p.options.length - 1] : p.type === 'bool' ? true : p.max;
    const u = paramToU16(p, v);
    assert.ok(Number.isInteger(u) && u >= 0 && u <= 65535, `${p.name} produced ${u}`);
  }
});
