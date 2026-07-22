import test from 'node:test';
import assert from 'node:assert/strict';
import zlib from 'node:zlib';
import { encodePNG, decodePNG } from '../tools/png.mjs';

/** Deterministic pixel pattern so failures are reproducible. */
function pattern(w, h) {
  const rgb = new Uint8Array(w * h * 3);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 3;
      rgb[i] = (x * 31 + y * 7) & 0xff;
      rgb[i + 1] = (x * 5 + y * 61) & 0xff;
      rgb[i + 2] = (x * y * 13 + 17) & 0xff;
    }
  }
  return rgb;
}

test('8x8 RGB PNG round-trips to the same pixels', () => {
  const rgb = pattern(8, 8);
  const png = encodePNG(8, 8, rgb);
  const out = decodePNG(png);
  assert.equal(out.width, 8);
  assert.equal(out.height, 8);
  assert.deepEqual(Array.from(out.rgb), Array.from(rgb));
});

test('non-square images round-trip', () => {
  for (const [w, h] of [[1, 1], [17, 3], [3, 17], [64, 1], [1, 64]]) {
    const rgb = pattern(w, h);
    const out = decodePNG(encodePNG(w, h, rgb));
    assert.equal(out.width, w);
    assert.equal(out.height, h);
    assert.deepEqual(Array.from(out.rgb), Array.from(rgb), `${w}x${h}`);
  }
});

test('emits a valid PNG signature and IHDR/IDAT/IEND chunk order', () => {
  const png = encodePNG(4, 4, pattern(4, 4));
  assert.deepEqual(Array.from(png.subarray(0, 8)), [137, 80, 78, 71, 13, 10, 26, 10]);
  const types = [];
  let pos = 8;
  while (pos < png.length) {
    const len = png.readUInt32BE(pos);
    types.push(png.toString('latin1', pos + 4, pos + 8));
    pos += 12 + len;
  }
  assert.deepEqual(types, ['IHDR', 'IDAT', 'IEND']);
});

test('decoder handles every scanline filter type', () => {
  // Hand-build a PNG using each of the 5 filters on successive rows.
  const w = 4;
  const h = 5;
  const stride = w * 3;
  const expected = pattern(w, h);
  const raw = Buffer.alloc(h * (stride + 1));
  const prev = new Uint8Array(stride);
  for (let y = 0; y < h; y++) {
    const filter = y; // 0..4
    raw[y * (stride + 1)] = filter;
    const line = expected.subarray(y * stride, (y + 1) * stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= 3 ? line[x - 3] : 0;
      const b = prev[x];
      const c = x >= 3 ? prev[x - 3] : 0;
      let pred = 0;
      if (filter === 1) pred = a;
      else if (filter === 2) pred = b;
      else if (filter === 3) pred = (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        pred = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      raw[y * (stride + 1) + 1 + x] = (line[x] - pred) & 0xff;
    }
    prev.set(line);
  }

  const crcOf = (type, data) => {
    const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
    let c = -1;
    for (let i = 0; i < body.length; i++) {
      c ^= body[i];
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    return (c ^ -1) >>> 0;
  };
  const mk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crcOf(type, data), 0);
    return Buffer.concat([len, Buffer.from(type, 'latin1'), data, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  const png = Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    mk('IHDR', ihdr),
    mk('IDAT', zlib.deflateSync(raw)),
    mk('IEND', Buffer.alloc(0)),
  ]);

  const out = decodePNG(png);
  assert.deepEqual(Array.from(out.rgb), Array.from(expected));
});

test('rejects mismatched pixel buffer length', () => {
  assert.throws(() => encodePNG(4, 4, new Uint8Array(10)), /expected 48 bytes/);
});
