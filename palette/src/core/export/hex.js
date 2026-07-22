// Plain hex list (.hex) — one `#RRGGBB` per line.

/** Serialise a palette as one `#RRGGBB` per line. */
export function toHex(palette) {
  return `${palette.entries.map((e) => e.hex).join('\n')}\n`;
}

/** Parse a hex list, tolerating a leading `#`, blank lines and `//` comments. */
export function parseHex(text) {
  return String(text)
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('//'))
    .map((l) => {
      const m = l.replace(/^#/, '').match(/^([0-9a-fA-F]{6})$/);
      if (!m) throw new Error(`bad hex line "${l}"`);
      return `#${m[1].toUpperCase()}`;
    });
}
