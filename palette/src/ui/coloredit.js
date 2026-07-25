// Editing one colour directly (UX_PLAN U7.6 — item 8).
//
// Overrides used to accept a typed hex and nothing else, which is the wrong tool for the job
// people actually have. "This green wants to be a shade lighter" is a move along one axis, and
// six hex digits are a poor way to express it; "I want *that* green, out of this reference
// image" is a pointing gesture, and typing is a poor way to express that too.
//
// So: an OKLCH editor with the sRGB edge drawn live (the answer to "why will this not get more
// saturated" is that the edge is where it is, and it is different at every lightness and hue),
// arrow-key nudging on the swatch itself, and an eyedropper.
//
// Everything here commits through the same `setOverride(id, hex)` the hex field always used, so
// an edited colour is an override like any other: it is in the seed, it survives a regenerate,
// and clearing it puts the generated colour back.

import { oklchToSrgb, srgbToRgb8, rgb8ToHex, rgb8ToOklch, hexToRgb8, clamp } from '../core/oklch.js';
import { maxChromaFor } from '../core/gamut.js';
import { colorLabel } from '../core/colornames.js';
import { option } from './dom.js';

/** How far one arrow key moves each axis. Shift multiplies by five. */
const NUDGE = { L: 0.01, C: 0.005, h: 2 };

/** The hex for an OKLCH triple, gamut-mapped the way the generator would. */
function hexOf({ L, C, h }) {
  return rgb8ToHex(srgbToRgb8(oklchToSrgb(clamp(L, 0, 1), Math.max(0, C), h)));
}

/**
 * Build the colour editor and return a controller.
 *
 * `refs` is the recolour gallery (for the eyedropper's fallback list of loaded images); it may
 * be absent, in which case the eyedropper falls back to the browser's own picker or reports
 * that there is nothing to sample from.
 */
