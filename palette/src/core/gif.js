// GIF decode and encode (PLAN §19.2). LZW is pure arithmetic with no platform dependency,
// so both halves live in core and the browser and `node --test` share one implementation.
//
// **The whole animation is the unit**, not one frame (spec changed 2026-07-22 by the repo
// owner). So the decoder returns every frame *already composited* — GIF stores sparse
// patches with disposal rules and transparency, and a caller that recolours a raw patch
// would be recolouring holes. Each frame that comes out is a complete, displayable picture
// with its own delay.
//
// The encoder exists so a recoloured animation can leave the app as an animation. It also
// makes the round trip testable: `encodeGif(decodeGif(bytes))` is checked against the
// original rather than assumed, and the browser's own decoder is checked against ours.
//
// Not supported, deliberately: interlaced *output* (nothing needs it) and per-frame local
// colour tables on encode (one global table is what a recoloured animation always wants,
// since every frame shares the palette). Both are handled on the way *in*.

import { Raster } from './raster.js';

const SIGNATURE = [0x47, 0x49, 0x46]; // "GIF"
const TRAILER = 0x3b;
const EXTENSION = 0x21;
const IMAGE_DESCRIPTOR = 0x2c;
const GRAPHIC_CONTROL = 0xf9;
const APPLICATION = 0xff;
const MAX_CODE = 4096;

/** Interlaced GIFs store rows in four passes; `[startRow, step]` for each. */
const INTERLACE_PASSES = [[0, 8], [4, 8], [2, 4], [1, 2]];

/**
 * Decode a GIF into complete frames.
 * Returns `{ width, height, loopCount, frames: [{ image, delayMs, disposal }] }`.
 */
export function decodeGif(bytes) {
  const buf = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  for (let i = 0; i < 3; i++) {
    if (buf[i] !== SIGNATURE[i]) throw new Error('decodeGif: not a GIF (bad signature)');
  }

  let at = 6; // past "GIF87a" / "GIF89a"
  const width = buf[at] | (buf[at + 1] << 8);
  const height = buf[at + 2] | (buf[at + 3] << 8);
  const packed = buf[at + 4];
  const bgIndex = buf[at + 5];
  at += 7; // + pixel aspect ratio

  let globalTable = null;
  if (packed & 0x80) {
    const size = 2 << (packed & 7);
    globalTable = buf.subarray(at, at + size * 3);
    at += size * 3;
  }

  // The composited canvas, as palette-independent RGB. `previous` backs disposal method 3.
  const background = globalTable ? colorAt(globalTable, bgIndex) : [0, 0, 0];
  let canvas = new Raster(width, height, background);
  const frames = [];
  let loopCount = 0;
  let control = { delayMs: 0, disposal: 0, transparentIndex: -1 };

  while (at < buf.length) {
    const block = buf[at++];
    if (block === TRAILER) break;

    if (block === EXTENSION) {
      const label = buf[at++];
      if (label === GRAPHIC_CONTROL) {
        const size = buf[at++];
        const flags = buf[at];
        control = {
          disposal: (flags >> 2) & 7,
          // GIF stores delay in hundredths of a second. 0 and 1 both mean "as fast as
          // possible" in practice; browsers clamp them to 100 ms, so we do too — otherwise
          // a recoloured animation plays at a speed no one has ever seen it at.
          delayMs: normalizeDelay((buf[at + 1] | (buf[at + 2] << 8)) * 10),
          transparentIndex: flags & 1 ? buf[at + 3] : -1,
        };
        at += size;
        at = skipSubBlocks(buf, at);
      } else if (label === APPLICATION) {
        const size = buf[at++];
        const name = String.fromCharCode(...buf.subarray(at, at + 11));
        at += size;
        if (name.startsWith('NETSCAPE')) {
          // Sub-block: [size=3][1][loop:u16le]
          if (buf[at] >= 3) loopCount = buf[at + 2] | (buf[at + 3] << 8);
        }
        at = skipSubBlocks(buf, at);
      } else {
        // Comment and plain-text extensions are both just sub-block chains — plain text's
        // fixed 12-byte header is itself a length-prefixed block — so one skip covers both.
        at = skipSubBlocks(buf, at);
      }
      continue;
    }

    if (block !== IMAGE_DESCRIPTOR) throw new Error(`decodeGif: unknown block 0x${block.toString(16)}`);

    const left = buf[at] | (buf[at + 1] << 8);
    const top = buf[at + 2] | (buf[at + 3] << 8);
    const fw = buf[at + 4] | (buf[at + 5] << 8);
    const fh = buf[at + 6] | (buf[at + 7] << 8);
    const iflags = buf[at + 8];
    at += 9;

    let table = globalTable;
    if (iflags & 0x80) {
      const size = 2 << (iflags & 7);
      table = buf.subarray(at, at + size * 3);
      at += size * 3;
    }
    if (!table) throw new Error('decodeGif: frame has no colour table');

    const minCodeSize = buf[at++];
    const { data, next } = readSubBlocks(buf, at);
    at = next;
    const indices = lzwDecode(data, minCodeSize, fw * fh);

    const restore = control.disposal === 3 ? cloneRaster(canvas) : null;
    drawFrame(canvas, indices, table, {
      left, top, w: fw, h: fh, interlaced: !!(iflags & 0x40), transparentIndex: control.transparentIndex,
    });
    frames.push({ image: cloneRaster(canvas), delayMs: control.delayMs, disposal: control.disposal });

    if (control.disposal === 2) fillRect(canvas, left, top, fw, fh, background);
    else if (control.disposal === 3 && restore) canvas = restore;
  }

  if (!frames.length) throw new Error('decodeGif: no frames');
  return { width, height, loopCount, frames };
}

