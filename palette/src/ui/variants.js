// The variant grid (UX_PLAN U3.2 — item 1). The single biggest reduction in twiddling.
//
// Finding a palette by sliders is an inverse problem: you know the look, and you have to work
// out which of 72 numbers produces it. Finding it by *picking* is not. The generator is pure
// and fast, so the honest answer to "what else could this be?" is a dozen palettes on screen,
// each one a variation of the one you have. Click the one that is closer to what you want and
// a fresh dozen are drawn around **it**: every click is a step of hill-climbing done by eye,
// with no parameter knowledge required at all.
//
// The first tile is always the current palette, so what you would be giving up is on screen
// beside what you would be getting. Strength decides how far the variations wander;
// "Surprise me" is the old uniform reroll, kept for the moment when you have nothing yet.

import { generatePalette, paletteHexes } from '../core/generate.js';
import { makeRng } from '../core/rng.js';
import { describePalette } from '../core/describe.js';
import { varyParams, randomizeParams, VARY_STRENGTHS } from './randomize.js';
import { stripElement, drawScene, drawContextMaps } from './strip.js';
import { fillSelect } from './dom.js';

const TILES = 11; // plus the current palette, which is always tile zero

// What a tile shows. The default is the **context colour-space maps** — one map per job
// (everything, sprites, scenery, sky, UI, FX) at the top saturation. A single scene only
// exercises the slots that scene happens to use, so comparing twelve palettes by one scene
// compares a fraction of each; the maps show every colour in every context it is allowed in.
// Only the fully saturated slice is drawn: four saturations × six contexts is twenty-four
// pictures per palette, which no tile can carry.
const VIEWS = [
  ['context', 'Context maps — every job, full saturation'],
  ['screenshot', 'Scene — screenshot'],
  ['parallax', 'Scene — landscape'],
  ['dungeon', 'Scene — dungeon'],
  ['sprite-over-bg', 'Scene — sprites on backgrounds'],
  ['ui-mockup', 'Scene — UI'],
  ['swatch-grid', 'Scene — swatches only'],
];

/**
 * Build the variants view. `dom` holds the grid container and its controls; `actions` supplies
 * `getState()` (the live `{ params, locks, overrides }`) and `onAdopt(params)`.
 * Returns `{ render(palette), setActive(on) }` — nothing is generated while the tab is hidden.
 */
export function createVariants(dom, { getState, onAdopt }) {
  let active = false;
  let dirty = true;
  let strength = 'moderate';
  let view = VIEWS[0][0];
  let counter = 0;
  let variants = []; // { params, palette, hexes }

  fillSelect(dom.strength, [
    ['subtle', 'Subtle variations'],
    ['moderate', 'Moderate variations'],
    ['wild', 'Wild variations'],
    ['surprise', 'Surprise me (full reroll)'],
  ]);
  fillSelect(dom.scene, VIEWS);

  /** Draw a fresh set of variations around the current parameters. */
  function build() {
    const state = getState();
    if (!state?.params) return;
    const opts = { locks: state.locks || {}, overrides: state.overrides || {} };
    counter += 1;
    variants = [];
    for (let i = 0; i < TILES; i++) {
      // Deterministic per (set, tile) so a redraw of the same set is the same set, but a new
      // press gives new candidates.
      const rng = makeRng((Math.imul(counter, 2654435761) ^ Math.imul(i + 1, 40503)) & 0xffff);
      const params = strength === 'surprise'
        ? randomizeParams(state.params, rng)
        : varyParams(state.params, rng, { strength });
      const palette = generatePalette(params, opts);
      variants.push({ params, palette, hexes: paletteHexes(palette) });
    }
    dirty = false;
  }

  /** Repaint the grid from `variants`, with the current palette pinned first. */
  function draw() {
    if (!active) return;
    const state = getState();
    if (!state?.params) return;
    if (dirty || !variants.length) build();

    dom.grid.innerHTML = '';
    const current = generatePalette(state.params, {
      locks: state.locks || {}, overrides: state.overrides || {},
    });
    dom.grid.appendChild(tile({
      palette: current,
      hexes: paletteHexes(current),
      params: state.params,
    }, { isCurrent: true }));
    for (const v of variants) dom.grid.appendChild(tile(v, { isCurrent: false }));
  }

  /** One clickable candidate. */
  function tile(v, { isCurrent }) {
    const el = document.createElement('div');
    el.className = `variant-tile${isCurrent ? ' is-current' : ''}`;
    const canvas = document.createElement('canvas');
    canvas.className = 'variant-scene';
    if (view === 'context') drawContextMaps(canvas, v.palette);
    else drawScene(canvas, v.palette, { scene: view });
    const strip = stripElement(v.hexes, { className: 'variant-strip' });
    const caption = document.createElement('div');
    caption.className = 'variant-caption';
    caption.textContent = isCurrent ? 'current' : describePalette(v.palette, v.params).split(' · ')[1] || 'variation';
    el.append(canvas, strip, caption);
    const described = describePalette(v.palette, v.params);
    el.title = view === 'context' && canvas.dataset.contexts
      ? `${described}\nMaps, left to right: ${canvas.dataset.contexts}`
      : described;
    if (!isCurrent) {
      el.addEventListener('click', () => {
        // Adopting re-centres the grid on the chosen palette: the next dozen are variations
        // of what you just picked, which is what makes repeated clicking a search.
        onAdopt(v.params);
        dirty = true;
        draw();
      });
    }
    return el;
  }

  dom.strength?.addEventListener('change', () => {
    strength = dom.strength.value;
    dirty = true;
    draw();
  });
  dom.scene?.addEventListener('change', () => { view = dom.scene.value; draw(); });
  dom.more?.addEventListener('click', () => { dirty = true; draw(); });

  return {
    /** A new palette invalidates the set — it was drawn around the previous one. */
    render() {
      dirty = true;
      if (active) draw();
    },
    /** Show or hide the view; nothing is generated while it is hidden. */
    setActive(on) {
      active = on;
      if (on) draw();
    },
    /** The strengths this view offers, for tests and for the start screen. */
    strengths: Object.keys(VARY_STRENGTHS),
  };
}

