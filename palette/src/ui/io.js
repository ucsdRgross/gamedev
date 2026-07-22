// Input/output surface (PLAN §12, §10): the seed field with URL-hash mirroring, the
// preset dropdown, the saved-palette dropdown backed by the dev server's /api/saves,
// import from a JSON file, and one download button per export format.

import { PRESETS } from '../core/presets.js';
import { EXPORTERS, runExport } from '../core/export/index.js';

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
 *   loadSeed(str), applyPreset(id), loadJson(text), getPalette(), getSaveName().
 * Returns `{ updateSeed(seed), refreshSaves() }` for the app to call after regeneration.
 */
export function createIO(dom, actions) {
  // ---- Presets --------------------------------------------------------
  for (const preset of PRESETS) {
    const o = document.createElement('option');
    o.value = preset.id;
    o.textContent = preset.name;
    dom.presetSelect.appendChild(o);
  }
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

  // ---- Saves (dev-server backed) --------------------------------------
  let savesAvailable = true;

  async function refreshSaves() {
    try {
      const res = await fetch('/api/saves');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const names = await res.json();
      const current = dom.savesSelect.value;
      dom.savesSelect.innerHTML = '<option value="">Load saved…</option>';
      for (const name of names) {
        const o = document.createElement('option');
        o.value = name; o.textContent = name;
        dom.savesSelect.appendChild(o);
      }
      if (names.includes(current)) dom.savesSelect.value = current;
      dom.saveDelete.disabled = !dom.savesSelect.value;
    } catch {
      savesAvailable = false;
      dom.savesSelect.innerHTML = '<option value="">(dev server only)</option>';
      dom.savesSelect.disabled = true;
      dom.saveBtn.disabled = true;
      dom.saveDelete.disabled = true;
      status(dom.savesStatus, 'File saves need `npm start`; use Export/Import here.');
    }
  }

  dom.savesSelect.addEventListener('change', async () => {
    dom.saveDelete.disabled = !dom.savesSelect.value;
    if (!dom.savesSelect.value) return;
    try {
      const res = await fetch(`/api/saves/${encodeURIComponent(dom.savesSelect.value)}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const text = await res.text();
      const ok = actions.loadJson(text);
      if (ok) {
        dom.saveName.value = dom.savesSelect.value;
        status(dom.savesStatus, `Loaded "${dom.savesSelect.value}"`, 'ok');
      } else {
        status(dom.savesStatus, 'That save is not a valid palette', 'err');
      }
    } catch (err) {
      status(dom.savesStatus, `Load failed: ${err.message}`, 'err');
    }
  });

  dom.saveBtn.addEventListener('click', async () => {
    if (!savesAvailable) return;
    const name = dom.saveName.value.trim();
    if (!/^[A-Za-z0-9 _-]{1,64}$/.test(name)) {
      status(dom.savesStatus, 'Name: letters, numbers, space, - and _ (max 64)', 'err');
      return;
    }
    try {
      const body = runExport('json', actions.getPalette(), { name });
      const res = await fetch(`/api/saves/${encodeURIComponent(name)}`, {
        method: 'PUT', headers: { 'Content-Type': 'application/json' }, body,
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      await refreshSaves();
      dom.savesSelect.value = name;
      dom.saveDelete.disabled = false;
      status(dom.savesStatus, `Saved "${name}"`, 'ok');
    } catch (err) {
      status(dom.savesStatus, `Save failed: ${err.message}`, 'err');
    }
  });

  dom.saveDelete.addEventListener('click', async () => {
    const name = dom.savesSelect.value;
    if (!name) return;
    try {
      const res = await fetch(`/api/saves/${encodeURIComponent(name)}`, { method: 'DELETE' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      await refreshSaves();
      status(dom.savesStatus, `Deleted "${name}"`, 'ok');
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

  return { updateSeed, refreshSaves };
}
