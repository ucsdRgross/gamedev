// Headless renderer: writes palettes to out/*.png for direct inspection.
//
//   npm run render
//
// Phase 1 output: a labelled swatch sheet per preset, the raw 1px export strips, a
// contact sheet of every preset, and a size sweep of the defaults.

import { rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Surface, readableOn, textWidth } from './surface.mjs';
import { generatePalette, paletteHexes } from '../src/core/generate.js';
import { PRESETS, presetParams } from '../src/core/presets.js';
import { defaultParams } from '../src/core/params.js';
import { toPngStrip } from '../src/core/export/png.js';
import { rankReferences } from '../src/core/reference.js';
import { writePNG } from './png.mjs';
import { SCENES, CATEGORIES } from '../src/scenes/index.js';
import { Raster } from '../src/core/raster.js';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'out');
const BG = [22, 22, 28];
const INK = [225, 225, 232];
const DIM = [128, 128, 140];

const CELL = 56;
const GAP = 4;
const COLUMNS = 8;
const PAD = 12;
const HEADER = 26;

/** Draw one labelled swatch sheet for a palette. */
function swatchSheet(palette, title, subtitle) {
  const n = palette.entries.length;
  const cols = Math.min(COLUMNS, n);
  const rows = Math.ceil(n / cols);
  const width = PAD * 2 + cols * CELL + (cols - 1) * GAP;
  const height = PAD * 2 + HEADER + rows * CELL + (rows - 1) * GAP + 14;
  const s = new Surface(width, height, BG);

  s.text(title.toUpperCase(), PAD, PAD, 3, INK);
  if (subtitle) s.text(subtitle.toUpperCase(), PAD, PAD + 18, 1, DIM);

  palette.entries.forEach((e, i) => {
    const x = PAD + (i % cols) * (CELL + GAP);
    const y = PAD + HEADER + Math.floor(i / cols) * (CELL + GAP);
    s.rect(x, y, CELL, CELL, e.rgb8);
    if (e.locked || e.overridden) s.outline(x, y, CELL, CELL, INK);
    const ink = readableOn(e.rgb8);
    s.text(e.hex.slice(1), x + 3, y + 3, 1, ink);
    s.text(String(i), x + 3, y + CELL - 8, 1, ink);
    // Role name, trimmed to whatever fits in the cell.
    const label = e.role.replace(/^universal_/, 'U_').replace(/^neutral_warm_/, 'NW');
    const max = Math.floor((CELL - 6) / 4);
    s.text(label.slice(0, max), x + 3, y + 11, 1, ink);
  });

  const footer = `${n} COLORS  ${palette.warnings.length ? `${palette.warnings.length} WARNINGS` : 'CLEAN'}`;
  s.text(footer, PAD, height - 12, 1, palette.warnings.length ? [230, 140, 100] : DIM);
  return s;
}

/** Draw a compact one-row strip for the contact sheet. */
function contactRow(palette, label, width, rowHeight) {
  const s = new Surface(width, rowHeight, BG);
  const labelWidth = 96;
  s.text(label.toUpperCase().slice(0, 22), 4, Math.floor((rowHeight - 5) / 2), 1, INK);
  const n = palette.entries.length;
  const swatchArea = width - labelWidth - 4;
  palette.entries.forEach((e, i) => {
    const x = labelWidth + Math.round((i * swatchArea) / n);
    const w = Math.round(((i + 1) * swatchArea) / n) - Math.round((i * swatchArea) / n);
    s.rect(x, 2, Math.max(1, w), rowHeight - 4, e.rgb8);
  });
  return s;
}

/** Write a Raster straight to a PNG file. */
function saveRaster(raster, path) {
  writePNG(path, raster.w, raster.h, raster.data);
}

/** Render one scene into a fresh scaled Raster. */
function renderScene(scene, palette, scale, frame = 0) {
  const r = new Raster(scene.width, scene.height);
  scene.render(r, palette, { frame });
  return scale > 1 ? r.scaled(scale) : r;
}

/**
 * Compose a category's scenes into one readable contact sheet: each scene scaled up,
 * three per row, titled with its id. This is the image to actually read at the gate.
 */
function sceneSheet(scenes, palette, scale) {
  const label = 8;
  const pad = 8;
  const imgs = scenes.map((s) => renderScene(s, palette, scale));
  const cols = Math.min(3, scenes.length);
  const cellW = Math.max(...imgs.map((i) => i.w)) + pad;
  const rows = Math.ceil(scenes.length / cols);
  const rowH = [];
  for (let r = 0; r < rows; r++) {
    const rowImgs = imgs.slice(r * cols, r * cols + cols);
    rowH.push(Math.max(...rowImgs.map((i) => i.h)) + label + pad);
  }
  const width = pad + cols * cellW;
  const height = pad + 12 + rowH.reduce((a, b) => a + b, 0);
  const sheet = new Raster(width, height, BG);
  sheet.text((scenes[0].category).toUpperCase(), pad, 3, 1, INK);
  let y = pad + 12;
  imgs.forEach((img, i) => {
    const col = i % cols;
    const row = Math.floor(i / cols);
    const x = pad + col * cellW;
    const cy = y + rowH.slice(0, row).reduce((a, b) => a + b, 0);
    sheet.text(scenes[i].id.toUpperCase().slice(0, Math.floor(cellW / 4)), x, cy, 1, DIM);
    sheet.blit(img, x, cy + label);
  });
  return sheet;
}

