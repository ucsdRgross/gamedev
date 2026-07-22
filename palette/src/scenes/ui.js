// UI scenes 25–26 (PLAN §8): a game-UI mockup and the text-legibility matrix with a
// WCAG contrast pass/fail overlay.

import {
  rgb, shade, neutrals, accents, rampOfRole, anchorDark, anchorLight, allEntries, role,
} from './util.js';
import { contrastRatio } from '../core/oklch.js';

const CAT = 'UI';
const WCAG_AA = 4.5;

function neutralShade(palette, t) {
  const n = neutrals(palette);
  if (n.length === 0) return anchorDark(palette).rgb8;
  return rgb(n[Math.max(0, Math.min(n.length - 1, Math.round(t * (n.length - 1))))]);
}

function desaturate(c) {
  const g = Math.round(c[0] * 0.3 + c[1] * 0.5 + c[2] * 0.2);
  return [Math.round((c[0] + g) / 2), Math.round((c[1] + g) / 2), Math.round((c[2] + g) / 2)];
}

// --- 25. UI mockup ---------------------------------------------------------
function renderUiMockup(surface, palette) {
  const dark = anchorDark(palette).rgb8;
  const light = anchorLight(palette).rgb8;
  surface.rect(0, 0, surface.w, surface.h, [dark[0] + 8, dark[1] + 8, dark[2] + 10]);

  // Top panel with health + mana bars.
  const panel = neutralShade(palette, 0.35);
  surface.rect(3, 3, surface.w - 6, 20, panel);
  surface.outline(3, 3, surface.w - 6, 20, light);
  const hp = rgb((accents(palette)[0]) || role(palette, 'ui_bad'));
  const mp = rgb((accents(palette)[1]) || role(palette, 'water'));
  surface.rect(6, 6, 40, 4, dark); surface.rect(6, 6, 30, 4, hp);
  surface.rect(6, 12, 40, 4, dark); surface.rect(6, 12, 22, 4, mp);
  surface.text('HP', 48, 6, 1, light);
  surface.text('MP', 48, 12, 1, light);

  // Buttons: normal / hover / pressed / disabled.
  const states = [
    ['norm', neutralShade(palette, 0.45), light],
    ['hovr', neutralShade(palette, 0.62), light],
    ['prsd', neutralShade(palette, 0.28), light],
    ['dsbl', desaturate(neutralShade(palette, 0.45)), desaturate(light)],
  ];
  const bw = 26;
  states.forEach(([label, fill, txt], i) => {
    const x = 4 + i * (bw + 2);
    const y = 28;
    surface.rect(x, y, bw, 11, fill);
    surface.outline(x, y, bw, 11, dark);
    surface.text(label.toUpperCase(), x + 3, y + 3, 1, txt);
  });

  // Inventory grid.
  const invY = 44;
  const g = neutralShade(palette, 0.2);
  for (let r = 0; r < 2; r++) {
    for (let c = 0; c < 6; c++) {
      const x = 4 + c * 13;
      const y = invY + r * 13;
      surface.rect(x, y, 11, 11, g);
      surface.outline(x, y, 11, 11, neutralShade(palette, 0.5));
      if ((r + c) % 3 === 0) surface.disc(x + 5, y + 5, 3, rgb(role(palette, 'gold')));
      if ((r + c) % 3 === 1) surface.rect(x + 4, y + 2, 3, 7, rgb(shade(rampOfRole(palette, 'metal'), 0.7)));
    }
  }

  // Minimap (top-right).
  const mmX = surface.w - 30;
  const mmY = 28;
  surface.rect(mmX, mmY, 26, 26, dark);
  surface.outline(mmX, mmY, 26, 26, light);
  for (let y = 0; y < 24; y++) {
    for (let x = 0; x < 24; x++) {
      const v = ((x * 7 + y * 13) % 11) / 11;
      surface.set(mmX + 1 + x, mmY + 1 + y, rgb(shade(rampOfRole(palette, 'foliage'), 0.25 + v * 0.3)));
    }
  }
  surface.set(mmX + 13, mmY + 13, rgb((accents(palette)[0]) || role(palette, 'ui_bad'))); // player blip

  // Tooltip.
  const ttY = surface.h - 14;
  surface.rect(surface.w - 60, ttY, 56, 11, dark);
  surface.outline(surface.w - 60, ttY, 56, 11, rgb(role(palette, 'gold')));
  surface.text('POTION +5', surface.w - 57, ttY + 3, 1, light);
}

// --- 26. Text legibility matrix -------------------------------------------
function renderTextMatrix(surface, palette) {
  surface.rect(0, 0, surface.w, surface.h, anchorDark(palette).rgb8);
  const es = allEntries(palette);
  const n = es.length;

  // Left block: a KxK WCAG pass/fail grid — fg row i on bg col j.
  const gridSize = Math.min(surface.h - 12, Math.floor(surface.w * 0.55));
  const cell = Math.max(1, Math.floor(gridSize / n));
  const pass = rgb(role(palette, 'ui_good'));
  const fail = rgb(role(palette, 'ui_bad'));
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      const ok = contrastRatio(es[i].rgb8, es[j].rgb8) >= WCAG_AA;
      surface.rect(1 + j * cell, 8 + i * cell, cell, cell, ok ? pass : fail);
    }
  }
  surface.text('WCAG AA GRID', 1, 1, 1, anchorLight(palette).rgb8);

  // Right block: real text samples, light and dark ink on a few backgrounds.
  const rx = 2 + n * cell + 6;
  const samples = [
    anchorDark(palette), anchorLight(palette),
    (neutrals(palette)[Math.floor(neutrals(palette).length / 2)]) || anchorDark(palette),
    role(palette, 'sky'), role(palette, 'foliage'),
  ];
  const rowH = Math.floor((surface.h - 8) / samples.length);
  samples.forEach((bg, i) => {
    const y = 8 + i * rowH;
    surface.rect(rx, y, surface.w - rx - 1, rowH - 1, bg.rgb8);
    const lightOk = contrastRatio(anchorLight(palette).rgb8, bg.rgb8) >= WCAG_AA;
    const darkOk = contrastRatio(anchorDark(palette).rgb8, bg.rgb8) >= WCAG_AA;
    surface.text('Aa1', rx + 2, y + 2, 1, anchorLight(palette).rgb8);
    surface.text('Aa1', rx + 20, y + 2, 1, anchorDark(palette).rgb8);
    // pass markers
    surface.rect(rx + 15, y + 2, 2, 2, lightOk ? rgb(role(palette, 'ui_good')) : rgb(role(palette, 'ui_bad')));
    surface.rect(rx + 33, y + 2, 2, 2, darkOk ? rgb(role(palette, 'ui_good')) : rgb(role(palette, 'ui_bad')));
  });
}

export const uiScenes = [
  { id: 'ui-mockup', title: 'UI mockup', category: CAT, width: 160, height: 96, render: renderUiMockup },
  { id: 'text-matrix', title: 'Text legibility matrix', category: CAT, width: 160, height: 100, render: renderTextMatrix },
];
