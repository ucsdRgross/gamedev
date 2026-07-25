// Saying what a palette is, in words (UX_PLAN U2.2 — items 32 and 34).
//
// Two jobs, both about closing the gap between 72 numbers and "what am I looking at":
//
//   * `describePalette` reads the *generated colours* (not the parameters) and returns one
//     line — "32 colours · 5 analogous hues around orange · dark-key, punchy · muted · warm
//     light, cool shadows". Useful as a save name, as a sanity check that the parameters say
//     what you think they say, and as the left-hand side of a comparison.
//   * `paramDiff` / `summarizeDiff` say what changed between two parameter sets, ordered by
//     how much of its own range each knob moved. That is what makes a preset, a fit, a
//     variant click or an undo explain itself instead of being an opaque jump.
//
// DOM-free; measured from `entry.actual`, so it describes what the generator produced rather
// than what was asked for.

import { PARAMS, PARAM_BY_NAME, BASIC_PARAM_NAMES, optionLabel } from './params.js';
import { rampsOf } from './analysis.js';
import { meanHue } from './oklch.js';

const BASICS = new Set(BASIC_PARAM_NAMES);

/**
 * Hue names by OKLCH angle. Calibrated against the primaries in this space — red is 29°,
 * orange 53°, yellow 110°, green 142°, cyan 195°, blue 264°, magenta 328° — not against the
 * HSL angles those names have elsewhere.
 */
const HUE_NAMES = [
  [15, 'crimson'], [40, 'red'], [70, 'orange'], [95, 'amber'], [120, 'yellow'],
  [138, 'lime'], [158, 'green'], [180, 'emerald'], [205, 'teal'], [230, 'cyan'],
  [255, 'azure'], [280, 'blue'], [305, 'indigo'], [330, 'violet'], [350, 'magenta'],
  [360, 'pink'],
];

/** The name of a hue angle (0..360) in the same words the rest of the app uses. */
export function hueName(h) {
  const a = ((h % 360) + 360) % 360;
  for (const [limit, name] of HUE_NAMES) if (a < limit) return name;
  return 'red';
}

/** Mean of an array, or 0 for an empty one. */
const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);

/** Pick the band a value falls in from `[[limit, word], …]`, last word as the fallback. */
function band(value, table) {
  for (const [limit, word] of table) if (value < limit) return word;
  return table[table.length - 1][1];
}

const KEY_BANDS = [[0.35, 'very dark'], [0.47, 'dark-key'], [0.62, 'mid-key'], [0.75, 'bright'], [1, 'high-key']];
const SAT_BANDS = [[0.012, 'greyscale'], [0.045, 'near-greyscale'], [0.09, 'muted'], [0.15, 'balanced'], [0.22, 'vivid'], [1, 'neon']];
const CONTRAST_BANDS = [[0.075, 'soft'], [0.13, 'moderate'], [0.19, 'punchy'], [1, 'extreme']];

/**
 * One line describing the palette as built. `params` is optional — without it the shading and
 * background clauses (which are statements of intent, not of colour) are left out.
 */
