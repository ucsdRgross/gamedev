// Sprite scenes 11–19 (PLAN §8). A single procedural humanoid drives most of them, so
// palette-swap, outline modes, and sprite-over-background all test the *same* sprite the
// way a real game would. Colours come from semantic roles and ramps, never raw indices.

import {
  rgb, ramps, shade, rampOfRole, neutrals, accents, anchorDark, anchorLight,
  allEntries, role, bgByDepth,
} from './util.js';

const CAT = 'Sprites';

/** A transparent-aware pixel buffer: cells are `[r,g,b]` or null (transparent). */
class Sprite {
  constructor(w, h) { this.w = w; this.h = h; this.px = new Array(w * h).fill(null); }
  set(x, y, rgb) { if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.px[y * this.w + x] = rgb; }
  get(x, y) { return (x < 0 || y < 0 || x >= this.w || y >= this.h) ? null : this.px[y * this.w + x]; }
  rect(x, y, w, h, rgb) { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.set(x + i, y + j, rgb); }
}

/** Resolve the character's colour set from the palette, with a swappable cloth ramp. */
function heroColors(palette, clothRamp) {
  const skin = rampOfRole(palette, 'skin');
  return {
    skin: rgb(shade(skin, 0.78)),
    skinSh: rgb(shade(skin, 0.5)),
    hair: rgb(shade(rampOfRole(palette, 'wood'), 0.3)),
    cloth: rgb(shade(clothRamp, 0.55)),
    clothSh: rgb(shade(clothRamp, 0.3)),
    clothLi: rgb(shade(clothRamp, 0.82)),
    pants: rgb((neutrals(palette)[0]) || anchorDark(palette)),
    metal: rgb(shade(rampOfRole(palette, 'metal'), 0.72)),
    eye: anchorDark(palette).rgb8,
  };
}

/** Draw a front-facing humanoid filling a w×h sprite; blocky so it reads at 16px. */
function drawHumanoid(sprite, C) {
  const { w, h } = sprite;
  const cx = Math.floor(w / 2);
  const u = (f) => Math.max(1, Math.round(h * f));
  // Head
  const headW = Math.round(w * 0.44);
  const headH = u(0.22);
  const headX = cx - Math.floor(headW / 2);
  const headY = u(0.06);
  sprite.rect(headX, headY, headW, headH, C.skin);
  sprite.rect(headX, headY, headW, Math.max(1, Math.floor(headH * 0.35)), C.hair); // hair cap
  sprite.rect(headX - 1, headY, 1, headH, C.hair);
  sprite.rect(headX + headW, headY, 1, headH, C.hair);
  // Eyes
  const eyeY = headY + Math.floor(headH * 0.55);
  sprite.set(cx - Math.max(1, Math.round(w * 0.09)), eyeY, C.eye);
  sprite.set(cx + Math.max(1, Math.round(w * 0.09)), eyeY, C.eye);
  // Torso
  const torsoW = Math.round(w * 0.5);
  const torsoX = cx - Math.floor(torsoW / 2);
  const torsoY = headY + headH;
  const torsoH = u(0.34);
  sprite.rect(torsoX, torsoY, torsoW, torsoH, C.cloth);
  sprite.rect(torsoX, torsoY, Math.max(1, Math.floor(torsoW * 0.25)), torsoH, C.clothLi); // lit side
  sprite.rect(torsoX + torsoW - Math.max(1, Math.floor(torsoW * 0.25)), torsoY, Math.max(1, Math.floor(torsoW * 0.25)), torsoH, C.clothSh);
  sprite.rect(torsoX, torsoY + torsoH - Math.max(1, Math.round(h * 0.06)), torsoW, Math.max(1, Math.round(h * 0.06)), C.metal); // belt
  // Arms
  const armW = Math.max(1, Math.round(w * 0.12));
  sprite.rect(torsoX - armW, torsoY, armW, Math.floor(torsoH * 0.8), C.cloth);
  sprite.rect(torsoX + torsoW, torsoY, armW, Math.floor(torsoH * 0.8), C.cloth);
  sprite.rect(torsoX - armW, torsoY + Math.floor(torsoH * 0.8), armW, Math.max(1, Math.round(h * 0.08)), C.skin); // hands
  sprite.rect(torsoX + torsoW, torsoY + Math.floor(torsoH * 0.8), armW, Math.max(1, Math.round(h * 0.08)), C.skin);
  // Legs
  const legW = Math.max(1, Math.floor(torsoW / 2) - 1);
  const legY = torsoY + torsoH;
  const legH = h - legY - u(0.04);
  sprite.rect(cx - legW - 1, legY, legW, legH, C.pants);
  sprite.rect(cx + 1, legY, legW, legH, C.pants);
  sprite.rect(cx - legW - 1, legY + legH, legW, Math.max(1, u(0.04)), C.eye); // feet
  sprite.rect(cx + 1, legY + legH, legW, Math.max(1, u(0.04)), C.eye);
}

