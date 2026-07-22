// GIF decode and encode (PLAN §19.2, task 5.8).
//
// The decoder is checked against **bytes this repository's encoder did not produce** — a
// GIF written out literally in `HAND_WRITTEN` below, with its LZW stream built by hand from
// literal codes. Testing a decoder only against its own encoder proves the pair agree with
// each other, which is exactly the thing that can be wrong while both are broken.
//
// The round trip is then asserted on top of that, because that is what the recolour path
// actually does: decode an animation, recolour every frame, write it back out.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decodeGif, encodeGif, lzwDecode, lzwEncode } from '../src/core/gif.js';
import { recolorFrames, recolorImage } from '../src/core/recolor/index.js';
import { generatePalette } from '../src/core/generate.js';
import { rgb8ToHex } from '../src/core/oklch.js';
import { Raster } from '../src/core/raster.js';

/**
 * A 4×4, two-frame, two-colour GIF assembled byte by byte.
 *
 * The LZW payload uses literal codes only (clear, then one code per pixel, then end-of-
 * information), which is a valid stream any decoder must accept. Frame 1 is a red left
 * half on black; frame 2 inverts it. Frame delays are 20 and 50 hundredths of a second.
 */
function handWritten() {
  const bytes = [];
  const push = (...v) => bytes.push(...v);
  const u16 = (v) => push(v & 255, (v >> 8) & 255);

  push(0x47, 0x49, 0x46, 0x38, 0x39, 0x61); // GIF89a
  u16(4); u16(4);
  push(0x80, 0, 0); // global table of 2, background 0, aspect 0
  push(0, 0, 0); // colour 0: black
  push(255, 0, 0); // colour 1: red

  // NETSCAPE looping extension.
  push(0x21, 0xff, 11, ...[...'NETSCAPE2.0'].map((c) => c.charCodeAt(0)), 3, 1, 0, 0, 0);

  const frame = (pixels, delayCs) => {
    push(0x21, 0xf9, 4, 0);
    u16(delayCs);
    push(0, 0);
    push(0x2c); u16(0); u16(0); u16(4); u16(4); push(0);
    push(2); // LZW minimum code size: clear=4, eoi=5, codes are 3 bits
    const data = literalLzw(pixels, 2);
    push(data.length, ...data, 0);
  };

  const left = [];
  const right = [];
  for (let y = 0; y < 4; y++) {
    for (let x = 0; x < 4; x++) {
      left.push(x < 2 ? 1 : 0);
      right.push(x < 2 ? 0 : 1);
    }
  }
  frame(left, 20);
  frame(right, 50);
  push(0x3b);
  return Uint8Array.from(bytes);
}

/**
 * A legal LZW stream that uses literal codes only, written independently of `lzwEncode` so
 * the decoder is not being tested against itself.
 *
 * A decoder grows its dictionary — and therefore its code width — whether or not the
 * encoder uses the new entries, so "literals only" is not by itself enough to keep the
 * width fixed. Emitting a clear code every two data codes resets the table before it can
 * reach the boundary, which keeps every code exactly `minCodeSize + 1` bits wide and the
 * stream trivially readable by hand.
 */
function literalLzw(indices, minCodeSize) {
  const clear = 1 << minCodeSize;
  const eoi = clear + 1;
  const codeSize = minCodeSize + 1;
  const codes = [clear];
  indices.forEach((v, i) => {
    if (i > 0 && i % 2 === 0) codes.push(clear);
    codes.push(v);
  });
  codes.push(eoi);

  const out = [];
  let bits = 0;
  let count = 0;
  for (const code of codes) {
    bits |= code << count;
    count += codeSize;
    while (count >= 8) {
      out.push(bits & 255);
      bits >>>= 8;
      count -= 8;
    }
  }
  if (count > 0) out.push(bits & 255);
  return out;
}

const HAND_WRITTEN = handWritten();

test('a hand-written GIF decodes to the right frames, size and colours', () => {
  const gif = decodeGif(HAND_WRITTEN);
  assert.equal(gif.width, 4);
  assert.equal(gif.height, 4);
  assert.equal(gif.frames.length, 2);
  assert.equal(gif.loopCount, 0);

  for (const f of gif.frames) {
    assert.equal(f.image.w, 4);
    assert.equal(f.image.h, 4);
  }
  assert.deepEqual(gif.frames[0].image.get(0, 0), [255, 0, 0]);
  assert.deepEqual(gif.frames[0].image.get(3, 0), [0, 0, 0]);
  assert.deepEqual(gif.frames[1].image.get(0, 0), [0, 0, 0]);
  assert.deepEqual(gif.frames[1].image.get(3, 0), [255, 0, 0]);
});