export function describePalette(palette, params = null) {
  const entries = palette.entries;
  const chromatic = entries.filter((e) => e.actual.C > 0.03);
  const fg = entries.filter((e) => e.layer === 'fg');
  const parts = [];

  parts.push(`${entries.length} colours`);

  // Hue identity: how many families, related how, centred where. "Around" is `root_hue` —
  // the theme the fan is built on. Neither the circular mean (which for a wide fan lands on
  // a hue the palette may not contain) nor `hues[0]` (the fan's first arm, not its centre)
  // is what a person means by "what colour is this palette".
  const hueCount = palette.plan?.hueCount ?? 0;
  const centre = params ? Number(params.root_hue) : meanHue(chromatic.map((e) => e.actual.h));
  const scheme = params ? String(params.hue_scheme) : '';
  const schemeWord = scheme && scheme !== 'even' && scheme !== 'custom' ? `${scheme} ` : '';
  if (chromatic.length === 0) parts.push('no colour at all — pure greys');
  else if (hueCount <= 1) parts.push(`a single ${hueName(centre)} hue`);
  else parts.push(`${hueCount} ${schemeWord}hues around ${hueName(centre)}`);

  // Value structure, measured from the foreground.
  const key = band(mean((fg.length ? fg : entries).map((e) => e.actual.L)), KEY_BANDS);
  const steps = rampsOf(palette)
    .filter((r) => r.entries.length > 1)
    .flatMap((r) => r.entries.slice(1).map((e, i) => Math.abs(e.actual.L - r.entries[i].actual.L)));
  const contrast = steps.length ? band(mean(steps), CONTRAST_BANDS) : 'flat';
  parts.push(`${key}, ${contrast} contrast`);

  // Saturation, measured over the colours that have any.
  parts.push(band(mean(chromatic.map((e) => e.actual.C)), SAT_BANDS));

  if (params) {
    // Shading: the hue-shift pair is the signature of painted pixel art.
    const shift = (Number(params.highlight_shift_strength) + Number(params.shadow_shift_strength)) / 2;
    if (shift < 0.08) parts.push('flat shading');
    else {
      const split = Number(params.temperature_split);
      const direction = split >= 0.5 ? 'warm light, cool shadows'
        : split <= 0.25 ? 'cool light, warm shadows'
          : 'evenly split light and shadow';
      parts.push(`${shift > 0.3 ? 'strongly' : 'gently'} hue-shifted — ${direction}`);
    }

    if (Number(params.earthiness) >= 0.35) parts.push('earthy');
    if (Number(params.l_range_compress) >= 0.3) parts.push('hazy, compressed values');
    const bgMult = Number(params.bg_chroma_mult);
    if (bgMult <= 0.45) parts.push('recessive backgrounds');
    else if (bgMult >= 0.85) parts.push('backgrounds as vivid as the sprites');
    const bits = Math.min(Number(params.bits_r), Number(params.bits_g), Number(params.bits_b));
    if (bits <= 5) parts.push(`${params.bits_r}/${params.bits_g}/${params.bits_b}-bit hardware`);
  }

  return parts.join(' · ');
}

// Name words, deliberately not the description's words (UX_PLAN U5.1 — item 6). "dark-key,
// balanced" is the right way to *describe* a palette and a terrible way to *call* one: a name
// has to be short, has to sound like a thing, and has to survive being read in a list of
// twenty. So the same measurements get a second, friendlier vocabulary.
// Calibrated against what the generator actually produces, not against the 0..0.37 chroma
// range: measured over all twenty-one presets the mean chroma of the coloured entries spans
// 0.036 (Monochrome Ink) to 0.166 (OKLab Crayon), so bands drawn at 0.22 would mean every
// palette ever made was called "mid" and nothing was ever called vivid.
const NAME_KEY = [[0.35, 'midnight'], [0.47, 'dusk'], [0.62, 'mid'], [0.75, 'bright'], [1, 'pale']];
const NAME_SAT = [[0.05, 'grey'], [0.08, 'muted'], [0.11, ''], [0.14, 'rich'], [1, 'vivid']];

/**
 * A name for a palette nobody wants to name (UX_PLAN U5.1).
 *
 * Keeping a palette must cost one click, and a dialogue asking "what shall we call it?" is
 * the reason `saved/` is empty while a text file in the project root holds pasted seeds. So
 * the name is read off the colours — "Muted teal 16", "Neon magenta 32" — and renamed later
 * if it ever matters. `taken` disambiguates with a trailing number rather than overwriting,
 * because the whole point is that nothing is ever lost by pressing the button.
 *
 * The result always satisfies the save-name rule (letters, digits, spaces; 64 max).
 */
