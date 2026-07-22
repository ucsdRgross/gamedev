// Swatch grid (PLAN §12). Every colour shows its role, hex, OKLCH readout and semantic
// tags, with a lock toggle and an inline override editor. A slim grayscale strip beside
// each colour is the value-only view — the single most important pixel-art check.

import { semanticsBySlot } from '../core/roles.js';
import { oklchToSrgb, srgbToRgb8, rgb8ToHex } from '../core/oklch.js';

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
 */
export function createSwatches(container, actions) {
  container.innerHTML = '';
  const grid = document.createElement('div');
  grid.className = 'swatch-grid';
  container.appendChild(grid);

  /** Redraw the grid from a freshly generated palette. */
  function render(palette) {
    grid.innerHTML = '';
    const bySlot = semanticsBySlot(palette.semantics);
    for (const entry of palette.entries) {
      grid.appendChild(buildSwatch(entry, bySlot.get(entry.id) || [], actions));
    }
  }

  return { render };
}

/** Build one swatch card. */
function buildSwatch(entry, semanticNames, actions) {
  const card = document.createElement('div');
  card.className = 'swatch';
  if (entry.overridden) card.classList.add('overridden');
  else if (entry.fixed) card.classList.add('fixed');

  // Colour block with a value-only strip and the lock / override pills.
  const color = document.createElement('div');
  color.className = 'swatch-color';
  color.style.background = entry.hex;
  color.title = `${entry.hex} — click to copy`;
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
  pills.append(lock, over);
  color.appendChild(pills);
  card.appendChild(color);

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

  const oklch = document.createElement('div');
  oklch.className = 'swatch-oklch';
  const { L, C, h } = entry.actual;
  oklch.textContent = `L ${L.toFixed(3)}  C ${C.toFixed(3)}  H ${h.toFixed(0)}°`;

  const tags = document.createElement('div');
  tags.className = 'swatch-tags';
  for (const nm of semanticNames) {
    const t = document.createElement('span');
    t.className = 'tag sem';
    t.textContent = nm;
    tags.appendChild(t);
  }

  body.append(role, hex, oklch, tags);
  card.appendChild(body);
  return card;
}
