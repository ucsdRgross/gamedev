import test from 'node:test';
import assert from 'node:assert/strict';
import { PRESETS, PRESET_BY_ID, presetParams } from '../src/core/presets.js';
import { REFERENCE_PALETTES, REFERENCE_BY_ID, fitScore, rankReferences } from '../src/core/reference.js';
import { PARAMS } from '../src/core/params.js';
import { generatePalette, paletteHexes, paletteViolations } from '../src/core/generate.js';
import { isOnGrid } from '../src/core/quantize.js';

test('the plan\'s preset counts are present', () => {
  const emulation = PRESETS.filter((p) => p.group === 'emulation');
  const mood = PRESETS.filter((p) => p.group === 'mood');
  assert.equal(emulation.length, 8, 'expected 8 emulation-flavoured presets');
  assert.equal(mood.length, 12, 'expected 12 mood presets');
  const ids = PRESETS.map((p) => p.id);
  assert.equal(new Set(ids).size, ids.length, 'preset ids must be unique');
  for (const p of PRESETS) {
    assert.ok(p.name && p.doc && p.doc.length > 20, `${p.id} needs a real doc string`);
  }
});

test('every preset resolves to a complete, in-range parameter set', () => {
  for (const preset of PRESETS) {
    const params = presetParams(preset.id);
    for (const spec of PARAMS) {
      const v = params[spec.name];
      assert.ok(v !== undefined, `${preset.id} is missing ${spec.name}`);
      if (spec.type === 'float' || spec.type === 'int') {
        assert.ok(v >= spec.min && v <= spec.max, `${preset.id}.${spec.name} = ${v} out of range`);
      } else if (spec.type === 'enum') {
        assert.ok(spec.options.includes(v), `${preset.id}.${spec.name} = ${v} not a valid option`);
      }
    }
    // Every key a preset declares must be a real parameter, or it is silently ignored.
    for (const key of Object.keys(preset.params)) {
      assert.ok(PARAMS.some((s) => s.name === key), `${preset.id} sets unknown parameter ${key}`);
    }
  }
  assert.throws(() => presetParams('nope'), /unknown preset/);
});

test('every preset generates a clean palette', () => {
  for (const preset of PRESETS) {
    const params = presetParams(preset.id);
    const palette = generatePalette(params);
    assert.equal(palette.entries.length, params.color_count, preset.id);
    assert.equal(new Set(paletteHexes(palette)).size, params.color_count, `${preset.id} has duplicates`);
    assert.deepEqual(paletteViolations(palette), [], `${preset.id} left constraint violations`);
    assert.deepEqual(palette.warnings, [], `${preset.id}: ${palette.warnings.join('; ')}`);
  }
});

test('emulation presets honour their declared bit depths', () => {
  for (const preset of PRESETS.filter((p) => p.group === 'emulation')) {
    const params = presetParams(preset.id);
    const palette = generatePalette(params);
    for (const e of palette.entries) {
      assert.ok(
        isOnGrid(e.rgb8, params.bits_r, params.bits_g, params.bits_b),
        `${preset.id}: ${e.id} ${e.hex} is off the ${params.bits_r}/${params.bits_g}/${params.bits_b} grid`,
      );
    }
  }
});

test('presets are visibly different from each other', () => {
  const seen = new Map();
  for (const preset of PRESETS) {
    const key = paletteHexes(generatePalette(presetParams(preset.id))).join(',');
    assert.ok(!seen.has(key), `${preset.id} produces the same palette as ${seen.get(key)}`);
    seen.set(key, preset.id);
  }
});

test('monochrome preset really is monochrome and gameboy really is four greens', () => {
  const mono = generatePalette(presetParams('monochrome-ink'));
  for (const e of mono.entries) assert.ok(e.actual.C < 0.06, `${e.id} chroma ${e.actual.C}`);
  const gb = generatePalette(presetParams('gameboy'));
  assert.equal(gb.entries.length, 4);
  for (const e of gb.entries) {
    if (e.actual.C < 0.02) continue;
    assert.ok(e.actual.h > 70 && e.actual.h < 180, `${e.id} hue ${e.actual.h} is not green`);
  }
});

test('reference palettes are well-formed and complete', () => {
  assert.equal(REFERENCE_PALETTES.length, 11);
  const ids = REFERENCE_PALETTES.map((r) => r.id);
  assert.equal(new Set(ids).size, ids.length);
  for (const ref of REFERENCE_PALETTES) {
    assert.ok(ref.name && ref.author, `${ref.id} needs a name and author`);
    assert.ok(ref.colors.length >= 4, `${ref.id} has too few colours`);
    for (const c of ref.colors) assert.match(c, /^#[0-9A-F]{6}$/, `${ref.id}: ${c}`);
    assert.equal(new Set(ref.colors).size, ref.colors.length, `${ref.id} has duplicate colours`);
  }
  assert.equal(REFERENCE_BY_ID.get('pico8').colors.length, 16);
  assert.equal(REFERENCE_BY_ID.get('gameboy').colors.length, 4);
  assert.equal(REFERENCE_BY_ID.get('resurrect64').colors.length, 64);
  assert.equal(REFERENCE_BY_ID.get('vinik24').colors.length, 24);
  assert.equal(REFERENCE_BY_ID.get('apollo').colors.length, 46);
});

test('a reference scores zero against itself and worse against others', () => {
  for (const ref of REFERENCE_PALETTES) {
    const self = fitScore(ref.colors, ref.id);
    assert.ok(self.score < 1e-9, `${ref.id} should match itself exactly, got ${self.score}`);
  }
  const cross = fitScore(REFERENCE_BY_ID.get('gameboy').colors, 'pico8');
  assert.ok(cross.score > 10, `four greens should be a poor fit for PICO-8, got ${cross.score}`);
  assert.throws(() => fitScore(['#000000'], 'nope'), /unknown reference/);
});

test('ranking orders references by fit and the gameboy preset ranks its namesake highly', () => {
  const ranked = rankReferences(paletteHexes(generatePalette(presetParams('gameboy'))));
  assert.equal(ranked.length, 11);
  for (let i = 1; i < ranked.length; i++) assert.ok(ranked[i].score >= ranked[i - 1].score);
  assert.equal(ranked[0].id, 'gameboy', `closest reference was ${ranked[0].id}`);
});
