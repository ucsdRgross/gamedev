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
import { defaultParams, normalizeParams, PARAM_BY_NAME, isAngularParam } from './params.js';
import { makeRng } from './rng.js';
import { hexToRgb8, rgb8ToOklab, deltaEOK } from './oklch.js';
import { paramDiff } from './describe.js';

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

/**
 * Perturb one numeric parameter, staying in bounds.
 *
 * Two moves. The usual one is a gaussian step scaled to the parameter's range — a hill climb.
 * With probability `jump` the value is instead **resampled uniformly across its whole range**,
 * which is how the search crosses a valley rather than walking down into one and stopping.
 *
 * The jump move is not decoration; it replaces something that used to happen by accident.
 * Until this was fixed the wrap test was `name.endsWith('_hue')`, which caught
 * `l_variance_per_hue` and `chroma_variance_per_hue` — neither of which is an angle. A small
 * negative step on those wrapped to 359.98 and then clamped to the parameter's *maximum*, so
 * the search had a hidden "jump to an extreme" move on exactly two knobs, and the old fit
 * thresholds were tuned around it. Measured over five seeds and two targets, removing the bug
 * without replacing it regressed both fits; an explicit annealed jump on *every* knob beats
 * the accident (see UX_PLAN's U6 note for the numbers).
 */
function jitterParam(params, name, rng, scale, jump = 0) {
  const spec = PARAM_BY_NAME.get(name);
  if (!spec || spec.type === 'enum' || spec.type === 'bool') return;
  const span = spec.max - spec.min;
  let v;
  if (jump > 0 && rng() < jump) {
    v = spec.min + rng() * span;
  } else {
    const g = (rng() + rng() + rng() - 1.5) * 2; // ~N(0,1)
    v = params[name] + g * scale * span;
  }
  // Only real angles wrap. `hue_span` is a width and the two `*_per_hue` variances are
  // spreads; all three clamp, or a step off the bottom lands at the top.
  if (isAngularParam(name)) v = ((v % 360) + 360) % 360;
  else v = Math.min(spec.max, Math.max(spec.min, v));
  if (spec.type === 'int') v = Math.round(v);
  params[name] = v;
}

/**
 * A fresh candidate for restart `r`: a base (defaults + inferred structure, or the caller's
 * `from`) plus an enum draw and a broad jitter. The scheme is chosen by restart index (not at
 * random) so every hue scheme gets a fair share of restarts to hill-climb from — the scheme is
 * the one knob a continuous search cannot nudge its way into, so it must be seeded across the
 * whole run rather than gambled on.
 *
 * Restart 0 with a `from` base is returned **untouched**. That is what makes "improve what I
 * have" safe: the search starts by evaluating the palette you already had, so it can only
 * report something at least as good.
 */
function seedCandidate(base, rng, r, { fixed = new Set(), keepEnums = false, searchable = SEARCH_FLOATS } = {}) {
  const p = { ...base };
  if (r === 0 && keepEnums) return p;
  if (!keepEnums || r > 0) {
    if (!fixed.has('hue_scheme')) p.hue_scheme = SCHEMES[r % SCHEMES.length];
    if (!fixed.has('shift_model')) p.shift_model = SHIFT_MODELS[Math.floor(r / SCHEMES.length) % SHIFT_MODELS.length];
  }
  for (const name of searchable) jitterParam(p, name, rng, 0.5);
  return p;
}

// How often a candidate contains a jump rather than only steps, at the start of a restart.
// Annealed to zero by the end of each restart: bold while there is budget left to recover
// from a bad landing, pure hill-climbing when there is not.
//
// 0.2 was measured, not guessed. Over eight RNG seeds and two targets (see UX_PLAN's U6 note
// for the table) rates of 0, 0.2 and 0.35 give recovery means of 4.24 / 4.26 / 4.30 — a wash —
// while the crayon fit goes 3.86 / 3.82 / 4.05. The real gain at 0.2 is in the spread: the
// crayon fit ranges 3.29–4.08 with jumps and 2.41–4.95 without, and a search whose worst case
// is bounded beats one that is sometimes lucky.
const JUMP_RATE = 0.2;

