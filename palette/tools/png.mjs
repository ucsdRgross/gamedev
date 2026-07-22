// Minimal PNG encoder/decoder for headless rendering and tests.
// Node-only: uses node:zlib. Browser-safe PNG writing lives in src/core/export/png.js.

import zlib from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

let CRC_TABLE = null;

/** Build (once) the CRC-32 lookup table used by PNG chunk checksums. */
function crcTable() {
  if (CRC_TABLE) return CRC_TABLE;
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  CRC_TABLE = t;
  return t;
}

/** CRC-32 of a buffer, as an unsigned 32-bit integer. */
function crc32(buf) {
  const t = crcTable();
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = t[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

/** Assemble one length-prefixed, CRC-suffixed PNG chunk. */
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

/** Encode raw 8-bit RGB pixel data (length w*h*3) as an 8-bit truecolour PNG buffer. */
export function encodePNG(width, height, rgb) {
  if (rgb.length !== width * height * 3) {
    throw new Error(`encodePNG: expected ${width * height * 3} bytes, got ${rgb.length}`);
  }
  const stride = width * 3;
  const raw = Buffer.alloc(height * (stride + 1));
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0; // filter type: None
    for (let x = 0; x < stride; x++) raw[y * (stride + 1) + 1 + x] = rgb[y * stride + x];
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // colour type: truecolour
  ihdr[10] = 0; // compression
  ihdr[11] = 0; // filter
  ihdr[12] = 0; // interlace
  return Buffer.concat([
    SIGNATURE,
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/** Paeth predictor from the PNG filtering spec. */
function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/** Decode an 8-bit RGB or RGBA PNG buffer to `{ width, height, rgb }` (alpha discarded). */
export function decodePNG(buf) {
  if (!buf.subarray(0, 8).equals(SIGNATURE)) throw new Error('decodePNG: bad signature');
  let pos = 8;
  let width = 0;
  let height = 0;
  let channels = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('latin1', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      if (data[8] !== 8) throw new Error('decodePNG: only 8-bit depth supported');
      if (data[9] === 2) channels = 3;
      else if (data[9] === 6) channels = 4;
      else throw new Error(`decodePNG: unsupported colour type ${data[9]}`);
      if (data[12] !== 0) throw new Error('decodePNG: interlacing not supported');
    } else if (type === 'IDAT') {
      idat.push(Buffer.from(data));
    } else if (type === 'IEND') {
      break;
    }
    pos += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = new Uint8Array(width * height * 3);
  let prev = new Uint8Array(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = new Uint8Array(stride);
    for (let x = 0; x < stride; x++) {
      const rawByte = raw[y * (stride + 1) + 1 + x];
      const a = x >= channels ? line[x - channels] : 0;
      const b = prev[x];
      const c = x >= channels ? prev[x - channels] : 0;
      let v;
      if (filter === 0) v = rawByte;
      else if (filter === 1) v = rawByte + a;
      else if (filter === 2) v = rawByte + b;
      else if (filter === 3) v = rawByte + ((a + b) >> 1);
      else if (filter === 4) v = rawByte + paeth(a, b, c);
      else throw new Error(`decodePNG: bad filter ${filter}`);
      line[x] = v & 0xff;
    }
    for (let x = 0; x < width; x++) {
      out[(y * width + x) * 3] = line[x * channels];
      out[(y * width + x) * 3 + 1] = line[x * channels + 1];
      out[(y * width + x) * 3 + 2] = line[x * channels + 2];
    }
    prev = line;
  }
  return { width, height, rgb: out };
}

/** Encode and write an RGB image to disk, creating parent directories as needed. */
export function writePNG(path, width, height, rgb) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, encodePNG(width, height, rgb));
}