/** Add an outline to a sprite. mode: 'dark' | 'colored' | 'selective'. */
function outlined(sprite, mode, darkRgb) {
  if (mode === 'none') return sprite;
  const out = new Sprite(sprite.w, sprite.h);
  out.px = sprite.px.slice();
  const darker = (c) => [Math.round(c[0] * 0.45), Math.round(c[1] * 0.45), Math.round(c[2] * 0.5)];
  for (let y = 0; y < sprite.h; y++) {
    for (let x = 0; x < sprite.w; x++) {
      if (sprite.get(x, y)) continue;
      const neigh = [[1, 0], [-1, 0], [0, 1], [0, -1]];
      for (const [dx, dy] of neigh) {
        const n = sprite.get(x - dx, y - dy);
        if (!n) continue;
        if (mode === 'selective' && !(dx === -1 || dy === -1)) continue; // bottom/right only
        out.set(x, y, mode === 'colored' ? darker(n) : darkRgb);
        break;
      }
    }
  }
  return out;
}

/** Blit a sprite's opaque pixels onto the surface. */
function blitSprite(surface, sprite, x, y) {
  for (let sy = 0; sy < sprite.h; sy++) {
    for (let sx = 0; sx < sprite.w; sx++) {
      const c = sprite.get(sx, sy);
      if (c) surface.set(x + sx, y + sy, c);
    }
  }
}

/** Build the hero sprite at a given size using the palette's default cloth ramp. */
function heroSprite(palette, size, clothRamp) {
  const s = new Sprite(size, size);
  drawHumanoid(s, heroColors(palette, clothRamp || rampOfRole(palette, 'foliage')));
  return s;
}

function backdrop(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, rgb(bgByDepth(palette, 0.4)));
}

// --- 11 & 12. 16×16 and 32×32 character -----------------------------------
function renderChar16(surface, palette) {
  backdrop(surface, palette);
  const s = outlined(heroSprite(palette, 16), 'dark', anchorDark(palette).rgb8);
  blitSprite(surface, s, Math.floor((surface.w - 16) / 2), Math.floor((surface.h - 16) / 2));
}
function renderChar32(surface, palette) {
  backdrop(surface, palette);
  const s = outlined(heroSprite(palette, 32), 'dark', anchorDark(palette).rgb8);
  blitSprite(surface, s, Math.floor((surface.w - 32) / 2), Math.floor((surface.h - 32) / 2));
}

// --- 13. Outline modes -----------------------------------------------------
function renderOutlineModes(surface, palette) {
  backdrop(surface, palette);
  const modes = ['none', 'dark', 'colored', 'selective'];
  const cw = Math.floor(surface.w / modes.length);
  modes.forEach((mode, i) => {
    const s = outlined(heroSprite(palette, 16), mode, anchorDark(palette).rgb8);
    blitSprite(surface, s, i * cw + Math.floor((cw - 16) / 2), 8);
    surface.text(mode.slice(0, 4).toUpperCase(), i * cw + 2, surface.h - 7, 1, anchorLight(palette).rgb8);
  });
}

// --- 14. Sprite over every background --------------------------------------
function renderSpriteOverBg(surface, palette) {
  const entries = allEntries(palette);
  const cols = 8;
  const cell = Math.floor(surface.w / cols);
  const sprite = outlined(heroSprite(palette, Math.min(16, cell - 2)), 'dark', anchorDark(palette).rgb8);
  entries.forEach((e, i) => {
    const cx = (i % cols) * cell;
    const cy = Math.floor(i / cols) * cell;
    surface.rect(cx, cy, cell, cell, rgb(e));
    blitSprite(surface, sprite, cx + Math.floor((cell - sprite.w) / 2), cy + Math.floor((cell - sprite.h) / 2));
  });
}

