// Scene smoke tests: every scene must render into its declared surface without throwing
// or producing NaN, for palettes across the whole size range and every preset. The
// gallery gate is visual, but this catches crashes and role-lookup gaps mechanically.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SCENES, SCENE_BY_ID, CATEGORIES } from '../src/scenes/index.js';
import { Raster } from '../src/core/raster.js';
import { generatePalette } from '../src/core/generate.js';
import { PRESETS } from '../src/core/presets.js';

/** Render a scene into a fresh surface and assert every pixel is a valid byte. */
function renderOk(scene, palette, frame = 0) {
  const surface = new Raster(scene.width, scene.height);
  scene.render(surface, palette, { frame });
  for (let i = 0; i < surface.data.length; i++) {
    const v = surface.data[i];
    assert.ok(Number.isFinite(v) && v >= 0 && v <= 255, `${scene.id}: bad pixel value ${v}`);
  }
  return surface;
}

test('the registry has 34 scenes with unique ids and valid dimensions', () => {
  assert.equal(SCENES.length, 34);
  assert.equal(SCENE_BY_ID.size, 34);
  assert.ok(CATEGORIES.length >= 6);
  for (const s of SCENES) {
    assert.ok(typeof s.render === 'function', `${s.id} has a render fn`);
    assert.ok(s.width > 0 && s.height > 0, `${s.id} has positive dimensions`);
    assert.ok(s.title && s.category, `${s.id} has title and category`);
  }
});

test('every scene renders across the palette size range', () => {
  for (const K of [4, 8, 16, 32, 48, 64]) {
    const palette = generatePalette({ color_count: K });
    for (const scene of SCENES) renderOk(scene, palette);
  }
});

test('every scene renders for every preset', () => {
  for (const preset of PRESETS) {
    const palette = generatePalette(preset.params);
    for (const scene of SCENES) renderOk(scene, palette);
  }
});

test('animated scenes render every frame of their loop', () => {
  const palette = generatePalette({ color_count: 32 });
  for (const scene of SCENES.filter((s) => s.animated)) {
    assert.ok(scene.frames >= 1);
    for (let f = 0; f < scene.frames; f++) renderOk(scene, palette, f);
  }
});

test('a scene actually draws something (not a blank surface)', () => {
  const palette = generatePalette({ color_count: 32 });
  for (const scene of SCENES) {
    const surface = renderOk(scene, palette);
    const first = [surface.data[0], surface.data[1], surface.data[2]].join(',');
    let varied = false;
    for (let i = 3; i < surface.data.length; i += 3) {
      if ([surface.data[i], surface.data[i + 1], surface.data[i + 2]].join(',') !== first) { varied = true; break; }
    }
    assert.ok(varied, `${scene.id} rendered a flat surface`);
  }
});
