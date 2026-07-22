// GIMP palette (.gpl) — read natively by Aseprite.

import { hexToRgb8, rgb8ToHex } from '../oklch.js';

/** Serialise a palette as a GIMP `.gpl` file. */
export function toGpl(palette, { name = 'Pixel Palette', columns = 8 } = {}) {
  const lines = ['GIMP Palette', `Name: ${name}`, `Columns: ${columns}`, '#'];
  for (const e of palette.entries) {
    const [r, g, b] = e.rgb8;
    lines.push(`${String(r).padStart(3)} ${String(g).padStart(3)} ${String(b).padStart(3)}\t${e.role}`);
  }
  return `${lines.join('\n')}\n`;
}

/** Parse a `.gpl` file back into `{ name, colors, names }`. */
export function parseGpl(text) {
  const lines = String(text).split(/\r?\n/);
  if (!lines[0]?.startsWith('GIMP Palette')) throw new Error('not a GIMP palette');
  let name = '';
  const colors = [];
  const names = [];
  for (const line of lines.slice(1)) {
    if (line.startsWith('Name:')) {
      name = line.slice(5).trim();
      continue;
    }
    if (!line.trim() || line.startsWith('#') || line.startsWith('Columns:')) continue;
    const m = line.match(/^\s*(\d+)\s+(\d+)\s+(\d+)\s*(?:\t(.*))?$/);
    if (!m) continue;
    colors.push(rgb8ToHex([Number(m[1]), Number(m[2]), Number(m[3])]));
    names.push(m[4]?.trim() ?? '');
  }
  return { name, colors, names };
}

/** Round-trip helper: the 8-bit colours a `.gpl` file describes. */
export function gplColors(text) {
  return parseGpl(text).colors.map(hexToRgb8);
}
