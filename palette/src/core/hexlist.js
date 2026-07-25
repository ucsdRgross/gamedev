// Reading a palette out of pasted text (UX_PLAN U5.6 — IMPROVEMENTS item 11).
//
// Colours arrive as text far more often than as files: a Lospec dump, a CSS block, a Discord
// message, the output of somebody's exporter. Every one of those is a list of hex codes with
// arbitrary punctuation around it, so the parser is deliberately permissive about the
// punctuation and strict about the tokens.
//
// **The one rule worth explaining**: a bare (unprefixed) token must be six or eight digits.
// The three-digit CSS shorthand is only accepted with a `#`, because `add`, `bee`, `cab`,
// `dad`, `fad`, `fee` and a hundred other English words are valid three-digit hex — without
// that rule, pasting a paragraph of prose yields a palette. With it, prose yields nothing.

import { hexToRgb8, rgb8ToOklab } from './oklch.js';
import { externalPalette } from './recolor/swatches.js';

// Punctuation, whitespace, quotes, `0x`, CSS syntax — anything that is not part of a hex
// token separates two of them. Splitting on the complement means the caller never has to say
// what the separator was.
const SEPARATOR = /[^#0-9a-fA-F]+/;

/** Expand `abc` → `aabbcc`, drop the alpha from an 8-digit token, uppercase the rest. */
function normalize(digits) {
  const d = digits.length <= 4
    ? digits.slice(0, 3).split('').map((c) => c + c).join('')
    : digits.slice(0, 6);
  return `#${d.toUpperCase()}`;
}

/**
 * Every colour in a blob of text, as `#RRGGBB`, in the order it first appeared.
 *
 * Duplicates are dropped: a CSS file naming the same colour in four rules is one colour, and
 * a palette with the same swatch four times is not what anybody pasted it to get.
 */
export function parseHexList(text, { max = 256 } = {}) {
  const out = [];
  const seen = new Set();
  for (const raw of String(text || '').split(SEPARATOR)) {
    if (!raw) continue;
    const hashed = raw.startsWith('#');
    const digits = hashed ? raw.slice(1) : raw;
    if (!/^[0-9a-fA-F]+$/.test(digits)) continue;
    const ok = hashed
      ? digits.length === 3 || digits.length === 4 || digits.length === 6 || digits.length === 8
      : digits.length === 6 || digits.length === 8;
    if (!ok) continue;
    const hex = normalize(digits);
    if (seen.has(hex)) continue;
    seen.add(hex);
    out.push(hex);
    if (out.length >= max) break;
  }
  return out;
}

/**
 * Turn parsed hexes into the external-palette shape the recolour engine and the compare view
 * take — the same shape `extractPalette` produces from an image, so a pasted palette is a
 * recolour target on exactly the same terms as a loaded one.
 */
export function hexListPalette(name, hexes) {
  const colors = hexes.map((hex) => {
    const rgb8 = hexToRgb8(hex);
    return { hex, rgb8, lab: rgb8ToOklab(rgb8) };
  });
  return externalPalette(name, { colors });
}
