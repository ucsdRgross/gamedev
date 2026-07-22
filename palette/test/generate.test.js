import test from 'node:test';
import assert from 'node:assert/strict';
import { generatePalette, paletteHexes, paletteViolations, entryFor } from '../src/core/generate.js';
import { defaultParams } from '../src/core/params.js';
import { FG_BG_SEP_SCALE } from '../src/core/repair.js';
import { deltaEOK, contrastRatio, hueDelta, rgb8ToOklch } from '../src/core/oklch.js';
import { midIndex } from '../src/core/ramp.js';
import { SEMANTIC_TARGETS } from '../src/core/roles.js';

const SCHEMES = ['even', 'analogous', 'complementary', 'split-comp', 'triadic', 'tetradic', 'custom'];
const HEX_RE = /^#[0-9A-F]{6}$/;

test('exactly K colours for every K in 4..64 across all schemes', () => {
  for (let k = 4; k <= 64; k++) {
    for (const scheme of SCHEMES) {
      const p = generatePalette({ ...defaultParams(), color_count: k, hue_scheme: scheme });
      assert.equal(p.entries.length, k, `K=${k} scheme=${scheme}`);
    }
  }
});

test('exactly K colours for every manual hue count', () => {
  for (let k = 4; k <= 64; k += 3) {
    for (let hues = 1; hues <= 8; hues++) {
      const p = generatePalette({ ...defaultParams(), color_count: k, hue_count: hues });
      assert.equal(p.entries.length, k, `K=${k} hues=${hues}`);
    }
  }
});

test('every emitted colour is a valid #RRGGBB in gamut', () => {
  for (let k = 4; k <= 64; k += 5) {
    const p = generatePalette({ ...defaultParams(), color_count: k });
    for (const e of p.entries) {
      assert.match(e.hex, HEX_RE, `${e.id} produced ${e.hex}`);
      for (const v of e.rgb8) {
        assert.ok(Number.isInteger(v) && v >= 0 && v <= 255, `${e.id} channel ${v}`);
      }
      assert.ok(Number.isFinite(e.oklch.L) && Number.isFinite(e.oklch.C) && Number.isFinite(e.oklch.h));
    }
  }
});

test('universal_light is the lightest colour and universal_dark the darkest', () => {
  for (let k = 4; k <= 64; k++) {
    for (const scheme of ['analogous', 'triadic']) {
      const p = generatePalette({ ...defaultParams(), color_count: k, hue_scheme: scheme });
      const dark = p.entries.find((e) => e.id === 'universal_dark');
      const light = p.entries.find((e) => e.id === 'universal_light');
      for (const e of p.entries) {
        if (e === dark || e === light) continue;
        assert.ok(e.actual.L > dark.actual.L, `${e.id} (L=${e.actual.L}) is darker than the dark anchor at K=${k}`);
        assert.ok(e.actual.L < light.actual.L, `${e.id} (L=${e.actual.L}) is lighter than the light anchor at K=${k}`);
      }
    }
  }
});

test('foreground ramps are monotonic in lightness', () => {
  for (let k = 8; k <= 64; k += 3) {
    for (const curve of ['ease-dark', 'linear', 'ease-light', 's-curve']) {
      const p = generatePalette({ ...defaultParams(), color_count: k, l_curve: curve });
      const ramps = new Map();
      for (const e of p.entries) {
        if (e.layer !== 'fg' && e.layer !== 'bg') continue;
        const key = `${e.layer}:${e.hueIndex}`;
        if (!ramps.has(key)) ramps.set(key, []);
        ramps.get(key).push(e);
      }
      for (const [key, ramp] of ramps) {
        ramp.sort((a, b) => a.step - b.step);
        for (let j = 1; j < ramp.length; j++) {
          assert.ok(
            ramp[j].actual.L > ramp[j - 1].actual.L,
            `K=${k} ${curve} ramp ${key} step ${j}: ${ramp[j - 1].actual.L} -> ${ramp[j].actual.L}`,
          );
        }
      }
    }
  }
});

