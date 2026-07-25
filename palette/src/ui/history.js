// Undo/redo plus a clickable history strip (PLAN §12, extended by UX_PLAN U3.3 — item 28).
//
// Each entry stores a full state snapshot, a thumbnail of the palette it produced, and a
// label saying what changed to get there, so clicking any past palette restores exactly the
// parameters, locks and overrides that made it — and hovering says why it is different.
//
// The list is 100 deep and survives a reload (`serialize`/`restore`, persisted by app.js):
// twenty in-memory steps was thin the moment variant-picking existed, and a good palette
// lost to a stray drag three reloads ago is the failure this whole phase is about.

const MAX = 100;
const THUMB_BARS = 18;

/** Deep-copy a state snapshot so later mutations can't reach back into history. */
export function cloneState(state) {
  return {
    params: { ...state.params },
    locks: { ...state.locks },
    overrides: { ...state.overrides },
  };
}

/**
 * Create the history controller. `onRestore(snapshot)` is called when the user clicks a
 * strip entry; `onChange()` fires whenever the undo/redo availability may have changed.
 */
export function createHistory(container, { onRestore, onChange }) {
  const items = []; // { snapshot, hexes, label }
  let cursor = -1;

  const canUndo = () => cursor > 0;
  const canRedo = () => cursor < items.length - 1;

  /** Append a new state, discarding any redo tail; caps the list at MAX entries. */
  function push(state, hexes, label = '') {
    if (cursor < items.length - 1) items.splice(cursor + 1);
    items.push({ snapshot: cloneState(state), hexes: hexes.slice(0, THUMB_BARS), label });
    if (items.length > MAX) items.shift();
    cursor = items.length - 1;
    render();
    onChange?.();
  }

  /** Overwrite the current entry — used to coalesce a slider drag into one history step. */
  function replaceCurrent(state, hexes, label = '') {
    if (cursor < 0) return push(state, hexes, label);
    items[cursor] = {
      snapshot: cloneState(state),
      hexes: hexes.slice(0, THUMB_BARS),
      label: label || items[cursor].label,
    };
    render();
    onChange?.();
    return undefined;
  }

  function undo() {
    if (!canUndo()) return null;
    cursor -= 1;
    render();
    onChange?.();
    return items[cursor].snapshot;
  }

  function redo() {
    if (!canRedo()) return null;
    cursor += 1;
    render();
    onChange?.();
    return items[cursor].snapshot;
  }

  /** The snapshot one step back, without moving the cursor (the Before/After view). */
  function previous() {
    return cursor > 0 ? items[cursor - 1].snapshot : null;
  }

  /** Draw the strip; the current entry is outlined. */
  function render() {
    container.innerHTML = '';
    items.forEach((item, i) => {
      const el = document.createElement('div');
      el.className = `history-item${i === cursor ? ' current' : ''}`;
      const what = item.label ? `${item.label}\n` : '';
      el.title = i === cursor ? `${what}current` : `${what}restore this palette`;
      for (const hex of item.hexes) {
        const bar = document.createElement('i');
        bar.style.background = hex;
        el.appendChild(bar);
      }
      el.addEventListener('click', () => {
        if (i === cursor) return;
        cursor = i;
        render();
        onChange?.();
        onRestore(items[i].snapshot);
      });
      container.appendChild(el);
    });
    // Keep the newest entry in view.
    container.scrollLeft = container.scrollWidth;
  }

  /** The whole strip as plain data, for persistence. */
  function serialize() {
    return { v: 1, cursor, items: items.map((it) => ({ ...it, snapshot: cloneState(it.snapshot) })) };
  }

  /**
   * Replace the strip from `serialize` output. Returns the snapshot the cursor lands on, or
   * null if the data is unusable — a corrupt or outdated store must never stop the app from
   * booting into a working default.
   */
  function restore(data) {
    if (!data || data.v !== 1 || !Array.isArray(data.items) || !data.items.length) return null;
    items.length = 0;
    for (const it of data.items) {
      if (!it?.snapshot?.params || !Array.isArray(it.hexes)) continue;
      items.push({
        snapshot: {
          params: { ...it.snapshot.params },
          locks: { ...(it.snapshot.locks || {}) },
          overrides: { ...(it.snapshot.overrides || {}) },
        },
        hexes: it.hexes.slice(0, THUMB_BARS),
        label: it.label || '',
      });
    }
    if (!items.length) return null;
    cursor = Math.min(Math.max(0, data.cursor ?? items.length - 1), items.length - 1);
    render();
    onChange?.();
    return items[cursor].snapshot;
  }

  return { push, replaceCurrent, undo, redo, canUndo, canRedo, previous, serialize, restore };
}