/** Browsers clamp 0 and 10 ms delays to 100 ms; matching them keeps playback recognisable. */
function normalizeDelay(ms) {
  return ms <= 10 ? 100 : ms;
}

/** The `i`th colour of a GIF colour table as `[r, g, b]`. */
function colorAt(table, i) {
  const p = i * 3;
  return [table[p] ?? 0, table[p + 1] ?? 0, table[p + 2] ?? 0];
}

/** Skip a chain of length-prefixed sub-blocks, returning the offset just past the terminator. */
function skipSubBlocks(buf, at) {
  while (buf[at]) at += buf[at] + 1;
  return at + 1;
}

/** Concatenate a chain of length-prefixed sub-blocks into one buffer. */
function readSubBlocks(buf, at) {
  const parts = [];
  let total = 0;
  while (buf[at]) {
    const size = buf[at];
    parts.push(buf.subarray(at + 1, at + 1 + size));
    total += size;
    at += size + 1;
  }
  const data = new Uint8Array(total);
  let p = 0;
  for (const part of parts) { data.set(part, p); p += part.length; }
  return { data, next: at + 1 };
}

/** A copy of a Raster, so a composited frame is not aliased by the next one's drawing. */
function cloneRaster(src) {
  const out = new Raster(src.w, src.h, null);
  out.data.set(src.data);
  return out;
}

/** Fill a rectangle of the compositing canvas with one colour (disposal method 2). */
function fillRect(canvas, left, top, w, h, rgb) {
  for (let y = top; y < top + h && y < canvas.h; y++) {
    for (let x = left; x < left + w && x < canvas.w; x++) canvas.set(x, y, rgb);
  }
}

/** Paint one decoded frame onto the compositing canvas, honouring interlace and transparency. */
function drawFrame(canvas, indices, table, { left, top, w, h, interlaced, transparentIndex }) {
  const rows = interlaced ? interlacedRows(h) : null;
  for (let row = 0; row < h; row++) {
    const y = top + (rows ? rows[row] : row);
    if (y < 0 || y >= canvas.h) continue;
    for (let x = 0; x < w; x++) {
      const index = indices[row * w + x];
      if (index === transparentIndex) continue;
      canvas.set(left + x, y, colorAt(table, index));
    }
  }
}

/** Destination row for each stored row of an interlaced frame. */
function interlacedRows(h) {
  const out = new Int32Array(h);
  let n = 0;
  for (const [start, step] of INTERLACE_PASSES) {
    for (let y = start; y < h; y += step) out[n++] = y;
  }
  return out;
}

