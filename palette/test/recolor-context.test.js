// Context-aware recolouring (ARCHITECTURE §12.8).
//
// The feature's whole claim is that a source *background* colour lands on a target
// BACKGROUND colour rather than wherever the ΔE happens to be smallest. That claim is worth
// exactly as much as the two properties guarding it, so both are asserted directly:
//
//  1. **Off is off.** Every default reproduces the layer-blind mapping byte for byte. A
//     feature that silently perturbs existing recolours would be a regression however good
//     its output is.
//  2. **The indexed invariant survives.** A source colour still maps to exactly one target
//     colour — context changes *which* target, never how many.
//
// The payoff itself is measured the way the investigation measured it: source images are
// gallery scenes rendered with a known palette, so every source colour's true layer is known
// and "did fg/bg separation survive" is a number rather than an opinion.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CONTEXT_IDS, HARD_PENALTY, RECOLOR_CONTEXTS, SOFT_PENALTY, applyContextPenalty, colorSignals,
  inferContexts, sourceContexts, targetPools,
} from '../src/core/recolor/context.js';
import { buildIndexedMapping, recolorIndexed } from '../src/core/recolor/indexed.js';
import { recolorFrames, recolorImage } from '../src/core/recolor/index.js';
import { uniqueColors } from '../src/core/recolor/image.js';
import { externalPalette, extractPalette } from '../src/core/recolor/swatches.js';
import { generatePalette } from '../src/core/generate.js';
import { deltaEOK } from '../src/core/oklch.js';
import { Raster } from '../src/core/raster.js';
import { SCENES } from '../src/scenes/index.js';
import { presetParams } from '../src/core/presets.js';

const target = generatePalette({ color_count: 48 });

/** A picture with an unambiguous flat backdrop, a subject, and a dark outline around it. */
function subjectOnBackdrop(w = 40, h = 30) {
  const img = new Raster(w, h, null);
  const backdrop = [180, 200, 215];
  const body = [200, 90, 60];
  const outline = [12, 10, 14];
  const spark = [255, 240, 40];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const inSubject = x >= 12 && x < 28 && y >= 8 && y < 24;
      const onEdge = inSubject && (x === 12 || x === 27 || y === 8 || y === 23);
      img.set(x, y, onEdge ? outline : inSubject ? body : backdrop);
    }
  }
  img.set(20, 15, spark);
  return { img, backdrop, body, outline, spark };
}

const keyOf = (rgb) => (rgb[0] << 16) | (rgb[1] << 8) | rgb[2];

// --- The partition ---------------------------------------------------------

test('RECOLOR_CONTEXTS is a strictly disjoint partition — the guarantee depends on it', () => {
  const seen = new Set();
  for (const c of RECOLOR_CONTEXTS) {
    for (const layer of c.layers) {
      assert.ok(!seen.has(layer), `layer ${layer} appears in more than one context`);
      seen.add(layer);
    }
  }
  // Every layer the generator can emit must have a home, or entries fall out of the scheme.
  const layers = new Set(generatePalette({ color_count: 64 }).entries.map((e) => e.layer));
  for (const l of layers) assert.ok(seen.has(l), `layer ${l} belongs to no context`);
});

test('targetPools partitions the palette and returns null for a palette with no layers', () => {
  const pools = targetPools(target.entries);
  const all = [...pools.values()].flat().sort((a, b) => a - b);
  assert.deepEqual(all, target.entries.map((_, i) => i));
  assert.equal(new Set(all).size, target.entries.length, 'an entry landed in two pools');

  // An extracted palette is deliberately just colours — no layers, so no structure to use.
  const { img } = subjectOnBackdrop();
  const ext = externalPalette('x', extractPalette(img));
  assert.equal(targetPools(ext.entries), null);
});

// --- Source signals and inference -----------------------------------------

test('colorSignals measures coverage, border share and edginess as documented', () => {
  const { img, backdrop, body, spark } = subjectOnBackdrop();
  const sig = colorSignals(img);
  const of = (rgb) => sig.find((s) => s.key === keyOf(rgb));

  // The backdrop owns the entire outer ring and is one flat field.
  assert.equal(of(backdrop).borderShare, 1);
  assert.ok(of(backdrop).edginess < 0.2, 'a flat field should have a low perimeter-to-area');
  // The lone sparkle pixel touches nothing but its neighbour and covers almost nothing.
  assert.ok(of(spark).coverage < 0.002);
  assert.equal(of(spark).borderShare, 0);
  // Coverage sums to 1 across every distinct colour.
  const totalCoverage = sig.reduce((a, s) => a + s.coverage, 0);
  assert.ok(Math.abs(totalCoverage - 1) < 1e-9);
  assert.ok(of(body).coverage > of(spark).coverage);
});

