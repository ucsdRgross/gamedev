// The hue wheel (UX_PLAN U6.3 — IMPROVEMENTS item 9).
//
// `hue_scheme: custom` used to be a lie: it spread hues evenly across `hue_span` exactly like
// the other schemes, and there was no way to say which hues you actually wanted. Now there is
// (`custom_hue_count` + `custom_hue_1..6` in the schema), and this is the way to say it that
// is not seven sliders reading "Pinned hue 3: 214".
//
// A hue is a position on a circle. Every representation other than a circle — a number, a
// slider, a text field — asks you to convert, and the conversion is the whole difficulty:
// nobody knows what 214° looks like, and everybody knows what *that blue over there* looks
// like. So: click the ring to pin, drag to move, click a pin to unpin.
//
// The ring is drawn from the palette's own gamut maths (OKLCH at a fixed lightness and
// chroma, gamut-mapped), not from an HSL rainbow, so the angle you click is the angle the
// generator will use. An HSL wheel would be off by up to thirty degrees in the greens.

import { oklchToSrgb, srgbToRgb8, rgb8ToHex, normHue, hueDelta } from '../core/oklch.js';
import { CUSTOM_HUE_PARAMS, customHues } from '../core/params.js';
import { hueName } from '../core/describe.js';

const SIZE = 220;
const R_OUT = 100;
const R_IN = 70;
// The slice of OKLCH the ring is drawn at. Mid lightness and a chroma most hues can reach, so
// the ring reads as a hue circle rather than as a chart of which hues clip.
const RING_L = 0.62;
const RING_C = 0.14;

/** Screen position of an angle on the ring. */
function pointAt(angle, radius) {
  const rad = ((angle - 90) * Math.PI) / 180;
  return [SIZE / 2 + Math.cos(rad) * radius, SIZE / 2 + Math.sin(rad) * radius];
}

/** The angle a click at (x, y) lands on, and how far out it was. */
function angleAt(x, y) {
  const dx = x - SIZE / 2;
  const dy = y - SIZE / 2;
  return {
    angle: normHue((Math.atan2(dy, dx) * 180) / Math.PI + 90),
    radius: Math.hypot(dx, dy),
  };
}

/**
 * Wire the hue-wheel popover.
 *
 * `getState()` supplies the live `{ params }`, `getPalette()` the current palette (its hues
 * are drawn as ticks, so you can see where the generator actually put them), and
 * `setParams(patch, source)` applies a change.
 */