/**
 * LZW decode to palette indices. The dictionary is kept as flat parallel arrays —
 * `prefix[code]` and `suffix[code]` — rather than growing byte arrays, so no allocation
 * happens per code and a long animation does not spend its time in the garbage collector.
 */
export function lzwDecode(data, minCodeSize, pixelCount) {
  const clear = 1 << minCodeSize;
  const eoi = clear + 1;
  const prefix = new Int32Array(MAX_CODE);
  const suffix = new Uint8Array(MAX_CODE);
  // `first[code]` is the first character of the string `code` expands to, carried forward
  // as entries are added. Walking the prefix chain for it instead is O(string length) per
  // code and turns decoding a large animation into tens of seconds.
  const first = new Uint8Array(MAX_CODE);
  const stack = new Uint8Array(MAX_CODE);
  for (let i = 0; i < clear; i++) { suffix[i] = i; first[i] = i; }

  const out = new Uint8Array(pixelCount);
  let outAt = 0;
  let codeSize = minCodeSize + 1;
  let next = eoi + 1;
  let prev = -1;
  let bit = 0;

  while (outAt < pixelCount) {
    const byte = bit >> 3;
    if (byte >= data.length) break;
    // LSB-first: a code can straddle three bytes at 12 bits wide.
    let code = (data[byte] | (data[byte + 1] << 8) | (data[byte + 2] << 16)) >>> (bit & 7);
    code &= (1 << codeSize) - 1;
    bit += codeSize;

    if (code === clear) {
      codeSize = minCodeSize + 1;
      next = eoi + 1;
      prev = -1;
      continue;
    }
    if (code === eoi) break;

    let top = 0;
    let current = code;
    if (prev === -1) {
      if (code >= clear) throw new Error('decodeGif: first LZW code is not a literal');
    } else {
      if (code > next) throw new Error('decodeGif: corrupt LZW stream');
      if (code === next) {
        // The "code not yet in the table" case: it can only be the previous string plus
        // its own first character, which is what makes LZW self-referential.
        stack[top++] = first[prev];
        current = prev;
      }
      if (next < MAX_CODE) {
        prefix[next] = prev;
        suffix[next] = first[code === next ? prev : code];
        first[next] = first[prev];
        next++;
        if (next === (1 << codeSize) && codeSize < 12) codeSize++;
      }
    }

    while (current >= clear) {
      // A corrupt stream can point a prefix chain at itself; without this the expansion
      // loop never ends and the decoder hangs instead of reporting a bad file.
      if (top >= MAX_CODE) throw new Error('decodeGif: corrupt LZW stream (cyclic prefix)');
      stack[top++] = suffix[current];
      current = prefix[current];
    }
    stack[top++] = suffix[current];
    while (top > 0 && outAt < pixelCount) out[outAt++] = stack[--top];
    prev = code;
  }
  return out;
}

/**
 * Encode frames as an animated GIF. `frames` is `[{ image, delayMs }]` and every image must
 * already contain only colours from `palette` — which is exactly what the recolour pipeline
 * produces, so the encoder never has to quantize and can index by lookup.
 */
export function encodeGif(frames, palette, { loopCount = 0 } = {}) {
  if (!frames.length) throw new Error('encodeGif: no frames');
  if (!palette.length) throw new Error('encodeGif: empty palette');
  if (palette.length > 256) throw new Error('encodeGif: a GIF colour table holds at most 256 colours');

  const { w, h } = frames[0].image;
  const bits = Math.max(1, Math.ceil(Math.log2(palette.length)));
  const tableSize = 1 << bits;
  const lookup = new Map(palette.map((c, i) => [(c[0] << 16) | (c[1] << 8) | c[2], i]));

  const out = [];
  push(out, [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]); // "GIF89a"
  pushU16(out, w);
  pushU16(out, h);
  out.push(0x80 | ((bits - 1) << 4) | (bits - 1)); // global table, colour resolution, size
  out.push(0, 0); // background index, pixel aspect ratio
  for (let i = 0; i < tableSize; i++) {
    const c = palette[i] ?? [0, 0, 0];
    push(out, [c[0], c[1], c[2]]);
  }

  if (frames.length > 1) {
    push(out, [EXTENSION, APPLICATION, 11]);
    push(out, [...'NETSCAPE2.0'].map((ch) => ch.charCodeAt(0)));
    push(out, [3, 1]);
    pushU16(out, loopCount);
    out.push(0);
  }

  for (const frame of frames) {
    const delay = Math.round((frame.delayMs ?? 100) / 10);
    push(out, [EXTENSION, GRAPHIC_CONTROL, 4, 0]); // no transparency, disposal 0
    pushU16(out, delay);
    push(out, [0, 0]); // transparent index, block terminator

    out.push(IMAGE_DESCRIPTOR);
    pushU16(out, 0);
    pushU16(out, 0);
    pushU16(out, frame.image.w);
    pushU16(out, frame.image.h);
    out.push(0); // no local table, not interlaced

    const indices = toIndices(frame.image, lookup);
    const minCodeSize = Math.max(2, bits);
    out.push(minCodeSize);
    writeSubBlocks(out, lzwEncode(indices, minCodeSize));
    out.push(0);
  }

  out.push(TRAILER);
  return Uint8Array.from(out);
}

