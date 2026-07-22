// The built-in reference images (PLAN §19.3/§19.4, task 5.9).
//
// These ship generated rather than as committed binaries (ARCHITECTURE §12.4), which is only
// safe if "generated" means "the same every time" — so determinism is asserted first. The
// rest of the file checks the set actually covers what it exists to cover: both recolour
// paths, and an animation of each kind.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { builtinSamples } from '../src/core/recolor/samples.js';
import { chooseMode, recolorFrames } from '../src/core/recolor/index.js';
import { countUniqueColors } from '../src/core/recolor/image.js';
import { decodeGif, encodeGif } from '../src/core/gif.js';
import { generatePalette } from '../src/core/generate.js';
import { rgb8ToHex } from '../src/core/oklch.js';

const samples = builtinSamples();
const byId = (id) => samples.find((s) => s.id === id);

test('the built-in samples are byte-identical every time they are generated', () => {
  const again = builtinSamples();
  assert.equal(again.length, samples.length);
  samples.forEach((s, i) => {
    assert.equal(again[i].id, s.id);
    assert.equal(again[i].frames.length, s.frames.length);
    s.frames.forEach((f, fi) => {
      assert.deepEqual([...again[i].frames[fi].image.data], [...f.image.data], `${s.id} frame ${fi}`);
    });
  });
});

test('the set covers both recolour paths and both kinds of animation', () => {
  const modes = samples.map((s) => ({ id: s.id, kind: s.kind, mode: chooseMode(s.frames[0].image).mode }));
  assert.ok(modes.some((m) => m.kind === 'still' && m.mode === 'indexed'), 'need flat pixel art');
  assert.ok(modes.some((m) => m.kind === 'still' && m.mode === 'quantize'), 'need a synthetic photograph');
  assert.ok(modes.some((m) => m.kind === 'animated' && m.mode === 'indexed'), 'need a flat animation');
  assert.ok(modes.some((m) => m.kind === 'animated' && m.mode === 'quantize'), 'need a smooth animation');

  for (const s of samples.filter((x) => x.kind === 'animated')) {
    assert.ok(s.frames.length > 1, `${s.id} is marked animated but has one frame`);
    for (const f of s.frames) assert.ok(f.delayMs > 0, `${s.id} has a frame with no delay`);
  }
});

test('the pixel-art samples are flat and the photographs are not', () => {
  assert.ok(countUniqueColors(byId('hero').frames[0].image) <= 32);
  assert.ok(countUniqueColors(byId('torch').frames[0].image) <= 32);
  assert.ok(countUniqueColors(byId('portrait').frames[0].image) > 256);
  assert.ok(countUniqueColors(byId('landscape').frames[0].image) > 256);
});

test('every sample recolours into the palette and nothing else', () => {
  const p = generatePalette({ color_count: 24 });
  const allowed = new Set(p.entries.map((e) => e.hex));
  for (const s of samples) {
    const out = recolorFrames(s.frames, p, {});
    assert.equal(out.frames.length, s.frames.length, s.id);
    for (const f of out.frames) {
      assert.equal(f.image.w, s.frames[0].image.w);
      for (let i = 0; i < f.image.data.length; i += 3) {
        const hex = rgb8ToHex([f.image.data[i], f.image.data[i + 1], f.image.data[i + 2]]);
        assert.ok(allowed.has(hex), `${s.id}: foreign colour ${hex}`);
      }
    }
  }
});

test('a recoloured animated sample writes a GIF that decodes back unchanged', () => {
  const p = generatePalette({ color_count: 16 });
  for (const s of samples.filter((x) => x.kind === 'animated')) {
    const out = recolorFrames(s.frames, p, {});
    const back = decodeGif(encodeGif(out.frames, p.entries.map((e) => e.rgb8)));
    assert.equal(back.frames.length, out.frames.length, s.id);
    assert.equal(back.width, s.frames[0].image.w);
    back.frames.forEach((f, i) => {
      assert.deepEqual([...f.image.data], [...out.frames[i].image.data], `${s.id} frame ${i}`);
    });
  }
});

test('every sample has a unique id and a human title', () => {
  assert.equal(new Set(samples.map((s) => s.id)).size, samples.length);
  for (const s of samples) {
    assert.match(s.id, /^[a-z][a-z0-9-]*$/);
    assert.ok(s.title.length > 3, `${s.id} needs a title`);
  }
});
