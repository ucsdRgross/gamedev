// The reachable-colour set and the dither reference sheet (PLAN §9.3, tasks 4c.2 and 4c.3).
//
// Two things here can be wrong in a way nothing else notices.
//
// **The blend colour.** Optical mixing is a linear-light average. Doing it in gamma-encoded sRGB
// or in OKLab still produces a colour between the two constituents, still passes any sanity
// check, and is wrong by several ΔE — enough to make the coverage figures and every recipe
// quietly false. So it is asserted against an independently written linear average, with both
// wrong answers as explicit negative controls.
//
// **The nearest-colour index.** A k-d tree that prunes one branch too eagerly returns *a* colour
// rather than *the* colour, which looks completely plausible on screen. It is checked against
// brute force.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BANDING_DE, BLEND_DENOM, blendColor, buildColorIndex, buildReach, buildReachMap,
  buildReachSlices, buildReferenceSlice, catalogueSections, colorSpaceSamples, entryLinears,
  patternWeights, patternsFor, preferredPattern, rampsOf, recipeText, roughnessBand,
} from '../src/core/layout/reach.js';
import { ditherSheet, pickPatchAt } from '../src/core/layout/render.js';
import { hslToSrgb, mapSample } from '../src/core/layout/colorspace.js';
import { okhslToSrgb } from '../src/core/okhsl.js';
import { patternById, patternTile } from '../src/core/patterns.js';
import { generatePalette } from '../src/core/generate.js';
import { presetParams } from '../src/core/presets.js';
import {
  linearRgbToOklab, linearToSrgb, rgb8ToSrgb, srgbToLinear, srgbToOklab, srgbToRgb8,
} from '../src/core/oklch.js';

const paletteAt = (k) => generatePalette({ color_count: k });

/** Small settings for the tests that only need the machinery, not a converged estimate. */
const FAST = { hullTrials: 0, sampleSize: { w: 24, h: 12 }, suggestions: 0 };

test('a blend is the LINEAR-LIGHT average, not the sRGB or OKLab one', () => {
  const palette = paletteAt(16);
  const linears = entryLinears(palette);
  const [a, b] = [0, palette.entries.length - 1];
  const got = blendColor(linears, [a, b], [8, 8]);

  // Independently computed, from the hexes rather than from anything reach.js built.
  const sa = rgb8ToSrgb(palette.entries[a].rgb8);
  const sb = rgb8ToSrgb(palette.entries[b].rgb8);
  const want = [0, 1, 2].map((c) => (srgbToLinear(sa[c]) + srgbToLinear(sb[c])) / 2);
  const wantLab = linearRgbToOklab(want[0], want[1], want[2]);
  for (let i = 0; i < 3; i++) assert.ok(Math.abs(got.lab[i] - wantLab[i]) < 1e-9);
  assert.deepEqual(got.rgb8, srgbToRgb8(want.map(linearToSrgb)));

  // The negative controls. Both are plausible, both are wrong, and both are far enough away
  // that this test would have caught either.
  const srgbMean = srgbToOklab([0, 1, 2].map((c) => (sa[c] + sb[c]) / 2));
  const oklabMean = [0, 1, 2].map((c) => (palette.entries[a].lab[c] + palette.entries[b].lab[c]) / 2);
  assert.ok(dist(got.lab, srgbMean) > 0.01, 'the sRGB mean is indistinguishable here — pick a wider pair');
  assert.ok(dist(got.lab, oklabMean) > 0.01, 'the OKLab mean is indistinguishable here — pick a wider pair');
});

test('an all-one-colour blend is that colour, and the weights are respected', () => {
  const palette = paletteAt(8);
  const linears = entryLinears(palette);
  assert.deepEqual(blendColor(linears, [3], [BLEND_DENOM]).rgb8, palette.entries[3].rgb8);
  // A 15:1 blend must sit far nearer the dominant colour than a 1:15 one does.
  const heavy = blendColor(linears, [0, 5], [15, 1]);
  const light = blendColor(linears, [0, 5], [1, 15]);
  assert.ok(dist(heavy.lab, palette.entries[0].lab) < dist(light.lab, palette.entries[0].lab));
});

