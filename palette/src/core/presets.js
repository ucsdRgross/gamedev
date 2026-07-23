// Parameter-set presets (PLAN §11).
//
// A preset is a full parameter set, not a canned list of colours, so every slider
// stays live and meaningful after one is loaded. Emulation presets pair a look with
// the matching per-channel bit depths; mood presets are pure art direction.

import { normalizeParams } from './params.js';

/** All presets, in menu order. */
export const PRESETS = [
  // --- Emulation-flavoured ------------------------------------------------
  {
    id: 'nes',
    name: 'NES-ish',
    group: 'emulation',
    doc: 'Blocky primaries and hard value steps. The 2C02 is not an RGB device; 3/3/3 is the closest expressible approximation.',
    params: {
      color_count: 16, hue_count: 4, hue_scheme: 'even', root_hue: 25, hue_span: 300,
      hue_jitter: 0, l_mid_base: 0.55, l_step: 0.22, l_curve: 'linear',
      chroma_base: 0.19, chroma_cap: 0.32, earthiness: 0, chroma_falloff_light: 0.01,
      highlight_shift_strength: 0.12, shadow_shift_strength: 0.15,
      bits_r: 3, bits_g: 3, bits_b: 3, quantize_mode: 'error-weighted',
      neutral_count: 2, accent_count: 0, min_delta_e: 5, seed: 1101,
    },
  },
  {
    id: 'gameboy',
    name: 'Game Boy DMG',
    group: 'emulation',
    doc: 'Four shades of dot-matrix green. One hue, no background layer. The DMG is an LCD with four fixed shades rather than an RGB device, so the bit depths stay open.',
    params: {
      color_count: 4, hue_count: 1, hue_scheme: 'analogous', root_hue: 128, hue_span: 0,
      hue_jitter: 0, perceptual_hue_spacing: 0,
      l_dark_anchor: 0.3, l_light_anchor: 0.8, l_mid_base: 0.7, l_step: 0.24,
      chroma_base: 0.13, chroma_cap: 0.17, chroma_peak_l: 0.7, chroma_curve_width: 1,
      chroma_falloff_light: 0, chroma_falloff_dark: 0, chroma_variance_per_hue: 0,
      l_variance_per_hue: 0, earthiness: 0,
      highlight_shift_strength: 0, shadow_shift_strength: 0,
      // The anchors take their hue from the shift targets, so both have to be green
      // too — otherwise the four-colour palette smuggles in an indigo and a cream.
      highlight_hue_target: 118, shadow_hue_target: 128, neutral_temperature: 128,
      neutral_chroma: 0.05, neutral_count: 0, accent_count: 0,
      bg_ramp_length: 1, fg_ramp_length: 2,
      min_anchor_contrast: 4.5, min_delta_e: 6, seed: 4,
    },
  },
  {
    id: 'cga',
    name: 'CGA',
    group: 'emulation',
    doc: 'Saturated, high-contrast, and unapologetically digital. Two bits per channel with no earthiness at all.',
    params: {
      color_count: 16, hue_count: 4, hue_scheme: 'tetradic', root_hue: 0, hue_jitter: 0,
      perceptual_hue_spacing: 0, l_mid_base: 0.6, l_step: 0.28, l_curve: 'linear',
      chroma_base: 0.28, chroma_cap: 0.37, earthiness: 0,
      chroma_falloff_light: -0.01, chroma_falloff_dark: 0,
      highlight_shift_strength: 0, shadow_shift_strength: 0,
      bits_r: 2, bits_g: 2, bits_b: 2, quantize_mode: 'round',
      neutral_count: 2, accent_count: 0, min_delta_e: 6, seed: 16,
    },
  },
  {
    id: 'ega',
    name: 'EGA',
    group: 'emulation',
    doc: 'Six-bit RGB, exactly 2/2/2. Slightly softer than CGA thanks to a longer neutral ramp.',
    params: {
      color_count: 16, hue_count: 4, hue_scheme: 'even', root_hue: 20, hue_jitter: 0,
      perceptual_hue_spacing: 0.3, l_mid_base: 0.56, l_step: 0.24,
      chroma_base: 0.24, chroma_cap: 0.34, earthiness: 0.05,
      bits_r: 2, bits_g: 2, bits_b: 2, quantize_mode: 'error-weighted',
      neutral_count: 3, accent_count: 0, min_delta_e: 5, seed: 64,
    },
  },
  {
    id: 'c64',
    name: 'C64',
    group: 'emulation',
    doc: 'Muted, slightly muddy, very few bright colours. A fixed hardware palette, so the bit depths stay open.',
    params: {
      color_count: 16, hue_count: 4, hue_scheme: 'even', root_hue: 40, hue_jitter: 4,
      l_dark_anchor: 0.1, l_light_anchor: 0.93, l_mid_base: 0.5, l_step: 0.19,
      chroma_base: 0.12, chroma_cap: 0.2, earthiness: 0.35,
      chroma_falloff_light: 0.03, chroma_falloff_dark: 0.01,
      highlight_shift_strength: 0.15, shadow_shift_strength: 0.2,
      neutral_count: 3, accent_count: 0, min_delta_e: 5, seed: 6510,
    },
  },
  {
    id: 'genesis',
    name: 'Genesis',
    group: 'emulation',
    doc: 'Nine-bit colour, 3/3/3. Coarse enough that error-weighted quantisation earns its keep.',
    params: {
      color_count: 32, hue_count: 5, hue_scheme: 'analogous', root_hue: 250, hue_span: 200,
      l_mid_base: 0.52, l_step: 0.17, chroma_base: 0.17, chroma_cap: 0.3,
      earthiness: 0.1, bg_chroma_mult: 0.45,
      bits_r: 3, bits_g: 3, bits_b: 3, quantize_mode: 'error-weighted',
      neutral_count: 3, accent_count: 2, min_delta_e: 4, seed: 68000,
    },
  },
  {
    id: 'snes',
    name: 'SNES',
    group: 'emulation',
    doc: 'Fifteen-bit colour, 5/5/5. Long ramps and soft gradients — the depth the hardware was known for.',
    params: {
      color_count: 48, hue_count: 6, hue_scheme: 'analogous', root_hue: 210, hue_span: 260,
      fg_ramp_length: 5, bg_ramp_length: 3, l_mid_base: 0.55, l_step: 0.13,
      l_curve: 's-curve', chroma_base: 0.15, chroma_cap: 0.28, earthiness: 0.15,
      bits_r: 5, bits_g: 5, bits_b: 5, quantize_mode: 'error-weighted',
      neutral_count: 4, neutral_split: true, accent_count: 2, min_delta_e: 3, seed: 5195,
    },
  },
  {
    id: 'pico8',
    name: 'PICO-8-ish',
    group: 'emulation',
    doc: 'Sixteen punchy colours with wide hue coverage and no muddiness anywhere.',
    params: {
      color_count: 16, hue_count: 4, hue_scheme: 'even', root_hue: 350, hue_jitter: 8,
      l_dark_anchor: 0.08, l_light_anchor: 0.96, l_mid_base: 0.6, l_step: 0.24,
      chroma_base: 0.21, chroma_cap: 0.33, earthiness: 0,
      chroma_falloff_light: -0.01, chroma_falloff_dark: -0.02,
      highlight_shift_strength: 0.3, shadow_shift_strength: 0.4,
      neutral_count: 2, accent_count: 0, min_delta_e: 6, seed: 8,
    },
  },

  // --- Mood ---------------------------------------------------------------
  {
    id: 'sunset-desert',
    name: 'Sunset Desert',
    group: 'mood',
    doc: 'Low sun on sandstone: warm analogous hues, hot highlights, violet shadows.',
    params: {
      // The analogous arc is centred on root_hue, so span 130 would reach back into
      // magenta at the dark end. 95 keeps it red-through-gold.
      color_count: 32, hue_scheme: 'analogous', root_hue: 45, hue_span: 95,
      l_mid_base: 0.6, l_step: 0.15, chroma_base: 0.17, earthiness: 0.25,
      // A little hue-adaptive lightness lets the gold end of the arc glow instead of
      // sitting as dull ochre — the reds are unaffected (their cusp is already at mid L).
      hue_lightness_follow: 0.4,
      highlight_hue_target: 75, highlight_shift_strength: 0.35,
      shadow_hue_target: 290, shadow_shift_strength: 0.45,
      global_temperature: 0.35, atmosphere_hue: 30, atmosphere_strength: 0.45,
      bg_lightness_offset: 0.05, neutral_temperature: 55, seed: 2201,
    },
  },
  {
    id: 'frozen-tundra',
    name: 'Frozen Tundra',
    group: 'mood',
    doc: 'Pale, high-key and cold. Backgrounds lift rather than darken, the way snow bounces light.',
    params: {
      color_count: 32, hue_scheme: 'analogous', root_hue: 215, hue_span: 110,
      l_dark_anchor: 0.16, l_light_anchor: 0.97, l_mid_base: 0.68, l_step: 0.13,
      l_curve: 'ease-light', chroma_base: 0.09, chroma_cap: 0.18, earthiness: 0.05,
      highlight_hue_target: 200, highlight_shift_strength: 0.2,
      shadow_hue_target: 265, shadow_shift_strength: 0.4,
      global_temperature: -0.4, bg_lightness_offset: 0.12, bg_chroma_mult: 0.3,
      atmosphere_hue: 210, atmosphere_strength: 0.6, neutral_temperature: 220,
      // Strong aerial perspective packs the backgrounds into one narrow band; asking
      // for deltaE 4 between all of them is past the packing limit at this contrast.
      min_delta_e: 3, seed: 77,
    },
  },
  {
    id: 'toxic-swamp',
    name: 'Toxic Swamp',
    group: 'mood',
    doc: 'Inverted temperature split — cool lights over warm shadows — which is what makes it read as deliberately wrong.',
    params: {
      color_count: 32, hue_scheme: 'analogous', root_hue: 100, hue_span: 120,
      l_mid_base: 0.45, l_step: 0.15, chroma_base: 0.2, chroma_falloff_dark: -0.05,
      // The whole point is acid yellow-greens; at a flat mid grey they turn dull olive.
      // Riding them toward their high-lightness cusp is what makes the swamp read toxic.
      hue_lightness_follow: 0.55,
      earthiness: 0.3, temperature_split: 0.1,
      highlight_hue_target: 150, highlight_shift_strength: 0.4,
      shadow_hue_target: 40, shadow_shift_strength: 0.4,
      atmosphere_hue: 110, atmosphere_strength: 0.5, bg_lightness_offset: -0.12,
      accent_count: 2, accent_chroma_boost: 0.1, neutral_temperature: 110, seed: 313,
    },
  },
  {
    id: 'neon-cyberpunk',
    name: 'Neon Cyberpunk',
    group: 'mood',
    doc: 'Emissive: negative chroma falloff keeps highlights hot instead of washing them out.',
    params: {
      color_count: 32, hue_scheme: 'split-comp', root_hue: 300, hue_span: 200,
      l_dark_anchor: 0.06, l_mid_base: 0.5, l_step: 0.18,
      chroma_base: 0.26, chroma_cap: 0.37, chroma_falloff_light: -0.05,
      chroma_falloff_dark: -0.03, earthiness: 0,
      // Neon means every hue at full punch; the split-comp arc reaches into yellow-green,
      // which needs high lightness to stay emissive rather than collapsing to olive.
      hue_lightness_follow: 0.7,
      highlight_hue_target: 330, highlight_shift_strength: 0.3,
      shadow_hue_target: 265, shadow_shift_strength: 0.45,
      bg_chroma_mult: 0.25, bg_lightness_offset: -0.2,
      atmosphere_hue: 280, atmosphere_strength: 0.4,
      accent_count: 4, accent_chroma_boost: 0.11, accent_l: 0.72, seed: 2077,
    },
  },
  {
    id: 'autumn-forest',
    name: 'Autumn Forest',
    group: 'mood',
    doc: 'Ochre, rust and moss. Heavy earthiness keeps it from tipping into orange candy.',
    params: {
      color_count: 32, hue_scheme: 'analogous', root_hue: 58, hue_span: 105,
      l_mid_base: 0.52, l_step: 0.15, chroma_base: 0.16, earthiness: 0.45,
      highlight_hue_target: 80, highlight_shift_strength: 0.28,
      shadow_hue_target: 300, shadow_shift_strength: 0.35,
      global_temperature: 0.2, atmosphere_hue: 45, atmosphere_strength: 0.35,
      neutral_temperature: 60, neutral_chroma: 0.026, seed: 1010,
    },
  },
  {
    id: 'underwater-cave',
    name: 'Underwater Cave',
    group: 'mood',
    doc: 'Everything drifts toward deep cyan with distance; foreground chroma is what keeps sprites legible.',
    params: {
      color_count: 32, hue_scheme: 'analogous', root_hue: 195, hue_span: 130,
      l_dark_anchor: 0.07, l_mid_base: 0.44, l_step: 0.15,
      chroma_base: 0.15, chroma_falloff_dark: -0.03, earthiness: 0.1,
      highlight_hue_target: 175, highlight_shift_strength: 0.3,
      shadow_hue_target: 255, shadow_shift_strength: 0.45,
      global_temperature: -0.3, bg_chroma_mult: 0.3, bg_lightness_offset: -0.15,
      atmosphere_hue: 195, atmosphere_strength: 0.7, bg_hue_shift: 0.6,
      fg_bg_separation_min: 0.2, seed: 20000,
    },
  },
  {
    id: 'blood-moon',
    name: 'Blood Moon Horror',
    group: 'mood',
    doc: 'Narrow red arc against near-black. The dark anchor does most of the work.',
    params: {
      color_count: 24, hue_scheme: 'analogous', root_hue: 15, hue_span: 55,
      l_dark_anchor: 0.05, l_light_anchor: 0.88, l_mid_base: 0.42, l_step: 0.17,
      l_curve: 'ease-dark', chroma_base: 0.19, chroma_falloff_dark: -0.04,
      earthiness: 0.15, highlight_hue_target: 35, highlight_shift_strength: 0.25,
      shadow_hue_target: 340, shadow_shift_strength: 0.4,
      bg_chroma_mult: 0.25, bg_lightness_offset: -0.16,
      atmosphere_hue: 5, atmosphere_strength: 0.4, neutral_temperature: 10, seed: 666,
    },
  },
  {
    id: 'pastel-cozy',
    name: 'Pastel Cozy',
    group: 'mood',
    doc: 'High lightness, low chroma, compressed range. Soft enough that ramp evenness matters more than contrast.',
    params: {
      color_count: 32, hue_scheme: 'even', root_hue: 340, hue_jitter: 10,
      l_dark_anchor: 0.2, l_light_anchor: 0.98, l_mid_base: 0.74, l_step: 0.1,
      l_curve: 'ease-light', l_range_compress: 0.15,
      chroma_base: 0.08, chroma_cap: 0.15, chroma_peak_l: 0.75, earthiness: 0.1,
      highlight_shift_strength: 0.2, shadow_shift_strength: 0.3,
      bg_chroma_mult: 0.5, bg_lightness_offset: 0.06, dither_evenness: 0.6,
      min_delta_e: 3, seed: 909,
    },
  },
  {
    id: 'monochrome-ink',
    name: 'Monochrome Ink',
    group: 'mood',
    doc: 'One hue at near-zero chroma with a hard value ladder — the palette that has to survive the grayscale check.',
    params: {
      color_count: 12, hue_count: 1, hue_scheme: 'analogous', root_hue: 250, hue_span: 0,
      hue_jitter: 0, l_dark_anchor: 0.07, l_light_anchor: 0.97,
      l_mid_base: 0.5, l_step: 0.2, l_curve: 'linear', fg_ramp_length: 5,
      chroma_base: 0.02, chroma_cap: 0.05, earthiness: 0,
      highlight_shift_strength: 0, shadow_shift_strength: 0,
      neutral_count: 2, accent_count: 0, neutral_chroma: 0.008, seed: 1,
    },
  },
  {
    id: 'sepia-western',
    name: 'Sepia Western',
    group: 'mood',
    doc: 'Dust and old film. Maximum earthiness with a narrow warm arc.',
    params: {
      color_count: 24, hue_scheme: 'analogous', root_hue: 45, hue_span: 70,
      l_mid_base: 0.58, l_step: 0.15, chroma_base: 0.12, chroma_cap: 0.18,
      earthiness: 0.7, global_temperature: 0.3,
      highlight_hue_target: 65, highlight_shift_strength: 0.2,
      shadow_hue_target: 20, shadow_shift_strength: 0.25, temperature_split: 0.6,
      bg_chroma_mult: 0.5, atmosphere_hue: 50, atmosphere_strength: 0.5,
      neutral_temperature: 50, seed: 1873,
    },
  },
  {
    id: 'candlelit-dungeon',
    name: 'Candlelit Dungeon',
    group: 'mood',
    doc: 'Warm firelight against cold stone: the shadow target sits warm, the neutrals stay cool.',
    params: {
      color_count: 32, hue_scheme: 'complementary', root_hue: 40, hue_span: 150,
      l_dark_anchor: 0.06, l_mid_base: 0.46, l_step: 0.17, l_curve: 'ease-dark',
      chroma_base: 0.16, chroma_falloff_dark: -0.02, earthiness: 0.3,
      highlight_hue_target: 60, highlight_shift_strength: 0.35,
      shadow_hue_target: 25, shadow_shift_strength: 0.3, temperature_split: 0.65,
      bg_chroma_mult: 0.3, bg_lightness_offset: -0.16,
      atmosphere_hue: 250, atmosphere_strength: 0.45,
      neutral_temperature: 240, accent_count: 2, seed: 1349,
    },
  },
  {
    id: 'overcast-coast',
    name: 'Overcast Coast',
    group: 'mood',
    doc: 'Flat grey light. Heavy range compression and strong aerial perspective, everything reading a little washed.',
    params: {
      color_count: 32, hue_scheme: 'analogous', root_hue: 200, hue_span: 150,
      l_mid_base: 0.6, l_step: 0.11, l_range_compress: 0.35,
      chroma_base: 0.08, chroma_cap: 0.16, chroma_falloff_light: 0.04, earthiness: 0.2,
      highlight_hue_target: 210, highlight_shift_strength: 0.2,
      shadow_hue_target: 255, shadow_shift_strength: 0.3,
      global_temperature: -0.2, bg_chroma_mult: 0.35, bg_lightness_offset: 0.08,
      atmosphere_hue: 215, atmosphere_strength: 0.65, dither_evenness: 0.5,
      min_delta_e: 3, seed: 4747,
    },
  },
  {
    id: 'oklab-crayon',
    name: 'OKLAB Crayon',
    group: 'mood',
    doc: 'Bright primary crayon set — five saturated hue families in light/mid/dark plus a neutral ramp. Derived by fitting the parameters to a reference strip (fit.js), which is why the yellow and green read as vivid gold and leaf rather than olive: hue_lightness_follow rides them up to where sRGB can hold the chroma.',
    params: {
      color_count: 20, hue_count: 5, hue_scheme: 'custom', root_hue: 242, hue_span: 337,
      hue_jitter: 7.4, perceptual_hue_spacing: 0, fg_ramp_length: 3, neutral_count: 3,
      accent_count: 0,
      l_dark_anchor: 0.15, l_light_anchor: 0.997, l_mid_base: 0.626, l_step: 0.289,
      l_curve: 'linear', l_range_compress: 0.34, l_variance_per_hue: 0.15,
      hue_lightness_follow: 0.975,
      chroma_base: 0.282, chroma_peak_l: 0.644, chroma_curve_width: 0.604,
      chroma_falloff_light: 0.018, chroma_falloff_dark: 0.11, chroma_variance_per_hue: 0.085,
      earthiness: 0.036, chroma_cap: 0.256,
      highlight_hue_target: 84, highlight_shift_strength: 0.142,
      shadow_hue_target: 118, shadow_shift_strength: 0.111, shift_model: 'relative-rotation',
      global_temperature: 0.43, temperature_split: 0.978,
      neutral_temperature: 355, neutral_chroma: 0, neutral_l_spread: 0.296,
      min_delta_e: 4, seed: 12345,
    },
  },
];

// Every preset here predates hue-adaptive lightness (`hue_lightness_follow`) and was tuned —
// and its golden snapshot approved — without it. Pin it off on any preset that does not set
// it explicitly, so each reproduces its originally-approved look byte-for-byte rather than
// silently shifting when the feature shipped on-by-default. The default palette (no preset)
// still gets the fix; a preset opts in by setting its own value (OKLAB Crayon uses 0.975).
for (const preset of PRESETS) {
  if (preset.params.hue_lightness_follow === undefined) preset.params.hue_lightness_follow = 0;
}

/** Presets looked up by id. */
export const PRESET_BY_ID = new Map(PRESETS.map((p) => [p.id, p]));

/** The full parameter set for a preset id; throws if the id is unknown. */
export function presetParams(id) {
  const preset = PRESET_BY_ID.get(id);
  if (!preset) throw new Error(`unknown preset "${id}"`);
  return normalizeParams(preset.params);
}
