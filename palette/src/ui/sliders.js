// Parameter controls, generated entirely from the PARAMS schema (PLAN §5). The schema
// is the single source of truth — hand-writing controls here would drift out of sync
// with the seed codec's field order. Each control's tooltip is the schema doc string.

import { PARAMS, PARAM_GROUPS, defaultParams } from '../core/params.js';

const GROUP_LABELS = {
  structure: 'Structure',
  lightness: 'Lightness',
  chroma: 'Chroma / Saturation',
  shift: 'Hue Shifting',
  background: 'Background / Atmosphere',
  neutrals: 'Neutrals',
  accents: 'Accents',
  hardware: 'Hardware / Output',
  quality: 'Quality Constraints',
  meta: 'Meta',
  recolor: 'Reference Recolouring',
};

/** Format a numeric value for its spec (ints plain, floats to the step's precision). */
function fmt(spec, v) {
  if (spec.type === 'int') return String(Math.round(v));
  const decimals = spec.step && spec.step < 1 ? Math.min(4, String(spec.step).split('.')[1]?.length || 2) : 0;
  return Number(v).toFixed(decimals);
}

/**
 * Build the parameter panel once and return a controller.
 * `onChange(name, value, opts)` fires on every edit; `render(params)` re-syncs every
 * control to a parameter set (used after presets, seeds, undo and randomize).
 */
export function createSliders(container, { onChange }) {
  const defaults = defaultParams();
  const controls = new Map(); // name -> { sync(v), markChanged(bool), el }
  container.innerHTML = '';

  const tip = makeTooltip();

  for (const group of PARAM_GROUPS) {
    const specs = PARAMS.filter((p) => p.group === group);
    if (!specs.length) continue;
    const details = document.createElement('details');
    details.className = 'param-group';
    details.open = group === 'structure' || group === 'lightness' || group === 'chroma';
    const summary = document.createElement('summary');
    summary.textContent = GROUP_LABELS[group] || group;
    details.appendChild(summary);
    const body = document.createElement('div');
    body.className = 'param-group-body';
    details.appendChild(body);

    for (const spec of specs) body.appendChild(buildControl(spec, controls, onChange, tip));
    container.appendChild(details);
  }

  /** Re-sync every control and flag those that differ from their default. */
  function render(params) {
    for (const [name, c] of controls) {
      c.sync(params[name]);
      c.markChanged(!valueEquals(params[name], defaults[name]));
    }
  }

  return { render };
}

/** Loose equality that treats 0.1 and 0.1000001 (float step noise) as equal. */
function valueEquals(a, b) {
  if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b) < 1e-6;
  return a === b;
}

/**
 * A single shared hover tooltip. The parameter docs are two or three sentences — a native
 * `title` truncates them and lags — so a custom element shows the full text, positioned
 * beside the control and clamped to the viewport. One element for the whole panel.
 */
function makeTooltip() {
  const el = document.createElement('div');
  el.className = 'param-tip';
  el.hidden = true;
  document.body.appendChild(el);

  const show = (anchor, text) => {
    el.textContent = text;
    el.hidden = false;
    const r = anchor.getBoundingClientRect();
    // Prefer to the left of the params panel; fall back below the control if there is no room.
    const w = Math.min(320, window.innerWidth - 24);
    el.style.width = `${w}px`;
    let left = r.right + 10;
    if (left + w > window.innerWidth - 12) left = Math.max(12, r.left - w - 10);
    el.style.left = `${left}px`;
    const top = Math.min(r.top, window.innerHeight - el.offsetHeight - 12);
    el.style.top = `${Math.max(12, top)}px`;
  };
  const hide = () => { el.hidden = true; };

  /** Wire an element to show `text` on hover. */
  return function attach(anchor, text) {
    anchor.addEventListener('mouseenter', () => show(anchor, text));
    anchor.addEventListener('mouseleave', hide);
    // Hidden on any edit/scroll so it never sits stale over a moving control.
    anchor.addEventListener('mousedown', hide);
  };
}

/** Build the DOM for one parameter control and register its sync/mark hooks. */
function buildControl(spec, controls, onChange, tip) {
  const wrap = document.createElement('div');
  wrap.className = 'ctrl';

  if (spec.type === 'bool') {
    const label = document.createElement('label');
    label.className = 'ctrl-bool';
    const box = document.createElement('input');
    box.type = 'checkbox';
    const name = document.createElement('span');
    name.className = 'ctrl-name';
    name.textContent = spec.name;
    tip(name, spec.doc);
    label.append(box, name);
    wrap.appendChild(label);
    box.addEventListener('change', () => onChange(spec.name, box.checked));
    controls.set(spec.name, {
      sync: (v) => { box.checked = Boolean(v); },
      markChanged: (c) => wrap.classList.toggle('changed', c),
    });
    return wrap;
  }

  const head = document.createElement('div');
  head.className = 'ctrl-head';
  const name = document.createElement('span');
  name.className = 'ctrl-name';
  name.textContent = spec.name;
  tip(name, spec.doc);
  head.appendChild(name);

  if (spec.type === 'enum') {
    wrap.appendChild(head);
    const sel = document.createElement('select');
    sel.className = 'enum-select';
    for (const opt of spec.options) {
      const o = document.createElement('option');
      o.value = opt; o.textContent = opt;
      sel.appendChild(o);
    }
    wrap.appendChild(sel);
    sel.addEventListener('change', () => onChange(spec.name, sel.value));
    controls.set(spec.name, {
      sync: (v) => { sel.value = v; },
      markChanged: (c) => wrap.classList.toggle('changed', c),
    });
    return wrap;
  }

  // float / int: a readout that doubles as a number input, plus a range slider.
  const valWrap = document.createElement('span');
  valWrap.className = 'ctrl-val';
  const num = document.createElement('input');
  num.type = 'number';
  num.min = spec.min; num.max = spec.max; num.step = spec.step;
  valWrap.appendChild(num);
  head.appendChild(valWrap);
  wrap.appendChild(head);

  const range = document.createElement('input');
  range.type = 'range';
  range.min = spec.min; range.max = spec.max; range.step = spec.step;
  tip(range, spec.doc);
  wrap.appendChild(range);

  // A slider drag should be a single history step: the first `input` opens a new entry,
  // every later `input` and the closing `change` coalesce into it.
  let dragging = false;
  const emit = (raw, coalesce) => {
    const v = spec.type === 'int' ? Math.round(Number(raw)) : Number(raw);
    onChange(spec.name, v, { coalesce });
  };
  range.addEventListener('input', () => { num.value = range.value; emit(range.value, dragging); dragging = true; });
  range.addEventListener('change', () => { emit(range.value, true); dragging = false; });
  num.addEventListener('change', () => { range.value = num.value; emit(num.value, false); });

  controls.set(spec.name, {
    sync: (v) => {
      if (document.activeElement !== range) range.value = v;
      if (document.activeElement !== num) num.value = fmt(spec, v);
    },
    markChanged: (c) => wrap.classList.toggle('changed', c),
  });
  return wrap;
}
