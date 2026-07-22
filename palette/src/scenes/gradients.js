// Dithering and gradient scenes 27–31 (PLAN §8): the dither pair matrix, Bayer ramp
// dithering, an ordered-dithered sky gradient, 1px noise, and a zoom comparison.

import { rgb, ramps, shade, rampOfRole, role, anchorDark, anchorLight, allEntries } from './util.js';
import { orderedDither } from '../core/dither.js';
import { Raster } from '../core/raster.js';

const CAT = 'Dither';

const paletteRgb = (palette) => palette.entries.map((e) => e.rgb8);

function mix(a, b, t) {
  return [Math.round(a[0] + (b[0] - a[0]) * t), Math.round(a[1] + (b[1] - a[1]) * t), Math.round(a[2] + (b[2] - a[2]) * t)];
}

/** Checkerboard two colours into a rectangle. */
function checker(surface, x, y, w, h, c1, c2) {
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) surface.set(x + i, y + j, (i + j) % 2 ? c2 : c1);
}

// --- 27. Dither pair matrix ------------------------------------------------
function renderDitherPairs(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, anchorDark(palette).rgb8);
  const fg = ramps(palette, 'fg');
  const rowH = Math.max(6, Math.floor((surface.h - 2) / Math.max(1, fg.length)));
  fg.forEach((ramp, r) => {
    const y = 1 + r * rowH;
    let x = 1;
    for (let s = 0; s < ramp.length - 1; s++) {
      const a = rgb(ramp[s]);
      const b = rgb(ramp[s + 1]);
      surface.rect(x, y, 5, rowH - 1, a);
      checker(surface, x + 5, y, 6, rowH - 1, a, b); // dithered intermediate
      surface.rect(x + 11, y, 5, rowH - 1, b);
      x += 18;
      if (x > surface.w - 16) break;
    }
  });
}

// --- 28. Bayer gradient ramps ----------------------------------------------
function renderBayerRamps(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, anchorDark(palette).rgb8);
  const ramp = rampOfRole(palette, 'stone');
  const dark = rgb(ramp[0]);
  const light = rgb(ramp[ramp.length - 1]);
  // A smooth full-colour gradient source, dithered two ways plus a plain band.
  const w = surface.w - 2;
  const bandH = Math.floor((surface.h - 4) / 3);
  const src = new Raster(w, bandH, null);
  for (let y = 0; y < bandH; y++) for (let x = 0; x < w; x++) src.set(x, y, mix(dark, light, x / (w - 1)));
  const pr = paletteRgb(palette);
  const b4 = orderedDither(src, pr, { size: 4, strength: 40 });
  const b8 = orderedDither(src, pr, { size: 8, strength: 40 });
  surface.blit(b4, 1, 1);
  surface.blit(b8, 1, 2 + bandH);
  // plain nearest (banded) for contrast
  const plain = orderedDither(src, pr, { size: 4, strength: 0 });
  surface.blit(plain, 1, 3 + bandH * 2);
  surface.text('4', surface.w - 6, 1, 1, anchorLight(palette).rgb8);
  surface.text('8', surface.w - 6, 2 + bandH, 1, anchorLight(palette).rgb8);
}

// --- 29. Sky gradient with ordered dithering -------------------------------
function renderSkyGradient(surface, palette) {
  const sky = role(palette, 'sky').rgb8;
  const top = mix(sky, [255, 255, 255], 0.35);
  const horizon = mix(sky, rgb(role(palette, 'fire')), 0.4);
  const src = new Raster(surface.w, surface.h, null);
  for (let y = 0; y < surface.h; y++) {
    const c = mix(top, horizon, y / (surface.h - 1));
    for (let x = 0; x < surface.w; x++) src.set(x, y, c);
  }
  const pr = paletteRgb(palette);
  const half = Math.floor(surface.w / 2);
  const dithered = orderedDither(src, pr, { size: 8, strength: 36 });
  const banded = orderedDither(src, pr, { size: 4, strength: 0 });
  surface.blit(banded, 0, 0);
  // overlay the dithered half on the left
  for (let y = 0; y < surface.h; y++) for (let x = 0; x < half; x++) surface.set(x, y, dithered.get(x, y));
  surface.rect(half, 0, 1, surface.h, anchorDark(palette).rgb8);
  surface.text('DITHER', 2, 2, 1, anchorDark(palette).rgb8);
  surface.text('BAND', half + 2, 2, 1, anchorDark(palette).rgb8);
}

// --- 30. 1px noise / checkerboard ------------------------------------------
function renderNoise(surface, palette) {
  const es = allEntries(palette);
  const cols = 4;
  const cw = Math.floor(surface.w / cols);
  const ch = Math.floor(surface.h / 2);
  // Pairs of adjacent palette colours checkerboarded at 1px — the max-frequency test.
  for (let k = 0; k < cols * 2; k++) {
    const a = es[k % es.length].rgb8;
    const b = es[(k + 1) % es.length].rgb8;
    const x = (k % cols) * cw;
    const y = Math.floor(k / cols) * ch;
    checker(surface, x, y, cw, ch, a, b);
  }
}

// --- 31. Zoom comparison ---------------------------------------------------
function renderZoom(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, anchorDark(palette).rgb8);
  // A small motif: a shaded gem on background.
  const m = new Raster(16, 16, rgb(role(palette, 'sky')));
  const gem = rampOfRole(palette, 'water');
  m.disc(8, 8, 6, rgb(shade(gem, 0.45)));
  m.disc(6, 6, 3, rgb(shade(gem, 0.75)));
  m.disc(9, 10, 2, rgb(shade(gem, 0.25)));
  m.set(5, 5, anchorLight(palette).rgb8);
  let x = 2;
  for (const factor of [1, 2, 4]) {
    const scaled = m.scaled(factor);
    surface.blit(scaled, x, Math.floor((surface.h - scaled.h) / 2));
    surface.text(`${factor}X`, x, surface.h - 7, 1, anchorLight(palette).rgb8);
    x += scaled.w + 4;
  }
}

export const gradientScenes = [
  { id: 'dither-pairs', title: 'Dither pair matrix', category: CAT, width: 128, height: 96, render: renderDitherPairs },
  { id: 'bayer-ramps', title: 'Bayer gradient ramps', category: CAT, width: 128, height: 64, render: renderBayerRamps },
  { id: 'sky-gradient', title: 'Sky gradient (ordered dither)', category: CAT, width: 128, height: 96, render: renderSkyGradient },
  { id: 'noise', title: '1px noise / checkerboard', category: CAT, width: 128, height: 64, render: renderNoise },
  { id: 'zoom', title: 'Zoom comparison 1× 2× 4×', category: CAT, width: 128, height: 80, render: renderZoom },
];
