// Fit a parameter set to a target palette — the engine behind "parameters from image".
//
// Given a list of target hexes (extracted from an image, or any reference), search the
// generator's parameter space for the params whose generated palette is perceptually
// closest to the target. DOM-free and deterministic (seeded PRNG, never Math.random), so
// `node --test` exercises the real search and the browser drives the same code.
//
// The fitness is a symmetric mean-nearest deltaE in OKLab — the same measure `reference.js`
// uses to score its embedded palettes (it keeps its own tiny copy so it need not depend on
// the generator). `coverage` asks whether the candidate can express the target's colours;
// `fidelity` asks whether it wastes colours the target has no use for; `score` is their mean.

import { generatePalette, paletteHexes } from './generate.js';
import { defaultParams, normalizeParams, PARAM_BY_NAME } from './params.js';
import { makeRng } from './rng.js';
import { hexToRgb8, rgb8ToOklab, deltaEOK } from './oklch.js';

/** Mean of the smallest deltaE from each colour in `from` to any colour in `to` (OKLab). */
export function meanNearest(from, to) {
  if (!from.length || !to.length) return Infinity;
  let sum = 0;
  for (const a of from) {
    let best = Infinity;
    for (const b of to) best = Math.min(best, deltaEOK(a, b));
    sum += best;
  }
  return sum / from.length;
}

/** Symmetric perceptual distance between two hex palettes. Lower is closer. */
export function paletteFit(candidateHexes, targetHexes) {
  const mine = candidateHexes.map((h) => rgb8ToOklab(hexToRgb8(h)));
  const theirs = targetHexes.map((h) => rgb8ToOklab(hexToRgb8(h)));
  const coverage = meanNearest(theirs, mine);
  const fidelity = meanNearest(mine, theirs);
  return { coverage, fidelity, score: (coverage + fidelity) / 2 };
}

/** Score a parameter set against a target already converted to OKLab, for the inner loop. */
function scoreParams(params, targetLab) {
  const mine = paletteHexes(generatePalette(params)).map((h) => rgb8ToOklab(hexToRgb8(h)));
  const coverage = meanNearest(targetLab, mine);
  const fidelity = meanNearest(mine, targetLab);
  return (coverage + fidelity) / 2;
}

/**
 * Guess the palette's structure from the target: total count, how many chromatic hue
 * families it holds, and how many near-neutral slots. The optimizer searches colour, not
 * structure, so a good guess here is what lets the continuous search actually converge.
 */
export function inferStructure(targetHexes) {
  const labs = targetHexes.map((h) => rgb8ToOklab(hexToRgb8(h)));
  const chroma = labs.map((l) => Math.hypot(l[1], l[2]));
  const NEUTRAL_C = 0.03;
  const neutralCount = chroma.filter((c) => c < NEUTRAL_C).length;

  // Cluster the chromatic colours by hue angle (greedy, 35° radius) to estimate hue_count.
  const hues = labs
    .filter((_, i) => chroma[i] >= NEUTRAL_C)
    .map((l) => (Math.atan2(l[2], l[1]) * 180) / Math.PI);
  const centers = [];
  for (const h of hues) {
    const near = centers.some((c) => {
      const d = Math.abs(((h - c + 540) % 360) - 180);
      return d < 35;
    });
    if (!near) centers.push(h);
  }
  const hueCount = Math.max(1, Math.min(8, centers.length));

  // Chromatic slots per hue family → a plausible foreground ramp length (2..5).
  const chromatic = targetHexes.length - neutralCount;
  const perHue = hueCount ? chromatic / hueCount : 3;
  const fgRamp = Math.max(2, Math.min(5, Math.round(perHue)));
  // Two of the neutral-ish slots are usually the universal anchors, not the neutral ramp.
  const neutralRamp = Math.max(0, Math.min(6, neutralCount - 2));

  return {
    color_count: Math.max(4, Math.min(64, targetHexes.length)),
    hue_count: hueCount,
    fg_ramp_length: fgRamp,
    neutral_count: neutralRamp,
  };
}

// The parameters the search perturbs — every knob that moves colour, but not the structural
// counts (fixed from inferStructure) or the hardware/recolour groups (not a look). Each is
// driven within its own schema range.
const SEARCH_FLOATS = [
  'root_hue', 'hue_span', 'hue_jitter', 'perceptual_hue_spacing',
  'l_dark_anchor', 'l_light_anchor', 'l_mid_base', 'l_step', 'l_range_compress',
  'l_variance_per_hue', 'hue_lightness_follow',
  'chroma_base', 'chroma_peak_l', 'chroma_curve_width', 'chroma_falloff_light',
  'chroma_falloff_dark', 'chroma_variance_per_hue', 'earthiness', 'chroma_cap',
  'highlight_hue_target', 'highlight_shift_strength', 'shadow_hue_target',
  'shadow_shift_strength', 'global_temperature', 'temperature_split',
  'neutral_temperature', 'neutral_chroma', 'neutral_l_spread',
];
// Enum knobs tried at restart time rather than perturbed continuously.
const SCHEMES = ['analogous', 'even', 'custom', 'complementary', 'split-comp'];
const SHIFT_MODELS = ['per-family', 'relative-rotation', 'global-attractor'];

