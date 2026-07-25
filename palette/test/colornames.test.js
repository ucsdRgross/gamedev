import test from 'node:test';
import assert from 'node:assert/strict';
import { COLOR_NAMES, nearestName, colorLabel, describeColor } from '../src/core/colornames.js';
import { generatePalette, paletteHexes } from '../src/core/generate.js';
import { presetParams, PRESETS } from '../src/core/presets.js';

test('the name list is well-formed: valid, unique hexes and unique names', () => {
  const entries = Object.entries(COLOR_NAMES);
  assert.ok(entries.length >= 100, `expected a usable list, got ${entries.length}`);
  const hexes = new Set();
  for (const [name, hex] of entries) {
    assert.match(hex, /^#[0-9A-F]{6}$/, `${name} has a malformed hex ${hex}`);
    assert.ok(!hexes.has(hex), `${hex} is listed twice (${name})`);
    hexes.add(hex);
    assert.match(name, /^[a-z][a-z ]*$/, `${name} should be lower-case words`);
  }
});

test('a listed colour finds itself exactly', () => {
  for (const [name, hex] of Object.entries(COLOR_NAMES)) {
    const near = nearestName(hex);
    assert.equal(near.distance, 0, `${name} did not match itself`);
    assert.equal(near.hex, hex);
  }
});

test('a colour near a listed one is called by that name', () => {
  const label = colorLabel('#4682B5'); // steel blue, one unit off
  assert.equal(label.label, 'steel blue');
  assert.equal(label.named, true);
  assert.equal(label.exact, false);
  assert.equal(colorLabel('#000000').exact, true);
});

test('a colour far from every name gets an honest description instead', () => {
  const label = colorLabel('#8BAC0F'); // Game Boy green — nothing in the list is close
  assert.equal(label.named, false);
  assert.match(label.label, /lime|green|yellow/);
});

test('descriptions state lightness, saturation and hue in that order', () => {
  assert.equal(describeColor('#000000'), 'near-black grey');
  assert.equal(describeColor('#808080'), 'mid grey');
  assert.match(describeColor('#00FFFF'), /cyan|teal/);
  assert.match(describeColor('#1E2A1E'), /^very dark|^near-black/);
  // A grey never claims a hue, whatever its lightness.
  for (const hex of ['#111111', '#555555', '#DDDDDD']) {
    assert.match(describeColor(hex), /grey$/, hex);
  }
});

test('every colour of every preset gets a label, named or described', () => {
  for (const p of PRESETS) {
    for (const hex of paletteHexes(generatePalette(presetParams(p.id)))) {
      const label = colorLabel(hex);
      assert.ok(label.label && label.label.length > 2, `${p.id} ${hex} produced "${label.label}"`);
    }
  }
});
