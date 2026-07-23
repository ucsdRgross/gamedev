// The reference-recolouring gallery (PLAN §19.3). Every reference image on one page,
// original beside recoloured, updating live with the palette.
//
// **Animations play.** A GIF is recoloured whole — every frame — and both the original and
// the recoloured version animate at the source's own timing (spec changed 2026-07-22).
//
// **Everything is lazy, and that is not an optimisation.** A real reference library is not
// six small samples: measured on the author's, 82 files of which most are 512×512 GIFs with
// 20 to 189 frames, decoding *one* takes 1.3–1.9 seconds. Loading them all up front is two
// minutes of frozen page, and recolouring them all on every slider drag is worse. So a card
// is created immediately from the file name alone and does its work — fetch, decode,
// recolour, paint — only when it scrolls into view. Off-screen cards are not decoded, not
// recoloured and not animated.
//
// Decoding lives here, at the edge, because `src/core/` may not touch the DOM: PNG and JPEG
// come in through `Image` + canvas, and GIF through `src/core/gif.js`, which is the only way
// to get at the individual frames at all.

import { builtinSamples } from '../core/recolor/samples.js';
import { recolorFrames } from '../core/recolor/index.js';
import { extractPalette, externalPalette } from '../core/recolor/swatches.js';
import { decodeGif, encodeGif } from '../core/gif.js';
import { encodePngRgb } from '../core/export/png.js';
import { Raster } from '../core/raster.js';
import { download } from './io.js';

const MODE_LABELS = { indexed: 'indexed remap', quantize: 'per-pixel quantize' };
const TICK_MS = 40;
const GENERATED = 'generated'; // the target-selector value for the live generated palette

/**
 * Build the recolour gallery. Returns `{ render(palette, params) }` for the app to call
 * after every regeneration, `{ setActive(bool) }` so it can idle while hidden, and
 * `{ addFiles(fileList) }` for the drop target and the file picker.
 */
