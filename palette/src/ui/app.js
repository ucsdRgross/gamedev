// Application orchestrator (PLAN §12). Holds the single source of UI state —
// { params, locks, overrides } — regenerates the palette live on any change, and wires
// the sliders, swatch grid, history strip and I/O panel together.
//
// This is the only browser-only module that drives the DOM directly. All colour work is
// delegated to src/core, so the same generator the tests exercise runs here unchanged.

import { generatePalette } from '../core/generate.js';
import { PARAMS, defaultParams, normalizeParams, coerceParam, PARAM_BY_NAME } from '../core/params.js';
import { decodeSeed } from '../core/seed.js';
import { presetParams } from '../core/presets.js';
import { parseJson } from '../core/export/json.js';
import { makeRng, rngRange, rngInt, rngPick } from '../core/rng.js';
import { createSliders } from './sliders.js';
import { createSwatches } from './swatches.js';
import { createHistory, cloneState } from './history.js';
import { createIO, readSeedFromHash } from './io.js';
import { createGallery } from './gallery.js';
import { createPicker } from './picker.js';
import { createRecolorGallery } from './recolor.js';
import { sceneUsage } from '../scenes/usage.js';

// Randomize varies the palette's look but leaves structure, hardware and quality alone,
// so the swatch grid stays stable (locked colours keep their slots) and stays valid.
const RANDOMIZE_SKIP = new Set([
  'color_count', 'fg_ramp_length', 'bg_ramp_length',
  'bits_r', 'bits_g', 'bits_b', 'quantize_mode', 'gamut_map_mode',
  'min_delta_e', 'min_anchor_contrast', 'force_unique_hex', 'dither_evenness',
]);

/** Draw a random in-range value for one parameter spec. */
function randomValue(spec, rng) {
  if (spec.type === 'bool') return rng() < 0.5;
  if (spec.type === 'enum') return rngPick(rng, spec.options);
  if (spec.type === 'int') return rngInt(rng, spec.min, spec.max);
  return coerceParam(spec, rngRange(rng, spec.min, spec.max));
}