/** Perturb one numeric parameter by gaussian noise scaled to its range, staying in bounds. */
function jitterParam(params, name, rng, scale) {
  const spec = PARAM_BY_NAME.get(name);
  if (!spec || spec.type === 'enum' || spec.type === 'bool') return;
  const span = spec.max - spec.min;
  const g = (rng() + rng() + rng() - 1.5) * 2; // ~N(0,1)
  let v = params[name] + g * scale * span;
  if (name === 'root_hue' || name.endsWith('_hue') || name.endsWith('_hue_target')) {
    v = ((v % 360) + 360) % 360; // hues wrap
  } else {
    v = Math.min(spec.max, Math.max(spec.min, v));
  }
  if (spec.type === 'int') v = Math.round(v);
  params[name] = v;
}

/**
 * A fresh candidate for restart `r`: defaults + inferred structure + an enum draw. The
 * scheme is chosen by restart index (not at random) so every hue scheme gets a fair share
 * of restarts to hill-climb from — the scheme is the one knob a continuous search cannot
 * nudge its way into, so it must be seeded across the whole run rather than gambled on.
 */
function seedCandidate(structure, rng, r) {
  const p = { ...defaultParams(), ...structure };
  p.hue_scheme = SCHEMES[r % SCHEMES.length];
  p.shift_model = SHIFT_MODELS[Math.floor(r / SCHEMES.length) % SHIFT_MODELS.length];
  for (const name of SEARCH_FLOATS) jitterParam(p, name, rng, 0.5);
  return p;
}

/**
 * Resumable fitter, so a caller (the UI) can run the search in slices without freezing.
 * `step(n)` runs up to `n` evaluations and returns `{ done, bestScore }`; `bestParams` and
 * `bestScore` are always readable. The whole run is a random-restart hill climb: from each
 * start it perturbs a shrinking subset of knobs and keeps only strict improvements.
 */
export function makeFitter(targetHexes, { seed = 1, iterations = 6000, restarts = 10 } = {}) {
  const rng = makeRng(seed);
  const targetLab = targetHexes.map((h) => rgb8ToOklab(hexToRgb8(h)));
  const structure = inferStructure(targetHexes);
  const budgetPer = Math.max(1, Math.floor(iterations / restarts));

  let restartIndex = 0;
  let bestParams = seedCandidate(structure, rng, restartIndex);
  let bestScore = scoreParams(bestParams, targetLab);
  let cur = bestParams;
  let curScore = bestScore;
  let done = 0;
  let sinceRestart = 0;

  const fitter = {
    total: iterations,
    get bestScore() { return bestScore; },
    get bestParams() { return normalizeParams(bestParams); },
    get progress() { return done / iterations; },
    get done() { return done >= iterations; },
    step(n) {
      const end = Math.min(iterations, done + n);
      while (done < end) {
        done++;
        sinceRestart++;
        if (sinceRestart >= budgetPer) { // next restart, cycling schemes deterministically
          restartIndex++;
          cur = seedCandidate(structure, rng, restartIndex);
          curScore = scoreParams(cur, targetLab);
          sinceRestart = 0;
          if (curScore < bestScore) { bestScore = curScore; bestParams = cur; }
          continue;
        }
        // Anneal the perturbation: bold early in a restart, fine near the end.
        const t = sinceRestart / budgetPer;
        const scale = 0.28 * (1 - t) + 0.015;
        const cand = { ...cur };
        const k = 1 + Math.floor(rng() * 3); // perturb 1..3 knobs at a time
        for (let j = 0; j < k; j++) {
          jitterParam(cand, SEARCH_FLOATS[Math.floor(rng() * SEARCH_FLOATS.length)], rng, scale);
        }
        const s = scoreParams(cand, targetLab);
        if (s < curScore) {
          cur = cand;
          curScore = s;
          if (s < bestScore) { bestScore = s; bestParams = cand; }
        }
      }
      return { done: fitter.done, bestScore };
    },
  };
  return fitter;
}

/**
 * Fit a parameter set to a target palette in one call. Returns the best params found (as a
 * normalised set the UI can load like a preset), the achieved fit and the eval count.
 */
export function fitParams(targetHexes, opts = {}) {
  const fitter = makeFitter(targetHexes, opts);
  fitter.step(fitter.total);
  const fit = paletteFit(paletteHexes(generatePalette(fitter.bestParams)), targetHexes);
  return {
    params: fitter.bestParams,
    score: fit.score,
    coverage: fit.coverage,
    fidelity: fit.fidelity,
    iterations: fitter.total,
  };
}
