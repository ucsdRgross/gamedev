// Keeping palettes: the auto-name that makes Keep a one-click button, and the autosave ring.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SAVE_NAME_RE, isSaveName, toSaveName, pushAutosave, AUTOSAVE_CAP } from '../src/core/library.js';
import { autoName } from '../src/core/describe.js';
import { generatePalette } from '../src/core/generate.js';
import { PRESETS, presetParams } from '../src/core/presets.js';

test('an auto-name is always a legal save name, for every preset and size', () => {
  for (const preset of PRESETS) {
    const params = presetParams(preset.id);
    const name = autoName(generatePalette(params), params);
    assert.ok(SAVE_NAME_RE.test(name), `${preset.id} produced "${name}"`);
  }
  for (const K of [4, 8, 16, 32, 48, 64]) {
    const params = { color_count: K };
    const name = autoName(generatePalette(params), params);
    assert.ok(SAVE_NAME_RE.test(name), `K=${K} produced "${name}"`);
    assert.ok(name.endsWith(String(K)) || K !== generatePalette(params).entries.length, name);
  }
});

test('an auto-name says the things you would use to pick it out of a list', () => {
  const name = (id) => { const p = presetParams(id); return autoName(generatePalette(p), p); };
  // A colourless palette is not named after a hue — "Grey azure 12" contradicts itself.
  assert.equal(name('monochrome-ink'), 'Grey 12');
  // Everything with colour in it is <word> <hue> <count>, and the hue is the one it is about.
  // Unremarkable saturation falls back to the key, which is the next most useful thing.
  assert.equal(name('underwater-cave'), 'Dusk teal 32');
  assert.equal(name('frozen-tundra'), 'Muted cyan 32');
  assert.equal(name('blood-moon'), 'Dusk red 24');
  assert.equal(name('sunset-desert'), 'Bright orange 32');
  assert.match(name('neon-cyberpunk'), /^(Rich|Vivid) \w+ \d+$/);
  // Names have to separate palettes, or the list they appear in is useless.
  const all = PRESETS.map((p) => name(p.id));
  assert.ok(new Set(all).size >= PRESETS.length - 4, `too many collisions: ${all.join(', ')}`);
});

test('an auto-name works without params, reading the hue off the colours', () => {
  const palette = generatePalette({ color_count: 24 });
  const name = autoName(palette);
  assert.ok(SAVE_NAME_RE.test(name), name);
  assert.ok(name.endsWith('24'), name);
});

test('a taken name gets a number rather than overwriting', () => {
  const params = { color_count: 32 };
  const palette = generatePalette(params);
  const first = autoName(palette, params);
  assert.equal(autoName(palette, params, { taken: [first] }), `${first} 2`);
  assert.equal(autoName(palette, params, { taken: [first, `${first} 2`] }), `${first} 3`);
  assert.ok(SAVE_NAME_RE.test(autoName(palette, params, { taken: [first, `${first} 2`] })));
});

test('save names are validated and coerced', () => {
  assert.ok(isSaveName('Muted teal 16'));
  assert.ok(isSaveName('a'));
  assert.equal(isSaveName(''), false);
  assert.equal(isSaveName('a/b'), false, 'a path separator is never a name');
  assert.equal(isSaveName('x'.repeat(65)), false);
  assert.equal(toSaveName('my palette.png'), 'my palette png');
  assert.equal(toSaveName('  ../../etc/passwd  '), 'etc passwd');
  assert.equal(toSaveName('!!!'), '');
  assert.ok(isSaveName(toSaveName('x'.repeat(200))));
});

test('the autosave ring keeps the newest first and never lists a palette twice', () => {
  let ring = [];
  for (const seed of ['a', 'b', 'c']) ring = pushAutosave(ring, { seed, name: seed });
  assert.deepEqual(ring.map((e) => e.seed), ['c', 'b', 'a']);
  // The same palette coming back — an undo, a reload — moves to the front, it does not repeat.
  ring = pushAutosave(ring, { seed: 'a', name: 'a again' });
  assert.deepEqual(ring.map((e) => e.seed), ['a', 'c', 'b']);
  assert.equal(ring[0].name, 'a again', 'the newest record of a palette wins');
});

test('the ring drops the oldest at the cap and refuses junk without throwing', () => {
  let ring = [];
  for (let i = 0; i < AUTOSAVE_CAP + 5; i++) ring = pushAutosave(ring, { seed: `s${i}` });
  assert.equal(ring.length, AUTOSAVE_CAP);
  assert.equal(ring[0].seed, `s${AUTOSAVE_CAP + 4}`);
  assert.equal(ring[ring.length - 1].seed, 's5');
  assert.deepEqual(pushAutosave(ring, {}).length, AUTOSAVE_CAP, 'an entry with no seed changes nothing');
  assert.deepEqual(pushAutosave(null, { seed: 'x' }).map((e) => e.seed), ['x']);
  assert.deepEqual(pushAutosave(undefined, {}), []);
  assert.equal(pushAutosave(ring, { seed: 'z' }, { cap: 3 }).length, 3);
});
