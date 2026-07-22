// Colour-space maps (PLAN §9.1, task 4b.2).
//
// A map's whole value is that position means something fixed, so the geometry is asserted
// literally: the rectangle's two side edges are the same hue, its top row is white's nearest
// colour and its bottom row is black's. The other half of the contract is honesty — the map
// must paint palette colours and nothing else, and the `shown/total` count it reports must
// be a fact about the pixels rather than a hopeful number.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_SATURATIONS, MAP_GEOMETRIES, buildColorMap, buildMapSlices, hslToSrgb,
  mapFidelity, mapPickAt, mapSample,
} from '../src/core/layout/colorspace.js';
import { mapSheet, paintLabels, pickAt } from '../src/core/layout/render.js';
import { generatePalette } from '../src/core/generate.js';
import { presetParams } from '../src/core/presets.js';
import { rgb8ToHex, srgbToRgb8 } from '../src/core/oklch.js';

const paletteAt = (k) => generatePalette({ color_count: k });
const SIZE = { w: 96, h: 64 };
const DISC = { w: 72, h: 72 };
const sizeFor = (geometry) => (geometry === 'polar' ? DISC : SIZE);

/** Every distinct `#RRGGBB` in a raster. */
function rasterHexes(raster) {
  const out = new Set();
  for (let i = 0; i < raster.data.length; i += 3) {
    out.add(rgb8ToHex([raster.data[i], raster.data[i + 1], raster.data[i + 2]]));
  }
  return out;
}

test('hslToSrgb matches the published HSL definition', () => {
  const cases = [
    [0, 1, 0.5, [255, 0, 0]],
    [120, 1, 0.5, [0, 255, 0]],
    [240, 1, 0.5, [0, 0, 255]],
    [60, 1, 0.5, [255, 255, 0]],
    [0, 0, 0.5, [128, 128, 128]],
    [210, 0.5, 0.25, [32, 64, 96]],
    [0, 1, 1, [255, 255, 255]],
    [0, 1, 0, [0, 0, 0]],
  ];
  for (const [h, s, l, expected] of cases) {
    assert.deepEqual(srgbToRgb8(hslToSrgb(h, s, l)), expected, `hsl(${h} ${s} ${l})`);
  }
  // Hue wraps: 360 and 0 are the same colour, and negatives normalise.
  assert.deepEqual(hslToSrgb(360, 1, 0.5), hslToSrgb(0, 1, 0.5));
  assert.deepEqual(hslToSrgb(-90, 0.6, 0.4), hslToSrgb(270, 0.6, 0.4));
});

test('rect geometry: the side edges are the same hue and lightness runs white to black', () => {
  const { w, h } = SIZE;
  const left = mapSample('rect', 0, 10, w, h, 1);
  const right = mapSample('rect', w - 1, 10, w, h, 1);
  assert.equal(left.h, 0);
  assert.equal(right.h, 360);
  assert.deepEqual(hslToSrgb(left.h, left.s, left.l), hslToSrgb(right.h, right.s, right.l));

  assert.equal(mapSample('rect', 5, 0, w, h, 1).l, 1); // top edge is white
  assert.equal(mapSample('rect', 5, h - 1, w, h, 1).l, 0); // bottom edge is black
  for (let y = 1; y < h; y++) {
    assert.ok(mapSample('rect', 5, y, w, h, 1).l < mapSample('rect', 5, y - 1, w, h, 1).l);
  }
});

test('rect map: side columns are identical, top row is one colour, bottom row is one colour', () => {
  const palette = paletteAt(32);
  const map = buildColorMap(palette, { geometry: 'rect', saturation: 1, size: SIZE });
  const { w, h, labels } = map;

  for (let y = 0; y < h; y++) {
    assert.equal(labels[y * w], labels[y * w + w - 1], `row ${y}: the wrapping edges differ`);
  }

  const top = new Set();
  const bottom = new Set();
  for (let x = 0; x < w; x++) {
    top.add(labels[x]);
    bottom.add(labels[(h - 1) * w + x]);
  }
  // At l=1 and l=0 the colour is white and black whatever the hue, so each row is one colour.
  assert.equal(top.size, 1);
  assert.equal(bottom.size, 1);
  const lightest = palette.entries[[...top][0]].actual.L;
  const darkest = palette.entries[[...bottom][0]].actual.L;
  assert.ok(lightest > darkest, `top ${lightest} should be lighter than bottom ${darkest}`);
  for (const e of palette.entries) {
    assert.ok(e.actual.L <= lightest + 1e-9, 'the top row should hold the palette\'s lightest colour');
    assert.ok(e.actual.L >= darkest - 1e-9, 'the bottom row should hold the palette\'s darkest colour');
  }
});

