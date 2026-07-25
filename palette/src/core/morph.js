// Morphing one parameter set into another (UX_PLAN U6.2 — IMPROVEMENTS item 3).
//
// Two palettes side by side answer "which do I prefer?". Neither answers "what is actually
// different?", and the parameter diff answers that in words rather than in colour. The morph
// answers it by showing the road between them: drag from 0 to 1 and watch which part of the
// picture moves. A palette that barely changes until 0.5 and then jumps was separated by an
// enum, not by a number — and that is visible in a way no list of 72 rows is.
//
// Three rules, each of which exists because the naive version is wrong:
//
//   * **Angles take the short way round.** Lerping 350° to 10° through 180 walks the whole
//     colour wheel backwards through cyan to move a hue by twenty degrees.
//   * **Enums and bools snap at the halfway point.** There is no half of `triadic`.
//   * **`seed` snaps too**, even though it is an integer. Walking it re-rolls the jitter at
//     every step, which turns a morph into a shimmer and hides the structural change the
//     morph exists to show.

import { PARAMS, isAngularParam, normalizeParams } from './params.js';
import { normHue, hueDelta } from './oklch.js';

/** Parameters that are numeric but must snap rather than travel. */
const SNAP_NUMERIC = new Set(['seed']);

/**
 * A parameter set `t` of the way from `a` to `b` (`t` clamped to 0..1).
 * `morphParams(a, b, 0)` is `a` and `morphParams(a, b, 1)` is `b`, exactly.
 */
export function morphParams(a, b, t) {
  const from = normalizeParams(a);
  const to = normalizeParams(b);
  const w = Math.min(1, Math.max(0, Number(t) || 0));
  if (w === 0) return from;
  if (w === 1) return to;
  const out = {};
  for (const spec of PARAMS) {
    const { name } = spec;
    if (spec.type === 'enum' || spec.type === 'bool' || SNAP_NUMERIC.has(name)) {
      out[name] = w < 0.5 ? from[name] : to[name];
      continue;
    }
    const v = isAngularParam(name)
      ? normHue(from[name] + w * hueDelta(from[name], to[name]))
      : from[name] + w * (to[name] - from[name]);
    out[name] = spec.type === 'int' ? Math.round(v) : v;
  }
  return normalizeParams(out);
}

/**
 * Where along a morph something discontinuous happens — the `t` values at which an enum,
 * a bool or the seed flips. Shown as ticks under the slider, because those are the only
 * places the picture can jump, and a jump you were not expecting reads as a bug.
 */
export function morphSnapPoints(a, b) {
  const from = normalizeParams(a);
  const to = normalizeParams(b);
  const snaps = [];
  for (const spec of PARAMS) {
    const isSnap = spec.type === 'enum' || spec.type === 'bool' || SNAP_NUMERIC.has(spec.name);
    if (isSnap && from[spec.name] !== to[spec.name]) snaps.push(spec.name);
  }
  return snaps.length ? [{ t: 0.5, names: snaps }] : [];
}
