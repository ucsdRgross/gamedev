// Application orchestrator (PLAN §12). Holds the single source of UI state —
// { params, locks, overrides } — regenerates the palette live on any change, and wires
// the sliders, swatch grid, history strip and I/O panel together.
//
// This is the only browser-only module that drives the DOM directly. All colour work is
// delegated to src/core, so the same generator the tests exercise runs here unchanged.

import { generatePalette } from '../core/generate.js';
import { defaultParams, normalizeParams, coerceParam, PARAM_BY_NAME, FREEZE_PARAMS } from '../core/params.js';
import { decodeSeed } from '../core/seed.js';
import { presetParams, PRESETS } from '../core/presets.js';
import { parseJson } from '../core/export/json.js';
import { makeRng } from '../core/rng.js';
import { paramEffect } from '../core/preview.js';
import { randomizeParams, varyParams } from './randomize.js';
import { createVariants } from './variants.js';
import { createSliders } from './sliders.js';
import { createSwatches } from './swatches.js';
import { createHistory, cloneState } from './history.js';
import { createIO, readSeedFromHash } from './io.js';
import { createGallery } from './gallery.js';
import { createHero } from './hero.js';
import { createPicker } from './picker.js';
import { createRecolorGallery } from './recolor.js';
import { createSizeSweep } from './sizes.js';
import { createHueWheel } from './wheel.js';
import { createStart } from './start.js';
import { createCompare } from './compare.js';
import { createReport } from './report.js';
import { createSuggest } from './suggest.js';
import { createColorEditor } from './coloredit.js';
import { createSaveStore, recordRing } from './saves.js';
import { describePalette, paramDiff, summarizeDiff, autoName } from '../core/describe.js';
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
    swatchArrange: $('swatch-arrange'),
    pinned: $('pinned'),
    history: $('history'),
    warnings: $('warnings'),
    report: $('report'),
    reportSummary: $('report-summary'),
    reportList: $('report-list'),
    suggestRun: $('suggest-run'),
    suggestNote: $('suggest-note'),
    suggestList: $('suggest-list'),
    meta: $('palette-meta'),
    desc: $('palette-desc'),
    changeNote: $('change-note'),
    sizesBtn: $('sizes-btn'),
    wheelBtn: $('wheel-btn'),
    seedInput: $('seed-input'),
    seedCopy: $('seed-copy'),
    undo: $('undo'),
    redo: $('redo'),
    beforeAfter: $('before-after'),
    keep: $('keep'),
    freeze: $('freeze'),
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
    tabStart: $('tab-start'),
    start: $('start'),
    startControls: $('start-controls'),
    startMoods: $('start-moods'),
    startPresets: $('start-presets'),
    startSaves: $('start-saves'),
    startSavesNote: $('start-saves-note'),
    startRecent: $('start-recent'),
    startRecentWrap: $('start-recent-wrap'),
    startPaste: $('start-paste'),
    startPasteNote: $('start-paste-note'),
    startPastePreview: $('start-paste-preview'),
    startPasteFit: $('start-paste-fit'),
    startPasteTarget: $('start-paste-target'),
    startFromImage: $('start-from-image'),
    gallery: $('gallery'),
    hero: $('hero'),
    heroBody: $('hero-body'),
    heroCanvas: $('hero-canvas'),
    heroScene: $('hero-scene'),
    heroZoom: $('hero-zoom'),
    heroArt: $('hero-art'),
    heroArtRow: $('hero-art-row'),
    heroOriginal: $('hero-original'),
    heroToggle: $('hero-toggle'),
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
    tabCompare: $('tab-compare'),
    compare: $('compare'),
    compareControls: $('compare-controls'),
    compareA: $('compare-a'),
    compareB: $('compare-b'),
    comparePin: $('compare-pin'),
    compareSource: $('compare-source'),
    compareStatus: $('compare-status'),
    compareReport: $('compare-report'),
    comparePaste: $('compare-paste'),
    compareHow: $('compare-how'),
    compareTakeAll: $('compare-take-all'),
    compareTakeMorph: $('compare-take-morph'),
    compareMorphRow: $('compare-morph-row'),
    compareMorph: $('compare-morph'),
    compareMorphValue: $('compare-morph-value'),
    compareMorphNote: $('compare-morph-note'),
    compareMorphScene: $('compare-morph-scene'),
    compareMorphStrip: $('compare-morph-strip'),
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
  let frozen = null; // the values Freeze is holding at zero, or null when not frozen

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
      const before = currentHexes().join();
      state.params = { ...state.params, [name]: spec ? coerceParam(spec, value) : value };
      regenerate();
      commit(opts.coalesce);
      noteSilentMove(name, before !== currentHexes().join());
    },
  });

  const setOverride = (id, hex, coalesce = false) => {
    state.overrides = { ...state.overrides, [id]: hex };
    regenerate();
    commit(coalesce);
  };
  const clearOverride = (id) => {
    const n = { ...state.overrides }; delete n[id]; state.overrides = n;
    regenerate();
    commit(false);
  };

  const swatches = createSwatches(dom.swatches, {
    toggleLock: (id) => {
      const entry = palette.entries.find((e) => e.id === id);
      if (!entry) return;
      if (state.locks[id]) { const n = { ...state.locks }; delete n[id]; state.locks = n; }
      else state.locks = { ...state.locks, [id]: entry.hex };
      regenerate();
      commit(false);
    },
    setOverride,
    clearOverride,
    copy: async (hex) => {
      try { await navigator.clipboard.writeText(hex); } catch { /* clipboard blocked */ }
    },
    editColor: (entry, anchor) => colorEditor.open(entry, anchor),
    nudge: (entry, ev) => colorEditor.nudge(entry, ev),
    // Releasing every pin at once (U7.6 — item 8): locks and overrides are invisible until you
    // scan every card, so the list that counts them also has to be able to undo them.
    clearPins: () => {
      state = { ...state, locks: {}, overrides: {} };
      colorEditor.close();
      regenerate();
      commit(false);
      noteChange('Cleared every locked and overridden colour');
    },
  }, { modeSelect: dom.swatchArrange, pinned: dom.pinned });

  const colorEditor = createColorEditor({
    setOverride,
    clearOverride,
    // The eyedropper's fallback samples the reference images the recolour gallery has decoded,
    // rather than fetching and decoding a second copy of every one of them.
    refs: { listSources: (...a) => recolor.listSources(...a), framesFor: (...a) => recolor.framesFor(...a) },
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
      exitFreeze();
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
    // A wholesale replacement ends the freeze even when the new set is itself unjittered:
    // the values Freeze is holding belonged to the palette that just went away.
    exitFreeze();
    state = { params: next, locks: {}, overrides: {} };
    regenerate();
    commit(false);
    noteChange(summary ? `${source} — ${summary}` : `${source} — nothing changed`);
  }

  // ---- Dead controls (UX_PLAN U7.3 — item 35) --------------------------
  // The trigger is the moment it actually goes wrong: a control was moved and every colour
  // stayed where it was. `paramEffect` then confirms it properly — a *tenth of the range* in
  // both directions, so a step too fine for the seed's own resolution is not called clamped —
  // and the badge on the control offers to go and find what is holding it down.
  //
  // On a settle rather than immediately: mid-drag every frame would pay for four extra palette
  // generations, and the interesting question is only ever about where the drag stopped.
  const STUCK_SETTLE_MS = 250;
  let stuckTimer = null;
  function noteSilentMove(name, changedSomething) {
    clearTimeout(stuckTimer);
    if (changedSomething) {
      sliders.markStuck(name, null);
      return;
    }
    stuckTimer = setTimeout(() => {
      try {
        const effect = paramEffect(state.params, name, { locks: state.locks, overrides: state.overrides });
        sliders.markStuck(name, effect.applies ? effect : null);
      } catch { /* never let a diagnosis break an edit */ }
    }, STUCK_SETTLE_MS);
  }

  /** Merge a patch of parameter values into the state as one history step. */
  function applyPatch(patch, source) {
    const next = { ...state.params };
    for (const [name, value] of Object.entries(patch)) {
      const spec = PARAM_BY_NAME.get(name);
      next[name] = spec ? coerceParam(spec, value) : value;
    }
    const summary = summarizeDiff(paramDiff(state.params, next, NOTABLE), 3);
    state = { ...state, params: next };
    regenerate();
    commit(false);
    if (source) noteChange(summary ? `${source} — ${summary}` : source);
  }

  /** Set one parameter (used by views outside the slider panel, like the size sweep). */
  function setParam(name, value) {
    const spec = PARAM_BY_NAME.get(name);
    state = { ...state, params: { ...state.params, [name]: spec ? coerceParam(spec, value) : value } };
    regenerate();
    commit(false);
  }

  // Saves go to the dev server's `saved/` folder when there is one and to `localStorage`
  // when there is not, so Keep works in the standalone build too (UX_PLAN U5.3).
  const store = createSaveStore();

  const io = createIO(dom, {
    store,
    onSaved: () => start.refresh(),
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
        exitFreeze();
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

  // The report card sits under the warnings in the palette pane. It borrows the same usage
  // counts the picker uses; `usageOf` re-counts them for a candidate palette, which is what
  // lets the unused-colour check prove its own fix rather than assert it.
  const report = createReport({
    root: dom.report,
    summary: dom.reportSummary,
    list: dom.reportList,
  }, {
    getPalette: () => palette,
    getUsage,
    usageOf: (p) => sceneUsage(p),
    applyFix: (patch, label) => applyPatch(patch, label),
    highlight: (ids) => swatches.highlight(ids),
  });

  const suggest = createSuggest({
    run: dom.suggestRun,
    note: dom.suggestNote,
    list: dom.suggestList,
  }, {
    getState: () => state,
    getPalette: () => palette,
    // One step: the colour count goes up by one and the new slot is locked to the suggestion.
    onAdd: (grown, hex) => {
      state = { params: normalizeParams(grown.params), locks: grown.locks, overrides: state.overrides };
      regenerate();
      commit(false);
      noteChange(`Added ${hex} as a locked slot (${grown.slotId}) — ${state.params.color_count} colours`);
    },
  });

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

  // The hero is pinned above the gallery grid, so it is the one picture that survives a
  // slider drag. It borrows the recolour gallery's library rather than fetching its own.
  const hero = createHero({
    root: dom.hero,
    body: dom.heroBody,
    canvas: dom.heroCanvas,
    scene: dom.heroScene,
    zoom: dom.heroZoom,
    art: dom.heroArt,
    artRow: dom.heroArtRow,
    original: dom.heroOriginal,
    collapse: dom.heroToggle,
    view: dom.galleryView, // the hero follows the gallery's colour-vision view
  }, { refs: recolor });

  const start = createStart({
    moods: dom.startMoods,
    presets: dom.startPresets,
    saves: dom.startSaves,
    savesNote: dom.startSavesNote,
    recent: dom.startRecent,
    recentWrap: dom.startRecentWrap,
    pasteInput: dom.startPaste,
    pasteNote: dom.startPasteNote,
    pastePreview: dom.startPastePreview,
    pasteFit: dom.startPasteFit,
    pasteTarget: dom.startPasteTarget,
    fromImage: dom.startFromImage,
  }, {
    store,
    actions: {
      applyParams: (params, source) => applyParamSet(params, source),
      loadSave: (name) => io.loadSave(name),
      loadSeed,
      fitTo: (hexes) => io.fitTo(hexes),
      pickImage: () => io.pickImage(),
      useAsTarget: (palette) => recolor.addTarget(palette),
      onPicked: (tab) => showTab(tab),
      // Shift-click a card (UX_PLAN U5.2, finally possible now U6.2 exists): hold it against
      // what you have instead of taking it, which is the question you actually had.
      compareWith: (source) => {
        showTab('compare');
        compare.setB(source);
      },
    },
  });

  const compare = createCompare({
    a: dom.compareA,
    b: dom.compareB,
    pinA: dom.comparePin,
    source: dom.compareSource,
    status: dom.compareStatus,
    report: dom.compareReport,
    pasteB: dom.comparePaste,
    howTo: dom.compareHow,
    takeAll: dom.compareTakeAll,
    takeMorph: dom.compareTakeMorph,
    morphRow: dom.compareMorphRow,
    morph: dom.compareMorph,
    morphValue: dom.compareMorphValue,
    morphNote: dom.compareMorphNote,
    morphScene: dom.compareMorphScene,
    morphStrip: dom.compareMorphStrip,
  }, {
    actions: {
      getState: () => state,
      applyParams: (params, source) => applyParamSet(params, source),
      fitTo: (hexes, opts) => io.fitTo(hexes, opts),
      listSaves: () => store.list(),
      readSave: (name) => store.read(name),
      listExternal: () => recolor.listTargets(),
      readExternal: (id) => recolor.readTarget(id),
    },
  });

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
    { name: 'start', tab: dom.tabStart, body: dom.start, controls: dom.startControls },
    { name: 'gallery', tab: dom.tabGallery, body: dom.gallery, controls: dom.galleryControls },
    { name: 'variants', tab: dom.tabVariants, body: dom.variants, controls: dom.variantsControls },
    { name: 'compare', tab: dom.tabCompare, body: dom.compare, controls: dom.compareControls },
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
    start.setActive(name === 'start');
    hero.setActive(name === 'gallery');
    variants.setActive(name === 'variants');
    compare.setActive(name === 'compare');
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
    // Likewise the freeze: the moment anything puts a non-zero spread back, the palette is
    // not frozen any more, whichever path did it.
    if (!transient && frozen && FREEZE_PARAMS.some((n) => src.params[n] !== 0)) exitFreeze();
    palette = generatePalette(src.params, { locks: src.locks, overrides: src.overrides });
    swatches.render(palette);
    sliders.render(src.params);
    // Every "clamped" badge was measured against the parameter set that has just been replaced,
    // so it is cleared here and re-established by `noteSilentMove` if it still holds.
    sliders.clearStuck();
    gallery.render(palette);
    hero.render(palette, src.params);
    variants.render(palette);
    picker.render(palette);
    recolor.render(palette, src.params);
    compare.render();
    wheel.refresh();
    report.schedule();
    suggest.invalidate();
    colorEditor.refresh(palette);
    if (!transient) { io.updateSeed(palette.seed); recordSettled(); }
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

  const wheel = createHueWheel({
    button: dom.wheelBtn,
    getState: () => state,
    getPalette: () => palette,
    // `source` is null mid-drag: the pin coalesces into one history entry, exactly as a
    // slider drag does, so dragging a pin around the wheel is one undo and not forty.
    setParams: (patch, source) => {
      const next = { ...state.params };
      for (const [name, value] of Object.entries(patch)) {
        const spec = PARAM_BY_NAME.get(name);
        next[name] = spec ? coerceParam(spec, value) : value;
      }
      state = { ...state, params: next };
      regenerate();
      commit(source === null);
      if (source) noteChange(source);
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

  // Keep (item 6): save in one click, with a name read off the colours. The dialogue that
  // used to be in the way is why `saved/` is empty and a text file in the project root is
  // holding pasted seeds — a decision demanded at the moment of *keeping* something is a
  // decision that stops people keeping things. The name is renameable afterwards, forever.
  // Seeds kept this session, so a second click on an unchanged palette reports the name it
  // already has instead of filing "Grey 32 2" beside an identical "Grey 32".
  const keptSeeds = new Map();

  dom.keep?.addEventListener('click', async () => {
    const already = keptSeeds.get(palette.seed);
    if (already) {
      noteChange(`Already kept as “${already}”`);
      return;
    }
    let taken = [];
    try { taken = await store.list(); } catch { /* a fresh store lists nothing */ }
    const name = autoName(palette, state.params, { taken });
    const saved = await io.save(name);
    if (saved) keptSeeds.set(palette.seed, saved);
    noteChange(saved ? `Kept as “${saved}” — rename it in Save & Export` : 'Could not keep this one');
  });

  // The autosave ring (item 26): the palettes you sat with, whether or not you kept them.
  // Recorded on a delay so a slider drag does not fill the ring with the twelve palettes it
  // passed through on the way — what is worth remembering is where you *stopped*.
  let ringTimer = null;
  function recordSettled() {
    clearTimeout(ringTimer);
    ringTimer = setTimeout(() => {
      if (!palette) return;
      recordRing({
        seed: palette.seed,
        name: autoName(palette, state.params),
        params: state.params,
        at: Date.now(),
      });
    }, 4000);
  }

  // Freeze (item 33): zero the three random spreads so the palette stops moving underneath
  // the knob being turned. It is a real parameter change — it is in the seed, in the history
  // and in the exported palette — but the previous values are remembered so it is one click
  // back. Anything that puts a non-zero value back (a preset, a seed, an undo, or dragging
  // one of the three sliders by hand) ends the freeze, because the remembered values no
  // longer belong to the palette on screen; `regenerate` notices that centrally.

  /** Put the Freeze button back to its off state without touching any parameter. */
  function exitFreeze() {
    frozen = null;
    if (!dom.freeze) return;
    dom.freeze.classList.remove('is-on');
    dom.freeze.textContent = 'Freeze';
  }

  dom.freeze?.addEventListener('click', () => {
    if (frozen) {
      const restore = frozen;
      exitFreeze();
      state = { ...state, params: { ...state.params, ...restore } };
      regenerate();
      commit(false);
      noteChange('Unfrozen — the hue jitter and per-hue variances are back');
      return;
    }
    frozen = Object.fromEntries(FREEZE_PARAMS.map((n) => [n, state.params[n]]));
    // Already at zero: freezing would be a no-op, and a button that claims to have done
    // something it did not is worse than one that says so.
    if (FREEZE_PARAMS.every((n) => state.params[n] === 0)) {
      noteChange('Already frozen — jitter and both per-hue variances are zero');
      frozen = null;
      return;
    }
    state = { ...state, params: { ...state.params, ...Object.fromEntries(FREEZE_PARAMS.map((n) => [n, 0])) } };
    dom.freeze.classList.add('is-on');
    dom.freeze.textContent = 'Frozen';
    regenerate();
    commit(false);
    noteChange('Frozen — every other slider now moves only what it says it moves');
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

  // A first-time visitor opens on Start; anyone returning to work — a restored session or a
  // shared seed — opens where they left off. It is a tab, so it is dismissed by clicking
  // another one, and it never stands between anybody and the tool (UX_PLAN U5.5).
  showTab(!restored && !hashSeed ? 'start' : 'gallery');
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
