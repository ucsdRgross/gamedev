import test from 'node:test';
import assert from 'node:assert/strict';
import { generatePalette, paletteHexes, paletteViolations } from '../src/core/generate.js';
import { PARAMS, normalizeParams } from '../src/core/params.js';
import { makeRng } from '../src/core/rng.js';
import { isOnGrid } from '../src/core/quantize.js';
import { encodeSeed, decodeSeed } from '../src/core/seed.js';
import { runExport, EXPORTERS } from '../src/core/export/index.js';

// The plan calls for 10,000 cases. Override for a quicker inner loop while iterating:
//   PALETTE_FUZZ_N=200 npm test
const CASES = Number(process.env.PALETTE_FUZZ_N ?? 10000);
const HEX_RE = /^#[0-9A-F]{6}$/;

/** Draw a parameter set uniformly across every field's full range. */
function randomParams(rng) {
  const p = {};
  for (const spec of PARAMS) {
    if (spec.type === 'bool') p[spec.name] = rng() < 0.5;
    else if (spec.type === 'enum') p[spec.name] = spec.options[Math.floor(rng() * spec.options.length)];
    else {
      const v = spec.min + rng() * (spec.max - spec.min);
      p[spec.name] = spec.type === 'int' ? Math.round(v) : v;
    }
  }
  return normalizeParams(p);
}

/**
 * Random art direction with engineering constraints the colour space can actually
 * meet. Uniform sampling across all 58 fields almost never lands here by chance —
 * "60 colours all 15 deltaE apart at 2 bits per channel" is not a palette anyone can
 * make — so a fraction of cases is pinned here deliberately and held to the strict
 * constraint. Everything outside is still checked for well-formedness.
 */
function feasibleParams(rng) {
  const base = randomParams(rng);
  return normalizeParams({
    ...base,
    color_count: 4 + Math.floor(rng() * 13),
    min_delta_e: 3,
    fg_bg_separation_min: 0.15,
    // Art direction can legitimately collapse chroma to zero (heavy earthiness plus a
    // steep falloff), and then lightness is the only axis left. The anchors have to
    // leave enough of it: 16 grey slots at 4.5 deltaE need 0.6 of lightness range.
    l_dark_anchor: 0.1,
    l_light_anchor: 0.95,
    l_range_compress: rng() * 0.3,
    chroma_base: 0.06 + rng() * 0.24,
    bits_r: 8, bits_g: 8, bits_b: 8,
    gamut_map_mode: 'chroma-reduce',
    force_unique_hex: true,
    // At full strength, hue-adaptive lightness pushes a foreground ramp up into a still-
    // saturated, lightness-shifted background (high bg_chroma_mult + positive
    // bg_lightness_offset) closely enough that fg/bg separation is no longer geometrically
    // reachable in a single-hue palette — genuine infeasibility, not a repair miss, so it is
    // capped out of the feasibility canary. The full 0..1 range is still fuzzed for
    // well-formedness in the other three-quarters of cases, and separation under the default
    // 0.5 is asserted deterministically in generate.test.js.
    hue_lightness_follow: Math.min(base.hue_lightness_follow, 0.6),
  });
}

