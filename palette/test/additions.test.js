import test from 'node:test';
import assert from 'node:assert/strict';
import { suggestAdditions, addColorSlot, SUGGEST_OPTIONS } from '../src/core/additions.js';
import { buildReach, BANDING_DE } from '../src/core/layout/reach.js';
import { generatePalette, paletteHexes } from '../src/core/generate.js';
import { defaultParams, PARAM_BY_NAME } from '../src/core/params.js';
import { presetParams } from '../src/core/presets.js';
import { hexToRgb8 } from '../src/core/oklch.js';

test('suggestions are ranked by the coverage the palette would actually have', () => {
  const palette = generatePalette({ ...defaultParams(), color_count: 16 });
  const suggestions = suggestAdditions(palette);
  assert.equal(suggestions.length, SUGGEST_OPTIONS.suggestions);
  for (let i = 1; i < suggestions.length; i++) {
    assert.ok(suggestions[i].after.mean >= suggestions[i - 1].after.mean, 'best first');
  }
  for (const s of suggestions) {
    assert.match(s.hex, /^#[0-9A-F]{6}$/);
    assert.equal(s.rgb8.length, 3);
    assert.ok(s.after.mean > 0 && s.after.mean < 100);
  }
});

test('a suggestion is a colour this palette could legally hold', () => {
  // 3/3/3-bit hardware: every legal colour is a multiple of 255/7 in each channel. A suggestion
  // that could not be produced by the generator would be advice the tool cannot take.
  const params = { ...defaultParams(), color_count: 16, bits_r: 3, bits_g: 3, bits_b: 3 };
  const palette = generatePalette(params);
  for (const s of suggestAdditions(palette)) {
    for (const channel of s.rgb8) {
      const level = (channel / 255) * 7;
      assert.ok(Math.abs(level - Math.round(level)) < 0.02, `${s.hex} is off the 3-bit grid`);
    }
  }
});

test('dropping the hull estimate does not change the advice', () => {
  // The palette pane runs a cheaper search than the picker. The saving comes entirely from the
  // hull statistic, which no suggestion is computed from — this pins that.
  const palette = generatePalette({ ...defaultParams(), color_count: 12 });
  const cheap = suggestAdditions(palette).map((s) => s.hex);
  const full = buildReach(palette, { suggestions: SUGGEST_OPTIONS.suggestions }).suggestions.map((s) => s.hex);
  assert.deepEqual(cheap, full);
});

test('adding a colour grows the palette by one and pins the colour into it', () => {
  const params = { ...defaultParams(), color_count: 24 };
  const before = generatePalette(params);
  const add = addColorSlot(params, '#7A9C3F');
  assert.ok(add, 'there is room at 24 colours');
  assert.equal(add.params.color_count, 25);
  const after = generatePalette(add.params, { locks: add.locks });
  assert.equal(after.entries.length, before.entries.length + 1);
  assert.ok(paletteHexes(after).includes('#7A9C3F'), 'the added colour must be in the palette');
  assert.equal(after.entries.find((e) => e.id === add.slotId).hex, '#7A9C3F');
  assert.equal(after.entries.find((e) => e.id === add.slotId).locked, true);
});

test('a lowercase hex is stored the way the rest of the app writes hexes', () => {
  const add = addColorSlot({ ...defaultParams(), color_count: 16 }, '#7a9c3f');
  assert.equal(add.locks[add.slotId], '#7A9C3F');
});

test('adding never disturbs a lock that was already there', () => {
  const params = { ...defaultParams(), color_count: 20 };
  const first = generatePalette(params).entries[5].id;
  const locks = { [first]: '#123456' };
  const add = addColorSlot(params, '#7A9C3F', { locks });
  assert.equal(add.locks[first], '#123456');
  assert.notEqual(add.slotId, first);
  const after = generatePalette(add.params, { locks: add.locks });
  assert.ok(paletteHexes(after).includes('#123456'));
  assert.ok(paletteHexes(after).includes('#7A9C3F'));
});

test('a full palette says so rather than replacing a colour', () => {
  const spec = PARAM_BY_NAME.get('color_count');
  assert.equal(addColorSlot({ ...defaultParams(), color_count: spec.max }, '#7A9C3F'), null);
});

test('the added colour lands where the palette was short, at every size', () => {
  for (const size of [4, 8, 16, 32]) {
    const params = { ...defaultParams(), color_count: size };
    const palette = generatePalette(params);
    const [best] = suggestAdditions(palette);
    if (!best) continue;
    const add = addColorSlot(params, best.hex);
    const after = generatePalette(add.params, { locks: add.locks });
    assert.ok(paletteHexes(after).includes(best.hex), `K=${size}`);
    // …and the palette really does reach further with it than without.
    const coverage = (p) => buildReach(p, { hullTrials: 0, suggestions: 0 }).stats.dithered.mean;
    assert.ok(coverage(after) <= coverage(palette) + BANDING_DE, `K=${size} coverage got worse`);
  }
});

test('every preset can be asked what it is missing without throwing', () => {
  for (const id of ['gameboy', 'nes', 'monochrome-ink', 'oklab-crayon']) {
    const palette = generatePalette(presetParams(id));
    for (const s of suggestAdditions(palette)) {
      assert.deepEqual(hexToRgb8(s.hex), s.rgb8, `${id}: ${s.hex}`);
    }
  }
});
