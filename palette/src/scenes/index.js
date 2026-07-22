// Scene registry (PLAN §7, §8). Each scene is `{ id, title, category, width, height,
// render(surface, palette, opts) }`, optionally `{ animated, frames }`. Scenes are pure
// and DOM-free: they draw into a Raster and address colours through semantic roles, so
// they run identically in the browser gallery and the headless renderer.

import { structureScenes } from './structure.js';
import { formScenes } from './form.js';
import { spriteScenes } from './sprites.js';
import { worldScenes } from './worlds.js';
import { uiScenes } from './ui.js';
import { gradientScenes } from './gradients.js';
import { motionScenes } from './motion.js';
import { benchmarkScenes } from './benchmark.js';

/** Every gallery scene, in display order. */
export const SCENES = [
  ...structureScenes,
  ...formScenes,
  ...spriteScenes,
  ...worldScenes,
  ...uiScenes,
  ...gradientScenes,
  ...motionScenes,
  ...benchmarkScenes,
];

/** Scenes looked up by id. */
export const SCENE_BY_ID = new Map(SCENES.map((s) => [s.id, s]));

/** Distinct category names in registry order, for the gallery filter bar. */
export const CATEGORIES = [...new Set(SCENES.map((s) => s.category))];
