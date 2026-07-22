// Palette-structure scenes 1–6 (PLAN §8): swatch grid, ramp strips, value view, OKLCH
// scatter plots, ΔE adjacency heatmap, and the colorblind board.

import { rgb, ramps, anchorDark, anchorLight, allEntries } from './util.js';
import { toValue, simulateColorblind, labOf } from '../core/analysis.js';
import { deltaEOK, normHue } from '../core/oklch.js';

const CAT = 'Structure';

/** Fill the surface with a neutral backdrop drawn from the palette's dark anchor. */
function backdrop(surface, palette) {
  const d = anchorDark(palette).rgb8;
  surface.rect(0, 0, surface.w, surface.h, [
    Math.min(255, d[0] + 14), Math.min(255, d[1] + 14), Math.min(255, d[2] + 16),
  ]);
}

/** A text colour that reads on the backdrop. */
function ink(palette) {
  return anchorLight(palette).rgb8;
}

// --- 1. Swatch grid --------------------------------------------------------
function renderSwatchGrid(surface, palette) {
  backdrop(surface, palette);
  const entries = allEntries(palette);
  const cols = 8;
  const cell = Math.floor((surface.w - 2) / cols);
  for (let i = 0; i < entries.length; i++) {
    const cx = 1 + (i % cols) * cell;
    const cy = 1 + Math.floor(i / cols) * cell;
    surface.rect(cx, cy, cell - 1, cell - 1, rgb(entries[i]));
    // value corner + a marker for locked/overridden slots
    surface.rect(cx + cell - 5, cy, 4, cell - 1, toValue(rgb(entries[i])));
    if (entries[i].fixed) surface.outline(cx, cy, cell - 1, cell - 1, ink(palette));
  }
}

// --- 2. Ramp strips --------------------------------------------------------
function renderRampStrips(surface, palette) {
  backdrop(surface, palette);
  const all = [...ramps(palette, 'fg'), ...ramps(palette, 'bg')];
  const rowH = Math.max(6, Math.floor((surface.h - 2) / Math.max(1, all.length)));
  const maxSteps = Math.max(1, ...all.map((r) => r.length));
  const stepW = Math.floor((surface.w - 2) / maxSteps);
  all.forEach((ramp, row) => {
    const y = 1 + row * rowH;
    ramp.forEach((e, s) => surface.rect(1 + s * stepW, y, stepW - 1, rowH - 1, rgb(e)));
  });
}

// --- 3. Value-only view ----------------------------------------------------
function renderValueView(surface, palette) {
  backdrop(surface, palette);
  const all = [...ramps(palette, 'fg'), ...ramps(palette, 'bg')];
  const rowH = Math.max(6, Math.floor((surface.h - 2) / Math.max(1, all.length)));
  const maxSteps = Math.max(1, ...all.map((r) => r.length));
  const stepW = Math.floor((surface.w - 2) / maxSteps);
  all.forEach((ramp, row) => {
    const y = 1 + row * rowH;
    // Top half colour, bottom half its value — the ΔL evenness is read from the grays.
    ramp.forEach((e, s) => {
      const x = 1 + s * stepW;
      surface.rect(x, y, stepW - 1, Math.floor((rowH - 1) / 2), rgb(e));
      surface.rect(x, y + Math.floor((rowH - 1) / 2), stepW - 1, Math.ceil((rowH - 1) / 2), toValue(rgb(e)));
    });
  });
}

// --- 4. OKLCH scatter plots ------------------------------------------------
function renderScatter(surface, palette) {
  backdrop(surface, palette);
  const half = Math.floor(surface.w / 2);
  const grid = ink(palette).map((v) => Math.round(v * 0.35));
  // Left: L (y, up=light) vs C (x). Right: polar hue wheel (angle=hue, radius=chroma).
  surface.outline(1, 1, half - 2, surface.h - 2, grid);
  surface.outline(half + 1, 1, half - 2, surface.h - 2, grid);
  const cxp = half + Math.floor(half / 2);
  const cyp = Math.floor(surface.h / 2);
  const rad = Math.floor(Math.min(half, surface.h) / 2) - 4;
  for (const e of allEntries(palette)) {
    const { L, C, h } = e.actual;
    // L×C plane
    const px = 2 + Math.round((C / 0.37) * (half - 6));
    const py = 1 + Math.round((1 - L) * (surface.h - 4));
    surface.disc(px, py, 1, rgb(e));
    // hue wheel
    const a = (normHue(h) * Math.PI) / 180;
    const rr = (C / 0.37) * rad;
    surface.disc(cxp + Math.round(Math.cos(a) * rr), cyp + Math.round(Math.sin(a) * rr), 1, rgb(e));
  }
}

// --- 5. ΔE adjacency heatmap ----------------------------------------------
function renderHeatmap(surface, palette) {
  backdrop(surface, palette);
  const es = allEntries(palette);
  const n = es.length;
  const cell = Math.max(1, Math.floor((Math.min(surface.w, surface.h) - 2) / n));
  const labs = es.map((e) => labOf(e.rgb8));
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      const d = i === j ? 0 : deltaEOK(labs[i], labs[j]);
      // Near-duplicates glow red; well-separated pairs are dark; the diagonal is black.
      let col;
      if (i === j) col = [0, 0, 0];
      else if (d < 4) col = [220, 60, 40];
      else { const t = Math.min(1, d / 30); const v = Math.round(30 + t * 200); col = [v, v, v]; }
      surface.rect(1 + j * cell, 1 + i * cell, cell, cell, col);
    }
  }
}

// --- 6. Colorblind board ---------------------------------------------------
function renderColorblindBoard(surface, palette) {
  backdrop(surface, palette);
  const es = allEntries(palette);
  const views = [['NORMAL', null], ['PROT', 'protan'], ['DEUT', 'deutan'], ['TRIT', 'tritan']];
  const blockH = Math.floor((surface.h - 2) / 4);
  const cols = Math.min(16, es.length);
  const swW = Math.floor((surface.w - 2) / cols);
  views.forEach(([label, type], b) => {
    const y = 1 + b * blockH;
    surface.text(label, 2, y + 1, 1, ink(palette));
    const rowY = y + 7;
    const swH = blockH - 8;
    es.slice(0, cols).forEach((e, i) => {
      const c = type ? simulateColorblind(e.rgb8, type) : e.rgb8;
      surface.rect(1 + i * swW, rowY, swW - 1, Math.max(2, swH), c);
    });
  });
}

export const structureScenes = [
  { id: 'swatch-grid', title: 'Swatch grid', category: CAT, width: 128, height: 128, render: renderSwatchGrid },
  { id: 'ramp-strips', title: 'Ramp strips', category: CAT, width: 128, height: 112, render: renderRampStrips },
  { id: 'value-view', title: 'Value-only view', category: CAT, width: 128, height: 112, render: renderValueView },
  { id: 'oklch-scatter', title: 'OKLCH scatter', category: CAT, width: 160, height: 96, render: renderScatter },
  { id: 'delta-e-heatmap', title: 'ΔE adjacency heatmap', category: CAT, width: 132, height: 132, render: renderHeatmap },
  { id: 'colorblind-board', title: 'Colorblind board', category: CAT, width: 144, height: 120, render: renderColorblindBoard },
];