test('polar geometry: the centre is white, the rim is black, outside the disc is unpainted', () => {
  const palette = paletteAt(24);
  const map = buildColorMap(palette, { geometry: 'polar', saturation: 1, size: DISC });
  const { w, h, labels } = map;

  assert.equal(mapSample('polar', 0, 0, w, h, 1), null, 'a corner is outside the disc');
  assert.equal(labels[0], -1);
  const centre = mapSample('polar', (w - 1) / 2, (h - 1) / 2, w, h, 1);
  assert.equal(centre.l, 1);
  assert.ok(mapSample('polar', 1, h / 2, w, h, 1).l < 0.05, 'the rim is black');

  // Hue 0 points up and increases clockwise.
  assert.equal(Math.round(mapSample('polar', (w - 1) / 2, 0, w, h, 1).h), 0);
  assert.equal(Math.round(mapSample('polar', w - 1, (h - 1) / 2, w, h, 1).h), 90);

  let outside = 0;
  for (let i = 0; i < labels.length; i++) if (labels[i] < 0) outside++;
  assert.ok(outside > 0 && outside < labels.length * 0.3, `disc mask covers ${outside} of ${labels.length}`);
});

test('a map paints palette colours and nothing else — no outline pixels in either geometry', () => {
  for (const geometry of MAP_GEOMETRIES) {
    const palette = generatePalette(presetParams('neon-cyberpunk'));
    const map = buildColorMap(palette, { geometry, size: sizeFor(geometry) });
    const paletteHexes = new Set(palette.entries.map((e) => e.hex));

    for (let i = 0; i < map.labels.length; i++) {
      const label = map.labels[i];
      assert.ok(label >= -1 && label < palette.entries.length, `${geometry}: stray label ${label}`);
    }
    // Rendered with a background that is *not* in the palette, so a foreign pixel anywhere
    // inside the shape would show up as an extra hex.
    const raster = paintLabels(map.labels, map.w, map.h, palette, [1, 2, 3]);
    const drawn = rasterHexes(raster);
    drawn.delete('#010203');
    for (const hex of drawn) assert.ok(paletteHexes.has(hex), `${geometry}: foreign pixel ${hex}`);
    assert.equal(drawn.size, map.shownCount, `${geometry}: drawn colours should match the reported count`);
  }
});

test('the shown/total count is a fact about the pixels', () => {
  for (const geometry of MAP_GEOMETRIES) {
    const palette = paletteAt(48);
    const map = buildColorMap(palette, { geometry, size: sizeFor(geometry) });
    const painted = new Set();
    for (let i = 0; i < map.labels.length; i++) if (map.labels[i] >= 0) painted.add(palette.entries[map.labels[i]].hex);

    assert.equal(map.total, palette.entries.length);
    assert.equal(map.shownCount, map.shown.length);
    assert.equal(map.shown.length + map.missing.length, map.total);
    for (const i of map.shown) assert.ok(painted.has(palette.entries[i].hex), `${geometry}: ${i} claimed shown`);
    for (const i of map.missing) assert.ok(!painted.has(palette.entries[i].hex), `${geometry}: ${i} claimed missing`);
    // The trade-off is real and must not be quietly "fixed": a slice shows most of a full
    // palette, not all of it. If this ever reads 48/48 the map has started forcing colours in.
    assert.ok(map.shownCount > map.total * 0.5, `${geometry}: only ${map.shownCount}/${map.total} shown`);
  }
});

test('slices report their union, and missing is exactly what no slice reaches', () => {
  const palette = paletteAt(48);
  const set = buildMapSlices(palette, { geometry: 'rect', size: SIZE });
  assert.equal(set.slices.length, DEFAULT_SATURATIONS.length);

  const union = new Set();
  for (const slice of set.slices) {
    for (const i of slice.shown) union.add(i);
    assert.ok(slice.shownCount <= set.shownCount, 'no slice may show more than the union');
  }
  assert.deepEqual(set.shown, [...union].sort((a, b) => a - b));
  assert.deepEqual(set.missing, palette.entries.map((_, i) => i).filter((i) => !union.has(i)));
  assert.equal(set.shownCount + set.missing.length, set.total);
  // Several slices beat one: desaturated slices are what reach the neutrals.
  assert.ok(set.shownCount >= Math.max(...set.slices.map((s) => s.shownCount)));
});

