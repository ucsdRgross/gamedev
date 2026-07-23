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

/**
 * Ordered parameter schema; index in this array is the seed-payload field order.
 *
 * Every `doc` string is written as **what it does · when to reach for it · which way to push
 * it for a given look** — it is the hover tooltip, so it has to earn the hover. The README's
 * "Parameter reference" carries the longer worked examples.
 */
export const PARAMS = [
  // --- Structure ---------------------------------------------------------
  i('color_count', 'structure', 4, 64, 32,
    'How many colours the palette has in total. More = richer shading and variety; fewer = a tighter retro feel (4 Game Boy, 16 CGA, 32 Endesga, 64 AAP-64). If colours look muddy or redundant you have too many for the hue count — lower this, or raise hue_count.'),
  i('hue_count', 'structure', 0, 8, 0,
    'How many distinct colour identities (hue families) the budget is split across; 0 derives a sensible number from color_count. Raise for a varied, rainbow-ish set; drop to 2–3 for a cohesive, strongly-themed palette. Too many at a low color_count starves each ramp and yields mud.'),
  e('hue_scheme', 'structure',
    ['even', 'analogous', 'complementary', 'split-comp', 'triadic', 'tetradic', 'custom'], 'analogous',
    'The relationship between hue families — the single biggest mood driver, so set it first. analogous = cohesive/harmonious; complementary = punchy two-sided contrast; triadic/tetradic = balanced variety; even = generic spread; split-comp = softer complement.'),
  f('root_hue', 'structure', 0, 360, 1, 35,
    'Rotates every hue together — the "what colour is this world" knob. 30–60 warm desert/autumn, 120 verdant, 200–240 cold night/underwater, 280–330 magic/alien. Reach for this to re-theme a palette whose structure you already like.'),
  f('hue_span', 'structure', 0, 360, 1, 140,
    'How wide an arc the hues cover (bites mainly on analogous/split schemes). Narrow (40–80) = strongly themed, all-swamp/all-desert; wide (180+) = varied but still related. Widen if the palette feels monotonous, narrow to force a single mood.'),
  f('hue_jitter', 'structure', 0, 30, 0.5, 6,
    'Random wobble on each hue angle so the set looks hand-picked, not mathematically spaced. 0 = perfectly regular (can read sterile); push past 15 for an organic, curated feel; change seed to reroll the specific wobble. Set to 0 (with the two per-hue variances) to freeze the palette so it stops shifting when you touch other knobs.'),
  f('perceptual_hue_spacing', 'structure', 0, 1, 0.01, 0.5,
    'Blends even angular hue spacing toward perceptually-even spacing. OKLCH hue is uneven — green sprawls, yellow is a narrow band — so at 0 hues clump; raise toward 1 for hues that look evenly separated to the eye. Leave near 0.5 unless hues feel bunched.'),
  i('fg_ramp_length', 'structure', 2, 5, 3,
    'Shades per foreground colour (dark→light within one hue). 3 is the pixel-art minimum; 4–5 gives smooth metal, skin and rounded forms. Raise for painterly shading, lower to spend the budget on more hues instead.'),
  i('bg_ramp_length', 'structure', 1, 3, 2,
    'Shades per background colour. Backgrounds carry less internal detail than foregrounds, so 1–2 is usual; raise to 3 only when backdrops show visible form or depth, lower to free budget for foreground ramps.'),
  i('neutral_count', 'structure', 0, 6, 3,
    'How many grey/stone/metal/UI-border slots. Raise for architecture, machinery and interface-heavy work; lower or 0 for organic scenes with no chrome. These desaturated colours are the backbone most scenes lean on.'),
  i('accent_count', 'structure', 0, 4, 2,
    'How many high-chroma "pop" colours for UI highlights, FX and pickups. 1–2 is plenty; add more only for lots of alerts/effects; 0 for a strictly naturalistic palette with nothing loud.'),
  e('tier_priority', 'structure',
    ['standard', 'background-first', 'neutrals-first', 'ramps-first'], 'standard',
    'When the budget is tight, which group is funded first. standard is balanced; background-first for atmospheric scenes; neutrals-first for UI/architecture; ramps-first to protect foreground shading. Only worth changing when a low color_count is starving the part you care about.'),

  // --- Lightness ---------------------------------------------------------
  f('l_dark_anchor', 'lightness', 0.02, 0.3, 0.005, 0.12,
    'Lightness of the universal darkest colour — outlines and deepest shadow. Raise for soft, faded, low-contrast darks; lower for inky high-contrast outlines. Too high makes outlines mushy; too low crushes shadow detail to black.'),
  f('l_light_anchor', 'lightness', 0.8, 1.0, 0.005, 0.95,
    'Lightness of the universal lightest colour — the brightness ceiling. Lower it for a dim, nocturnal, muted feel; keep it high (0.95+) for bright highlights and paper-white UI. Sets how far the value range can stretch at the top.'),
  f('l_mid_base', 'lightness', 0.3, 0.8, 0.005, 0.56,
    'Where foreground midtones sit — the overall light/dark master. Lower for a dark, moody, dungeon palette; raise for bright, airy daytime. Shifts the whole foreground up or down without moving the anchors.'),
  f('l_step', 'lightness', 0.05, 0.4, 0.005, 0.15,
    'Lightness jump between adjacent ramp steps — this IS your contrast. Small (0.08–0.12) = soft, painterly, blendable shading; large (0.2+) = punchy, readable-at-1× steps. Raise if shading looks flat/muddy, lower if it looks harsh or posterised.'),
  e('l_curve', 'lightness', ['ease-dark', 'linear', 'ease-light', 's-curve'], 'linear',
    'Where the ramp bunches its steps. ease-dark packs them into the shadows (rich darks, few highlights); ease-light the opposite; s-curve spreads the midtones apart for maximum form-reading; linear is even. ease-dark for moody, s-curve for bold readable sprites.'),
  f('l_range_compress', 'lightness', 0, 1, 0.01, 0,
    'Squeezes every ramp toward mid-grey. 0 = full contrast; raise toward 1 for foggy, washed-out, hazy, dreamlike, faded-photo looks. The go-to for atmosphere and distance — overdo it and everything turns to flat grey.'),
  f('l_variance_per_hue', 'lightness', 0, 0.15, 0.005, 0.04,
    'Lets different hues sit at different lightnesses (real palettes never put yellow and blue at the same L). Raise for natural, hand-tuned variety; 0 for a rigid systematic look. Part of the palette\'s randomness — zero it (with hue_jitter and chroma_variance_per_hue) to freeze the palette.'),

  // --- Chroma ------------------------------------------------------------
  f('chroma_base', 'chroma', 0, 0.37, 0.005, 0.145,
    'Master saturation. 0 = greyscale, ~0.1 muted/earthy, ~0.18 balanced, 0.3+ = neon/vivid. The fastest fix for "too dull" (raise) or "too candy/garish" (lower).'),
  f('chroma_peak_l', 'chroma', 0.3, 0.9, 0.005, 0.62,
    'The lightness at which colours are most saturated; real pigments peak in the upper-mid (~0.6). Lower it to make shadows the most vivid (rich, moody), raise it to make highlights glow (emissive). Move it toward whichever tones you want most colourful.'),
  f('chroma_curve_width', 'chroma', 0.1, 1.0, 0.01, 0.45,
    'How quickly saturation falls off away from chroma_peak_l. Narrow = only midtones are colourful while lights and darks go grey (natural); wide = colour holds across the whole ramp (poster/vivid). Narrow for realism, widen for bold flat colour.'),
  f('chroma_falloff_light', 'chroma', -0.1, 0.2, 0.005, 0.02,
    'Extra saturation change in the highlights. Positive = sun-bleached, washed, pastel tops; negative = hot, neon, emissive highlights that keep their colour. Push negative for glow/lava/magic, positive for daylight and haze.'),
  f('chroma_falloff_dark', 'chroma', -0.1, 0.2, 0.005, -0.015,
    'Extra saturation change in the shadows. Negative boosts shadow chroma — the trick that makes darks rich and coloured instead of muddy grey; positive greys them out. Keep it slightly negative for painterly shadows.'),
  f('chroma_variance_per_hue', 'chroma', 0, 0.15, 0.005, 0.03,
    'Lets some hue families be more saturated than others, avoiding the flat "everything at one saturation" look. Raise for natural variety (a vivid red beside a muted green); 0 for uniform saturation. Part of the palette\'s randomness.'),
  f('earthiness', 'chroma', 0, 1, 0.01, 0.15,
    'Pulls colours toward ochre/brown while cutting chroma — dirt, rust, wood, natural muting. Unlike plain desaturation (which yields dead grey) it keeps warmth. Raise for organic/historical/muted palettes, 0 for clean synthetic colour.'),
  f('chroma_cap', 'chroma', 0.05, 0.37, 0.005, 0.3,
    'Hard saturation ceiling applied before gamut mapping, so colours stay reachable in sRGB. Lower it to guarantee a muted, safe, print-friendly set; raise toward 0.37 to allow the most vivid colours the display can show. Mostly a safety limit — lower it if bright colours look clipped.'),

  // --- Hue shifting ------------------------------------------------------
  f('highlight_hue_target', 'shift', 0, 360, 1, 90,
    'The hue highlights drift toward as they brighten (hue-shifted shading). 90 warm sunlight, 200 cool moonlight, 40 firelight, 330 magic/alien. Set it to the colour of your light source.'),
  f('highlight_shift_strength', 'shift', 0, 1, 0.01, 0.25,
    'How far highlights rotate toward highlight_hue_target — the signature move of hue-shifted pixel art. 0 = flat tint-only shading; raise toward 0.4 for that lively "colours warm as they lighten" look. The single knob that most makes shading feel painted.'),
  f('shadow_hue_target', 'shift', 0, 360, 1, 280,
    'The hue shadows drift toward as they darken. 280 classic cool indigo, 20 warm firelit interior, 200 icy. Set it roughly complementary to highlight_hue_target for the strongest light/shadow colour separation.'),
  f('shadow_shift_strength', 'shift', 0, 1, 0.01, 0.35,
    'How hard shadows rotate toward shadow_hue_target. Raise for dramatic warm-light/cool-shadow depth; 0 for shadows that are just darker versions of the base. Pair with highlight_shift_strength for full hue-shifted shading.'),
  e('shift_model', 'shift', ['global-attractor', 'relative-rotation', 'per-family'], 'per-family',
    'How the hue shift is applied. per-family preserves each colour\'s identity (safe default); global-attractor pulls everything toward one temperature (most cohesive/filmic, but collapses hue identity on short ramps); relative-rotation keeps identity while rotating. Switch to global-attractor for a unified look, back to per-family if hues lose their identity.'),
  e('shift_direction', 'shift', ['shortest', 'always-cw', 'always-ccw'], 'shortest',
    'Which way hues rotate toward the target. shortest is natural but flips direction either side of the target (a visible seam); always-cw/ccw force one direction to remove that break. Only change it if you see a hue discontinuity where two ramps meet.'),
  f('global_temperature', 'shift', -1, 1, 0.01, 0,
    'A warm/cool bias over the entire palette. Negative = cooler/bluer (winter, night, tech); positive = warmer/oranger (sunset, cozy, autumn). A quick overall mood tint on top of everything else.'),
  f('temperature_split', 'shift', 0, 1, 0.01, 0.75,
    'How much lights go warm while shadows go cool. High (0.75) = strong warm-light/cool-shadow realism; below 0.25 it inverts to cool-light/warm-shadow — the toxic/alien/sickly look. Raise for natural lighting, invert for eerie.'),

  // --- Background --------------------------------------------------------
  f('bg_chroma_mult', 'background', 0.1, 1.0, 0.01, 0.4,
    'How much backgrounds are desaturated versus foregrounds — the main tool for making sprites pop off the scene. Low (0.3) = grey recessive backdrops that push foreground forward; near 1 = backgrounds as vivid as foreground (flatter). Lower it if foregrounds do not read against the scene.'),
  f('bg_lightness_offset', 'background', -0.3, 0.3, 0.005, -0.08,
    'Shifts backgrounds lighter or darker than the foreground. Negative = dark backdrops (dungeon, night, cave); positive = light backdrops (fog, snow, sky). Use it to separate background depth from the foreground midtones.'),
  f('bg_hue_shift', 'background', 0, 1, 0.01, 0.3,
    'How strongly backgrounds pull toward atmosphere_hue instead of their own hue — the aerial-perspective knob for hue. Raise for a unified atmospheric wash (everything tends toward the fog colour with distance); 0 keeps backgrounds true to their base hue.'),
  f('atmosphere_hue', 'background', 0, 360, 1, 220,
    'The colour distant/background layers converge toward — fog, haze, aerial perspective. 220 cool misty blue, 30 dusty warm, 200 underwater. Set it to the "air colour" of the scene.'),
  f('atmosphere_strength', 'background', 0, 1, 0.01, 0.35,
    'Overall intensity of aerial perspective — how far distance washes colours toward atmosphere_hue and mutes them. Raise for deep, layered, hazy depth; 0 for crisp flat art with no atmosphere. Great for parallax backdrops.'),
  f('fg_bg_separation_min', 'background', 0, 1, 0.01, 0.15,
    'Enforced minimum perceptual distance between ANY foreground and ANY background colour, so sprites never blend into the scene. Raise if characters get lost against backdrops; lower to allow closer, more unified fg/bg colours. A readability guarantee, not a look.'),

  // --- Neutrals ----------------------------------------------------------
  f('neutral_temperature', 'neutrals', 0, 360, 1, 230,
    'The hue tint of the greys — stone, metal, UI chrome. ~230 cool slate/steel, ~60 warm taupe/sand. Cool neutrals read as stone/tech, warm as wood/parchment. Match it to your world\'s materials.'),
  f('neutral_chroma', 'neutrals', 0, 0.06, 0.002, 0.018,
    'How tinted the neutrals are. 0 = pure digital grey (can look sterile/flat); a little (~0.02) gives painted-looking, believable greys. Raise for warm/atmospheric neutrals, keep at 0 for stark UI or tech.'),
  b('neutral_split', 'neutrals', false,
    'Emit both a cool AND a warm neutral family instead of one. Turn on above ~24 colours, where stone and skin want different greys; off to save budget. Essential for scenes mixing architecture with characters.'),
  f('neutral_l_spread', 'neutrals', 0.1, 0.5, 0.01, 0.3,
    'Contrast within the neutral ramp — how far its darkest and lightest greys are apart. Wide = bold stone/metal shading; narrow = flat, subtle, uniform greys. Widen for dramatic materials, narrow for quiet UI.'),

  // --- Accents -----------------------------------------------------------
  f('accent_chroma_boost', 'accents', 0, 0.15, 0.005, 0.06,
    'How much more saturated accents are than everything else — what makes them pop as UI highlights and FX. Raise for loud, attention-grabbing accents; lower so they sit closer to the main palette. Drives alert and effect legibility.'),
  e('accent_hue_mode', 'accents', ['complementary', 'spectral-gap', 'fixed-offset'], 'spectral-gap',
    'Where accent hues are placed. complementary = opposite the primaries (reads as alert/danger, maximum contrast); spectral-gap = fills the hue holes the primaries left (harmonious variety); fixed-offset = a set rotation. complementary for UI alerts, spectral-gap for a fuller natural spread.'),
  f('accent_l', 'accents', 0.4, 0.9, 0.005, 0.68,
    'Lightness of the accent colours. Keep them clear of l_mid_base so they read as a separate layer, not just another midtone. Raise for bright glowing accents, lower for deep jewel-tone accents.'),

  // --- Hardware / output -------------------------------------------------
  i('bits_r', 'hardware', 1, 8, 8,
    'Red-channel bit depth — emulates real hardware colour precision. 8 = modern/unlimited; 5 with 5/5/5 = SNES; 3 with 3/3/3 = Genesis; lower = harsher retro banding. Drop all three together for an authentic console-limited palette (the generator quantises legally, never just clamps).'),
  i('bits_g', 'hardware', 1, 8, 8,
    'Green-channel bit depth. Set it with bits_r and bits_b — 5/5/5 SNES, 3/3/3 Genesis, 2/2/2 harsher still. Lower for authentic hardware banding, 8 for unlimited modern colour.'),
  i('bits_b', 'hardware', 1, 8, 8,
    'Blue-channel bit depth. Blue is often given one fewer bit on real hardware (e.g. 5/6/5). Lower it with the others for a period-accurate console feel, 8 for full precision.'),
  e('quantize_mode', 'hardware', ['round', 'floor', 'error-weighted'], 'error-weighted',
    'How ideal colours snap onto the legal hardware grid. error-weighted picks the legal colour with the lowest perceptual error — best, and clearly so at low bit depth; round/floor are simpler and more predictable. Leave it on error-weighted unless emulating a specific hardware rounding rule.'),
  e('gamut_map_mode', 'hardware', ['chroma-reduce', 'clip', 'reduce-l-adjust'], 'chroma-reduce',
    'How colours outside sRGB are brought in range. chroma-reduce (correct default) lowers saturation while keeping hue and lightness; clip distorts hue and exists only to demonstrate the artifact; reduce-l-adjust trades some lightness. Keep chroma-reduce unless you specifically want the clipping look.'),

  // --- Quality constraints -----------------------------------------------
  f('min_delta_e', 'quality', 0, 15, 0.1, 4,
    'Minimum perceptual gap forced between any two colours, so no two slots are near-duplicates. Raise to guarantee every colour is visibly distinct (no wasted slots); lower to allow subtle near-neighbours for smoother gradients. Best-effort — misses are reported in warnings, not forced.'),
  f('min_anchor_contrast', 'quality', 1, 21, 0.1, 10,
    'WCAG contrast floor between the two universal anchors, so dark-on-light text stays legible. Raise for accessible UI and text; lower only if you do not use the anchors for text. A legibility guarantee, not a look.'),
  f('dither_evenness', 'quality', 0, 1, 0.01, 0.3,
    'Biases ramp steps toward equal lightness gaps so adjacent colours checkerboard into convincing in-between tones. Raise if you rely on dithering for extra shades (the steps blend cleanly); lower for ramps tuned purely by eye. Helps gradient- and dither-heavy work.'),
  b('force_unique_hex', 'quality', true,
    'Guarantees every slot is a distinct hex value (no accidental duplicates after quantisation). Leave on normally; turn off only if you deliberately want repeated colours. Best-effort at extreme low bit depths — misses go to warnings.'),

  // --- Meta --------------------------------------------------------------
  i('seed', 'meta', 0, 65535, 12345,
    'The master seed for every random choice (hue_jitter and the two per-hue variances). Same seed = the exact same palette every time; change it to reroll the random variation while keeping every other setting. This is the ONE knob behind Randomize — it does not add randomness, it selects which variation you get.'),

  // --- Reference recolouring (PLAN §19.1) ---------------------------------
  // Appended after `seed` because field order is the seed payload's order and appending is
  // the only safe edit. These change no colour in the palette — they decide how reference
  // images are re-rendered into it — but they are seed-encoded like everything else, so a
  // pasted seed reproduces the whole view and not just the swatches.
  e('recolor_mode', 'recolor', ['auto', 'indexed', 'quantize'], 'auto',
    'How reference images are recoloured into the palette. indexed keeps one target colour per source colour (correct for pixel art — preserves outlines and ramps); quantize decides every pixel on its own (correct for photos — dithers gradients); auto chooses by the source\'s colour count. Force indexed if pixel art breaks up, quantize if a photo posterises.'),
  i('recolor_indexed_max', 'recolor', 2, 256, 256,
    'The colour-count threshold auto uses to choose indexed vs quantize. Raise it to treat richer images as pixel art (indexed); lower it to send more images down the photo path. Only matters when recolor_mode is auto.'),
  e('remap_match', 'recolor', ['delta-e', 'lightness-rank', 'optimal'], 'delta-e',
    'How source colours are matched to target colours in indexed mode. delta-e = nearest colour (accurate, but jumps around when the palette changes); lightness-rank = match by brightness order (stable, keeps value structure even with alien hues); optimal = best overall assignment, no target reused. Use lightness-rank for consistent recolours that hold still across palette tweaks.'),
  b('remap_preserve_order', 'recolor', false,
    'Forces the colour mapping to keep lightness order (dark source → dark target). Turn it on so a wildly different target palette still reads correctly — value structure is what the eye reads first. The most useful knob when recolouring into an unrelated palette.'),
  e('remap_overflow', 'recolor', ['share', 'merge'], 'share',
    'What happens when the source has more colours than the target. share lets several source colours reuse one target (keeps detail, can flatten); merge clusters the source down first (cleaner, fewer collisions). Try merge if the shared mapping looks muddy.'),
  e('quant_dither', 'recolor', ['none', 'floyd-steinberg', 'bayer4', 'bayer8'], 'floyd-steinberg',
    'Dithering in the per-pixel/photo path. none bands on gradients; floyd-steinberg = smooth organic dithering (best for stills); bayer4/bayer8 = ordered cross-hatch that stays stable frame to frame (best for animations, which "boil" under floyd-steinberg). Pick bayer for GIFs, floyd-steinberg for single images.'),
  f('quant_dither_strength', 'recolor', 0, 1, 0.05, 1,
    'How strong the dithering is. 0 = plain nearest colour (hard bands); 1 = full dithering (smoothest gradients). Lower it if the dither texture is too noisy, raise it if you still see banding.'),
  f('quant_lightness_weight', 'recolor', 0.25, 8, 0.05, 1,
    'In the photo path, how much matching favours getting lightness right over hue. Above 1 protects value/form and lets hue drift (good when the target lacks the source\'s hues); below 1 favours hue. Raise it when recoloured photos lose their shading or depth.'),
  i('quant_downscale', 'recolor', 0, 256, 0,
    'Shrinks the source to this pixel width before recolouring, turning a photo into chunky pixel art. 0 keeps the original resolution. Set ~64–128 for a genuine downscaled pixel-art result instead of a full-res recolour.'),
  i('gif_frame', 'recolor', 0, 63, 0,
    'Which frame a STILL export pulls from a multi-frame source. The animation itself is always recoloured in full — this only picks the frame for the single-image PNG export.'),
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
