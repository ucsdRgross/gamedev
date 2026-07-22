// World scenes 20–24 (PLAN §8): parallax landscape, dungeon interior, day/dusk/night
// sweep, tileset seams, and a full fake screenshot that puts everything together.

import {
  rgb, shade, rampOfRole, bgByDepth, neutrals, accents,
  anchorDark, anchorLight, role,
} from './util.js';

const CAT = 'Scenes';

/** Cheap deterministic value noise in [0,1) for tile texture and stars. */
function hash(x, y) {
  let n = (x * 374761393 + y * 668265263) ^ 0x5bd1e995;
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}

function mix(a, b, t) {
  return [Math.round(a[0] + (b[0] - a[0]) * t), Math.round(a[1] + (b[1] - a[1]) * t), Math.round(a[2] + (b[2] - a[2]) * t)];
}

// --- 20. Parallax landscape ------------------------------------------------
function renderParallax(surface, palette) {
  // Sky gradient from the lightest backgrounds down.
  for (let y = 0; y < surface.h; y++) {
    const t = y / surface.h;
    surface.rect(0, y, surface.w, 1, rgb(bgByDepth(palette, 1 - t * 0.5)));
  }
  const haze = rgb(role(palette, 'sky'));
  // Three depth layers of hills, each hazier and lighter with distance.
  const layers = [
    { base: 0.75, amp: 0.10, y: 0.5, hazeT: 0.55 },
    { base: 0.45, amp: 0.14, y: 0.66, hazeT: 0.3 },
    { base: 0.18, amp: 0.2, y: 0.82, hazeT: 0.0 },
  ];
  for (const L of layers) {
    let col = rgb(shade(rampOfRole(palette, 'foliage'), L.base));
    col = mix(col, haze, L.hazeT);
    for (let x = 0; x < surface.w; x++) {
      const hy = Math.floor(surface.h * L.y - Math.sin(x * 0.08 + L.y * 10) * surface.h * L.amp);
      surface.rect(x, hy, 1, surface.h - hy, col);
    }
  }
}

// --- 21. Dungeon interior --------------------------------------------------
function renderDungeon(surface, palette) {
  const cool = mix(bgByDepth(palette, 0.1).rgb8, role(palette, 'water').rgb8, 0.4);
  surface.rect(0, 0, surface.w, surface.h, cool);
  // Stone wall blocks
  const stone = rampOfRole(palette, 'stone');
  for (let by = 0; by < surface.h; by += 10) {
    for (let bx = ((by / 10) % 2) * 8; bx < surface.w; bx += 16) {
      surface.rect(bx, by, 15, 9, rgb(shade(stone, 0.25 + hash(bx, by) * 0.15)));
      surface.outline(bx, by, 15, 9, rgb(shade(stone, 0.12)));
    }
  }
  // Torch with warm radial light.
  const fire = rgb(role(palette, 'fire'));
  const tx = Math.floor(surface.w * 0.3);
  const ty = Math.floor(surface.h * 0.35);
  for (let y = 0; y < surface.h; y++) {
    for (let x = 0; x < surface.w; x++) {
      const d = Math.hypot(x - tx, y - ty) / (surface.w * 0.5);
      if (d < 1) {
        const t = (1 - d) * 0.5;
        const base = surface.get(x, y);
        surface.set(x, y, mix(base, fire, t));
      }
    }
  }
  surface.rect(tx - 1, ty, 2, 6, rgb(shade(rampOfRole(palette, 'wood'), 0.4)));
  surface.disc(tx, ty - 1, 2, fire);
  surface.set(tx, ty - 2, rgb(role(palette, 'gold')));
}

// --- 22. Day / dusk / night sweep -----------------------------------------
function renderDayNight(surface, palette) {
  const cols = 3;
  const cw = Math.floor(surface.w / cols);
  const states = [
    { name: 'DAY', skyT: 0.95, sun: rgb(role(palette, 'gold')), tint: null, tintT: 0 },
    { name: 'DUSK', skyT: 0.6, sun: rgb(role(palette, 'fire')), tint: rgb(role(palette, 'fire')), tintT: 0.3 },
    { name: 'NIGHT', skyT: 0.15, sun: rgb(role(palette, 'sky')), tint: rgb(anchorDark(palette)), tintT: 0.45 },
  ];
  states.forEach((st, i) => {
    const x0 = i * cw;
    for (let y = 0; y < surface.h; y++) {
      let c = rgb(bgByDepth(palette, st.skyT * (1 - y / surface.h * 0.4)));
      if (st.tint) c = mix(c, st.tint, st.tintT);
      surface.rect(x0, y, cw, 1, c);
    }
    // sun / moon
    surface.disc(x0 + Math.floor(cw * 0.7), Math.floor(surface.h * 0.25), 3, st.sun);
    // ground + hill
    const gy = Math.floor(surface.h * 0.68);
    let ground = rgb(shade(rampOfRole(palette, 'foliage'), 0.35));
    if (st.tint) ground = mix(ground, st.tint, st.tintT * 0.7);
    surface.rect(x0, gy, cw, surface.h - gy, ground);
    surface.text(st.name, x0 + 2, surface.h - 7, 1, anchorLight(palette).rgb8);
    if (i > 0) surface.rect(x0, 0, 1, surface.h, anchorDark(palette).rgb8);
  });
}

