// Colour names (UX_PLAN U2.3 — item 21).
//
// "The dusty rose one" is how people actually refer to a colour; `#C98A82` is not. A name on
// every swatch makes a palette discussable, memorable and searchable, and it is what the
// auto-generated save names are built from.
//
// Two layers, because a fixed list can only ever be sparse:
//   * `nearestName` — the closest entry in an embedded list of well-known colour names,
//     measured in OKLab so "closest" means closest to the eye.
//   * `describeColor` — a procedural fallback ("dark muted teal") used when nothing in the
//     list is near enough to claim. Never wrong, never evocative.
// `colorLabel` picks between them, which is what the UI should call.
//
// Hexes are the conventional published values (CSS/X11 where the name exists there), so the
// list is checkable rather than invented. DOM-free, no dependencies.

import { hexToRgb8, rgb8ToOklab, rgb8ToOklch, deltaEOK } from './oklch.js';

/** name -> hex. Ordered loosely by hue family; order carries no meaning. */
export const COLOR_NAMES = {
  // Reds, pinks
  crimson: '#DC143C',
  scarlet: '#FF2400',
  ruby: '#9B111E',
  oxblood: '#4A0000',
  maroon: '#800000',
  brick: '#CB4154',
  rust: '#B7410E',
  tomato: '#FF6347',
  coral: '#FF7F50',
  salmon: '#FA8072',
  blush: '#DE5D83',
  rose: '#FF007F',
  'dusty rose': '#DCAE96',
  pink: '#FFC0CB',
  'hot pink': '#FF69B4',
  magenta: '#FF00FF',
  raspberry: '#E30B5C',
  mulberry: '#C54B8C',
  wine: '#722F37',
  burgundy: '#800020',
  blood: '#8A0303',

  // Oranges, browns
  orange: '#FFA500',
  tangerine: '#F28500',
  flame: '#E25822',
  apricot: '#FBCEB1',
  peach: '#FFE5B4',
  amber: '#FFBF00',
  gold: '#FFD700',
  honey: '#EBA937',
  mustard: '#FFDB58',
  ochre: '#CC7722',
  copper: '#B87333',
  bronze: '#CD7F32',
  brass: '#B5A642',
  terracotta: '#E2725B',
  sienna: '#A0522D',
  umber: '#635147',
  sepia: '#704214',
  chocolate: '#D2691E',
  coffee: '#6F4E37',
  mahogany: '#C04000',
  chestnut: '#954535',
  walnut: '#5C4033',
  tan: '#D2B48C',
  sand: '#C2B280',
  wheat: '#F5DEB3',
  cream: '#FFFDD0',
  ivory: '#FFFFF0',
  bone: '#E3DAC9',
  linen: '#FAF0E6',
  taupe: '#483C32',
  flesh: '#FFE0BD',
  'skin tan': '#E0AC69',
  'deep skin': '#8D5524',

  // Yellows, greens
  yellow: '#FFFF00',
  lemon: '#FFF700',
  straw: '#E4D96F',
  khaki: '#F0E68C',
  olive: '#808000',
  'olive drab': '#6B8E23',
  moss: '#8A9A5B',
  sage: '#9CAF88',
  chartreuse: '#7FFF00',
  lime: '#00FF00',
  fern: '#4F7942',
  'forest green': '#228B22',
  'hunter green': '#355E3B',
  pine: '#01796F',
  emerald: '#50C878',
  jade: '#00A86B',
  mint: '#98FF98',
  seafoam: '#93E9BE',
  viridian: '#40826D',
  'sea green': '#2E8B57',

  // Cyans, teals
  teal: '#008080',
  turquoise: '#40E0D0',
  aquamarine: '#7FFFD4',
  cyan: '#00FFFF',
  'powder blue': '#B0E0E6',
  'sky blue': '#87CEEB',

  // Blues
  cerulean: '#2A52BE',
  azure: '#007FFF',
  cobalt: '#0047AB',
  denim: '#1560BD',
  'steel blue': '#4682B4',
  navy: '#000080',
  'midnight blue': '#191970',
  'prussian blue': '#003153',
  'slate blue': '#6A5ACD',

  // Violets, purples
  periwinkle: '#CCCCFF',
  lavender: '#E6E6FA',
  lilac: '#C8A2C8',
  violet: '#7F00FF',
  amethyst: '#9966CC',
  indigo: '#4B0082',
  'royal purple': '#7851A9',
  eggplant: '#614051',
  orchid: '#DA70D6',
  plum: '#DDA0DD',

  // Neutrals
  white: '#FFFFFF',
  snow: '#FFFAFA',
  silver: '#C0C0C0',
  ash: '#B2BEB5',
  pewter: '#8E9294',
  stone: '#928E85',
  slate: '#708090',
  gunmetal: '#2A3439',
  graphite: '#41424C',
  charcoal: '#36454F',
  soot: '#1A1A1A',
  black: '#000000',
};

