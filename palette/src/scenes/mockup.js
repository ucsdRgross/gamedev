// Composed screen mockups (UX_PLAN U4.2, IMPROVEMENTS item 18).
//
// Every other scene tests one thing — a ramp, a sprite, a UI panel. That is what makes them
// good tests and bad *previews*: a palette can pass all thirty-four and still fall apart the
// moment a HUD sits on top of a tilemap with a character between them, because the question
// nobody asked was "do these three colours separate when they are ten pixels apart".
//
// So these two are deliberately crowded, and deliberately big — 256×192 is a real low-res
// game screen (a quarter of 1024×768, the size a 4× window lands on), not a test card. One is
// the world screen (tilemap, character, HUD, dialogue, inventory), the other the menu screen
// (portrait, stats, item grid, tabs). Between them every layer of the palette has to work at
// once and next to everything else.
//
// Text appears at three scales in both. 3× headings are where a palette's contrast looks
// fine; 1× body text at the size pixel art actually labels things is where it does not.

import {
  rgb, shade, rampOfRole, bgByDepth, neutrals, accents,
  anchorDark, anchorLight, role,
} from './util.js';

const CAT = 'Mockup';
const W = 256;
const H = 192;

/** Deterministic value noise in [0,1) — tile texture must not change between renders. */
function hash(x, y) {
  let n = (x * 374761393 + y * 668265263) ^ 0x5bd1e995;
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}

function mix(a, b, t) {
  return [
    Math.round(a[0] + (b[0] - a[0]) * t),
    Math.round(a[1] + (b[1] - a[1]) * t),
    Math.round(a[2] + (b[2] - a[2]) * t),
  ];
}

/** A neutral by 0..1 lightness, falling back to the anchors when there are no neutrals. */
function neutralShade(palette, t) {
  const n = neutrals(palette);
  if (n.length === 0) return mix(anchorDark(palette).rgb8, anchorLight(palette).rgb8, t);
  return rgb(n[Math.max(0, Math.min(n.length - 1, Math.round(t * (n.length - 1))))]);
}

/** A panel: filled body, bright top-left bevel, dark bottom-right — the standard UI read. */
function panel(surface, x, y, w, h, palette, { fill = 0.3, alpha = 1 } = {}) {
  const body = neutralShade(palette, fill);
  if (alpha >= 1) {
    surface.rect(x, y, w, h, body);
  } else {
    // A translucent panel is what a HUD over a tilemap really is; blending against whatever
    // is underneath is the only way to see whether the palette survives being layered.
    for (let py = y; py < y + h; py++) {
      for (let px = x; px < x + w; px++) surface.set(px, py, mix(surface.get(px, py), body, alpha));
    }
  }
  surface.rect(x, y, w, 1, neutralShade(palette, fill + 0.28));
  surface.rect(x, y, 1, h, neutralShade(palette, fill + 0.28));
  surface.rect(x, y + h - 1, w, 1, anchorDark(palette).rgb8);
  surface.rect(x + w - 1, y, 1, h, anchorDark(palette).rgb8);
}

// --- 35. World screen ------------------------------------------------------

/**
 * The terrain kind of a 16×16 tile — a cliff, a pond, a path, and grass everywhere else.
 *
 * The layout is built around what the panels cover: the HUD takes the top-left, the minimap
 * the top-right, and the dialogue and bag the bottom third, which leaves rows 4–8 as the only
 * band of world anyone actually sees. Everything that has to be legible lives there.
 */
function terrainAt(tx, ty) {
  if (ty <= 1) return 'cliff';
  if (isWater(tx, ty)) return 'water';
  if (ty === 7 || (tx === 11 && ty > 7)) return 'path';
  return 'grass';
}

const TILE = 16;

/**
 * The pond, tested in fractional tile coordinates.
 *
 * Deliberately *not* quantised to the tile grid: at tile resolution this ellipse comes out as
 * a hard plus-shape that reads as a rendering bug rather than as water, and the shoreline —
 * the edge where the palette has to hold two terrains apart — is where the interesting
 * question is. The rest of the map stays on the grid, so the seams are still on show.
 */
