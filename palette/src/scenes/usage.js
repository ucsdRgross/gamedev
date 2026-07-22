// How much each palette colour actually gets used, measured by rendering the gallery and
// counting pixels. This is what backs the picker's `usage` blob-sizing mode (PLAN §9):
// the colours you reach for most often get the biggest targets to aim at.
//
// It lives here rather than in `src/core/layout/` because `src/core/` may not import
// `src/scenes/` — core owns colour, scenes own pictures. The picker takes the counts as
// data, so the layering holds and the layout code stays testable without any scene.

import { Raster } from '../core/raster.js';
import { SCENES } from './index.js';

// Only the scenes that depict something. The structure and dither categories are
// diagnostics — a swatch grid uses every colour exactly equally, which would flatten the
// measurement into the `equal` mode and tell the picker nothing.
const USAGE_CATEGORIES = new Set(['Form', 'Sprites', 'Scenes', 'UI', 'Motion']);

/** Per-entry pixel counts across the depictive gallery scenes, in palette order. */
export function sceneUsage(palette) {
  const byColor = new Map();
  palette.entries.forEach((e, i) => {
    const key = (e.rgb8[0] << 16) | (e.rgb8[1] << 8) | e.rgb8[2];
    if (!byColor.has(key)) byColor.set(key, i); // duplicate hexes credit the first slot
  });

  const counts = new Int32Array(palette.entries.length);
  for (const scene of SCENES) {
    if (!USAGE_CATEGORIES.has(scene.category)) continue;
    const r = new Raster(scene.width, scene.height);
    scene.render(r, palette, { frame: 0 });
    for (let p = 0; p < r.data.length; p += 3) {
      const key = (r.data[p] << 16) | (r.data[p + 1] << 8) | r.data[p + 2];
      const slot = byColor.get(key);
      if (slot !== undefined) counts[slot]++;
    }
  }
  return counts;
}
