// Application orchestrator (PLAN §12). Holds the single source of UI state —
// { params, locks, overrides } — regenerates the palette live on any change, and wires
// the sliders, swatch grid, history strip and I/O panel together.
//
// This is the only browser-only module that drives the DOM directly. All colour work is
// delegated to src/core, so the same generator the tests exercise runs here unchanged.

import { generatePalette } from '../core/generate.js';
import { defaultParams, normalizeParams, coerceParam, PARAM_BY_NAME } from '../core/params.js';
import { decodeSeed } from '../core/seed.js';
import { presetParams, PRESETS } from '../core/presets.js';
import { parseJson } from '../core/export/json.js';
import { makeRng } from '../core/rng.js';
import { randomizeParams, varyParams } from './randomize.js';
import { createVariants } from './variants.js';
import { createSliders } from './sliders.js';
import { createSwatches } from './swatches.js';
import { createHistory, cloneState } from './history.js';
import { createIO, readSeedFromHash } from './io.js';
import { createGallery } from './gallery.js';
import { createPicker } from './picker.js';
import { createRecolorGallery } from './recolor.js';
import { createSizeSweep } from './sizes.js';
import { describePalette, paramDiff, summarizeDiff } from '../core/describe.js';
import { sceneUsage } from '../scenes/usage.js';

// A change smaller than 1.5% of a parameter's range is not what the user is looking at. Every
// user-facing summary filters at this threshold, or a variation (which nudges forty knobs)
// reads as "+34 more" and hides the two changes that did the work.
const NOTABLE = { minMagnitude: 0.015 };

