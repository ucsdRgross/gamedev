// The rules for keeping palettes (UX_PLAN U5.1 and U5.3 — IMPROVEMENTS items 6 and 26).
//
// Two things are kept, and they are not the same thing:
//
//   * **Saves** are deliberate. You pressed Keep, the palette has a name, and it stays until
//     you delete it.
//   * The **autosave ring** is not. It records palettes you sat with, oldest falling off the
//     end, so that the palette you had ten minutes ago is recoverable even though you never
//     decided it was worth recovering. That is the case the save button cannot cover, because
//     by the time you know you wanted it you have already moved on.
//
// The storage itself is the UI's problem (`localStorage` is browser-only and core is not).
// What lives here is the part with rules: what a save may be called, and what the ring does
// when the same palette arrives twice.

/**
 * What a save may be called — the same rule the dev server's `/api/saves` enforces, so a name
 * accepted here is never rejected on write. Letters, digits, spaces, `-` and `_`, 1 to 64.
 */
export const SAVE_NAME_RE = /^[A-Za-z0-9 _-]{1,64}$/;

/** True when `name` is a legal save name. */
export function isSaveName(name) {
  return SAVE_NAME_RE.test(String(name ?? ''));
}

/**
 * Coerce arbitrary text into a legal save name, or `''` if nothing usable is left.
 * Used when a name arrives from outside — an imported file, a pasted list, a dropped image.
 */
export function toSaveName(text) {
  const cleaned = String(text ?? '').replace(/[^A-Za-z0-9 _-]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 64);
  return isSaveName(cleaned) ? cleaned : '';
}

/** How many palettes the ring remembers. Twelve is about an afternoon's worth of detours. */
export const AUTOSAVE_CAP = 12;

/**
 * Add one entry to the front of the autosave ring, newest first.
 *
 * Entries are identified by `seed`: a palette that comes back — an undo, a Before/After, a
 * reloaded page — moves to the front instead of appearing twice, so the ring holds twelve
 * *different* palettes rather than twelve records of the same one. Pure, so the caller can
 * keep the ring wherever it likes.
 */
export function pushAutosave(ring, entry, { cap = AUTOSAVE_CAP } = {}) {
  if (!entry?.seed) return Array.isArray(ring) ? [...ring] : [];
  const rest = (Array.isArray(ring) ? ring : []).filter((e) => e?.seed !== entry.seed);
  return [entry, ...rest].slice(0, Math.max(1, cap));
}