export function createHueWheel({ button, getState, getPalette, setParams }) {
  if (!button) return { close() {} };

  const pop = document.createElement('div');
  pop.className = 'wheel-pop';
  pop.hidden = true;
  const canvas = document.createElement('canvas');
  canvas.className = 'wheel-canvas';
  canvas.width = SIZE;
  canvas.height = SIZE;
  const note = document.createElement('div');
  note.className = 'wheel-note';
  const actions = document.createElement('div');
  actions.className = 'wheel-actions';
  const seed = document.createElement('button');
  seed.className = 'btn btn-small';
  seed.textContent = 'Take the palette\'s hues';
  seed.title = 'Pin the hues this palette actually has, so you can move them one at a time';
  const clear = document.createElement('button');
  clear.className = 'btn btn-small';
  clear.textContent = 'Clear pins';
  clear.title = 'Back to the even spread — the custom scheme as it behaves with nothing pinned';
  actions.append(seed, clear);
  pop.append(canvas, note, actions);
  document.body.appendChild(pop);

  let dragging = -1; // index of the pin under the pointer, or -1
  // Where that pin was when the press started. A drag commits on every pointermove, so by the
  // time the release arrives the pin is already at the pointer — comparing the two would call
  // every drag a click and delete the pin instead of moving it.
  let dragFrom = 0;

  const close = () => { pop.hidden = true; };

  /** Write a new pin set back into the parameters, switching the scheme to custom. */
  function commit(pins, source) {
    const patch = { hue_scheme: 'custom', custom_hue_count: pins.length };
    CUSTOM_HUE_PARAMS.forEach((name, i) => {
      // Unused slots keep their current value rather than being zeroed: raising the count
      // again should bring back the pin you had, not a stack of reds at 0°.
      if (i < pins.length) patch[name] = normHue(pins[i]);
    });
    setParams(patch, source);
    draw();
  }

  /** Paint the ring, the palette's real hues, and the pins. */
  function draw() {
    const ctx = canvas.getContext('2d');
    const params = getState()?.params || {};
    const pins = customHues(params);
    ctx.clearRect(0, 0, SIZE, SIZE);

    // The ring, one degree at a time, in the generator's own colour space.
    for (let a = 0; a < 360; a++) {
      const [r, g, bl] = srgbToRgb8(oklchToSrgb(RING_L, RING_C, a));
      ctx.fillStyle = `rgb(${r},${g},${bl})`;
      ctx.beginPath();
      ctx.arc(SIZE / 2, SIZE / 2, R_OUT, ((a - 90.6) * Math.PI) / 180, ((a - 89.4) * Math.PI) / 180);
      ctx.arc(SIZE / 2, SIZE / 2, R_IN, ((a - 89.4) * Math.PI) / 180, ((a - 90.6) * Math.PI) / 180, true);
      ctx.closePath();
      ctx.fill();
    }

    // Where the palette's hues actually ended up — the answer to "did my pin survive?".
    const palette = getPalette?.();
    for (const h of palette?.hues || []) {
      const [x1, y1] = pointAt(h, R_IN - 4);
      const [x2, y2] = pointAt(h, R_IN - 14);
      ctx.strokeStyle = 'rgba(230,236,245,0.55)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.stroke();
    }

    // The pins themselves, as handles straddling the ring.
    pins.forEach((h, i) => {
      const [x, y] = pointAt(h, (R_OUT + R_IN) / 2);
      ctx.fillStyle = rgb8ToHex(srgbToRgb8(oklchToSrgb(RING_L, RING_C, h)));
      ctx.strokeStyle = '#0b0e14';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(x, y, 10, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = '#0b0e14';
      ctx.font = 'bold 11px system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(String(i + 1), x, y);
    });

    const custom = params.hue_scheme === 'custom';
    note.textContent = pins.length
      ? `${pins.length} pinned: ${pins.map((h) => `${Math.round(h)}° ${hueName(h)}`).join(', ')}`
        + (custom ? '' : ' — but the scheme is not “Chosen by hand”, so they are not in use')
      : 'Click the ring to pin a hue. Click a pin to remove it, drag it to move it. '
        + 'The pale ticks are where this palette\'s hues actually are.';
    note.classList.toggle('is-warning', pins.length > 0 && !custom);
  }

  /** Which pin is under a point, or -1. */
  function pinAt(x, y) {
    const pins = customHues(getState()?.params || {});
    for (let i = 0; i < pins.length; i++) {
      const [px, py] = pointAt(pins[i], (R_OUT + R_IN) / 2);
      if (Math.hypot(x - px, y - py) <= 12) return i;
    }
    return -1;
  }

  /** Canvas coordinates for a pointer event, in the canvas's own pixel space. */
  function localPoint(ev) {
    const r = canvas.getBoundingClientRect();
    return [(ev.clientX - r.left) * (SIZE / r.width), (ev.clientY - r.top) * (SIZE / r.height)];
  }

  canvas.addEventListener('pointerdown', (ev) => {
    const [x, y] = localPoint(ev);
    const hit = pinAt(x, y);
    if (hit >= 0) {
      dragging = hit;
      dragFrom = customHues(getState()?.params || {})[hit];
      try { canvas.setPointerCapture(ev.pointerId); } catch { /* synthetic events have no capture */ }
      return;
    }
    const { angle, radius } = angleAt(x, y);
    if (radius < R_IN - 18 || radius > R_OUT + 18) return;
    const pins = customHues(getState()?.params || {});
    if (pins.length >= CUSTOM_HUE_PARAMS.length) {
      note.textContent = `Six pins is the most the seed can carry — move one instead.`;
      return;
    }
    commit([...pins, angle], `Pinned a ${hueName(angle)} hue`);
  });

  canvas.addEventListener('pointermove', (ev) => {
    if (dragging < 0) return;
    const [x, y] = localPoint(ev);
    const pins = customHues(getState()?.params || {});
    pins[dragging] = angleAt(x, y).angle;
    // Dragging coalesces into one history entry, like a slider drag does.
    commit(pins, null);
  });

  const endDrag = () => { dragging = -1; };
  canvas.addEventListener('pointerup', (ev) => {
    if (dragging < 0) return;
    const [x, y] = localPoint(ev);
    const released = angleAt(x, y).angle;
    const pins = customHues(getState()?.params || {});
    const index = dragging;
    endDrag();
    // A press and release at the same angle is a click, and a click on a pin removes it.
    // Measured against where the pin was when the press began, not where it is now.
    if (Math.abs(hueDelta(released, dragFrom)) < 2) {
      const kept = pins.filter((_, i) => i !== index);
      commit(kept, kept.length ? `Removed the ${hueName(dragFrom)} pin` : 'Cleared the hue pins');
      return;
    }
    commit(pins, `Moved a pin to ${Math.round(released)}° ${hueName(released)}`);
  });
  canvas.addEventListener('pointercancel', endDrag);

  seed.addEventListener('click', () => {
    const hues = (getPalette?.()?.hues || []).slice(0, CUSTOM_HUE_PARAMS.length);
    if (!hues.length) return;
    commit(hues, `Pinned this palette's ${hues.length} hues`);
  });
  clear.addEventListener('click', () => {
    setParams({ custom_hue_count: 0 }, 'Cleared the hue pins');
    draw();
  });

  button.addEventListener('click', (ev) => {
    ev.stopPropagation();
    if (!pop.hidden) { close(); return; }
    pop.hidden = false;
    draw();
    const r = button.getBoundingClientRect();
    const w = pop.offsetWidth;
    pop.style.left = `${Math.max(12, Math.min(r.right - w, window.innerWidth - w - 12))}px`;
    pop.style.top = `${Math.min(r.bottom + 6, window.innerHeight - pop.offsetHeight - 12)}px`;
  });
  document.addEventListener('click', (ev) => {
    if (!pop.hidden && !pop.contains(ev.target)) close();
  });
  window.addEventListener('keydown', (ev) => { if (ev.key === 'Escape') close(); });

  return {
    close,
    /** Repaint if open — the ticks follow the palette. */
    refresh() { if (!pop.hidden) draw(); },
  };
}
