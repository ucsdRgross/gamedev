// JASC-PAL (.pal), the Paint Shop Pro palette format.

import { rgb8ToHex } from '../oklch.js';

/** Serialise a palette as a JASC `.pal` file. */
export function toPal(palette) {
  const lines = ['JASC-PAL', '0100', String(palette.entries.length)];
  for (const e of palette.entries) lines.push(e.rgb8.join(' '));
  return `${lines.join('\r\n')}\r\n`;
}

/** Parse a JASC `.pal` file back into an array of `#RRGGBB` strings. */
export function parsePal(text) {
  const lines = String(text).split(/\r?\n/).map((l) => l.trim());
  if (lines[0] !== 'JASC-PAL') throw new Error('not a JASC palette');
  const count = Number(lines[2]);
  if (!Number.isInteger(count) || count < 0) throw new Error('bad JASC colour count');
  const colors = [];
  for (const line of lines.slice(3)) {
    if (!line) continue;
    const m = line.match(/^(\d+)\s+(\d+)\s+(\d+)$/);
    if (!m) continue;
    colors.push(rgb8ToHex([Number(m[1]), Number(m[2]), Number(m[3])]));
    if (colors.length === count) break;
  }
  if (colors.length !== count) throw new Error(`expected ${count} colours, found ${colors.length}`);
  return colors;
}
