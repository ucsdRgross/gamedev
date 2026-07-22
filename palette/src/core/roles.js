// Stable slot naming and semantic role assignment (PLAN §3.4-3.5).
//
// Structural slots (fg_h2_mid) carry a semantic layer on top (foliage, skin, stone…).
// The test gallery draws its tree in whatever slot holds `foliage`, so the assignment
// is what makes the gallery a real check rather than a decoration. Exports carry both.

import { hueDelta } from './oklch.js';
import { midIndex } from './ramp.js';

/** Human-readable name for a structural slot, stable across parameter changes. */
export function roleName(slot) {
  if (slot.layer === 'anchor') return slot.kind === 'dark' ? 'universal_dark' : 'universal_light';
  if (slot.layer === 'bridge') return `bridge_${slot.hueIndex}`;
  if (slot.layer === 'neutral') return `neutral_${slot.step}`;
  if (slot.layer === 'neutral-warm') return `neutral_warm_${slot.step}`;
  if (slot.layer === 'accent') return `accent_${slot.step}`;
  const prefix = slot.layer === 'bg' ? 'bg' : 'fg';
  const offset = slot.step - midIndex(slot.steps);
  const step =
    offset === 0 ? 'mid'
    : offset === -1 ? 'shadow'
    : offset === -2 ? 'deep'
    : offset === 1 ? 'light'
    : offset === 2 ? 'bright'
    : offset < 0 ? `dark${-offset}`
    : `hi${offset}`;
  return `${prefix}_h${slot.hueIndex}_${step}`;
}

/**
 * Semantic roles and the colour each looks for.
 * `hue: null` means "wants a neutral"; `chroma` biases toward or away from saturation.
 */
export const SEMANTIC_TARGETS = [
  { name: 'foliage', hue: 140, L: 0.45, chroma: 'mid', layer: 'fg' },
  { name: 'skin', hue: 45, L: 0.72, chroma: 'low', layer: 'fg' },
  { name: 'stone', hue: null, L: 0.5, chroma: 'low', layer: 'any' },
  { name: 'metal', hue: null, L: 0.68, chroma: 'low', layer: 'any' },
  { name: 'wood', hue: 55, L: 0.42, chroma: 'mid', layer: 'fg' },
  { name: 'water', hue: 235, L: 0.5, chroma: 'mid', layer: 'any' },
  { name: 'fire', hue: 45, L: 0.7, chroma: 'high', layer: 'fg' },
  { name: 'blood', hue: 20, L: 0.35, chroma: 'high', layer: 'fg' },
  { name: 'gold', hue: 90, L: 0.75, chroma: 'high', layer: 'fg' },
  { name: 'sky', hue: 240, L: 0.75, chroma: 'low', layer: 'bg' },
  { name: 'ui_good', hue: 145, L: 0.65, chroma: 'high', layer: 'fg' },
  { name: 'ui_bad', hue: 25, L: 0.6, chroma: 'high', layer: 'fg' },
  { name: 'ui_neutral', hue: null, L: 0.6, chroma: 'low', layer: 'any' },
];

/** Distance from an entry to a semantic target; lower is a better match. */
function score(entry, target) {
  const { L, C, h } = entry.oklch;
  let s = Math.abs(L - target.L) * 2.2;
  if (target.hue === null) {
    s += C * 12; // neutrals want as little chroma as possible
  } else {
    s += (Math.abs(hueDelta(h, target.hue)) / 180) * 1.6;
    if (target.chroma === 'high') s += Math.max(0, 0.2 - C) * 3;
    if (target.chroma === 'low') s += Math.max(0, C - 0.12) * 2;
    s += C < 0.02 ? 0.6 : 0; // a hued role should not land on a grey
  }
  if (target.layer !== 'any' && entry.layer !== target.layer) s += 0.35;
  if (entry.layer === 'anchor') s += 1.0;
  return s;
}

/**
 * Map each semantic role onto its best-fitting palette entry.
 * Entries are reused only once every candidate has been taken — unavoidable at K=4.
 */
export function assignSemanticRoles(entries) {
  const used = new Set();
  const out = {};
  for (const target of SEMANTIC_TARGETS) {
    let best = null;
    let bestScore = Infinity;
    for (const e of entries) {
      const s = score(e, target) + (used.has(e.id) ? 1.5 : 0);
      if (s < bestScore) {
        bestScore = s;
        best = e;
      }
    }
    if (best) {
      out[target.name] = best.id;
      used.add(best.id);
    }
  }
  return out;
}

/** Invert a role assignment map into slot id -> semantic names. */
export function semanticsBySlot(assignments) {
  const out = new Map();
  for (const [name, id] of Object.entries(assignments)) {
    if (!out.has(id)) out.set(id, []);
    out.get(id).push(name);
  }
  return out;
}
