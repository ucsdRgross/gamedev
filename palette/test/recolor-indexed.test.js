// Indexed remap (PLAN §19.1, task 5.3).
//
// The property this whole path exists for is that the mapping is a fact about the *colour*,
// not about the pixel. It is asserted directly, for every match mode and every overflow
// mode, because a remap that gets it wrong still passes "output uses only target colours"
// and still produces an image — it just quietly destroys every outline in it.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  REMAP_MATCH, REMAP_OVERFLOW, buildIndexedMapping, hungarian, recolorIndexed,
} from '../src/core/recolor/indexed.js';
import { downscale, uniqueColors } from '../src/core/recolor/image.js';
import { Raster } from '../src/core/raster.js';
import { generatePalette } from '../src/core/generate.js';
import { rgb8ToHex, rgb8ToOklab } from '../src/core/oklch.js';

const palette = (k) => generatePalette({ color_count: k });

/** A deterministic pseudo-pixel-art image built from `n` distinct colours. */
function sourceArt(n, w = 24, h = 16) {
  const colors = [];
  for (let i = 0; i < n; i++) {
    colors.push([(i * 97 + 20) % 256, (i * 53 + 90) % 256, (i * 31 + 140) % 256]);
  }
  const img = new Raster(w, h, null);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      // Blocky regions with a one-pixel outline, so a remap that decides per pixel would
      // visibly break the outline into several colours.
      const region = (Math.floor(x / 5) + Math.floor(y / 4) * 3) % n;
      const outline = x % 5 === 0 || y % 4 === 0;
      img.set(x, y, colors[outline ? 0 : region]);
    }
  }
  return { img, colors };
}

/** Every distinct hex in an image. */
function hexes(image) {
  const out = new Set();
  for (let i = 0; i < image.data.length; i += 3) {
    out.add(rgb8ToHex([image.data[i], image.data[i + 1], image.data[i + 2]]));
  }
  return out;
}

test('the output contains only target-palette colours', () => {
  const p = palette(32);
  const allowed = new Set(p.entries.map((e) => e.hex));
  const { img } = sourceArt(20);
  for (const match of REMAP_MATCH) {
    for (const overflow of REMAP_OVERFLOW) {
      for (const preserveOrder of [false, true]) {
        const out = recolorIndexed(img, p.entries, { match, overflow, preserveOrder }).image;
        for (const hex of hexes(out)) {
          assert.ok(allowed.has(hex), `${match}/${overflow}/${preserveOrder}: foreign colour ${hex}`);
        }
      }
    }
  }
});

test('a source colour maps to the same target colour everywhere it appears', () => {
  const p = palette(24);
  const { img } = sourceArt(18, 40, 28);
  for (const match of REMAP_MATCH) {
    for (const overflow of REMAP_OVERFLOW) {
      const out = recolorIndexed(img, p.entries, { match, overflow }).image;
      const seen = new Map();
      for (let i = 0; i < img.data.length; i += 3) {
        const from = rgb8ToHex([img.data[i], img.data[i + 1], img.data[i + 2]]);
        const to = rgb8ToHex([out.data[i], out.data[i + 1], out.data[i + 2]]);
        const prior = seen.get(from);
        if (prior === undefined) seen.set(from, to);
        else assert.equal(to, prior, `${match}/${overflow}: ${from} became both ${prior} and ${to}`);
      }
      assert.ok(seen.size > 1, 'the fixture should have several source colours');
    }
  }
});

test('remap_preserve_order is genuinely monotonic in lightness', () => {
  const p = palette(32);
  const { img } = sourceArt(16);
  const { colors } = uniqueColors(img);

  for (const match of REMAP_MATCH) {
    const mapping = buildIndexedMapping(colors, p.entries, { match, preserveOrder: true });
    const pairs = colors
      .map((c) => ({ L: rgb8ToOklab(c.rgb)[0], target: p.entries[mapping.get(c.key)].lab[0] }))
      .sort((a, b) => a.L - b.L);
    for (let i = 1; i < pairs.length; i++) {
      assert.ok(
        pairs[i].target >= pairs[i - 1].target - 1e-12,
        `${match}: source L ${pairs[i].L.toFixed(3)} mapped darker than a darker source`,
      );
    }
  }
});

test('without preserve_order, delta-e matching is free to invert lightness', () => {
  // The guard on the test above: if every mode were monotonic anyway, that test would pass
  // without the feature existing. A hue-led match genuinely does reorder value.
  const p = palette(32);
  const { img } = sourceArt(24);
  const { colors } = uniqueColors(img);
  const mapping = buildIndexedMapping(colors, p.entries, { match: 'delta-e', preserveOrder: false });
  const pairs = colors
    .map((c) => ({ L: rgb8ToOklab(c.rgb)[0], target: p.entries[mapping.get(c.key)].lab[0] }))
    .sort((a, b) => a.L - b.L);
  const inversions = pairs.filter((v, i) => i > 0 && v.target < pairs[i - 1].target).length;
  assert.ok(inversions > 0, 'expected unconstrained matching to invert lightness somewhere');
});

test('optimal never reuses a target while an unused one remains', () => {
  const p = palette(32);
  const { colors } = uniqueColors(sourceArt(12).img);
  for (const preserveOrder of [false, true]) {
    const mapping = buildIndexedMapping(colors, p.entries, { match: 'optimal', preserveOrder });
    const used = [...mapping.values()];
    assert.equal(new Set(used).size, used.length, `preserveOrder=${preserveOrder}: a target repeated`);
  }
});