function isWater(tx, ty) {
  return (tx - 3.4) ** 2 * 0.6 + (ty - 5.3) ** 2 * 2 <= 4;
}

/**
 * A terrain colour at ramp position `t`.
 *
 * Water needs the tint. `rampOfRole` hands back the hue-*nearest foreground* ramp, and on the
 * default palette the water role is an accent with no ramp of its own — so the pond came out
 * drawn in the foliage ramp, pixel-identical to the grass around it. Shading structure comes
 * from the ramp; the hue comes from the role, which is the colour the palette actually
 * nominates for water. When a palette has no blue the pond still goes green, as it should.
 */
function terrainColor(palette, kind, ramp, t) {
  const base = rgb(shade(ramp, t));
  return kind === 'water' ? mix(base, rgb(role(palette, 'water')), 0.72) : base;
}

/** Draw the tilemap: textured 16×16 tiles with a lit top edge wherever the terrain changes. */
function drawTilemap(surface, palette) {
  const ramps = {
    grass: rampOfRole(palette, 'foliage'),
    path: rampOfRole(palette, 'wood'),
    cliff: rampOfRole(palette, 'stone'),
    water: rampOfRole(palette, 'water'),
  };
  const base = { grass: 0.42, path: 0.5, cliff: 0.34, water: 0.45 };
  const grain = { grass: 0.22, path: 0.14, cliff: 0.2, water: 0.12 };
  for (let ty = 0; ty < H / TILE; ty++) {
    for (let tx = 0; tx < W / TILE; tx++) {
      const tileKind = terrainAt(tx, ty);
      for (let y = 0; y < TILE; y++) {
        for (let x = 0; x < TILE; x++) {
          const px = tx * TILE + x;
          const py = ty * TILE + y;
          // Water is decided per pixel; everything else follows its tile.
          const wet = isWater((px + 0.5) / TILE, (py + 0.5) / TILE);
          const kind = wet ? 'water' : (tileKind === 'water' ? 'grass' : tileKind);
          const ramp = ramps[kind];
          const n = hash(px, py);
          let t = base[kind] + (n - 0.5) * grain[kind];
          // Water reads as water because of its bands, not its hue — a palette whose water
          // ramp has no steps left to band with is a thing worth seeing here.
          if (wet) {
            t += Math.sin(py * 0.7) * 0.14;
            // Shoreline: the shallows are a step lighter, which is the pair of colours a
            // palette most often fails to separate.
            const shore = !isWater((px + 2.5) / TILE, (py + 0.5) / TILE)
              || !isWater((px - 1.5) / TILE, (py + 0.5) / TILE)
              || !isWater((px + 0.5) / TILE, (py + 2.5) / TILE)
              || !isWater((px + 0.5) / TILE, (py - 1.5) / TILE);
            if (shore) t += 0.3;
          }
          surface.set(px, py, terrainColor(palette, kind, ramp, t));
        }
      }
      // Lit lip on the top edge of any tile whose neighbour above is different terrain.
      if (ty > 0 && tileKind !== 'water' && terrainAt(tx, ty - 1) !== tileKind) {
        surface.rect(tx * TILE, ty * TILE, TILE, 2,
          terrainColor(palette, tileKind, ramps[tileKind], base[tileKind] + 0.3));
      }
      // Tufts: two-pixel marks well up the grass ramp. Per-pixel grain says nothing about a
      // ramp — a shape drawn a whole step lighter is what shows whether the steps separate.
      if (tileKind === 'grass') {
        const light = rgb(shade(ramps.grass, 0.72));
        for (let i = 0; i < 3; i++) {
          const gx = tx * TILE + Math.floor(hash(tx * 31 + i, ty * 17) * (TILE - 3));
          const gy = ty * TILE + Math.floor(hash(tx * 13, ty * 29 + i) * (TILE - 3));
          if (isWater((gx + 0.5) / TILE, (gy + 0.5) / TILE)) continue; // no grass in the pond
          surface.rect(gx, gy + 1, 1, 2, light);
          surface.set(gx + 1, gy, light);
        }
      }
    }
  }
}

