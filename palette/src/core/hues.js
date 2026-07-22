// Hue schemes, perceptual hue spacing, jitter, and circular interpolation.
//
// OKLCH hue is not perceptually uniform: the arc from red to yellow spans 80 degrees
// while yellow to green spans 33, so evenly spaced angles over-sample orange and can
// hand back three near-identical greens. `perceptual_hue_spacing` blends toward a warp
// that pins the six sRGB primaries/secondaries to evenly spaced positions instead.

import { rgb8ToOklch, hueDelta, normHue } from './oklch.js';

/** OKLCH hue angles of the six sRGB primaries and secondaries, in ascending order. */
export const HUE_LANDMARKS = [
  [255, 0, 0], [255, 255, 0], [0, 255, 0], [0, 255, 255], [0, 0, 255], [255, 0, 255],
].map((c) => rgb8ToOklch(c).h);

const LANDMARK_STEP = 60;

/** Interpret an angle as a perceptual coordinate and map it to the actual OKLCH hue. */
export function perceptualToHue(p) {
  const base = HUE_LANDMARKS[0];
  const rel = normHue(p - base);
  const k = Math.floor(rel / LANDMARK_STEP) % 6;
  const t = (rel - k * LANDMARK_STEP) / LANDMARK_STEP;
  const a = HUE_LANDMARKS[k];
  const b = HUE_LANDMARKS[(k + 1) % 6];
  return normHue(a + t * normHue(b - a));
}

/**
 * Interpolate between hue angles by weight `w`.
 * `direction` removes the antipode discontinuity, where base hues on either side of the
 * target would otherwise shift in opposite directions.
 */
export function lerpHue(from, to, w, direction = 'shortest') {
  if (direction === 'always-cw') return normHue(from + w * normHue(to - from));
  if (direction === 'always-ccw') return normHue(from - w * normHue(from - to));
  return normHue(from + w * hueDelta(from, to));
}

/** Circular positions of the poles a scheme distributes its hues across. */
function schemePoles(scheme, root) {
  switch (scheme) {
    case 'complementary': return [root, root + 180];
    case 'split-comp': return [root, root + 150, root + 210];
    case 'triadic': return [root, root + 120, root + 240];
    case 'tetradic': return [root, root + 90, root + 180, root + 270];
    default: return null;
  }
}

/** Base hue angles for a scheme before warping and jitter. */
function schemeAngles(scheme, n, root, span) {
  if (n <= 0) return [];
  if (scheme === 'even') return Array.from({ length: n }, (_, i) => root + (i * 360) / n);
  if (scheme === 'custom') return Array.from({ length: n }, (_, i) => root + (i * span) / n);
  if (scheme === 'analogous') {
    if (n === 1) return [root];
    return Array.from({ length: n }, (_, i) => root + (i / (n - 1) - 0.5) * span);
  }
  const poles = schemePoles(scheme, root);
  // Round-robin hues onto the poles, then fan each pole's members apart.
  const members = poles.map(() => []);
  for (let i = 0; i < n; i++) members[i % poles.length].push(i);
  const spread = Math.min(40, span / (4 * poles.length));
  const out = new Array(n);
  members.forEach((idxs, p) => {
    idxs.forEach((slot, j) => {
      out[slot] = poles[p] + (j - (idxs.length - 1) / 2) * spread;
    });
  });
  return out;
}

/** Push hues apart until no two are closer than `minGap` degrees. */
function separate(hues, minGap) {
  if (hues.length < 2) return hues;
  const out = hues.slice();
  for (let pass = 0; pass < 24; pass++) {
    let moved = false;
    for (let a = 0; a < out.length; a++) {
      for (let b = a + 1; b < out.length; b++) {
        const d = hueDelta(out[a], out[b]);
        if (Math.abs(d) < minGap) {
          const push = (minGap - Math.abs(d)) / 2 + 0.01;
          const sign = d === 0 ? 1 : Math.sign(d);
          out[a] = normHue(out[a] - sign * push);
          out[b] = normHue(out[b] + sign * push);
          moved = true;
        }
      }
    }
    if (!moved) break;
  }
  return out;
}

/**
 * Build the palette's base hue angles from the scheme parameters.
 * `rng` must be the seeded PRNG — jitter is part of the determinism contract.
 */
export function buildHues(params, hueCount, rng) {
  const n = Math.max(0, hueCount | 0);
  if (n === 0) return [];
  const raw = schemeAngles(params.hue_scheme, n, params.root_hue, params.hue_span);
  const w = params.perceptual_hue_spacing;
  const warped = raw.map((a) => (w > 0 ? lerpHue(normHue(a), perceptualToHue(a), w) : normHue(a)));
  const jittered = warped.map((h) => normHue(h + (rng() * 2 - 1) * params.hue_jitter));
  return separate(jittered, n > 1 ? Math.min(8, 300 / n) : 0);
}

/** Centres of the `count` largest gaps in a hue set — where accents can fill holes. */
export function hueGapCenters(hues, count) {
  const out = [];
  const set = hues.slice();
  for (let k = 0; k < count; k++) {
    if (set.length === 0) {
      out.push(normHue(k * 90));
      set.push(normHue(k * 90));
      continue;
    }
    const sorted = set.slice().sort((a, b) => a - b);
    let bestGap = -1;
    let bestCenter = 0;
    for (let i = 0; i < sorted.length; i++) {
      const a = sorted[i];
      const b = i + 1 < sorted.length ? sorted[i + 1] : sorted[0] + 360;
      const gap = b - a;
      if (gap > bestGap) {
        bestGap = gap;
        bestCenter = normHue(a + gap / 2);
      }
    }
    out.push(bestCenter);
    set.push(bestCenter);
  }
  return out;
}