function boot() {
  const $ = (id) => document.getElementById(id);
  const dom = {
    params: $('params'),
    paramsToolbar: $('params-toolbar'),
    swatches: $('swatches'),
    history: $('history'),
    warnings: $('warnings'),
    meta: $('palette-meta'),
    desc: $('palette-desc'),
    changeNote: $('change-note'),
    sizesBtn: $('sizes-btn'),
    seedInput: $('seed-input'),
    seedCopy: $('seed-copy'),
    undo: $('undo'),
    redo: $('redo'),
    beforeAfter: $('before-after'),
    vary: $('vary'),
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
    fitImageBtn: $('fit-image-btn'),
    fitImageFile: $('fit-image-file'),
    fitStatus: $('fit-status'),
    gallery: $('gallery'),
    galleryCategory: $('gallery-category'),
    galleryView: $('gallery-view'),
    galleryZoom: $('gallery-zoom'),
    galleryAnimate: $('gallery-animate'),
    galleryControls: $('gallery-controls'),
    tabGallery: $('tab-gallery'),
    tabVariants: $('tab-variants'),
    variants: $('variants'),
    variantsControls: $('variants-controls'),
    variantsGrid: $('variants-grid'),
    variantsStrength: $('variants-strength'),
    variantsScene: $('variants-scene'),
    variantsMore: $('variants-more'),
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
    pickerRebuild: $('picker-rebuild'),
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
    recolorTarget: $('recolor-target'),
    recolorPalettePicker: $('recolor-palette-picker'),
    recolorTargetSwatches: $('recolor-target-swatches'),
  };

  // ---- State ----------------------------------------------------------
  let state = { params: defaultParams(), locks: {}, overrides: {} };
  let palette = null;
  let randomCounter = 0;
  let lastCommitted = null; // baseline for "what changed" labels on history entries
  let showingBefore = false; // the Before/After button is holding a past palette on screen

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
    toolbar: dom.paramsToolbar,
    // The hover sweeps generate real palettes from the live state, pinned colours included.
    getState: () => state,
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
    onRestore: (snapshot) => { state = cloneState(snapshot); regenerate(); persistHistory(); },
    onChange: () => {
      dom.undo.disabled = !history.canUndo();
      dom.redo.disabled = !history.canRedo();
      if (dom.beforeAfter) dom.beforeAfter.disabled = !history.previous();
      persistHistory();
    },
  });

  // ---- History persistence (UX_PLAN U3.3) ------------------------------
  // A hundred steps in memory is still one reload away from nothing, and the palette worth
  // keeping is routinely three reloads back. Written on a timer so a slider drag does not
  // serialise the whole strip on every frame.
  const HISTORY_KEY = 'palette.history.v1';
  let persistTimer = null;
  function persistHistory() {
    clearTimeout(persistTimer);
    persistTimer = setTimeout(() => {
      try { localStorage.setItem(HISTORY_KEY, JSON.stringify(history.serialize())); } catch { /* full or blocked */ }
    }, 400);
  }

  /** Load a `PAL1-…` seed into state; returns false (leaving state untouched) on error. */
  function loadSeed(str) {
    try {
      const decoded = decodeSeed(str);
      const summary = summarizeDiff(paramDiff(state.params, decoded.params, NOTABLE), 3);
      state = { params: decoded.params, locks: decoded.locks, overrides: decoded.overrides };
      regenerate();
      commit(false);
      noteChange(summary ? `Seed loaded — ${summary}` : 'Seed loaded');
      return true;
    } catch { return false; }
  }

  /**
   * Show a one-line "what just changed" note above the panel (UX_PLAN U2.5 — item 34).
   * A preset, a fit or a pasted seed is otherwise an opaque jump: this says which knobs moved
   * and by how much, so the jump teaches the parameters instead of hiding them.
   */
  function noteChange(text) {
    if (!dom.changeNote) return;
    dom.changeNote.textContent = text || '';
    dom.changeNote.hidden = !text;
  }

  /** Replace the whole parameter set, reporting what it changed. */
  function applyParamSet(params, source) {
    const next = normalizeParams(params);
    // Taken before the state moves — `commit` resets the baseline the labels are measured on.
    const summary = summarizeDiff(paramDiff(state.params, next, NOTABLE), 3);
    state = { params: next, locks: {}, overrides: {} };
    regenerate();
    commit(false);
    noteChange(summary ? `${source} — ${summary}` : `${source} — nothing changed`);
  }

  /** Set one parameter (used by views outside the slider panel, like the size sweep). */
  function setParam(name, value) {
    const spec = PARAM_BY_NAME.get(name);
    state = { ...state, params: { ...state.params, [name]: spec ? coerceParam(spec, value) : value } };
    regenerate();
    commit(false);
  }

  const io = createIO(dom, {
    applyPreset: (id) => {
      const preset = PRESETS.find((p) => p.id === id);
      applyParamSet(presetParams(id), `Preset “${preset?.name || id}”`);
    },
    applyParams: (params) => applyParamSet(params, 'Fitted parameters'),
    loadSeed,
    loadJson: (text) => {
      try {
        const parsed = parseJson(text);
        const next = normalizeParams(parsed.params);
        const summary = summarizeDiff(paramDiff(state.params, next, NOTABLE), 3);
        state = {
          params: next,
          locks: parsed.locks || {},
          overrides: parsed.overrides || {},
        };
        regenerate();
        commit(false);
        noteChange(summary ? `Loaded palette — ${summary}` : 'Loaded palette');
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
    rebuild: dom.pickerRebuild,
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
    target: dom.recolorTarget,
    palettePicker: dom.recolorPalettePicker,
    targetSwatches: dom.recolorTargetSwatches,
  }, { onStatus: (text) => { dom.recolorStatus.textContent = text; } });

  const variants = createVariants({
    grid: dom.variantsGrid,
    strength: dom.variantsStrength,
    scene: dom.variantsScene,
    more: dom.variantsMore,
  }, {
    getState: () => state,
    onAdopt: (params) => applyParamSet(params, 'Variation taken'),
  });

  // The four views of the middle pane. Only one is built and animating at a time — the
  // gallery, the variants, the picker and the recolour page are all expensive enough that
  // leaving a hidden one running would be felt.
  const TABS = [
    { name: 'gallery', tab: dom.tabGallery, body: dom.gallery, controls: dom.galleryControls },
    { name: 'variants', tab: dom.tabVariants, body: dom.variants, controls: dom.variantsControls },
    { name: 'picker', tab: dom.tabPicker, body: dom.picker, controls: dom.pickerControls },
    { name: 'recolor', tab: dom.tabRecolor, body: dom.recolor, controls: dom.recolorControls },
  ];

  /** Switch the middle pane between the gallery, the variants, the picker and the recolour. */
  function showTab(name) {
    for (const t of TABS) {
      const on = t.name === name;
      t.tab.classList.toggle('is-active', on);
      t.tab.setAttribute('aria-selected', String(on));
      t.body.hidden = !on;
      t.controls.hidden = !on;
    }
    variants.setActive(name === 'variants');
    picker.setActive(name === 'picker');
    recolor.setActive(name === 'recolor');
  }
  for (const t of TABS) t.tab.addEventListener('click', () => showTab(t.name));

  // ---- Core loop ------------------------------------------------------
  /**
   * Regenerate the palette and repaint every dependent view.
   *
   * `src` is normally the live state; the Before/After button passes a past snapshot with
   * `transient`, which repaints everything **without** touching the seed field, the URL hash
   * or the history — looking at where you were must not count as going there.
   */
  function regenerate(src = state, { transient = false } = {}) {
    // Any real change leaves the Before/After view — otherwise the button would still claim
    // to be showing the past while the user edits the present.
    if (!transient && showingBefore) exitBefore();
    palette = generatePalette(src.params, { locks: src.locks, overrides: src.overrides });
    swatches.render(palette);
    sliders.render(src.params);
    gallery.render(palette);
    variants.render(palette);
    picker.render(palette);
    recolor.render(palette, src.params);
    if (!transient) io.updateSeed(palette.seed);
    renderMeta(src.params);
  }

  /**
   * Record the current state in history — coalescing into the last entry mid-drag — with a
   * label saying what moved, so the strip is a list of decisions rather than of thumbnails.
   */
  function commit(coalesce) {
    // The baseline is the last *pushed* entry, not the last call: during a drag every frame
    // coalesces into one entry, and its label should describe the whole drag.
    const label = summarizeDiff(paramDiff(lastCommitted?.params, state.params, NOTABLE), 2);
    if (coalesce) {
      history.replaceCurrent(state, currentHexes(), label);
    } else {
      history.push(state, currentHexes(), label);
      lastCommitted = cloneState(state);
    }
  }

  /** Update the palette-count readout, the plain-English description and the warnings. */
  function renderMeta(params = state.params) {
    dom.meta.textContent = `${palette.entries.length} colours · ${palette.plan.hueCount} hues`;
    if (dom.desc) dom.desc.textContent = describePalette(palette, params);
    if (palette.warnings.length) {
      dom.warnings.hidden = false;
      dom.warnings.innerHTML = `<strong>${palette.warnings.length} constraint warning(s):</strong>`
        + `<ul>${palette.warnings.map((w) => `<li>${escapeHtml(w)}</li>`).join('')}</ul>`;
    } else {
      dom.warnings.hidden = true;
      dom.warnings.innerHTML = '';
    }
  }

  createSizeSweep({
    button: dom.sizesBtn,
    getState: () => state,
    onPick: (size) => {
      setParam('color_count', size);
      noteChange(`Colour count → ${size}`);
    },
  });

  // ---- Top-bar actions ------------------------------------------------
  /** A fresh RNG for a button press — never the same variation twice in a row. */
  function pressRng() {
    randomCounter += 1;
    return makeRng((Date.now() ^ Math.imul(randomCounter, 2654435761)) & 0xffff);
  }

  // Vary is the everyday button: the same palette, moved. Randomize (below) is the "I have
  // nothing yet, surprise me" button, and stays exactly as it was.
  dom.vary?.addEventListener('click', (e) => {
    const strength = e.shiftKey ? 'wild' : 'moderate';
    const before = state.params;
    const next = varyParams(before, pressRng(), { strength });
    // The summary is taken against the pre-vary parameters: `commit` moves the baseline, so
    // reading it afterwards would always report nothing.
    const summary = summarizeDiff(paramDiff(before, next, NOTABLE), 2);
    state = { params: next, locks: state.locks, overrides: state.overrides };
    regenerate();
    commit(false);
    noteChange(`${e.shiftKey ? 'Bold' : 'Gentle'} variation — ${summary || 'a new seed only'}`);
  });

  dom.randomize.addEventListener('click', () => {
    state = { params: randomizeParams(state.params, pressRng()), locks: state.locks, overrides: state.overrides };
    regenerate();
    commit(false);
    noteChange('Randomized every look parameter');
  });

  // Before / After (item 22): show the previous palette everywhere while it is on, without
  // committing anything. An on-screen toggle rather than a held key, so it is discoverable.
  /** Put the button back to "Before" without repainting. */
  function exitBefore() {
    showingBefore = false;
    if (!dom.beforeAfter) return;
    dom.beforeAfter.classList.remove('is-on');
    dom.beforeAfter.textContent = 'Before';
    dom.beforeAfter.title = 'Show the palette as it was one step ago — click again to come back';
  }

  dom.beforeAfter?.addEventListener('click', () => {
    if (showingBefore) {
      exitBefore();
      regenerate();
      return;
    }
    const prev = history.previous();
    if (!prev) return;
    showingBefore = true;
    dom.beforeAfter.classList.add('is-on');
    dom.beforeAfter.textContent = 'After';
    dom.beforeAfter.title = 'Showing the previous palette — click to come back';
    regenerate(prev, { transient: true });
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
  // A URL seed always wins — it is an explicit request for a specific palette. Otherwise the
  // last session's history is restored, so closing the tab is no longer a way to lose work.
  let restored = null;
  if (!hashSeed) {
    try {
      const saved = localStorage.getItem(HISTORY_KEY);
      if (saved) restored = history.restore(JSON.parse(saved));
    } catch { /* unusable store: fall through to a clean start */ }
  }
  if (restored) state = cloneState(restored);
  regenerate();
  if (!restored) history.push(state, currentHexes(), 'start');
  lastCommitted = cloneState(state);
  if (dom.beforeAfter) dom.beforeAfter.disabled = !history.previous();
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
