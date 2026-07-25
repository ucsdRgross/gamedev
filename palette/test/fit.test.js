import test from 'node:test';
import assert from 'node:assert/strict';
import { paletteFit, inferStructure, fitParams, makeFitter } from '../src/core/fit.js';
import { generatePalette, paletteHexes } from '../src/core/generate.js';
import { defaultParams, PARAM_BY_NAME, isAngularParam } from '../src/core/params.js';
import { presetParams } from '../src/core/presets.js';

// Fit quality is measured over SEVERAL seeds, never one. The previous thresholds were tuned
// against seed 3 alone, and the consequence was that a genuine bug (the `_hue` suffix wrap,
// which sent `l_variance_per_hue` to its ceiling) became load-bearing: fixing it "regressed"
// the fit against a threshold that only ever described one lucky run. A mean over three seeds
// plus a per-seed ceiling says what is actually being promised.
const FIT_SEEDS = [1, 2, 3];

/** Mean and worst score over `FIT_SEEDS` for one target. */
function fitAcrossSeeds(target, iterations) {
  const scores = FIT_SEEDS.map((seed) => fitParams(target, { seed, iterations }).score);
  return { scores, mean: scores.reduce((a, b) => a + b, 0) / scores.length, worst: Math.max(...scores) };
}

const CRAYON = ['#FFFFF6', '#FF907D', '#ED0003', '#880001', '#F0AF10', '#C46300', '#713500',
  '#94D15C', '#40990E', '#215605', '#13CBFF', '#098AF4', '#014D8E', '#FE8FE0', '#D121AF',
  '#770F63', '#BDBBBA', '#817E7D', '#464545', '#141414'];

test('paletteFit is zero for identical palettes and positive otherwise', () => {
  const same = paletteFit(CRAYON, CRAYON);
  assert.ok(same.score < 1e-9, `identical should score ~0, got ${same.score}`);
  const diff = paletteFit(['#000000', '#FFFFFF'], ['#FF0000', '#00FF00']);
  assert.ok(diff.score > 5, `disjoint palettes should be far apart, got ${diff.score}`);
});

test('paletteFit reports both directions', () => {
  // A candidate that covers the target but adds a useless colour: coverage good, fidelity worse.
  const target = ['#FF0000', '#00FF00'];
  const candidate = ['#FF0000', '#00FF00', '#0000FF'];
  const fit = paletteFit(candidate, target);
  assert.ok(fit.coverage < 1e-6, `target fully covered: ${fit.coverage}`);
  assert.ok(fit.fidelity > fit.coverage, 'the extra blue should cost fidelity');
});

test('inferStructure reads the crayon strip: 20 colours, 5 hue families, 3 neutrals', () => {
  const s = inferStructure(CRAYON);
  assert.equal(s.color_count, 20);
  assert.equal(s.hue_count, 5);
  assert.equal(s.fg_ramp_length, 3);
  assert.equal(s.neutral_count, 3);
});

const RECOVERY = paletteHexes(generatePalette({
  color_count: 16, hue_count: 4, hue_scheme: 'analogous', root_hue: 200, hue_span: 120,
  l_mid_base: 0.55, chroma_base: 0.16, seed: 999,
}));

test('fitParams recovers a palette generated from known parameters', () => {
  const { scores, mean, worst } = fitAcrossSeeds(RECOVERY, 3000);
  // Measured 3.87 / 4.20 / 4.38 across these seeds; the bounds leave room for the search to
  // be re-tuned without a rewrite, and are tight enough that a real regression trips them.
  assert.ok(mean < 4.8, `mean should recover the target closely, got ${mean.toFixed(2)} of ${scores.map((s) => s.toFixed(2))}`);
  assert.ok(worst < 5.4, `no seed should fail badly, worst was ${worst.toFixed(2)}`);
});

test('fitParams is deterministic under a fixed seed', () => {
  const a = fitParams(CRAYON, { seed: 5, iterations: 1200 });
  const b = fitParams(CRAYON, { seed: 5, iterations: 1200 });
  assert.equal(a.score, b.score);
  assert.deepEqual(a.params, b.params);
});

test('makeFitter converges and never worsens its best score', () => {
  const fitter = makeFitter(CRAYON, { seed: 3, iterations: 2000 });
  const first = fitter.step(500).bestScore;
  const second = fitter.step(500).bestScore;
  const third = fitter.step(1000).bestScore;
  assert.ok(second <= first && third <= second, 'best score must be monotonically non-increasing');
  assert.ok(fitter.done, 'should be done after the full budget');
});

test('the crayon target fits to a close score', () => {
  // Mean deltaE ~4 at this budget is a close visual match (one JND ~2); the hue schemes are
  // regular while the crayon hues are slightly irregular, so a small residual is expected.
  // The shipped OKLAB Crayon preset was fitted at a higher budget and lands near 3.1.
  const { scores, mean, worst } = fitAcrossSeeds(CRAYON, 4000);
  assert.ok(mean < 4.4, `crayon fit should be close, got ${mean.toFixed(2)} of ${scores.map((s) => s.toFixed(2))}`);
  assert.ok(worst < 5.0, `no seed should fail badly, worst was ${worst.toFixed(2)}`);
  // eslint-disable-next-line no-console
  console.log(`    crayon fit: mean ${mean.toFixed(3)} over seeds ${FIT_SEEDS.join(',')} (${scores.map((s) => s.toFixed(2)).join(' ')})`);
});

