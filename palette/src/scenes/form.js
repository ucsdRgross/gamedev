// Form-and-shading scenes 7–10 (PLAN §8): lit spheres per ramp, an isometric cube, a
// cylinder falloff study, and material studies whose ramps are shaped per material.

import { rgb, ramps, shade, rampOfRole, anchorDark, anchorLight } from './util.js';

const CAT = 'Form';

// Light from the upper-left-front, normalised.
const LX = -0.42;
const LY = -0.5;
const LZ = 0.75;
const AMBIENT = 0.22;

/** Fill with a mid-dark neutral backdrop. */
function backdrop(surface, palette) {
  const d = anchorDark(palette).rgb8;
  surface.rect(0, 0, surface.w, surface.h, [d[0] + 10, d[1] + 10, d[2] + 12]);
}

/** Draw a lit sphere; `shadeFn(intensity 0..1)` returns the surface colour. */
function litSphere(surface, cx, cy, r, shadeFn) {
  for (let y = -r; y <= r; y++) {
    for (let x = -r; x <= r; x++) {
      const nx = x / r;
      const ny = y / r;
      const d2 = nx * nx + ny * ny;
      if (d2 > 1) continue;
      const nz = Math.sqrt(1 - d2);
      const ndotl = Math.max(0, nx * LX + ny * LY + nz * LZ);
      const intensity = AMBIENT + (1 - AMBIENT) * ndotl;
      surface.set(cx + x, cy + y, shadeFn(intensity));
    }
  }
}

/** A shade function that samples a palette ramp dark→light. */
const rampShader = (ramp) => (t) => rgb(shade(ramp, t));

// --- 7. Lit sphere per ramp -----------------------------------------------
function renderSpheres(surface, palette) {
  backdrop(surface, palette);
  const fg = ramps(palette, 'fg');
  const n = Math.max(1, fg.length);
  const r = Math.max(6, Math.floor((surface.w / n) / 2) - 3);
  const gap = Math.floor(surface.w / n);
  fg.forEach((ramp, i) => litSphere(surface, gap * i + Math.floor(gap / 2), Math.floor(surface.h / 2), r, rampShader(ramp)));
}

// --- 8. Isometric cube -----------------------------------------------------
function renderIsoCube(surface, palette) {
  backdrop(surface, palette);
  const ramp = rampOfRole(palette, 'stone');
  const top = rgb(shade(ramp, 0.95));
  const left = rgb(shade(ramp, 0.55));
  const right = rgb(shade(ramp, 0.28));
  const cx = Math.floor(surface.w / 2);
  const s = Math.floor(Math.min(surface.w, surface.h) / 3); // half-width of the top diamond
  const faceH = s; // vertical height of the side faces
  const topCy = Math.floor(surface.h / 2) - Math.floor(faceH / 2);
  // Walk each column: a diamond top-face slice, then the side face hanging below it.
  for (let dx = -s; dx <= s; dx++) {
    const colHalf = Math.round((1 - Math.abs(dx) / s) * (s / 2));
    for (let dy = -colHalf; dy <= colHalf; dy++) surface.set(cx + dx, topCy + dy, top);
    const faceTop = topCy + colHalf;
    const col = dx < 0 ? left : right;
    for (let k = 0; k < faceH; k++) surface.set(cx + dx, faceTop + k, col);
  }
}

// --- 9. Cylinder / bevel study --------------------------------------------
function renderCylinder(surface, palette) {
  backdrop(surface, palette);
  const ramp = rampOfRole(palette, 'metal');
  const pad = 6;
  const x0 = pad;
  const w = surface.w - pad * 2;
  const y0 = pad;
  const h = surface.h - pad * 2;
  for (let x = 0; x < w; x++) {
    // Curvature falloff across the width: brightest left-of-centre, soft roll to edges.
    const u = x / (w - 1);
    const nx = (u - 0.4) * 2;
    const ndotl = Math.max(0, Math.cos(nx * 1.2) * 0.9);
    const intensity = AMBIENT + (1 - AMBIENT) * ndotl;
    surface.rect(x0 + x, y0, 1, h, rgb(shade(ramp, intensity)));
  }
}

// --- 10. Material studies --------------------------------------------------
const MATERIALS = [
  { name: 'gold', role: 'gold', metal: true },
  { name: 'silver', role: 'metal', metal: true },
  { name: 'bronze', role: 'wood', metal: true },
  { name: 'wood', role: 'wood', metal: false },
  { name: 'stone', role: 'stone', metal: false },
  { name: 'cloth', role: 'foliage', metal: false },
  { name: 'glass', role: 'water', metal: false, rim: true },
  { name: 'water', role: 'water', metal: true },
];

/** Metals compress the diffuse range then jump to a hard specular; matte is linear. */
function materialShader(palette, spec) {
  const ramp = rampOfRole(palette, spec.role);
  const spec_hi = anchorLight(palette).rgb8;
  return (t) => {
    if (spec.metal) {
      if (t > 0.82) return spec_hi; // hard specular
      return rgb(shade(ramp, Math.pow(t, 1.5) * 0.9));
    }
    if (spec.rim && t < 0.3) return rgb(shade(ramp, 0.7)); // bright rim on glass
    return rgb(shade(ramp, t));
  };
}

function renderMaterials(surface, palette) {
  backdrop(surface, palette);
  const cols = 4;
  const rows = 2;
  const cw = Math.floor(surface.w / cols);
  const ch = Math.floor(surface.h / rows);
  const r = Math.floor(Math.min(cw, ch) / 2) - 3;
  MATERIALS.forEach((spec, i) => {
    const cx = (i % cols) * cw + Math.floor(cw / 2);
    const cy = Math.floor(i / cols) * ch + Math.floor(ch / 2);
    litSphere(surface, cx, cy, r, materialShader(palette, spec));
  });
}

export const formScenes = [
  { id: 'spheres', title: 'Lit sphere per ramp', category: CAT, width: 160, height: 64, render: renderSpheres },
  { id: 'iso-cube', title: 'Isometric cube', category: CAT, width: 96, height: 96, render: renderIsoCube },
  { id: 'cylinder', title: 'Cylinder / bevel', category: CAT, width: 120, height: 72, render: renderCylinder },
  { id: 'materials', title: 'Material studies', category: CAT, width: 160, height: 88, render: renderMaterials },
];