export function createColorEditor({ setOverride, clearOverride, refs }) {
  const panel = document.createElement('div');
  panel.className = 'color-editor';
  panel.hidden = true;
  document.body.appendChild(panel);

  const head = document.createElement('div');
  head.className = 'ce-head';
  const chip = document.createElement('span');
  chip.className = 'ce-chip';
  const title = document.createElement('span');
  title.className = 'ce-title';
  head.append(chip, title);

  const hex = document.createElement('input');
  hex.className = 'ce-hex';
  hex.spellcheck = false;

  const axes = {};
  const axisRows = document.createElement('div');
  axisRows.className = 'ce-axes';
  for (const [key, label, min, max, step] of [
    ['L', 'Lightness', 0, 1, 0.002],
    ['C', 'Chroma', 0, 0.4, 0.002],
    ['h', 'Hue', 0, 360, 1],
  ]) {
    const row = document.createElement('div');
    row.className = 'ce-axis';
    const name = document.createElement('span');
    name.className = 'ce-axis-name';
    name.textContent = label;
    const value = document.createElement('span');
    value.className = 'ce-axis-value';
    const range = document.createElement('input');
    range.type = 'range';
    range.min = min; range.max = max; range.step = step;
    range.addEventListener('input', () => {
      current[key] = Number(range.value);
      commit(true);
    });
    range.addEventListener('change', () => commit(false));
    row.append(name, value, range);
    axisRows.appendChild(row);
    axes[key] = { range, value };
  }

  // The live gamut edge: the most chroma sRGB can hold at the lightness and hue on the sliders
  // right now. It moves as the other two axes move, which is exactly why a fixed ceiling on the
  // chroma slider would be a lie.
  const edge = document.createElement('div');
  edge.className = 'ce-edge';

  const actions = document.createElement('div');
  actions.className = 'ce-actions';
  const drop = button('Eyedrop', 'Sample a colour from a reference image or anywhere on screen');
  const reset = button('Clear', 'Remove the override and put the generated colour back');
  const close = button('Done', 'Close the editor');
  actions.append(drop, reset, close);

  const note = document.createElement('div');
  note.className = 'ce-note';

  panel.append(head, hex, axisRows, edge, actions, note);

  let entry = null;
  let current = { L: 0.5, C: 0, h: 0 };

  /** Push the current OKLCH to the palette as an override on the open swatch. */
  function commit(coalesce) {
    if (!entry) return;
    setOverride(entry.id, hexOf(current), coalesce);
    sync();
  }

  /** Redraw the panel from `current` without touching the palette. */
  function sync() {
    const value = hexOf(current);
    chip.style.background = value;
    hex.value = value;
    title.textContent = `${entry ? entry.role : ''} · ${colorLabel(value).label}`;
    for (const [key, fmt] of [['L', 3], ['C', 3], ['h', 0]]) {
      if (document.activeElement !== axes[key].range) axes[key].range.value = current[key];
      axes[key].value.textContent = current[key].toFixed(fmt);
    }
    const most = maxChromaFor(clamp(current.L, 0, 1), current.h);
    const over = current.C > most + 1e-4;
    edge.textContent = `sRGB holds at most C ${most.toFixed(3)} at this lightness and hue`
      + (over ? ` — asking for ${current.C.toFixed(3)}, so it is being brought back in` : '');
    edge.classList.toggle('is-over', over);
  }

  /** Open the editor on one entry, anchored beside its card. */
  function open(paletteEntry, anchor) {
    entry = paletteEntry;
    current = { ...paletteEntry.actual };
    panel.hidden = false;
    note.textContent = paletteEntry.overridden
      ? 'This colour is pinned. Clear to let the generator decide it again.'
      : 'Editing pins this colour: the generator builds the rest around it.';
    sync();
    place(anchor);
  }

  /** Position the panel beside an anchor, clamped to the viewport. */
  function place(anchor) {
    const r = anchor.getBoundingClientRect();
    const w = Math.min(260, window.innerWidth - 24);
    panel.style.width = `${w}px`;
    let left = r.left - w - 10;
    if (left < 12) left = Math.min(window.innerWidth - w - 12, r.right + 10);
    panel.style.left = `${left}px`;
    panel.style.top = `${Math.max(12, Math.min(r.top, window.innerHeight - panel.offsetHeight - 12))}px`;
  }

  hex.addEventListener('change', () => {
    const parsed = /^#?[0-9a-fA-F]{6}$/.test(hex.value.trim())
      ? `#${hex.value.trim().replace('#', '').toUpperCase()}` : null;
    if (!parsed) { sync(); return; }
    current = rgb8ToOklch(hexToRgb8(parsed));
    commit(false);
  });

  close.addEventListener('click', () => { panel.hidden = true; entry = null; });
  reset.addEventListener('click', () => {
    if (entry) clearOverride(entry.id);
    panel.hidden = true;
    entry = null;
  });
  drop.addEventListener('click', async () => {
    const picked = await pickColor(refs, (text) => { note.textContent = text; });
    if (!picked) return;
    current = rgb8ToOklch(hexToRgb8(picked));
    commit(false);
  });

  // Arrow keys inside the panel move the axes, so the whole edit can be done from the keyboard
  // once it is open — the same nudges the swatch card offers when it merely has focus.
  panel.addEventListener('keydown', (ev) => {
    const step = nudgeFor(ev);
    if (!step) return;
    ev.preventDefault();
    current[step.axis] = axisClamp(step.axis, current[step.axis] + step.delta);
    commit(false);
  });

  return {
    open,
    /** Re-point the open editor at the regenerated version of the same slot. */
    refresh(palette) {
      if (!entry || panel.hidden) return;
      const fresh = palette.entries.find((e) => e.id === entry.id);
      if (fresh) entry = fresh;
    },
    /** Nudge one entry's colour along an axis from a key event; returns true if it handled it. */
    nudge(paletteEntry, ev) {
      const step = nudgeFor(ev);
      if (!step) return false;
      const from = { ...paletteEntry.actual };
      from[step.axis] = axisClamp(step.axis, from[step.axis] + step.delta);
      // A held arrow key coalesces into one history entry, exactly as a slider drag does:
      // twenty undos to get back across one nudge would make the feature unusable.
      setOverride(paletteEntry.id, hexOf(from), ev.repeat);
      return true;
    },
    close() { panel.hidden = true; entry = null; },
  };
}

/** Keep an axis inside what it means: hue wraps, lightness and chroma clamp. */
function axisClamp(axis, value) {
  if (axis === 'h') return ((value % 360) + 360) % 360;
  if (axis === 'L') return clamp(value, 0, 1);
  return clamp(value, 0, 0.4);
}