// --- U6.1 additions -------------------------------------------------------

test('`fixed` names are never touched by the search', () => {
  const fixed = ['root_hue', 'chroma_base', 'l_mid_base'];
  const from = { ...defaultParams(), root_hue: 275, chroma_base: 0.2, l_mid_base: 0.44 };
  const r = fitParams(CRAYON, { seed: 2, iterations: 600, from, fixed });
  for (const name of fixed) {
    assert.ok(Math.abs(r.params[name] - from[name]) < 1e-6, `${name} moved to ${r.params[name]}`);
  }
  // Fixing the enums must hold them too, since restarts are where enums are redrawn.
  const withEnums = fitParams(CRAYON, {
    seed: 2, iterations: 600, from: { ...from, hue_scheme: 'triadic', shift_model: 'relative-rotation' },
    fixed: [...fixed, 'hue_scheme', 'shift_model'],
  });
  assert.equal(withEnums.params.hue_scheme, 'triadic');
  assert.equal(withEnums.params.shift_model, 'relative-rotation');
});

test('fixing everything the search can move is refused rather than looping pointlessly', () => {
  const everything = Object.keys(defaultParams());
  assert.throws(() => makeFitter(CRAYON, { fixed: everything }), /nothing to fit/);
});

test('`from` starts at the caller\'s palette and can only improve on it', () => {
  // Start from a preset that is nothing like the target: the search must still never report
  // something worse than where it began, because its first candidate *is* where it began.
  const from = presetParams('frozen-tundra');
  const startScore = paletteFit(paletteHexes(generatePalette(from)), CRAYON).score;
  const r = fitParams(CRAYON, { seed: 4, iterations: 400, from });
  assert.ok(r.score <= startScore + 1e-9, `started at ${startScore.toFixed(2)}, reported ${r.score.toFixed(2)}`);
  // The structure the caller chose is honoured rather than replaced by inferStructure.
  assert.equal(r.params.color_count, from.color_count);
});

test('`onProgress` reports a usable best-so-far, never worsening', () => {
  const seen = [];
  fitParams(CRAYON, { seed: 3, iterations: 500, onProgress: (p) => seen.push(p) });
  assert.ok(seen.length > 2, `expected several improvements, got ${seen.length}`);
  for (let i = 1; i < seen.length; i++) {
    assert.ok(seen[i].bestScore <= seen[i - 1].bestScore, 'progress must never report a worse best');
    assert.ok(seen[i].progress >= seen[i - 1].progress - 1e-9, 'progress must not go backwards');
  }
  // Every reported set is a complete, generatable parameter set — a UI paints it directly.
  const last = seen[seen.length - 1];
  assert.equal(generatePalette(last.params).entries.length, last.params.color_count);
});

test('keepLooking resumes a finished run instead of starting over', () => {
  const fitter = makeFitter(CRAYON, { seed: 3, iterations: 400 });
  fitter.step(400);
  assert.ok(fitter.done);
  const before = fitter.bestScore;
  fitter.keepLooking(600);
  assert.equal(fitter.done, false, 'the run reopens');
  assert.equal(fitter.bestScore, before, 'the best so far is kept, not discarded');
  fitter.step(600);
  assert.ok(fitter.done);
  assert.ok(fitter.bestScore <= before, 'looking longer can only improve');
  assert.equal(fitter.total, 1000);
});

test('the fitter reports what it changed, biggest move first', () => {
  const from = presetParams('frozen-tundra');
  const r = fitParams(CRAYON, { seed: 4, iterations: 500, from });
  assert.ok(Array.isArray(r.diff) && r.diff.length > 0, 'a fit from a distant start changed something');
  // Ordered by `weight`, not raw magnitude — paramDiff favours the Basics, so "hue count
  // +6" leads "dither evenness +0.02" even when the raw fractions say otherwise.
  for (let i = 1; i < r.diff.length; i++) {
    assert.ok(r.diff[i].weight <= r.diff[i - 1].weight, 'the diff is ordered biggest move first');
  }
  // Everything named as changed really did change.
  for (const change of r.diff) assert.notDeepEqual(r.params[change.name], from[change.name]);
});

test('the search wraps only real angles — the per-hue variances clamp', () => {
  // The regression this exists for: `l_variance_per_hue` and `chroma_variance_per_hue` end in
  // `_hue` but are spreads, not angles. Wrapping them sent a small negative step to 359.98,
  // which then clamped to the parameter's MAXIMUM — an invisible jump to an extreme.
  // Every non-angular knob the search touches must stay inside its own schema range.
  for (const seed of [1, 2, 3, 4]) {
    const r = fitParams(RECOVERY, { seed, iterations: 300 });
    for (const name of ['l_variance_per_hue', 'chroma_variance_per_hue', 'hue_span']) {
      const spec = PARAM_BY_NAME.get(name);
      assert.ok(r.params[name] >= spec.min && r.params[name] <= spec.max,
        `seed ${seed}: ${name} left its range at ${r.params[name]} (${spec.min}..${spec.max})`);
    }
  }
  // And the two that were being wrapped by mistake are not in the angular set at all.
  for (const name of ['l_variance_per_hue', 'chroma_variance_per_hue', 'hue_span']) {
    assert.equal(isAngularParam(name), false, `${name} is not an angle`);
  }
});
