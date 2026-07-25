// Arrangements are a *view* of the palette, so the property that matters is conservation:
// whichever way the swatches are grouped, every colour is still on screen exactly once.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { arrangeEntries, ARRANGEMENTS, ARRANGEMENT_IDS } from '../src/core/arrange.js';
import { generatePalette } from '../src/core/generate.js';
import { hueName } from '../src/core/describe.js';
import { PRESETS } from '../src/core/presets.js';

const ids = (groups) => groups.flatMap((g) => g.entries.map((e) => e.id));

test('every arrangement has an id, a label and a hint, and the ids are unique', () => {
  assert.equal(ARRANGEMENTS.length, ARRANGEMENT_IDS.length);
  assert.equal(new Set(ARRANGEMENT_IDS).size, ARRANGEMENT_IDS.length);
  for (const [id, label, hint] of ARRANGEMENTS) {
    assert.ok(id && label && hint, `${id} is fully described`);
  }
  assert.equal(ARRANGEMENT_IDS[0], 'slot', 'the generator order is the default');
});

test('every mode shows every colour exactly once, at every palette size', () => {
  for (const K of [4, 8, 16, 32, 64]) {
    const palette = generatePalette({ color_count: K });
    const expected = palette.entries.map((e) => e.id).sort();
    for (const mode of ARRANGEMENT_IDS) {
      const seen = ids(arrangeEntries(palette, mode));
      assert.equal(new Set(seen).size, seen.length, `${mode} at K=${K} shows no colour twice`);
      assert.deepEqual(seen.sort(), expected, `${mode} at K=${K} shows every colour`);
    }
  }
});

test('every mode holds up across every preset', () => {
  for (const preset of PRESETS) {
    const palette = generatePalette(preset.params);
    const expected = palette.entries.map((e) => e.id).sort();
    for (const mode of ARRANGEMENT_IDS) {
      assert.deepEqual(ids(arrangeEntries(palette, mode)).sort(), expected, `${preset.id}/${mode}`);
    }
    for (const mode of ARRANGEMENT_IDS) {
      for (const g of arrangeEntries(palette, mode)) {
        assert.ok(g.entries.length > 0, `${preset.id}/${mode}: ${g.key} is not an empty group`);
        assert.ok(typeof g.title === 'string', `${preset.id}/${mode}: ${g.key} has a title`);
      }
    }
  }
});

test('an unknown mode falls back to generator order rather than dropping colours', () => {
  const palette = generatePalette({ color_count: 24 });
  const groups = arrangeEntries(palette, 'nonsense');
  assert.equal(groups.length, 1);
  assert.deepEqual(groups[0].entries.map((e) => e.id), palette.entries.map((e) => e.id));
});

test('lightness mode runs darkest to lightest', () => {
  const palette = generatePalette({ color_count: 32 });
  const [group] = arrangeEntries(palette, 'lightness');
  assert.equal(group.title, '', 'a flat run draws no heading');
  for (let i = 1; i < group.entries.length; i++) {
    assert.ok(group.entries[i].actual.L >= group.entries[i - 1].actual.L);
  }
});

test('ramps mode gives every ramp its own titled row, in shading order', () => {
  const palette = generatePalette({ color_count: 32 });
  const groups = arrangeEntries(palette, 'ramps');
  assert.ok(groups.length > 1, 'a 32-colour palette has several ramps');
  const named = groups.filter((g) => /^(Foreground|Background) /.test(g.title));
  assert.ok(named.length >= 2, 'hue ramps are named by layer and hue');
  for (const g of groups) {
    for (let i = 1; i < g.entries.length; i++) {
      assert.ok(g.entries[i].step >= g.entries[i - 1].step, `${g.key} runs in step order`);
    }
  }
  // The anchors are not part of any hue ramp and must still have somewhere to live.
  const anchors = groups.find((g) => g.title === 'Anchors');
  assert.ok(anchors && anchors.entries.length === 2);
});

test('hue mode groups by colour family with the near-greys pulled out first', () => {
  const palette = generatePalette({ color_count: 48 });
  const groups = arrangeEntries(palette, 'hue');
  assert.ok(groups.length > 1);
  assert.match(groups[0].title, /^Neutral · \d+$/, 'the near-greys lead, not scattered by hue');
  for (const e of groups[0].entries) assert.ok(e.actual.C < 0.02);
  // Each remaining group is one colour family, and the families run around the wheel.
  for (const g of groups.slice(1)) {
    const names = new Set(g.entries.map((e) => hueName(e.actual.h)));
    assert.equal(names.size, 1, `${g.key} is a single family`);
    assert.match(g.title, /^[A-Z].* · \d+$/, `${g.key} is titled and counted`);
  }
  const order = groups.slice(1).map((g) => g.entries[0].actual.h);
  for (let i = 1; i < order.length; i++) {
    assert.ok(order[i] > order[i - 1], 'families run around the wheel, not in slot order');
  }

  // A palette asked for no chroma at all still keeps a little (repair pushes near-duplicates
  // apart, and the hue shift tints the ends), so the check is that it reads as grey — not that
  // the chromatic groups vanish entirely.
  const grey = generatePalette({
    color_count: 16, chroma_base: 0, chroma_cap: 0.05, accent_count: 0, neutral_chroma: 0,
    earthiness: 0, chroma_variance_per_hue: 0,
  });
  const greyGroups = arrangeEntries(grey, 'hue');
  assert.ok(greyGroups[0].entries.length >= grey.entries.length * 0.8,
    'a greyscale palette lands almost entirely in Neutral');
});
