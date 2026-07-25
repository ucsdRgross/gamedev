// The Start tab (UX_PLAN U5.2, U5.4, U5.5, U5.6 — IMPROVEMENTS items 26, 27, 6, 11).
//
// Everything that answers "where does a palette come from?" on one page, as pictures.
//
// The tool's entry points were all *text*: a dropdown of preset names, a dropdown of save
// names, a seed field. Picking a starting point by reading nineteen names is the same problem
// the variant grid exists to solve one level down — you know roughly what you want to see and
// you are being asked to guess which word produces it. So presets, saves and the palettes you
// merely passed through are all shown as what they look like, and clicking one takes it.
//
// **Nothing here replaces anything.** The preset `<select>`, the saves `<select>`, the seed
// field and Fit to image all still work exactly as they did; this is a second door.
//
// Thumbnails cost a palette generation plus a scene render each, so the preset row — which
// never changes — is built once and kept, and nothing is built at all until the tab is shown.

import { generatePalette } from '../core/generate.js';
import { PRESETS, presetParams } from '../core/presets.js';
import { parseJson } from '../core/export/json.js';
import { parseHexList, hexListPalette } from '../core/hexlist.js';
import { describePalette } from '../core/describe.js';
import { stripElement, drawScene } from './strip.js';
import { loadRing } from './saves.js';

/**
 * Moods, and the preset each one means.
 *
 * A chip is not a new mechanism — it is the preset list indexed by what someone actually
 * arrives with. Nobody sits down wanting "Genesis"; they sit down wanting *cold*, or *cosy*,
 * or *horrible*. The preset names stay in their dropdown for the people who do know.
 */
const MOODS = [
  ['Cosy', 'pastel-cozy'],
  ['Cold', 'frozen-tundra'],
  ['Warm', 'sunset-desert'],
  ['Nocturnal', 'candlelit-dungeon'],
  ['Neon', 'neon-cyberpunk'],
  ['Sickly', 'toxic-swamp'],
  ['Grim', 'blood-moon'],
  ['Autumnal', 'autumn-forest'],
  ['Underwater', 'underwater-cave'],
  ['Overcast', 'overcast-coast'],
  ['Dusty', 'sepia-western'],
  ['Inky', 'monochrome-ink'],
  ['Retro', 'nes'],
];

/**
 * Build the Start tab. `actions` supplies:
 *   `applyParams(params, source)`, `loadJson(text)`, `loadSeed(str)`,
 *   `pickImage()`, `useAsTarget(palette)`, `fitTo(hexes)`, `onPicked()`.
 * `store` is the save store from `saves.js`.
 *
 * Returns `{ setActive(on), refresh() }`.
 */
