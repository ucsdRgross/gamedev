// CSS custom properties.

import { rampsOf } from '../analysis.js';

/** Convert a slot id or role name to a CSS-safe custom property suffix. */
function cssName(name) {
  return name.replace(/_/g, '-').replace(/[^a-zA-Z0-9-]/g, '');
}

/** The step word of a structural role — `fg_h2_shadow` → `shadow`. */
function stepWord(role) {
  const at = role.lastIndexOf('_');
  return at < 0 ? role : role.slice(at + 1);
}

/**
 * Serialise a palette as CSS custom properties: structural slots, semantic roles, and the whole
 * ramp each semantic role sits in.
 *
 * That third block is what makes the file usable without the generator open (UX_PLAN U7.5 —
 * item 20). `--pal-fg-h2-shadow` is a name only this tool understands; `--pal-foliage-shadow`
 * is the one a stylesheet wants to write, and it is the same colour. Roles that landed on a
 * neutral, an accent or an anchor have no ramp around them, so they appear in the second block
 * and not the third — naming a ramp that does not exist would be the more useless half-truth.
 */
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

  const rampFor = new Map();
  for (const ramp of rampsOf(palette)) {
    for (const entry of ramp.entries) rampFor.set(entry.id, ramp);
  }
  const ramped = semantic.filter(([, id]) => rampFor.has(id));
  if (ramped.length) {
    lines.push('', '  /* the ramp each semantic role sits in */');
    for (const [name, id] of ramped) {
      for (const entry of rampFor.get(id).entries) {
        lines.push(`  --${prefix}-${cssName(name)}-${cssName(stepWord(entry.role))}: ${entry.hex};`);
      }
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