export function autoName(palette, params = null, { taken = [] } = {}) {
  const entries = palette.entries;
  const chromatic = entries.filter((e) => e.actual.C > 0.03);
  const fg = entries.filter((e) => e.layer === 'fg');
  const key = band(mean((fg.length ? fg : entries).map((e) => e.actual.L)), NAME_KEY);
  const sat = chromatic.length ? band(mean(chromatic.map((e) => e.actual.C)), NAME_SAT) : 'grey';
  // The saturation word wins when there is one, because "neon" says more about a palette than
  // "bright" does; a palette of unremarkable saturation falls back to its key.
  const words = [sat || key];
  // A palette called grey does not then get named after a hue: the whole claim being made is
  // that it has not got one, and "Grey azure 12" contradicts itself in three words.
  if (chromatic.length && sat !== 'grey') {
    const centre = params ? Number(params.root_hue) : meanHue(chromatic.map((e) => e.actual.h));
    words.push(hueName(centre));
  }
  words.push(String(entries.length));
  const base = words.join(' ').replace(/^./, (c) => c.toUpperCase()).slice(0, 60);
  if (!taken.includes(base)) return base;
  for (let n = 2; n < 1000; n++) {
    const candidate = `${base} ${n}`;
    if (!taken.includes(candidate)) return candidate;
  }
  return base;
}

/** Two parameter values equal for diff purposes (float step noise ignored). */
function same(a, b) {
  if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b) < 1e-6;
  return a === b;
}

/**
 * What changed between two parameter sets, biggest move first.
 *
 * `magnitude` is the fraction of its own range a numeric parameter moved, so a 20° hue turn
 * and a 0.05 chroma bump can be ranked against each other. An enum or bool flip counts as
 * 0.5 — always significant, but not automatically ahead of a knob that crossed its whole
 * range. Sorting additionally favours the Basics, because "hue count went from 2 to 8" is
 * more of an explanation than "the dither evenness moved" even at equal fractions.
 */
export function paramDiff(from, to, { minMagnitude = 0 } = {}) {
  const out = [];
  for (const spec of PARAMS) {
    const a = from?.[spec.name];
    const b = to?.[spec.name];
    if (a === undefined || b === undefined || same(a, b)) continue;
    const numeric = spec.type === 'float' || spec.type === 'int';
    // `seed` selects which random variation you get; the number itself means nothing, so it
    // must never be *described* as a change — a reroll would otherwise outrank every real
    // move purely because 0..65535 is a wide range.
    const magnitude = spec.name === 'seed' ? 0
      : numeric ? Math.abs(Number(b) - Number(a)) / (spec.max - spec.min)
        : 0.5;
    // A variation nudges dozens of knobs by a fraction of a percent; listing those as
    // "+34 more" buries the two changes that actually did something.
    if (magnitude < minMagnitude) continue;
    out.push({
      name: spec.name,
      label: spec.label,
      type: spec.type,
      from: a,
      to: b,
      delta: numeric ? Number(b) - Number(a) : null,
      magnitude,
      weight: magnitude * (BASICS.has(spec.name) ? 1.3 : 1),
    });
  }
  return out.sort((x, y) => y.weight - x.weight);
}

/** How one diff entry reads: "Saturation +0.06" or "How the hues relate → Triadic". */
export function describeChange(change) {
  const spec = PARAM_BY_NAME.get(change.name);
  if (change.type === 'bool') return `${change.label} ${change.to ? 'on' : 'off'}`;
  if (change.type === 'enum') {
    const label = optionLabel(spec, change.to);
    return `${change.label} → ${label.split('—')[0].trim()}`;
  }
  const decimals = spec.type === 'int' || spec.step >= 1 ? 0 : (spec.step < 0.01 ? 3 : 2);
  const sign = change.delta > 0 ? '+' : '−';
  return `${change.label} ${sign}${Math.abs(change.delta).toFixed(decimals)}`;
}

/**
 * A one-line summary of a diff — the `n` biggest moves, then a count of the rest.
 * Returns '' when nothing changed, so a caller can skip the line entirely.
 */
export function summarizeDiff(diff, n = 3) {
  if (!diff.length) return '';
  const head = diff.slice(0, n).map(describeChange).join(' · ');
  const rest = diff.length - Math.min(n, diff.length);
  return rest > 0 ? `${head} · +${rest} more` : head;
}