test('the colour index agrees with brute force', () => {
  const rng = makeTestRng(11);
  const points = Array.from({ length: 4000 }, () => [rng(), rng() * 0.6 - 0.3, rng() * 0.6 - 0.3]);
  const index = buildColorIndex(points);
  for (let q = 0; q < 300; q++) {
    // Deliberately including queries far outside the cloud: the map samples the whole HSL space,
    // most of which no palette reaches, and a structure that only works near the data would pass
    // a gentler test and fail in use.
    const query = [rng() * 1.6 - 0.3, rng() * 1.2 - 0.6, rng() * 1.2 - 0.6];
    let bestD = Infinity;
    for (const p of points) bestD = Math.min(bestD, dist(query, p));
    const got = index.nearest(query[0], query[1], query[2]);
    assert.ok(Math.abs(got.dist - 100 * bestD) < 1e-9, `query ${q}: ${got.dist} vs ${100 * bestD}`);
  }
});

test('an empty index reports no neighbour rather than throwing', () => {
  const index = buildColorIndex([]);
  assert.equal(index.nearest(0.5, 0, 0).index, -1);
  assert.equal(index.nearest(0.5, 0, 0).dist, Infinity);
});

test('every pair appears, and nothing exceeds the arity ceiling', () => {
  const palette = paletteAt(8);
  const reach = buildReach(palette, { ...FAST, maxArity: 4 });
  assert.ok(reach.blends.every((b) => b.arity >= 1 && b.arity <= 4));

  // Every pair of palette colours must be reachable as a pair somewhere in the enumeration.
  // The kept set is deduplicated by colour, so this is asserted over the pairs the enumeration
  // produced rather than over the survivors.
  const pairs = new Set();
  for (const b of reach.blends) if (b.arity === 2) pairs.add(`${b.entries[0]}-${b.entries[1]}`);
  const k = palette.entries.length;
  let missing = 0;
  for (let i = 0; i < k; i++) {
    for (let j = i + 1; j < k; j++) if (!pairs.has(`${i}-${j}`)) missing++;
  }
  // A pair only disappears if every one of its fifteen ratios landed on a colour some simpler
  // blend already reaches — which is a real thing to happen for two near-identical colours.
  assert.ok(missing < (k * (k - 1)) / 2 * 0.25, `${missing} pairs vanished entirely`);
});

test('dithering never reaches less of colour space than the flat palette', () => {
  for (const preset of ['gameboy', 'neon-cyberpunk', 'snes']) {
    const reach = buildReach(generatePalette(presetParams(preset)), { ...FAST, suggestions: 1 });
    const { flat, dithered } = reach.stats;
    assert.ok(dithered.mean <= flat.mean + 1e-9, `${preset}: dithering made the mean worse`);
    assert.ok(dithered.within >= flat.within - 1e-9, `${preset}: dithering made coverage worse`);
    assert.ok(reach.stats.distinct >= reach.stats.k, `${preset}: fewer reachable colours than entries`);
  }
});

