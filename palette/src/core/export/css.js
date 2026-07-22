// CSS custom properties.

/** Convert a slot id or role name to a CSS-safe custom property suffix. */
function cssName(name) {
  return name.replace(/_/g, '-').replace(/[^a-zA-Z0-9-]/g, '');
}

/** Serialise a palette as CSS custom properties, structural slots plus semantic roles. */
export function toCss(palette, { prefix = 'pal', selector = ':root' } = {}) {
  const lines = [`${selector} {`];
  for (const e of palette.entries) lines.push(`  --${prefix}-${cssName(e.role)}: ${e.hex};`);
  const byId = new Map(palette.entries.map((e) => [e.id, e.hex]));
  const semantic = Object.entries(palette.semantics);
  if (semantic.length) {
    lines.push('', '  /* semantic roles */');
    for (const [name, id] of semantic) {
      lines.push(`  --${prefix}-${cssName(name)}: ${byId.get(id)};`);
    }
  }
  lines.push('}');
  return `${lines.join('\n')}\n`;
}

/** Parse CSS custom properties back into a property-name -> hex map. */
export function parseCss(text) {
  const out = {};
  for (const m of String(text).matchAll(/--([a-zA-Z0-9-]+)\s*:\s*(#[0-9A-Fa-f]{6})\s*;/g)) {
    out[m[1]] = m[2].toUpperCase();
  }
  return out;
}
