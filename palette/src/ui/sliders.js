// Parameter controls, generated entirely from the PARAMS schema (PLAN §5). The schema
// is the single source of truth — hand-writing controls here would drift out of sync
// with the seed codec's field order.
//
// What a control shows (UX_PLAN U1): the human-readable `label`, a one-line `hint`, and —
// for a numeric parameter — what each *end* of its range means. A slider whose two ends are
// named does not need its documentation read, which is the whole point; the full `doc` string
// is still one hover away, under the raw parameter name so it stays greppable.
//
// The panel toolbar filters rather than reorganises: search, Basics/All, and "only changed".
// Nothing is ever removed from the panel — every parameter is always one click from view.

import {
  PARAMS, PARAM_GROUPS, BASIC_PARAM_NAMES, defaultParams, optionLabel,
} from '../core/params.js';
import { sweepPalettes, findClamp } from '../core/preview.js';
import { stripElement } from './strip.js';

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

const BASICS = new Set(BASIC_PARAM_NAMES);

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
 * `toolbar` is the element the filter row is built into (optional).
 */
export function createSliders(container, { onChange, toolbar, getState }) {
  const defaults = defaultParams();
  const controls = new Map(); // name -> { sync(v), markChanged(bool), el }
  const rows = []; // { spec, wrap, group } — everything the filter walks
  const groupEls = new Map(); // group -> { details, body, count }
  const changed = new Set();
  let filter = { text: '', basics: false, changedOnly: false };
  container.innerHTML = '';

  const tip = makeTooltip(getState);

  /** Reset a list of parameters to their defaults as one history step. */
  function resetNames(names) {
    names.forEach((name, idx) => onChange(name, defaults[name], { coalesce: idx > 0 }));
  }

  for (const group of PARAM_GROUPS) {
    const specs = PARAMS.filter((p) => p.group === group);
    if (!specs.length) continue;
    const details = document.createElement('details');
    details.className = 'param-group';
    details.open = group === 'structure' || group === 'lightness' || group === 'chroma';
    const summary = document.createElement('summary');
    const title = document.createElement('span');
    title.textContent = GROUP_LABELS[group] || group;
    const reset = document.createElement('button');
    reset.className = 'group-reset';
    reset.textContent = '↺';
    reset.title = `Reset every ${GROUP_LABELS[group] || group} parameter to its default`;
    // A button inside <summary> would otherwise toggle the disclosure as well.
    reset.addEventListener('click', (ev) => {
      ev.preventDefault();
      ev.stopPropagation();
      resetNames(specs.map((s) => s.name));
    });
    summary.append(title, reset);
    details.appendChild(summary);
    const body = document.createElement('div');
    body.className = 'param-group-body';
    details.appendChild(body);

    for (const spec of specs) {
      const wrap = buildControl(spec, controls, onChange, defaults, getState);
      // One hover surface per control: the whole row shows the name, the documentation and
      // the sweep. Attaching to the label and the slider separately meant two floating
      // panels fighting over the same corner of the screen.
      tip.attach(wrap, spec);
      body.appendChild(wrap);
      rows.push({ spec, wrap, group });
    }
    container.appendChild(details);
    groupEls.set(group, { details, body });
  }

  if (toolbar) buildToolbar(toolbar, filter, applyFilter, () => resetNames(PARAMS.map((p) => p.name)));

  /** Show or hide each control for the current filter, then hide the empty groups. */
  function applyFilter() {
    const q = filter.text.trim().toLowerCase();
    const shownPerGroup = new Map();
    for (const { spec, wrap, group } of rows) {
      const hay = `${spec.label} ${spec.name} ${spec.hint} ${spec.doc}`.toLowerCase();
      const show = (!q || hay.includes(q))
        && (!filter.basics || BASICS.has(spec.name))
        && (!filter.changedOnly || changed.has(spec.name));
      wrap.hidden = !show;
      if (show) shownPerGroup.set(group, (shownPerGroup.get(group) || 0) + 1);
    }
    const filtering = Boolean(q) || filter.basics || filter.changedOnly;
    for (const [group, { details }] of groupEls) {
      const n = shownPerGroup.get(group) || 0;
      details.hidden = n === 0;
      // While a filter is on, a collapsed group would hide its own matches.
      if (filtering && n > 0) details.open = true;
    }
  }

  /** Re-sync every control and flag those that differ from their default. */
  function render(params) {
    // Every sweep was computed against the previous parameters, so it is now stale.
    tip.invalidate();
    changed.clear();
    for (const [name, c] of controls) {
      c.sync(params[name]);
      const isChanged = !valueEquals(params[name], defaults[name]);
      if (isChanged) changed.add(name);
      c.markChanged(isChanged);
    }
    applyFilter();
  }

  return {
    render,
    /**
     * Mark (or unmark) a control as one that just did nothing (UX_PLAN U7.3 — item 35).
     * `effect` is a `paramEffect` result; passing null takes the mark off.
     */
    markStuck(name, effect) {
      controls.get(name)?.markStuck?.(effect);
    },
    /** Take every mark off — the parameter set they were measured against has been replaced. */
    clearStuck() {
      for (const c of controls.values()) c.markStuck?.(null);
    },
  };
}

