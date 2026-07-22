// Embedded real palettes, read-only, purely as comparison targets (PLAN §11).
//
// These are not presets and cannot be loaded as parameters — they exist so a generated
// palette can be scored against something a human made. The fit score doubles as an
// automated regression metric.

import { hexToRgb8, rgb8ToOklab, deltaEOK } from './oklch.js';

/** Reference palettes, each an ordered list of `#RRGGBB` strings. */
export const REFERENCE_PALETTES = [
  {
    id: 'db16',
    name: 'DawnBringer 16',
    author: 'DawnBringer',
    colors: ['#140C1C', '#442434', '#30346D', '#4E4A4E', '#854C30', '#346524', '#D04648',
      '#757161', '#597DCE', '#D27D2C', '#8595A1', '#6DAA2C', '#D2AA99', '#6DC2CA',
      '#DAD45E', '#DEEED6'],
  },
  {
    id: 'db32',
    name: 'DawnBringer 32',
    author: 'DawnBringer',
    colors: ['#000000', '#222034', '#45283C', '#663931', '#8F563B', '#DF7126', '#D9A066',
      '#EEC39A', '#FBF236', '#99E550', '#6ABE30', '#37946E', '#4B692F', '#524B24',
      '#323C39', '#3F3F74', '#306082', '#5B6EE1', '#639BFF', '#5FCDE4', '#CBDBFC',
      '#FFFFFF', '#9BADB7', '#847E87', '#696A6A', '#595652', '#76428A', '#AC3232',
      '#D95763', '#D77BBA', '#8F974A', '#8A6F30'],
  },
  {
    id: 'endesga32',
    name: 'Endesga 32',
    author: 'Endesga',
    colors: ['#BE4A2F', '#D77643', '#EAD4AA', '#E4A672', '#B86F50', '#733E39', '#3E2731',
      '#A22633', '#E43B44', '#F77622', '#FEAE34', '#FEE761', '#63C74D', '#3E8948',
      '#265C42', '#193C3E', '#124E89', '#0099DB', '#2CE8F5', '#FFFFFF', '#C0CBDC',
      '#8B9BB4', '#5A6988', '#3A4466', '#262B44', '#181425', '#FF0044', '#68386C',
      '#B55088', '#F6757A', '#E8B796', '#C28569'],
  },
  {
    id: 'pico8',
    name: 'PICO-8',
    author: 'Lexaloffle',
    colors: ['#000000', '#1D2B53', '#7E2553', '#008751', '#AB5236', '#5F574F', '#C2C3C7',
      '#FFF1E8', '#FF004D', '#FFA300', '#FFEC27', '#00E436', '#29ADFF', '#83769C',
      '#FF77A8', '#FFCCAA'],
  },
  {
    id: 'sweetie16',
    name: 'Sweetie 16',
    author: 'GrafxKid',
    colors: ['#1A1C2C', '#5D275D', '#B13E53', '#EF7D57', '#FFCD75', '#A7F070', '#38B764',
      '#257179', '#29366F', '#3B5DC9', '#41A6F6', '#73EFF7', '#F4F4F4', '#94B0C2',
      '#566C86', '#333C57'],
  },
  {
    id: 'nes',
    name: 'NES (2C02)',
    author: 'Nintendo',
    colors: ['#7C7C7C', '#0000FC', '#0000BC', '#4428BC', '#940084', '#A80020', '#A81000',
      '#881400', '#503000', '#007800', '#006800', '#005800', '#004058', '#000000',
      '#BCBCBC', '#0078F8', '#0058F8', '#6844FC', '#D800CC', '#E40058', '#F83800',
      '#E45C10', '#AC7C00', '#00B800', '#00A800', '#00A844', '#008888',
      '#F8F8F8', '#3CBCFC', '#6888FC', '#9878F8', '#F878F8', '#F85898', '#F87858',
      '#FCA044', '#F8B800', '#B8F818', '#58D854', '#58F898', '#00E8D8', '#787878',
      '#FCFCFC', '#A4E4FC', '#B8B8F8', '#D8B8F8', '#F8B8F8', '#F8A4C0', '#F0D0B0',
      '#FCE0A8', '#F8D878', '#D8F878', '#B8F8B8', '#B8F8D8', '#00FCFC', '#F8D8F8'],
  },
  {
    id: 'gameboy',
    name: 'Game Boy DMG',
    author: 'Nintendo',
    colors: ['#0F380F', '#306230', '#8BAC0F', '#9BBC0F'],
  },
  {
    id: 'c64',
    name: 'Commodore 64',
    author: 'Commodore',
    colors: ['#000000', '#FFFFFF', '#880000', '#AAFFEE', '#CC44CC', '#00CC55', '#0000AA',
      '#EEEE77', '#DD8855', '#664400', '#FF7777', '#333333', '#777777', '#AAFF66',
      '#0088FF', '#BBBBBB'],
  },
  {
    id: 'resurrect64',
    name: 'Resurrect 64',
    author: 'Kerrie Lake',
    colors: ['#2E222F', '#3E3546', '#625565', '#966C6C', '#AB947A', '#694F62', '#7F708A',
      '#9BABB2', '#C7DCD0', '#FFFFFF', '#6E2727', '#B33831', '#EA4F36', '#F57D4A',
      '#AE2334', '#E83B3B', '#FB6B1D', '#F79617', '#F9C22B', '#7A3045', '#9E4539',
      '#CD683D', '#E6904E', '#FBB954', '#4C3E24', '#676633', '#A2A947', '#D5E04B',
      '#FBFF86', '#165A4C', '#239063', '#1EBC73', '#91DB69', '#CDDF6C', '#313638',
      '#374E4A', '#547E64', '#92A984', '#B2BA90', '#0B5E65', '#0B8A8F', '#0EAF9B',
      '#30E1B9', '#8FF8E2', '#323353', '#484A77', '#4D65B4', '#4D9BE6', '#8FD3FF',
      '#45293F', '#6B3E75', '#905EA9', '#A884F3', '#EAADED', '#753C54', '#A24B6F',
      '#CF657F', '#ED8099', '#831C5D', '#C32454', '#F04F78', '#F68181', '#FCA790',
      '#FDCBB0'],
  },
  {
    id: 'apollo',
    name: 'Apollo',
    author: 'AdamCYounis',
    colors: ['#172038', '#253A5E', '#3C5E8B', '#4F8FBA', '#73BED3', '#A4DDDB', '#19332D',
      '#25562E', '#468232', '#75A743', '#A8CA58', '#D0DA91', '#4D2B32', '#7A4841',
      '#AD7757', '#C09473', '#D7B594', '#E7D5B3', '#341C27', '#602C2C', '#884B2B',
      '#BE772B', '#DE9E41', '#E8C170', '#241527', '#411D31', '#752438', '#A53030',
      '#CF573C', '#DA863E', '#1E1D39', '#402751', '#7A367B', '#A23E8C', '#C65197',
      '#DF84A5', '#090A14', '#10141F', '#151D28', '#202E37', '#394A50', '#577277',
      '#819796', '#A8B5B2', '#C7CFCC', '#EBEDE9'],
  },
  {
    id: 'vinik24',
    name: 'Vinik 24',
    author: 'Vinik',
    colors: ['#000000', '#6F6776', '#9A9A97', '#C5CCB8', '#8B5580', '#C38890', '#A593A5',
      '#666092', '#9A4F50', '#C28D75', '#7CA1C0', '#416AA3', '#8D6268', '#BE955C',
      '#68ACA9', '#387080', '#6E6962', '#93A167', '#6EAA78', '#557064', '#9D9F7F',
      '#7E9E99', '#5D6872', '#433455'],
  },
];

