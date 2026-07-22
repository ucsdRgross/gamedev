// A DOM-free RGB pixel buffer and the drawing primitives the gallery scenes use
// (ARCHITECTURE §8 decision). Scenes draw into a small logical Raster; the browser blits
// it to a canvas via `toImageData`, and the headless renderer hands `rows()` to the PNG
// encoder. Keeping the surface in core is what lets the same scene code run both places.
//
// Colours are `[r, g, b]` integer triples throughout, matching Entry.rgb8, so scenes can
// pass palette entries straight in.

import { hexToRgb8 } from './oklch.js';
import { drawText } from './pixelfont.js';

/** A width×height RGB8 pixel buffer with pixel-art drawing primitives. */
export class Raster {
  constructor(width, height, fill = [0, 0, 0]) {
    this.w = width | 0;
    this.h = height | 0;
    this.data = new Uint8ClampedArray(this.w * this.h * 3);
    if (fill) this.clear(fill);
  }

  /** Fill the whole buffer with one colour. */
  clear(rgb) {
    const [r, g, b] = rgb;
    for (let i = 0; i < this.data.length; i += 3) {
      this.data[i] = r; this.data[i + 1] = g; this.data[i + 2] = b;
    }
    return this;
  }

  /** Set one pixel, ignoring out-of-bounds writes. */
  set(x, y, rgb) {
    x |= 0; y |= 0;
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const i = (y * this.w + x) * 3;
    this.data[i] = rgb[0]; this.data[i + 1] = rgb[1]; this.data[i + 2] = rgb[2];
  }

  /** Read one pixel as `[r, g, b]`; edge-clamped so filters never read past the border. */
  get(x, y) {
    x = x < 0 ? 0 : x >= this.w ? this.w - 1 : x | 0;
    y = y < 0 ? 0 : y >= this.h ? this.h - 1 : y | 0;
    const i = (y * this.w + x) * 3;
    return [this.data[i], this.data[i + 1], this.data[i + 2]];
  }

  /** Fill an axis-aligned rectangle (clipped to the buffer). */
  rect(x, y, w, h, rgb) {
    const x0 = Math.max(0, x | 0);
    const y0 = Math.max(0, y | 0);
    const x1 = Math.min(this.w, (x | 0) + (w | 0));
    const y1 = Math.min(this.h, (y | 0) + (h | 0));
    const [r, g, b] = rgb;
    for (let py = y0; py < y1; py++) {
      let i = (py * this.w + x0) * 3;
      for (let px = x0; px < x1; px++) {
        this.data[i] = r; this.data[i + 1] = g; this.data[i + 2] = b; i += 3;
      }
    }
  }

  /** Stroke a one-pixel rectangle outline. */
  outline(x, y, w, h, rgb) {
    this.rect(x, y, w, 1, rgb);
    this.rect(x, y + h - 1, w, 1, rgb);
    this.rect(x, y, 1, h, rgb);
    this.rect(x + w - 1, y, 1, h, rgb);
  }

  /** Draw a line with Bresenham's algorithm. */
  line(x0, y0, x1, y1, rgb) {
    x0 |= 0; y0 |= 0; x1 |= 0; y1 |= 0;
    const dx = Math.abs(x1 - x0);
    const dy = -Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1;
    const sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      this.set(x0, y0, rgb);
      if (x0 === x1 && y0 === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }

  /** Fill a disc of the given radius centred on (cx, cy). */
  disc(cx, cy, radius, rgb) {
    const r2 = radius * radius;
    for (let dy = -radius; dy <= radius; dy++) {
      for (let dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy <= r2) this.set(cx + dx, cy + dy, rgb);
      }
    }
  }

  /** Draw pixel-font text; unknown glyphs render as a box. */
  text(str, x, y, scale, rgb) {
    drawText(str, x, y, scale, (px, py) => this.set(px, py, rgb));
  }

  /** Copy another raster in at (x, y). */
  blit(src, x, y) {
    for (let sy = 0; sy < src.h; sy++) {
      for (let sx = 0; sx < src.w; sx++) {
        this.set(x + sx, y + sy, src.get(sx, sy));
      }
    }
  }

  /** A new raster scaled up by an integer factor with nearest-neighbour sampling. */
  scaled(factor) {
    const f = Math.max(1, factor | 0);
    const out = new Raster(this.w * f, this.h * f, null);
    for (let y = 0; y < this.h; y++) {
      for (let x = 0; x < this.w; x++) {
        const c = this.get(x, y);
        out.rect(x * f, y * f, f, f, c);
      }
    }
    return out;
  }

  /** RGBA `Uint8ClampedArray` for a browser `ImageData` (alpha fixed at 255). */
  toImageData(ImageDataCtor) {
    const rgba = new Uint8ClampedArray(this.w * this.h * 4);
    for (let p = 0, q = 0; p < this.data.length; p += 3, q += 4) {
      rgba[q] = this.data[p]; rgba[q + 1] = this.data[p + 1];
      rgba[q + 2] = this.data[p + 2]; rgba[q + 3] = 255;
    }
    return ImageDataCtor ? new ImageDataCtor(rgba, this.w, this.h) : rgba;
  }

  /** Rows of `[r,g,b]` arrays, the shape the PNG encoder in tools/png.mjs consumes. */
  rows() {
    const out = [];
    for (let y = 0; y < this.h; y++) {
      const row = [];
      for (let x = 0; x < this.w; x++) row.push(this.get(x, y));
      out.push(row);
    }
    return out;
  }
}

/** Coerce a colour argument (hex string, Entry, or `[r,g,b]`) to an `[r,g,b]` triple. */
export function toRgb(c) {
  if (typeof c === 'string') return hexToRgb8(c);
  if (Array.isArray(c)) return c;
  if (c && c.rgb8) return c.rgb8;
  if (c && typeof c.hex === 'string') return hexToRgb8(c.hex);
  return [0, 0, 0];
}
