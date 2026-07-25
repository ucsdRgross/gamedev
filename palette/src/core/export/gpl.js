// GIMP palette (.gpl) — read natively by Aseprite.

import { hexToRgb8, rgb8ToHex } from '../oklch.js';

/**
 * Serialise a palette as a GIMP `.gpl` file.
 *
 * The colour lines carry the structural role in the name field, where every reader shows it.
 * The header comments carry the two things that would otherwise be lost the moment the file
 * leaves this tool (UX_PLAN U7.5 — item 20): the semantic role assignments, and the `PAL1-`
 * seed, so an exported palette can always be pasted back into the generator that made it.
 */
export function toGpl(palette, { name = 'Pixel Palette', columns = 8 } = {}) {
  const lines = ['GIMP Palette', `Name: ${name}`, `Columns: ${columns}`];
  if (palette.seed) {
    lines.push('# Pixel Palette Creator — paste this seed back into the app to edit it:', `#   ${palette.seed}`);
  }
  const semantic = Object.entries(palette.semantics || {});
  if (semantic.length) {
    lines.push('# semantic roles:');
    for (const [role, id] of semantic) lines.push(`#   ${role} = ${id}`);
  }
  lines.push('#');
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
