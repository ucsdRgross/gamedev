// The reference images that ship with the tool (PLAN §19.3, ARCHITECTURE §12.4).
//
// **Generated, not committed as binaries.** Every one is a pure function of a fixed seed,
// so the gallery is never empty, the tests always have real data, the standalone build has
// the same set as the served app, and nothing in the repository is an opaque blob.
//
// The set has to cover both recolour paths and the animated case, because those are what
// can be wrong: flat pixel art with hard outlines (indexed), synthetic photographs with
// thousands of colours (quantize), and animations of each kind.

import { makeRng } from '../rng.js';
import { Raster } from '../raster.js';

/** Fixed seeds. Changing one changes that picture and nothing else. */
const SEEDS = { hero: 0x5eed01, tiles: 0x5eed02, portrait: 0x5eed03, landscape: 0x5eed04, torch: 0x5eed05, orb: 0x5eed06 };

/**
 * Every built-in reference image, in gallery order.
 * Each is `{ id, title, kind: 'still' | 'animated', frames: [{ image, delayMs }] }` — one
 * frame for a still, so the gallery and the recolour pipeline have a single shape to handle.
 */
export function builtinSamples() {
  return [
    still('hero', 'Character sprite', hero()),
    still('tiles', 'Tileset strip', tiles()),
    still('portrait', 'Portrait (synthetic photo)', portrait()),
    still('landscape', 'Landscape (synthetic photo)', landscape()),
    animated('torch', 'Torch flicker', torch()),
    animated('orb', 'Orbiting sphere', orb()),
  ];
}

function still(id, title, image) {
  return { id, title, kind: 'still', frames: [{ image, delayMs: 0 }] };
}

function animated(id, title, frames) {
  return { id, title, kind: 'animated', frames };
}

// --- Pixel art (the indexed path) ------------------------------------------

const HERO = {
  skin: [222, 168, 132], skinShade: [178, 121, 96], hair: [72, 44, 38],
  tunic: [58, 104, 148], tunicShade: [38, 70, 106], belt: [96, 64, 40],
  metal: [186, 190, 200], metalShade: [120, 126, 140],
  outline: [26, 22, 32], eye: [30, 40, 60], boot: [70, 52, 44],
};

/** A 32×32 character sprite: flat fills, a hard outline, and a small shading ramp. */
function hero() {
  const bg = [116, 148, 108];
  const img = new Raster(32, 40, bg);
  const put = (x, y, c) => img.set(x, y, c);
  const box = (x, y, w, h, c) => img.rect(x, y, w, h, c);

  box(11, 4, 10, 9, HERO.skin); // head
  box(11, 4, 10, 3, HERO.hair);
  box(18, 4, 3, 9, HERO.skinShade);
  put(13, 9, HERO.eye); put(14, 9, HERO.eye);
  put(17, 9, HERO.eye); put(18, 9, HERO.eye);

  box(9, 13, 14, 13, HERO.tunic); // body
  box(18, 13, 5, 13, HERO.tunicShade);
  box(9, 22, 14, 3, HERO.belt);
  box(6, 14, 3, 9, HERO.skin); // arms
  box(23, 14, 3, 9, HERO.skinShade);
  box(24, 8, 2, 12, HERO.metal); // sword
  box(25, 8, 1, 12, HERO.metalShade);
  box(22, 19, 6, 2, HERO.metal);
  box(11, 26, 4, 10, HERO.tunicShade); // legs
  box(17, 26, 4, 10, HERO.tunicShade);
  box(10, 36, 6, 3, HERO.boot);
  box(16, 36, 6, 3, HERO.boot);

  outlineNonBackground(img, bg, HERO.outline);
  return img;
}

/**
 * Draw a one-pixel outline around every non-background region. This is the feature the
 * indexed path exists to protect — per-pixel matching turns a single-colour outline into
 * several colours, and it is instantly visible.
 */
function outlineNonBackground(img, bg, ink) {
  const solid = [];
  for (let y = 0; y < img.h; y++) {
    for (let x = 0; x < img.w; x++) solid.push(!sameColor(img.get(x, y), bg));
  }
  const at = (x, y) => (x < 0 || y < 0 || x >= img.w || y >= img.h ? false : solid[y * img.w + x]);
  for (let y = 0; y < img.h; y++) {
    for (let x = 0; x < img.w; x++) {
      if (at(x, y)) continue;
      if (at(x - 1, y) || at(x + 1, y) || at(x, y - 1) || at(x, y + 1)) img.set(x, y, ink);
    }
  }
}