test(`${CASES} randomised parameter sets produce well-formed palettes`, () => {
  const rng = makeRng(0xC0FFEE);
  const stats = {
    cases: 0, withViolations: 0, withWarnings: 0, withDuplicates: 0,
    feasible: 0, feasibleWithViolations: 0, fineDuplicates: 0, worstViolation: Infinity,
  };

  for (let i = 0; i < CASES; i++) {
    const feasible = i % 4 === 0;
    const params = feasible ? feasibleParams(rng) : randomParams(rng);
    let palette;
    try {
      palette = generatePalette(params);
    } catch (err) {
      assert.fail(`case ${i} threw: ${err.stack}\nparams: ${JSON.stringify(params)}`);
    }
    stats.cases++;

    const where = () => `case ${i} (seed ${palette.seed})`;
    assert.equal(palette.entries.length, params.color_count, `${where()}: wrong colour count`);

    const fineGrained = Math.min(params.bits_r, params.bits_g, params.bits_b) >= 6;
    let dark = null;
    let light = null;
    const ramps = new Map();

    for (const e of palette.entries) {
      assert.match(e.hex, HEX_RE, `${where()}: ${e.id} hex ${e.hex}`);
      for (const v of e.rgb8) {
        assert.ok(Number.isInteger(v) && v >= 0 && v <= 255, `${where()}: ${e.id} channel ${v}`);
      }
      assert.ok(
        isOnGrid(e.rgb8, params.bits_r, params.bits_g, params.bits_b),
        `${where()}: ${e.id} off the bit-depth grid`,
      );
      for (const k of ['L', 'C', 'h']) {
        assert.ok(Number.isFinite(e.oklch[k]), `${where()}: ${e.id} requested ${k} is not finite`);
        assert.ok(Number.isFinite(e.actual[k]), `${where()}: ${e.id} actual ${k} is not finite`);
      }
      assert.ok(e.actual.L >= 0 && e.actual.L <= 1, `${where()}: ${e.id} L ${e.actual.L}`);
      assert.ok(e.actual.C >= 0 && e.actual.C < 0.5, `${where()}: ${e.id} C ${e.actual.C}`);
      assert.ok(e.actual.h >= 0 && e.actual.h < 360, `${where()}: ${e.id} h ${e.actual.h}`);
      assert.ok(e.lab.every(Number.isFinite), `${where()}: ${e.id} lab has a NaN`);

      if (e.id === 'universal_dark') dark = e;
      if (e.id === 'universal_light') light = e;
      if (e.layer === 'fg' || e.layer === 'bg') {
        const key = `${e.layer}:${e.hueIndex}`;
        if (!ramps.has(key)) ramps.set(key, []);
        ramps.get(key).push(e);
      }
    }

    // "The anchors are the extremes" is asserted only on the feasible cases, and only where
    // the output grid is fine enough to express an ordering. Both restrictions are earned:
    //
    // - **Feasible only.** Repair may move an anchor off the extreme when the requested
    //   constraints cannot all be met — an infeasible `min_delta_e` against a crowd of dark
    //   slots pushed one dark anchor from a requested L of 0.10 to 0.46. That is repair
    //   doing its job and saying so in `palette.warnings`, not the structure being wrong.
    // - **Fine-grained only.** Near black one legal step outweighs the gap: a dark anchor
    //   requested at L=0.026 quantises to #000600 (L=0.106) while a background requested
    //   *above* it at L=0.070 quantises to #000000 (L=0).
    //
    // `generate.test.js` asserts the same thing on the achieved colours under default
    // parameters, which is where the guarantee actually has to hold.
    if (feasible && fineGrained && params.gamut_map_mode === 'chroma-reduce') {
      for (const e of palette.entries) {
        if (e === dark || e === light) continue;
        assert.ok(e.actual.L >= dark.actual.L, `${where()}: ${e.id} is darker than universal_dark`);
        assert.ok(e.actual.L <= light.actual.L, `${where()}: ${e.id} is lighter than universal_light`);
      }
    }
    if (fineGrained) {
      for (const [key, ramp] of ramps) {
        ramp.sort((a, b) => a.step - b.step);
        for (let j = 1; j < ramp.length; j++) {
          assert.ok(
            ramp[j].oklch.L > ramp[j - 1].oklch.L,
            `${where()}: ramp ${key} is not monotonic in requested lightness`,
          );
          // The emitted colour can wobble by up to a grid step when the two steps are
          // separated mostly in chroma rather than lightness, and `reduce-l-adjust`
          // deliberately spends a little lightness on top of that. `clip` is exempt:
          // naive channel clamping moves lightness and hue arbitrarily, which is the
          // whole reason that mode exists only as a demonstration.
          if (params.gamut_map_mode !== 'clip') {
            const slack = params.gamut_map_mode === 'reduce-l-adjust' ? 0.045 : 0.01;
            assert.ok(
              ramp[j].actual.L >= ramp[j - 1].actual.L - slack,
              `${where()}: ramp ${key} inverted after quantisation`,
            );
          }
        }
      }
    }

    // Uniqueness is best-effort under random parameters: a fourteen-step near-grey
    // ramp squeezed into a 0.04 lightness band has fewer legal colours available than
    // it has slots. The contract is that failures are never silent — the strict
    // guarantee is asserted for every K in generate.test.js and for every preset.
    if (params.force_unique_hex) {
      const unique = new Set(paletteHexes(palette)).size;
      if (unique !== params.color_count) {
        stats.withDuplicates++;
        if (fineGrained) {
          stats.fineDuplicates++;
          stats.firstFineDuplicate ??= `${where()}: ${params.color_count - unique} duplicate(s)`;
        }
        assert.ok(
          palette.warnings.some((w) => /unique hex/.test(w)),
          `${where()}: ${params.color_count - unique} duplicate hexes with no warning`,
        );
      }
    }

    // Distance constraints are best-effort: uniform random parameters routinely ask
    // for more separation than the sRGB volume holds — 60 colours all 15 deltaE apart
    // does not fit. Only cases with a budget the geometry can actually satisfy are
    // held to the constraint; the rest are tracked.
    const violations = paletteViolations(palette);
    if (feasible) {
      stats.feasible++;
      if (violations.length) {
        stats.feasibleWithViolations++;
        stats.firstFeasibleFailure ??= `${where()}: ${violations[0].a}/${violations[0].b} at deltaE ${violations[0].deltaE.toFixed(2)}`;
      }
    }
    if (violations.length) {
      stats.withViolations++;
      stats.worstViolation = Math.min(stats.worstViolation, violations[0].deltaE);
    }
    if (palette.warnings.length) stats.withWarnings++;

    // Seed and export paths must survive the same inputs.
    if (i % 50 === 0) {
      const decoded = decodeSeed(palette.seed);
      assert.deepEqual(decoded.params, palette.params, `${where()}: seed did not round-trip`);
      assert.equal(encodeSeed(decoded.params), palette.seed, `${where()}: seed is not canonical`);
      for (const exporter of EXPORTERS) {
        assert.doesNotThrow(() => runExport(exporter.id, palette), `${where()}: ${exporter.id} export`);
      }
    }
    if (i % 50 === 25) {
      assert.deepEqual(
        paletteHexes(generatePalette(params)), paletteHexes(palette),
        `${where()}: regeneration was not deterministic`,
      );
    }
  }

  assert.equal(stats.cases, CASES);
  // A canary, not an art-direction claim: cases whose constraints the colour space can
  // actually accommodate should almost always resolve. If this rate climbs, repair has
  // regressed even though every per-colour assertion above still passes.
  assert.ok(stats.feasible > CASES * 0.2, `only ${stats.feasible} feasible cases sampled`);
  assert.equal(
    stats.feasibleWithViolations, 0,
    `${stats.feasibleWithViolations}/${stats.feasible} satisfiable cases left violations — ${stats.firstFeasibleFailure}`,
  );
  assert.ok(
    stats.fineDuplicates < CASES * 0.01,
    `${stats.fineDuplicates}/${CASES} cases with a fine grid still had duplicates` +
      ` — ${stats.firstFineDuplicate} (${stats.withDuplicates} total, mostly low bit depth)`,
  );
});