test('frame delays are decoded, with the browser clamp on absurdly short ones', () => {
  const gif = decodeGif(HAND_WRITTEN);
  assert.equal(gif.frames[0].delayMs, 200);
  assert.equal(gif.frames[1].delayMs, 500);

  // A delay of 0 or 1 hundredths means "as fast as possible"; every browser shows it at
  // 100 ms, so a recoloured animation has to play at the speed the original is seen at.
  const fast = Uint8Array.from(HAND_WRITTEN);
  const at = HAND_WRITTEN.indexOf(0xf9);
  fast[at + 3] = 0;
  fast[at + 4] = 0;
  assert.equal(decodeGif(fast).frames[0].delayMs, 100);
});

test('a non-GIF is refused', () => {
  assert.throws(() => decodeGif(Uint8Array.from([1, 2, 3, 4, 5, 6, 7, 8])), /not a GIF/);
});

test('LZW round-trips over data that forces the dictionary to grow and reset', () => {
  // Long, structured, and highly repetitive, so the encoder crosses every code-width
  // boundary and eventually fills the table — where an off-by-one shows up as garbage
  // partway through rather than as an immediate failure.
  const n = 40000;
  for (const minCodeSize of [2, 4, 8]) {
    const range = 1 << minCodeSize;
    const indices = new Uint8Array(n);
    for (let i = 0; i < n; i++) indices[i] = ((i % 7) + ((i / 97) | 0) % 3) % range;
    const encoded = lzwEncode(indices, minCodeSize);
    const decoded = lzwDecode(encoded, minCodeSize, n);
    assert.deepEqual([...decoded], [...indices], `minCodeSize ${minCodeSize} did not round-trip`);
  }
});

test('an index too large for the code size is refused, not silently truncated', () => {
  assert.throws(() => lzwEncode(Uint8Array.from([0, 1, 9]), 2), /larger minimum code size/);
});

test('LZW round-trips random data, which compresses badly and grows differently', () => {
  let seed = 987654321;
  const rand = () => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed;
  };
  const n = 20000;
  const indices = new Uint8Array(n);
  for (let i = 0; i < n; i++) indices[i] = rand() % 16;
  const encoded = lzwEncode(indices, 4);
  assert.deepEqual([...lzwDecode(encoded, 4, n)], [...indices]);
});

test('an encoded animation decodes back to the same pixels and delays', () => {
  const palette = [[10, 10, 20], [200, 40, 60], [240, 230, 190], [40, 160, 120]];
  const frames = [];
  for (let f = 0; f < 5; f++) {
    const img = new Raster(12, 9, null);
    for (let y = 0; y < 9; y++) {
      for (let x = 0; x < 12; x++) img.set(x, y, palette[(x + y + f) % palette.length]);
    }
    frames.push({ image: img, delayMs: 80 + f * 10 });
  }

  const gif = decodeGif(encodeGif(frames, palette));
  assert.equal(gif.width, 12);
  assert.equal(gif.height, 9);
  assert.equal(gif.frames.length, frames.length);
  gif.frames.forEach((got, i) => {
    assert.deepEqual([...got.image.data], [...frames[i].image.data], `frame ${i} differs`);
    assert.equal(got.delayMs, frames[i].delayMs, `frame ${i} delay differs`);
  });
});

test('a single-frame encode is a still GIF and still round-trips', () => {
  const palette = [[0, 0, 0], [255, 255, 255]];
  const img = new Raster(7, 5, null);
  for (let y = 0; y < 5; y++) for (let x = 0; x < 7; x++) img.set(x, y, palette[(x * y) % 2]);
  const gif = decodeGif(encodeGif([{ image: img, delayMs: 100 }], palette));
  assert.equal(gif.frames.length, 1);
  assert.deepEqual([...gif.frames[0].image.data], [...img.data]);
});

test('palette sizes from 2 to 256 all encode and decode', () => {
  for (const k of [2, 3, 5, 16, 17, 255, 256]) {
    const palette = [];
    for (let i = 0; i < k; i++) palette.push([i & 255, (i * 7) & 255, (i * 13) & 255]);
    const img = new Raster(20, 20, null);
    for (let y = 0; y < 20; y++) for (let x = 0; x < 20; x++) img.set(x, y, palette[(x * 20 + y) % k]);
    const gif = decodeGif(encodeGif([{ image: img, delayMs: 100 }], palette));
    assert.deepEqual([...gif.frames[0].image.data], [...img.data], `k=${k}`);
  }
});

test('encoding refuses input it cannot represent', () => {
  const img = new Raster(2, 2, [1, 2, 3]);
  assert.throws(() => encodeGif([], [[0, 0, 0]]), /no frames/);
  assert.throws(() => encodeGif([{ image: img }], []), /empty palette/);
  assert.throws(() => encodeGif([{ image: img }], [[9, 9, 9]]), /not in the palette/);
  const tooMany = [];
  for (let i = 0; i < 257; i++) tooMany.push([i & 255, 0, 0]);
  assert.throws(() => encodeGif([{ image: img }], tooMany), /at most 256/);
});