test('colorSignals over several frames tallies them together, so context cannot flicker', () => {
  const a = new Raster(4, 4, [10, 20, 30]);
  const b = new Raster(4, 4, [200, 100, 50]);
  const sig = colorSignals([a, b]);
  assert.equal(sig.length, 2);
  for (const s of sig) assert.ok(Math.abs(s.coverage - 0.5) < 1e-9);
});

test('inferContexts assigns EVERY colour — it abstains on nothing', () => {
  const { img } = subjectOnBackdrop();
  const sig = colorSignals(img);
  const ctx = inferContexts(sig);
  assert.equal(ctx.size, sig.length);
  for (const s of sig) assert.ok(CONTEXT_IDS.includes(ctx.get(s.key)));
});

test('inferContexts finds the backdrop and the outline when the picture has clear ones', () => {
  const { img, backdrop, body, outline } = subjectOnBackdrop();
  const ctx = sourceContexts([img]);
  assert.equal(ctx.get(keyOf(backdrop)), 'scenery');
  assert.equal(ctx.get(keyOf(outline)), 'anchor');
  assert.equal(ctx.get(keyOf(body)), 'sprite');
});

test('a manual override always beats the inference, and a bogus one is ignored', () => {
  const { img, backdrop } = subjectOnBackdrop();
  const forced = sourceContexts([img], new Map([[keyOf(backdrop), 'accent']]));
  assert.equal(forced.get(keyOf(backdrop)), 'accent');
  const bogus = sourceContexts([img], new Map([[keyOf(backdrop), 'not-a-context']]));
  assert.equal(bogus.get(keyOf(backdrop)), 'scenery', 'an unknown id must fall back to the guess');
});

// --- The penalty -----------------------------------------------------------

test('applyContextPenalty surcharges only out-of-pool targets, and bias scales it', () => {
  const pools = new Map([['sprite', [0]], ['scenery', [1]]]);
  const base = () => Float64Array.from([1, 2, 3, 4]); // 2 sources x 2 targets
  const hard = applyContextPenalty(base(), ['sprite', 'scenery'], pools, 2, 1);
  assert.deepEqual([...hard], [1, 2 + HARD_PENALTY, 3 + HARD_PENALTY, 4]);
  // Below 1 the surcharge is on the ΔE scale, not a fraction of the hard penalty — see the
  // placebo test below for why that distinction is load-bearing.
  const half = applyContextPenalty(base(), ['sprite', 'scenery'], pools, 2, 0.5);
  assert.deepEqual([...half], [1, 2 + SOFT_PENALTY * 0.5, 3 + SOFT_PENALTY * 0.5, 4]);
  // Zero bias must not touch the matrix at all — this is what makes `off` exact.
  assert.deepEqual([...applyContextPenalty(base(), ['sprite', 'scenery'], pools, 2, 0)], [1, 2, 3, 4]);
});

test('remap_context_bias is a real knob, not a placebo', () => {
  // The first cut interpolated to HARD_PENALTY, which made every setting from 0.2 upward a
  // 200+ ΔE surcharge — unpayable, so identical output across the whole range. The knob has to
  // actually move the assignment somewhere between "off" and "hard", and only a comparison of
  // whole mappings catches it: every individual unit test still passed while it was broken.
  const scene = SCENES.find((s) => s.id === 'screenshot');
  const source = generatePalette({ ...presetParams('neon-cyberpunk'), color_count: 48 });
  const raster = new Raster(scene.width, scene.height);
  scene.render(raster, source, { frame: 0 });

  const { colors } = uniqueColors(raster);
  const pools = targetPools(target.entries);
  const contexts = sourceContexts([raster]);
  const mappingAt = (contextBias) => colors
    .map((c) => buildIndexedMapping(colors, target.entries, { contexts, pools, contextBias }).get(c.key))
    .join(',');

  const off = mappingAt(0);
  const hard = mappingAt(1);
  assert.notEqual(off, hard, 'the hard end must differ from off, or nothing is happening');

  const mid = [0.25, 0.5, 0.75].map(mappingAt);
  assert.ok(
    mid.some((m) => m !== off && m !== hard),
    'no intermediate bias produced a mapping between off and hard — the knob is a placebo',
  );
});

test('a context whose pool is empty is left alone rather than penalised everywhere', () => {
  const pools = new Map([['sprite', [0, 1]], ['accent', []]]);
  const cost = applyContextPenalty(Float64Array.from([1, 2]), ['accent'], pools, 2, 1);
  assert.deepEqual([...cost], [1, 2]);
});

// --- The two guarding properties ------------------------------------------

