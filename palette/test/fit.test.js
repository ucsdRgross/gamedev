import test from 'node:test';
import assert from 'node:assert/strict';
import { paletteFit, inferStructure, fitParams, makeFitter } from '../src/core/fit.js';
import { generatePalette, paletteHexes } from '../src/core/generate.js';

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

test('fitParams recovers a palette generated from known parameters', () => {
  // Generate a target from real params, then check the fitter finds a close match to it.
  const known = generatePalette({
    color_count: 16, hue_count: 4, hue_scheme: 'analogous', root_hue: 200, hue_span: 120,
    l_mid_base: 0.55, chroma_base: 0.16, seed: 999,
  });
  const target = paletteHexes(known);
  const r = fitParams(target, { seed: 3, iterations: 3000 });
  assert.ok(r.score < 3.5, `should recover the generated target closely, got ${r.score.toFixed(2)}`);
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
  const r = fitParams(CRAYON, { seed: 3, iterations: 4000 });
  // Mean deltaE ~4 at this budget is a close visual match (one JND ~2); the hue schemes are
  // regular while the crayon hues are slightly irregular, so a small residual is expected.
  // The shipped OKLAB Crayon preset was fitted at a higher budget and lands near 3.1.
  assert.ok(r.score < 4.5, `crayon fit should be close, got ${r.score.toFixed(2)}`);
  // eslint-disable-next-line no-console
  console.log(`    crayon fit score: ${r.score.toFixed(3)} (coverage ${r.coverage.toFixed(2)}, fidelity ${r.fidelity.toFixed(2)})`);
});