// --- 15. Palette-swap row --------------------------------------------------
function renderPaletteSwap(surface, palette) {
  backdrop(surface, palette);
  const fg = ramps(palette, 'fg');
  const cw = Math.floor(surface.w / Math.max(1, fg.length));
  fg.forEach((ramp, i) => {
    const s = new Sprite(16, 16);
    drawHumanoid(s, heroColors(palette, ramp));
    const o = outlined(s, 'dark', anchorDark(palette).rgb8);
    blitSprite(surface, o, i * cw + Math.floor((cw - 16) / 2), Math.floor((surface.h - 16) / 2));
  });
}

// --- 16. Item icon row -----------------------------------------------------
function renderItems(surface, palette) {
  backdrop(surface, palette);
  const dark = anchorDark(palette).rgb8;
  const metal = rgb(shade(rampOfRole(palette, 'metal'), 0.75));
  const metalHi = anchorLight(palette).rgb8;
  const gold = rgb(role(palette, 'gold'));
  const potion = rgb((accents(palette)[0]) || role(palette, 'ui_bad'));
  const gem = rgb((accents(palette)[1]) || role(palette, 'water'));
  const wood = rgb(shade(rampOfRole(palette, 'wood'), 0.4));
  const cell = Math.floor(surface.w / 5);
  const cy = Math.floor(surface.h / 2);
  const put = (i, drawFn) => drawFn((i * cell) + Math.floor(cell / 2), cy);
  // sword
  put(0, (x, y) => { surface.rect(x - 1, y - 8, 2, 12, metal); surface.set(x, y - 8, metalHi); surface.rect(x - 3, y + 3, 6, 2, wood); surface.rect(x - 1, y + 4, 2, 3, wood); });
  // potion
  put(1, (x, y) => { surface.rect(x - 3, y - 2, 6, 7, potion); surface.rect(x - 2, y - 5, 4, 3, dark); surface.rect(x - 1, y - 7, 2, 2, wood); surface.set(x - 2, y, metalHi); });
  // coin
  put(2, (x, y) => { surface.disc(x, y, 4, gold); surface.outline(x - 4, y - 4, 9, 9, dark); surface.set(x - 1, y - 1, metalHi); });
  // key
  put(3, (x, y) => { surface.rect(x - 4, y - 4, 5, 5, gold); surface.rect(x - 2, y - 2, 1, 1, dark); surface.rect(x + 1, y, 5, 2, gold); surface.rect(x + 4, y + 2, 2, 2, gold); });
  // gem
  put(4, (x, y) => { surface.disc(x, y, 4, gem); surface.rect(x - 1, y - 4, 2, 8, [Math.min(255, gem[0] + 60), Math.min(255, gem[1] + 60), Math.min(255, gem[2] + 60)]); surface.set(x - 1, y - 2, metalHi); });
}

// --- 17. Combat scene ------------------------------------------------------
function renderCombat(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, rgb(bgByDepth(palette, 0.7)));
  surface.rect(0, Math.floor(surface.h * 0.7), surface.w, surface.h, rgb(bgByDepth(palette, 0.2))); // ground
  const player = outlined(heroSprite(palette, 20, rampOfRole(palette, 'foliage')), 'dark', anchorDark(palette).rgb8);
  const enemy = outlined(heroSprite(palette, 20, rampOfRole(palette, 'blood')), 'dark', anchorDark(palette).rgb8);
  const groundY = Math.floor(surface.h * 0.7) - 20;
  blitSprite(surface, player, Math.floor(surface.w * 0.15), groundY);
  blitSprite(surface, enemy, Math.floor(surface.w * 0.6), groundY);
  // pickup (coin) between them
  const gold = rgb(role(palette, 'gold'));
  const mx = Math.floor(surface.w * 0.45);
  const my = groundY + 12;
  surface.disc(mx, my, 3, gold);
  surface.set(mx - 1, my - 1, anchorLight(palette).rgb8);
}

