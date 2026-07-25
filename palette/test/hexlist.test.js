// Paste ingestion. The interesting cases are not the well-formed ones — they are the blob of
// prose that must yield nothing, and the CSS file that must yield exactly its colours.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseHexList, hexListPalette } from '../src/core/hexlist.js';

test('the plain forms all parse', () => {
  assert.deepEqual(parseHexList('#ff0000 #00FF00 #0000ff'), ['#FF0000', '#00FF00', '#0000FF']);
  assert.deepEqual(parseHexList('ff0000,00ff00,0000ff'), ['#FF0000', '#00FF00', '#0000FF']);
  assert.deepEqual(parseHexList('ff0000\n00ff00\n0000ff'), ['#FF0000', '#00FF00', '#0000FF']);
  assert.deepEqual(parseHexList('  ff0000\t00ff00  '), ['#FF0000', '#00FF00']);
});

test('a lospec dump parses as-is', () => {
  const dump = '1a1c2c\n5d275d\nb13e53\nef7d57\nffcd75\na7f070\n38b764\n257179';
  assert.deepEqual(parseHexList(dump).length, 8);
  assert.equal(parseHexList(dump)[0], '#1A1C2C');
});

test('CSS shorthand and alpha are accepted and normalised', () => {
  assert.deepEqual(parseHexList('#abc'), ['#AABBCC']);
  assert.deepEqual(parseHexList('#abcd'), ['#AABBCC'], 'the alpha nibble is dropped');
  assert.deepEqual(parseHexList('#ff0000ff'), ['#FF0000'], 'the alpha byte is dropped');
});

test('a bare three-digit token is refused, because English words are valid hex', () => {
  assert.deepEqual(parseHexList('add a bee to the cab dad'), []);
  assert.deepEqual(parseHexList('faded, deaf, added, feeble, cabbage'), []);
  // With the hash it is unambiguous and therefore fine.
  assert.deepEqual(parseHexList('#add'), ['#AADDDD']);
  // The six-digit rule is a floor, not a guarantee: `decade` and `facade` really are hex, and
  // accepting bare six-digit tokens is the whole reason a Lospec dump parses. Prose stays
  // clean because six-letter hex-only words are rare, not because they are impossible.
  assert.deepEqual(parseHexList('a decade of facade'), ['#DECADE', '#FACADE']);
});

test('colours are lifted out of real surrounding syntax', () => {
  const css = `:root {\n  --bg: #1a1c2c;\n  --fg: #f4f4f4; /* paper */\n  --accent: rgb(0,0,0);\n}`;
  assert.deepEqual(parseHexList(css), ['#1A1C2C', '#F4F4F4']);
  assert.deepEqual(parseHexList('["#ff0000", "#00ff00"]'), ['#FF0000', '#00FF00']);
  assert.deepEqual(parseHexList('0xFF0000; 0x00FF00;'), ['#FF0000', '#00FF00']);
});

test('duplicates collapse, order is first-appearance, and the cap holds', () => {
  assert.deepEqual(parseHexList('#ff0000 #00ff00 #ff0000'), ['#FF0000', '#00FF00']);
  assert.deepEqual(parseHexList('#123456 #abcdef', { max: 1 }), ['#123456']);
});

test('nothing usable yields an empty list rather than throwing', () => {
  for (const input of ['', null, undefined, 'no colours here at all', '#12 #1234567 #xyzxyz']) {
    assert.deepEqual(parseHexList(input), [], JSON.stringify(input));
  }
});

test('a parsed list becomes a recolour target of the same shape as an image-derived one', () => {
  const palette = hexListPalette('pasted', parseHexList('#1a1c2c, #f4f4f4, #b13e53'));
  assert.equal(palette.name, 'pasted');
  assert.equal(palette.external, true);
  assert.equal(palette.entries.length, 3);
  for (const e of palette.entries) {
    assert.match(e.hex, /^#[0-9A-F]{6}$/);
    assert.equal(e.rgb8.length, 3);
    assert.equal(e.lab.length, 3, 'the recolour engine matches in OKLab, so lab must be there');
  }
  assert.deepEqual(palette.entries[0].rgb8, [0x1a, 0x1c, 0x2c]);
});
