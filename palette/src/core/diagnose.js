// Palette diagnostics (UX_PLAN U7.1 — item 14): what is wrong with this palette, and what
// to change to fix it.
//
// The pane already shows the generator's own constraint *warnings*. This is the other half:
// the faults the generator is not required to prevent — a wasted near-duplicate slot, a hole
// in the value ladder, a pair that collapses under deutan, a colour that could not be as
// saturated as it was asked to be. Every one of them is computable from data the palette
// already carries, and every one of them has a knob that moves it.
//
// **A fix is never guessed.** Each check exposes a `metric` — a single number, lower is
// better, measured on a palette — and a list of candidate parameter patches. A candidate is
// only offered after it has been *generated and re-measured*: it is attached to the finding
// only if the palette it produces scores strictly better on that check. So "raise the minimum
// distance to 5.5" is a claim that has been tested, not a plausible-sounding suggestion, and
// a check that has no fix that works honestly says so and offers the swatches instead.
//
// Thresholds are measured against the twenty-one presets rather than chosen, because a
// diagnostic that fires on every palette is noise. The measurement behind each one is written
// down beside it.
//
// DOM-free, like everything in `src/core`. `sceneUsage` counts are passed in rather than
// imported: core may not import `src/scenes/`.

import { generatePalette } from './generate.js';
import { PARAM_BY_NAME, coerceParam } from './params.js';
import { deltaEOK, contrastRatio, rgb8ToOklab } from './oklch.js';
import { simulateColorblind } from './analysis.js';
import { hueName } from './describe.js';

// ---------------------------------------------------------------------------
// Thresholds, and what they were measured against
// ---------------------------------------------------------------------------

/**
 * Below this ΔE two slots are the same colour wearing two names.
 *
 * Measured over the twenty-one presets, the closest pair in a palette sits at a median ΔE of
 * 4.05 — i.e. exactly on the default `min_delta_e`, because repair puts it there. The floor
 * here is well under that, so this fires on a palette whose own minimum has been turned down,
 * not on every palette that uses the default.
 */
export const NEAR_DUPE_DE = 2.5;

/** A gap in the value ladder is a hole once it is this many times the average step. */
const HOLE_RATIO = 3;

/** …and never below this, so a small palette's naturally coarse ladder is not a fault. */
const HOLE_FLOOR = 0.12;

/** A palette needs at least this many colours before a hole in its ladder means anything. */
const HOLE_MIN_COLORS = 12;

/**
 * A hue hole worth mentioning, in degrees, and how much bigger than the palette's other gaps
 * it has to be. Measured over the presets (families clustered at 20°): a palette with four or
 * more hue families has a largest gap of 46–102°, so 90° alone would call ordinary palettes
 * faulty. The ratio test is what distinguishes "one hue is missing" — the actual defect —
 * from "this palette covers a deliberately narrow arc", where every gap is wide.
 */
const HUE_GAP_DEG = 90;
const HUE_GAP_RATIO = 2;

/** Hues within this many degrees are the same family, not two. */
const HUE_CLUSTER_DEG = 20;

/** A colour needs this much chroma before it has a hue worth counting. */
const CHROMATIC_C = 0.04;

/**
 * A colour-vision collision: colours this far apart to normal vision that come this close
 * under a dichromat simulation. The wide gate on the first number is deliberate — every
 * palette has pairs that are *already* similar and stay similar, and reporting those says
 * nothing. What is worth knowing is the pair the eye reads as unmistakably different and a
 * dichromat cannot tell apart at all, because that is where colour is carrying meaning alone.
 */
const CVD_CLEAR_DE = 10;
const CVD_COLLIDE_DE = 3;

/** WCAG AA for body text. A background no anchor clears is a background text cannot sit on. */
const TEXT_CONTRAST = 4.5;

/** Chroma the generator asked for and did not get, above which the swatch is worth flagging. */
export const DIVERGENCE_C = 0.05;

/** How many findings any one check contributes, so one fault cannot fill the whole card. */
const PER_CHECK = 3;

