// Motion scene 32 (PLAN §8): palette-cycled water, torch flicker and a day-night sweep.
// Animated scenes take an `opts.frame`; `frames` says how many the loop has. Catching
// ramps that band or strobe only in motion is the whole point.

import { rgb, shade, rampOfRole, role, bgByDepth, anchorDark } from './util.js';

const CAT = 'Motion';
const FRAMES = 16;

function mix(a, b, t) {
  return [Math.round(a[0] + (b[0] - a[0]) * t), Math.round(a[1] + (b[1] - a[1]) * t), Math.round(a[2] + (b[2] - a[2]) * t)];
}

function renderAnimated(surface, palette, { frame = 0 } = {}) {
  const bandH = Math.floor(surface.h / 3);

  // 1. Palette-cycled water: shift the ramp index down each frame.
  const water = rampOfRole(palette, 'water');
  for (let y = 0; y < bandH; y++) {
    const idx = ((y + frame) % (water.length * 2));
    const t = idx < water.length ? idx / (water.length - 1) : (2 * water.length - 1 - idx) / (water.length - 1);
    surface.rect(0, y, surface.w, 1, rgb(shade(water, 0.2 + t * 0.6)));
  }

  // 2. Torch flicker: radius and brightness wobble deterministically per frame.
  const y0 = bandH;
  surface.rect(0, y0, surface.w, bandH, mix(rgb(anchorDark(palette)), rgb(role(palette, 'water')), 0.3));
  const flick = 0.8 + 0.2 * Math.sin(frame * 1.7) + 0.1 * Math.sin(frame * 3.3);
  const fire = rgb(role(palette, 'fire'));
  const tx = Math.floor(surface.w / 2);
  const ty = y0 + Math.floor(bandH / 2);
  const rad = surface.w * 0.4 * flick;
  for (let y = 0; y < bandH; y++) {
    for (let x = 0; x < surface.w; x++) {
      const d = Math.hypot(x - tx, ty - (y0 + y)) / rad;
      if (d < 1) surface.set(x, y0 + y, mix(surface.get(x, y0 + y), fire, (1 - d) * 0.55 * flick));
    }
  }
  surface.disc(tx, ty, 2, fire);
  surface.set(tx, ty - 1, rgb(role(palette, 'gold')));

  // 3. Day-night sweep: sky lightness cycles smoothly through the frame loop.
  const y1 = bandH * 2;
  const phase = (Math.sin((frame / FRAMES) * Math.PI * 2) + 1) / 2; // 0..1..0
  for (let y = 0; y < surface.h - y1; y++) {
    surface.rect(0, y1 + y, surface.w, 1, rgb(bgByDepth(palette, 0.15 + phase * 0.8)));
  }
  const gy = y1 + Math.floor((surface.h - y1) * 0.6);
  surface.rect(0, gy, surface.w, surface.h - gy, rgb(shade(rampOfRole(palette, 'foliage'), 0.3)));
  const sun = phase > 0.5 ? rgb(role(palette, 'gold')) : rgb(role(palette, 'sky'));
  surface.disc(Math.floor(surface.w * (0.1 + phase * 0.8)), y1 + 6, 3, sun);
}

export const motionScenes = [
  {
    id: 'animated', title: 'Animated (water / torch / day-night)', category: CAT,
    width: 128, height: 96, animated: true, frames: FRAMES, render: renderAnimated,
  },
];