export function createRecolorGallery(dom, { onStatus } = {}) {
  // The in-memory library the gallery draws from — seeded from the server when one is
  // there, extended by drag-and-drop. The gallery never reads the network directly, which
  // is what lets the standalone build work unchanged (ARCHITECTURE §12.3).
  //
  // A source starts as a *descriptor*: `{ id, title, origin, source }` where `source` is
  // either ready-made frames (the built-ins, and dropped files) or a URL to fetch on demand.
  let sources = builtinSamples().map((s) => ({
    id: s.id, title: s.title, origin: 'built-in', frames: s.frames,
  }));
  const cards = [];
  // The scrolling element is the `.scroll` pane, not the content list inside it. The sweep
  // must measure against *that* rectangle — the list's own rect grows to the full content
  // height, which would count every card as on-screen and defeat the whole point.
  const viewport = dom.container.closest('.scroll') ?? dom.container;
  // External target palettes, loaded from `palettes/` (or dropped in): id -> { name, palette }.
  // The recolour target is either the live generated palette or one of these; an external one
  // does not move when the sliders do, which is how a recolour is held still while tuning.
  const targets = new Map();
  let targetId = GENERATED;
  let palette = null;
  let params = {};
  let active = false;
  let dirty = true;
  let zoom = 2;
  let timer = null;
  let persist = true; // flipped off the first time the reference API is not there
  let sweepQueued = false;

  /** The palette every card recolours into right now — generated, or a chosen external one. */
  function currentTarget() {
    return targetId === GENERATED ? palette : targets.get(targetId)?.palette ?? palette;
  }

  /**
   * Read `palette/reference/` and make the gallery match it.
   *
   * Re-runnable, and that is the point: dropping files into the folder by hand should not
   * mean restarting the app. Folder entries are dropped and re-read wholesale so a file
   * deleted on disk disappears here too; session-only images are left alone, since nothing
   * on disk can account for them. Only the *listing* is fetched — the images themselves are
   * left to their cards.
   */
  async function loadServerLibrary(announce = false) {
    let names;
    try {
      const res = await fetch('/api/reference', { cache: 'no-store' });
      if (!res.ok) throw new Error(String(res.status));
      names = await res.json();
    } catch {
      // No server: the standalone build. Drag-and-drop still works, it just cannot persist.
      persist = false;
      dom.persistNote.hidden = false;
      if (announce) onStatus?.('no folder to rescan — running without the local server');
      return;
    }
    sources = sources.filter((s) => s.origin !== 'folder');
    for (const name of names) {
      sources.push({
        id: `folder:${name}`,
        title: name,
        origin: 'folder',
        url: `/reference/${encodeURIComponent(name)}`,
      });
    }
    dirty = true;
    rebuild();
    if (announce) onStatus?.(`folder rescanned — ${names.length} image${names.length === 1 ? '' : 's'}`);
  }

  /**
   * Read `palette/palettes/`, extract a palette from each image, and rebuild the target
   * selector. Like the reference library it is re-runnable, so palette images copied into the
   * folder by hand appear on a rescan. Extraction happens here (not lazily) because a palette
   * is tiny and its colours drive the selector and the preview immediately.
   */
  async function loadPaletteLibrary(announce = false) {
    let names;
    try {
      const res = await fetch('/api/palettes', { cache: 'no-store' });
      if (!res.ok) throw new Error(String(res.status));
      names = await res.json();
    } catch {
      persist = false;
      if (announce) onStatus?.('no palette folder to rescan — running without the local server');
      updateTargetOptions();
      return;
    }
    // Drop the folder-backed entries and re-read; session drops (no url) survive.
    for (const [id, t] of [...targets]) if (t.origin === 'folder') targets.delete(id);
    for (const name of names) {
      try {
        const res = await fetch(`/palettes/${encodeURIComponent(name)}`, { cache: 'no-store' });
        await addPaletteSource(name, new Uint8Array(await res.arrayBuffer()), 'folder');
      } catch {
        onStatus?.(`could not read palette ${name}`);
      }
    }
    updateTargetOptions();
    if (announce) onStatus?.(`palettes rescanned — ${names.length}`);
  }

  /** Decode a palette image, extract its colours, and register it as a target. */
  async function addPaletteSource(name, bytes, origin) {
    const frames = await decodeBytes(bytes, name);
    const extraction = extractPalette(frames[0].image);
    if (!extraction.kept) throw new Error('no colours found');
    const id = `pal:${name}`;
    targets.set(id, { name, origin, palette: externalPalette(name, extraction), extraction });
    return id;
  }

  /** Add dropped/picked palette images: persist to the folder if served, else keep for the session. */
  async function addPalettes(files) {
    const images = [...files].filter((f) => /\.(png|jpe?g|gif)$/i.test(f.name));
    if (!images.length) { onStatus?.('no image files in that drop'); return; }
    let lastId = null;
    for (const file of images) {
      const bytes = new Uint8Array(await file.arrayBuffer());
      try {
        if (persist) {
          try { await fetch(`/api/palettes/${encodeURIComponent(file.name)}`, { method: 'PUT', body: bytes }); }
          catch { onStatus?.(`${file.name} added for this session only`); }
        }
        lastId = await addPaletteSource(file.name, bytes, persist ? 'folder' : 'session');
      } catch (err) {
        onStatus?.(`${file.name}: ${err.message}`);
      }
    }
    // Select the palette just added — that is why someone added it.
    if (lastId) targetId = lastId;
    updateTargetOptions();
    setTarget(targetId);
    onStatus?.(`palette added: ${targets.get(lastId)?.name ?? ''}`);
  }

  /** Rebuild the target `<select>` and reflect the current choice. */
  function updateTargetOptions() {
    if (!dom.target) return;
    const opts = [[GENERATED, 'Generated palette']];
    for (const [id, t] of targets) opts.push([id, `${t.name} · ${t.palette.entries.length}`]);
    if (!targets.has(targetId) && targetId !== GENERATED) targetId = GENERATED;
    dom.target.innerHTML = '';
    for (const [value, label] of opts) {
      const o = document.createElement('option');
      o.value = value;
      o.textContent = label;
      o.selected = value === targetId;
      dom.target.appendChild(o);
    }
    drawTargetSwatches();
  }

  /** Switch the recolour target and re-recolour the cards on screen. */
  function setTarget(id) {
    targetId = id;
    drawTargetSwatches();
    refresh();
  }

  /** Show the current target's colours as a little strip, so the choice is visible. */
  function drawTargetSwatches() {
    if (!dom.targetSwatches) return;
    const target = currentTarget();
    dom.targetSwatches.innerHTML = '';
    if (!target) return;
    for (const e of target.entries) {
      const sw = document.createElement('span');
      sw.className = 'recolor-target-swatch';
      sw.style.background = e.hex;
      sw.title = e.hex;
      dom.targetSwatches.appendChild(sw);
    }
  }

  /** Decode one file's bytes into frames. */
  async function decodeBytes(bytes, name) {
    return isGif(bytes)
      ? decodeGif(bytes).frames.map((f) => ({ image: f.image, delayMs: f.delayMs }))
      : [{ image: await decodeStill(bytes, name), delayMs: 0 }];
  }

  /** Add dropped or picked files, persisting them to the folder when a server is present. */
  async function addFiles(files) {
    const images = [...files].filter((f) => /\.(png|jpe?g|gif)$/i.test(f.name));
    if (!images.length) {
      onStatus?.('no PNG, JPEG or GIF files in that drop');
      return;
    }
    let added = 0;
    for (const file of images) {
      const bytes = new Uint8Array(await file.arrayBuffer());
      if (persist) {
        try {
          await fetch(`/api/reference/${encodeURIComponent(file.name)}`, { method: 'PUT', body: bytes });
          added++;
          continue; // it is in the folder now; the rescan below picks it up like any other
        } catch {
          onStatus?.(`${file.name} added for this session only`);
        }
      }
      try {
        const frames = await decodeBytes(bytes, file.name);
        const id = `session:${file.name}`;
        const entry = { id, title: file.name, origin: 'session', frames };
        const at = sources.findIndex((s) => s.id === id);
        if (at >= 0) sources[at] = entry; else sources.push(entry);
        added++;
      } catch (err) {
        onStatus?.(`${file.name}: ${err.message}`);
      }
    }
    if (persist) await loadServerLibrary();
    else { dirty = true; rebuild(); }
    onStatus?.(`${added} image${added === 1 ? '' : 's'} added`);
  }

  /**
   * Rebuild the card list. Only the shells — a card does its real work when it is seen.
   * Cheap enough to do wholesale even with a hundred sources.
   */
  function rebuild() {
    if (!active || !palette) return;
    dom.container.innerHTML = '';
    cards.length = 0;
    for (const source of sources) cards.push(buildShell(source));
    dirty = false;
    sweep();
    restartTimer();
  }

  /**
   * Decide which cards are on screen and fill those. A plain rect test against the scroll
   * container, not an IntersectionObserver: IO does not deliver a callback when the page is
   * not being composited (headless verification, a backgrounded tab), and a gallery that
   * silently loads nothing is worse than one that measures a few rectangles. `margin` pulls
   * cards in just below the fold so scrolling meets them already decoded.
   */
  function sweep() {
    sweepQueued = false;
    if (!active || !palette) return;
    const view = viewport.getBoundingClientRect();
    const margin = view.height + 200;
    for (const card of cards) {
      const r = card.el.getBoundingClientRect();
      card.visible = r.bottom > view.top - margin && r.top < view.bottom + margin;
      if (card.visible && (!card.frames || card.stale)) void fill(card);
    }
    restartTimer();
  }

  /**
   * Coalesce a burst of scroll events into one sweep. A short timeout, not
   * `requestAnimationFrame`: rAF is paused in a backgrounded tab and does not fire at all
   * when the page is not being composited, and a gallery that stops loading the moment it
   * loses focus is a bug, not a saving.
   */
  function queueSweep() {
    if (sweepQueued) return;
    sweepQueued = true;
    setTimeout(sweep, 60);
  }

  /** A card before it has been looked at: heading, placeholder, and nothing decoded. */
  function buildShell(source) {
    const el = document.createElement('div');
    el.className = 'recolor-card';

    const head = document.createElement('div');
    head.className = 'recolor-head';
    const title = document.createElement('span');
    title.className = 'recolor-title';
    title.textContent = source.title;
    const meta = document.createElement('span');
    meta.className = 'meta';
    meta.textContent = `${source.origin} · …`;
    const save = document.createElement('button');
    save.className = 'btn btn-small';
    save.textContent = 'PNG';
    save.disabled = true;
    head.append(title, meta, save);

    const pair = document.createElement('div');
    pair.className = 'recolor-pair';

    el.append(head, pair);
    dom.container.append(el);
    return {
      source, el, meta, save, pair, frames: null, result: null,
      before: null, after: null, frame: 0, elapsed: 0, visible: false, stale: true, busy: false,
    };
  }

  /** Fetch, decode and recolour one card — once, and only when it is on screen. */
  async function fill(card) {
    const target = currentTarget();
    if (card.busy || !target) return;
    if (card.frames && !card.stale) return;
    card.busy = true;
    try {
      if (!card.frames) {
        card.frames = card.source.frames ?? null;
        if (!card.frames) {
          card.meta.textContent = `${card.source.origin} · loading…`;
          const res = await fetch(card.source.url, { cache: 'force-cache' });
          card.frames = await decodeBytes(new Uint8Array(await res.arrayBuffer()), card.source.title);
        }
      }
      card.result = recolorFrames(card.frames, target, recolorOptions(params));
      card.stale = false;
      paintCard(card);
    } catch (err) {
      card.meta.textContent = `${card.source.origin} · could not read this file`;
      onStatus?.(`${card.source.title}: ${err.message}`);
      card.frames = card.frames ?? [];
    } finally {
      card.busy = false;
    }
  }

  /** Put a filled card's pixels and readout on screen. */
  function paintCard(card) {
    const { source, frames, result } = card;
    const animated = frames.length > 1;
    card.meta.textContent = `${source.origin} · ${result.unique} colours · ${MODE_LABELS[result.mode]}`
      + (animated ? ` · ${frames.length} frames` : '');
    card.save.disabled = false;
    card.save.textContent = animated ? 'GIF' : 'PNG';
    card.save.title = animated ? 'Download the recoloured animation' : 'Download the recoloured image';
    card.save.onclick = () => exportResult(card);

    card.frame = Math.min(card.frame, frames.length - 1);
    if (!card.before) {
      card.before = canvasFor(frames[card.frame].image);
      card.after = canvasFor(result.frames[card.frame].image);
      card.pair.append(labelled('original', card.before), labelled('recoloured', card.after));
    } else {
      paint(card.before, frames[card.frame].image);
      paint(card.after, result.frames[card.frame].image);
    }
  }

  /** A canvas showing one Raster at the current zoom. */
  function canvasFor(raster) {
    const canvas = document.createElement('canvas');
    canvas.className = 'recolor-canvas';
    paint(canvas, raster);
    return canvas;
  }

  function paint(canvas, raster) {
    const scaled = zoom > 1 ? raster.scaled(zoom) : raster;
    canvas.width = scaled.w;
    canvas.height = scaled.h;
    canvas.getContext('2d').putImageData(scaled.toImageData(ImageData), 0, 0);
  }

  function labelled(text, canvas) {
    const wrap = document.createElement('div');
    wrap.className = 'recolor-slot';
    const label = document.createElement('span');
    label.className = 'recolor-slot-label';
    label.textContent = text;
    wrap.append(label, canvas);
    return wrap;
  }

  /** Download the recoloured result: a PNG for a still, an animated GIF for an animation. */
  function exportResult(card) {
    const name = card.source.title.replace(/\.[^.]+$/, '');
    if (card.frames.length > 1) {
      const bytes = encodeGif(card.result.frames, currentTarget().entries.map((e) => e.rgb8));
      download(`${name}-recoloured.gif`, bytes, 'image/gif', true);
      return;
    }
    // `gif_frame` only matters for a still export of something that has several frames.
    const frame = card.result.frames[Math.min(card.result.frames.length - 1, params.gif_frame ?? 0)].image;
    download(`${name}-recoloured.png`, encodePngRgb(frame.w, frame.h, frame.data), 'image/png', true);
  }

  /**
   * One timer for every animation on screen. Each card keeps its own elapsed time so the
   * frames advance at the source's real delays rather than at whatever rate the timer fires.
   * Only visible, filled cards are advanced — a library of a hundred animations must not
   * cost anything for the ninety that are scrolled away.
   */
  function restartTimer() {
    if (timer) clearInterval(timer);
    timer = null;
    if (!active) return;
    timer = setInterval(() => {
      for (const card of cards) {
        if (!card.visible || !card.result || card.frames.length < 2) continue;
        card.elapsed += TICK_MS;
        const delay = card.frames[card.frame].delayMs || 100;
        if (card.elapsed < delay) continue;
        card.elapsed = 0;
        card.frame = (card.frame + 1) % card.frames.length;
        paint(card.before, card.frames[card.frame].image);
        paint(card.after, card.result.frames[card.frame].image);
      }
    }, TICK_MS);
  }

  /** Mark every card as needing a re-recolour, and redo the ones on screen now. */
  function refresh() {
    for (const card of cards) card.stale = true;
    sweep();
  }

  dom.zoom.addEventListener('change', () => {
    zoom = Number(dom.zoom.value);
    dirty = true;
    rebuild();
  });
  dom.picker.addEventListener('change', () => {
    if (dom.picker.files?.length) addFiles(dom.picker.files);
    dom.picker.value = '';
  });
  dom.rescan.addEventListener('click', () => { loadServerLibrary(true); loadPaletteLibrary(); });
  dom.target?.addEventListener('change', () => setTarget(dom.target.value));
  dom.palettePicker?.addEventListener('change', () => {
    if (dom.palettePicker.files?.length) addPalettes(dom.palettePicker.files);
    dom.palettePicker.value = '';
  });
  viewport.addEventListener('scroll', queueSweep, { passive: true });
  window.addEventListener('resize', queueSweep, { passive: true });
  dom.container.addEventListener('dragover', (e) => {
    e.preventDefault();
    dom.container.classList.add('is-dropping');
  });
  dom.container.addEventListener('dragleave', () => dom.container.classList.remove('is-dropping'));
  dom.container.addEventListener('drop', (e) => {
    e.preventDefault();
    dom.container.classList.remove('is-dropping');
    if (e.dataTransfer?.files?.length) addFiles(e.dataTransfer.files);
  });

  /** Note a new palette or parameter set; the work waits until the tab is on screen. */
  function render(nextPalette, nextParams) {
    palette = nextPalette;
    params = nextParams;
    if (targetId === GENERATED) drawTargetSwatches();
    if (!active) {
      dirty = true;
      return;
    }
    if (dirty) rebuild();
    else refresh();
  }

  /** Show or hide the gallery; hiding stops the animation timer dead. */
  function setActive(on) {
    active = on;
    if (!on) {
      if (timer) clearInterval(timer);
      timer = null;
      return;
    }
    if (dirty) rebuild();
    else { refresh(); restartTimer(); }
  }

  loadServerLibrary();
  loadPaletteLibrary();
  return { render, setActive, addFiles };
}

