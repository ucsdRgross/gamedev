// PNG writer for palette strips and picker layouts.
//
// Browser-safe on purpose: it uses stored (uncompressed) DEFLATE blocks so it needs no
// zlib, which keeps src/core free of Node built-ins. tools/png.mjs is the Node-side
// encoder that actually compresses, and its decoder reads these files fine.

const SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10];

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

/** CRC-32 of a byte array, as an unsigned 32-bit integer. */
function crc32(bytes) {
  const t = crcTable();
  let c = -1;
  for (let i = 0; i < bytes.length; i++) c = t[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

/** Adler-32 checksum, as required by the zlib wrapper. */
function adler32(bytes) {
  let a = 1;
  let b = 0;
  for (let i = 0; i < bytes.length; i++) {
    a = (a + bytes[i]) % 65521;
    b = (b + a) % 65521;
  }
  return ((b << 16) | a) >>> 0;
}

/** Wrap raw bytes in a zlib stream made entirely of stored DEFLATE blocks. */
function deflateStored(bytes) {
  const out = [0x78, 0x01];
  const MAX = 65535;
  for (let i = 0; i < bytes.length || i === 0; i += MAX) {
    const len = Math.min(MAX, bytes.length - i);
    const final = i + len >= bytes.length ? 1 : 0;
    out.push(final, len & 255, (len >> 8) & 255, ~len & 255, (~len >> 8) & 255);
    for (let k = 0; k < len; k++) out.push(bytes[i + k]);
    if (final) break;
  }
  const a = adler32(bytes);
  out.push((a >>> 24) & 255, (a >>> 16) & 255, (a >>> 8) & 255, a & 255);
  return out;
}

/** Assemble one length-prefixed, CRC-suffixed PNG chunk. */
function chunk(type, data) {
  const body = [...type].map((c) => c.charCodeAt(0)).concat(Array.from(data));
  const len = data.length;
  const crc = crc32(body);
  return [
    (len >>> 24) & 255, (len >>> 16) & 255, (len >>> 8) & 255, len & 255,
    ...body,
    (crc >>> 24) & 255, (crc >>> 16) & 255, (crc >>> 8) & 255, crc & 255,
  ];
}

/** Encode raw 8-bit RGB pixel data (length w*h*3) as a PNG byte array. */
export function encodePngRgb(width, height, rgb) {
  if (rgb.length !== width * height * 3) {
    throw new Error(`encodePngRgb: expected ${width * height * 3} bytes, got ${rgb.length}`);
  }
  const stride = width * 3;
  const raw = new Uint8Array(height * (stride + 1));
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0; // filter type: None
    raw.set(rgb.subarray(y * stride, (y + 1) * stride), y * (stride + 1) + 1);
  }
  const ihdr = [
    (width >>> 24) & 255, (width >>> 16) & 255, (width >>> 8) & 255, width & 255,
    (height >>> 24) & 255, (height >>> 16) & 255, (height >>> 8) & 255, height & 255,
    8, 2, 0, 0, 0,
  ];
  return Uint8Array.from([
    ...SIGNATURE,
    ...chunk('IHDR', ihdr),
    ...chunk('IDAT', deflateStored(raw)),
    ...chunk('IEND', []),
  ]);
}

/** Render a palette as a PNG strip: `cell` pixels per colour, `height` rows tall. */
export function toPngStrip(palette, { cell = 1, height = 1 } = {}) {
  const n = palette.entries.length;
  const width = n * cell;
  const rgb = new Uint8Array(width * height * 3);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const c = palette.entries[Math.min(n - 1, Math.floor(x / cell))].rgb8;
      const i = (y * width + x) * 3;
      rgb[i] = c[0];
      rgb[i + 1] = c[1];
      rgb[i + 2] = c[2];
    }
  }
  return encodePngRgb(width, height, rgb);
}
