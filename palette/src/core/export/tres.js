// Godot resource (.tres) — drop straight into solatro/, necroma/, worldgen/, ….
//
// Emitted as a scriptless Resource carrying `metadata/*` properties, so it loads in any
// Godot 4 project without needing a matching script class to exist first. Read it with
// `load("res://palette.tres").get_meta("colors")`.

/** Escape a string for a Godot resource literal. */
function q(s) {
  return `"${String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

/** Format a float the way Godot writes them: fixed, trimmed, never in exponent form. */
function f(v) {
  const s = v.toFixed(6).replace(/0+$/, '').replace(/\.$/, '.0');
  return s === '-0.0' ? '0.0' : s;
}

/** Serialise a palette as a Godot 4 `.tres` resource with named colour roles. */
export function toTres(palette, { name = 'Pixel Palette' } = {}) {
  const entries = palette.entries;
  const colors = entries
    .flatMap((e) => [...e.rgb8.map((c) => f(c / 255)), '1.0'])
    .join(', ');
  const semantic = Object.entries(palette.semantics)
    .map(([role, id]) => `${q(role)}: ${q(id)}`)
    .join(',\n');

  return `[gd_resource type="Resource" format=3]

[resource]
resource_name = ${q(name)}
metadata/palette_name = ${q(name)}
metadata/seed = ${q(palette.seed)}
metadata/color_count = ${entries.length}
metadata/ids = PackedStringArray(${entries.map((e) => q(e.id)).join(', ')})
metadata/roles = PackedStringArray(${entries.map((e) => q(e.role)).join(', ')})
metadata/hexes = PackedStringArray(${entries.map((e) => q(e.hex)).join(', ')})
metadata/colors = PackedColorArray(${colors})
metadata/semantic_roles = {
${semantic}
}
`;
}

/**
 * Structurally validate an emitted `.tres`, returning `{ colors, ids, roles, hexes }`.
 * Not a general Godot parser — just enough to prove the export is well-formed.
 */
export function parseTres(text) {
  const src = String(text);
  if (!/^\[gd_resource type="Resource" format=3\]\s*$/m.test(src)) {
    throw new Error('missing or malformed gd_resource header');
  }
  if (!/^\[resource\]\s*$/m.test(src)) throw new Error('missing [resource] section');

  const strings = (key) => {
    const m = src.match(new RegExp(`^metadata/${key} = PackedStringArray\\(([^)]*)\\)$`, 'm'));
    if (!m) throw new Error(`missing metadata/${key}`);
    return m[1].trim() === '' ? [] : m[1].split(',').map((s) => JSON.parse(s.trim()));
  };
  const colorMatch = src.match(/^metadata\/colors = PackedColorArray\(([^)]*)\)$/m);
  if (!colorMatch) throw new Error('missing metadata/colors');
  const nums = colorMatch[1].trim() === '' ? [] : colorMatch[1].split(',').map((s) => {
    const v = Number(s.trim());
    if (!Number.isFinite(v) || v < 0 || v > 1) throw new Error(`bad colour component "${s.trim()}"`);
    return v;
  });
  if (nums.length % 4 !== 0) throw new Error('PackedColorArray length is not a multiple of 4');

  const ids = strings('ids');
  const roles = strings('roles');
  const hexes = strings('hexes');
  const count = Number(src.match(/^metadata\/color_count = (\d+)$/m)?.[1]);
  if (![ids.length, roles.length, hexes.length, nums.length / 4].every((n) => n === count)) {
    throw new Error('metadata arrays disagree on the colour count');
  }
  const colors = [];
  for (let i = 0; i < nums.length; i += 4) {
    colors.push([
      Math.round(nums[i] * 255), Math.round(nums[i + 1] * 255), Math.round(nums[i + 2] * 255),
    ]);
    if (nums[i + 3] !== 1) throw new Error('colours must be fully opaque');
  }
  return { count, ids, roles, hexes, colors };
}