test('off, and bias 0, reproduce the layer-blind mapping exactly', () => {
  const { img } = subjectOnBackdrop();
  const { colors } = uniqueColors(img);
  const blind = buildIndexedMapping(colors, target.entries, { match: 'delta-e' });

  for (const match of ['delta-e', 'lightness-rank', 'optimal']) {
    for (const preserveOrder of [false, true]) {
      const base = buildIndexedMapping(colors, target.entries, { match, preserveOrder });
      const off = recolorImage(img, target, { mode: 'indexed', match, preserveOrder });
      assert.equal(off.context.applied, false);
      const zero = buildIndexedMapping(colors, target.entries, {
        match, preserveOrder, contexts: sourceContexts([img]), pools: targetPools(target.entries), contextBias: 0,
      });
      for (const c of colors) {
        assert.equal(zero.get(c.key), base.get(c.key), `${match}/${preserveOrder} moved at bias 0`);
        assert.equal(off.mapping.get(c.key), base.get(c.key));
      }
    }
  }
  assert.ok(blind.size > 0);
});

test('a source colour still maps to exactly one target colour under every context setting', () => {
  const { img } = subjectOnBackdrop();
  const pools = targetPools(target.entries);
  const contexts = sourceContexts([img]);
  for (const match of ['delta-e', 'lightness-rank', 'optimal']) {
    for (const overflow of ['share', 'merge']) {
      for (const contextBias of [0.5, 1]) {
        const { image, mapping } = recolorIndexed(img, target.entries, {
          match, overflow, contexts, pools, contextBias,
        });
        // Re-derive the mapping from the pixels: every occurrence of a source colour must
        // have become the same output colour.
        const seen = new Map();
        for (let p = 0; p < img.data.length; p += 3) {
          const src = (img.data[p] << 16) | (img.data[p + 1] << 8) | img.data[p + 2];
          const dst = (image.data[p] << 16) | (image.data[p + 1] << 8) | image.data[p + 2];
          if (seen.has(src)) assert.equal(seen.get(src), dst, `${match}/${overflow} split a colour`);
          else seen.set(src, dst);
        }
        assert.ok(mapping.size > 0);
      }
    }
  }
});

test('every output colour is still a target-palette colour', () => {
  const { img } = subjectOnBackdrop();
  const allowed = new Set(target.entries.map((e) => keyOf(e.rgb8)));
  const { image } = recolorIndexed(img, target.entries, {
    contexts: sourceContexts([img]), pools: targetPools(target.entries), contextBias: 1,
  });
  for (let p = 0; p < image.data.length; p += 3) {
    assert.ok(allowed.has((image.data[p] << 16) | (image.data[p + 1] << 8) | image.data[p + 2]));
  }
});

// --- The payoff, measured --------------------------------------------------

/**
 * Render a gallery scene with `source`, so every source colour that is a palette entry
 * carries its true layer, then report fg/bg separation before and after a recolour.
 */
function separationCase(sceneId, sourceParams) {
  const source = generatePalette({ ...sourceParams, color_count: 48 });
  const scene = SCENES.find((s) => s.id === sceneId);
  const raster = new Raster(scene.width, scene.height);
  scene.render(raster, source, { frame: 0 });

  const byKey = new Map();
  source.entries.forEach((e) => {
    const k = keyOf(e.rgb8);
    if (!byKey.has(k)) byKey.set(k, e);
  });
  const { colors } = uniqueColors(raster);
  const labelled = colors.map((c) => ({ ...c, entry: byKey.get(c.key) })).filter((c) => c.entry);
  return {
    raster,
    colors,
    fg: labelled.filter((c) => c.entry.layer === 'fg'),
    bg: labelled.filter((c) => c.entry.layer === 'bg'),
  };
}

/** Smallest ΔE between any colour of one set and any colour of the other. */
function minCross(a, b) {
  let m = Infinity;
  for (const x of a) for (const y of b) m = Math.min(m, deltaEOK(x, y));
  return m;
}

test('context-aware recolouring rescues the fg/bg separation the blind path loses', () => {
  const pools = targetPools(target.entries);
  let blindCollapsed = 0;
  let contextCollapsed = 0;
  let cases = 0;

  for (const preset of ['neon-cyberpunk', 'sepia-western', 'pastel-cozy', 'c64']) {
    for (const sceneId of ['sprite-over-bg', 'combat', 'day-night', 'screenshot']) {
      const { raster, colors, fg, bg } = separationCase(sceneId, presetParams(preset));
      if (fg.length < 2 || bg.length < 2) continue;
      cases++;

      const blind = buildIndexedMapping(colors, target.entries, { match: 'delta-e' });
      // The oracle: each source colour's TRUE layer, so this measures the mapping and not
      // the inference. What the inference costs is a separate question (and a separate doc).
      const oracle = new Map();
      for (const c of fg) oracle.set(c.key, 'sprite');
      for (const c of bg) oracle.set(c.key, 'scenery');
      const ctx = buildIndexedMapping(colors, target.entries, {
        match: 'delta-e', contexts: oracle, pools, contextBias: 1,
      });

      const lab = (m) => (c) => target.entries[m.get(c.key)].lab;
      if (minCross(fg.map(lab(blind)), bg.map(lab(blind))) < 2) blindCollapsed++;
      if (minCross(fg.map(lab(ctx)), bg.map(lab(ctx))) < 2) contextCollapsed++;

      // No source foreground colour may land on a target background slot, or vice versa.
      for (const c of fg) assert.notEqual(target.entries[ctx.get(c.key)].layer, 'bg');
      for (const c of bg) assert.notEqual(target.entries[ctx.get(c.key)].layer, 'fg');
      assert.ok(raster.w > 0);
    }
  }

  assert.ok(cases >= 12, `expected a dozen or more measurable cases, got ${cases}`);
  // The blind path collapses the distinction on most of these; the context path on none.
  assert.equal(contextCollapsed, 0, 'context-aware recolouring collapsed fg/bg separation');
  assert.ok(blindCollapsed > cases / 2, 'the blind path was expected to collapse most cases');
});