/** The §19.1 parameters, translated into what `recolorFrames` takes. */
function recolorOptions(params) {
  return {
    mode: params.recolor_mode ?? 'auto',
    indexedMax: params.recolor_indexed_max ?? 256,
    match: params.remap_match ?? 'delta-e',
    preserveOrder: !!params.remap_preserve_order,
    overflow: params.remap_overflow ?? 'share',
    dither: params.quant_dither ?? 'floyd-steinberg',
    ditherStrength: params.quant_dither_strength ?? 1,
    lightnessWeight: params.quant_lightness_weight ?? 1,
    downscaleTo: params.quant_downscale ?? 0,
  };
}

/** GIF files start with "GIF"; anything else goes through the browser's own decoders. */
function isGif(bytes) {
  return bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46;
}

/** Decode a PNG or JPEG through the browser and hand back an RGB Raster. */
function decodeStill(bytes, name) {
  return new Promise((resolvePromise, reject) => {
    const url = URL.createObjectURL(new Blob([bytes]));
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = img.naturalWidth;
      canvas.height = img.naturalHeight;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0);
      const { data } = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const raster = new Raster(canvas.width, canvas.height, null);
      for (let i = 0, p = 0; i < data.length; i += 4, p += 3) {
        raster.data[p] = data[i];
        raster.data[p + 1] = data[i + 1];
        raster.data[p + 2] = data[i + 2];
      }
      URL.revokeObjectURL(url);
      resolvePromise(raster);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error(`could not decode ${name}`));
    };
    img.src = url;
  });
}
