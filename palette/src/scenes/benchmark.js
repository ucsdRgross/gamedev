// Benchmark scenes 33–34 (PLAN §8): photo-style quantization of built-in reference
// images, and a side-by-side compare of our palette against embedded real palettes with
// a numeric ΔE fit score. These are the harshest tests — smooth full-colour sources
// expose gaps no hand-made sprite will.
//
// Scene 33 ships three procedurally-generated references so it works with nothing added
// to the repo; the interactive drag-and-drop is a gallery-UI feature layered on top.

import { rgb, role, anchorDark, anchorLight } from './util.js';
import { paletteHexes } from '../core/generate.js';
import { floydSteinberg, orderedDither } from '../core/dither.js';
import { REFERENCE_PALETTES, rankReferences } from '../core/reference.js';
import { hexToRgb8, oklchToSrgb, srgbToRgb8 } from '../core/oklch.js';
import { Raster } from '../core/raster.js';

const CAT = 'Benchmark';

const paletteRgb = (palette) => palette.entries.map((e) => e.rgb8);
function mix(a, b, t) {
  return [Math.round(a[0] + (b[0] - a[0]) * t), Math.round(a[1] + (b[1] - a[1]) * t), Math.round(a[2] + (b[2] - a[2]) * t)];
}

// --- Procedural reference images (full colour, palette-independent) --------

/** A smoothly-shaded orange sphere on a dark ground — the classic volume reference. */
export function refLitSphere(w, h) {
  const r = new Raster(w, h, [24, 22, 30]);
  const cx = w / 2;
  const cy = h / 2;
  const rad = Math.min(w, h) * 0.42;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const nx = (x - cx) / rad;
      const ny = (y - cy) / rad;
      const d2 = nx * nx + ny * ny;
      if (d2 > 1) continue;
      const nz = Math.sqrt(1 - d2);
      const l = Math.max(0, nx * -0.45 + ny * -0.5 + nz * 0.74);
      const L = 0.15 + l * 0.75;
      r.set(x, y, srgbToRgb8(oklchToSrgb(L, 0.13 * (0.4 + l), 50)));
    }
  }
  return r;
}

/** A flesh gradient field: hue warms left→right, light falls top→bottom. */
export function refFleshField(w, h) {
  const r = new Raster(w, h, null);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const hue = 30 + (x / w) * 40;
      const L = 0.82 - (y / h) * 0.5;
      r.set(x, y, srgbToRgb8(oklchToSrgb(L, 0.07, hue)));
    }
  }
  return r;
}

/** A hazy landscape: sky gradient over layered hills fading toward atmosphere. */
export function refHazyLandscape(w, h) {
  const r = new Raster(w, h, null);
  const haze = srgbToRgb8(oklchToSrgb(0.8, 0.03, 230));
  for (let y = 0; y < h; y++) {
    const c = srgbToRgb8(oklchToSrgb(0.9 - (y / h) * 0.35, 0.05, 230 - (y / h) * 40));
    for (let x = 0; x < w; x++) r.set(x, y, c);
  }
  const layers = [{ y: 0.55, L: 0.5, hz: 0.55 }, { y: 0.7, L: 0.38, hz: 0.3 }, { y: 0.85, L: 0.25, hz: 0.05 }];
  for (const L of layers) {
    let col = srgbToRgb8(oklchToSrgb(L.L, 0.06, 150));
    col = mix(col, haze, L.hz);
    for (let x = 0; x < w; x++) {
      const hy = Math.floor(h * L.y - Math.sin(x * 0.07 + L.y * 8) * h * 0.06);
      for (let y = hy; y < h; y++) r.set(x, y, col);
    }
  }
  return r;
}

const REFS = [refLitSphere, refFleshField, refHazyLandscape];

// --- 33. Photo quantization ------------------------------------------------
function renderPhotoQuant(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, anchorDark(palette).rgb8);
  const pr = paletteRgb(palette);
  const tileW = Math.floor((surface.w - 4) / 3);
  const rowH = Math.floor((surface.h - 2) / REFS.length);
  const imgH = rowH - 2;
  REFS.forEach((make, i) => {
    const y = 1 + i * rowH;
    const src = make(tileW, imgH);
    const fs = floydSteinberg(src, pr);
    const bay = orderedDither(src, pr, { size: 8, strength: 34 });
    surface.blit(src, 1, y);
    surface.blit(fs, 2 + tileW, y);
    surface.blit(bay, 3 + tileW * 2, y);
  });
  surface.text('SRC', 1, 0, 1, anchorLight(palette).rgb8);
  surface.text('FS', 2 + tileW, 0, 1, anchorLight(palette).rgb8);
  surface.text('BAYER', 3 + tileW * 2, 0, 1, anchorLight(palette).rgb8);
}

// --- 34. Reference compare with ΔE fit score -------------------------------
function renderReferenceCompare(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, anchorDark(palette).rgb8);
  const ourHexes = paletteHexes(palette);
  // Our palette plus the two closest embedded references, each quantizing the same image.
  const ranked = rankReferences(ourHexes).slice(0, 2);
  const cols = [
    { label: 'YOURS', rgb: paletteRgb(palette), score: null },
    ...ranked.map((r) => {
      const ref = REFERENCE_PALETTES.find((p) => p.id === r.id);
      return { label: r.name, rgb: ref.colors.map(hexToRgb8), score: r.score };
    }),
  ];
  const tileW = Math.floor((surface.w - (cols.length + 1)) / cols.length);
  const imgH = surface.h - 14;
  const src = refHazyLandscape(tileW, imgH);
  cols.forEach((col, i) => {
    const x = 1 + i * (tileW + 1);
    surface.blit(floydSteinberg(src, col.rgb), x, 8);
    surface.text(col.label.toUpperCase().slice(0, 8), x, 1, 1, anchorLight(palette).rgb8);
    if (col.score !== null) surface.text(`DE ${col.score.toFixed(1)}`, x, surface.h - 6, 1, rgb(role(palette, 'gold')));
  });
}

export const benchmarkScenes = [
  { id: 'photo-quant', title: 'Photo quantization', category: CAT, width: 160, height: 120, render: renderPhotoQuant },
  { id: 'reference-compare', title: 'Reference compare (ΔE fit)', category: CAT, width: 168, height: 96, render: renderReferenceCompare },
];
