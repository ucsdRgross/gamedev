// The artist's-palette picker (PLAN §9). Two families of view, and the difference between
// them is the point rather than an implementation detail (ARCHITECTURE §11):
//
//   * **Colour-space maps** (§9.1, the default) — a standard HSL picker geometry with every
//     pixel painted its nearest palette colour. Position is fixed, so you always know where
//     to look, but a colour can fail to be anybody's nearest and go unshown. The coverage
//     count is on screen for that reason.
//   * **Arrangement layouts** (§9.2) — fifteen spatial optimisations that guarantee every
//     colour appears with a controlled area, at the cost of moving when the palette changes.
//
// Both render to a label buffer plus pixels, so hover, click-to-copy and PNG export are one
// code path over `pickAt` no matter which view is showing. The maths is all in
// `src/core/layout/`, so what is drawn here is pixel-for-pixel what `npm run render` writes.
//
// Building a layout costs tens of milliseconds and the contact sheet builds all fifteen, so
// work is deferred: nothing is rebuilt while the picker tab is hidden, and the current view
// is cached until the palette or its own controls actually change.

import { VARIANTS, buildLayout, rankLayouts } from '../core/layout/index.js';
import { BLOB_MODES } from '../core/layout/score.js';
import { buildContextMaps, buildMapSlices, mapFidelity } from '../core/layout/colorspace.js';
import {
  EDGE_MODES, contactSheet, contextSheet, mapSheet, renderLayout, pickAt,
} from '../core/layout/render.js';
import { encodePngRgb } from '../core/export/png.js';
import { download } from './io.js';

const BLOB_LABELS = {
  isolation: 'Perceptual isolation',
  equal: 'Equal area',
  role: 'Role importance',
  usage: 'Scene usage',
  chroma: 'Chroma',
};
const EDGE_LABELS = { none: 'No outline', shade: 'Hue-shifted shade', seam: 'Dark seam' };

/** The view selector. Maps come first because they are the default (PLAN §9.1). */
const VIEWS = [
  ['map-rect', 'Map — hue × lightness'],
  ['map-polar', 'Map — colour wheel'],
  ['map-context', 'Map — by context (sprites, scenery, UI…)'],
  ['layout', 'Arrangement layout'],
];

// The by-context sheet draws one map per context per saturation, so its tiles are smaller than
// the two-column default view — otherwise six rows of full-size maps is a very tall sheet.
const CONTEXT_MAP_SIZE = { w: 168, h: 84 };

const EXPORT_SCALE = 12; // high-resolution layout export: 12 output pixels per cell

// A layout can only be exported bigger by scaling its cells up; a map is a continuous
// function, so it is exported by *sampling it finer* — twice the on-screen resolution, with
// edges that are genuinely sharper rather than blockier. Kept to 2× because `export/png.js`
// writes stored DEFLATE blocks (ARCHITECTURE §2), so a sheet costs about w×h×3 bytes.
const MAP_EXPORT_SIZE = { rect: { w: 768, h: 384 }, polar: { w: 480, h: 480 } };

/**
 * Build the picker. `dom` holds the canvas and its controls. Returns `{ render(palette) }`
 * for the app to call after every regeneration, and `{ setActive(bool) }` so it can skip
 * all work while the tab is hidden.
 */
