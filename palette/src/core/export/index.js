// Export registry — one entry per downloadable format.

import { toGpl } from './gpl.js';
import { toPal } from './pal.js';
import { toHex } from './hex.js';
import { toLospec } from './lospec.js';
import { toCss } from './css.js';
import { toJson } from './json.js';
import { toTres } from './tres.js';
import { toPngStrip } from './png.js';

/** Every export format, in the order the UI lists them. */
export const EXPORTERS = [
  {
    id: 'tres', label: 'Godot .tres', extension: 'tres', mime: 'text/plain', binary: false,
    run: (palette, opts) => toTres(palette, opts),
  },
  {
    id: 'png', label: 'PNG strip', extension: 'png', mime: 'image/png', binary: true,
    run: (palette, opts) => toPngStrip(palette, opts),
  },
  {
    id: 'gpl', label: 'GIMP .gpl (Aseprite)', extension: 'gpl', mime: 'text/plain', binary: false,
    run: (palette, opts) => toGpl(palette, opts),
  },
  {
    id: 'pal', label: 'JASC .pal', extension: 'pal', mime: 'text/plain', binary: false,
    run: (palette) => toPal(palette),
  },
  {
    id: 'hex', label: 'Hex list', extension: 'hex', mime: 'text/plain', binary: false,
    run: (palette) => toHex(palette),
  },
  {
    id: 'json', label: 'JSON (round-trips)', extension: 'json', mime: 'application/json', binary: false,
    run: (palette, opts) => toJson(palette, opts),
  },
  {
    id: 'css', label: 'CSS custom properties', extension: 'css', mime: 'text/css', binary: false,
    run: (palette, opts) => toCss(palette, opts),
  },
  {
    id: 'lospec', label: 'Lospec hex', extension: 'txt', mime: 'text/plain', binary: false,
    run: (palette) => toLospec(palette),
  },
];

/** Exporters looked up by id. */
export const EXPORTER_BY_ID = new Map(EXPORTERS.map((e) => [e.id, e]));

/** Run one exporter by id, returning a string or a Uint8Array. */
export function runExport(id, palette, opts = {}) {
  const exporter = EXPORTER_BY_ID.get(id);
  if (!exporter) throw new Error(`unknown export format "${id}"`);
  return exporter.run(palette, opts);
}

export { toGpl, toPal, toHex, toLospec, toCss, toJson, toTres, toPngStrip };