// --- 23. Tileset sheet -----------------------------------------------------
function renderTileset(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, rgb(anchorDark(palette)));
  const tiles = [
    { name: 'grass', ramp: rampOfRole(palette, 'foliage'), base: 0.4, spec: 0.18 },
    { name: 'dirt', ramp: rampOfRole(palette, 'wood'), base: 0.4, spec: 0.15 },
    { name: 'stone', ramp: rampOfRole(palette, 'stone'), base: 0.4, spec: 0.12 },
    { name: 'water', ramp: rampOfRole(palette, 'water'), base: 0.45, spec: 0.2 },
  ];
  const T = 16;
  const reps = 2; // tile 2×2 to reveal seams
  const cw = T * reps + 4;
  tiles.forEach((tile, i) => {
    const ox = i * cw + 2;
    const oy = 2;
    for (let ry = 0; ry < reps; ry++) {
      for (let rx = 0; rx < reps; rx++) {
        for (let y = 0; y < T; y++) {
          for (let x = 0; x < T; x++) {
            const n = hash(x + rx * 999, y + ry * 999);
            const t = tile.base + (n - 0.5) * tile.spec;
            surface.set(ox + rx * T + x, oy + ry * T + y, rgb(shade(tile.ramp, t)));
          }
        }
      }
    }
    surface.text(tile.name.toUpperCase().slice(0, 5), ox, oy + T * reps + 1, 1, anchorLight(palette).rgb8);
  });
}

// --- 24. Full fake screenshot ----------------------------------------------
function renderScreenshot(surface, palette) {
  // Sky
  for (let y = 0; y < surface.h; y++) surface.rect(0, y, surface.w, 1, rgb(bgByDepth(palette, 0.95 - y / surface.h * 0.5)));
  // Parallax hills
  const foliage = rampOfRole(palette, 'foliage');
  for (let x = 0; x < surface.w; x++) {
    const hy = Math.floor(surface.h * 0.55 - Math.sin(x * 0.06) * 6);
    surface.rect(x, hy, 1, surface.h - hy, mix(rgb(shade(foliage, 0.4)), rgb(role(palette, 'sky')), 0.35));
  }
  // Ground
  const gy = Math.floor(surface.h * 0.72);
  surface.rect(0, gy, surface.w, surface.h - gy, rgb(shade(foliage, 0.3)));
  // A tree
  const wood = rampOfRole(palette, 'wood');
  surface.rect(Math.floor(surface.w * 0.75), gy - 14, 3, 14, rgb(shade(wood, 0.4)));
  surface.disc(Math.floor(surface.w * 0.75) + 1, gy - 16, 7, rgb(shade(foliage, 0.5)));
  // Player (blocky)
  const px = Math.floor(surface.w * 0.25);
  const cloth = rampOfRole(palette, 'blood');
  surface.rect(px, gy - 12, 6, 7, rgb(shade(cloth, 0.55)));
  surface.rect(px + 1, gy - 17, 4, 5, rgb(shade(rampOfRole(palette, 'skin'), 0.75)));
  surface.rect(px, gy - 5, 2, 5, anchorDark(palette).rgb8);
  surface.rect(px + 4, gy - 5, 2, 5, anchorDark(palette).rgb8);
  surface.outline(px - 1, gy - 18, 8, 18, anchorDark(palette).rgb8);
  // HUD: health bar + coin count
  surface.rect(2, 2, surface.w - 4, 7, mix(rgb(anchorDark(palette)), rgb(neutrals(palette)[0] || anchorDark(palette)), 0.5));
  surface.outline(2, 2, surface.w - 4, 7, anchorLight(palette).rgb8);
  const hp = rgb((accents(palette)[0]) || role(palette, 'ui_bad'));
  surface.rect(4, 4, Math.floor((surface.w - 8) * 0.6), 3, hp);
  surface.disc(surface.w - 8, 5, 2, rgb(role(palette, 'gold')));
}

export const worldScenes = [
  { id: 'parallax', title: 'Parallax landscape', category: CAT, width: 160, height: 96, render: renderParallax },
  { id: 'dungeon', title: 'Dungeon interior', category: CAT, width: 128, height: 96, render: renderDungeon },
  { id: 'day-night', title: 'Day / dusk / night', category: CAT, width: 180, height: 72, render: renderDayNight },
  { id: 'tileset', title: 'Tileset sheet', category: CAT, width: 160, height: 44, render: renderTileset },
  { id: 'screenshot', title: 'Full screenshot', category: CAT, width: 160, height: 112, render: renderScreenshot },
];
