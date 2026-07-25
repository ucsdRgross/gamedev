// The pinned hero (UX_PLAN U4.1 and U4.3 — IMPROVEMENTS items 4 and 18/19).
//
// The gallery is thirty-six scenes in a scrolling grid, which means that the moment you
// scroll to the scene you care about you are looking at *one* thing, and the moment you
// scroll back to the sliders you are looking at none of it. Tuning a palette is a loop of
// "move a knob, look at the picture"; if the picture leaves the screen every time you move
// the knob, the loop is broken and the tool is answering the wrong question.
//
// So one picture is pinned above the grid and never scrolls away. Two, in fact:
//
//   * a **scene** — a composed mockup by default, since that is the closest thing here to
//     the picture the palette is for;
//   * a row of **real reference art**, recoloured live into the palette. A generated scene
//     is drawn by code that knows the palette's semantic roles and so is quietly generous to
//     it; a real illustration is not, and it is the honest test of whether the colours work.
//
// Everything here is coalesced onto one animation frame, because this repaints on every
// slider frame. The art row asks the recolour gallery for its decoded frames rather than
// fetching for itself — see `listSources`/`framesFor` there.

import { Raster } from '../core/raster.js';
import { applyViewSpec } from '../core/analysis.js';
import { SCENES, SCENE_BY_ID } from '../scenes/index.js';
import { recolorFrames } from '../core/recolor/index.js';
import { recolorOptions } from './recolor.js';

/** What the hero opens on: the crowded world mockup, the scene closest to a real screen. */
const DEFAULT_SCENE = 'world-screen';

/** The reference images pinned before anyone chooses: small, built-in, always present. */
const DEFAULT_ART = ['hero', 'tiles'];

const PREFS_KEY = 'palette.hero.v1';

/**
 * Build the pinned hero. `dom` holds the block and its controls; `refs` is the recolour
 * gallery's library accessors, or null when there is no library to draw from.
 *
 * Returns `{ render(palette, params), setActive(on) }`.
 */
