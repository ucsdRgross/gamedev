// Budget-driven allocation (PLAN §3).
//
// The palette must contain exactly K colours. Hue count is DERIVED from the budget,
// never the other way round, and every tier is re-entrant: leftover budget lengthens
// ramps, splits neutrals and extends background ramps. It never emits filler accents —
// a hue-count-driven allocator that pads the remainder with high-chroma singletons
// produces 20 structured colours plus a dozen unrelated neons.

/** Hue count derived from the colour budget (PLAN §3.1). */
export function deriveHueCount(k) {
  if (k <= 7) return 1;
  if (k <= 11) return 2;
  if (k <= 15) return 3;
  if (k <= 23) return 4;
  if (k <= 39) return 5;
  if (k <= 55) return 6;
  return 8;
}

/** Hue count actually used: the derived value unless manually overridden. */
export function effectiveHueCount(params) {
  const manual = params.hue_count | 0;
  const n = manual > 0 ? manual : deriveHueCount(params.color_count);
  // A hue still needs at least one slot after the two anchors are taken.
  return Math.max(1, Math.min(n, Math.max(1, params.color_count - 2)));
}

/** Order in which the twelve allocation rounds claim budget, per `tier_priority`. */
function roundOrder(priority) {
  const standard = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  const move = (list, picks) => [...picks, ...list.filter((r) => !picks.includes(r))];
  switch (priority) {
    case 'background-first': return move(standard, [1, 5, 6, 11]);
    case 'neutrals-first': return move(standard, [1, 4, 10]);
    case 'ramps-first': return move(standard, [1, 2, 3, 7, 8]);
    default: return standard;
  }
}

/**
 * Decide the palette's structure for the given budget.
 * Returns per-hue ramp lengths and tier counts summing to exactly `color_count`.
 */
export function allocate(params) {
  const K = params.color_count;
  const hues = effectiveHueCount(params);
  const plan = {
    hueCount: hues,
    fgLen: new Array(hues).fill(0),
    bgLen: new Array(hues).fill(0),
    neutrals: 0,
    warmNeutrals: 0,
    accents: 0,
    bridges: 0,
  };

  let budget = K - 2; // two universal anchors come off the top
  const claim = (fn) => {
    if (budget > 0) {
      fn();
      budget--;
    }
  };
  const growFg = (target) => {
    if (params.fg_ramp_length < target) return;
    for (let i = 0; i < hues; i++) claim(() => { plan.fgLen[i]++; });
  };
  const growBg = (target) => {
    if (params.bg_ramp_length < target) return;
    for (let i = 0; i < hues; i++) claim(() => { plan.bgLen[i]++; });
  };

  const rounds = {
    1: () => growFg(1),
    2: () => growFg(2),
    3: () => growFg(3),
    4: () => {
      for (let n = 0; n < Math.min(3, params.neutral_count); n++) claim(() => { plan.neutrals++; });
    },
    5: () => growBg(1),
    6: () => growBg(2),
    7: () => growFg(4),
    8: () => growFg(5),
    9: () => {
      for (let n = 0; n < params.accent_count; n++) claim(() => { plan.accents++; });
    },
    10: () => {
      if (!params.neutral_split) return;
      for (let n = 0; n < params.neutral_count; n++) claim(() => { plan.warmNeutrals++; });
    },
    11: () => growBg(3),
    12: () => {
      if (hues < 2) return;
      for (let n = 0; n < hues; n++) claim(() => { plan.bridges++; });
    },
  };

  for (const r of roundOrder(params.tier_priority)) rounds[r]();

  // Leftover budget deepens what is already there rather than inventing new colours.
  let guard = 0;
  while (budget > 0 && guard++ < 4096) {
    for (let i = 0; i < hues && budget > 0; i++) claim(() => { plan.fgLen[i]++; });
    for (let i = 0; i < hues && budget > 0; i++) claim(() => { plan.bgLen[i]++; });
    if (budget > 0) claim(() => { plan.neutrals++; });
    if (budget > 0 && params.neutral_split) claim(() => { plan.warmNeutrals++; });
  }

  plan.total = 2 + planSlotCount(plan);
  return plan;
}

/** Number of non-anchor slots described by a plan. */
function planSlotCount(plan) {
  const sum = (a) => a.reduce((x, y) => x + y, 0);
  return (
    sum(plan.fgLen) + sum(plan.bgLen) +
    plan.neutrals + plan.warmNeutrals + plan.accents + plan.bridges
  );
}

/**
 * Expand a plan into slot descriptors in stable role order (PLAN §3.4).
 * Ordering is by role, never by generation order: nudging a slider must not reshuffle
 * exported indices, or re-importing into Aseprite scrambles finished artwork.
 */
export function buildSlots(plan) {
  const slots = [{ id: 'universal_dark', layer: 'anchor', kind: 'dark' }];
  for (let i = 0; i < plan.hueCount; i++) {
    for (let j = 0; j < plan.fgLen[i]; j++) {
      slots.push({ id: `fg_h${i}_${j}`, layer: 'fg', hueIndex: i, step: j, steps: plan.fgLen[i] });
    }
  }
  for (let k = 0; k < plan.bridges; k++) {
    slots.push({ id: `bridge_${k}`, layer: 'bridge', hueIndex: k, steps: plan.bridges });
  }
  for (let k = 0; k < plan.neutrals; k++) {
    slots.push({ id: `neutral_${k}`, layer: 'neutral', step: k, steps: plan.neutrals });
  }
  for (let k = 0; k < plan.warmNeutrals; k++) {
    slots.push({ id: `neutral_warm_${k}`, layer: 'neutral-warm', step: k, steps: plan.warmNeutrals });
  }
  for (let i = 0; i < plan.hueCount; i++) {
    for (let j = 0; j < plan.bgLen[i]; j++) {
      slots.push({ id: `bg_h${i}_${j}`, layer: 'bg', hueIndex: i, step: j, steps: plan.bgLen[i] });
    }
  }
  for (let k = 0; k < plan.accents; k++) {
    slots.push({ id: `accent_${k}`, layer: 'accent', step: k, steps: plan.accents });
  }
  slots.push({ id: 'universal_light', layer: 'anchor', kind: 'light' });
  return slots;
}
