// Shared helpers for the gallery scenes. Scenes address colours through these — by
// semantic role or by ramp — never by raw palette index, so that the same scene remains
// a meaningful test across every palette the generator can produce (ARCHITECTURE §8).

import { entryFor } from '../core/generate.js';
import { rampsOf } from '../core/analysis.js';
import { hueDelta } from '../core/oklch.js';

/** All ramps of a layer ('fg' or 'bg') as arrays of entries, each sorted dark→light. */
export function ramps(palette, layer) {
  return rampsOf(palette)
    .filter((r) => r.entries[0].layer === layer)
    .map((r) => [...r.entries].sort((a, b) => a.step - b.step));
}

/** The `[r,g,b]` of a palette entry. */
export const rgb = (entry) => entry.rgb8;

/** Resolve a semantic role or slot id to its entry. */
export const role = (palette, name) => entryFor(palette, name);

/** The universal dark and light anchors. */
export const anchorDark = (palette) => entryFor(palette, 'universal_dark');
export const anchorLight = (palette) => entryFor(palette, 'universal_light');

/** Pick a ramp step by a 0..1 light factor (0 = darkest step, 1 = lightest). */
export function shade(rampEntries, t) {
  const n = rampEntries.length;
  if (n === 0) return null;
  const i = Math.max(0, Math.min(n - 1, Math.round(t * (n - 1))));
  return rampEntries[i];
}

/** The foreground ramp that owns a semantic role, or the hue-nearest fg ramp. */
export function rampOfRole(palette, name) {
  const e = entryFor(palette, name);
  const fg = ramps(palette, 'fg');
  if (fg.length === 0) return [e];
  const owner = fg.find((r) => r.some((x) => x.id === e.id));
  if (owner) return owner;
  let best = fg[0];
  let bestD = Infinity;
  for (const r of fg) {
    const mid = r[Math.floor(r.length / 2)];
    const d = Math.abs(hueDelta(mid.actual.h, e.actual.h));
    if (d < bestD) { bestD = d; best = r; }
  }
  return best;
}

/** Neutral ramp entries sorted dark→light (both families, if the palette split them). */
export function neutrals(palette) {
  return palette.entries
    .filter((e) => e.layer === 'neutral' || e.layer === 'neutral-warm')
    .sort((a, b) => a.actual.L - b.actual.L);
}

/** Accent entries, brightest chroma first. */
export function accents(palette) {
  return palette.entries.filter((e) => e.layer === 'accent');
}

/** Background entries sorted dark→light — the atmosphere/scenery colours. */
export function backgrounds(palette) {
  return palette.entries
    .filter((e) => e.layer === 'bg')
    .sort((a, b) => a.actual.L - b.actual.L);
}

/** A background colour by depth 0..1 (0 = nearest/darkest, 1 = farthest/lightest). */
export function bgByDepth(palette, t) {
  const bg = backgrounds(palette);
  if (bg.length === 0) return anchorDark(palette);
  return bg[Math.max(0, Math.min(bg.length - 1, Math.round(t * (bg.length - 1))))];
}

/** Every entry, for scenes that genuinely iterate the whole palette (swatch grid, board). */
export const allEntries = (palette) => palette.entries;