/**
 * A 16×24 character with a shadow, a full keyline and a three-step cloth ramp.
 *
 * The keyline is drawn as a dark plate under every limb rather than as a rectangle around the
 * torso: the first version outlined the body only, and the arms and the sword — the parts that
 * stick out and give a sprite its silhouette — were left touching the grass with nothing
 * between them, which is exactly where a low-contrast palette turns a character into a blob.
 */
function drawCharacter(surface, palette, x, y) {
  const dark = anchorDark(palette).rgb8;
  const skin = rampOfRole(palette, 'skin');
  const cloth = rampOfRole(palette, 'blood');
  const metal = rampOfRole(palette, 'metal');
  const hair = rampOfRole(palette, 'wood');

  // Contact shadow — the cheapest test of whether the darkest colours separate from ground.
  for (let dx = -7; dx <= 7; dx++) {
    for (let dy = -2; dy <= 2; dy++) {
      if ((dx / 7) ** 2 + (dy / 2) ** 2 <= 1) {
        surface.set(x + 8 + dx, y + 23 + dy, mix(surface.get(x + 8 + dx, y + 23 + dy), dark, 0.45));
      }
    }
  }
  // Keyline plates: every part, inflated by one pixel, in the darkest colour.
  for (const [px, py, pw, ph] of [
    [3, 0, 10, 9], // head
    [2, 7, 12, 11], // torso
    [0, 8, 4, 8], [12, 8, 4, 8], // arms
    [3, 16, 11, 9], // legs + boots
    [14, 2, 4, 15], [13, 13, 6, 4], // sword and crossguard
  ]) {
    surface.rect(x + px - 1, y + py - 1, pw + 2, ph + 2, dark);
  }
  surface.rect(x + 4, y + 1, 8, 7, rgb(shade(skin, 0.78))); // head
  surface.rect(x + 10, y + 1, 2, 7, rgb(shade(skin, 0.55))); // shaded side
  surface.rect(x + 4, y, 8, 3, rgb(shade(hair, 0.45)));
  surface.rect(x + 5, y + 4, 2, 2, dark); // eyes
  surface.rect(x + 9, y + 4, 2, 2, dark);
  surface.rect(x + 3, y + 8, 10, 9, rgb(shade(cloth, 0.55))); // torso
  surface.rect(x + 10, y + 8, 3, 9, rgb(shade(cloth, 0.32)));
  surface.rect(x + 3, y + 14, 10, 2, rgb(shade(hair, 0.3))); // belt
  surface.rect(x + 1, y + 9, 2, 6, rgb(shade(skin, 0.68))); // arms
  surface.rect(x + 13, y + 9, 2, 6, rgb(shade(skin, 0.5)));
  surface.rect(x + 15, y + 3, 2, 13, rgb(shade(metal, 0.8))); // sword
  surface.rect(x + 16, y + 3, 1, 13, rgb(shade(metal, 0.5)));
  surface.rect(x + 14, y + 14, 4, 2, rgb(role(palette, 'gold')));
  surface.rect(x + 4, y + 17, 3, 6, rgb(shade(cloth, 0.35))); // legs
  surface.rect(x + 9, y + 17, 3, 6, rgb(shade(cloth, 0.35)));
  surface.rect(x + 3, y + 21, 4, 2, rgb(shade(hair, 0.25))); // boots
  surface.rect(x + 9, y + 21, 4, 2, rgb(shade(hair, 0.25)));
}