test('extreme corners of the parameter space do not crash', () => {
  const extremes = [];
  for (const which of ['min', 'max']) {
    const p = {};
    for (const spec of PARAMS) {
      if (spec.type === 'bool') p[spec.name] = which === 'max';
      else if (spec.type === 'enum') {
        p[spec.name] = which === 'min' ? spec.options[0] : spec.options[spec.options.length - 1];
      } else p[spec.name] = which === 'min' ? spec.min : spec.max;
    }
    extremes.push(p);
  }
  // Plus the pathological combinations that are easy to get wrong.
  extremes.push({ color_count: 4, hue_count: 8, chroma_base: 0, chroma_cap: 0.05 });
  extremes.push({ color_count: 64, hue_count: 1, fg_ramp_length: 2, bg_ramp_length: 1, neutral_count: 0, accent_count: 0 });
  extremes.push({ color_count: 64, bits_r: 1, bits_g: 1, bits_b: 1 });
  extremes.push({ color_count: 4, l_dark_anchor: 0.3, l_light_anchor: 0.8, l_step: 0.4, min_delta_e: 15 });
  extremes.push({ color_count: 32, l_range_compress: 1, min_delta_e: 15, min_anchor_contrast: 21 });
  extremes.push({ color_count: 32, gamut_map_mode: 'clip', chroma_base: 0.37, chroma_cap: 0.37 });

  for (const [i, raw] of extremes.entries()) {
    const params = normalizeParams(raw);
    const palette = generatePalette(params);
    assert.equal(palette.entries.length, params.color_count, `extreme ${i}: wrong count`);
    for (const e of palette.entries) {
      assert.match(e.hex, HEX_RE, `extreme ${i}: ${e.id}`);
      assert.ok(e.lab.every(Number.isFinite), `extreme ${i}: ${e.id} lab NaN`);
    }
    for (const exporter of EXPORTERS) {
      assert.doesNotThrow(() => runExport(exporter.id, palette), `extreme ${i}: ${exporter.id}`);
    }
  }
});
