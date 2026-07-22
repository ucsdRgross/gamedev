// Repair pass: enforce minimum perceptual distance, foreground/background separation
// and hex uniqueness (PLAN §2.5).
//
// This runs AFTER bit-depth quantisation, because quantisation can collapse two
// distinct colours onto the same legal grid point. Locked and overridden slots are
// never moved — an explicitly chosen colour must not be silently relocated.
//
// Relocation is strict cost-descent rather than pairwise nudging. A slot squeezed
// between two neighbours can be pushed off one only to be pushed back by the other,
// and pairwise nudging oscillates forever in that situation. Scoring a candidate
// against the whole palette instead means every accepted move lowers the total
// violation cost by exactly the amount it lowers the mover's, so the sweep converges.

import { deltaEOK, contrastRatio, clamp } from './oklch.js';
import { midIndex } from './ramp.js';

/**
 * How readily a slot may be moved; higher numbers yield first. Bridges yield to
 * everything: they are the remainder tier, so displacing one costs the palette least.
 */
export const LAYER_PRIORITY = {
  anchor: 0,
  fg: 1,
  accent: 2,
  neutral: 3,
  'neutral-warm': 4,
  bg: 5,
  bridge: 6,
};

/** Foreground/background separation is expressed as a fraction of this deltaE. */
export const FG_BG_SEP_SCALE = 30;

const MAX_SWEEPS = 24;

/** True when the two entries sit on opposite sides of the foreground/background split. */
function isFgBgPair(a, b) {
  const fg = (e) => e.layer === 'fg' || e.layer === 'bridge' || e.layer === 'accent';
  return (fg(a) && b.layer === 'bg') || (fg(b) && a.layer === 'bg');
}

/** Minimum acceptable distance between two specific entries. */
function threshold(a, b, params) {
  const base = params.min_delta_e;
  if (isFgBgPair(a, b)) {
    return Math.max(base, params.fg_bg_separation_min * FG_BG_SEP_SCALE);
  }
  return base;
}

/** Pick which of a violating pair moves, or null when both are pinned. */
function chooseMover(a, b) {
  const movable = (e) => !e.fixed;
  if (!movable(a) && !movable(b)) return null;
  if (!movable(a)) return b;
  if (!movable(b)) return a;
  const pa = LAYER_PRIORITY[a.layer] ?? 9;
  const pb = LAYER_PRIORITY[b.layer] ?? 9;
  if (pa !== pb) return pa > pb ? a : b;
  // Same layer: within one ramp, move the step further from the midtone outward, which
  // separates the pair without ever reordering the ramp.
  if (a.hueIndex === b.hueIndex && a.steps > 1 && b.steps > 1) {
    const da = Math.abs(a.step - midIndex(a.steps));
    const db = Math.abs(b.step - midIndex(b.steps));
    if (da !== db) return da > db ? a : b;
  }
  return a.id < b.id ? b : a; // deterministic tie-break
}

/**
 * Total squared shortfall between one entry and the rest of the palette.
 * `ceiling` lets the caller abandon a candidate as soon as it is known to be worse
 * than the incumbent, which is most of them.
 */
function moverCost(mover, entries, params, ceiling = Infinity) {
  let cost = 0;
  for (const e of entries) {
    if (e === mover) continue;
    const gap = threshold(mover, e, params) - deltaEOK(mover.lab, e.lab);
    if (gap > 0) {
      cost += gap * gap;
      if (cost >= ceiling) return cost;
    }
  }
  return cost;
}