/**
 * A tree: trunk from the wood ramp, three-step canopy from foliage, outlined.
 *
 * The outline is not decoration. Without it the canopy is foliage-on-grass — the same ramp at
 * neighbouring steps — and on a palette with a short green run the whole tree disappears into
 * the ground. Pixel art solves that with a dark keyline, and so does this.
 */
function drawTree(surface, palette, x, y) {
  const wood = rampOfRole(palette, 'wood');
  const leaf = rampOfRole(palette, 'foliage');
  const dark = anchorDark(palette).rgb8;
  surface.disc(x, y - 20, 12, dark);
  surface.disc(x - 3, y - 23, 8, dark);
  surface.rect(x - 3, y - 13, 7, 13, dark);
  surface.rect(x - 2, y - 12, 5, 12, rgb(shade(wood, 0.38)));
  surface.rect(x + 1, y - 12, 2, 12, rgb(shade(wood, 0.2)));
  surface.disc(x, y - 20, 11, rgb(shade(leaf, 0.5)));
  surface.disc(x - 3, y - 23, 7, rgb(shade(leaf, 0.78)));
  surface.disc(x + 5, y - 16, 5, rgb(shade(leaf, 0.24)));
}

/** The health/mana HUD, the coin readout and the minimap. */
function drawHud(surface, palette) {
  const light = anchorLight(palette).rgb8;
  const dark = anchorDark(palette).rgb8;
  const hp = rgb(accents(palette)[0] || role(palette, 'ui_bad'));
  const mp = rgb(accents(palette)[1] || role(palette, 'water'));

  panel(surface, 4, 4, 116, 30, palette, { fill: 0.22, alpha: 0.86 });
  surface.text('LV 12', 8, 8, 1, light);
  // Hearts: a discrete gauge, where two nearly-equal accents show up as an unreadable row.
  for (let i = 0; i < 5; i++) {
    const hx = 8 + i * 10;
    const full = i < 3;
    const c = full ? hp : mix(hp, dark, 0.72);
    surface.rect(hx, 16, 7, 5, c);
    surface.rect(hx + 1, 15, 2, 1, c);
    surface.rect(hx + 4, 15, 2, 1, c);
    surface.rect(hx + 2, 21, 3, 1, c);
    if (full) surface.rect(hx + 1, 16, 2, 2, mix(c, light, 0.45)); // specular
  }
  surface.rect(8, 25, 104, 5, dark); // mana bar
  surface.rect(9, 26, 62, 3, mp);
  surface.text('MP', 92, 8, 1, mix(light, mp, 0.5));

  // Coins, top centre-left of the map panel.
  surface.disc(128, 12, 5, rgb(role(palette, 'gold')));
  surface.disc(127, 11, 3, mix(rgb(role(palette, 'gold')), light, 0.5));
  surface.text('X 248', 136, 9, 1, light);

  // Minimap: a coarse rendering of the same terrain, four pixels per tile.
  const mx = W - 72;
  const my = 4;
  panel(surface, mx, my, 68, 56, palette, { fill: 0.16, alpha: 0.9 });
  // A minimap is four pixels per tile with no room for texture, so the terrains are told
  // apart by ramp *step* as much as by hue — which is exactly the check worth making.
  const miniRamp = {
    grass: [rampOfRole(palette, 'foliage'), 0.55],
    water: [rampOfRole(palette, 'water'), 0.3],
    cliff: [rampOfRole(palette, 'stone'), 0.75],
    path: [rampOfRole(palette, 'wood'), 0.62],
  };
  for (let ty = 0; ty < 12; ty++) {
    for (let tx = 0; tx < 16; tx++) {
      const kind = terrainAt(tx, ty);
      const [ramp, t] = miniRamp[kind];
      surface.rect(mx + 2 + tx * 4, my + 2 + ty * 4, 4, 4, terrainColor(palette, kind, ramp, t));
    }
  }
  surface.rect(mx + 2 + 7 * 4, my + 2 + 7 * 4, 4, 4, hp); // player blip
  surface.outline(mx + 1, my + 1, 66, 54, dark);
}

