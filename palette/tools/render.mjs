// Headless renderer: writes palettes to out/*.png for direct inspection.
//
//   npm run render
//
// Phase 1 output: a labelled swatch sheet per preset, the raw 1px export strips, a
// contact sheet of every preset, and a size sweep of the defaults.

import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
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
import { rankLayouts } from '../src/core/layout/index.js';
import { contactSheet, contextSheet, ditherSheet, layoutRaster, mapSheet } from '../src/core/layout/render.js';
import { buildReach } from '../src/core/layout/reach.js';
import { MAP_GEOMETRIES, buildContextMaps, buildMapSlices, mapFidelity } from '../src/core/layout/colorspace.js';
import { builtinSamples } from '../src/core/recolor/samples.js';
import { recolorFrames } from '../src/core/recolor/index.js';
import { countUniqueColors } from '../src/core/recolor/image.js';
import { encodeGif } from '../src/core/gif.js';

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

/**
 * Render the picker: every layout variant at full size plus one contact sheet, ranked
 * best mean-neighbour ΔE first. Returns the ranking so it can be printed.
 */
function renderLayouts(palette, tag) {
  const ranked = rankLayouts(palette);
  for (const layout of ranked) {
    // Both edge treatments, because which one reads better is a judgement to make by eye.
    saveRaster(layoutRaster(layout, palette, { scale: 6 }), join(OUT, 'layouts', tag, `${layout.id}.png`));
    saveRaster(layoutRaster(layout, palette, { scale: 6, edges: 'shade' }), join(OUT, 'layouts', tag, `${layout.id}-shaded.png`));
  }
  saveRaster(contactSheet(ranked, palette, { scale: 3 }), join(OUT, `layout-sheet-${tag}.png`));
  saveRaster(contactSheet(ranked, palette, { scale: 3, edges: 'shade' }), join(OUT, `layout-sheet-${tag}-shaded.png`));
  return ranked;
}

/**
 * Render the colour-space maps (PLAN §9.1): both geometries, every saturation slice, with
 * the unreachable colours strip. Returns the coverage figures, which are the number GATE 4b
 * is reported against — a map that claims full coverage is a map that has started cheating.
 */
function renderMaps(palette, tag) {
  // The by-context sheet: the same hue×lightness geometry per artistic context, so each chart
  // answers "what may I use here" while a colour keeps the position it has on the full map.
  const contexts = buildContextMaps(palette, { geometry: 'rect', size: { w: 168, h: 84 } });
  saveRaster(contextSheet(contexts, palette).raster, join(OUT, 'maps', `${tag}-context.png`));

  return MAP_GEOMETRIES.map((geometry) => {
    const set = buildMapSlices(palette, { geometry });
    saveRaster(mapSheet(set, palette, { columns: 2 }).raster, join(OUT, 'maps', `${tag}-${geometry}.png`));
    return {
      geometry,
      shownCount: set.shownCount,
      total: set.total,
      slices: set.slices.map((s) => ({ saturation: s.saturation, shownCount: s.shownCount, fidelity: mapFidelity(s, palette) })),
      missing: set.missing.map((i) => palette.entries[i].hex),
      contexts: contexts.map((c) => ({ id: c.context.id, total: c.total, shownCount: c.shownCount })),
    };
  });
}

/**
 * Render the dithering reference (PLAN §9.3): what the palette can reach by mixing, and every
 * way to mix it.
 *
 * The figures returned are what GATE 4c is reported against, and the two that matter are read
 * together: `dithered` against `flat` is what dithering buys, and `dithered` against `floor` is
 * whether any more of it is available. A view that claimed to reach everything would be a view
 * that had started cheating, exactly as for the maps above.
 */
function renderDither(palette, tag) {
  const reach = buildReach(palette);
  const sheet = ditherSheet(reach);
  saveRaster(sheet.raster, join(OUT, 'dither', `${tag}.png`));
  return { tag, ...reach.stats, suggestions: reach.suggestions, hatched: sheet.overlayCount };
}

/**
 * Render the reference recolouring (PLAN §19.3): every built-in sample, original above
 * recoloured, as one sheet per palette. Animations are laid out as filmstrips, because a
 * PNG cannot animate — and written out as real animated GIFs beside the sheet, which is the
 * form the app actually produces.
 */