/** Candidate OKLCH positions for a slot, ordered from smallest displacement outward. */
function candidates(start, lo, hi, away, cMax) {
  const out = [];
  const seen = new Set();
  const push = (L, C) => {
    const c = Math.min(C, cMax);
    const key = `${L.toFixed(4)}:${c.toFixed(4)}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push({ L, C: c, h: start.h });
  };
  // Fine steps first: a slot boxed in on both sides often needs only a hair of
  // lightness, and a coarser first offer would overshoot into the other neighbour.
  for (const d of [0.004, 0.007, 0.012, 0.02, 0.03, 0.045, 0.065, 0.09, 0.12, 0.16, 0.21, 0.28, 0.36]) {
    for (const dir of [away, -away]) push(clamp(start.L + dir * d, lo, hi), start.C);
  }
  for (const s of [0.7, 1.35, 0.45, 1.8, 0.2, 2.4]) push(start.L, start.C * s);
  // A little two-axis coverage for slots pinned at the end of their lightness window.
  for (const d of [0.05, 0.12]) {
    for (const s of [0.6, 1.6]) {
      for (const dir of [away, -away]) {
        push(clamp(start.L + dir * d, lo, hi), start.C * s);
      }
    }
  }
  return out;
}

/**
 * True when placing `mover` at lightness `L` would reorder its own ramp.
 * Repair is free to move a ramp step, but never past its neighbours — a ramp that is
 * not monotonic in lightness has stopped being a ramp.
 */
function breaksRampOrder(mover, L, entries) {
  if (mover.steps <= 1 || (mover.layer !== 'fg' && mover.layer !== 'bg')) return false;
  for (const e of entries) {
    if (e === mover || e.layer !== mover.layer || e.hueIndex !== mover.hueIndex) continue;
    if (e.step < mover.step && L <= e.oklch.L) return true;
    if (e.step > mover.step && L >= e.oklch.L) return true;
  }
  return false;
}

/** Move one slot to the position that best relieves its constraint violations. */
function relocate(mover, entries, params, realize) {
  const start = { ...mover.oklch };
  const lo = mover.lMin ?? 0.01;
  const hi = mover.lMax ?? 0.99;
  let bestCost = moverCost(mover, entries, params);
  if (bestCost <= 0) return false;
  let bestColor = start;

  // Prefer moving away from the closest offender.
  let closest = null;
  let closestD = Infinity;
  for (const e of entries) {
    if (e === mover) continue;
    const d = deltaEOK(mover.lab, e.lab);
    if (d < closestD) {
      closestD = d;
      closest = e;
    }
  }
  const away = Math.sign(start.L - (closest?.oklch.L ?? 0.5)) || (start.L >= 0.5 ? 1 : -1);

  // Repair may raise chroma to break a tie, but not past the palette's own ceiling.
  // Accents already sit above it by design, so they keep whatever they arrived with.
  const cMax = Math.max(start.C, params.chroma_cap);
  for (const c of candidates(start, lo, hi, away, cMax)) {
    if (breaksRampOrder(mover, c.L, entries)) continue;
    Object.assign(mover, realize(c));
    const cost = moverCost(mover, entries, params, bestCost);
    if (cost < bestCost - 1e-12) {
      bestCost = cost;
      bestColor = c;
      if (cost <= 0) break;
    }
  }
  Object.assign(mover, realize(bestColor));
  return bestColor !== start;
}

/** Total squared shortfall across every pair in the palette. */
function totalCost(entries, params) {
  let cost = 0;
  for (let i = 0; i < entries.length; i++) {
    for (let j = i + 1; j < entries.length; j++) {
      const gap = threshold(entries[i], entries[j], params) - deltaEOK(entries[i].lab, entries[j].lab);
      if (gap > 0) cost += gap * gap;
    }
  }
  return cost;
}

/**
 * Last-resort relaxation: sort every movable slot by lightness and space them out.
 *
 * Cost-descent moves one slot at a time, so it cannot break a chain — in a
 * near-greyscale palette every colour is boxed in by the next one and no single move
 * lowers the total. Resolving the whole chain at once does. Sorting by lightness
 * preserves each ramp's internal order, and the result is kept only if it genuinely
 * reduces the violation cost, so a palette that was already fine is never flattened.
 */
function relaxAlongLightness(entries, params, realize) {
  const movable = entries.filter((e) => !e.fixed && e.layer !== 'anchor');
  if (movable.length < 2) return;

  const before = totalCost(entries, params);
  const snapshot = movable.map((e) => ({ entry: e, oklch: { ...e.oklch } }));
  // Ties break on ramp position, never on id: `bg_h0_10` sorts before `bg_h0_9` as a
  // string, which would silently invert the ramp.
  const order = movable.slice().sort((a, b) => (
    a.oklch.L - b.oklch.L
    || (a.layer === b.layer && a.hueIndex === b.hueIndex ? a.step - b.step : 0)
    || (a.id < b.id ? -1 : 1)
  ));

  const lo = Math.max(...order.map((e) => e.lMin ?? 0.01));
  const hi = Math.min(...order.map((e) => e.lMax ?? 0.99));
  // Space for the strictest threshold in play, not just the base one: a foreground and
  // a background slot need `fg_bg_separation_min` between them, and in a near-grey
  // palette lightness is the only axis that can supply it.
  const strictest = Math.max(
    params.min_delta_e, params.fg_bg_separation_min * FG_BG_SEP_SCALE,
  ) / 100;
  const gap = Math.min(strictest, (hi - lo) / Math.max(1, order.length - 1));
  const ls = order.map((e) => e.oklch.L);

  for (let i = 1; i < ls.length; i++) ls[i] = Math.max(ls[i], ls[i - 1] + gap);
  const overflow = ls[ls.length - 1] - hi;
  if (overflow > 0) for (let i = 0; i < ls.length; i++) ls[i] -= overflow;
  for (let i = ls.length - 2; i >= 0; i--) ls[i] = Math.min(ls[i], ls[i + 1] - gap);
  for (let i = 0; i < ls.length; i++) ls[i] = clamp(ls[i], lo, hi);

  order.forEach((e, i) => Object.assign(e, realize({ ...e.oklch, L: ls[i] })));
  if (totalCost(entries, params) >= before || !rampsOrdered(entries)) {
    for (const s of snapshot) Object.assign(s.entry, realize(s.oklch));
  }
}

/** True when every foreground and background ramp is still strictly increasing in L. */
function rampsOrdered(entries) {
  const ramps = new Map();
  for (const e of entries) {
    if (e.layer !== 'fg' && e.layer !== 'bg') continue;
    const key = `${e.layer}:${e.hueIndex}`;
    if (!ramps.has(key)) ramps.set(key, []);
    ramps.get(key).push(e);
  }
  for (const ramp of ramps.values()) {
    ramp.sort((a, b) => a.step - b.step);
    for (let i = 1; i < ramp.length; i++) {
      if (ramp[i].oklch.L <= ramp[i - 1].oklch.L) return false;
    }
  }
  return true;
}

/** Push the two universal anchors apart until they clear the WCAG contrast floor. */
function enforceAnchorContrast(entries, params, realize) {
  const dark = entries.find((e) => e.id === 'universal_dark');
  const light = entries.find((e) => e.id === 'universal_light');
  if (!dark || !light) return null;
  for (let i = 0; i < 50; i++) {
    if (contrastRatio(dark.rgb8, light.rgb8) >= params.min_anchor_contrast) return null;
    let moved = false;
    if (!dark.fixed && dark.oklch.L > 0.005) {
      Object.assign(dark, realize({ ...dark.oklch, L: Math.max(0, dark.oklch.L - 0.02) }));
      moved = true;
    }
    if (!light.fixed && light.oklch.L < 0.995) {
      Object.assign(light, realize({ ...light.oklch, L: Math.min(1, light.oklch.L + 0.02) }));
      moved = true;
    }
    if (!moved) break;
  }
  const got = contrastRatio(dark.rgb8, light.rgb8);
  return got >= params.min_anchor_contrast
    ? null
    : `anchor contrast ${got.toFixed(2)} below the requested ${params.min_anchor_contrast}`;
}

/**
 * Walk clashing entries along L until every hex in the palette is distinct.
 * Best-effort: a slot boxed in between two ramp neighbours less than one grid step
 * apart genuinely has nowhere to go. Unresolvable clashes are skipped and reported,
 * so one stuck pair does not abandon the rest of the palette.
 */
function forceUnique(entries, params, realize) {
  const stuck = new Set();
  for (let pass = 0; pass < 64; pass++) {
    const byHex = new Map();
    let a = null;
    let b = null;
    for (const e of entries) {
      const prev = byHex.get(e.hex);
      if (prev && !stuck.has(`${prev.id}|${e.id}`)) {
        a = prev;
        b = e;
        break;
      }
      if (!prev) byHex.set(e.hex, e);
    }
    if (!a) {
      const hexes = new Set(entries.map((e) => e.hex));
      return hexes.size === entries.length
        ? []
        : [`could not give every slot a unique hex (${entries.length - hexes.size} duplicate(s) remain)`];
    }
    const mover = chooseMover(a, b) ?? b;
    const start = { ...mover.oklch };
    const lo = mover.lMin ?? 0.01;
    const hi = mover.lMax ?? 0.99;
    const away = Math.sign(start.L - 0.5) || 1;
    const taken = new Set(entries.filter((e) => e !== mover).map((e) => e.hex));
    let placed = false;
    for (const c of candidates(start, lo, hi, away, Math.max(start.C, params.chroma_cap))) {
      if (breaksRampOrder(mover, c.L, entries)) continue;
      const r = realize(c);
      if (!taken.has(r.hex)) {
        Object.assign(mover, r);
        placed = true;
        break;
      }
    }
    if (!placed) {
      Object.assign(mover, realize(start));
      stuck.add(`${a.id}|${b.id}`);
    }
  }
  return ['hex uniqueness did not converge'];
}

/**
 * Enforce the palette's quality constraints, sweeping to a fixed point.
 * `realize` maps an OKLCH triple through gamut mapping and quantisation to a final
 * entry; repair calls it every time it moves a colour, so constraints are always
 * evaluated on the colour that will actually be emitted.
 */
export function repairPalette(entries, params, realize) {
  const warnings = [];
  const anchorWarning = enforceAnchorContrast(entries, params, realize);
  if (anchorWarning) warnings.push(anchorWarning);

  let sweeps = 0;
  for (; sweeps < MAX_SWEEPS; sweeps++) {
    // Collect the slots to move first, then move each once. `relocate` already scores
    // a candidate against the whole palette, so relocating per violating pair would
    // redo the same work for every conflict a single slot is involved in.
    const movers = new Set();
    for (let i = 0; i < entries.length; i++) {
      for (let j = i + 1; j < entries.length; j++) {
        const a = entries[i];
        const b = entries[j];
        const thr = threshold(a, b, params);
        if (thr <= 0 || deltaEOK(a.lab, b.lab) >= thr) continue;
        const mover = chooseMover(a, b);
        if (mover) movers.add(mover);
      }
    }
    if (movers.size === 0) break;
    let moves = 0;
    for (const mover of movers) {
      if (relocate(mover, entries, params, realize)) moves++;
    }
    if (moves === 0) {
      // Local descent is stuck. Try to break the chain, then let the sweeps resume on
      // whatever the relaxation left behind.
      relaxAlongLightness(entries, params, realize);
      if (!residualViolations(entries, params).length) break;
      let recovered = 0;
      for (const mover of movers) {
        if (relocate(mover, entries, params, realize)) recovered++;
      }
      if (recovered === 0) break;
    }
  }

  // The sweeps can also run out of budget rather than getting stuck, so try the chain
  // break once more before giving up, and re-sweep whatever it frees.
  if (residualViolations(entries, params).length) {
    relaxAlongLightness(entries, params, realize);
    for (let extra = 0; extra < 6; extra++) {
      let moves = 0;
      for (const e of entries) {
        if (!e.fixed && relocate(e, entries, params, realize)) moves++;
      }
      if (moves === 0) break;
    }
  }

  if (params.force_unique_hex) warnings.push(...forceUnique(entries, params, realize));

  const residual = residualViolations(entries, params);
  if (residual.length) {
    warnings.push(
      `${residual.length} pair(s) still closer than the requested minimum distance` +
        ` (closest: ${residual[0].a} / ${residual[0].b} at deltaE ${residual[0].deltaE.toFixed(2)})`,
    );
  }
  return { warnings, sweeps };
}

/** Pairs still violating their distance threshold, worst first. */
export function residualViolations(entries, params) {
  const out = [];
  for (let i = 0; i < entries.length; i++) {
    for (let j = i + 1; j < entries.length; j++) {
      const a = entries[i];
      const b = entries[j];
      const thr = threshold(a, b, params);
      const d = deltaEOK(a.lab, b.lab);
      if (d < thr) out.push({ a: a.id, b: b.id, deltaE: d, threshold: thr });
    }
  }
  return out.sort((x, y) => x.deltaE - y.deltaE);
}
