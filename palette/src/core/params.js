// The parameter schema (PLAN §5). Single source of truth: the UI generates its
// sliders from this array, and the seed codec reads its field order from it.
//
// Field order is APPEND-ONLY. Adding a parameter at the end keeps old PAL1 seeds
// decodable (the decoder fills missing trailing fields with defaults); reordering
// or removing entries silently reinterprets every seed ever pasted.

/**
 * @typedef {Object} ParamSpec
 * @property {string} name
 * @property {string} group
 * @property {'float'|'int'|'enum'|'bool'} type
 * @property {number} [min]
 * @property {number} [max]
 * @property {number} [step]
 * @property {string[]} [options]
 * @property {*} default
 * @property {string} doc
 */

const f = (name, group, min, max, step, def, doc) => ({
  name, group, type: 'float', min, max, step, default: def, doc,
});
const i = (name, group, min, max, def, doc) => ({
  name, group, type: 'int', min, max, step: 1, default: def, doc,
});
const e = (name, group, options, def, doc) => ({
  name, group, type: 'enum', options, default: def, doc,
});
const b = (name, group, def, doc) => ({ name, group, type: 'bool', default: def, doc });

/** Ordered parameter schema; index in this array is the seed-payload field order. */
export const PARAMS = [
  // --- Structure ---------------------------------------------------------
  i('color_count', 'structure', 4, 64, 32,
    'Total colour budget. 4 = Game Boy, 16 = CGA/Arne, 32 = Endesga, 64 = AAP-64.'),
  i('hue_count', 'structure', 0, 8, 0,
    'Distinct colour identities. 0 derives it from the budget; too many at low K yields mud.'),
  e('hue_scheme', 'structure',
    ['even', 'analogous', 'complementary', 'split-comp', 'triadic', 'tetradic', 'custom'], 'analogous',
    'The single biggest driver of palette mood. Even reads generic, analogous cohesive, complementary punchy.'),
  f('root_hue', 'structure', 0, 360, 1, 35,
    'Rotates the whole palette. The main "what colour is this world" knob.'),
  f('hue_span', 'structure', 0, 360, 1, 140,
    'Width of the analogous arc. Narrow = strongly themed (all-swamp, all-desert).'),
  f('hue_jitter', 'structure', 0, 30, 0.5, 6,
    'Breaks mathematical regularity so the palette feels hand-picked rather than computed.'),
  f('perceptual_hue_spacing', 'structure', 0, 1, 0.01, 0.5,
    'Blends even hue-angle spacing toward perceptually-even. OKLCH hue is not uniform: green sprawls, yellow is narrow.'),
  i('fg_ramp_length', 'structure', 2, 5, 3,
    'Steps per foreground ramp. 3 is the pixel-art minimum; 5 is needed for metal and skin.'),
  i('bg_ramp_length', 'structure', 1, 3, 2,
    'Background ramps are shorter — depth needs less internal detail.'),
  i('neutral_count', 'structure', 0, 6, 3, 'Stone / metal / UI-border slots.'),
  i('accent_count', 'structure', 0, 4, 2, 'High-chroma UI and FX pops.'),
  e('tier_priority', 'structure',
    ['standard', 'background-first', 'neutrals-first', 'ramps-first'], 'standard',
    'Which allocation round claims budget first when the colour count is tight.'),

  // --- Lightness ---------------------------------------------------------
  f('l_dark_anchor', 'lightness', 0.02, 0.3, 0.005, 0.12,
    'The universal dark. Too high and outlines go mushy; too low and shadow detail disappears.'),
  f('l_light_anchor', 'lightness', 0.8, 1.0, 0.005, 0.95,
    'The universal light; the palette brightness ceiling.'),
  f('l_mid_base', 'lightness', 0.3, 0.8, 0.005, 0.56,
    'Where foreground midtones sit — the darkness/brightness master knob.'),
  f('l_step', 'lightness', 0.05, 0.4, 0.005, 0.15,
    'Lightness delta per ramp step. This is contrast: small = painterly, large = punchy at 1x.'),
  e('l_curve', 'lightness', ['ease-dark', 'linear', 'ease-light', 's-curve'], 'linear',
    'Where ramp steps cluster. Clustering in shadow gives rich darks; S-curve maximises midtone separation.'),
  f('l_range_compress', 'lightness', 0, 1, 0.01, 0,
    'Squeezes ramps toward mid-grey. High = foggy, washed, dreamlike.'),
  f('l_variance_per_hue', 'lightness', 0, 0.15, 0.005, 0.04,
    'Lets hues sit at different lightnesses — real palettes do not put yellow and blue at the same L.'),

  // --- Chroma ------------------------------------------------------------
  f('chroma_base', 'chroma', 0, 0.37, 0.005, 0.145,
    'Master saturation. 0 = greyscale, 0.30+ = neon.'),
  f('chroma_peak_l', 'chroma', 0.3, 0.9, 0.005, 0.62,
    'Lightness at which chroma peaks. Real pigments saturate in the upper-mid range.'),
  f('chroma_curve_width', 'chroma', 0.1, 1.0, 0.01, 0.45,
    'How sharply chroma falls off away from the peak.'),
  f('chroma_falloff_light', 'chroma', -0.1, 0.2, 0.005, 0.02,
    'Highlight washout. Positive = sun-bleached; negative = hot, neon, emissive.'),
  f('chroma_falloff_dark', 'chroma', -0.1, 0.2, 0.005, -0.015,
    'Negative boosts shadow chroma — what makes shadows rich rather than muddy.'),
  f('chroma_variance_per_hue', 'chroma', 0, 0.15, 0.005, 0.03,
    'Some hue families more saturated than others; avoids the flat "everything at C=0.18" look.'),
  f('earthiness', 'chroma', 0, 1, 0.01, 0.15,
    'Chroma reduction plus a hue pull toward ochre. Distinct from desaturating, which yields dead grey.'),
  f('chroma_cap', 'chroma', 0.05, 0.37, 0.005, 0.3,
    'Chroma ceiling before gamut mapping; keeps colours reachable in sRGB.'),

  // --- Hue shifting ------------------------------------------------------
  f('highlight_hue_target', 'shift', 0, 360, 1, 90,
    'Where lights drift. 90 = sunlight, 200 = moonlight, 330 = magic/alien.'),
  f('highlight_shift_strength', 'shift', 0, 1, 0.01, 0.25,
    'The signature parameter of hue-shifted pixel art.'),
  f('shadow_hue_target', 'shift', 0, 360, 1, 280,
    'Where darks drift. 280 = classic cool indigo, 20 = warm firelit interiors.'),
  f('shadow_shift_strength', 'shift', 0, 1, 0.01, 0.35, 'How hard shadows drift.'),
  e('shift_model', 'shift', ['global-attractor', 'relative-rotation', 'per-family'], 'per-family',
    'Global attractor is most cohesive but collapses hue identity on short ramps; relative rotation preserves it.'),
  e('shift_direction', 'shift', ['shortest', 'always-cw', 'always-ccw'], 'shortest',
    'Removes the antipode discontinuity, where hues either side of the target shift opposite ways.'),
  f('global_temperature', 'shift', -1, 1, 0.01, 0, 'Warm/cool bias on everything.'),
  f('temperature_split', 'shift', 0, 1, 0.01, 0.75,
    'Warm-light/cool-shadow separation. Below 0.25 it inverts — cool lights, warm shadows — the toxic/alien look.'),

  // --- Background --------------------------------------------------------
  f('bg_chroma_mult', 'background', 0.1, 1.0, 0.01, 0.4,
    'Background desaturation — the primary tool for foreground readability.'),
  f('bg_lightness_offset', 'background', -0.3, 0.3, 0.005, -0.08,
    'Pushes backgrounds darker (dungeon) or lighter (fog, snow).'),
  f('bg_hue_shift', 'background', 0, 1, 0.01, 0.3, 'Pull toward the atmospheric hue.'),
  f('atmosphere_hue', 'background', 0, 360, 1, 220,
    'The fog / aerial-perspective colour distant layers converge toward.'),
  f('atmosphere_strength', 'background', 0, 1, 0.01, 0.35, 'Aerial perspective intensity.'),
  f('fg_bg_separation_min', 'background', 0, 1, 0.01, 0.15,
    'Enforced minimum distance between any foreground and any background colour, as a fraction of 30 deltaE.'),

  // --- Neutrals ----------------------------------------------------------
  f('neutral_temperature', 'neutrals', 0, 360, 1, 230, 'Cool slate to warm taupe. Governs stone, metal, UI chrome.'),
  f('neutral_chroma', 'neutrals', 0, 0.06, 0.002, 0.018,
    '0 is pure grey and reads digital; slightly tinted neutrals are what make a palette feel painted.'),
  b('neutral_split', 'neutrals', false,
    'Emit both cool and warm neutral families. Essential above ~24 colours — stone and skin want different neutrals.'),
  f('neutral_l_spread', 'neutrals', 0.1, 0.5, 0.01, 0.3, 'Contrast within the neutral ramp.'),

  // --- Accents -----------------------------------------------------------
  f('accent_chroma_boost', 'accents', 0, 0.15, 0.005, 0.06,
    'How much accents out-saturate everything else; drives UI and FX pop.'),
  e('accent_hue_mode', 'accents', ['complementary', 'spectral-gap', 'fixed-offset'], 'spectral-gap',
    'Complementary accents read as alerts; spectral-gap accents fill the hue holes the primaries left.'),
  f('accent_l', 'accents', 0.4, 0.9, 0.005, 0.68,
    'Accent lightness. Accents need to sit clear of the foreground midtones to read as a separate layer.'),

  // --- Hardware / output -------------------------------------------------
  i('bits_r', 'hardware', 1, 8, 8, 'Red channel bit depth. 5/5/5 is SNES-like, 3/3/3 Genesis-like.'),
  i('bits_g', 'hardware', 1, 8, 8, 'Green channel bit depth.'),
  i('bits_b', 'hardware', 1, 8, 8, 'Blue channel bit depth.'),
  e('quantize_mode', 'hardware', ['round', 'floor', 'error-weighted'], 'error-weighted',
    'Error-weighted picks the legal value with the lowest deltaE from the ideal — clearly better at low bit depth.'),
  e('gamut_map_mode', 'hardware', ['chroma-reduce', 'clip', 'reduce-l-adjust'], 'chroma-reduce',
    'Chroma-reduce is the correct default; clip exists only to demonstrate the artifact.'),

  // --- Quality constraints -----------------------------------------------
  f('min_delta_e', 'quality', 0, 15, 0.1, 4,
    'Minimum perceptual distance between any two colours; prevents wasted near-duplicate slots.'),
  f('min_anchor_contrast', 'quality', 1, 21, 0.1, 10,
    'WCAG contrast floor between the two universal anchors — guarantees text legibility.'),
  f('dither_evenness', 'quality', 0, 1, 0.01, 0.3,
    'Biases ramp steps toward uniform delta-L so adjacent pairs checkerboard into convincing intermediates.'),
  b('force_unique_hex', 'quality', true, 'Hard guarantee of K distinct hex values.'),

  // --- Meta --------------------------------------------------------------
  i('seed', 'meta', 0, 65535, 12345, 'Feeds the xorshift128 PRNG used for jitter and randomisation.'),

  // --- Reference recolouring (PLAN §19.1) ---------------------------------
  // Appended after `seed` because field order is the seed payload's order and appending is
  // the only safe edit. These change no colour in the palette — they decide how reference
  // images are re-rendered into it — but they are seed-encoded like everything else, so a
  // pasted seed reproduces the whole view and not just the swatches.
  e('recolor_mode', 'recolor', ['auto', 'indexed', 'quantize'], 'auto',
    'Indexed keeps one target colour per source colour (right for pixel art); quantize decides per pixel (right for photographs). Auto picks on the source colour count.'),
  i('recolor_indexed_max', 'recolor', 2, 256, 256,
    'Colour count at or below which auto chooses the indexed path.'),
  e('remap_match', 'recolor', ['delta-e', 'lightness-rank', 'optimal'], 'delta-e',
    'How the source palette is matched: nearest, by lightness rank, or the assignment minimising total distance without reusing a target.'),
  b('remap_preserve_order', 'recolor', false,
    'Force the mapping to be monotonic in lightness. What lets a palette with completely different hues still read correctly, because value structure is what the eye reads first.'),
  e('remap_overflow', 'recolor', ['share', 'merge'], 'share',
    'When the source has more colours than the target: share lets colours reuse a target, merge clusters the source down first.'),
  e('quant_dither', 'recolor', ['none', 'floyd-steinberg', 'bayer4', 'bayer8'], 'floyd-steinberg',
    'Error diffusion or ordered dithering when matching per pixel. Without it a smooth gradient bands.'),
  f('quant_dither_strength', 'recolor', 0, 1, 0.05, 1,
    'How hard the dither works. 0 is plain nearest-colour matching.'),
  f('quant_lightness_weight', 'recolor', 0.25, 8, 0.05, 1,
    'Weight on lightness versus chroma when matching. Above 1 protects the value structure and lets hue drift.'),
  i('quant_downscale', 'recolor', 0, 256, 0,
    'Shrink a source to this width before matching, to get a pixel-art result from a photograph. 0 leaves it alone.'),
  i('gif_frame', 'recolor', 0, 63, 0,
    'Which frame the still exports use. The animation itself is always recoloured whole, every frame.'),
];

