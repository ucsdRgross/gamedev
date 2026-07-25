import test from 'node:test';
import assert from 'node:assert/strict';
import { generatePalette } from '../src/core/generate.js';
import { presetParams } from '../src/core/presets.js';
import { defaultParams } from '../src/core/params.js';
import {
  describePalette, hueName, paramDiff, describeChange, summarizeDiff,
} from '../src/core/describe.js';

/** The palette a preset produces, with its parameters. */
function preset(id) {
  const params = presetParams(id);
  return { params, palette: generatePalette(params) };
}

test('hue names follow OKLCH angles, not HSL ones', () => {
  // Landmarks measured from the sRGB primaries in OKLCH (red 29°, yellow 110°, green 142°,
  // cyan 195°, blue 264°, magenta 328°).
  assert.equal(hueName(29), 'red');
  assert.equal(hueName(110), 'yellow');
  assert.equal(hueName(142), 'green');
  assert.equal(hueName(195), 'teal');
  assert.equal(hueName(264), 'blue');
  assert.equal(hueName(328), 'violet');
  assert.equal(hueName(-10), hueName(350), 'angles wrap');
});

test('a description opens with the colour count and the hue story', () => {
  const { params, palette } = preset('snes');
  const text = describePalette(palette, params);
  assert.match(text, /^48 colours · /);
  assert.match(text, /6 analogous hues around cyan/, text); // root_hue 210 in OKLCH
});

test('descriptions name the value key, the contrast and the saturation', () => {
  const dungeon = preset('candlelit-dungeon');
  assert.match(describePalette(dungeon.palette, dungeon.params), /dark|very dark/);

  const ink = preset('monochrome-ink');
  assert.match(describePalette(ink.palette, ink.params), /greyscale/);

  const gb = preset('gameboy');
  assert.match(describePalette(gb.palette, gb.params), /^4 colours · a single \w+ hue/);
});

test('descriptions report the shading and hardware choices that define a look', () => {
  const toxic = preset('toxic-swamp');
  assert.match(describePalette(toxic.palette, toxic.params), /cool light, warm shadows/);

  const snes = preset('snes');
  assert.match(describePalette(snes.palette, snes.params), /5\/5\/5-bit hardware/);

  const ink = preset('monochrome-ink');
  assert.match(describePalette(ink.palette, ink.params), /flat shading/);
});

test('a description works without parameters, using only the colours', () => {
  const { palette } = preset('autumn-forest');
  const text = describePalette(palette);
  assert.match(text, /^32 colours · /);
  assert.ok(!text.includes('hue-shifted'), 'shading is a statement of intent, not of colour');
});

test('an unchanged parameter set has no diff', () => {
  assert.deepEqual(paramDiff(defaultParams(), defaultParams()), []);
  assert.equal(summarizeDiff([]), '');
});

test('a diff finds every change and ranks the big moves first', () => {
  const from = defaultParams();
  const to = { ...from, chroma_base: 0.3, dither_evenness: 0.32, hue_scheme: 'triadic' };
  const diff = paramDiff(from, to);
  assert.deepEqual(diff.map((d) => d.name).sort(), ['chroma_base', 'dither_evenness', 'hue_scheme']);
  // chroma_base moved 42% of its range and is a "big mover"; dither_evenness moved 2%.
  assert.equal(diff[diff.length - 1].name, 'dither_evenness');
  assert.ok(diff[0].magnitude > diff[1].magnitude || diff[0].weight > diff[1].weight);
});

test('changes read as sentences, with the parameter label and the direction', () => {
  const from = defaultParams();
  const diff = paramDiff(from, {
    ...from, chroma_base: 0.205, root_hue: 210, hue_scheme: 'triadic', neutral_split: true,
  });
  const byName = Object.fromEntries(diff.map((d) => [d.name, describeChange(d)]));
  assert.equal(byName.chroma_base, 'Saturation +0.060');
  assert.equal(byName.root_hue, 'Colour of the world +175');
  assert.equal(byName.hue_scheme, 'How the hues relate → Triadic');
  assert.equal(byName.neutral_split, 'Separate warm and cool greys on');
});

test('a seed reroll is never described as a change', () => {
  const from = defaultParams();
  const diff = paramDiff(from, { ...from, seed: 54321, chroma_base: 0.16 });
  // It is still reported (something did change), but it can never outrank a real move, and a
  // summary that filters out imperceptible changes drops it entirely.
  assert.equal(diff[0].name, 'chroma_base');
  assert.equal(diff.find((d) => d.name === 'seed').magnitude, 0);
  const filtered = paramDiff(from, { ...from, seed: 54321 }, { minMagnitude: 0.015 });
  assert.deepEqual(filtered, []);
});

test('a summary can ignore changes too small to see', () => {
  const from = defaultParams();
  const to = { ...from, chroma_base: 0.3, l_step: 0.152 }; // l_step moved 0.6% of its range
  assert.equal(paramDiff(from, to).length, 2);
  assert.deepEqual(paramDiff(from, to, { minMagnitude: 0.015 }).map((d) => d.name), ['chroma_base']);
});

test('a summary lists the top changes and counts the rest', () => {
  const from = defaultParams();
  const diff = paramDiff(from, presetParams('snes'));
  const summary = summarizeDiff(diff, 3);
  assert.equal(summary.split(' · ').length, 4, summary);
  assert.match(summary, /\+\d+ more$/);
  assert.equal(summarizeDiff(diff.slice(0, 2), 3).includes('more'), false);
});
