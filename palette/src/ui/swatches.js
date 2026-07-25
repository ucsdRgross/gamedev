// Swatch grid (PLAN §12). Every colour shows its role, hex, OKLCH readout and semantic
// tags, with a lock toggle and an inline override editor. A slim grayscale strip beside
// each colour is the value-only view — the single most important pixel-art check.

import { semanticsBySlot } from '../core/roles.js';
import { oklchToSrgb, srgbToRgb8, rgb8ToHex } from '../core/oklch.js';
import { colorLabel } from '../core/colornames.js';
import { arrangeEntries, ARRANGEMENTS } from '../core/arrange.js';
import { rampEvenness } from '../core/analysis.js';
import { entryDivergence } from '../core/diagnose.js';

const HEX_RE = /^#?[0-9a-fA-F]{6}$/;

/** Normalise a user-typed hex to `#RRGGBB`, or null if it is not a full 6-digit hex. */
export function parseHexInput(raw) {
  const s = String(raw || '').trim();
  if (!HEX_RE.test(s)) return null;
  return `#${s.replace('#', '').toUpperCase()}`;
}

/** The neutral gray of the same OKLCH lightness — the swatch's value-only appearance. */
function valueHex(entry) {
  return rgb8ToHex(srgbToRgb8(oklchToSrgb(entry.actual.L, 0, 0)));
}

/**
 * Build the swatch grid and return a controller.
 * Actions: `toggleLock(id)`, `setOverride(id, hex)`, `clearOverride(id)`, `copy(hex)`.
 *
 * `modeSelect` is the optional arrangement selector (UX_PLAN U4.5): the same colours grouped
 * as ramps, or sorted by lightness or hue. Regrouping is a view — `arrangeEntries` in core
 * guarantees every colour is still shown exactly once — so the grid rebuilds from it directly.
 * `pinned` is the "3 locked, 1 overridden — clear all" line (U7.6): a lock is invisible unless
 * you scan every card, which is how palettes end up with pins nobody remembers setting.
 */
export function createSwatches(container, actions, { modeSelect, pinned } = {}) {
  container.innerHTML = '';
  const grid = document.createElement('div');
  grid.className = 'swatch-grid';
  container.appendChild(grid);
  let mode = 'slot';
  let last = null;
  let flagged = []; // slot ids the report card has asked to point at

  if (modeSelect) {
    modeSelect.innerHTML = '';
    for (const [id, label, hint] of ARRANGEMENTS) {
      const o = document.createElement('option');
      o.value = id;
      o.textContent = label;
      o.title = hint;
      modeSelect.appendChild(o);
    }
    modeSelect.value = mode;
    modeSelect.addEventListener('change', () => {
      mode = modeSelect.value;
      modeSelect.title = ARRANGEMENTS.find(([id]) => id === mode)?.[2] || '';
      if (last) render(last);
    });
  }

  /**
   * The pinned-colours line: how many colours are being held, and one button to release them.
   * Clicking the count flags them in the grid, which is the only way to find a lock set
   * twenty edits ago without reading every card.
   */
  function renderPinned(palette) {
    if (!pinned) return;
    const locked = palette.entries.filter((e) => e.locked);
    const overridden = palette.entries.filter((e) => e.overridden);
    const all = [...new Set([...locked, ...overridden])];
    pinned.hidden = all.length === 0;
    if (!all.length) return;
    pinned.innerHTML = '';
    const count = document.createElement('button');
    count.className = 'pinned-count';
    count.textContent = [
      locked.length ? `${locked.length} locked` : '',
      overridden.length ? `${overridden.length} overridden` : '',
    ].filter(Boolean).join(' · ');
    count.title = 'Show which colours are being held';
    count.addEventListener('click', () => {
      const on = flagged.length !== all.length;
      flagged = on ? all.map((e) => e.id) : [];
      applyFlags();
    });
    const clear = document.createElement('button');
    clear.className = 'btn btn-small';
    clear.textContent = 'Clear all';
    clear.title = 'Release every locked and overridden colour, letting the generator decide them again';
    clear.addEventListener('click', () => actions.clearPins());
    pinned.append(count, clear);
  }

  /** Redraw the grid from a freshly generated palette. */
  function render(palette) {
    last = palette;
    renderPinned(palette);
    // The grid is thrown away and rebuilt on every edit, so a card being nudged with the arrow
    // keys would lose focus after the first press and the second would go nowhere.
    const focused = document.activeElement?.closest?.('.swatch')?.dataset.slot;
    container.innerHTML = '';
    const bySlot = semanticsBySlot(palette.semantics);
    const groups = arrangeEntries(palette, mode);
    // One flat run with no heading is the plain grid: draw it straight into the container so
    // the markup — and the CSS grid it relies on — is exactly what it was before U4.5.
    if (groups.length === 1 && !groups[0].title) {
      container.appendChild(fill(document.createElement('div'), groups[0].entries, bySlot));
    } else {
      for (const group of groups) {
        const head = document.createElement('div');
        head.className = 'swatch-group-head';
        head.append(text('span', 'swatch-group-title', group.title));
        const note = groupNote(group, mode);
        if (note) head.append(text('span', 'swatch-group-note', note));
        container.append(head, fill(document.createElement('div'), group.entries, bySlot));
      }
    }
    applyFlags();
    if (focused) container.querySelector(`.swatch[data-slot="${focused}"]`)?.focus({ preventScroll: true });
  }

  /** Fill one grid element with swatch cards. */
  function fill(el, entries, bySlot) {
    el.className = 'swatch-grid';
    for (const entry of entries) el.appendChild(buildSwatch(entry, bySlot.get(entry.id) || [], actions));
    return el;
  }

  /**
   * Point at the slots a report-card finding names (UX_PLAN U7.2).
   *
   * The flag is re-applied after every rebuild rather than being set once on the DOM: the grid
   * is thrown away and rebuilt whenever the palette or the arrangement changes, and a finding
   * that stopped pointing at anything the moment a slider moved would be useless in the one
   * situation it exists for — watching whether the fix worked.
   */
  function applyFlags() {
    const wanted = new Set(flagged);
    let first = null;
    for (const card of container.querySelectorAll('.swatch')) {
      const on = wanted.has(card.dataset.slot);
      card.classList.toggle('is-flagged', on);
      if (on && !first) first = card;
    }
    first?.scrollIntoView({ block: 'nearest' });
  }

  return {
    render,
    /** Flag these slot ids, or clear the flags when given nothing. */
    highlight(ids) {
      flagged = ids || [];
      applyFlags();
    },
  };
}

