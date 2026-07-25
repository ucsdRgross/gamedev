// Input/output surface (PLAN §12, §10): the seed field with URL-hash mirroring, the
// preset dropdown, the saved-palette dropdown backed by the dev server's /api/saves,
// import from a JSON file, and one download button per export format.

import { PRESETS } from '../core/presets.js';
import { EXPORTERS, runExport } from '../core/export/index.js';
import { makeFitter } from '../core/fit.js';
import { extractPalette } from '../core/recolor/swatches.js';
import { isSaveName } from '../core/library.js';
import { decodeStillToRaster } from './imagefile.js';
import { option } from './dom.js';

/** Read a `PAL1-…` seed out of the URL hash (`#seed=…`), or null. */
export function readSeedFromHash() {
  const m = /(?:^|[#&])seed=([^&]+)/.exec(location.hash);
  return m ? decodeURIComponent(m[1]) : null;
}

/** Mirror a seed into the URL hash without adding a browser history entry. */
export function writeSeedToHash(seed) {
  const next = `#seed=${encodeURIComponent(seed)}`;
  if (location.hash !== next) history.replaceState(null, '', next);
}

/** Trigger a browser download of a string or byte array. */
export function download(filename, data, mime, binary) {
  const blob = binary
    ? new Blob([data instanceof Uint8Array ? data : new Uint8Array(data)], { type: mime })
    : new Blob([data], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Set a status line's text and tone (''/'ok'/'err'). */
function status(el, text, tone = '') {
  if (!el) return;
  el.textContent = text;
  el.className = `io-status${tone ? ` ${tone}` : ''}`;
}

/**
 * Wire the I/O panel. `actions` supplies the app callbacks:
 *   loadSeed(str), applyPreset(id), applyParams(params), loadJson(text), getPalette(),
 *   getSaveName(), onSaved(name). `store` is the save store from `saves.js`.
 * Returns `{ updateSeed, refreshSaves, loadSave, save, fitTo, pickImage }` — the last four so
 * the Start tab drives the same code paths rather than its own copies of them.
 */
export function createIO(dom, { store, ...actions }) {
  // ---- Presets --------------------------------------------------------
  for (const preset of PRESETS) dom.presetSelect.appendChild(option(preset.id, preset.name));
  dom.presetSelect.addEventListener('change', () => {
    if (dom.presetSelect.value) {
      actions.applyPreset(dom.presetSelect.value);
      dom.presetSelect.value = '';
    }
  });

  // ---- Seed field -----------------------------------------------------
  const submitSeed = () => {
    const ok = actions.loadSeed(dom.seedInput.value.trim());
    dom.seedInput.classList.toggle('bad', !ok);
  };
  dom.seedInput.addEventListener('change', submitSeed);
  dom.seedInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') submitSeed(); });
  dom.seedCopy?.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(dom.seedInput.value);
      dom.seedCopy.textContent = 'Copied';
      setTimeout(() => { dom.seedCopy.textContent = 'Copy'; }, 1200);
    } catch { /* clipboard blocked; the field is already selectable */ }
  });

  // ---- Export buttons -------------------------------------------------
  for (const exp of EXPORTERS) {
    const btn = document.createElement('button');
    btn.className = 'btn btn-small';
    btn.textContent = exp.label;
    btn.title = `Download .${exp.extension}`;
    btn.addEventListener('click', () => {
      try {
        const palette = actions.getPalette();
        const data = runExport(exp.id, palette, { name: actions.getSaveName() || 'Pixel Palette' });
        const base = (actions.getSaveName() || 'palette').replace(/[^A-Za-z0-9_-]+/g, '_');
        download(`${base}.${exp.extension}`, data, exp.mime, exp.binary);
        status(dom.exportStatus, `Exported ${exp.label}`, 'ok');
      } catch (err) {
        status(dom.exportStatus, `Export failed: ${err.message}`, 'err');
      }
    });
    dom.exportButtons.appendChild(btn);
  }

  // ---- Import ---------------------------------------------------------
  dom.importFile?.addEventListener('change', async () => {
    const file = dom.importFile.files?.[0];
    if (!file) return;
    try {
      const text = await file.text();
      const ok = actions.loadJson(text);
      status(dom.importStatus, ok ? `Loaded ${file.name}` : 'Not a palette JSON', ok ? 'ok' : 'err');
    } catch (err) {
      status(dom.importStatus, `Import failed: ${err.message}`, 'err');
    }
    dom.importFile.value = '';
  });

  // ---- Fit to image ---------------------------------------------------
  // Decode an image at the edge, extract its palette, then search the generator's parameter
  // space for the set that reproduces it (fit.js). The search is deterministic but takes a
  // few seconds, so it runs in animation-frame slices to keep the page responsive, reporting
  // best-score-so-far. When done, the fitted params are applied exactly like a preset.
  /** Open the image picker — also the Start tab's "start from an image". */
  function pickImage() {
    dom.fitImageFile?.click();
  }

  /**
   * Search for the parameters that reproduce `target` (an array of hexes), reporting progress.
   * Shared by "Fit to image…", the Start tab's pasted colours and Compare's "how to get
   * there": all three end up with a list of colours and the same question about it.
   *
   * `from` starts the search at an existing parameter set, which changes what the answer
   * *means* — without it the fitter reports "here is a palette like that", with it "here is
   * what to change about yours". Compare needs the second one.
   */
  function fitTo(target, { from = null, fixed = [], label = '', onDone = null } = {}) {
    if (!Array.isArray(target) || target.length < 2) {
      status(dom.fitStatus, 'Need at least two colours to fit', 'err');
      onDone?.(null);
      return;
    }
    // Fewer iterations for larger targets — each evaluation generates a whole palette, so
    // cost grows with colour count. Keeps a big drop-in from running for minutes.
    const iterations = Math.max(1500, Math.round(4000 * Math.min(1, 24 / target.length)));
    const fitter = makeFitter(target, { iterations, from, fixed });
    const what = label || `${target.length} colours`;
    if (dom.fitImageBtn) dom.fitImageBtn.disabled = true;
    const tick = () => {
      const t0 = performance.now();
      while (!fitter.done && performance.now() - t0 < 25) fitter.step(10);
      status(dom.fitStatus,
        `${what}… ${Math.round(fitter.progress * 100)}% · ΔE ${fitter.bestScore.toFixed(2)}`);
      if (!fitter.done) { requestAnimationFrame(tick); return; }
      actions.applyParams(fitter.bestParams);
      if (dom.fitImageBtn) dom.fitImageBtn.disabled = false;
      status(dom.fitStatus, `${what} · ΔE ${fitter.bestScore.toFixed(2)}`, 'ok');
      onDone?.(fitter);
    };
    requestAnimationFrame(tick);
  }

  dom.fitImageBtn?.addEventListener('click', pickImage);
  dom.fitImageFile?.addEventListener('change', async () => {
    const file = dom.fitImageFile.files?.[0];
    if (!file) return;
    dom.fitImageFile.value = '';
    try {
      status(dom.fitStatus, `Reading ${file.name}…`);
      const bytes = new Uint8Array(await file.arrayBuffer());
      const raster = await decodeStillToRaster(bytes, file.name);
      fitTo(extractPalette(raster).colors.map((c) => c.hex));
    } catch (err) {
      if (dom.fitImageBtn) dom.fitImageBtn.disabled = false;
      status(dom.fitStatus, `Fit failed: ${err.message}`, 'err');
    }
  });

  // ---- Saves -----------------------------------------------------------
  // Backed by the store (`saves.js`), which is the dev server's `saved/` folder when there is
  // one and `localStorage` when there is not. The panel used to disable itself outright
  // without a server, which meant the standalone build — the whole point of `npm run build` —
  // could not keep a palette at all.
  async function refreshSaves() {
    try {
      const names = await store.list();
      const current = dom.savesSelect.value;
      dom.savesSelect.innerHTML = '<option value="">Load saved…</option>';
      for (const name of names) dom.savesSelect.appendChild(option(name, name));
      if (names.includes(current)) dom.savesSelect.value = current;
      dom.saveDelete.disabled = !dom.savesSelect.value;
      // Where a save goes is a different promise in each backend, so it is always stated.
      if (!dom.savesStatus.textContent) status(dom.savesStatus, `Saves go to ${store.where()}.`);
    } catch (err) {
      status(dom.savesStatus, `Could not read saves: ${err.message}`, 'err');
    }
  }

  /** Load one save by name, reporting into the panel. Shared with the Start tab's library. */
  async function loadSave(name) {
    try {
      const ok = actions.loadJson(await store.read(name));
      if (ok) {
        dom.saveName.value = name;
        dom.savesSelect.value = name;
        dom.saveDelete.disabled = false;
        status(dom.savesStatus, `Loaded "${name}"`, 'ok');
      } else {
        status(dom.savesStatus, 'That save is not a valid palette', 'err');
      }
      return ok;
    } catch (err) {
      status(dom.savesStatus, `Load failed: ${err.message}`, 'err');
      return false;
    }
  }

  /**
   * Write the current palette under `name`. Returns the name on success, null on failure.
   * The one-click Keep button and the named Save button both come through here.
   */
  async function save(name) {
    if (!isSaveName(name)) {
      status(dom.savesStatus, 'Name: letters, numbers, space, - and _ (max 64)', 'err');
      return null;
    }
    try {
      await store.write(name, runExport('json', actions.getPalette(), { name }));
      await refreshSaves();
      dom.savesSelect.value = name;
      dom.saveName.value = name;
      dom.saveDelete.disabled = false;
      status(dom.savesStatus, `Saved "${name}" to ${store.where()}`, 'ok');
      actions.onSaved?.(name);
      return name;
    } catch (err) {
      status(dom.savesStatus, `Save failed: ${err.message}`, 'err');
      return null;
    }
  }

  dom.savesSelect.addEventListener('change', () => {
    dom.saveDelete.disabled = !dom.savesSelect.value;
    if (dom.savesSelect.value) loadSave(dom.savesSelect.value);
  });

  dom.saveBtn.addEventListener('click', () => save(dom.saveName.value.trim()));

  dom.saveDelete.addEventListener('click', async () => {
    const name = dom.savesSelect.value;
    if (!name) return;
    try {
      await store.remove(name);
      await refreshSaves();
      status(dom.savesStatus, `Deleted "${name}"`, 'ok');
      actions.onSaved?.(name);
    } catch (err) {
      status(dom.savesStatus, `Delete failed: ${err.message}`, 'err');
    }
  });

  /** Push the current seed into the field and the URL hash. */
  function updateSeed(seed) {
    if (document.activeElement !== dom.seedInput) dom.seedInput.value = seed;
    dom.seedInput.classList.remove('bad');
    writeSeedToHash(seed);
  }

  return { updateSeed, refreshSaves, loadSave, save, fitTo, pickImage };
}
