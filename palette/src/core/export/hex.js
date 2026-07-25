// Plain hex list (.hex) — one `#RRGGBB` per line.

import { semanticsBySlot } from '../roles.js';

/**
 * Serialise a palette as one `#RRGGBB` per line, each annotated with what it is.
 *
 * The annotations are `//` comments, which this parser has always skipped and which every
 * other reader of a hex list treats the same way, so the file is still a plain list of colours
 * to anything that only wants the colours. What they buy (UX_PLAN U7.5 — item 20) is a file
 * that says which slot each colour is, which semantic roles landed on it, and — in the header
 * — the `PAL1-` seed that regenerates the whole thing.
 */
export function toHex(palette) {
  const bySlot = semanticsBySlot(palette.semantics || {});
  const lines = [];
  if (palette.seed) {
    lines.push('// Pixel Palette Creator — paste this seed back into the app to edit it:');
    lines.push(`//   ${palette.seed}`);
  }
  for (const e of palette.entries) {
    const roles = bySlot.get(e.id) || [];
    lines.push(`${e.hex}  // ${e.role}${roles.length ? ` · ${roles.join(' ')}` : ''}`);
  }
  return `${lines.join('\n')}\n`;
}

/** Parse a hex list, tolerating a leading `#`, blank lines and `//` comments. */
export function parseHex(text) {
  return String(text)
    .split(/\r?\n/)
    // A comment may follow a colour as well as replace a line: that is how `toHex` says what
    // each colour is for without stopping the file from being a plain list of colours.
    .map((l) => l.replace(/\/\/.*$/, '').trim())
    .filter(Boolean)
    .map((l) => {
      const m = l.replace(/^#/, '').match(/^([0-9a-fA-F]{6})$/);
      if (!m) throw new Error(`bad hex line "${l}"`);
      return `#${m[1].toUpperCase()}`;
    });
}