test('highlights sit closer to the highlight target than midtones do', () => {
  for (const model of ['global-attractor', 'relative-rotation']) {
    const p = generatePalette({
      ...defaultParams(), color_count: 32, shift_model: model, shift_direction: 'shortest',
      temperature_split: 1, earthiness: 0, global_temperature: 0,
    });
    const byHue = new Map();
    for (const e of p.entries) {
      if (e.layer !== 'fg') continue;
      if (!byHue.has(e.hueIndex)) byHue.set(e.hueIndex, []);
      byHue.get(e.hueIndex).push(e);
    }
    for (const [hue, ramp] of byHue) {
      ramp.sort((a, b) => a.step - b.step);
      const m = midIndex(ramp.length);
      const mid = ramp[m];
      const hi = ramp[ramp.length - 1];
      if (hi === mid || hi.actual.C < 0.03 || mid.actual.C < 0.03) continue;
      const dMid = Math.abs(hueDelta(mid.actual.h, p.params.highlight_hue_target));
      const dHi = Math.abs(hueDelta(hi.actual.h, p.params.highlight_hue_target));
      assert.ok(dHi <= dMid + 6, `${model} hue ${hue}: highlight ${dHi} vs mid ${dMid} degrees from target`);
    }
  }
});

test('shadows sit closer to the shadow target than midtones do', () => {
  const p = generatePalette({
    ...defaultParams(), color_count: 32, shift_model: 'global-attractor',
    temperature_split: 1, earthiness: 0, global_temperature: 0,
  });
  const byHue = new Map();
  for (const e of p.entries) {
    if (e.layer !== 'fg') continue;
    if (!byHue.has(e.hueIndex)) byHue.set(e.hueIndex, []);
    byHue.get(e.hueIndex).push(e);
  }
  for (const [hue, ramp] of byHue) {
    ramp.sort((a, b) => a.step - b.step);
    const mid = ramp[midIndex(ramp.length)];
    const lo = ramp[0];
    if (lo === mid || lo.actual.C < 0.03 || mid.actual.C < 0.03) continue;
    const dMid = Math.abs(hueDelta(mid.actual.h, p.params.shadow_hue_target));
    const dLo = Math.abs(hueDelta(lo.actual.h, p.params.shadow_hue_target));
    assert.ok(dLo <= dMid + 6, `hue ${hue}: shadow ${dLo} vs mid ${dMid} degrees from target`);
  }
});

test('all pairs satisfy min_delta_e at default quality settings', () => {
  for (let k = 4; k <= 64; k++) {
    const p = generatePalette({ ...defaultParams(), color_count: k });
    const bad = paletteViolations(p);
    assert.equal(bad.length, 0, `K=${k}: ${bad.slice(0, 3).map((v) => `${v.a}/${v.b}@${v.deltaE.toFixed(2)}`).join(', ')}`);
    assert.deepEqual(p.warnings, [], `K=${k} warnings: ${p.warnings.join('; ')}`);
  }
});

test('foreground and background stay perceptually separated', () => {
  for (const sep of [0.1, 0.25, 0.4]) {
    const p = generatePalette({ ...defaultParams(), color_count: 40, fg_bg_separation_min: sep });
    const threshold = Math.max(p.params.min_delta_e, sep * FG_BG_SEP_SCALE);
    const fg = p.entries.filter((e) => ['fg', 'bridge', 'accent'].includes(e.layer));
    const bg = p.entries.filter((e) => e.layer === 'bg');
    assert.ok(bg.length > 0, 'expected background slots at K=40');
    for (const a of fg) {
      for (const b of bg) {
        assert.ok(
          deltaEOK(a.lab, b.lab) >= threshold - 1e-9,
          `${a.id} vs ${b.id}: ${deltaEOK(a.lab, b.lab).toFixed(2)} < ${threshold}`,
        );
      }
    }
  }
});

test('hex values are unique when force_unique_hex is set', () => {
  for (let k = 4; k <= 64; k++) {
    const p = generatePalette({ ...defaultParams(), color_count: k, force_unique_hex: true });
    const hexes = paletteHexes(p);
    assert.equal(new Set(hexes).size, k, `K=${k} produced duplicates`);
  }
});

test('anchor contrast meets the requested WCAG floor', () => {
  for (const target of [4.5, 7, 10, 14]) {
    for (const k of [4, 16, 32, 64]) {
      const p = generatePalette({ ...defaultParams(), color_count: k, min_anchor_contrast: target });
      const dark = p.entries.find((e) => e.id === 'universal_dark');
      const light = p.entries.find((e) => e.id === 'universal_light');
      const ratio = contrastRatio(dark.rgb8, light.rgb8);
      assert.ok(ratio >= target - 1e-6, `K=${k} target ${target}: got ${ratio.toFixed(2)}`);
    }
  }
});