/**
 * How much of a problem a candidate patch has to remove before it is called a fix.
 *
 * Measured over the presets, a merely-strictly-better bar offers things like "raise the
 * lightness step" against eight colour-vision collisions on the strength of removing one of
 * them — a palette-wide change sold as a fix for a fault it barely touches. A quarter of the
 * problem is the smallest gain worth putting a button on.
 */
const FIX_GAIN = 0.75;

// ---------------------------------------------------------------------------
// Small shared measurements
// ---------------------------------------------------------------------------

/** Every unordered pair of entries with its perceptual distance, closest first. */
function pairs(entries) {
  const out = [];
  for (let i = 0; i < entries.length; i++) {
    for (let j = i + 1; j < entries.length; j++) {
      out.push({ a: entries[i], b: entries[j], deltaE: deltaEOK(entries[i].lab, entries[j].lab) });
    }
  }
  return out.sort((x, y) => x.deltaE - y.deltaE);
}

/** The chromatic entries' hue angles collapsed into families, in ascending order. */
function hueFamilies(palette) {
  const hs = palette.entries
    .filter((e) => e.actual.C > CHROMATIC_C)
    .map((e) => e.actual.h)
    .sort((a, b) => a - b);
  const out = [];
  for (const h of hs) {
    const last = out[out.length - 1];
    if (last && h - last.end <= HUE_CLUSTER_DEG) last.end = h;
    else out.push({ start: h, end: h });
  }
  // The wrap: a family straddling 0° arrives as one cluster at each end of the sorted list.
  if (out.length > 1 && out[0].start + 360 - out[out.length - 1].end <= HUE_CLUSTER_DEG) {
    out[0].start = out[out.length - 1].start - 360;
    out.pop();
  }
  return out;
}

/** The gaps between hue families, each `{ from, to, size }`, largest first. */
function hueGaps(families) {
  if (families.length < 2) return [];
  return families
    .map((f, i) => {
      const next = families[(i + 1) % families.length];
      return { from: f.end, to: next.start, size: (((next.start - f.end) % 360) + 360) % 360 };
    })
    .sort((x, y) => y.size - x.size);
}

/**
 * The one hue gap worth reporting, or null.
 *
 * Two conditions, and both matter. Wider than `HUE_GAP_DEG` is what makes it a hole; wider
 * than `HUE_GAP_RATIO` times the palette's other gaps is what makes it *this palette's* hole
 * rather than the shape of a deliberately narrow arc, where every gap is wide.
 */
function worstHueGap(palette) {
  const families = hueFamilies(palette);
  if (families.length < 3) return null;
  const gaps = hueGaps(families);
  const rest = median(gaps.slice(1).map((g) => g.size));
  const worst = gaps[0];
  if (worst.size <= HUE_GAP_DEG || worst.size < HUE_GAP_RATIO * rest) return null;
  return worst;
}