function sameColor(a, b) {
  return a[0] === b[0] && a[1] === b[1] && a[2] === b[2];
}

/** A 64×32 tileset strip: grass, stone, water and dirt, each with its own small ramp. */
function tiles() {
  const rng = makeRng(SEEDS.tiles);
  const sets = [
    [[74, 122, 62], [96, 150, 78], [54, 94, 48]], // grass
    [[122, 120, 128], [154, 152, 160], [88, 86, 96]], // stone
    [[48, 96, 152], [72, 132, 190], [32, 68, 116]], // water
    [[132, 100, 68], [160, 128, 90], [98, 72, 48]], // dirt
  ];
  const img = new Raster(64, 32, null);
  for (let t = 0; t < 4; t++) {
    const ramp = sets[t];
    for (let y = 0; y < 32; y++) {
      for (let x = 0; x < 16; x++) {
        // A cheap value-noise speckle, quantised to three levels — the way a hand-drawn
        // tile is textured, and flat enough that the indexed path is clearly the right one.
        const n = rng();
        const shade = n < 0.15 ? 2 : n < 0.4 ? 1 : 0;
        img.set(t * 16 + x, y, ramp[shade]);
      }
    }
    img.outline(t * 16, 0, 16, 32, [26, 22, 32]);
  }
  return img;
}

// --- Synthetic photographs (the quantize path) -----------------------------

/** A 64×72 portrait: a lit head over a soft vignette. Thousands of distinct colours. */
function portrait() {
  const rng = makeRng(SEEDS.portrait);
  const img = new Raster(64, 72, null);
  const cx = 32;
  const cy = 34;
  for (let y = 0; y < 72; y++) {
    for (let x = 0; x < 64; x++) {
      const dx = (x - cx) / 20;
      const dy = (y - cy) / 26;
      const r = Math.sqrt(dx * dx + dy * dy);
      let rgb;
      if (r < 1) {
        // Lambert-ish shading from the upper left, so the face carries a full value ramp.
        const z = Math.sqrt(Math.max(0, 1 - r * r));
        let light = Math.max(0.15, (-dx * 0.5 - dy * 0.6 + z * 0.8) / 1.3);
        light *= featureShading(x, y);
        rgb = [226 * light + 30, 176 * light + 22, 146 * light + 18];
        // A hair mass on top, kept smooth so this stays a photograph rather than pixel art.
        const hair = Math.max(0, 1 - Math.hypot((x - cx) / 20, (y - 10) / 13));
        if (hair > 0.02 && y < 26) rgb = mix(rgb, [58, 40, 36], Math.min(1, hair * 2.5));
      } else {
        const v = Math.max(0, 1 - (r - 1) * 0.6);
        rgb = [40 + 70 * v, 48 + 60 * v, 66 + 70 * v];
      }
      // Film grain: what makes this a photograph rather than a gradient, and what makes
      // dithering worth having.
      const grain = (rng() - 0.5) * 9;
      img.set(x, y, rgb.map((c) => clamp255(c + grain)));
    }
  }
  return img;
}

/**
 * Soft eye sockets, a nose shadow and a mouth line, as multipliers on the lighting rather
 * than as drawn colours — so the face reads as a face while staying a continuous-tone
 * image. Skin is the hardest thing for a generated palette to hold up on, which is why the
 * reference set includes one.
 */
function featureShading(x, y) {
  const blob = (bx, by, rx, ry, depth) => {
    const d = Math.hypot((x - bx) / rx, (y - by) / ry);
    return d < 1 ? 1 - depth * (1 - d) : 1;
  };
  return blob(25, 30, 4.5, 3, 0.45) // left eye
    * blob(39, 30, 4.5, 3, 0.45) // right eye
    * blob(32, 39, 3, 6, 0.18) // nose
    * blob(32, 49, 7, 2.5, 0.32); // mouth
}

