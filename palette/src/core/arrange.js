// Swatch arrangements (UX_PLAN U4.5 — IMPROVEMENTS item 19).
//
// The swatch grid is drawn in generator order, which is the order the palette is *built* in:
// anchor, every foreground ramp, bridges, neutrals, backgrounds, accents, anchor. That order
// is right for reading the structure and wrong for nearly every question anyone actually asks
// of a palette — "does this ramp step evenly?", "where is the value hole?", "how many greens
// did I end up with?". Each of those is the same colours in a different order.
//
// So the arrangement is a view, not a rebuild: every mode returns the same entries regrouped,
// never a different set. A test pins that, because a swatch silently dropped from a view is
// a colour the user stops checking.
//
// `ramps` is built on `rampsOf()` from analysis.js — the same grouping the evenness metrics
// and the dither reference use, so a ramp on screen is the ramp the analysis talks about.

import { rampsOf } from './analysis.js';
import { hueName } from './describe.js';

/** The arrangements the palette pane offers: `[id, label, hint]`, in display order. */
export const ARRANGEMENTS = [
  ['slot', 'Grid', 'Generator order — the structure the palette is built in'],
  ['ramps', 'Ramps', 'One row per shading run, dark to light — where evenness is read'],
  ['lightness', 'By lightness', 'Darkest to lightest — where the value holes show'],
  ['hue', 'By hue', 'Grouped into colour families — how the budget was actually spent'],
];

/** Just the ids, for validation and for building a selector. */
export const ARRANGEMENT_IDS = ARRANGEMENTS.map(([id]) => id);

/** What to call the layers that are not fg/bg hue ramps. */
const LAYER_TITLES = {
  neutral: 'Neutrals',
  'neutral-warm': 'Warm neutrals',
  accent: 'Accents',
  bridge: 'Bridges',
  anchor: 'Anchors',
};

// Below this chroma a hue angle is noise — the OKLCH hue of a near-grey swings wildly on a
// change too small to see, so grouping those by hue name would scatter one grey ramp across
// four families. They get their own group instead.
const ACHROMATIC = 0.02;

/** Mean of an array of angles that are known not to straddle 0° (one hue band never does). */
const meanOf = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

/**
 * Regroup a palette's entries for display.
 *
 * Returns `[{ key, title, entries }]` — `title` is empty for the modes that are one flat run,
 * which is the signal to draw no heading. Every entry appears exactly once in every mode.
 */
export function arrangeEntries(palette, mode = 'slot') {
  const entries = palette.entries;
  if (mode === 'ramps') return rampGroups(palette);
  if (mode === 'lightness') {
    return [{ key: 'lightness', title: '', entries: [...entries].sort((a, b) => a.actual.L - b.actual.L) }];
  }
  if (mode === 'hue') return hueGroups(entries);
  return [{ key: 'slot', title: '', entries: [...entries] }];
}

/**
 * One group per shading run: the fg/bg hue ramps first (in generator order), then whatever
 * layer the rest belong to. Neutrals and warm neutrals are genuine ramps too — they carry a
 * `step` — so they are sorted into shading order like the hue ramps rather than left in a heap.
 */
function rampGroups(palette) {
  const groups = [];
  const taken = new Set();
  for (const { key, entries } of rampsOf(palette)) {
    for (const e of entries) taken.add(e.id);
    const layer = entries[0].layer === 'bg' ? 'Background' : 'Foreground';
    // The middle step names the ramp: the ends are hue-shifted toward the light and the
    // shadow targets, so calling a ramp by its darkest step names the shadow, not the colour.
    const mid = entries[Math.floor(entries.length / 2)];
    groups.push({ key, title: `${layer} ${hueName(mid.actual.h)}`, entries });
  }
  const rest = new Map();
  for (const e of palette.entries) {
    if (taken.has(e.id)) continue;
    if (!rest.has(e.layer)) rest.set(e.layer, []);
    rest.get(e.layer).push(e);
  }
  for (const [layer, list] of rest) {
    groups.push({
      key: `layer_${layer}`,
      title: LAYER_TITLES[layer] || layer,
      entries: list.sort((a, b) => a.step - b.step || a.actual.L - b.actual.L),
    });
  }
  return groups;
}

/** One group per colour family, neutrals first, each family sorted dark to light. */
function hueGroups(entries) {
  const neutral = [];
  const families = new Map(); // hue name -> entries
  for (const e of entries) {
    if (e.actual.C < ACHROMATIC) { neutral.push(e); continue; }
    const name = hueName(e.actual.h);
    if (!families.has(name)) families.set(name, []);
    families.get(name).push(e);
  }
  const groups = [...families.entries()]
    .map(([name, list]) => ({
      key: `hue_${name}`,
      title: `${name[0].toUpperCase()}${name.slice(1)} · ${list.length}`,
      entries: list.sort((a, b) => a.actual.L - b.actual.L),
      order: meanOf(list.map((e) => e.actual.h)),
    }))
    .sort((a, b) => a.order - b.order)
    .map(({ order, ...g }) => g);
  if (neutral.length) {
    groups.unshift({
      key: 'hue_neutral',
      title: `Neutral · ${neutral.length}`,
      entries: neutral.sort((a, b) => a.actual.L - b.actual.L),
    });
  }
  return groups;
}