/** Palette index per pixel; a colour outside the palette is a bug upstream, not a fallback. */
function toIndices(image, lookup) {
  const out = new Uint8Array(image.w * image.h);
  for (let i = 0, p = 0; i < image.data.length; i += 3, p++) {
    const key = (image.data[i] << 16) | (image.data[i + 1] << 8) | image.data[i + 2];
    const index = lookup.get(key);
    if (index === undefined) throw new Error(`encodeGif: colour #${key.toString(16).padStart(6, '0')} is not in the palette`);
    out[p] = index;
  }
  return out;
}

function push(out, bytes) {
  for (const b of bytes) out.push(b);
}

function pushU16(out, v) {
  out.push(v & 255, (v >> 8) & 255);
}

/** Split a byte stream into GIF's 255-byte length-prefixed sub-blocks. */
function writeSubBlocks(out, bytes) {
  for (let at = 0; at < bytes.length; at += 255) {
    const size = Math.min(255, bytes.length - at);
    out.push(size);
    for (let i = 0; i < size; i++) out.push(bytes[at + i]);
  }
}

/**
 * LZW encode palette indices, LSB-first, resetting the dictionary when it fills.
 *
 * The counters here mirror `lzwDecode` exactly — the code width grows when the next free
 * code reaches the current width's capacity, and the table is cleared at 4096. Getting that
 * one step out of sync produces a file that decodes to garbage only partway through, which
 * is why the tests assert a full round trip rather than spot-checking the header.
 */
export function lzwEncode(indices, minCodeSize) {
  const clear = 1 << minCodeSize;
  const eoi = clear + 1;
  const out = [];
  let bits = 0;
  let bitCount = 0;
  let codeSize = minCodeSize + 1;
  let next = eoi + 1;
  let dict = new Map();

  const emit = (code) => {
    bits |= code << bitCount;
    bitCount += codeSize;
    while (bitCount >= 8) {
      out.push(bits & 255);
      bits >>>= 8;
      bitCount -= 8;
    }
  };

  // An index at or above the clear code cannot be written in `minCodeSize` bits at all; it
  // would silently truncate and produce a file that decodes to nonsense.
  for (let i = 0; i < indices.length; i++) {
    if (indices[i] >= clear) throw new Error(`lzwEncode: index ${indices[i]} needs a larger minimum code size than ${minCodeSize}`);
  }

  emit(clear);
  if (!indices.length) {
    emit(eoi);
    if (bitCount > 0) out.push(bits & 255);
    return Uint8Array.from(out);
  }

  let prefix = indices[0];
  for (let i = 1; i < indices.length; i++) {
    const k = indices[i];
    const key = prefix * 256 + k;
    const found = dict.get(key);
    if (found !== undefined) {
      prefix = found;
      continue;
    }
    emit(prefix);
    if (next === MAX_CODE) {
      emit(clear);
      dict = new Map();
      next = eoi + 1;
      codeSize = minCodeSize + 1;
    } else {
      dict.set(key, next++);
      if (next === (1 << codeSize) + 1 && codeSize < 12) codeSize++;
    }
    prefix = k;
  }
  emit(prefix);
  emit(eoi);
  if (bitCount > 0) out.push(bits & 255);
  return Uint8Array.from(out);
}
