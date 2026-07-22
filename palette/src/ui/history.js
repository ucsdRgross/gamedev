// Undo/redo plus a 20-deep clickable history strip (PLAN §12). Each entry stores a
// full state snapshot and a thumbnail of the palette it produced, so clicking any past
// palette restores exactly the parameters, locks and overrides that made it.

const MAX = 20;
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
  const items = []; // { snapshot, hexes }
  let cursor = -1;

  const canUndo = () => cursor > 0;
  const canRedo = () => cursor < items.length - 1;

  /** Append a new state, discarding any redo tail; caps the list at MAX entries. */
  function push(state, hexes) {
    if (cursor < items.length - 1) items.splice(cursor + 1);
    items.push({ snapshot: cloneState(state), hexes: hexes.slice(0, THUMB_BARS) });
    if (items.length > MAX) items.shift();
    cursor = items.length - 1;
    render();
    onChange?.();
  }

  /** Overwrite the current entry — used to coalesce a slider drag into one history step. */
  function replaceCurrent(state, hexes) {
    if (cursor < 0) return push(state, hexes);
    items[cursor] = { snapshot: cloneState(state), hexes: hexes.slice(0, THUMB_BARS) };
    render();
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

  /** Draw the strip; the current entry is outlined. */
  function render() {
    container.innerHTML = '';
    items.forEach((item, i) => {
      const el = document.createElement('div');
      el.className = `history-item${i === cursor ? ' current' : ''}`;
      el.title = i === cursor ? 'current' : 'restore this palette';
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

  return { push, replaceCurrent, undo, redo, canUndo, canRedo };
}