/** Parameter specs looked up by name. */
export const PARAM_BY_NAME = new Map(PARAMS.map((p) => [p.name, p]));

/** Distinct group names in schema order, for building the UI panels. */
export const PARAM_GROUPS = [...new Set(PARAMS.map((p) => p.group))];

/** A fresh parameter object with every field at its default. */
export function defaultParams() {
  const out = {};
  for (const p of PARAMS) out[p.name] = p.default;
  return out;
}

/** Clamp/coerce a single value to its spec's type and range. */
export function coerceParam(spec, value) {
  if (spec.type === 'bool') return Boolean(value);
  if (spec.type === 'enum') {
    return spec.options.includes(value) ? value : spec.default;
  }
  let v = Number(value);
  if (!Number.isFinite(v)) v = spec.default;
  if (spec.type === 'int') v = Math.round(v);
  return Math.min(spec.max, Math.max(spec.min, v));
}

/** Fill missing fields with defaults and clamp everything into range. */
export function normalizeParams(partial = {}) {
  const out = {};
  for (const p of PARAMS) {
    out[p.name] = Object.prototype.hasOwnProperty.call(partial, p.name)
      ? coerceParam(p, partial[p.name])
      : p.default;
  }
  return out;
}

/** Map a parameter value onto the 0..65535 integer used by the seed payload. */
export function paramToU16(spec, value) {
  if (spec.type === 'bool') return value ? 1 : 0;
  if (spec.type === 'enum') return Math.max(0, spec.options.indexOf(value));
  const t = (coerceParam(spec, value) - spec.min) / (spec.max - spec.min);
  return Math.round(Math.min(1, Math.max(0, t)) * 65535);
}

/**
 * Snap every value onto the seed's u16 grid.
 * The generator runs on snapped parameters so that a palette and the seed string
 * describing it are always in exact correspondence — otherwise pasting a seed back
 * reproduces a palette a fraction of a step away from the original.
 */
export function snapParams(params) {
  const norm = normalizeParams(params);
  const out = {};
  for (const p of PARAMS) out[p.name] = u16ToParam(p, paramToU16(p, norm[p.name]));
  return out;
}

/** Inverse of `paramToU16`. */
export function u16ToParam(spec, u) {
  if (spec.type === 'bool') return u !== 0;
  if (spec.type === 'enum') return spec.options[Math.min(spec.options.length - 1, u)] ?? spec.default;
  const v = spec.min + (u / 65535) * (spec.max - spec.min);
  return spec.type === 'int' ? Math.round(v) : v;
}