/** The list precomputed into OKLab, built once. */
const NAMED = Object.entries(COLOR_NAMES).map(([name, hex]) => ({
  name,
  hex,
  lab: rgb8ToOklab(hexToRgb8(hex)),
}));

/** Lightness and chroma bands for the procedural fallback. */
const L_WORDS = [[0.16, 'near-black'], [0.32, 'very dark'], [0.46, 'dark'], [0.62, 'mid'], [0.76, 'light'], [0.9, 'pale'], [1.01, 'near-white']];
const C_WORDS = [[0.02, 'grey'], [0.055, 'muted'], [0.11, 'soft'], [0.18, ''], [0.26, 'vivid'], [1, 'intense']];
const HUE_WORDS = [
  [15, 'crimson'], [40, 'red'], [70, 'orange'], [95, 'amber'], [120, 'yellow'],
  [138, 'lime'], [158, 'green'], [180, 'emerald'], [205, 'teal'], [230, 'cyan'],
  [255, 'azure'], [280, 'blue'], [305, 'indigo'], [330, 'violet'], [350, 'magenta'],
  [360, 'pink'],
];

/** Pick a word from a `[[limit, word], …]` table. */
function pick(value, table) {
  for (const [limit, word] of table) if (value < limit) return word;
  return table[table.length - 1][1];
}

/**
 * A plain description of a colour: lightness, saturation, hue. Always correct and always
 * available — the floor under the name list rather than a competitor to it.
 */
export function describeColor(hex) {
  const { L, C, h } = rgb8ToOklch(hexToRgb8(hex));
  const light = pick(L, L_WORDS);
  const sat = pick(C, C_WORDS);
  if (C < 0.02) return `${light} grey`;
  const hue = pick(((h % 360) + 360) % 360, HUE_WORDS);
  return [light, sat, hue].filter(Boolean).join(' ');
}

/** The nearest named colour, with its perceptual distance (0 = exactly that colour). */
export function nearestName(hex) {
  const lab = rgb8ToOklab(hexToRgb8(hex));
  let best = NAMED[0];
  let bestDist = Infinity;
  for (const entry of NAMED) {
    const d = deltaEOK(lab, entry.lab);
    if (d < bestDist) {
      bestDist = d;
      best = entry;
    }
  }
  return { name: best.name, hex: best.hex, distance: bestDist };
}

// Past this distance, calling a colour by that name would be a lie. `deltaEOK` here runs on
// roughly a 0–13 scale over the sRGB gamut, and with a 111-entry list the nearest name for a
// generated palette colour sits at a median of about 4.7 — so 5 is the point where "a kind of
// teal" is still true. Above it the procedural description takes over.
const NAME_LIMIT = 5;

/**
 * What to call a colour: its nearest name when one is genuinely close, otherwise a plain
 * description. `exact` marks a hit on the list itself.
 */
export function colorLabel(hex) {
  const near = nearestName(hex);
  if (near.distance <= NAME_LIMIT) {
    return { label: near.name, exact: near.distance < 1e-6, distance: near.distance, named: true };
  }
  return { label: describeColor(hex), exact: false, distance: near.distance, named: false };
}