/** The dialogue box — the three text scales, over a panel, over the world. */
function drawDialogue(surface, palette) {
  const light = anchorLight(palette).rgb8;
  const x = 4;
  const y = H - 60;
  panel(surface, x, y, 150, 56, palette, { fill: 0.18, alpha: 0.94 });
  surface.text('QUEST', x + 6, y + 5, 3, rgb(role(palette, 'gold')));
  surface.text('FIND THE OLD KEY', x + 6, y + 24, 2, mix(light, rgb(role(palette, 'gold')), 0.25));
  surface.text('IT IS SAID THE MILLER BURIED', x + 6, y + 38, 1, light);
  surface.text('IT UNDER THE THIRD STONE.', x + 6, y + 46, 1, mix(light, neutralShade(palette, 0.5), 0.5));
}

/** The inventory: a 5×2 slot grid with icons and one selected slot. */
function drawInventory(surface, palette) {
  const dark = anchorDark(palette).rgb8;
  const gold = rgb(role(palette, 'gold'));
  const x = 160;
  const y = H - 60;
  panel(surface, x, y, 92, 56, palette, { fill: 0.2, alpha: 0.94 });
  surface.text('BAG', x + 5, y + 4, 1, mix(anchorLight(palette).rgb8, gold, 0.4));
  for (let r = 0; r < 2; r++) {
    for (let c = 0; c < 5; c++) {
      const sx = x + 4 + c * 17;
      const sy = y + 13 + r * 20;
      surface.rect(sx, sy, 16, 18, neutralShade(palette, 0.1));
      surface.outline(sx, sy, 16, 18, neutralShade(palette, 0.42));
      const i = r * 5 + c;
      if (i === 2) { // potion
        surface.rect(sx + 5, sy + 4, 6, 10, rgb(role(palette, 'ui_bad')));
        surface.rect(sx + 6, sy + 2, 4, 3, neutralShade(palette, 0.6));
      } else if (i === 0) { // sword
        const metal = rampOfRole(palette, 'metal');
        surface.rect(sx + 7, sy + 2, 2, 11, rgb(shade(metal, 0.85)));
        surface.rect(sx + 5, sy + 12, 6, 2, rgb(shade(metal, 0.4)));
      } else if (i === 4) { // herb
        surface.disc(sx + 8, sy + 9, 4, rgb(shade(rampOfRole(palette, 'foliage'), 0.6)));
      } else if (i === 6) { // coin stack
        surface.rect(sx + 4, sy + 10, 9, 3, gold);
        surface.rect(sx + 5, sy + 6, 7, 3, mix(gold, dark, 0.25));
      } else if (i === 7) { // scroll
        surface.rect(sx + 4, sy + 4, 9, 11, rgb(shade(rampOfRole(palette, 'skin'), 0.85)));
        surface.rect(sx + 5, sy + 7, 7, 1, dark);
        surface.rect(sx + 5, sy + 10, 5, 1, dark);
      }
      if (i === 2) surface.outline(sx - 1, sy - 1, 18, 20, gold); // selection
    }
  }
}

function renderWorldScreen(surface, palette) {
  drawTilemap(surface, palette);
  drawTree(surface, palette, 226, 124);
  drawTree(surface, palette, 62, 74);
  // A chest by the path, so gold has something to sit on other than the HUD.
  const wood = rampOfRole(palette, 'wood');
  surface.rect(150, 96, 18, 13, rgb(shade(wood, 0.42)));
  surface.rect(150, 96, 18, 4, rgb(shade(wood, 0.6)));
  surface.rect(157, 100, 4, 5, rgb(role(palette, 'gold')));
  surface.outline(150, 96, 18, 13, anchorDark(palette).rgb8);
  // Flowers: two small accents dropped on the grass. A palette whose accents only work on a
  // panel — and disappear the moment they are four pixels on foliage — shows it here.
  const bloom = [rgb(accents(palette)[0] || role(palette, 'ui_bad')), rgb(role(palette, 'gold'))];
  for (let i = 0; i < 7; i++) {
    const fx = 20 + Math.floor(hash(i, 3) * 200);
    const fy = 96 + Math.floor(hash(i, 11) * 28);
    if (terrainAt(Math.floor(fx / TILE), Math.floor(fy / TILE)) !== 'grass') continue;
    surface.rect(fx, fy, 2, 2, bloom[i % 2]);
  }
  drawCharacter(surface, palette, 112, 88);
  drawHud(surface, palette);
  drawDialogue(surface, palette);
  drawInventory(surface, palette);
}

