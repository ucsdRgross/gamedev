// The test-visual gallery (PLAN §8). Renders every scene from src/scenes into a canvas,
// filterable by category, with colour-vision views, a zoom control, animation, and
// drag-and-drop photo quantization on the benchmark scene. Scenes are shared with the
// headless renderer unchanged — the gallery just puts their Raster output on screen.

import { SCENES, CATEGORIES } from '../scenes/index.js';
import { applyView, VIEWS } from '../core/analysis.js';
import { Raster } from '../core/raster.js';
import { floydSteinberg, orderedDither } from '../core/dither.js';

const VIEW_LABELS = { color: 'Colour', value: 'Value', protan: 'Protan', deutan: 'Deutan', tritan: 'Tritan' };

/** Paint a Raster onto a canvas at an integer zoom with crisp nearest-neighbour pixels. */
function paint(canvas, raster, zoom) {
  const scaled = zoom > 1 ? raster.scaled(zoom) : raster;
  canvas.width = scaled.w;
  canvas.height = scaled.h;
  const ctx = canvas.getContext('2d');
  ctx.putImageData(scaled.toImageData(ImageData), 0, 0);
}

/** Load a dropped image file into a small full-colour Raster for quantization. */
function imageToRaster(file, maxW = 64) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const scale = Math.min(1, maxW / img.width);
      const w = Math.max(1, Math.round(img.width * scale));
      const h = Math.max(1, Math.round(img.height * scale));
      const c = document.createElement('canvas');
      c.width = w; c.height = h;
      const ctx = c.getContext('2d');
      ctx.drawImage(img, 0, 0, w, h);
      const data = ctx.getImageData(0, 0, w, h).data;
      const r = new Raster(w, h, null);
      for (let i = 0, p = 0; i < data.length; i += 4, p += 3) {
        r.data[p] = data[i]; r.data[p + 1] = data[i + 1]; r.data[p + 2] = data[i + 2];
      }
      URL.revokeObjectURL(img.src);
      resolve(r);
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(file);
  });
}

/** Render a dropped photo as original | Floyd–Steinberg | Bayer onto one raster. */
function customPhotoRaster(source, palette) {
  const pr = palette.entries.map((e) => e.rgb8);
  const fs = floydSteinberg(source, pr);
  const bay = orderedDither(source, pr, { size: 8, strength: 34 });
  const gap = 2;
  const out = new Raster(source.w * 3 + gap * 2, source.h, [20, 20, 26]);
  out.blit(source, 0, 0);
  out.blit(fs, source.w + gap, 0);
  out.blit(bay, source.w * 2 + gap * 2, 0);
  return out;
}

/**
 * Build the gallery. `dom` holds the container and the four control elements. Returns
 * `{ render(palette) }` for the app to call after every regeneration.
 */
export function createGallery(dom, { getPalette }) {
  let palette = null;
  let view = 'color';
  let zoom = 3;
  let animate = true;
  let category = 'All';
  let frame = 0;
  let pending = false;
  const customPhotos = new Map(); // scene id -> dropped source Raster

  // Category filter.
  dom.category.innerHTML = '';
  for (const c of ['All', ...CATEGORIES]) {
    const o = document.createElement('option'); o.value = c; o.textContent = c; dom.category.appendChild(o);
  }
  // View selector.
  dom.view.innerHTML = '';
  for (const v of VIEWS) {
    const o = document.createElement('option'); o.value = v; o.textContent = VIEW_LABELS[v]; dom.view.appendChild(o);
  }

  // Build one card per scene.
  const cards = SCENES.map((scene) => {
    const card = document.createElement('div');
    card.className = 'scene-card';
    card.dataset.category = scene.category;
    const canvas = document.createElement('canvas');
    const title = document.createElement('div');
    title.className = 'scene-title';
    title.textContent = scene.title;
    const cat = document.createElement('div');
    cat.className = 'scene-cat';
    cat.textContent = scene.category + (scene.animated ? ' · anim' : '');
    card.append(canvas, title, cat);
    if (scene.id === 'photo-quant') attachDrop(card, scene, cat);
    dom.container.appendChild(card);
    return { scene, card, canvas };
  });

  /** Wire drag-and-drop image quantization onto the photo benchmark card. */
  function attachDrop(card, scene, cat) {
    const hint = document.createElement('div');
    hint.className = 'scene-drop-hint';
    hint.textContent = 'drop an image →';
    cat.after(hint);
    const stop = (e) => { e.preventDefault(); e.stopPropagation(); };
    card.addEventListener('dragover', (e) => { stop(e); card.classList.add('dragover'); });
    card.addEventListener('dragleave', () => card.classList.remove('dragover'));
    card.addEventListener('drop', async (e) => {
      stop(e); card.classList.remove('dragover');
      const file = e.dataTransfer?.files?.[0];
      if (!file || !file.type.startsWith('image/')) return;
      try {
        customPhotos.set(scene.id, await imageToRaster(file));
        hint.textContent = `${file.name.slice(0, 18)} — drop to replace`;
        drawCard(cards.find((c) => c.scene.id === scene.id));
      } catch { hint.textContent = 'could not load image'; }
    });
  }

  /** Render one card's scene into its canvas with the current view/zoom. */
  function drawCard({ scene, canvas }) {
    if (!palette) return;
    let raster;
    if (scene.id === 'photo-quant' && customPhotos.has(scene.id)) {
      raster = customPhotoRaster(customPhotos.get(scene.id), palette);
    } else {
      raster = new Raster(scene.width, scene.height);
      scene.render(raster, palette, { frame });
    }
    paint(canvas, applyView(raster, view), zoom);
  }

  /** Which cards are visible under the current category filter. */
  function visibleCards() {
    return cards.filter(({ scene, card }) => {
      const show = category === 'All' || scene.category === category;
      card.style.display = show ? '' : 'none';
      return show;
    });
  }

  /** Redraw everything, coalesced to one animation frame. */
  function scheduleRender() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => {
      pending = false;
      for (const c of visibleCards()) drawCard(c);
    });
  }

  // Animation loop: advance the frame and redraw only the animated visible cards.
  setInterval(() => {
    if (!animate || !palette) return;
    const anim = visibleCards().filter(({ scene }) => scene.animated);
    if (anim.length === 0) return;
    frame += 1;
    for (const c of anim) drawCard(c);
  }, 120);

  dom.category.addEventListener('change', () => { category = dom.category.value; scheduleRender(); });
  dom.view.addEventListener('change', () => { view = dom.view.value; scheduleRender(); });
  dom.zoom.addEventListener('change', () => { zoom = Number(dom.zoom.value); scheduleRender(); });
  dom.animate.addEventListener('change', () => { animate = dom.animate.checked; });

  /** Repaint the gallery for a new palette. */
  function render(next) {
    palette = next || getPalette();
    scheduleRender();
  }

  return { render };
}