// --- Integration -----------------------------------------------------------

test('recolorFrames decides context once across every frame', () => {
  const { img, backdrop } = subjectOnBackdrop();
  // A second frame where the backdrop is a minority of the picture. Decided per frame, its
  // context could change; decided across both, it cannot.
  const other = new Raster(img.w, img.h, [200, 90, 60]);
  for (let x = 0; x < img.w; x++) other.set(x, 0, backdrop);

  const frames = [{ image: img, delay: 10 }, { image: other, delay: 10 }];
  const out = recolorFrames(frames, target, { mode: 'indexed', recolorContext: 'suggest' });
  assert.equal(out.context.applied, true);
  assert.equal(out.frames.length, 2);

  const readBack = (frame, source) => {
    const idx = [];
    for (let p = 0; p < source.data.length; p += 3) {
      const src = (source.data[p] << 16) | (source.data[p + 1] << 8) | source.data[p + 2];
      if (src === keyOf(backdrop)) {
        idx.push((frame.data[p] << 16) | (frame.data[p + 1] << 8) | frame.data[p + 2]);
      }
    }
    return new Set(idx);
  };
  const a = readBack(out.frames[0].image, img);
  const b = readBack(out.frames[1].image, other);
  assert.equal(a.size, 1);
  assert.equal(b.size, 1);
  assert.deepEqual([...a], [...b], 'the backdrop took a different target in a different frame');
});

test('an external target palette falls back to the blind path instead of failing', () => {
  const { img } = subjectOnBackdrop();
  const strip = new Raster(6, 1, null);
  [[20, 20, 30], [90, 60, 50], [160, 120, 90], [210, 180, 140], [240, 230, 210], [255, 255, 255]]
    .forEach((c, i) => strip.set(i, 0, c));
  const ext = externalPalette('strip', extractPalette(strip));

  const on = recolorImage(img, ext, { mode: 'indexed', recolorContext: 'suggest' });
  const off = recolorImage(img, ext, { mode: 'indexed', recolorContext: 'off' });
  assert.equal(on.context.applied, false);
  for (const c of uniqueColors(img).colors) {
    assert.equal(on.mapping.get(c.key), off.mapping.get(c.key));
  }
});

test('remap_context_order off makes preserve_order win outright', () => {
  const { img } = subjectOnBackdrop();
  const withOrder = recolorImage(img, target, {
    mode: 'indexed', recolorContext: 'suggest', preserveOrder: true, contextOrder: false,
  });
  assert.equal(withOrder.context.applied, false, 'context should stand down');

  const combined = recolorImage(img, target, {
    mode: 'indexed', recolorContext: 'suggest', preserveOrder: true, contextOrder: true,
  });
  assert.equal(combined.context.applied, true);
  // Combining the two must still leave the mapping monotonic in lightness: walk the source
  // colours dark to light and the targets they claim must never step backwards.
  const bySourceL = colorSignals(img).sort((a, b) => a.L - b.L);
  assert.ok(bySourceL.length > 1);
  let prev = -Infinity;
  for (const s of bySourceL) {
    const L = target.entries[combined.mapping.get(s.key)].lab[0];
    assert.ok(L >= prev - 1e-9, 'preserve_order was violated while context was on');
    prev = L;
  }
});

test('the photo path ignores context rather than half-applying it', () => {
  const noisy = new Raster(40, 40, null);
  for (let y = 0; y < 40; y++) {
    for (let x = 0; x < 40; x++) noisy.set(x, y, [(x * 7) % 256, (y * 11) % 256, (x * y) % 256]);
  }
  const out = recolorImage(noisy, target, { mode: 'quantize', recolorContext: 'suggest' });
  assert.equal(out.mode, 'quantize');
  assert.equal(out.context, undefined, 'the quantize path reports no context decision');
});