export function createPicker(dom, { getUsage }) {
  let palette = null;
  let rendered = null;
  let active = false;
  let dirty = true;
  let view = VIEWS[0][0];
  let variant = VARIANTS[0].id;
  let blobMode = 'isolation';
  let edges = 'none';
  let scale = 6;

  fillSelect(dom.view, VIEWS);
  fillSelect(dom.variant, VARIANTS.map((v) => [v.id, `${v.n}. ${v.title}`]));
  fillSelect(dom.blob, BLOB_MODES.map((m) => [m, BLOB_LABELS[m]]));
  fillSelect(dom.edges, EDGE_MODES.map((m) => [m, EDGE_LABELS[m]]));

  /** Rebuild the current view if anything it depends on has changed. */
  function ensureRendered() {
    if (!palette || (!dirty && rendered)) return rendered;
    if (view === 'layout') rendered = buildLayoutView();
    else if (view === 'map-context') rendered = buildContextView();
    else rendered = buildMapView();
    dirty = false;
    return rendered;
  }

  /** One hue×lightness map per context, so each answers "what may I use for this job". */
  function buildContextView() {
    const maps = buildContextMaps(palette, { geometry: 'rect', size: CONTEXT_MAP_SIZE });
    const out = contextSheet(maps, palette);
    out.status = `${maps.length} contexts · `
      + maps.map((m) => `${m.context.id} ${m.shownCount}/${m.total}`).join(' · ');
    return out;
  }

  /** The default view: every saturation slice of one geometry, plus what none of them reach. */
  function buildMapView() {
    const set = buildMapSlices(palette, { geometry: view === 'map-polar' ? 'polar' : 'rect' });
    const out = mapSheet(set, palette, { columns: 2 });
    const fidelity = set.slices.reduce((a, s) => a + mapFidelity(s, palette), 0) / set.slices.length;
    out.status = `shows ${set.shownCount}/${set.total} across ${set.slices.length} slices`
      + ` · per slice ${set.slices.map((s) => s.shownCount).join('/')}`
      + ` · mean ΔE ${fidelity.toFixed(1)}`
      + (set.missing.length ? ` · ${set.missing.length} only in the strip` : '');
    return out;
  }

  /** The optimizer's view: one arrangement variant, with its objective score. */
  function buildLayoutView() {
    const layout = buildLayout(palette, { variant, blobMode, usage: getUsage?.() ?? null });
    const out = renderLayout(layout, palette, { scale, edges });
    out.layout = layout;
    out.status = `mean ΔE ${layout.score.mean.toFixed(2)} · worst ${layout.score.worst.toFixed(1)}`
      + ` · ${(layout.score.crossings * 100).toFixed(0)}% edges cross`
      + (layout.optimized ? '' : ' · structural');
    return out;
  }

  /** Repaint the canvas and the status readout. */
  function draw() {
    if (!active || !palette) return;
    const r = ensureRendered();
    dom.canvas.width = r.w;
    dom.canvas.height = r.h;
    dom.canvas.getContext('2d').putImageData(r.raster.toImageData(ImageData), 0, 0);
    dom.score.textContent = r.status;
  }

  /** Which entry is under a pointer event, or null. Reads the rendered label map, so the
   *  readout matches what is on screen — the smoothed blob shape, or the map's exact edge. */
  function entryAt(event) {
    if (!rendered || !palette) return null;
    const rect = dom.canvas.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * rendered.w;
    const y = ((event.clientY - rect.top) / rect.height) * rendered.h;
    const index = pickAt(rendered, x, y);
    return index >= 0 ? palette.entries[index] : null;
  }

  /** Clear the hover readout back to its resting state. */
  function clearReadout() {
    dom.readout.textContent = '';
    dom.swatch.style.background = 'transparent';
  }

  dom.canvas.addEventListener('mousemove', (e) => {
    const entry = entryAt(e);
    if (!entry) {
      clearReadout();
      return;
    }
    const { L, C, h } = entry.actual;
    dom.readout.textContent = `${entry.role} · ${entry.hex} · L ${L.toFixed(3)} C ${C.toFixed(3)} h ${h.toFixed(0)}°`;
    dom.swatch.style.background = entry.hex;
  });
  dom.canvas.addEventListener('mouseleave', clearReadout);

  dom.canvas.addEventListener('click', async (e) => {
    const entry = entryAt(e);
    if (!entry) return;
    try {
      await navigator.clipboard.writeText(entry.hex);
      dom.readout.textContent = `copied ${entry.hex}`;
    } catch {
      dom.readout.textContent = `${entry.hex} (clipboard blocked)`;
    }
  });

  dom.view.addEventListener('change', () => {
    view = dom.view.value;
    dom.layoutControls.hidden = view !== 'layout';
    dirty = true;
    draw();
  });
  dom.variant.addEventListener('change', () => { variant = dom.variant.value; dirty = true; draw(); });
  dom.blob.addEventListener('change', () => { blobMode = dom.blob.value; dirty = true; draw(); });
  dom.edges.addEventListener('change', () => { edges = dom.edges.value; dirty = true; draw(); });
  dom.scale.addEventListener('change', () => { scale = Number(dom.scale.value); dirty = true; draw(); });

  dom.exportPng.addEventListener('click', () => {
    if (!palette) return;
    if (view === 'layout') {
      const out = renderLayout(buildLayout(palette, { variant, blobMode, usage: getUsage?.() ?? null }), palette, { scale: EXPORT_SCALE, edges });
      savePng(`palette-${variant}`, out.raster);
      return;
    }
    if (view === 'map-context') {
      // Maps are continuous, so the export samples finer rather than scaling pixels up.
      const maps = buildContextMaps(palette, {
        geometry: 'rect',
        size: { w: CONTEXT_MAP_SIZE.w * 2, h: CONTEXT_MAP_SIZE.h * 2 },
      });
      savePng('palette-map-context', contextSheet(maps, palette).raster);
      return;
    }
    const geometry = view === 'map-polar' ? 'polar' : 'rect';
    const set = buildMapSlices(palette, { geometry, size: MAP_EXPORT_SIZE[geometry] });
    savePng(`palette-map-${geometry}`, mapSheet(set, palette, { columns: 2 }).raster);
  });

  dom.exportSheet.addEventListener('click', () => {
    if (!palette) return;
    dom.score.textContent = 'building all fifteen layouts…';
    // Yield so the message paints before the (blocking) build starts. A timeout, not
    // requestAnimationFrame: rAF is paused in a backgrounded tab, and an export that
    // silently never happens is worse than one that skips a frame of feedback.
    setTimeout(() => {
      const sheet = contactSheet(rankLayouts(palette, { blobMode, usage: getUsage?.() ?? null }), palette, { scale: 3, edges });
      savePng('palette-layouts-sheet', sheet);
      draw();
    });
  });

  /** Note a new palette; the rebuild waits until the picker is actually on screen. */
  function render(next) {
    palette = next;
    dirty = true;
    draw();
  }

  /** Show or hide the picker; becoming visible triggers the deferred rebuild. */
  function setActive(on) {
    active = on;
    if (on) draw();
  }

  return { render, setActive };
}

/** Fill a `<select>` from `[value, label]` pairs. */
function fillSelect(el, pairs) {
  el.innerHTML = '';
  for (const [value, label] of pairs) {
    const o = document.createElement('option');
    o.value = value;
    o.textContent = label;
    el.appendChild(o);
  }
}

/** Encode a Raster as a PNG and hand it to the browser as a download. */
function savePng(name, raster) {
  download(`${name}.png`, encodePngRgb(raster.w, raster.h, raster.data), 'image/png', true);
}