/** Median of a numeric array (0 for an empty one). */
function median(xs) {
  if (!xs.length) return 0;
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

/**
 * The non-anchor entries in ascending lightness — the palette's value ladder.
 * The anchors are excluded because they are *meant* to sit alone at the extremes: the gap
 * between the darkest colour and the outline black is the anchor doing its job.
 */
function valueLadder(palette) {
  return palette.entries
    .filter((e) => e.layer !== 'anchor')
    .sort((a, b) => a.actual.L - b.actual.L);
}

/** Gaps in the value ladder wider than a hole threshold, widest first. */
function valueHoles(palette) {
  const ladder = valueLadder(palette);
  if (ladder.length < HOLE_MIN_COLORS) return [];
  const span = ladder[ladder.length - 1].actual.L - ladder[0].actual.L;
  const limit = Math.max(HOLE_FLOOR, HOLE_RATIO * (span / (ladder.length - 1)));
  const out = [];
  for (let i = 1; i < ladder.length; i++) {
    const size = ladder[i].actual.L - ladder[i - 1].actual.L;
    if (size > limit) out.push({ below: ladder[i - 1], above: ladder[i], size, limit });
  }
  return out.sort((x, y) => y.size - x.size);
}

/** Pairs that read as clearly different colours but collapse under a dichromat simulation. */
function cvdCollisions(palette) {
  const types = ['protan', 'deutan', 'tritan'];
  const sim = new Map();
  const simLab = (entry, type) => {
    const key = `${entry.id}:${type}`;
    if (!sim.has(key)) sim.set(key, rgb8ToOklab(simulateColorblind(entry.rgb8, type)));
    return sim.get(key);
  };
  const out = [];
  for (const pair of pairs(palette.entries)) {
    if (pair.deltaE < CVD_CLEAR_DE) continue;
    for (const type of types) {
      const d = deltaEOK(simLab(pair.a, type), simLab(pair.b, type));
      if (d < CVD_COLLIDE_DE) {
        out.push({ ...pair, type, under: d });
        break;
      }
    }
  }
  return out.sort((x, y) => x.under - y.under);
}

/** How much chroma one entry lost between what was requested and what sRGB could hold. */
export function entryDivergence(entry) {
  const lost = entry.oklch.C - entry.actual.C;
  if (!(lost > DIVERGENCE_C)) return null;
  return {
    chromaLost: lost,
    requested: entry.oklch.C,
    achieved: entry.actual.C,
    note: `chroma reduced ${entry.oklch.C.toFixed(3)} → ${entry.actual.C.toFixed(3)} to fit sRGB`,
  };
}

/** Background colours that neither anchor can carry legible text on. */
function unreadableBackgrounds(palette) {
  const dark = palette.entries.find((e) => e.id === 'universal_dark');
  const light = palette.entries.find((e) => e.id === 'universal_light');
  if (!dark || !light) return [];
  return palette.entries
    .filter((e) => e.layer === 'bg')
    .map((e) => ({
      entry: e,
      best: Math.max(contrastRatio(e.rgb8, dark.rgb8), contrastRatio(e.rgb8, light.rgb8)),
    }))
    .filter((r) => r.best < TEXT_CONTRAST)
    .sort((x, y) => x.best - y.best);
}

// ---------------------------------------------------------------------------
// The checks
// ---------------------------------------------------------------------------

/**
 * A check is a metric plus the findings that explain it plus the patches worth trying.
 *
 * `metric` must be measurable on *any* palette, not only the one being diagnosed: that is what
 * makes a candidate fix verifiable. `fixes` returns patches in the order they should be tried,
 * best-first, and the first one that lowers the metric is the one offered.
 */
export const CHECKS = [
  {
    id: 'duplicates',
    severity: 'high',
    metric(palette) {
      const limit = Math.max(NEAR_DUPE_DE, palette.params.min_delta_e);
      return pairs(palette.entries).filter((p) => p.deltaE < limit).length;
    },
    findings(palette) {
      const limit = Math.max(NEAR_DUPE_DE, palette.params.min_delta_e);
      const close = pairs(palette.entries).filter((p) => p.deltaE < limit);
      const asked = palette.params.min_delta_e >= NEAR_DUPE_DE;
      return close.slice(0, PER_CHECK).map((p) => ({
        title: 'Two colours are near-duplicates',
        detail: `${p.a.role} and ${p.b.role} are only ΔE ${p.deltaE.toFixed(2)} apart`
          + (asked ? `, below the ΔE ${limit.toFixed(1)} this palette asks for` : ' — one of the two slots is doing no work'),
        entries: [p.a.id, p.b.id],
        key: `${p.a.id}|${p.b.id}`,
        weight: limit - p.deltaE,
      }));
    },
    fixes(palette) {
      const worst = pairs(palette.entries)[0]?.deltaE ?? 0;
      return [
        { label: `Raise the minimum distance to ${(worst + 1.5).toFixed(1)}`, params: { min_delta_e: worst + 1.5 } },
        { label: 'Spend two fewer colours', params: { color_count: palette.params.color_count - 2 } },
        { label: 'Open the ramps up (larger lightness step)', params: { l_step: palette.params.l_step + 0.03 } },
      ];
    },
  },

  {
    id: 'value-hole',
    severity: 'medium',
    metric(palette) {
      return valueHoles(palette).reduce((a, h) => a + (h.size - h.limit), 0);
    },
    findings(palette) {
      return valueHoles(palette).slice(0, 2).map((h) => ({
        title: 'A hole in the value structure',
        detail: `nothing between L ${h.below.actual.L.toFixed(2)} (${h.below.role}) and`
          + ` L ${h.above.actual.L.toFixed(2)} (${h.above.role}) — a ${h.size.toFixed(2)} gap where`
          + ` this palette's steps average ${(h.limit / HOLE_RATIO).toFixed(2)}`,
        entries: [h.below.id, h.above.id],
        key: `${h.below.id}|${h.above.id}`,
        weight: h.size,
      }));
    },
    fixes(palette) {
      return [
        { label: 'Tighten the ramp steps', params: { l_step: palette.params.l_step - 0.03 } },
        { label: 'One more shade per foreground colour', params: { fg_ramp_length: palette.params.fg_ramp_length + 1 } },
        { label: 'Four more colours', params: { color_count: palette.params.color_count + 4 } },
      ];
    },
  },

  {
    id: 'hue-gap',
    severity: 'low',
    metric(palette) {
      const gap = worstHueGap(palette);
      return gap ? gap.size - HUE_GAP_DEG : 0;
    },
    findings(palette) {
      const gap = worstHueGap(palette);
      if (!gap) return [];
      const mid = (((gap.from + gap.size / 2) % 360) + 360) % 360;
      return [{
        title: `A ${Math.round(gap.size)}° hue gap`,
        detail: `no colour between ${Math.round(gap.from)}° and ${Math.round(gap.to)}° — this palette`
          + ` has no ${hueName(mid)} at all, and the rest of its hues are spaced far more evenly`,
        entries: [],
        key: `${Math.round(gap.from)}-${Math.round(gap.to)}`,
        weight: gap.size,
      }];
    },
    fixes(palette) {
      return [
        { label: 'One more hue family', params: { hue_count: (palette.plan.hueCount || 0) + 1 } },
        { label: 'Spread the hues wider', params: { hue_span: palette.params.hue_span + 40 } },
        { label: 'Space the hues evenly', params: { hue_scheme: 'even' } },
      ];
    },
  },

  {
    id: 'unused',
    severity: 'low',
    metric(palette, ctx) {
      const usage = ctx.usageFor(palette);
      if (!usage) return 0;
      return palette.entries.filter((e, i) => usage[i] === 0).length;
    },
    findings(palette, ctx) {
      const usage = ctx.usageFor(palette);
      if (!usage) return [];
      const idle = palette.entries.filter((e, i) => usage[i] === 0);
      if (!idle.length) return [];
      const names = idle.slice(0, 6).map((e) => e.role).join(', ');
      return [{
        title: `${idle.length} colour${idle.length === 1 ? '' : 's'} no gallery scene draws`,
        // Deliberately not called dead: the scenes reach colours through the semantic roles and
        // the ramps, so a slot the gallery never touches can still be the one an artist picks.
        // What it does say is that this palette has more slots than its own structure spends.
        detail: `${names}${idle.length > 6 ? `, +${idle.length - 6} more` : ''}`
          + ' — every scene in the gallery was drawn without them',
        entries: idle.map((e) => e.id),
        key: idle.map((e) => e.id).join('|'),
        weight: idle.length,
      }];
    },
    fixes(palette, ctx) {
      const usage = ctx.usageFor(palette);
      const idle = usage ? palette.entries.filter((e, i) => usage[i] === 0).length : 0;
      return [
        { label: `Spend ${idle} fewer colour${idle === 1 ? '' : 's'}`, params: { color_count: palette.params.color_count - idle } },
        { label: 'One more hue family to spend them on', params: { hue_count: (palette.plan.hueCount || 0) + 1 } },
      ];
    },
  },

  {
    id: 'cvd',
    severity: 'medium',
    metric(palette) {
      return cvdCollisions(palette).length;
    },
    findings(palette) {
      // Two, not three: measured over the presets a palette has a median of two of these and a
      // p75 of six, so this check would otherwise crowd every other finding off the card.
      return cvdCollisions(palette).slice(0, 2).map((c) => ({
        title: `Two colours collide under ${c.type}`,
        detail: `${c.a.role} and ${c.b.role} are ΔE ${c.deltaE.toFixed(1)} apart to normal vision`
          + ` and ΔE ${c.under.toFixed(1)} apart under ${c.type} — anything told apart by these two`
          + ' is not told apart at all',
        entries: [c.a.id, c.b.id],
        key: `${c.a.id}|${c.b.id}|${c.type}`,
        weight: CVD_COLLIDE_DE - c.under,
      }));
    },
    fixes(palette) {
      // A dichromat pair collapses on the red–green axis, so the only separation that survives
      // is lightness. Both candidates buy lightness; whether either buys enough is measured.
      return [
        { label: 'Separate the ramp steps further', params: { l_step: palette.params.l_step + 0.03 } },
        { label: 'Raise the minimum distance', params: { min_delta_e: palette.params.min_delta_e + 1.5 } },
      ];
    },
  },

  {
    id: 'contrast',
    severity: 'high',
    metric(palette) {
      const dark = palette.entries.find((e) => e.id === 'universal_dark');
      const light = palette.entries.find((e) => e.id === 'universal_light');
      const anchor = dark && light
        ? Math.max(0, palette.params.min_anchor_contrast - contrastRatio(dark.rgb8, light.rgb8))
        : 0;
      return anchor + unreadableBackgrounds(palette).length;
    },
    findings(palette) {
      const out = [];
      const dark = palette.entries.find((e) => e.id === 'universal_dark');
      const light = palette.entries.find((e) => e.id === 'universal_light');
      if (dark && light) {
        const got = contrastRatio(dark.rgb8, light.rgb8);
        if (got < palette.params.min_anchor_contrast) {
          out.push({
            title: 'The two anchors miss their contrast floor',
            detail: `${got.toFixed(2)}:1 against the ${palette.params.min_anchor_contrast}:1 asked for`
              + ' — dark-on-light text will not be legible',
            entries: [dark.id, light.id],
            key: 'anchors',
            weight: palette.params.min_anchor_contrast - got,
          });
        }
      }
      for (const r of unreadableBackgrounds(palette).slice(0, 2)) {
        out.push({
          // Not high, unlike the anchors above: the anchors missing their floor is the palette
          // failing something it was told to guarantee, whereas a background text cannot sit on
          // is a fact about a colour that may never carry text. Most misses here are within a
          // tenth of a ratio point of passing.
          severity: 'medium',
          title: 'No text colour works on this background',
          detail: `${r.entry.role} reaches only ${r.best.toFixed(2)}:1 against the better anchor,`
            + ` short of the ${TEXT_CONTRAST}:1 body text needs`,
          entries: [r.entry.id],
          key: `text:${r.entry.id}`,
          weight: TEXT_CONTRAST - r.best,
        });
      }
      return out;
    },
    fixes(palette) {
      return [
        { label: 'Push the anchors apart', params: { l_dark_anchor: palette.params.l_dark_anchor - 0.04, l_light_anchor: palette.params.l_light_anchor + 0.03 } },
        { label: 'Darken the backgrounds', params: { bg_lightness_offset: palette.params.bg_lightness_offset - 0.06 } },
      ];
    },
  },

  {
    id: 'diverged',
    severity: 'low',
    metric(palette) {
      let sum = 0;
      for (const e of palette.entries) {
        const d = entryDivergence(e);
        if (d) sum += d.chromaLost;
      }
      return sum;
    },
    findings(palette) {
      const lost = palette.entries
        .map((e) => ({ entry: e, div: entryDivergence(e) }))
        .filter((r) => r.div)
        .sort((x, y) => y.div.chromaLost - x.div.chromaLost);
      if (!lost.length) return [];
      const worst = lost[0];
      return [{
        title: `${lost.length} colour${lost.length === 1 ? ' is' : 's are'} less saturated than asked`,
        // The one finding here that is not a fault: sRGB cannot hold the colour, and the
        // sliders go on showing the request. Saying so is most of the value — it is the answer
        // to "why will this not get any more saturated".
        detail: `${worst.entry.role} ${worst.div.note}. sRGB has no more chroma at that hue and`
          + ' lightness, so the slider above it is already at the end of what it can reach',
        entries: lost.slice(0, 6).map((r) => r.entry.id),
        key: `diverged:${worst.entry.id}`,
        weight: worst.div.chromaLost,
      }];
    },
    fixes(palette) {
      return [
        // Letting each hue sit where it can actually hold chroma is the principled answer:
        // yellow and green clip at mid lightness and do not clip near their cusp.
        { label: 'Let each hue find its own lightness', params: { hue_lightness_follow: palette.params.hue_lightness_follow + 0.25 } },
        { label: 'Ask for the saturation sRGB can give', params: { chroma_cap: palette.params.chroma_cap - 0.04 } },
        { label: 'Lower the master saturation', params: { chroma_base: palette.params.chroma_base - 0.03 } },
      ];
    },
  },
];

/** Severity order, worst first — the order the report card lists findings in. */
export const SEVERITY_ORDER = ['high', 'medium', 'low'];

/** Clamp a patch to the schema and drop the fields it would not actually move. */
function cleanPatch(params, patch) {
  const out = {};
  for (const [name, value] of Object.entries(patch)) {
    const spec = PARAM_BY_NAME.get(name);
    if (!spec) continue;
    const v = coerceParam(spec, value);
    const now = params[name];
    const unmoved = typeof v === 'number' && typeof now === 'number'
      ? Math.abs(v - now) < 1e-9
      : v === now;
    if (unmoved) continue;
    out[name] = v;
  }
  return out;
}

/**
 * The first candidate patch that measurably improves this check, or null.
 *
 * Every candidate costs one palette generation (about 2 ms at K=32), and only checks that
 * actually found something are ever asked, so the whole card is a few dozen milliseconds
 * unless scene usage is being recomputed with it.
 */
function verifiedFix(check, palette, ctx) {
  const before = check.metric(palette, ctx);
  if (!(before > 0)) return null;
  for (const candidate of check.fixes(palette, ctx)) {
    const patch = cleanPatch(palette.params, candidate.params);
    if (!Object.keys(patch).length) continue; // already at the end of that knob's range
    let after;
    try {
      const trial = generatePalette({ ...palette.params, ...patch }, {
        locks: palette.locks, overrides: palette.overrides,
      });
      after = check.metric(trial, ctx);
    } catch { continue; }
    if (after <= before * FIX_GAIN) {
      return { label: candidate.label, params: patch, before, after };
    }
  }
  return null;
}

/**
 * Diagnose a palette.
 *
 * `usage` is the `sceneUsage` count array for this palette (optional — core cannot compute it,
 * since it may not import the scenes). `usageOf` lets the unused-colour check verify its own
 * fix by measuring a candidate palette; without it that check reports but offers no fix.
 * `verify: false` skips every candidate generation, which is what the tests use to time the
 * measurement on its own.
 */
export function diagnose(palette, { usage = null, usageOf = null, verify = true } = {}) {
  const cache = new Map();
  if (usage) cache.set(palette, usage);
  const ctx = {
    usageFor(p) {
      if (cache.has(p)) return cache.get(p);
      const u = usageOf ? usageOf(p) : null;
      cache.set(p, u);
      return u;
    },
  };

  const out = [];
  for (const check of CHECKS) {
    const found = check.findings(palette, ctx);
    if (!found.length) continue;
    const fix = verify ? verifiedFix(check, palette, ctx) : null;
    for (const f of found) {
      out.push({
        id: `${check.id}:${f.key}`,
        check: check.id,
        // A check sets the usual severity of its findings; a finding may say otherwise when it
        // knows something the check does not (see the contrast check for the case).
        severity: f.severity || check.severity,
        title: f.title,
        detail: f.detail,
        entries: f.entries,
        weight: f.weight,
        fix,
      });
    }
  }
  return out.sort((a, b) => (
    SEVERITY_ORDER.indexOf(a.severity) - SEVERITY_ORDER.indexOf(b.severity)
    || b.weight - a.weight
    || (a.id < b.id ? -1 : 1)
  ));
}

/** One line for the report card's header: how many findings, worst severity first. */
export function summarizeFindings(findings) {
  if (!findings.length) return 'Nothing to report — no duplicates, holes, collisions or clipping';
  const counts = SEVERITY_ORDER
    .map((s) => [s, findings.filter((f) => f.severity === s).length])
    .filter(([, n]) => n > 0)
    .map(([s, n]) => `${n} ${s}`);
  return `${findings.length} finding${findings.length === 1 ? '' : 's'} · ${counts.join(' · ')}`;
}