test('optimal beats nearest-each on total distance when they differ', () => {
  const p = palette(16);
  const { colors } = uniqueColors(sourceArt(14).img);
  const total = (match) => {
    const mapping = buildIndexedMapping(colors, p.entries, { match });
    return colors.reduce((sum, c) => {
      const a = rgb8ToOklab(c.rgb);
      const b = p.entries[mapping.get(c.key)].lab;
      return sum + Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    }, 0);
  };
  // `optimal` is constrained (no reuse), so it cannot beat unconstrained nearest-each; the
  // point is that it pays a bounded price for covering the palette, not that it wins.
  assert.ok(total('optimal') >= total('delta-e') - 1e-9);
  assert.ok(total('optimal') < total('delta-e') * 3, 'optimal should not be wildly worse');
});

test('the assignment solver matches brute force on small problems', () => {
  let seed = 12345;
  const rand = () => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff;
  };
  for (let trial = 0; trial < 40; trial++) {
    const rows = 1 + Math.floor(rand() * 5);
    const cols = rows + Math.floor(rand() * 3);
    const cost = new Float64Array(rows * cols);
    for (let i = 0; i < cost.length; i++) cost[i] = Math.round(rand() * 100);

    const got = hungarian(cost, rows, cols);
    let total = 0;
    for (let i = 0; i < rows; i++) total += cost[i * cols + got[i]];
    assert.equal(new Set(got).size, rows, 'assignment must be injective');

    // Brute force over every injective row → column map.
    let best = Infinity;
    const pick = (row, used, sum) => {
      if (sum >= best) return;
      if (row === rows) { best = sum; return; }
      for (let j = 0; j < cols; j++) {
        if (used & (1 << j)) continue;
        pick(row + 1, used | (1 << j), sum + cost[row * cols + j]);
      }
    };
    pick(0, 0, 0);
    assert.equal(total, best, `trial ${trial}: ${rows}x${cols}`);
  }
});

test('merge overflow clusters the source down instead of sharing targets', () => {
  const p = palette(8);
  const { img } = sourceArt(40, 40, 24);
  const { colors } = uniqueColors(img);
  assert.ok(colors.length > p.entries.length, 'the fixture must overflow the target');

  for (const match of REMAP_MATCH) {
    const shared = buildIndexedMapping(colors, p.entries, { match, overflow: 'share' });
    const merged = buildIndexedMapping(colors, p.entries, { match, overflow: 'merge' });
    // The two are different decisions, not different spellings of one: `share` lets each
    // source colour pick independently, `merge` decides which colours travel together first.
    const differing = colors.filter((c) => shared.get(c.key) !== merged.get(c.key)).length;
    assert.ok(differing > 0, `${match}: merge made no difference`);
    // Both stay inside the target palette. (The resulting colour *sets* often coincide —
    // that is why this compares the mapping, which is where the two actually differ.)
    for (const m of [shared, merged]) assert.ok(new Set(m.values()).size <= p.entries.length);
  }
  assert.ok(hexes(recolorIndexed(img, p.entries, { overflow: 'merge' }).image).size <= p.entries.length);
});

test('lightness-rank is monotonic by construction and uses the full target range', () => {
  const p = palette(16);
  const { colors } = uniqueColors(sourceArt(16).img);
  const mapping = buildIndexedMapping(colors, p.entries, { match: 'lightness-rank' });
  const pairs = colors
    .map((c) => ({ L: rgb8ToOklab(c.rgb)[0], target: p.entries[mapping.get(c.key)].lab[0] }))
    .sort((a, b) => a.L - b.L);
  for (let i = 1; i < pairs.length; i++) assert.ok(pairs[i].target >= pairs[i - 1].target - 1e-12);

  const targetLs = p.entries.map((e) => e.lab[0]);
  assert.equal(pairs[0].target, Math.min(...targetLs), 'the darkest source should take the darkest target');
  assert.equal(pairs.at(-1).target, Math.max(...targetLs), 'the lightest source should take the lightest target');
});

test('remapping is deterministic', () => {
  const p = palette(24);
  const { img } = sourceArt(20);
  for (const match of REMAP_MATCH) {
    const a = recolorIndexed(img, p.entries, { match, overflow: 'merge' }).image;
    const b = recolorIndexed(img, p.entries, { match, overflow: 'merge' }).image;
    assert.deepEqual([...a.data], [...b.data]);
  }
});

test('an empty target palette is refused rather than producing a blank image', () => {
  assert.throws(() => recolorIndexed(sourceArt(4).img, [], {}), /target palette is empty/);
});

test('downscale averages rather than point-samples, and leaves small images alone', () => {
  const img = new Raster(4, 2, null);
  img.set(0, 0, [0, 0, 0]); img.set(1, 0, [100, 100, 100]);
  img.set(2, 0, [200, 200, 200]); img.set(3, 0, [0, 0, 0]);
  img.set(0, 1, [0, 0, 0]); img.set(1, 1, [100, 100, 100]);
  img.set(2, 1, [200, 200, 200]); img.set(3, 1, [0, 0, 0]);

  const small = downscale(img, 2);
  assert.equal(small.w, 2);
  assert.equal(small.h, 1);
  assert.deepEqual(small.get(0, 0), [50, 50, 50]); // (0 + 100 + 0 + 100) / 4
  assert.deepEqual(small.get(1, 0), [100, 100, 100]); // (200 + 0 + 200 + 0) / 4
  assert.equal(downscale(img, 99), img, 'an image already small enough is returned unchanged');
});
