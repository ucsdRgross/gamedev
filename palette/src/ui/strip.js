// Small palette pictures, shared by everything that shows a palette other than the main
// swatch grid (UX_PLAN U2.4): the hover previews under a slider, the colour-count sweep, the
// variant grid, the library and the compare view.
//
// Two ways to draw a palette small:
//   * a **strip** — every colour as a cell, in slot order. Says what is in the palette.
//   * a **thumbnail** — a real gallery scene rendered in it. Says what it looks like.
// Both are wanted: a strip is unambiguous, a scene is honest about how the colours interact.
//
// Scene rendering goes through the same `Raster` the gallery and the headless renderer use,
// so a thumbnail is a smaller version of the picture, not a different drawing.

import { Raster } from '../core/raster.js';
import { SCENE_BY_ID } from '../scenes/index.js';
import { buildContextMaps } from '../core/layout/colorspace.js';
import { contextThumbSheet } from '../core/layout/render.js';

/** The scene a thumbnail shows unless asked otherwise — a full mock screenshot. */
export const DEFAULT_THUMB_SCENE = 'screenshot';

/** A DOM strip of colour cells. Cheap enough to build a few dozen of. */
export function stripElement(hexes, { className = 'mini-strip', title = '' } = {}) {
  const el = document.createElement('div');
  el.className = className;
  if (title) el.title = title;
  for (const hex of hexes) {
    const cell = document.createElement('i');
    cell.style.background = hex;
    el.appendChild(cell);
  }
  return el;
}

/** Paint a palette onto a canvas as a strip of `cell`-wide columns. */
export function drawStrip(canvas, hexes, { cell = 6, height = 18 } = {}) {
  canvas.width = Math.max(1, hexes.length * cell);
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  hexes.forEach((hex, i) => {
    ctx.fillStyle = hex;
    ctx.fillRect(i * cell, 0, cell, height);
  });
  return canvas;
}

/** Render one gallery scene into a canvas at an integer zoom, nearest-neighbour. */
export function drawScene(canvas, palette, { scene = DEFAULT_THUMB_SCENE, zoom = 1, frame = 0 } = {}) {
  const def = SCENE_BY_ID.get(scene) || SCENE_BY_ID.get(DEFAULT_THUMB_SCENE);
  if (!def) return canvas;
  const raster = new Raster(def.width, def.height);
  def.render(raster, palette, { frame });
  const scaled = zoom > 1 ? raster.scaled(zoom) : raster;
  canvas.width = scaled.w;
  canvas.height = scaled.h;
  canvas.getContext('2d').putImageData(scaled.toImageData(ImageData), 0, 0);
  return canvas;
}

/** A ready-made scene thumbnail element for a palette. */
export function sceneThumb(palette, opts = {}) {
  const canvas = document.createElement('canvas');
  canvas.className = opts.className || 'mini-scene';
  return drawScene(canvas, palette, opts);
}

/** The default thumbnail map size — 2:1, the aspect a hue×lightness map is drawn at. */
export const CONTEXT_THUMB_SIZE = { w: 84, h: 42 };

/**
 * Paint the palette's **context colour-space maps** into a canvas: one map per context
 * (everything, sprites, scenery, sky, UI, FX) at the top saturation only.
 *
 * This is the honest thumbnail of a palette. A gallery scene shows a dozen slots doing one
 * job; these show every slot doing every job, and where a context is missing colour it shows
 * as a stretch of the map that only one swatch can reach. Four saturations per context would
 * be twenty-four pictures per palette, which is unreadable at tile size, so only the fully
 * saturated slice is drawn — the one that separates the hues most.
 *
 * Costs about 10 ms per palette at the default size, so a twelve-tile grid is ~125 ms: fine
 * to build when the grid is drawn, not something to run on every slider frame.
 */
export function drawContextMaps(canvas, palette, { size = CONTEXT_THUMB_SIZE, columns = 3 } = {}) {
  const maps = buildContextMaps(palette, { geometry: 'rect', saturations: [1], size });
  const sheet = contextThumbSheet(maps, palette, { columns });
  canvas.width = sheet.w;
  canvas.height = sheet.h;
  canvas.getContext('2d').putImageData(sheet.toImageData(ImageData), 0, 0);
  canvas.dataset.contexts = maps.map((m) => m.context.id).join(' · ');
  return canvas;
}

/** A ready-made context-map thumbnail element for a palette. */
export function contextThumb(palette, opts = {}) {
  const canvas = document.createElement('canvas');
  canvas.className = opts.className || 'mini-scene';
  return drawContextMaps(canvas, palette, opts);
}