export function createStart(dom, { store, actions }) {
  let active = false;
  let built = false;
  let pasted = [];

  /**
   * One clickable palette card: a scene in it, its colours, and what it is called.
   * `onCompare` (shift-click) sends it to the Compare view instead of loading it — the
   * ordinary question about a card you are hovering is "is this better than what I have?",
   * and taking it to find out loses what you had.
   */
  function card(palette, { title, subtitle = '', onClick, onCompare, onDelete } = {}) {
    const el = document.createElement('div');
    el.className = 'start-card';
    const canvas = document.createElement('canvas');
    canvas.className = 'start-card-scene';
    drawScene(canvas, palette, { scene: 'screenshot' });
    const strip = stripElement(palette.entries.map((e) => e.hex), { className: 'start-card-strip' });
    const name = document.createElement('div');
    name.className = 'start-card-name';
    name.textContent = title;
    el.append(canvas, strip, name);
    if (subtitle) {
      const sub = document.createElement('div');
      sub.className = 'start-card-sub';
      sub.textContent = subtitle;
      el.appendChild(sub);
    }
    el.title = describePalette(palette) + (onCompare ? '\nShift-click to compare against this instead of taking it.' : '');
    el.addEventListener('click', (e) => {
      if (onCompare && e.shiftKey) { onCompare(); return; }
      onClick();
    });
    if (onDelete) {
      const del = document.createElement('button');
      del.className = 'start-card-del';
      del.textContent = '×';
      del.title = `Delete “${title}”`;
      del.addEventListener('click', (e) => { e.stopPropagation(); onDelete(); });
      el.appendChild(del);
    }
    return el;
  }

  // ---- Moods -----------------------------------------------------------
  function buildMoods() {
    dom.moods.innerHTML = '';
    for (const [label, id] of MOODS) {
      const preset = PRESETS.find((p) => p.id === id);
      if (!preset) continue;
      const chip = document.createElement('button');
      chip.className = 'mood-chip';
      chip.textContent = label;
      chip.title = `Start from “${preset.name}” — then take a variation of it`;
      // A chip is a *starting* point, so it hands straight over to the variant grid: the
      // intended next move is picking, not reading the seventy-two knobs it just set.
      chip.addEventListener('click', () => {
        actions.applyParams(presetParams(id), `Mood “${label}”`);
        actions.onPicked?.('variants');
      });
      dom.moods.appendChild(chip);
    }
  }

  // ---- Presets (U5.4) --------------------------------------------------
  function buildPresets() {
    dom.presets.innerHTML = '';
    for (const preset of PRESETS) {
      const params = presetParams(preset.id);
      dom.presets.appendChild(card(generatePalette(params), {
        title: preset.name,
        onClick: () => actions.applyParams(params, `Preset “${preset.name}”`),
        onCompare: () => actions.compareWith(`preset:${preset.id}`),
      }));
    }
  }

  // ---- Kept palettes (U5.2) -------------------------------------------
  // A generation counter, because this is async and re-entrant: Keep triggers a rebuild while
  // the previous one is still reading files, and without the guard the in-flight run appends
  // its cards into the container the new run just cleared — every save shown twice.
  let savesRun = 0;

  async function buildSaves() {
    const run = ++savesRun;
    let names = [];
    try {
      names = await store.list();
    } catch {
      dom.savesNote.textContent = 'could not read the saves';
      return;
    }
    // Read in parallel: a library is a page you look at, not a queue you wait through.
    const loaded = await Promise.all(names.map(async (name) => {
      try { return { name, parsed: parseJson(await store.read(name)) }; } catch { return null; }
    }));
    if (run !== savesRun) return;
    dom.saves.innerHTML = '';
    dom.savesNote.textContent = names.length
      ? `${names.length} kept in ${store.where()}`
      : `nothing kept yet — press Keep and it lands in ${store.where()}`;
    for (const entry of loaded) {
      if (!entry) continue; // a save that will not parse is not worth a broken card
      const { name, parsed } = entry;
      dom.saves.appendChild(card(generatePalette(parsed.params, {
        locks: parsed.locks, overrides: parsed.overrides,
      }), {
        title: name,
        onClick: () => actions.loadSave(name),
        onCompare: () => actions.compareWith(`save:${name}`),
        onDelete: async () => {
          try { await store.remove(name); } catch { /* the rebuild below shows the truth */ }
          buildSaves();
        },
      }));
    }
  }

  // ---- Recently passed through (U5.3) ---------------------------------
  function buildRing() {
    const ring = loadRing();
    dom.recent.innerHTML = '';
    dom.recentWrap.hidden = ring.length === 0;
    if (!ring.length) return;
    for (const entry of ring) {
      let palette;
      try {
        palette = generatePalette(entry.params);
      } catch { continue; }
      dom.recent.appendChild(card(palette, {
        title: entry.name || 'untitled',
        subtitle: entry.at ? new Date(entry.at).toLocaleTimeString() : '',
        onClick: () => actions.loadSeed(entry.seed),
        onCompare: () => actions.compareWith(`seed:${entry.seed}`),
      }));
    }
  }

  // ---- Pasted colours (U5.6) ------------------------------------------
  function readPaste() {
    pasted = parseHexList(dom.pasteInput.value);
    dom.pastePreview.innerHTML = '';
    if (pasted.length) dom.pastePreview.appendChild(stripElement(pasted, { className: 'start-card-strip' }));
    dom.pasteNote.textContent = pasted.length
      ? `${pasted.length} colour${pasted.length === 1 ? '' : 's'} read`
      : 'paste hex codes in any format — Lospec, CSS, a comma-separated list';
    dom.pasteFit.disabled = pasted.length < 2;
    dom.pasteTarget.disabled = pasted.length < 1;
  }

  dom.pasteInput?.addEventListener('input', readPaste);
  dom.pasteFit?.addEventListener('click', () => {
    actions.fitTo(pasted);
    actions.onPicked?.('gallery');
  });
  dom.pasteTarget?.addEventListener('click', () => {
    actions.useAsTarget(hexListPalette('pasted colours', pasted));
    actions.onPicked?.('recolor');
  });
  dom.fromImage?.addEventListener('click', () => actions.pickImage());

  /** Rebuild everything that can change. Presets are built once — they never do. */
  function refresh() {
    if (!active) return;
    if (!built) {
      buildMoods();
      buildPresets();
      readPaste();
      built = true;
    }
    buildSaves();
    buildRing();
  }

  return {
    setActive(on) {
      active = on;
      if (on) refresh();
    },
    refresh,
  };
}
