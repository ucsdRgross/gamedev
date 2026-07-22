// Lospec-compatible list: bare uppercase hex, one per line, no `#`.

/** Serialise a palette in the form Lospec's palette upload accepts. */
export function toLospec(palette) {
  return `${palette.entries.map((e) => e.hex.slice(1)).join('\n')}\n`;
}

/** Parse a Lospec hex list back into `#RRGGBB` strings. */
export function parseLospec(text) {
  return String(text)
    .split(/\r?\n/)
    .map((l) => l.trim().replace(/^#/, ''))
    .filter(Boolean)
    .map((l) => {
      if (!/^[0-9a-fA-F]{6}$/.test(l)) throw new Error(`bad Lospec line "${l}"`);
      return `#${l.toUpperCase()}`;
    });
}