test('maps are deterministic and depend only on the palette', () => {
  for (const geometry of MAP_GEOMETRIES) {
    const size = sizeFor(geometry);
    const a = buildColorMap(paletteAt(32), { geometry, size });
    const b = buildColorMap(paletteAt(32), { geometry, size });
    assert.deepEqual([...a.labels], [...b.labels], `${geometry} is not deterministic`);
    assert.deepEqual(a.shown, b.shown);
  }
});

test('resolution changes sampling density, not geometry', () => {
  const palette = paletteAt(32);
  const small = buildColorMap(palette, { geometry: 'rect', size: { w: 48, h: 32 } });
  const large = buildColorMap(palette, { geometry: 'rect', size: { w: 192, h: 128 } });
  // Same corners: the geometry is defined on the unit rectangle, not on the pixel count.
  assert.equal(small.labels[0], large.labels[0]);
  assert.equal(small.labels[small.w - 1], large.labels[large.w - 1]);
  assert.equal(small.labels[small.labels.length - 1], large.labels[large.labels.length - 1]);
  assert.ok(large.shownCount >= small.shownCount, 'finer sampling cannot show fewer colours');
});

test('mapPickAt reads back the label under a pixel and refuses to guess outside', () => {
  const palette = paletteAt(16);
  const map = buildColorMap(palette, { geometry: 'rect', size: SIZE });
  assert.equal(mapPickAt(map, 0, 0), map.labels[0]);
  assert.equal(mapPickAt(map, 10.7, 4.2), map.labels[4 * map.w + 10]);
  assert.equal(mapPickAt(map, -1, 0), -1);
  assert.equal(mapPickAt(map, map.w, 0), -1);
  assert.equal(mapPickAt(map, 0, map.h), -1);
});

test('mapFidelity measures the error the map is showing', () => {
  const palette = paletteAt(64);
  const coarse = generatePalette({ color_count: 8 });
  const fine = buildColorMap(palette, { geometry: 'rect', size: SIZE });
  const rough = buildColorMap(coarse, { geometry: 'rect', size: SIZE });
  assert.ok(mapFidelity(fine, palette) > 0);
  assert.ok(mapFidelity(fine, palette) < mapFidelity(rough, coarse), 'more colours should map more faithfully');
});

test('the slice sheet draws every slice plus a strip of the colours no slice reaches', () => {
  const palette = paletteAt(48);
  // Deliberately one slice, because the default four usually reach everything and a strip
  // test with nothing to put in the strip asserts nothing. A single fully-saturated slice
  // always leaves the near-neutrals stranded, which is exactly the case the strip exists for.
  const set = buildMapSlices(palette, { geometry: 'rect', saturations: [1], size: SIZE });
  assert.ok(set.missing.length > 0, 'a single saturated slice should strand some colours');

  const sheet = mapSheet(set, palette, { columns: 2 });
  assert.ok(sheet.w > SIZE.w && sheet.h > SIZE.h);
  const drawn = rasterHexes(sheet.raster);
  for (const i of set.shown) assert.ok(drawn.has(palette.entries[i].hex), `slice sheet lost colour ${i}`);
  // The point of the strip: a colour missing from every slice is still on the sheet, and
  // labelled, so it can be hovered and copied like anything else on it.
  for (const i of set.missing) {
    assert.ok(drawn.has(palette.entries[i].hex), `unreachable colour ${i} not in the strip`);
    assert.ok(sheet.labels.includes(i), `unreachable colour ${i} is drawn but not hit-testable`);
  }
  // Every sheet pixel is either a palette colour or background — no text pixel claims a label.
  for (let i = 0; i < sheet.labels.length; i++) {
    assert.ok(sheet.labels[i] >= -1 && sheet.labels[i] < palette.entries.length);
  }
  assert.equal(pickAt(sheet, -1, 0), -1);
});

test('more saturation slices reach more of the palette', () => {
  const palette = paletteAt(48);
  const one = buildMapSlices(palette, { geometry: 'rect', saturations: [1], size: SIZE });
  const all = buildMapSlices(palette, { geometry: 'rect', size: SIZE });
  assert.ok(all.shownCount > one.shownCount, `${all.shownCount} slices union vs ${one.shownCount} for one`);
  for (const i of one.shown) assert.ok(all.shown.includes(i), 'the union must contain every single-slice colour');
});

test('an unknown geometry is refused rather than silently defaulting', () => {
  assert.throws(() => buildColorMap(paletteAt(8), { geometry: 'hexagon' }), /unknown map geometry/);
});