// --- 18. Skin-tone study ---------------------------------------------------
function renderSkin(surface, palette) {
  backdrop(surface, palette);
  const skin = rampOfRole(palette, 'skin');
  const wood = rgb(shade(rampOfRole(palette, 'wood'), 0.4));
  const blood = rgb(shade(rampOfRole(palette, 'blood'), 0.5));
  const eye = anchorDark(palette).rgb8;
  const variants = [
    (c) => c,
    (c) => mix(c, wood, 0.28),
    (c) => mix(c, blood, 0.22),
    (c) => mix(c, [255, 240, 220], 0.25),
    (c) => mix(c, [90, 70, 50], 0.3),
  ];
  const n = variants.length;
  const cw = Math.floor(surface.w / n);
  const r = Math.floor(Math.min(cw, surface.h) / 2) - 4;
  variants.forEach((tint, i) => {
    const cx = i * cw + Math.floor(cw / 2);
    const cy = Math.floor(surface.h / 2);
    const base = tint(rgb(shade(skin, 0.75)));
    const sh = tint(rgb(shade(skin, 0.5)));
    surface.disc(cx, cy, r, base);
    surface.disc(cx + Math.floor(r / 2), cy + Math.floor(r / 3), Math.floor(r / 2), sh); // cheek shadow
    surface.set(cx - Math.floor(r / 3), cy - 1, eye);
    surface.set(cx + Math.floor(r / 3), cy - 1, eye);
    surface.rect(cx - Math.floor(r / 3), cy + Math.floor(r / 2), Math.floor(r * 0.7), 1, eye); // mouth
  });
}

// --- 19. Foliage study -----------------------------------------------------
function renderFoliage(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, rgb(bgByDepth(palette, 0.9))); // sky
  const grassRamp = rampOfRole(palette, 'foliage');
  const groundY = Math.floor(surface.h * 0.72);
  surface.rect(0, groundY, surface.w, surface.h - groundY, rgb(shade(grassRamp, 0.35)));
  // grass blades
  for (let x = 0; x < surface.w; x += 2) {
    surface.set(x, groundY - 1, rgb(shade(grassRamp, 0.5 + ((x * 7) % 5) * 0.06)));
  }
  const wood = rampOfRole(palette, 'wood');
  const trees = [0.2, 0.5, 0.78];
  trees.forEach((tx, k) => {
    const x = Math.floor(surface.w * tx);
    const trunkH = Math.floor(surface.h * (0.2 + k * 0.02));
    surface.rect(x - 1, groundY - trunkH, 3, trunkH, rgb(shade(wood, 0.4)));
    const cr = Math.floor(surface.w * 0.11);
    const cy = groundY - trunkH - Math.floor(cr * 0.6);
    surface.disc(x, cy, cr, rgb(shade(grassRamp, 0.45)));
    surface.disc(x - Math.floor(cr / 2), cy - 1, Math.floor(cr * 0.7), rgb(shade(grassRamp, 0.62))); // lit clump
    surface.disc(x + Math.floor(cr / 2), cy + 2, Math.floor(cr * 0.6), rgb(shade(grassRamp, 0.28))); // shadow clump
  });
}

/** Linear RGB-space mix of two colours (t=0 → a). */
function mix(a, b, t) {
  return [Math.round(a[0] + (b[0] - a[0]) * t), Math.round(a[1] + (b[1] - a[1]) * t), Math.round(a[2] + (b[2] - a[2]) * t)];
}

export const spriteScenes = [
  { id: 'char-16', title: '16×16 character', category: CAT, width: 48, height: 48, render: renderChar16 },
  { id: 'char-32', title: '32×32 character', category: CAT, width: 64, height: 64, render: renderChar32 },
  { id: 'outline-modes', title: 'Outline modes', category: CAT, width: 128, height: 40, render: renderOutlineModes },
  { id: 'sprite-over-bg', title: 'Sprite over every background', category: CAT, width: 128, height: 128, render: renderSpriteOverBg },
  { id: 'palette-swap', title: 'Palette-swap row', category: CAT, width: 160, height: 32, render: renderPaletteSwap },
  { id: 'items', title: 'Item icon row', category: CAT, width: 120, height: 32, render: renderItems },
  { id: 'combat', title: 'Combat scene', category: CAT, width: 128, height: 80, render: renderCombat },
  { id: 'skin', title: 'Skin-tone study', category: CAT, width: 160, height: 44, render: renderSkin },
  { id: 'foliage', title: 'Foliage study', category: CAT, width: 128, height: 80, render: renderFoliage },
];