test('a greyscale palette still produces a result, and reports its limits honestly', () => {
  // The "try its best" case. A palette with no chroma cannot reach a coloured region however it
  // is dithered, and the view has to say so rather than produce a confident-looking sheet.
  const palette = generatePalette({ color_count: 12, chroma_base: 0, accent_count: 0 });
  const reach = buildReach(palette, { sampleSize: { w: 24, h: 12 }, hullTrials: 20000 });

  assert.ok(reach.stats.distinct > reach.stats.k, 'dithering added no colours at all');
  assert.ok(reach.stats.dithered.within < 0.5, 'a greyscale palette cannot cover half of colour space');
  assert.ok(reach.stats.dithered.mean <= reach.stats.flat.mean);
  assert.ok(reach.suggestions.length > 0, 'no colour was suggested for a palette that plainly needs one');
  // A suggestion must actually help, and be a legal colour on this palette's own grid.
  for (const s of reach.suggestions) {
    assert.match(s.hex, /^#[0-9A-F]{6}$/);
    assert.ok(s.after.mean <= reach.stats.dithered.mean + 1e-9, `${s.hex} made it worse`);
  }
  const sheet = ditherSheet(reach);
  assert.ok(sheet.unreachable > 0, 'the sheet claims a greyscale palette reaches all of colour space');
});

test('the reach map keeps the colour-space map geometry', () => {
  const reach = buildReach(paletteAt(16), FAST);
  const map = buildReachMap(reach, { size: { w: 48, h: 24 }, saturation: 0.7 });
  assert.equal(map.ids.length, 48 * 24);
  assert.ok(map.ids.every((id) => id >= 0 && id < reach.blends.length));
  // Hue spans an inclusive 0-360 across the rectangle, exactly as `buildColorMap` does, so the
  // two views can be flipped between without relearning where anything is.
  for (let y = 0; y < 24; y++) {
    assert.equal(map.ids[y * 48], map.ids[y * 48 + 47], `row ${y} edges differ`);
  }
  assert.ok(map.mean >= 0 && map.within >= 0 && map.within <= 1);
});

test('the reach map is at least as accurate as painting flat palette colours', () => {
  const palette = paletteAt(24);
  const reach = buildReach(palette, FAST);
  const slices = buildReachSlices(reach, { size: { w: 48, h: 24 } });
  assert.equal(slices.slices.length, 4);
  assert.ok(slices.mean <= reach.stats.flat.mean + 1e-6);
});

test('the complete-colormap reference is palette-agnostic and the true OKHSL colour', () => {
  // The reference is the thing the reachable map is compared against, so it must NOT depend on the
  // palette — two very different palettes must produce the same reference — and it must be the true
  // colour at each position, in OKHSL (perceptually uniform, so it does not band; see okhsl.js).
  const a = buildReferenceSlice({ saturation: 1, size: { w: 32, h: 16 } });
  const b = buildReferenceSlice({ saturation: 1, size: { w: 32, h: 16 } });
  assert.deepEqual([...a.rgb], [...b.rgb]);
  // Top row is white (l = 1), bottom row is black (l = 0), independent of any palette.
  assert.equal(a.rgb[0], (255 << 16) | (255 << 8) | 255);
  assert.equal(a.rgb[(a.h - 1) * a.w], 0);
  // A mid pixel equals the true OKHSL colour there, computed independently.
  const hsl = mapSample('rect', 10, 8, 32, 16, 1);
  const want = srgbToRgb8(okhslToSrgb(hsl.h, hsl.s, hsl.l));
  assert.equal(a.rgb[8 * 32 + 10], (want[0] << 16) | (want[1] << 8) | want[2]);
});

test('the reference gradient is perceptually smooth, unlike HSL', () => {
  // The reason for OKHSL: down a column of the reference, perceived lightness (CIE L*) must fall in
  // near-even steps — the property HSL lacks, which reads as banding. Measured as the coefficient
  // of variation of the step sizes, with plain HSL as the negative control.
  const ref = buildReferenceSlice({ saturation: 0.7, size: { w: 8, h: 64 } });
  const lstar = (c) => {
    const lin = [(c >> 16) & 255, (c >> 8) & 255, c & 255]
      .map((v) => v / 255).map((s) => (s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4));
    const Y = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
    return 116 * (Y > (6 / 29) ** 3 ? Math.cbrt(Y) : Y / (3 * (6 / 29) ** 2) + 4 / 29) - 16;
  };
  const stepSpread = (colorAt) => {
    const Ls = [];
    for (let y = 2; y < 62; y++) Ls.push(lstar(colorAt(y)));
    const steps = Ls.slice(1).map((l, i) => l - Ls[i]);
    const mean = steps.reduce((s, v) => s + v, 0) / steps.length;
    return Math.sqrt(steps.reduce((s, v) => s + (v - mean) ** 2, 0) / steps.length) / Math.abs(mean);
  };
  const okhslSpread = stepSpread((y) => ref.rgb[y * 8 + 4]);
  const hslSpread = stepSpread((y) => {
    const hsl = mapSample('rect', 4, y, 8, 64, 0.7);
    const c = srgbToRgb8(hslToSrgb(hsl.h, hsl.s, hsl.l));
    return (c[0] << 16) | (c[1] << 8) | c[2];
  });
  assert.ok(okhslSpread < hslSpread, `OKHSL steps (cv ${okhslSpread.toFixed(2)}) are not more even than HSL (cv ${hslSpread.toFixed(2)})`);
});

test('the sheet outlines the reachable region instead of hatching it', () => {
  // The outline must exist (white contour pixels in the overlay) and must not cover colours: it is
  // one pixel wide on the reachable side, so the plain reachable map beside it has none of it.
  const reach = buildReach(paletteAt(24), FAST);
  const sheet = ditherSheet(reach);
  const white = (245 << 16) | (245 << 8) | 250;
  let outline = 0;
  for (let i = 0; i < sheet.overlay.length; i++) if (sheet.overlay[i] === white) outline++;
  assert.ok(outline > 0, 'no selection outline was drawn');
  // The outline is a thin contour, not a fill: far fewer pixels than a solid region would take.
  assert.ok(outline < sheet.labels.length * 0.05, `the "outline" covers ${outline} pixels — that is a fill, not a contour`);
});

test('a pattern only claims weights it can express exactly', () => {
  const bayer2 = patternById('bayer2');
  const bayer4 = patternById('bayer4');
  // A 2x2 tile has four cells: quarters yes, sixteenths no.
  assert.deepEqual(patternWeights(bayer2, [4, 12]), [1, 3]);
  assert.equal(patternWeights(bayer2, [2, 14]), null);
  assert.deepEqual(patternWeights(bayer4, [2, 14]), [2, 14]);
  assert.deepEqual(patternWeights(patternById('bayer8'), [2, 14]), [8, 56]);

  // Whatever a pattern accepts, the tile it produces must honour it.
  for (const p of patternsFor([4, 4, 8])) {
    const scaled = patternWeights(p, [4, 4, 8]);
    const counts = [0, 0, 0];
    for (const slot of patternTile(p, scaled)) counts[slot]++;
    assert.deepEqual(counts, scaled, p.id);
  }
});

test('preferredPattern picks the smallest tile that fits, so 8:8 is a plain checkerboard', () => {
  assert.equal(preferredPattern([8, 8]).id, 'bayer2');
  assert.equal(preferredPattern([2, 14]).id, 'bayer4');
  assert.equal(preferredPattern([4, 4, 8]).id, 'bayer2');
});

test('the catalogue covers every pattern, both roughness extremes, and 3- and 4-way blends', () => {
  const palette = paletteAt(32);
  const reach = buildReach(palette, FAST);
  const sections = catalogueSections(reach);
  const byId = new Map(sections.map((s) => [s.id, s]));

  // Every pattern gets its own row, or the "show me all the options" promise is not kept.
  const shown = new Set(byId.get('patterns').rows.flatMap((r) => r.cells.map((c) => c.pattern.id)));
  assert.equal(shown.size, 14, `only ${shown.size} patterns in the catalogue`);

  // Contrast is present on purpose. The requirement was explicitly not just analogous pairs.
  const contrast = byId.get('contrast').rows.flatMap((r) => r.cells);
  assert.ok(contrast.some((c) => roughnessBand(c.roughness).id === 'rough'), 'no genuinely contrasting pair shown');
  const ramps = byId.get('ramps').rows.flatMap((r) => r.cells);
  assert.ok(ramps.some((c) => roughnessBand(c.roughness).id === 'smooth'), 'no cleanly blending pair shown');

  const multi = byId.get('multicolour').rows.flatMap((r) => r.cells);
  assert.ok(multi.some((c) => c.arity === 3), 'no three-colour blend');
  assert.ok(multi.some((c) => c.arity === 4), 'no four-colour blend');

  // Every cell's weights must be expressible by the pattern it is drawn with.
  for (const section of sections) {
    for (const row of section.rows) {
      for (const cell of row.cells) {
        const pattern = cell.pattern ?? preferredPattern(cell.weights);
        assert.notEqual(patternWeights(pattern, cell.weights), null,
          `${section.id}: ${pattern.id} cannot draw ${cell.weights.join(':')}`);
      }
    }
  }
});

test('rampsOf finds the ramps without importing the scene helpers', () => {
  const palette = paletteAt(32);
  const ramps = rampsOf(palette);
  assert.ok(ramps.length > 0);
  for (const ramp of ramps) {
    assert.ok(ramp.entries.length >= 2);
    // Ordered by step, which is what makes "adjacent shades" mean adjacent shades.
    for (let i = 1; i < ramp.entries.length; i++) {
      assert.ok(palette.entries[ramp.entries[i]].step > palette.entries[ramp.entries[i - 1]].step);
    }
  }
});

test('the sheet emits only palette colours, except inside the declared overlay', () => {
  // The core honesty rule: every *labelled* pixel is a palette colour, so the reachable maps and
  // the catalogue patches are guaranteed to contain nothing the palette does not. The three kinds
  // of deliberate non-palette pixel — average chips, the palette-agnostic reference colormaps, and
  // the white selection outline — all live in the declared `overlay` layer, so the exception is
  // visible and bounded rather than able to spread into the guaranteed pixels.
  const palette = paletteAt(16);
  const reach = buildReach(palette, FAST);
  const sheet = ditherSheet(reach);
  const allowed = new Set(palette.entries.map((e) => e.hex));

  let foreign = 0;
  let overlaid = 0;
  for (let i = 0; i < sheet.labels.length; i++) {
    if (sheet.overlay[i] >= 0) { overlaid++; continue; } // the declared exception
    if (sheet.labels[i] < 0) continue; // background
    if (!allowed.has(hexOf(sheet.raster.data, i * 3))) foreign++;
  }
  assert.equal(foreign, 0, `${foreign} labelled pixels are not palette colours`);
  // The overlay is deliberately large now (it carries the reference colormaps), but it must not be
  // *most* of the sheet — the labelled reachable maps and the whole catalogue are the bulk of it.
  assert.ok(overlaid > 0, 'nothing was drawn in the overlay at all');
  assert.ok(overlaid < sheet.labels.length * 0.5, `the overlay covers ${overlaid} pixels, more than half the sheet`);
});

test('hover reports the whole recipe, not just one constituent', () => {
  const palette = paletteAt(16);
  const reach = buildReach(palette, FAST);
  const sheet = ditherSheet(reach);

  const found = new Set();
  for (let i = 0; i < sheet.patches.length; i++) if (sheet.patches[i] >= 0) found.add(sheet.patches[i]);
  assert.ok(found.size > 10, 'almost nothing on the sheet is hit-testable');

  for (const id of found) {
    const patch = sheet.patchTable[id];
    assert.equal(patch.entries.length, patch.weights.length);
    assert.equal(patch.weights.reduce((a, b) => a + b, 0), BLEND_DENOM);
    assert.equal(patch.hexes.length, patch.entries.length);
    assert.ok(patch.arity >= 1 && patch.arity <= 4);
  }

  // And it is reachable through the public picker path, at a coordinate that has one.
  const at = sheet.patches.findIndex((v) => v >= 0);
  const got = pickPatchAt(sheet, at % sheet.w, Math.floor(at / sheet.w));
  assert.ok(got && got.hexes.length >= 1);
  assert.equal(pickPatchAt(sheet, -5, -5), null);
});

test('recipeText names the colours, the ratio and the pattern', () => {
  const palette = paletteAt(16);
  const reach = buildReach(palette, FAST);
  const pair = reach.blends.find((b) => b.arity === 2);
  const text = recipeText(reach, pair);
  for (const e of pair.entries) assert.ok(text.includes(palette.entries[e].hex), text);
  assert.ok(text.includes(preferredPattern(pair.weights).title.toUpperCase()), text);
  assert.ok(text.includes(pair.hex), text);

  const flat = reach.blends.find((b) => b.arity === 1);
  assert.match(recipeText(reach, flat), /NO DITHER NEEDED/);
});

test('the whole thing is deterministic', () => {
  const params = { color_count: 16 };
  const a = ditherSheet(buildReach(generatePalette(params), FAST));
  const b = ditherSheet(buildReach(generatePalette(params), FAST));
  assert.equal(a.w, b.w);
  assert.equal(a.h, b.h);
  assert.deepEqual([...a.raster.data], [...b.raster.data]);
});

test('the colour-space sample set covers every saturation slice', () => {
  const { labs, groups } = colorSpaceSamples({ size: { w: 8, h: 4 } });
  assert.equal(groups.length, 4);
  assert.equal(labs.length, 8 * 4 * 4);
  assert.equal(groups.at(-1).end, labs.length);
  for (const g of groups) assert.ok(g.end > g.start);
});

test('the roughness bands sit where the measured ramp steps put them', () => {
  assert.equal(BANDING_DE, 2);
  assert.equal(roughnessBand(0).id, 'smooth');
  assert.equal(roughnessBand(18).id, 'smooth');
  assert.equal(roughnessBand(18.1).id, 'textured');
  assert.equal(roughnessBand(35.1).id, 'rough');

  // The boundary exists to classify a real thing correctly: adjacent steps of a ramp are the
  // everyday convincing blend, so the median one must land in `smooth`. This is the assertion
  // that caught the first, guessed, boundary of 10.
  const palette = paletteAt(32);
  const steps = [];
  for (const ramp of rampsOf(palette)) {
    for (let i = 1; i < ramp.entries.length; i++) {
      steps.push(dist(palette.entries[ramp.entries[i]].lab, palette.entries[ramp.entries[i - 1]].lab) * 100);
    }
  }
  steps.sort((a, b) => a - b);
  assert.equal(roughnessBand(steps[Math.floor(steps.length / 2)]).id, 'smooth');
});

function dist(a, b) {
  return Math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2);
}

function hexOf(data, p) {
  return `#${[data[p], data[p + 1], data[p + 2]]
    .map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`;
}

/** A tiny deterministic PRNG, local to the test so it cannot drift with `rng.js`. */
function makeTestRng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(s ^ (s >>> 15), 2246822507) + 0x9e3779b9) >>> 0;
    return ((s ^ (s >>> 13)) >>> 0) / 4294967296;
  };
}