/** A 96×64 landscape: sky gradient, sun, haze and layered hills. */
function landscape() {
  const rng = makeRng(SEEDS.landscape);
  const img = new Raster(96, 64, null);
  // Index 0 is the farthest ridge and sits highest; each nearer one starts lower down, so
  // painting them front-to-back leaves all three visible instead of one flat mass.
  const ridges = [0, 1, 2].map((i) => {
    const base = 28 + i * 11;
    const heights = [];
    let v = base;
    for (let x = 0; x < 96; x++) {
      v += (rng() - 0.5) * 2.2;
      v = Math.max(base - 4, Math.min(base + 6, v));
      heights.push(v);
    }
    return heights;
  });

  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 96; x++) {
      const t = y / 63;
      let rgb = [40 + 150 * t, 90 + 120 * t, 180 - 20 * t]; // sky
      const sun = Math.hypot(x - 70, y - 14);
      if (sun < 20) rgb = mix(rgb, [255, 238, 190], Math.max(0, 1 - sun / 20) ** 2);
      // Far to near: each ridge overwrites the ones behind it, and aerial perspective
      // washes the distant ones toward the sky's colour.
      for (let i = 0; i < ridges.length; i++) {
        if (y < ridges[i][x]) continue;
        const near = i / (ridges.length - 1);
        const shade = 0.85 + 0.25 * Math.min(1, (y - ridges[i][x]) / 24);
        const body = mix([104, 132, 128], [30, 54, 40], near);
        rgb = body.map((c) => c * shade);
      }
      const grain = (rng() - 0.5) * 7;
      img.set(x, y, rgb.map((c) => clamp255(c + grain)));
    }
  }
  return img;
}

function mix(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}

function clamp255(v) {
  return Math.max(0, Math.min(255, Math.round(v)));
}

// --- Animations ------------------------------------------------------------

/** An 8-frame torch flicker: flat pixel-art colours, so it exercises indexed + animated. */
function torch() {
  const rng = makeRng(SEEDS.torch);
  const flame = [[252, 232, 150], [246, 176, 62], [214, 92, 40], [140, 46, 34]];
  const wood = [[104, 72, 46], [72, 48, 32]];
  const bg = [22, 20, 30];
  const frames = [];
  for (let f = 0; f < 8; f++) {
    const img = new Raster(24, 32, bg);
    img.rect(10, 20, 4, 12, wood[0]);
    img.rect(12, 20, 2, 12, wood[1]);
    const lean = Math.sin((f / 8) * Math.PI * 2) * 2;
    for (let y = 0; y < 20; y++) {
      const t = y / 19;
      const width = Math.max(1, Math.round(6 * Math.sin(t * Math.PI) + 1 + rng() * 1.5));
      const cx = 12 + lean * (1 - t);
      for (let x = -width; x <= width; x++) {
        const level = Math.min(3, Math.floor((Math.abs(x) / (width + 0.5)) * 3 + t * 1.2));
        img.set(Math.round(cx + x), 20 - y, flame[level]);
      }
    }
    frames.push({ image: img, delayMs: 90 });
  }
  return frames;
}

/** A 12-frame orbiting shaded sphere: smooth colours, so it exercises quantize + animated. */
function orb() {
  const frames = [];
  for (let f = 0; f < 12; f++) {
    const img = new Raster(48, 48, null);
    const a = (f / 12) * Math.PI * 2;
    const bx = 24 + Math.cos(a) * 13;
    const by = 24 + Math.sin(a) * 9;
    for (let y = 0; y < 48; y++) {
      for (let x = 0; x < 48; x++) {
        const bg = [18 + x * 0.8, 22 + y * 0.9, 48 + (x + y) * 0.4];
        const d = Math.hypot(x - bx, y - by) / 9;
        if (d < 1) {
          const z = Math.sqrt(Math.max(0, 1 - d * d));
          const light = Math.max(0.1, (-(x - bx) / 9 * 0.5 - (y - by) / 9 * 0.5 + z) / 1.4);
          img.set(x, y, [clamp255(60 + 195 * light), clamp255(40 + 150 * light ** 1.3), clamp255(90 + 120 * light ** 0.8)]);
        } else {
          img.set(x, y, bg.map(clamp255));
        }
      }
    }
    frames.push({ image: img, delayMs: 80 });
  }
  return frames;
}