export function createHero(dom, { refs } = {}) {
  let palette = null;
  let params = {};
  let active = true;
  let pending = false;
  let scene = DEFAULT_SCENE;
  let zoom = 2;
  let art = [...DEFAULT_ART];
  let showOriginal = true;
  let collapsed = false;
  // `art` is the *wish list* — what the user asked to see, persisted across reloads. `loaded`
  // is what is actually here. They differ because the reference library arrives in stages:
  // the built-ins are there at once and the folder listing is a fetch, so at first paint a
  // pin on a folder image names an id the library has never heard of. Rendering from `loaded`
  // (plus whatever is in flight) rather than pruning `art` is what lets that pin survive the
  // gap and appear when its image turns up.
  const loaded = new Map(); // id -> { frames, title }
  const loading = new Set(); // ids being fetched right now
  const cards = new Map(); // id -> the canvases showing it

  restorePrefs();

  // Scene selector: every gallery scene, grouped by category so the mockups lead.
  if (dom.scene) {
    dom.scene.innerHTML = '';
    let group = null;
    for (const s of SCENES) {
      if (!group || group.label !== s.category) {
        group = document.createElement('optgroup');
        group.label = s.category;
        dom.scene.appendChild(group);
      }
      const o = document.createElement('option');
      o.value = s.id;
      o.textContent = s.title;
      group.appendChild(o);
    }
    dom.scene.value = SCENE_BY_ID.has(scene) ? scene : DEFAULT_SCENE;
    scene = dom.scene.value;
  }
  if (dom.zoom) dom.zoom.value = String(zoom);
  if (dom.original) dom.original.checked = showOriginal;

  /**
   * Repaint everything, coalesced to about one frame.
   *
   * A timeout rather than `requestAnimationFrame`, for the same reason the recolour gallery
   * uses one: rAF does not fire at all while the page is not being composited, so under
   * headless verification — and in a backgrounded tab — the hero would silently never paint,
   * and "the picture that is always on screen" would be the one picture that is blank.
   */
  function schedule() {
    if (pending || !active || collapsed) return;
    pending = true;
    setTimeout(() => { pending = false; draw(); }, 16);
  }

  /** Paint the pinned scene and every pinned reference image. */
  function draw() {
    if (!palette || !active || collapsed) return;
    drawScene();
    for (const id of cards.keys()) drawArt(id);
  }

  /** The pins that have something to show: loaded, or on their way. */
  function shownArt() {
    return art.filter((id) => loaded.has(id) || loading.has(id));
  }

  /** The pinned scene, in the gallery's current colour-vision view. */
  function drawScene() {
    const def = SCENE_BY_ID.get(scene) || SCENE_BY_ID.get(DEFAULT_SCENE);
    if (!def || !dom.canvas) return;
    const raster = new Raster(def.width, def.height);
    def.render(raster, palette, { frame: 0 });
    const viewed = applyViewSpec(raster, dom.view?.value || 'color');
    const scaled = zoom > 1 ? viewed.scaled(zoom) : viewed;
    dom.canvas.width = scaled.w;
    dom.canvas.height = scaled.h;
    dom.canvas.getContext('2d').putImageData(scaled.toImageData(ImageData), 0, 0);
    dom.canvas.title = `${def.title} — pinned, so it never scrolls away while you tune`;
  }

  /** One reference image: the original beside the same image recoloured into the palette. */
  function drawArt(id) {
    const entry = loaded.get(id);
    const card = cards.get(id);
    if (!entry || !card) return;
    // Only the first frame. The hero is a still reference that repaints on every slider
    // frame; recolouring a 189-frame GIF at that rate is not a preview, it is a stall.
    const frame = entry.frames[0];
    if (!frame) return;
    const result = recolorFrames([frame], palette, recolorOptions(params));
    paint(card.after, result.frames[0].image);
    card.before.hidden = !showOriginal;
    if (showOriginal) paint(card.before, frame.image);
    card.el.title = `${entry.title} — ${result.unique} colours, ${result.mode}. Click to unpin.`;
  }

  function paint(canvas, raster) {
    canvas.width = raster.w;
    canvas.height = raster.h;
    canvas.getContext('2d').putImageData(raster.toImageData(ImageData), 0, 0);
  }

  /** Build the card shells for the pinned set, dropping any that were unpinned. */
  function rebuildArt() {
    if (!dom.artRow) return;
    dom.artRow.innerHTML = '';
    cards.clear();
    const shown = shownArt();
    for (const id of shown) {
      const el = document.createElement('div');
      el.className = 'hero-art';
      const before = document.createElement('canvas');
      before.className = 'hero-art-canvas is-before';
      const after = document.createElement('canvas');
      after.className = 'hero-art-canvas';
      const label = document.createElement('span');
      label.className = 'hero-art-label';
      label.textContent = loaded.get(id)?.title ?? 'loading…';
      el.append(before, after, label);
      el.addEventListener('click', () => unpin(id));
      dom.artRow.appendChild(el);
      cards.set(id, { el, before, after });
    }
    dom.artRow.hidden = shown.length === 0;
  }

  /** Pin one reference image, loading it if this is the first time it has been asked for. */
  async function pin(id) {
    if (!id || art.includes(id) || !refs) return;
    art = [...art, id];
    savePrefs();
    // Started before the first rebuild, not after: `load` marks the id as in flight
    // synchronously, which is what puts a "loading…" slot on screen straight away. A 512×512
    // GIF takes over a second to decode, and a click with no visible effect reads as broken.
    const decoding = load(id);
    rebuildArt();
    await decoding;
    rebuildArt();
    schedule();
  }

  function unpin(id) {
    art = art.filter((a) => a !== id);
    savePrefs();
    rebuildArt();
    schedule();
  }

  /** Fetch and decode one reference image through the recolour gallery's library. */
  async function load(id) {
    if (loaded.has(id) || loading.has(id) || !refs) return;
    loading.add(id);
    try {
      const title = refs.listSources().find((s) => s.id === id)?.title ?? id;
      loaded.set(id, { frames: await refs.framesFor(id), title });
    } catch {
      // A reference that will not decode is genuinely gone, so drop the pin rather than
      // leave a slot that retries on every library change.
      art = art.filter((a) => a !== id);
      savePrefs();
    } finally {
      loading.delete(id);
    }
  }

  // The library arrives asynchronously (the folder listing is a fetch), so the selector is
  // filled from a callback rather than read once at boot — and a pin is only *loaded* once
  // the library admits to having it. Pins it has never heard of are left alone: on the first
  // callback that is every folder image, and dropping them there would mean a pinned
  // illustration never survived a reload.
  refs?.onSourcesChange((sources) => {
    if (dom.art) {
      dom.art.innerHTML = '';
      const head = document.createElement('option');
      head.value = '';
      head.textContent = `Pin reference art… (${sources.length})`;
      dom.art.appendChild(head);
      for (const s of sources) {
        const o = document.createElement('option');
        o.value = s.id;
        o.textContent = s.title;
        dom.art.appendChild(o);
      }
    }
    const known = new Set(sources.map((s) => s.id));
    const wanted = art.filter((id) => known.has(id) && !loaded.has(id) && !loading.has(id));
    if (!wanted.length) return;
    rebuildArt();
    Promise.all(wanted.map(load)).then(() => { rebuildArt(); schedule(); });
  });

  dom.scene?.addEventListener('change', () => { scene = dom.scene.value; savePrefs(); schedule(); });
  dom.zoom?.addEventListener('change', () => { zoom = Number(dom.zoom.value); savePrefs(); schedule(); });
  dom.view?.addEventListener('change', schedule);
  dom.original?.addEventListener('change', () => {
    showOriginal = dom.original.checked;
    savePrefs();
    schedule();
  });
  dom.art?.addEventListener('change', () => {
    const id = dom.art.value;
    dom.art.value = '';
    pin(id);
  });
  dom.collapse?.addEventListener('click', () => {
    collapsed = !collapsed;
    applyCollapsed();
    savePrefs();
    schedule();
  });

  /** Show or hide the pinned pictures without losing what is pinned. */
  function applyCollapsed() {
    if (dom.body) dom.body.hidden = collapsed;
    if (!dom.collapse) return;
    dom.collapse.textContent = collapsed ? 'Show' : 'Hide';
    dom.collapse.title = collapsed
      ? 'Show the pinned pictures again'
      : 'Hide the pinned pictures and give the whole pane to the gallery';
  }
  applyCollapsed();

  function savePrefs() {
    try {
      localStorage.setItem(PREFS_KEY, JSON.stringify({ scene, zoom, art, showOriginal, collapsed }));
    } catch { /* blocked or full: the hero just forgets between sessions */ }
  }

  function restorePrefs() {
    try {
      const saved = JSON.parse(localStorage.getItem(PREFS_KEY) || 'null');
      if (!saved) return;
      if (typeof saved.scene === 'string' && SCENE_BY_ID.has(saved.scene)) scene = saved.scene;
      if (Number.isFinite(saved.zoom)) zoom = Math.min(4, Math.max(1, saved.zoom));
      if (Array.isArray(saved.art)) art = saved.art.filter((a) => typeof a === 'string');
      if (typeof saved.showOriginal === 'boolean') showOriginal = saved.showOriginal;
      if (typeof saved.collapsed === 'boolean') collapsed = saved.collapsed;
    } catch { /* unusable store: open on the defaults */ }
  }

  return {
    /** A new palette: repaint on the next frame. */
    render(nextPalette, nextParams) {
      palette = nextPalette;
      params = nextParams || params;
      schedule();
    },
    /** The hero belongs to the Gallery tab; it costs nothing while another tab is up. */
    setActive(on) {
      active = on;
      if (dom.root) dom.root.hidden = !on;
      if (on) schedule();
    },
  };
}