/** The filter row above the panel: search, Basics/All, only-changed, reset-all. */
function buildToolbar(toolbar, filter, applyFilter, resetAll) {
  toolbar.innerHTML = '';

  const search = document.createElement('input');
  search.type = 'search';
  search.className = 'param-search';
  search.placeholder = 'Search parameters…';
  search.spellcheck = false;
  search.title = 'Filter by name, label, hint or documentation — try "shadow" or "contrast"';
  search.addEventListener('input', () => { filter.text = search.value; applyFilter(); });

  const basics = toggleButton('Basics', 'Show only the parameters that decide most of the look', (on) => {
    filter.basics = on;
    applyFilter();
  });
  const changedOnly = toggleButton('Changed', 'Show only the parameters that differ from their default — what makes this palette what it is', (on) => {
    filter.changedOnly = on;
    applyFilter();
  });

  const help = document.createElement('span');
  help.className = 'param-toolbar-hint';
  help.textContent = 'alt-click a name to reset it';
  help.title = 'Alt-click any parameter name to put it back to its default; ↺ on a group header resets the whole group';
  help.addEventListener('click', (ev) => { if (ev.altKey) resetAll(); });

  toolbar.append(search, basics, changedOnly, help);
}

/** A small two-state button; `onToggle(on)` fires on every press. */
function toggleButton(text, title, onToggle) {
  const btn = document.createElement('button');
  btn.className = 'btn btn-small toggle-btn';
  btn.textContent = text;
  btn.title = title;
  btn.setAttribute('aria-pressed', 'false');
  btn.addEventListener('click', () => {
    const on = btn.getAttribute('aria-pressed') !== 'true';
    btn.setAttribute('aria-pressed', String(on));
    btn.classList.toggle('is-on', on);
    onToggle(on);
  });
  return btn;
}

/** Loose equality that treats 0.1 and 0.1000001 (float step noise) as equal. */
function valueEquals(a, b) {
  if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b) < 1e-6;
  return a === b;
}

// How long the pointer has to rest on a control before its sweep is generated. A sweep is
// five whole palettes; sliding the pointer down the panel should not build sixty of them.
const PREVIEW_DELAY_MS = 160;
const PREVIEW_STEPS = 5;

/**
 * The single floating panel a control shows on hover (UX_PLAN U2.4). It carries three things,
 * in increasing order of usefulness:
 *
 *   1. the raw parameter name — the panel shows a human label, but the name is what appears
 *      in the README, in seeds and in the source, so it must stay findable;
 *   2. the full `doc` string, which a native `title` would truncate and delay;
 *   3. **the sweep** — the palette this parameter produces at five points across its range,
 *      with the current one marked. This is the part that makes reading (1) and (2) optional.
 *
 * The sweep needs the live parameter set, so the panel is built with a `getState` accessor
 * rather than being handed values; it is cached per parameter and thrown away on any edit.
 */
