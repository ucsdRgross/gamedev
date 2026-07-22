// Palette analysis (PLAN §8): dichromat simulation, the grayscale value view, and ramp
// evenness metrics. All pure and DOM-free, so scenes and tests share them.

import {
  srgbToLinear, linearToSrgb, rgb8ToOklch, oklchToSrgb, srgbToRgb8, rgb8ToOklab,
  deltaEOK, clamp,
} from './oklch.js';
import { Raster } from './raster.js';

// Viénot, Brettel & Mollon (1999) dichromat matrices, operating on LINEAR sRGB.
// The protan/deutan matrices share their first two rows: a dichromat collapses the
// long/medium cone response onto one axis, which is exactly the confusion these model.
// (Values from the libDaltonLens reference implementation of Viénot 1999.)
const DICHROMAT = {
  protan: [
    [0.11238, 0.88762, 0.0],
    [0.11238, 0.88762, 0.0],
    [0.00401, -0.00401, 1.0],
  ],
  deutan: [
    [0.29275, 0.70725, 0.0],
    [0.29275, 0.70725, 0.0],
    [-0.02234, 0.02234, 1.0],
  ],
  tritan: [
    [1.0, 0.14461, -0.14461],
    [0.0, 0.85924, 0.14076],
    [0.0, 0.25164, 0.74836],
  ],
};

/** The colour-vision views the gallery offers, in display order. */
export const VIEWS = ['color', 'value', 'protan', 'deutan', 'tritan'];

/** Simulate how a dichromat (`protan`/`deutan`/`tritan`) sees an `[r,g,b]` colour. */
export function simulateColorblind(rgb8, type) {
  const m = DICHROMAT[type];
  if (!m) return [rgb8[0], rgb8[1], rgb8[2]];
  const lin = [srgbToLinear(rgb8[0] / 255), srgbToLinear(rgb8[1] / 255), srgbToLinear(rgb8[2] / 255)];
  const out = [];
  for (let row = 0; row < 3; row++) {
    const v = m[row][0] * lin[0] + m[row][1] * lin[1] + m[row][2] * lin[2];
    out.push(Math.round(linearToSrgb(clamp(v, 0, 1)) * 255));
  }
  return out;
}

/** The neutral gray of the same OKLCH lightness — the value-only appearance of a colour. */
export function toValue(rgb8) {
  const { L } = rgb8ToOklch(rgb8);
  return srgbToRgb8(oklchToSrgb(L, 0, 0));
}

/** Transform one `[r,g,b]` for a given view name; `color` is the identity. */
export function viewColor(rgb8, view) {
  if (view === 'value') return toValue(rgb8);
  if (view === 'protan' || view === 'deutan' || view === 'tritan') return simulateColorblind(rgb8, view);
  return rgb8;
}

/** A new raster with a colour-vision view applied to every pixel. */
export function applyView(raster, view) {
  if (view === 'color' || !view) return raster;
  const out = new Raster(raster.w, raster.h, null);
  for (let i = 0; i < raster.data.length; i += 3) {
    const c = viewColor([raster.data[i], raster.data[i + 1], raster.data[i + 2]], view);
    out.data[i] = c[0]; out.data[i + 1] = c[1]; out.data[i + 2] = c[2];
  }
  return out;
}

/**
 * Ramp evenness: how uniform the steps of a ramp are in lightness and in perceptual
 * distance. `evennessL` near 1 means the ΔL between steps barely varies — the property a
 * good pixel-art ramp needs so its steps dither cleanly.
 */
export function rampEvenness(entries) {
  if (entries.length < 2) return { deltaL: [], deltaE: [], meanL: 0, stdevL: 0, evennessL: 1, meanE: 0, stdevE: 0, evennessE: 1 };
  const deltaL = [];
  const deltaE = [];
  for (let i = 1; i < entries.length; i++) {
    deltaL.push(Math.abs(entries[i].actual.L - entries[i - 1].actual.L));
    deltaE.push(deltaEOK(entries[i].lab, entries[i - 1].lab));
  }
  const stats = (arr) => {
    const mean = arr.reduce((a, b) => a + b, 0) / arr.length;
    const variance = arr.reduce((a, b) => a + (b - mean) ** 2, 0) / arr.length;
    const stdev = Math.sqrt(variance);
    const evenness = mean > 0 ? clamp(1 - stdev / mean, 0, 1) : 1;
    return { mean, stdev, evenness };
  };
  const sL = stats(deltaL);
  const sE = stats(deltaE);
  return {
    deltaL, deltaE,
    meanL: sL.mean, stdevL: sL.stdev, evennessL: sL.evenness,
    meanE: sE.mean, stdevE: sE.stdev, evennessE: sE.evenness,
  };
}

/** Group palette entries into ramps keyed by layer+hue, in stable order. */
export function rampsOf(palette) {
  const groups = new Map();
  for (const e of palette.entries) {
    if (e.layer !== 'fg' && e.layer !== 'bg') continue;
    const key = `${e.layer}_h${e.hueIndex}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(e);
  }
  for (const arr of groups.values()) arr.sort((a, b) => a.step - b.step);
  return [...groups.entries()].map(([key, entries]) => ({ key, entries }));
}

/** OKLab `[L,a,b]` for an `[r,g,b]` colour — used by scatter plots and distance views. */
export function labOf(rgb8) {
  return rgb8ToOklab(rgb8);
}