/** A `<span>`-ish element with a class and text. */
function text(tag, className, content) {
  const el = document.createElement(tag);
  el.className = className;
  el.textContent = content;
  return el;
}

/**
 * The number worth printing beside a group heading.
 *
 * For a ramp that is its evenness: a ramp whose steps are unevenly spaced in lightness is
 * the thing the Ramps view exists to make visible, and the eye is poor at judging it from
 * four swatches. `rampEvenness` is the same metric the analysis and the dither reference use.
 */
function groupNote(group, mode) {
  if (mode !== 'ramps' || group.entries.length < 2) return '';
  const { evennessL, meanL } = rampEvenness(group.entries);
  const steps = `${group.entries.length} steps · ΔL ${meanL.toFixed(3)}`;
  // Two steps have exactly one gap, so "100% even" would be true of every two-step ramp
  // and would mean nothing. Evenness is only reported where there is something to compare.
  return group.entries.length < 3 ? steps : `${steps} · ${Math.round(evennessL * 100)}% even`;
}

/** Build one swatch card. */
function buildSwatch(entry, semanticNames, actions) {
  const card = document.createElement('div');
  card.className = 'swatch';
  card.dataset.slot = entry.id;
  if (entry.overridden) card.classList.add('overridden');
  else if (entry.fixed) card.classList.add('fixed');

  // Colour block with a value-only strip and the lock / override pills.
  // What to call this colour — a name when one is genuinely close, a plain description
  // otherwise (UX_PLAN U2.5, item 21). "the dusty rose one" is how palettes get discussed.
  const named = colorLabel(entry.hex);

  const color = document.createElement('div');
  color.className = 'swatch-color';
  color.style.background = entry.hex;
  color.title = `${named.label} · ${entry.hex} — click to copy`;
  const value = document.createElement('div');
  value.className = 'swatch-value';
  value.style.background = valueHex(entry);
  value.title = 'value-only view';
  color.appendChild(value);
  color.addEventListener('click', () => actions.copy(entry.hex));

  const pills = document.createElement('div');
  pills.className = 'swatch-actions';
  const lock = document.createElement('span');
  lock.className = `pill${entry.locked ? ' on-lock' : ''}`;
  lock.textContent = entry.locked ? 'Lock' : 'lock';
  lock.title = 'Keep this colour when you re-randomize';
  lock.addEventListener('click', (e) => { e.stopPropagation(); actions.toggleLock(entry.id); });
  const over = document.createElement('span');
  over.className = `pill${entry.overridden ? ' on-override' : ''}`;
  over.textContent = entry.overridden ? 'Ovr' : 'ovr';
  over.title = entry.overridden ? 'Clear this manual override' : 'Pin this exact colour';
  over.addEventListener('click', (e) => {
    e.stopPropagation();
    if (entry.overridden) actions.clearOverride(entry.id);
    else actions.setOverride(entry.id, entry.hex);
  });
  // The OKLCH editor (U7.6 — item 8). Separate from `ovr`, which pins the colour as it is:
  // this one opens the axes, the sRGB edge and the eyedropper, and pins whatever comes out.
  const edit = document.createElement('span');
  edit.className = 'pill';
  edit.textContent = 'edit';
  edit.title = 'Open the OKLCH editor — lightness, chroma, hue, the sRGB edge and an eyedropper';
  edit.addEventListener('click', (e) => {
    e.stopPropagation();
    actions.editColor(entry, card);
  });
  pills.append(lock, over, edit);
  color.appendChild(pills);
  card.appendChild(color);

  // Arrow keys nudge the colour once the card has focus: up/down lightness, left/right hue,
  // alt for chroma, shift for a bigger step. The fastest edit is the one that needs no dialogue.
  card.tabIndex = 0;
  card.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { actions.editColor(entry, card); e.preventDefault(); return; }
    if (actions.nudge(entry, e)) e.preventDefault();
  });

  // Body: role, editable hex, OKLCH readout, semantic tags.
  const body = document.createElement('div');
  body.className = 'swatch-body';

  const role = document.createElement('div');
  role.className = 'swatch-role';
  role.textContent = entry.role;
  role.title = `${entry.role} (${entry.layer}, slot ${entry.id})`;

  const hex = document.createElement('input');
  hex.className = 'swatch-hex';
  hex.value = entry.hex;
  hex.spellcheck = false;
  hex.setAttribute('aria-label', `${entry.role} hex`);
  const commitHex = () => {
    const parsed = parseHexInput(hex.value);
    if (parsed && parsed !== entry.hex) actions.setOverride(entry.id, parsed);
    else hex.value = entry.hex;
  };
  hex.addEventListener('change', commitHex);
  hex.addEventListener('keydown', (e) => { if (e.key === 'Enter') hex.blur(); });

  const colorName = document.createElement('div');
  colorName.className = `swatch-name${named.named ? '' : ' is-described'}`;
  colorName.textContent = named.label;
  colorName.title = named.named
    ? `Nearest named colour: ${named.label}`
    : 'No named colour is close enough, so this describes it instead';

  const oklch = document.createElement('div');
  oklch.className = 'swatch-oklch';
  const { L, C, h } = entry.actual;
  oklch.textContent = `L ${L.toFixed(3)}  C ${C.toFixed(3)}  H ${h.toFixed(0)}°`;

  // What was asked for versus what sRGB could give (UX_PLAN U7.2 — item 14, last row). The
  // sliders keep showing the request and the swatch shows the result, and until now nothing
  // connected the two: this is the answer to "why will this colour not get any more saturated".
  const diverged = entryDivergence(entry);
  if (diverged) {
    oklch.classList.add('is-clipped');
    oklch.title = `Requested C ${diverged.requested.toFixed(3)} — ${diverged.note}.`
      + ' sRGB has no more chroma at that hue and lightness.';
    const mark = document.createElement('span');
    mark.className = 'swatch-clip';
    mark.textContent = '↓C';
    oklch.appendChild(mark);
  }

  const tags = document.createElement('div');
  tags.className = 'swatch-tags';
  for (const nm of semanticNames) {
    const t = document.createElement('span');
    t.className = 'tag sem';
    t.textContent = nm;
    tags.appendChild(t);
  }

  body.append(role, colorName, hex, oklch, tags);
  card.appendChild(body);
  return card;
}