// --- 36. Menu screen -------------------------------------------------------

/** A 40×48 portrait bust — face, hair, collar — for the character panel. */
function drawPortrait(surface, palette, x, y) {
  const skin = rampOfRole(palette, 'skin');
  const hair = rampOfRole(palette, 'wood');
  const cloth = rampOfRole(palette, 'blood');
  const dark = anchorDark(palette).rgb8;
  surface.rect(x, y, 40, 48, mix(bgByDepth(palette, 0.5).rgb8, dark, 0.35));
  surface.rect(x + 4, y + 34, 32, 14, rgb(shade(cloth, 0.45))); // shoulders
  surface.rect(x + 22, y + 34, 14, 14, rgb(shade(cloth, 0.28)));
  surface.rect(x + 10, y + 8, 20, 28, rgb(shade(skin, 0.8))); // face
  surface.rect(x + 24, y + 8, 6, 28, rgb(shade(skin, 0.58))); // shaded cheek
  surface.rect(x + 8, y + 4, 24, 9, rgb(shade(hair, 0.42))); // hair
  surface.rect(x + 8, y + 4, 24, 3, rgb(shade(hair, 0.62)));
  surface.rect(x + 8, y + 10, 3, 16, rgb(shade(hair, 0.32)));
  surface.rect(x + 29, y + 10, 3, 16, rgb(shade(hair, 0.32)));
  surface.rect(x + 14, y + 17, 3, 3, dark); // eyes
  surface.rect(x + 23, y + 17, 3, 3, dark);
  surface.rect(x + 16, y + 28, 8, 1, mix(rgb(shade(skin, 0.4)), dark, 0.4)); // mouth
  surface.outline(x, y, 40, 48, neutralShade(palette, 0.5));
}

/** A labelled bar — the stat readout, and the place two similar accents get caught. */
function drawStat(surface, palette, x, y, w, label, t, color) {
  const light = anchorLight(palette).rgb8;
  surface.text(label, x, y, 1, mix(light, neutralShade(palette, 0.55), 0.45));
  surface.rect(x + 26, y - 1, w, 7, anchorDark(palette).rgb8);
  surface.rect(x + 27, y, Math.max(1, Math.round((w - 2) * t)), 5, color);
  surface.rect(x + 27, y, Math.max(1, Math.round((w - 2) * t)), 1, mix(color, light, 0.35));
}