function boot() {
  const $ = (id) => document.getElementById(id);
  const dom = {
    params: $('params'),
    swatches: $('swatches'),
    history: $('history'),
    warnings: $('warnings'),
    meta: $('palette-meta'),
    seedInput: $('seed-input'),
    seedCopy: $('seed-copy'),
    undo: $('undo'),
    redo: $('redo'),
    randomize: $('randomize'),
    resetDefaults: $('reset-defaults'),
    presetSelect: $('preset-select'),
    savesSelect: $('saves-select'),
    saveName: $('save-name'),
    saveBtn: $('save-btn'),
    saveDelete: $('save-delete'),
    savesStatus: $('saves-status'),
    exportButtons: $('export-buttons'),
    exportStatus: $('export-status'),
    importFile: $('import-file'),
    importStatus: $('import-status'),
    gallery: $('gallery'),
    galleryCategory: $('gallery-category'),
    galleryView: $('gallery-view'),
    galleryZoom: $('gallery-zoom'),
    galleryAnimate: $('gallery-animate'),
    galleryControls: $('gallery-controls'),
    tabGallery: $('tab-gallery'),
    tabPicker: $('tab-picker'),
    picker: $('picker'),
    pickerControls: $('picker-controls'),
    pickerCanvas: $('picker-canvas'),
    pickerView: $('picker-view'),
    pickerLayoutControls: $('picker-layout-controls'),
    pickerVariant: $('picker-variant'),
    pickerBlob: $('picker-blob'),
    pickerEdges: $('picker-edges'),
    pickerScale: $('picker-scale'),
    pickerExport: $('picker-export'),
    pickerSheet: $('picker-sheet'),
    pickerReadout: $('picker-readout'),
    pickerSwatch: $('picker-swatch'),
    pickerScore: $('picker-score'),
    tabRecolor: $('tab-recolor'),
    recolor: $('recolor'),
    recolorControls: $('recolor-controls'),
    recolorList: $('recolor-list'),
    recolorZoom: $('recolor-zoom'),
    recolorPicker: $('recolor-picker'),
    recolorRescan: $('recolor-rescan'),
    recolorStatus: $('recolor-status'),
    recolorPersistNote: $('recolor-persist-note'),
  };

  // ---- State ----------------------------------------------------------
  let state = { params: defaultParams(), locks: {}, overrides: {} };
  let palette = null;
  let randomCounter = 0;

  // Seed the initial state from the URL hash, if present.
  const hashSeed = readSeedFromHash();
  if (hashSeed) {
    try {
      const decoded = decodeSeed(hashSeed);
      state = { params: decoded.params, locks: decoded.locks, overrides: decoded.overrides };
    } catch { /* keep defaults if the hash is stale or malformed */ }
  }

  const currentHexes = () => (palette ? palette.entries.map((e) => e.hex) : []);

  // ---- Sub-controllers ------------------------------------------------
  const sliders = createSliders(dom.params, {
    onChange: (name, value, opts = {}) => {
      const spec = PARAM_BY_NAME.get(name);
      state.params = { ...state.params, [name]: spec ? coerceParam(spec, value) : value };
      regenerate();
      commit(opts.coalesce);
    },
  });

  const swatches = createSwatches(dom.swatches, {
    toggleLock: (id) => {
      const entry = palette.entries.find((e) => e.id === id);
      if (!entry) return;
      if (state.locks[id]) { const n = { ...state.locks }; delete n[id]; state.locks = n; }
      else state.locks = { ...state.locks, [id]: entry.hex };
      regenerate();
      commit(false);
    },
    setOverride: (id, hex) => {
      state.overrides = { ...state.overrides, [id]: hex };
      regenerate();
      commit(false);
    },
    clearOverride: (id) => {
      const n = { ...state.overrides }; delete n[id]; state.overrides = n;
      regenerate();
      commit(false);
    },
    copy: async (hex) => {
      try { await navigator.clipboard.writeText(hex); } catch { /* clipboard blocked */ }
    },
  });

  const history = createHistory(dom.history, {
    onRestore: (snapshot) => { state = cloneState(snapshot); regenerate(); },
    onChange: () => {
      dom.undo.disabled = !history.canUndo();
      dom.redo.disabled = !history.canRedo();
    },
  });

  /** Load a `PAL1-…` seed into state; returns false (leaving state untouched) on error. */
  function loadSeed(str) {
    try {
      const decoded = decodeSeed(str);
      state = { params: decoded.params, locks: decoded.locks, overrides: decoded.overrides };
      regenerate();
      commit(false);
      return true;
    } catch { return false; }
  }

  const io = createIO(dom, {
    applyPreset: (id) => {
      state = { params: presetParams(id), locks: {}, overrides: {} };
      regenerate();
      commit(false);
    },
    loadSeed,
    loadJson: (text) => {
      try {
        const parsed = parseJson(text);
        state = {
          params: normalizeParams(parsed.params),
          locks: parsed.locks || {},
          overrides: parsed.overrides || {},
        };
        regenerate();
        commit(false);
        return true;
      } catch { return false; }
    },
    getPalette: () => palette,
    getSaveName: () => dom.saveName.value.trim(),
  });

  const gallery = createGallery({
    container: dom.gallery,
    category: dom.galleryCategory,
    view: dom.galleryView,
    zoom: dom.galleryZoom,
    animate: dom.galleryAnimate,
  }, { getPalette: () => palette });

  // Scene usage backs the picker's `usage` blob mode. It costs a full gallery render, so
  // it is computed at most once per palette and only if that mode is actually selected.
  let usageCache = { seed: null, counts: null };
  const getUsage = () => {
    if (!palette) return null;
    if (usageCache.seed !== palette.seed) usageCache = { seed: palette.seed, counts: sceneUsage(palette) };
    return usageCache.counts;
  };

  const picker = createPicker({
    canvas: dom.pickerCanvas,
    view: dom.pickerView,
    layoutControls: dom.pickerLayoutControls,
    variant: dom.pickerVariant,
    blob: dom.pickerBlob,
    edges: dom.pickerEdges,
    scale: dom.pickerScale,
    exportPng: dom.pickerExport,
    exportSheet: dom.pickerSheet,
    readout: dom.pickerReadout,
    swatch: dom.pickerSwatch,
    score: dom.pickerScore,
  }, { getUsage });

  const recolor = createRecolorGallery({
    container: dom.recolorList,
    zoom: dom.recolorZoom,
    picker: dom.recolorPicker,
    rescan: dom.recolorRescan,
    persistNote: dom.recolorPersistNote,
  }, { onStatus: (text) => { dom.recolorStatus.textContent = text; } });

  // The three views of the middle pane. Only one is built and animating at a time — the
  // gallery, the picker and the recolour page are all expensive enough that leaving a
  // hidden one running would be felt.
  const TABS = [
    { name: 'gallery', tab: dom.tabGallery, body: dom.gallery, controls: dom.galleryControls },
    { name: 'picker', tab: dom.tabPicker, body: dom.picker, controls: dom.pickerControls },
    { name: 'recolor', tab: dom.tabRecolor, body: dom.recolor, controls: dom.recolorControls },
  ];

  /** Switch the middle pane between the gallery, the picker and the recolour page. */
  function showTab(name) {
    for (const t of TABS) {
      const on = t.name === name;
      t.tab.classList.toggle('is-active', on);
      t.tab.setAttribute('aria-selected', String(on));
      t.body.hidden = !on;
      t.controls.hidden = !on;
    }
    picker.setActive(name === 'picker');
    recolor.setActive(name === 'recolor');
  }
  for (const t of TABS) t.tab.addEventListener('click', () => showTab(t.name));

  // ---- Core loop ------------------------------------------------------
  /** Regenerate the palette from state and repaint every dependent view. */
  function regenerate() {
    palette = generatePalette(state.params, { locks: state.locks, overrides: state.overrides });
    swatches.render(palette);
    sliders.render(state.params);
    gallery.render(palette);
    picker.render(palette);
    recolor.render(palette, state.params);
    io.updateSeed(palette.seed);
    renderMeta();
  }

  /** Record the current state in history — coalescing into the last entry mid-drag. */
  function commit(coalesce) {
    if (coalesce) history.replaceCurrent(state, currentHexes());
    else history.push(state, currentHexes());
  }

  /** Update the palette-count readout and the warnings panel. */
  function renderMeta() {
    dom.meta.textContent = `${palette.entries.length} colours · ${palette.plan.hueCount} hues`;
    if (palette.warnings.length) {
      dom.warnings.hidden = false;
      dom.warnings.innerHTML = `<strong>${palette.warnings.length} constraint warning(s):</strong>`
        + `<ul>${palette.warnings.map((w) => `<li>${escapeHtml(w)}</li>`).join('')}</ul>`;
    } else {
      dom.warnings.hidden = true;
      dom.warnings.innerHTML = '';
    }
  }

  // ---- Top-bar actions ------------------------------------------------
  dom.randomize.addEventListener('click', () => {
    randomCounter += 1;
    const rng = makeRng((Date.now() ^ Math.imul(randomCounter, 2654435761)) & 0xffff);
    const next = { ...state.params };
    for (const spec of PARAMS) {
      if (RANDOMIZE_SKIP.has(spec.name) || spec.name === 'seed') continue;
      next[spec.name] = randomValue(spec, rng);
    }
    next.seed = rngInt(rng, 0, 65535);
    state = { params: next, locks: state.locks, overrides: state.overrides };
    regenerate();
    commit(false);
  });

  dom.resetDefaults.addEventListener('click', () => {
    state = { params: defaultParams(), locks: {}, overrides: {} };
    regenerate();
    commit(false);
  });

  dom.undo.addEventListener('click', () => {
    const snap = history.undo();
    if (snap) { state = cloneState(snap); regenerate(); }
  });
  dom.redo.addEventListener('click', () => {
    const snap = history.redo();
    if (snap) { state = cloneState(snap); regenerate(); }
  });

  window.addEventListener('keydown', (e) => {
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName || '');
    if (typing) return;
    const mod = e.ctrlKey || e.metaKey;
    if (mod && e.key.toLowerCase() === 'z' && !e.shiftKey) { e.preventDefault(); dom.undo.click(); }
    else if (mod && (e.key.toLowerCase() === 'y' || (e.key.toLowerCase() === 'z' && e.shiftKey))) { e.preventDefault(); dom.redo.click(); }
  });

  window.addEventListener('hashchange', () => {
    const seed = readSeedFromHash();
    if (seed && palette && seed !== palette.seed) loadSeed(seed);
  });

  // ---- First paint ----------------------------------------------------
  regenerate();
  history.push(state, currentHexes());
  io.refreshSaves();
}

/** Minimal HTML escape for warning strings shown in the panel. */
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
}