function makeTooltip(getState) {
  const el = document.createElement('div');
  el.className = 'param-tip';
  el.hidden = true;
  const head = document.createElement('b');
  head.className = 'param-tip-name';
  const body = document.createElement('span');
  const sweepBox = document.createElement('div');
  sweepBox.className = 'param-sweep';
  el.append(head, body, sweepBox);
  document.body.appendChild(el);

  const cache = new Map(); // parameter name -> built sweep element
  let timer = null;
  let shownFor = null;

  /** Position the panel beside `anchor`, clamped to the viewport. */
  const place = (anchor) => {
    const r = anchor.getBoundingClientRect();
    const w = Math.min(320, window.innerWidth - 24);
    el.style.width = `${w}px`;
    let left = r.right + 10;
    if (left + w > window.innerWidth - 12) left = Math.max(12, r.left - w - 10);
    el.style.left = `${left}px`;
    const top = Math.min(r.top, window.innerHeight - el.offsetHeight - 12);
    el.style.top = `${Math.max(12, top)}px`;
  };

  /** The five-strip sweep for one parameter, built once per parameter set. */
  const buildSweep = (spec) => {
    if (cache.has(spec.name)) return cache.get(spec.name);
    const box = document.createElement('div');
    const state = getState?.();
    if (!state?.params) return box;
    let steps = [];
    try {
      steps = sweepPalettes(state.params, spec.name, PREVIEW_STEPS, {
        locks: state.locks || {},
        overrides: state.overrides || {},
      });
    } catch {
      return box; // a preview must never be the thing that breaks the panel
    }
    for (const step of steps) {
      const row = document.createElement('div');
      row.className = `sweep-row${step.current ? ' is-current' : ''}`;
      const label = document.createElement('span');
      label.className = 'sweep-label';
      label.textContent = step.label;
      row.append(label, stripElement(step.hexes, { className: 'sweep-strip' }));
      box.appendChild(row);
    }
    cache.set(spec.name, box);
    return box;
  };

  const show = (anchor, spec) => {
    shownFor = spec.name;
    head.textContent = spec.name;
    body.textContent = spec.doc;
    sweepBox.innerHTML = '';
    el.hidden = false;
    place(anchor);
    // The text appears immediately; the sweep arrives a moment later so that skimming the
    // panel costs nothing.
    clearTimeout(timer);
    timer = setTimeout(() => {
      if (shownFor !== spec.name || el.hidden) return;
      sweepBox.appendChild(buildSweep(spec));
      place(anchor);
    }, PREVIEW_DELAY_MS);
  };

  const hide = () => {
    clearTimeout(timer);
    shownFor = null;
    el.hidden = true;
  };

  return {
    /** Wire a control row to show its documentation and sweep on hover. */
    attach(anchor, spec) {
      anchor.addEventListener('mouseenter', () => show(anchor, spec));
      anchor.addEventListener('mouseleave', hide);
      // Hidden on any edit/scroll so it never sits stale over a moving control.
      anchor.addEventListener('mousedown', hide);
    },
    /** Drop every cached sweep — they were computed against the old parameter set. */
    invalidate() {
      cache.clear();
      hide();
    },
  };
}

/** The label element: human name, alt-click to reset to default. */
function makeName(spec, onChange, defaults) {
  const name = document.createElement('span');
  name.className = 'ctrl-name';
  name.textContent = spec.label;
  name.title = spec.name;
  name.addEventListener('click', (ev) => {
    if (!ev.altKey) return;
    ev.preventDefault();
    onChange(spec.name, defaults[spec.name], { coalesce: false });
  });
  return name;
}

/** The one-line "what it does" under a control. */
function makeHint(spec) {
  const hint = document.createElement('div');
  hint.className = 'ctrl-hint';
  hint.textContent = spec.hint;
  return hint;
}

/**
 * The "this control just did nothing" badge (UX_PLAN U7.3 — item 35).
 *
 * Two states, and the difference matters. *At its limit* is the user's own doing and needs no
 * explanation. **Clamped** means the value moved and the palette did not, which is the case
 * that leaves somebody dragging a dead slider wondering what is broken — so that badge is a
 * button, and pressing it goes and finds which other parameter is holding this one down.
 *
 * The search is `findClamp`, which verifies its answer rather than inferring it, and can take
 * up to a second. It runs behind a `setTimeout` so the "looking…" state is painted first.
 */