function renderRecolor(palette, tag, options = {}) {
  const pad = 8;
  const label = 8;
  const scale = 2;
  const samples = builtinSamples();
  const rows = samples.map((s) => {
    const result = recolorFrames(s.frames, palette, options);
    // A still PNG cannot animate, so an animation becomes a filmstrip — capped, because a
    // long one would set the width of the whole sheet and leave every other row in a desert
    // of background. The real animations are written beside the sheet as GIFs.
    const strip = (frames) => {
      const shown = frames.slice(0, 8);
      const first = shown[0].image;
      const r = new Raster(first.w * shown.length + 2 * (shown.length - 1), first.h, BG);
      shown.forEach((f, i) => r.blit(f.image, i * (first.w + 2), 0));
      return r.scaled(scale);
    };
    return { sample: s, result, before: strip(s.frames), after: strip(result.frames) };
  });

  const width = pad * 2 + Math.max(...rows.map((r) => r.before.w));
  const height = pad + rows.reduce((n, r) => n + label * 2 + r.before.h + r.after.h + pad * 2, 0);
  const sheet = new Raster(width, height, BG);
  let y = pad;
  for (const row of rows) {
    const unique = countUniqueColors(row.sample.frames[0].image);
    sheet.text(`${row.sample.title.toUpperCase()}  ${unique} COLOURS  ${row.result.mode.toUpperCase()}`, pad, y, 1, INK);
    y += label;
    sheet.blit(row.before, pad, y);
    y += row.before.h + 2;
    sheet.blit(row.after, pad, y);
    y += row.after.h + pad;

    if (row.sample.kind === 'animated') {
      writeFileSync(
        join(OUT, 'recolor', `${tag}-${row.sample.id}.gif`),
        encodeGif(row.result.frames, palette.entries.map((e) => e.rgb8)),
      );
    }
  }
  saveRaster(sheet, join(OUT, `recolor-sheet-${tag}.png`));
  return rows.map((r) => ({
    id: r.sample.id,
    mode: r.result.mode,
    unique: countUniqueColors(r.sample.frames[0].image),
    frames: r.sample.frames.length,
  }));
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

  // Picker layouts: the defaults at a full budget, where arrangement actually matters.
  const pickerPalette = generatePalette({ ...defaultParams(), color_count: 48 });
  const ranked = renderLayouts(pickerPalette, 'default48');
  renderLayouts(generatePalette(presetParams('neon-cyberpunk')), 'neon');

  // Colour-space maps: the picker's default view, for the same two palettes.
  const maps = renderMaps(pickerPalette, 'default48');
  renderMaps(generatePalette(presetParams('neon-cyberpunk')), 'neon');

  // The dithering reference: the same full-budget palette, plus a deliberately hard case.
  // Game Boy is four colours of one hue, so it is where "try its best even when a complete
  // colormap is impossible" either holds up or does not.
  mkdirSync(join(OUT, 'dither'), { recursive: true });
  const dither = [
    renderDither(pickerPalette, 'default48'),
    renderDither(generatePalette(presetParams('neon-cyberpunk')), 'neon'),
    renderDither(generatePalette(presetParams('gameboy')), 'gameboy'),
  ];

  // Reference recolouring: the same two palettes, so the sheets can be read side by side.
  mkdirSync(join(OUT, 'recolor'), { recursive: true });
  const recoloured = renderRecolor(generatePalette(defaultParams()), 'default');
  renderRecolor(generatePalette(presetParams('gameboy')), 'gameboy');
  // The same palette with context awareness on, so the two sheets can be read against each
  // other. Whether the trade it makes (ARCHITECTURE §12.8: separation bought with fidelity) is
  // worth it on a given image is a judgement by eye, and this is what there is to judge.
  renderRecolor(generatePalette(defaultParams()), 'default-context', {
    recolorContext: 'suggest', contextBias: 1,
  });

  const strip = toPngStrip(generatePalette(defaultParams()), { cell: 1, height: 1 });
  console.log(`rendered ${PRESETS.length} presets and ${sizes.length} sizes to ${OUT}`);
  console.log(`rendered ${SCENES.length} scenes (×2 palettes) + ${CATEGORIES.length} category sheets`);
  console.log(`picker layouts ranked (K=${pickerPalette.entries.length}, mean / worst neighbour dE):`);
  for (const l of ranked) {
    const flag = l.optimized ? 'opt' : '   ';
    console.log(`  ${flag} ${String(l.variant).padStart(2)}. ${l.title.padEnd(26)} ${l.score.mean.toFixed(3).padStart(7)} ${l.score.worst.toFixed(1).padStart(6)}`);
  }
  console.log(`colour-space maps (K=${pickerPalette.entries.length}, shown/total per slice, mean dE to the true colour):`);
  for (const m of maps) {
    const slices = m.slices.map((s) => `s${s.saturation.toFixed(2)} ${s.shownCount}/${m.total} (dE ${s.fidelity.toFixed(1)})`).join('  ');
    console.log(`  ${m.geometry.padEnd(6)} union ${m.shownCount}/${m.total}   ${slices}`);
    if (m.missing.length) console.log(`         reached by no slice: ${m.missing.join(' ')}`);
  }
  console.log('dithering reach (mean dE to colour space / share band-free, flat -> dithered -> best possible):');
  for (const d of dither) {
    const pc = (v) => `${String(Math.round(v * 100)).padStart(3)}%`;
    console.log(`  ${d.tag.padEnd(10)} K=${String(d.k).padStart(2)}  ${d.distinct} reachable`
      + `   flat ${d.flat.mean.toFixed(2)} ${pc(d.flat.within)}`
      + ` -> dithered ${d.dithered.mean.toFixed(2)} ${pc(d.dithered.within)}`
      + (d.floor ? ` -> floor ${d.floor.mean.toFixed(2)} ${pc(d.floor.within)}` : '')
      + `   ${Object.entries(d.byArity).map(([a, n]) => `${n}x${a}`).join(' ')}`);
    if (d.suggestions.length) {
      console.log(`             add ${d.suggestions.map((s) => `${s.hex} (-> ${s.after.mean.toFixed(2)})`).join('  ')}`);
    }
  }
  console.log('reference recolouring (source colours -> chosen mode):');
  for (const r of recoloured) {
    const anim = r.frames > 1 ? `${r.frames} frames` : 'still';
    console.log(`  ${r.id.padEnd(10)} ${String(r.unique).padStart(5)} colours  ${r.mode.padEnd(9)} ${anim}`);
  }
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