/** Reference palettes looked up by id. */
export const REFERENCE_BY_ID = new Map(REFERENCE_PALETTES.map((p) => [p.id, p]));

/** Mean of the smallest deltaE from each colour in `from` to any colour in `to`. */
function meanNearest(from, to) {
  if (!from.length || !to.length) return Infinity;
  let sum = 0;
  for (const a of from) {
    let best = Infinity;
    for (const b of to) best = Math.min(best, deltaEOK(a, b));
    sum += best;
  }
  return sum / from.length;
}

/**
 * Score how well a palette matches a reference, in deltaE. Lower is closer.
 * `coverage` asks whether the palette can express the reference's colours; `fidelity`
 * asks whether it wastes colours the reference has no use for. `score` is their mean.
 */
export function fitScore(hexes, referenceId) {
  const ref = REFERENCE_BY_ID.get(referenceId);
  if (!ref) throw new Error(`unknown reference palette "${referenceId}"`);
  const mine = hexes.map((h) => rgb8ToOklab(hexToRgb8(h)));
  const theirs = ref.colors.map((h) => rgb8ToOklab(hexToRgb8(h)));
  const coverage = meanNearest(theirs, mine);
  const fidelity = meanNearest(mine, theirs);
  return { id: ref.id, name: ref.name, coverage, fidelity, score: (coverage + fidelity) / 2 };
}

/** Fit scores against every reference palette, closest first. */
export function rankReferences(hexes) {
  return REFERENCE_PALETTES.map((r) => fitScore(hexes, r.id)).sort((a, b) => a.score - b.score);
}