/** Render every scene for a palette: per-scene PNGs plus per-category contact sheets. */
function renderScenes(palette, tag) {
  for (const scene of SCENES) {
    saveRaster(renderScene(scene, palette, 3), join(OUT, 'scenes', tag, `${scene.id}.png`));
  }
  for (const cat of CATEGORIES) {
    const scenes = SCENES.filter((s) => s.category === cat);
    const slug = cat.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    saveRaster(sceneSheet(scenes, palette, 3), join(OUT, 'scene-sheets', `${tag}-${slug}.png`));
  }
  // A few frames of the animated scene, so motion is inspectable as a filmstrip.
  const anim = SCENES.find((s) => s.animated);
  if (anim) {
    const frames = [0, Math.floor(anim.frames / 3), Math.floor((anim.frames * 2) / 3)];
    frames.forEach((f) => saveRaster(renderScene(anim, palette, 3, f), join(OUT, 'scenes', tag, `${anim.id}-f${f}.png`)));
  }
}

/** Render every preset, the contact sheet, and a size sweep of the defaults. */
function main() {
  rmSync(OUT, { recursive: true, force: true });
  const summary = [];

  for (const preset of PRESETS) {
    const params = presetParams(preset.id);
    const palette = generatePalette(params);
    const best = rankReferences(paletteHexes(palette))[0];
    const subtitle = `${preset.group}  k=${params.color_count}  bits ${params.bits_r}/${params.bits_g}/${params.bits_b}  nearest ${best.name} ${best.score.toFixed(1)}`;
    swatchSheet(palette, preset.name, subtitle).save(join(OUT, 'presets', `${preset.id}.png`));
    writePNG(
      join(OUT, 'strips', `${preset.id}.png`),
      palette.entries.length, 1,
      Uint8Array.from(palette.entries.flatMap((e) => e.rgb8)),
    );
    summary.push({ preset, palette });
  }

  // Contact sheet: every preset as one row, for at-a-glance comparison.
  const rowHeight = 22;
  const sheetWidth = 640;
  const sheet = new Surface(sheetWidth, PAD * 2 + 22 + summary.length * rowHeight, BG);
  sheet.text('PRESET CONTACT SHEET', PAD, PAD, 2, INK);
  summary.forEach(({ preset, palette }, i) => {
    sheet.blit(contactRow(palette, preset.name, sheetWidth - PAD * 2, rowHeight), PAD, PAD + 22 + i * rowHeight);
  });
  sheet.save(join(OUT, 'contact-sheet.png'));

  // Size sweep: the default parameters at every interesting budget.
  const sizes = [4, 8, 12, 16, 24, 32, 48, 64];
  for (const k of sizes) {
    const palette = generatePalette({ ...defaultParams(), color_count: k });
    swatchSheet(palette, `Default K=${k}`, `derived hues: ${palette.plan.hueCount}  fg ramps: ${palette.plan.fgLen.join('/')}  bg: ${palette.plan.bgLen.join('/')}`)
      .save(join(OUT, 'sizes', `k${String(k).padStart(2, '0')}.png`));
  }

  const sizeSheet = new Surface(sheetWidth, PAD * 2 + 22 + sizes.length * rowHeight, BG);
  sizeSheet.text('DEFAULT PARAMETERS BY BUDGET', PAD, PAD, 2, INK);
  sizes.forEach((k, i) => {
    const palette = generatePalette({ ...defaultParams(), color_count: k });
    sizeSheet.blit(contactRow(palette, `K=${k}`, sheetWidth - PAD * 2, rowHeight), PAD, PAD + 22 + i * rowHeight);
  });
  sizeSheet.save(join(OUT, 'size-sweep.png'));

  // Gallery scenes: render for the defaults and for one vivid preset, so role usage is
  // checked against very different palettes.
  renderScenes(generatePalette(defaultParams()), 'default');
  renderScenes(generatePalette(presetParams('neon-cyberpunk')), 'neon');

  const strip = toPngStrip(generatePalette(defaultParams()), { cell: 1, height: 1 });
  console.log(`rendered ${PRESETS.length} presets and ${sizes.length} sizes to ${OUT}`);
  console.log(`rendered ${SCENES.length} scenes (×2 palettes) + ${CATEGORIES.length} category sheets`);
  console.log(`export strip sanity: ${strip.length} bytes`);
  const dirty = summary.filter(({ palette }) => palette.warnings.length);
  if (dirty.length) {
    console.log('presets with warnings:');
    for (const { preset, palette } of dirty) console.log(`  ${preset.id}: ${palette.warnings.join('; ')}`);
  } else {
    console.log('all presets generated without warnings');
  }
}

main();