test('a decoded frame recolours like any other image', () => {
  const gif = decodeGif(HAND_WRITTEN);
  const p = generatePalette({ color_count: 16 });
  const allowed = new Set(p.entries.map((e) => e.hex));
  const out = recolorImage(gif.frames[0].image, p, {});
  assert.equal(out.mode, 'indexed');
  for (let i = 0; i < out.image.data.length; i += 3) {
    assert.ok(allowed.has(rgb8ToHex([out.image.data[i], out.image.data[i + 1], out.image.data[i + 2]])));
  }
});

test('recolouring an animation keeps one source colour on one target in every frame', () => {
  // The animated form of the property `indexed.js` exists for. Deciding per frame lets a
  // colour that changes rank between frames land differently in each, which reads on screen
  // as the palette flickering — so the mapping is built from all the frames at once.
  const palette = [[10, 10, 20], [220, 40, 60], [240, 230, 190]];
  const frames = [];
  for (let f = 0; f < 4; f++) {
    const img = new Raster(10, 6, null);
    for (let y = 0; y < 6; y++) {
      for (let x = 0; x < 10; x++) {
        // Each colour's share of the picture changes frame to frame, so any per-frame
        // decision would be tempted to move it.
        img.set(x, y, palette[(x + f * 3 < 5 ? 0 : (y + f) % 2 ? 1 : 2)]);
      }
    }
    frames.push({ image: img, delayMs: 100 });
  }

  const p = generatePalette({ color_count: 12 });
  const out = recolorFrames(frames, p, {});
  assert.equal(out.frames.length, frames.length);

  const seen = new Map();
  out.frames.forEach((got, fi) => {
    const src = frames[fi].image;
    for (let i = 0; i < src.data.length; i += 3) {
      const from = rgb8ToHex([src.data[i], src.data[i + 1], src.data[i + 2]]);
      const to = rgb8ToHex([got.image.data[i], got.image.data[i + 1], got.image.data[i + 2]]);
      if (!seen.has(from)) seen.set(from, to);
      else assert.equal(seen.get(from), to, `${from} moved between frames (frame ${fi})`);
    }
  });
  assert.equal(seen.size, palette.length, 'every source colour should have been seen');
});

test('animated mode selection sees every frame, not just the first', () => {
  // A colour that appears only in a late frame still counts. The earlier bug shape here
  // would be building the mapping from frame 0 alone and then hitting an unmapped colour.
  const palette = generatePalette({ color_count: 12 });
  const frames = [];
  for (let f = 0; f < 4; f++) {
    const img = new Raster(8, 8, [10, 10, 10]);
    // A unique colour introduced in each frame, so frame 0 undercounts the animation.
    img.set(f, 0, [f * 60 + 20, 200 - f * 40, 90]);
    frames.push({ image: img, delayMs: 100 });
  }
  const out = recolorFrames(frames, palette, {});
  const allowed = new Set(palette.entries.map((e) => e.hex));
  for (const fr of out.frames) {
    for (let i = 0; i < fr.image.data.length; i += 3) {
      assert.ok(allowed.has(rgb8ToHex([fr.image.data[i], fr.image.data[i + 1], fr.image.data[i + 2]])));
    }
  }
  // The count is over the union of frames, so it exceeds any single frame's.
  assert.ok(out.unique >= 5, `expected the whole-animation colour count, got ${out.unique}`);
});

test('a recoloured animation survives the encode/decode round trip', () => {
  const gif = decodeGif(HAND_WRITTEN);
  const p = generatePalette({ color_count: 8 });
  const out = recolorFrames(gif.frames, p, {});
  const bytes = encodeGif(out.frames, p.entries.map((e) => e.rgb8));
  const back = decodeGif(bytes);
  assert.equal(back.frames.length, out.frames.length);
  back.frames.forEach((got, i) => {
    assert.deepEqual([...got.image.data], [...out.frames[i].image.data], `frame ${i}`);
    assert.equal(got.delayMs, out.frames[i].delayMs);
  });
});

test('encoding is deterministic', () => {
  const palette = [[0, 0, 0], [255, 0, 0], [0, 255, 0]];
  const img = new Raster(9, 9, null);
  for (let y = 0; y < 9; y++) for (let x = 0; x < 9; x++) img.set(x, y, palette[(x + y) % 3]);
  const a = encodeGif([{ image: img, delayMs: 60 }], palette);
  const b = encodeGif([{ image: img, delayMs: 60 }], palette);
  assert.deepEqual([...a], [...b]);
});