function renderMenuScreen(surface, palette) {
  const light = anchorLight(palette).rgb8;
  const dark = anchorDark(palette).rgb8;
  const gold = rgb(role(palette, 'gold'));

  // Backdrop: the world, dimmed — a menu is nearly always drawn over something.
  for (let y = 0; y < H; y++) {
    const band = mix(bgByDepth(palette, 0.9 - (y / H) * 0.6).rgb8, dark, 0.55);
    surface.rect(0, y, W, 1, band);
  }
  for (let i = 0; i < 90; i++) {
    const sx = Math.floor(hash(i, 7) * W);
    const sy = Math.floor(hash(i, 19) * H);
    surface.set(sx, sy, mix(surface.get(sx, sy), light, 0.35));
  }

  // Tabs.
  const tabs = ['ITEMS', 'GEAR', 'MAGIC', 'MAP'];
  tabs.forEach((name, i) => {
    const tx = 6 + i * 44;
    const on = i === 0;
    panel(surface, tx, 4, 42, 14, palette, { fill: on ? 0.42 : 0.16 });
    surface.text(name, tx + 4, 8, 1, on ? gold : mix(light, dark, 0.45));
  });

  // Left column: portrait, name at 2×, stats.
  panel(surface, 6, 22, 96, 108, palette, { fill: 0.2 });
  drawPortrait(surface, palette, 12, 28);
  surface.text('ROWAN', 58, 30, 2, light);
  surface.text('KNIGHT', 58, 44, 1, mix(light, gold, 0.4));
  surface.text('LV 12', 58, 52, 1, mix(light, neutralShade(palette, 0.5), 0.5));
  drawStat(surface, palette, 12, 84, 82, 'HP', 0.72, rgb(accents(palette)[0] || role(palette, 'ui_bad')));
  drawStat(surface, palette, 12, 94, 82, 'MP', 0.41, rgb(accents(palette)[1] || role(palette, 'water')));
  drawStat(surface, palette, 12, 104, 82, 'STR', 0.88, rgb(role(palette, 'ui_good')));
  drawStat(surface, palette, 12, 114, 82, 'DEF', 0.55, rgb(role(palette, 'metal')));

  // Right column: a 6×4 item grid, rarity-coloured, one slot selected.
  panel(surface, 108, 22, 142, 108, palette, { fill: 0.14 });
  const rarity = [
    neutralShade(palette, 0.55),
    rgb(role(palette, 'ui_good')),
    rgb(role(palette, 'water')),
    gold,
  ];
  for (let r = 0; r < 4; r++) {
    for (let c = 0; c < 6; c++) {
      const sx = 113 + c * 22;
      const sy = 27 + r * 25;
      const i = r * 6 + c;
      surface.rect(sx, sy, 20, 22, neutralShade(palette, 0.08));
      surface.outline(sx, sy, 20, 22, neutralShade(palette, 0.36));
      if (i < 17) {
        const tint = rarity[i % rarity.length];
        surface.rect(sx + 4, sy + 4, 12, 12, mix(tint, dark, 0.35));
        surface.rect(sx + 4, sy + 4, 12, 3, tint);
        surface.text(String((i % 9) + 1), sx + 13, sy + 16, 1, light);
      }
      if (i === 8) { // the cursor
        surface.outline(sx - 1, sy - 1, 22, 24, gold);
        surface.outline(sx - 2, sy - 2, 24, 26, mix(gold, dark, 0.55));
      }
    }
  }
  // Scrollbar — a thin element that must not vanish into its track.
  surface.rect(244, 27, 4, 98, neutralShade(palette, 0.1));
  surface.rect(244, 40, 4, 36, neutralShade(palette, 0.6));

  // Footer: description at three scales again, plus the button legend.
  panel(surface, 6, 134, 244, 52, palette, { fill: 0.24 });
  surface.text('IRON KEY', 12, 138, 2, gold);
  surface.text('OPENS SOMETHING THAT HAS BEEN SHUT', 12, 154, 1, light);
  surface.text('A LONG TIME. HEAVIER THAN IT LOOKS.', 12, 162, 1, mix(light, neutralShade(palette, 0.5), 0.45));
  surface.text('A USE', 12, 172, 1, rgb(role(palette, 'ui_good')));
  surface.text('B BACK', 52, 172, 1, rgb(role(palette, 'ui_bad')));
  surface.text('SORT', 100, 172, 1, mix(light, dark, 0.4));
  surface.text('X24', 220, 170, 2, mix(light, gold, 0.3));
}

export const mockupScenes = [
  { id: 'world-screen', title: 'World screen (256×192)', category: CAT, width: W, height: H, render: renderWorldScreen },
  { id: 'menu-screen', title: 'Menu screen (256×192)', category: CAT, width: W, height: H, render: renderMenuScreen },
];
