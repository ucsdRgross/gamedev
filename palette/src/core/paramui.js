// Human-readable presentation for every parameter (UX_PLAN U1).
//
// `params.js` owns the *contract* — field order, ranges, defaults, the seed payload. This
// file owns how a parameter is *spoken about*: the name on the slider, the one-line hint
// under it, what each end of the range means, and what each enum option does. It is a
// separate module for one reason: `params.js` is seed-critical and append-only, so the file
// that gets edited every time a wording improves should not be the file where a stray edit
// silently reinterprets every PAL1 seed ever pasted.
//
// The panel shows `label` + `hint` + the end labels; the full `doc` string from params.js is
// still there on hover for the long version. Written so that reading the doc is optional:
// a slider whose two ends are named does not need prose.
//
// `test/params.test.js` asserts this map covers every parameter exactly — no missing entry,
// no entry for a parameter that does not exist, no duplicate labels, every enum option named.

/**
 * name -> { label, hint, low, high, options }
 *   label   what the control is called (shown instead of the raw snake_case key)
 *   hint    one line under it: what it does, in the user's terms
 *   low/high what each end of a numeric range means
 *   options enum value -> label ("what picking this does"), shown in the dropdown
 */
export const PARAM_UI = {
  // --- Structure ---------------------------------------------------------
  color_count: {
    label: 'Number of colours',
    hint: 'Total slots in the palette',
    low: 'fewer · tighter retro', high: 'richer · more variety',
  },
  hue_count: {
    label: 'Colour families',
    hint: 'How many distinct hues the budget splits across — 0 decides for you',
    low: 'cohesive · themed', high: 'varied · rainbow',
  },
  hue_scheme: {
    label: 'How the hues relate',
    hint: 'The biggest mood driver — set this one first',
    options: {
      even: 'Even spread — generic, no relationship',
      analogous: 'Analogous — cohesive, one mood',
      complementary: 'Complementary — punchy two-sided contrast',
      'split-comp': 'Split complement — softer contrast',
      triadic: 'Triadic — balanced three-way variety',
      tetradic: 'Tetradic — balanced four-way variety',
      custom: 'Fan — even spread across the hue span',
    },
  },
  root_hue: {
    label: 'Colour of the world',
    hint: '30–60 desert · 120 verdant · 200–240 night · 280–330 magic',
    low: '0° red', high: '360° back to red',
  },
  hue_span: {
    label: 'How wide the hues spread',
    hint: 'The arc the hue families cover (analogous and split schemes)',
    low: 'one strong theme', high: 'varied but related',
  },
  hue_jitter: {
    label: 'Hand-picked wobble',
    hint: 'Random nudge on each hue angle so the set looks curated, not calculated',
    low: 'machine-regular', high: 'organic',
  },
  perceptual_hue_spacing: {
    label: 'Hue spacing: by angle or by eye',
    hint: 'OKLCH hue is uneven — green sprawls, yellow is narrow',
    low: 'even by angle', high: 'even to the eye',
  },
  fg_ramp_length: {
    label: 'Shades per foreground colour',
    hint: '3 is the pixel-art minimum; 4–5 gives smooth metal and skin',
    low: 'flat', high: 'smooth shading',
  },
  bg_ramp_length: {
    label: 'Shades per background colour',
    hint: 'Backdrops carry less internal detail than sprites',
    low: 'flat', high: 'visible depth',
  },
  neutral_count: {
    label: 'Grey / stone / metal slots',
    hint: 'The desaturated backbone most scenes lean on',
    low: 'organic · no chrome', high: 'architectural · UI-heavy',
  },
  accent_count: {
    label: 'Pop colours',
    hint: 'High-chroma slots for UI highlights, FX and pickups',
    low: 'strictly naturalistic', high: 'lots of alerts',
  },
  tier_priority: {
    label: 'Spend the budget on…',
    hint: 'Who gets funded first when there are not enough colours to go round',
    options: {
      standard: 'Balanced — no group favoured',
      'background-first': 'Backgrounds first — atmospheric scenes',
      'neutrals-first': 'Neutrals first — UI and architecture',
      'ramps-first': 'Foreground ramps first — protect shading',
    },
  },

  // --- Lightness ---------------------------------------------------------
  l_dark_anchor: {
    label: 'Darkest colour',
    hint: 'Outlines and the deepest shadow',
    low: 'inky · high contrast', high: 'soft · faded darks',
  },
  l_light_anchor: {
    label: 'Brightest colour',
    hint: 'The ceiling every highlight is measured against',
    low: 'dim · nocturnal', high: 'paper-white',
  },
  l_mid_base: {
    label: 'Overall brightness',
    hint: 'Where foreground midtones sit — the light/dark master',
    low: 'dungeon', high: 'bright daylight',
  },
  l_step: {
    label: 'Shading contrast',
    hint: 'The lightness jump between one shade and the next — this IS contrast',
    low: 'soft · painterly', high: 'punchy · reads at 1×',
  },
  l_curve: {
    label: 'Where the shades bunch up',
    hint: 'How the steps of a ramp are distributed between dark and light',
    options: {
      'ease-dark': 'Bunch in the shadows — rich darks',
      linear: 'Even steps throughout',
      'ease-light': 'Bunch in the highlights — rich lights',
      's-curve': 'Spread the midtones — maximum form',
    },
  },
  l_range_compress: {
    label: 'Haze / washed out',
    hint: 'Squeezes every ramp toward mid-grey — atmosphere and distance',
    low: 'crisp full contrast', high: 'foggy · faded photo',
  },
  l_variance_per_hue: {
    label: 'Random brightness variety',
    hint: 'Lets hues sit at different lightnesses at random (zero it to freeze the palette)',
    low: 'rigid · systematic', high: 'natural variety',
  },
  hue_lightness_follow: {
    label: 'Let each hue find its brightest form',
    hint: 'Yellow, green and cyan only hold colour high on the lightness axis',
    low: 'uniform · olive greens', high: 'vivid gold and leaf-green',
  },

  // --- Chroma ------------------------------------------------------------
  chroma_base: {
    label: 'Saturation',
    hint: 'Master colourfulness — the fastest fix for "too dull" or "too garish"',
    low: 'greyscale', high: 'neon',
  },
  chroma_peak_l: {
    label: 'Most colourful at',
    hint: 'The lightness where colour is strongest; real pigment peaks upper-mid',
    low: 'shadows · moody', high: 'highlights · glowing',
  },
  chroma_curve_width: {
    label: 'Colour across the ramp',
    hint: 'How fast saturation falls away from its peak',
    low: 'midtones only · natural', high: 'whole ramp · poster',
  },
  chroma_falloff_light: {
    label: 'Highlights keep or lose colour',
    hint: 'What happens to saturation as a colour brightens',
    low: 'hot · neon · emissive', high: 'sun-bleached · pastel',
  },
  chroma_falloff_dark: {
    label: 'Shadows keep or lose colour',
    hint: 'The knob that decides between painted shadows and mud',
    low: 'rich coloured shadows', high: 'grey · muddy shadows',
  },
  chroma_variance_per_hue: {
    label: 'Saturation variety between hues',
    hint: 'A vivid red beside a muted green, rather than one flat saturation',
    low: 'uniform', high: 'natural variety',
  },
  earthiness: {
    label: 'Earthy — dirt, rust, wood',
    hint: 'Pulls toward ochre while cutting chroma; keeps warmth, unlike plain desaturation',
    low: 'clean synthetic colour', high: 'weathered · historical',
  },
  chroma_cap: {
    label: 'Saturation ceiling (safety)',
    hint: 'A hard limit applied before gamut mapping so colours stay reachable',
    low: 'guaranteed muted', high: 'the most the display allows',
  },

  // --- Hue shifting ------------------------------------------------------
  highlight_hue_target: {
    label: 'Colour of the light',
    hint: '90 sunlight · 200 moonlight · 40 firelight · 330 magic',
    low: '0° red', high: '360° back to red',
  },
  highlight_shift_strength: {
    label: 'Hue-shifted highlights',
    hint: 'How far highlights rotate toward the light colour — the painted-shading knob',
    low: 'flat tint only', high: 'strongly painted',
  },
  shadow_hue_target: {
    label: 'Colour of the shadows',
    hint: '280 cool indigo · 20 warm firelit · 200 icy',
    low: '0° red', high: '360° back to red',
  },
  shadow_shift_strength: {
    label: 'Hue-shifted shadows',
    hint: 'How far shadows rotate toward the shadow colour',
    low: 'just darker', high: 'dramatic depth',
  },
  shift_model: {
    label: 'How hues rotate',
    hint: 'Whether a shifted colour keeps its own identity',
    options: {
      'global-attractor': 'One temperature for everything — cohesive, filmic',
      'relative-rotation': 'Rotate, but keep each hue distinct',
      'per-family': 'Keep each hue’s identity (safe default)',
    },
  },
  shift_direction: {
    label: 'Rotation direction',
    hint: 'Only change this if you see a hue break where two ramps meet',
    options: {
      shortest: 'Shortest way round — natural, can seam',
      'always-cw': 'Always clockwise — no seam',
      'always-ccw': 'Always anticlockwise — no seam',
    },
  },
  global_temperature: {
    label: 'Warm / cool bias',
    hint: 'A mood tint over the entire palette',
    low: 'cooler · winter · tech', high: 'warmer · sunset · cozy',
  },
  temperature_split: {
    label: 'Warm light vs cool shadow',
    hint: 'Below a quarter it inverts — cool light, warm shadow',
    low: 'inverted · toxic · alien', high: 'natural realism',
  },

  // --- Background --------------------------------------------------------
  bg_chroma_mult: {
    label: 'Background saturation',
    hint: 'The main tool for making sprites pop off the scene',
    low: 'grey · recessive', high: 'as vivid as the sprites',
  },
  bg_lightness_offset: {
    label: 'Background brightness',
    hint: 'How far backdrops sit above or below the foreground',
    low: 'dark backdrop · night', high: 'light backdrop · fog',
  },
  bg_hue_shift: {
    label: 'Backgrounds pull to the air colour',
    hint: 'Aerial perspective, applied to hue',
    low: 'true to their own hue', high: 'unified atmospheric wash',
  },
  atmosphere_hue: {
    label: 'Colour of the air',
    hint: '220 misty blue · 30 dusty warm · 200 underwater',
    low: '0° red', high: '360° back to red',
  },
  atmosphere_strength: {
    label: 'Distance haze',
    hint: 'How far distance washes colours toward the air colour',
    low: 'crisp · flat', high: 'deep layered haze',
  },
  fg_bg_separation_min: {
    label: 'Keep sprites readable on backdrops',
    hint: 'An enforced minimum distance between any foreground and any background colour',
    low: 'close · unified', high: 'guaranteed pop',
  },

  // --- Neutrals ----------------------------------------------------------
  neutral_temperature: {
    label: 'Tint of the greys',
    hint: '230 cool slate and steel · 60 warm taupe and sand',
    low: '0° red', high: '360° back to red',
  },
  neutral_chroma: {
    label: 'Greys: digital or painted',
    hint: 'A little colour in the greys reads as painted rather than sterile',
    low: 'pure digital grey', high: 'painted greys',
  },
  neutral_split: {
    label: 'Separate warm and cool greys',
    hint: 'Two neutral families instead of one — stone and skin want different greys',
  },
  neutral_l_spread: {
    label: 'Contrast within the greys',
    hint: 'How far the darkest and lightest grey are apart',
    low: 'flat · quiet UI', high: 'bold stone and metal',
  },

  // --- Accents -----------------------------------------------------------
  accent_chroma_boost: {
    label: 'How loud the accents are',
    hint: 'How far accents out-saturate everything else',
    low: 'sits with the palette', high: 'shouts',
  },
  accent_hue_mode: {
    label: 'Where accents sit',
    hint: 'Which hues the pop colours are given',
    options: {
      complementary: 'Opposite the primaries — reads as alert or danger',
      'spectral-gap': 'Fill the hue gaps — harmonious variety',
      'fixed-offset': 'A set rotation from the root hue',
    },
  },
  accent_l: {
    label: 'Accent brightness',
    hint: 'Keep it clear of the overall brightness so accents read as a separate layer',
    low: 'deep jewel tones', high: 'bright and glowing',
  },

  // --- Hardware / output -------------------------------------------------
  bits_r: {
    label: 'Red bit depth',
    hint: '8 modern · 5 with 5/5/5 is SNES · 3 with 3/3/3 is Genesis',
    low: 'harsh retro banding', high: 'unlimited',
  },
  bits_g: {
    label: 'Green bit depth',
    hint: 'Set it together with red and blue for a period-accurate console feel',
    low: 'harsh retro banding', high: 'unlimited',
  },
  bits_b: {
    label: 'Blue bit depth',
    hint: 'Real hardware often gives blue one bit fewer (5/6/5)',
    low: 'harsh retro banding', high: 'unlimited',
  },
  quantize_mode: {
    label: 'Snapping to hardware colours',
    hint: 'How an ideal colour picks its nearest legal one',
    options: {
      round: 'Round — simple and predictable',
      floor: 'Floor — simple, biases dark',
      'error-weighted': 'Lowest perceptual error — best, especially at low bit depth',
    },
  },
  gamut_map_mode: {
    label: 'Handling impossible colours',
    hint: 'What happens to a colour sRGB cannot show',
    options: {
      'chroma-reduce': 'Desaturate until it fits — keeps hue and lightness (correct)',
      clip: 'Clip the channels — distorts hue (artifact demo)',
      'reduce-l-adjust': 'Trade some lightness instead',
    },
  },

  // --- Quality constraints -----------------------------------------------
  min_delta_e: {
    label: 'Minimum difference between colours',
    hint: 'Stops two slots being near-duplicates. Best effort — misses are reported',
    low: 'allow subtle neighbours', high: 'every colour visibly distinct',
  },
  min_anchor_contrast: {
    label: 'Text legibility floor (WCAG)',
    hint: 'Contrast forced between the darkest and lightest colour',
    low: 'loose', high: 'accessible text',
  },
  dither_evenness: {
    label: 'Even ramp steps (dither-friendly)',
    hint: 'Equal lightness gaps checkerboard into convincing in-between tones',
    low: 'tuned by eye', high: 'mathematically even',
  },
  force_unique_hex: {
    label: 'No duplicate colours',
    hint: 'Guarantees every slot is a distinct hex after quantisation',
  },

  // --- Meta --------------------------------------------------------------
  seed: {
    label: 'Variation number',
    hint: 'Same number, same palette. Change it to reroll the random variation only',
    low: 'one variation', high: 'another',
  },

  // --- Reference recolouring ---------------------------------------------
  recolor_mode: {
    label: 'How images are recoloured',
    hint: 'Pixel art and photographs need opposite strategies',
    options: {
      auto: 'Choose by the source’s colour count',
      indexed: 'Indexed — one target per source colour (pixel art)',
      quantize: 'Per pixel with dithering (photographs)',
    },
  },
  recolor_indexed_max: {
    label: 'Auto switches at this colour count',
    hint: 'Sources with fewer colours than this are treated as pixel art',
    low: 'send more down the photo path', high: 'treat richer images as pixel art',
  },
  remap_match: {
    label: 'How source colours find targets',
    hint: 'The single biggest decision in an indexed recolour',
    options: {
      'delta-e': 'Nearest colour — accurate, but jumps when the palette moves',
      'lightness-rank': 'By brightness order — stable, keeps value structure',
      optimal: 'Best overall assignment, no target reused',
    },
  },
  remap_preserve_order: {
    label: 'Keep dark→dark, light→light',
    hint: 'Forces the mapping monotonic in lightness — what makes an alien palette still read',
  },
  remap_overflow: {
    label: 'When the source has more colours',
    hint: 'What to do when there are not enough targets to go round',
    options: {
      share: 'Share targets — keeps detail, can flatten',
      merge: 'Merge the source first — cleaner, fewer collisions',
    },
  },
  quant_dither: {
    label: 'Dithering (photo path)',
    hint: 'Ordered patterns hold still frame to frame; error diffusion boils',
    options: {
      none: 'None — hard bands on gradients',
      'floyd-steinberg': 'Floyd–Steinberg — smooth, best for stills',
      bayer4: 'Bayer 4×4 — stable, best for animation',
      bayer8: 'Bayer 8×8 — stable, finer texture',
    },
  },
  quant_dither_strength: {
    label: 'Dither strength',
    hint: 'How hard the dithering works to hide banding',
    low: 'hard bands', high: 'smoothest · noisiest',
  },
  quant_lightness_weight: {
    label: 'Match by lightness or by hue',
    hint: 'Raise it when recoloured photos lose their shading',
    low: 'favour hue', high: 'protect value and form',
  },
  quant_downscale: {
    label: 'Shrink to this width first',
    hint: 'Turns a photograph into genuine chunky pixel art; 0 keeps the resolution',
    low: 'keep original resolution', high: 'coarse pixels',
  },
  gif_frame: {
    label: 'Frame used for a still export',
    hint: 'Animations are always recoloured whole — this only picks the single-image frame',
    low: 'first frame', high: 'later frame',
  },
  recolor_context: {
    label: 'Match colours by their job',
    hint: 'Sends a source background to a target background instead of the nearest colour',
    options: {
      off: 'Off — pure colour matching',
      suggest: 'Infer each source colour’s job from the image',
      manual: 'Infer, but my own assignments win',
    },
  },
  remap_context_order: {
    label: 'Combine context with lightness order',
    hint: 'Off, forcing dark→dark wins outright and context is ignored',
  },
  remap_context_bias: {
    label: 'How hard context pushes',
    hint: '0.2–0.4 keeps dithered texture on tile art; 1 is a hard rule',
    low: 'a mild preference', high: 'a hard rule',
  },

  // Custom hue pins (U6.3). Only bite when the scheme is “Chosen by hand”.
  custom_hue_count: {
    label: 'Hues chosen by hand',
    hint: 'with the scheme set to “Chosen by hand”: how many angles you are pinning yourself',
    low: 'none — an even spread', high: 'six pinned by hand',
  },
  custom_hue_1: {
    label: 'Pinned hue 1', hint: 'the first hand-picked hue angle', low: 'red', high: 'red again',
  },
  custom_hue_2: {
    label: 'Pinned hue 2', hint: 'the second hand-picked hue angle', low: 'red', high: 'back to red',
  },
  custom_hue_3: {
    label: 'Pinned hue 3', hint: 'the third hand-picked hue angle', low: 'red', high: 'round to red',
  },
  custom_hue_4: {
    label: 'Pinned hue 4', hint: 'the fourth hand-picked hue angle', low: 'red', high: 'the whole way round',
  },
  custom_hue_5: {
    label: 'Pinned hue 5', hint: 'the fifth hand-picked hue angle', low: 'red', high: 'all the way round',
  },
  custom_hue_6: {
    label: 'Pinned hue 6', hint: 'the sixth hand-picked hue angle', low: 'red', high: 'right round to red',
  },
};

/**
 * The controls the Basics view shows — the five the README calls the big movers, plus the
 * handful that finish the job. Everything else is one click away under "All".
 * Order is the order they appear in Basics.
 */
export const BASIC_PARAMS = [
  'hue_scheme',
  'root_hue',
  'color_count',
  'hue_count',
  'l_mid_base',
  'l_step',
  'chroma_base',
  'earthiness',
  'highlight_shift_strength',
  'shadow_shift_strength',
  'bg_chroma_mult',
];
