// Where kept palettes live (UX_PLAN U5.1/U5.3 — IMPROVEMENTS items 6 and 26).
//
// Saving used to mean the dev server: no `npm start`, no saves, and the standalone build —
// the double-clickable file that is the whole point of `npm run build` — could not keep a
// palette at all. That is half of why `saved/` is empty and a text file in the project root
// is holding pasted seeds instead.
//
// So this is a store with two backends behind one interface. Files when a server is there,
// because files are the ones you can copy, diff and commit; `localStorage` when it is not,
// because a palette you cannot keep is a palette you lose. Which one is in use is reported,
// never hidden: "kept in this browser" and "kept in saved/" are different promises.
//
// The autosave ring lives in `localStorage` in both cases. It is not a save — it is the
// safety net under the save button — and writing a file every few seconds would turn a
// version-controlled folder into a churn of junk.

import { pushAutosave } from '../core/library.js';

const SAVES_KEY = 'palette.saves.v1';
const RING_KEY = 'palette.autosave.v1';

/** Read the whole local save map, tolerating a corrupted or absent store. */
function readLocal() {
  try {
    const raw = JSON.parse(localStorage.getItem(SAVES_KEY) || '{}');
    return raw && typeof raw === 'object' ? raw : {};
  } catch { return {}; }
}

function writeLocal(map) {
  localStorage.setItem(SAVES_KEY, JSON.stringify(map));
}

/**
 * Build the save store. `ready` resolves to the backend actually in use once the probe for
 * the dev server has come back; every other method awaits it, so callers never have to.
 */
export function createSaveStore() {
  let backend = null;
  const ready = (async () => {
    try {
      const res = await fetch('/api/saves', { cache: 'no-store' });
      backend = res.ok ? 'server' : 'local';
    } catch {
      backend = 'local';
    }
    return backend;
  })();

  /** Names of every save, alphabetical, so the library has a stable order. */
  async function list() {
    if (await ready === 'server') {
      const res = await fetch('/api/saves', { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return (await res.json()).sort();
    }
    return Object.keys(readLocal()).sort();
  }

  /** The JSON text of one save. */
  async function read(name) {
    if (await ready === 'server') {
      const res = await fetch(`/api/saves/${encodeURIComponent(name)}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.text();
    }
    const text = readLocal()[name];
    if (text === undefined) throw new Error('no such save');
    return text;
  }

  async function write(name, text) {
    if (await ready === 'server') {
      const res = await fetch(`/api/saves/${encodeURIComponent(name)}`, {
        method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: text,
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return;
    }
    const map = readLocal();
    map[name] = text;
    writeLocal(map); // throws on a full quota, which the caller reports rather than swallows
  }

  async function remove(name) {
    if (await ready === 'server') {
      const res = await fetch(`/api/saves/${encodeURIComponent(name)}`, { method: 'DELETE' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return;
    }
    const map = readLocal();
    delete map[name];
    writeLocal(map);
  }

  /** Where saves are going, in words fit to show the user. */
  function where() {
    return backend === 'server' ? 'saved/' : backend === 'local' ? 'this browser' : '…';
  }

  return { ready, list, read, write, remove, where, backend: () => backend };
}

/** The autosave ring as stored, newest first; `[]` when there is nothing or it is unreadable. */
export function loadRing() {
  try {
    const raw = JSON.parse(localStorage.getItem(RING_KEY) || '[]');
    return Array.isArray(raw) ? raw.filter((e) => e && typeof e.seed === 'string') : [];
  } catch { return []; }
}

/** Record one palette in the ring and store it. Returns the new ring. */
export function recordRing(entry) {
  const next = pushAutosave(loadRing(), entry);
  try { localStorage.setItem(RING_KEY, JSON.stringify(next)); } catch { /* full: keep the in-memory one */ }
  return next;
}