function makeStuckBadge(spec, getState) {
  const badge = document.createElement('button');
  badge.className = 'ctrl-stuck';
  badge.hidden = true;
  let searched = null; // the parameter set the last search was run against

  badge.addEventListener('click', (ev) => {
    ev.preventDefault();
    ev.stopPropagation();
    const state = getState?.();
    if (!state?.params || searched === state.params) return;
    searched = state.params;
    badge.textContent = 'looking…';
    setTimeout(() => {
      let found = null;
      try {
        found = findClamp(state.params, spec.name, { locks: state.locks || {}, overrides: state.overrides || {} });
      } catch { /* a diagnosis must never break the panel */ }
      if (!found) {
        badge.textContent = 'clamped';
        badge.title = 'Moving this changes no colour, and no single other parameter on its own'
          + ' brings it back — read the hint above for what it depends on';
        return;
      }
      const names = found.set.map((s) => s.label).join(' and ');
      badge.textContent = `clamped by ${names}`;
      badge.title = `This does nothing until ${found.set.map((s) => `${s.name} moves (${s.value} works)`).join(' and ')}`
        + ' — checked by moving each one and watching whether this control came back to life';
    }, 0);
  });

  return {
    badge,
    set(effect) {
      if (!effect || effect.moves) {
        badge.hidden = true;
        searched = null;
        return;
      }
      badge.hidden = false;
      const limit = effect.atMin || effect.atMax;
      badge.textContent = limit ? 'at its limit' : 'clamped';
      badge.title = limit
        ? 'This is already at the end of its own range'
        : 'Moving this changed no colour at all — click to find out what is holding it down';
      badge.disabled = Boolean(limit);
    },
  };
}

/** Build the DOM for one parameter control and register its sync/mark hooks. */
function buildControl(spec, controls, onChange, defaults, getState) {
  const wrap = document.createElement('div');
  wrap.className = 'ctrl';
  const stuck = makeStuckBadge(spec, getState);

  if (spec.type === 'bool') {
    const label = document.createElement('label');
    label.className = 'ctrl-bool';
    const box = document.createElement('input');
    box.type = 'checkbox';
    label.append(box, makeName(spec, onChange, defaults), stuck.badge);
    wrap.appendChild(label);
    if (spec.hint) wrap.appendChild(makeHint(spec));
    box.addEventListener('change', () => onChange(spec.name, box.checked));
    controls.set(spec.name, {
      sync: (v) => { box.checked = Boolean(v); },
      markChanged: (c) => wrap.classList.toggle('changed', c),
      markStuck: (e) => { stuck.set(e); wrap.classList.toggle('is-stuck', Boolean(e) && !e.moves); },
    });
    return wrap;
  }

  const head = document.createElement('div');
  head.className = 'ctrl-head';
  head.append(makeName(spec, onChange, defaults), stuck.badge);

  if (spec.type === 'enum') {
    wrap.appendChild(head);
    const sel = document.createElement('select');
    sel.className = 'enum-select';
    for (const opt of spec.options) {
      const o = document.createElement('option');
      o.value = opt;
      o.textContent = optionLabel(spec, opt);
      sel.appendChild(o);
    }
    wrap.appendChild(sel);
    // The chosen option's own explanation, rather than a generic hint: for an enum, "what
    // does this setting do" is answered per option, not per parameter.
    const hint = makeHint(spec);
    wrap.appendChild(hint);
    const syncHint = (v) => {
      const optText = optionLabel(spec, v);
      const dash = optText.indexOf('—');
      hint.textContent = dash >= 0 ? optText.slice(dash + 1).trim() : spec.hint;
    };
    sel.addEventListener('change', () => { syncHint(sel.value); onChange(spec.name, sel.value); });
    controls.set(spec.name, {
      sync: (v) => { sel.value = v; syncHint(v); },
      markChanged: (c) => wrap.classList.toggle('changed', c),
      markStuck: (e) => { stuck.set(e); wrap.classList.toggle('is-stuck', Boolean(e) && !e.moves); },
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
  if (spec.hint) wrap.appendChild(makeHint(spec));

  const range = document.createElement('input');
  range.type = 'range';
  range.min = spec.min; range.max = spec.max; range.step = spec.step;
  wrap.appendChild(range);

  // What the two ends mean, which is what stops the doc string being mandatory reading.
  if (spec.lowLabel || spec.highLabel) {
    const ends = document.createElement('div');
    ends.className = 'ctrl-ends';
    const lo = document.createElement('span');
    lo.textContent = spec.lowLabel || '';
    const hi = document.createElement('span');
    hi.textContent = spec.highLabel || '';
    ends.append(lo, hi);
    wrap.appendChild(ends);
  }

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
    markStuck: (e) => { stuck.set(e); wrap.classList.toggle('is-stuck', Boolean(e) && !e.moves); },
  });
  return wrap;
}
