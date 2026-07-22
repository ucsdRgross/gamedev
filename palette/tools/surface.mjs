// A tiny RGB drawing surface for headless rendering.
//
// Not a Canvas2D implementation — just enough to lay out swatch sheets and, later, the
// test scenes: rectangles, lines, and pixel text. Everything is nearest-neighbour and
// unantialiased, which is what pixel-art output wants anyway.

import { writePNG } from './png.mjs';
import { drawText, textWidth, textHeight } from '../src/core/pixelfont.js';
import { hexToRgb8, relativeLuminance } from '../src/core/oklch.js';

/** A fixed-size RGB pixel buffer with simple drawing operations. */
export class Surface {
  constructor(width, height, background = [16, 16, 20]) {
    this.width = width;
    this.height = height;
    this.data = new Uint8Array(width * height * 3);
    this.clear(background);
  }

  /** Fill the entire surface with one colour. */
  clear(rgb) {
    for (let i = 0; i < this.data.length; i += 3) {
      this.data[i] = rgb[0];
      this.data[i + 1] = rgb[1];
      this.data[i + 2] = rgb[2];
    }
  }

  /** Set one pixel, ignoring out-of-bounds writes. */
  plot(x, y, rgb) {
    const px = Math.floor(x);
    const py = Math.floor(y);
    if (px < 0 || py < 0 || px >= this.width || py >= this.height) return;
    const i = (py * this.width + px) * 3;
    this.data[i] = rgb[0];
    this.data[i + 1] = rgb[1];
    this.data[i + 2] = rgb[2];
  }

  /** Fill an axis-aligned rectangle. */
  rect(x, y, w, h, rgb) {
    for (let dy = 0; dy < h; dy++) {
      for (let dx = 0; dx < w; dx++) this.plot(x + dx, y + dy, rgb);
    }
  }

  /** Stroke a one-pixel rectangle outline. */
  outline(x, y, w, h, rgb) {
    for (let dx = 0; dx < w; dx++) {
      this.plot(x + dx, y, rgb);
      this.plot(x + dx, y + h - 1, rgb);
    }
    for (let dy = 0; dy < h; dy++) {
      this.plot(x, y + dy, rgb);
      this.plot(x + w - 1, y + dy, rgb);
    }
  }

  /** Draw pixel text at the given scale. */
  text(str, x, y, scale, rgb) {
    drawText(str, x, y, scale, (px, py) => this.plot(px, py, rgb));
  }

  /** Copy another surface in at an offset. */
  blit(other, x, y) {
    for (let dy = 0; dy < other.height; dy++) {
      for (let dx = 0; dx < other.width; dx++) {
        const i = (dy * other.width + dx) * 3;
        this.plot(x + dx, y + dy, [other.data[i], other.data[i + 1], other.data[i + 2]]);
      }
    }
  }

  /** Write the surface to a PNG file. */
  save(path) {
    writePNG(path, this.width, this.height, this.data);
  }
}

/** Black or white, whichever reads better on the given background. */
export function readableOn(rgb) {
  return relativeLuminance(rgb) > 0.35 ? [0, 0, 0] : [255, 255, 255];
}

/** Convenience: convert a hex string to the 8-bit triple the surface expects. */
export const rgb = hexToRgb8;

export { textWidth, textHeight };