/**
 * Resumable fitter, so a caller (the UI) can run the search in slices without freezing.
 * `step(n)` runs up to `n` evaluations and returns `{ done, bestScore }`; `bestParams` and
 * `bestScore` are always readable. The whole run is a random-restart hill climb: from each
 * start it perturbs a shrinking subset of knobs and keeps only strict improvements.
 *
 * Options (UX_PLAN U6.1):
 *   `from`       start from these parameters instead of defaults + inferred structure. The
 *                first candidate is then exactly `from`, so the result is never worse than
 *                what the caller already had, and the caller's structure is respected rather
 *                than overwritten by `inferStructure`.
 *   `fixed`      names the search must never touch — the parts of the palette already
 *                decided. "Match these colours, but keep my 32 slots and my hue scheme" is
 *                the normal way to want a fit, and without this it was unsayable.
 *   `onProgress` called with `{ progress, bestScore, params }` whenever the best improves, so
 *                a UI can show the palette getting closer instead of a number going down.
 *   `keepLooking(n)` add `n` more evaluations to a finished run, keeping the best so far.
 */
export function makeFitter(targetHexes, {
  seed = 1, iterations = 6000, restarts = 10, from = null, fixed = [], onProgress = null,
} = {}) {
  const rng = makeRng(seed);
  const targetLab = targetHexes.map((h) => rgb8ToOklab(hexToRgb8(h)));
  const structure = inferStructure(targetHexes);
  const fixedSet = new Set(fixed);
  const searchable = SEARCH_FLOATS.filter((n) => !fixedSet.has(n));
  // Fixed at construction so `keepLooking` extends the run with more restarts of the same
  // length, rather than silently stretching every remaining one.
  const budgetPer = Math.max(1, Math.floor(iterations / restarts));
  const base = from ? normalizeParams(from) : { ...defaultParams(), ...structure };
  const seedOpts = { fixed: fixedSet, keepEnums: Boolean(from), searchable };

  let total = iterations;
  let restartIndex = 0;
  let bestParams = seedCandidate(base, rng, restartIndex, seedOpts);
  let bestScore = scoreParams(bestParams, targetLab);
  let cur = bestParams;
  let curScore = bestScore;
  let done = 0;
  let sinceRestart = 0;

  /** Record a new best and tell the caller, if it asked. */
  function improve(params, score) {
    bestScore = score;
    bestParams = params;
    onProgress?.({ progress: done / total, bestScore, params: normalizeParams(params) });
  }

  const fitter = {
    get total() { return total; },
    get bestScore() { return bestScore; },
    get bestParams() { return normalizeParams(bestParams); },
    /** What the search changed, biggest move first — the "how to get there" list. */
    get diff() { return paramDiff(normalizeParams(base), normalizeParams(bestParams)); },
    get progress() { return done / total; },
    get done() { return done >= total; },
    /**
     * Keep looking: extend a finished (or unfinished) run by `extra` evaluations. The best so
     * far is kept, so this only ever improves — "not quite" should cost one more click, not a
     * restart from nothing.
     */
    keepLooking(extra) {
      total += Math.max(0, Math.floor(extra));
      return fitter;
    },
    step(n) {
      const end = Math.min(total, done + n);
      while (done < end) {
        done++;
        sinceRestart++;
        if (sinceRestart >= budgetPer) { // next restart, cycling schemes deterministically
          restartIndex++;
          cur = seedCandidate(base, rng, restartIndex, seedOpts);
          curScore = scoreParams(cur, targetLab);
          sinceRestart = 0;
          if (curScore < bestScore) improve(cur, curScore);
          continue;
        }
        // Anneal both moves together: bold early in a restart, fine near the end.
        const t = sinceRestart / budgetPer;
        const scale = 0.28 * (1 - t) + 0.015;
        const jump = JUMP_RATE * (1 - t);
        const cand = { ...cur };
        const k = 1 + Math.floor(rng() * 3); // perturb 1..3 knobs at a time
        // At most one knob may jump per candidate. Letting all three roll independently makes
        // a majority of candidates a scramble rather than a move, which throws away the local
        // information the hill climb is built on.
        const jumpAt = rng() < jump ? Math.floor(rng() * k) : -1;
        for (let j = 0; j < k; j++) {
          jitterParam(cand, searchable[Math.floor(rng() * searchable.length)], rng, scale, j === jumpAt ? 1 : 0);
        }
        const s = scoreParams(cand, targetLab);
        if (s < curScore) {
          cur = cand;
          curScore = s;
          if (s < bestScore) improve(cand, s);
        }
      }
      return { done: fitter.done, bestScore };
    },
  };
  if (!searchable.length) throw new Error('every searchable parameter is fixed — nothing to fit');
  return fitter;
}

/**
 * Fit a parameter set to a target palette in one call. Returns the best params found (as a
 * normalised set the UI can load like a preset), the achieved fit, the eval count, and the
 * ordered list of what it changed from the starting point.
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
    diff: fitter.diff,
  };
}