/**
 * Which axis an arrow key moves: up/down is lightness, left/right is hue, and holding Alt
 * turns the vertical pair into chroma. Shift makes any of them five times bigger.
 */
function nudgeFor(ev) {
  const big = ev.shiftKey ? 5 : 1;
  if (ev.key === 'ArrowUp') return { axis: ev.altKey ? 'C' : 'L', delta: NUDGE[ev.altKey ? 'C' : 'L'] * big };
  if (ev.key === 'ArrowDown') return { axis: ev.altKey ? 'C' : 'L', delta: -NUDGE[ev.altKey ? 'C' : 'L'] * big };
  if (ev.key === 'ArrowRight') return { axis: 'h', delta: NUDGE.h * big };
  if (ev.key === 'ArrowLeft') return { axis: 'h', delta: -NUDGE.h * big };
  return null;
}

/** A small labelled button. */
function button(text, title) {
  const el = document.createElement('button');
  el.className = 'btn btn-small';
  el.textContent = text;
  el.title = title;
  return el;
}

/**
 * Pick a colour from the screen, or from a loaded reference image.
 *
 * The browser's own `EyeDropper` samples anything on screen — the reference gallery, the
 * picker canvas, another window — so it is the better answer wherever it exists. Where it does
 * not (Firefox, Safari), the fallback samples the same reference library the recolour gallery
 * decoded, which is the case item 8 actually asks for. Returns a `#RRGGBB` or null.
 */
async function pickColor(refs, say) {
  if (typeof window !== 'undefined' && window.EyeDropper) {
    try {
      const result = await new window.EyeDropper().open();
      return result.sRGBHex.toUpperCase();
    } catch {
      return null; // the user pressed Escape
    }
  }
  const sources = refs?.listSources?.() ?? [];
  if (!sources.length) {
    say('no reference images are loaded, and this browser has no eyedropper of its own');
    return null;
  }
  say('pick a colour from a reference image');
  return sampleFromReference(refs, sources);
}

/**
 * The fallback eyedropper: the loaded reference images, drawn at a size that fits, click to
 * sample. Resolves to a hex, or null if the overlay is dismissed.
 */
function sampleFromReference(refs, sources) {
  return new Promise((resolve) => {
    const overlay = document.createElement('div');
    overlay.className = 'ce-overlay';
    const bar = document.createElement('div');
    bar.className = 'ce-overlay-bar';
    const select = document.createElement('select');
    for (const s of sources) select.appendChild(option(s.id, s.title));
    const cancel = button('Cancel', 'Close without sampling');
    const hint = document.createElement('span');
    hint.className = 'meta';
    hint.textContent = 'click anywhere in the image to take that colour';
    bar.append(select, hint, cancel);

    const canvas = document.createElement('canvas');
    canvas.className = 'ce-overlay-canvas';
    overlay.append(bar, canvas);
    document.body.appendChild(overlay);

    const done = (value) => {
      overlay.remove();
      resolve(value);
    };

    /** Draw the first frame of one source at its natural size. */
    async function show(id) {
      let frames = [];
      try {
        frames = await refs.framesFor(id);
      } catch {
        hint.textContent = 'that image would not decode';
        return;
      }
      const image = frames[0]?.image;
      if (!image) return;
      canvas.width = image.w;
      canvas.height = image.h;
      canvas.getContext('2d').putImageData(image.toImageData(ImageData), 0, 0);
    }

    canvas.addEventListener('click', (ev) => {
      const r = canvas.getBoundingClientRect();
      const x = Math.floor(((ev.clientX - r.left) / r.width) * canvas.width);
      const y = Math.floor(((ev.clientY - r.top) / r.height) * canvas.height);
      const px = canvas.getContext('2d').getImageData(x, y, 1, 1).data;
      done(rgb8ToHex([px[0], px[1], px[2]]));
    });
    select.addEventListener('change', () => show(select.value));
    cancel.addEventListener('click', () => done(null));
    overlay.addEventListener('click', (ev) => { if (ev.target === overlay) done(null); });
    show(sources[0].id);
  });
}
