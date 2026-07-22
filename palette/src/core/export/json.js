// JSON export — the only lossless format. Round-trips back into the tool.

import { normalizeParams } from '../params.js';

export const JSON_FORMAT = 'pixel-palette/1';

/** Serialise a palette to JSON: colours, OKLCH values, the parameter set and the seed. */
export function toJson(palette, { name = 'Pixel Palette', indent = 2 } = {}) {
  return `${JSON.stringify({
    format: JSON_FORMAT,
    name,
    seed: palette.seed,
    params: palette.params,
    locks: palette.locks,
    overrides: palette.overrides,
    semantics: palette.semantics,
    warnings: palette.warnings,
    colors: palette.entries.map((e, index) => ({
      index,
      id: e.id,
      role: e.role,
      layer: e.layer,
      hex: e.hex,
      rgb: e.rgb8,
      oklch: {
        L: Number(e.actual.L.toFixed(5)),
        C: Number(e.actual.C.toFixed(5)),
        h: Number(e.actual.h.toFixed(3)),
      },
      locked: e.locked,
      overridden: e.overridden,
    })),
  }, null, indent)}\n`;
}

/** Parse a JSON export back into `{ name, seed, params, locks, overrides, colors }`. */
export function parseJson(text) {
  const data = typeof text === 'string' ? JSON.parse(text) : text;
  if (data.format !== JSON_FORMAT) throw new Error(`unexpected format "${data.format}"`);
  return {
    name: data.name ?? '',
    seed: data.seed ?? '',
    params: normalizeParams(data.params ?? {}),
    locks: data.locks ?? {},
    overrides: data.overrides ?? {},
    semantics: data.semantics ?? {},
    colors: (data.colors ?? []).map((c) => c.hex),
  };
}
