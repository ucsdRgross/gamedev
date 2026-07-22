// A 3x5 bitmap font, renderer-agnostic.
//
// Used by the headless renderer to label output and by the gallery's text-legibility
// scene. Deliberately tiny: the point of the legibility matrix is to test colour pairs
// at the size pixel art actually uses.

export const GLYPH_WIDTH = 3;
export const GLYPH_HEIGHT = 5;

const GLYPHS = {
  A: '###|#.#|###|#.#|#.#',
  B: '##.|#.#|##.|#.#|##.',
  C: '###|#..|#..|#..|###',
  D: '##.|#.#|#.#|#.#|##.',
  E: '###|#..|##.|#..|###',
  F: '###|#..|##.|#..|#..',
  G: '###|#..|#.#|#.#|###',
  H: '#.#|#.#|###|#.#|#.#',
  I: '###|.#.|.#.|.#.|###',
  J: '..#|..#|..#|#.#|###',
  K: '#.#|#.#|##.|#.#|#.#',
  L: '#..|#..|#..|#..|###',
  M: '#.#|###|###|#.#|#.#',
  N: '##.|#.#|#.#|#.#|#.#',
  O: '###|#.#|#.#|#.#|###',
  P: '###|#.#|###|#..|#..',
  Q: '###|#.#|#.#|###|..#',
  R: '###|#.#|##.|#.#|#.#',
  S: '###|#..|###|..#|###',
  T: '###|.#.|.#.|.#.|.#.',
  U: '#.#|#.#|#.#|#.#|###',
  V: '#.#|#.#|#.#|#.#|.#.',
  W: '#.#|#.#|###|###|#.#',
  X: '#.#|#.#|.#.|#.#|#.#',
  Y: '#.#|#.#|###|.#.|.#.',
  Z: '###|..#|.#.|#..|###',
  0: '###|#.#|#.#|#.#|###',
  1: '.#.|##.|.#.|.#.|###',
  2: '###|..#|###|#..|###',
  3: '###|..#|.##|..#|###',
  4: '#.#|#.#|###|..#|..#',
  5: '###|#..|###|..#|###',
  6: '###|#..|###|#.#|###',
  7: '###|..#|..#|..#|..#',
  8: '###|#.#|###|#.#|###',
  9: '###|#.#|###|..#|###',
  ' ': '...|...|...|...|...',
  '-': '...|...|###|...|...',
  _: '...|...|...|...|###',
  '.': '...|...|...|...|.#.',
  ',': '...|...|...|.#.|#..',
  ':': '...|.#.|...|.#.|...',
  '#': '#.#|###|#.#|###|#.#',
  '/': '..#|..#|.#.|#..|#..',
  '(': '.#.|#..|#..|#..|.#.',
  ')': '.#.|..#|..#|..#|.#.',
  '+': '...|.#.|###|.#.|...',
  '=': '...|###|...|###|...',
  '!': '.#.|.#.|.#.|...|.#.',
  '?': '###|..#|.##|...|.#.',
  '%': '#.#|..#|.#.|#..|#.#',
  '*': '#.#|.#.|#.#|...|...',
  '<': '..#|.#.|#..|.#.|..#',
  '>': '#..|.#.|..#|.#.|#..',
};

const UNKNOWN = '###|#.#|#.#|#.#|###';

/** The five row bitmaps for a character, uppercased; unknown characters draw a box. */
export function glyphRows(ch) {
  return (GLYPHS[String(ch).toUpperCase()] ?? UNKNOWN).split('|');
}

/** Pixel width of a string at the given scale. */
export function textWidth(text, scale = 1, spacing = 1) {
  const n = String(text).length;
  return n === 0 ? 0 : (n * (GLYPH_WIDTH + spacing) - spacing) * scale;
}

/** Pixel height of one line at the given scale. */
export function textHeight(scale = 1) {
  return GLYPH_HEIGHT * scale;
}

/**
 * Draw text by calling `plot(x, y)` for every lit pixel.
 * Keeps the font independent of any particular drawing surface.
 */
export function drawText(text, x, y, scale, plot, spacing = 1) {
  let cursor = x;
  for (const ch of String(text)) {
    const rows = glyphRows(ch);
    for (let ry = 0; ry < GLYPH_HEIGHT; ry++) {
      for (let rx = 0; rx < GLYPH_WIDTH; rx++) {
        if (rows[ry][rx] !== '#') continue;
        for (let sy = 0; sy < scale; sy++) {
          for (let sx = 0; sx < scale; sx++) {
            plot(cursor + rx * scale + sx, y + ry * scale + sy);
          }
        }
      }
    }
    cursor += (GLYPH_WIDTH + spacing) * scale;
  }
}