test('generation is deterministic and depends on the seed', () => {
  const base = { ...defaultParams(), color_count: 24 };
  assert.deepEqual(paletteHexes(generatePalette(base)), paletteHexes(generatePalette(base)));
  const other = paletteHexes(generatePalette({ ...base, seed: 777 }));
  assert.notDeepEqual(paletteHexes(generatePalette(base)), other);
});

test('bit-depth reduction lands every colour on the legal grid', () => {
  for (const [r, g, b] of [[5, 5, 5], [3, 3, 3], [2, 2, 2], [4, 2, 3]]) {
    const p = generatePalette({ ...defaultParams(), color_count: 16, bits_r: r, bits_g: g, bits_b: b });
    const legal = [r, g, b].map((bits) => {
      const levels = 2 ** bits;
      return new Set(Array.from({ length: levels }, (_, k) => Math.round((k / (levels - 1)) * 255)));
    });
    for (const e of p.entries) {
      for (let c = 0; c < 3; c++) {
        assert.ok(legal[c].has(e.rgb8[c]), `${e.id} channel ${c} = ${e.rgb8[c]} off the ${[r, g, b][c]}-bit grid`);
      }
    }
  }
});

test('locks and overrides are honoured exactly and survive repair', () => {
  const base = { ...defaultParams(), color_count: 16 };
  const plain = generatePalette(base);
  const targetId = plain.entries[5].id;
  const otherId = plain.entries[9].id;
  const p = generatePalette(base, {
    locks: { [targetId]: '#FF00AA' },
    overrides: { [otherId]: '#123456' },
  });
  assert.equal(p.entries.find((e) => e.id === targetId).hex, '#FF00AA');
  assert.equal(p.entries.find((e) => e.id === otherId).hex, '#123456');
  assert.ok(p.entries.find((e) => e.id === targetId).locked);
  assert.ok(p.entries.find((e) => e.id === otherId).overridden);
  assert.equal(p.entries.length, 16);
});

test('every semantic role resolves to a real slot', () => {
  for (const k of [4, 8, 16, 32, 64]) {
    const p = generatePalette({ ...defaultParams(), color_count: k });
    const ids = new Set(p.entries.map((e) => e.id));
    for (const target of SEMANTIC_TARGETS) {
      const id = p.semantics[target.name];
      assert.ok(ids.has(id), `K=${k}: role ${target.name} -> ${id}`);
      assert.ok(entryFor(p, target.name), `K=${k}: entryFor(${target.name})`);
    }
  }
});

test('foliage lands on a green and water on a blue when the palette has them', () => {
  const p = generatePalette({
    ...defaultParams(), color_count: 48, hue_scheme: 'even', root_hue: 0, earthiness: 0,
  });
  const foliage = rgb8ToOklch(entryFor(p, 'foliage').rgb8);
  const water = rgb8ToOklch(entryFor(p, 'water').rgb8);
  assert.ok(Math.abs(hueDelta(foliage.h, 140)) < 60, `foliage hue ${foliage.h.toFixed(0)}`);
  assert.ok(Math.abs(hueDelta(water.h, 235)) < 60, `water hue ${water.h.toFixed(0)}`);
});

test('slot ids and roles stay stable when colour parameters move', () => {
  const a = generatePalette({ ...defaultParams(), color_count: 32, root_hue: 10 });
  const b = generatePalette({ ...defaultParams(), color_count: 32, root_hue: 300, chroma_base: 0.05 });
  assert.deepEqual(a.entries.map((e) => e.id), b.entries.map((e) => e.id));
  assert.deepEqual(a.entries.map((e) => e.role), b.entries.map((e) => e.role));
});

test('grayscale parameters produce a neutral palette without crashing', () => {
  const p = generatePalette({ ...defaultParams(), color_count: 16, chroma_base: 0, chroma_cap: 0.05 });
  assert.equal(p.entries.length, 16);
  for (const e of p.entries) assert.ok(e.actual.C < 0.08, `${e.id} chroma ${e.actual.C}`);
});
