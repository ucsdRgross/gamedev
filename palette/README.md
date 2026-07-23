# Pixel-Art Palette Creator

Procedural retro palette generator in OKLCH space. Generates structurally-sound
pixel-art palettes from 58 tunable parameters, proves they work by applying them to a
gallery of test visuals, and exports to Godot, Aseprite, and the web.

**Status: complete.** Generator, browser app, 34-scene test gallery, artist's-palette
picker (colour-space maps + 15 arrangement layouts), and reference-image recolouring —
including recolouring into your own external palette images — all built and gated
(297 tests green).

| Document | What it is |
|---|---|
| [PLAN.md](PLAN.md) | The specification — colour theory, algorithms, formulas, task list |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The `Palette` contract, design decisions, per-phase notes (§9 app, §10 gallery, §11 picker, §12 recolouring) |
| [PROGRESS.md](PROGRESS.md) | Task-by-task state. Source of truth for what is done |

New to the project? Read PLAN.md for *what* is being built, then ARCHITECTURE.md for
*how the built part works* and what the next phase has to build on. Everything you need
is in this directory — no setup outside the repository, and nothing to install.

## Requirements

Node 22 or newer, and nothing else — no dependencies to install. The `test` script uses
`node --test test/*.test.js`, whose glob expansion needs the runner built into Node ≥ 22.

## Running it

**Double-click `start.cmd`.** It boots the local server and opens the app in your browser —
no command line needed for anything, including adding your own reference images.

The rest is for working on the code.

```bash
npm test
```

297 tests: colour-space round-trips against published reference values, gamut mapping,
bit-depth quantisation, generator invariants across every palette size from 4 to 64, seed
round-trips, export round-trips, the dev-server API, the raster/analysis/dither modules, a
34-scene smoke test, the picker layouts and colour-space maps, the recolour paths (indexed,
quantize, external-palette extraction), the GIF codec, the Randomize exclusions, golden
snapshots, and a 10,000-case fuzz. Takes about 6 minutes;
`PALETTE_FUZZ_N=200 npm test` shortens the fuzz while iterating.

```bash
npm start
```

Starts the dependency-free dev server (default `http://localhost:5173/`) and serves the
browser app: live parameter sliders, a swatch grid with lock/override, undo/redo and a
history strip, seed field with URL-hash sync, save/load against `saved/*.json`, all eight
export formats, the **34-scene test gallery** (category filter, colour-vision views, zoom,
animation, drag-and-drop photo quantization), the **artist's-palette picker** (colour-space
maps by default, 15 arrangement layouts behind a selector), and the **recolour page** —
every reference image re-rendered in the generated palette, animations included, playing.

```bash
npm run render
```

Writes labelled swatch sheets, export strips, a preset contact sheet, a budget sweep, every
gallery scene (per-scene PNGs plus per-category contact sheets, for two palettes), the picker
layouts and colour-space maps, and the recoloured reference images — including real animated
GIFs in `out/recolor/` — to `out/` for direct inspection. These are meant to be looked at: a
palette can pass every test and still be wrong.

```bash
npm run build
```

Inlines the whole app into one double-clickable `dist/palette_creator.html` (a flat import
map of base64 data-URL modules — no bundler). Seeds and export/import work there; the
file-backed save API does not (there is no server behind it).

```js
import { generatePalette, paletteHexes } from './src/core/generate.js';
import { presetParams } from './src/core/presets.js';
import { runExport } from './src/core/export/index.js';

const palette = generatePalette(presetParams('snes'));
paletteHexes(palette);              // ['#0D0A18', '#3A2100', …]
palette.seed;                       // 'PAL1-…' — paste back to reproduce exactly
runExport('tres', palette);         // Godot resource, ready for solatro/ or necroma/
```

## Parameter reference

Every parameter, what it does, and **when to reach for it and which way to push it** for a
particular look. The same guidance is on each slider — hover its name in the app. Parameters
are grouped exactly as the panel groups them.

Two things worth knowing before you start:

- **Set the big movers first.** `hue_scheme`, `root_hue`, `color_count`, `l_mid_base` and
  `chroma_base` decide 80% of the feel. Tune the rest to taste afterward.
- **The seed string captures everything.** Copy it to reproduce a palette exactly, or paste
  someone else's. It encodes the full parameter set, not a random seed, so it keeps working
  even as the generator is re-tuned.

### Structure — how the budget is spent

| Parameter | What it controls | Push it this way |
|---|---|---|
| `color_count` | Total number of colours | **More** → richer shading/variety; **fewer** → tighter retro feel (4 Game Boy · 16 CGA · 32 Endesga · 64 AAP-64). Muddy or redundant colours mean too many for the hue count. |
| `hue_count` | Distinct hue families the budget is split across | **Higher** → varied, rainbow-ish; **2–3** → cohesive, strongly themed. `0` derives it. Too many at low `color_count` starves ramps into mud. |
| `hue_scheme` | The relationship between hues (biggest mood driver — set first) | `analogous` cohesive · `complementary` punchy contrast · `triadic`/`tetradic` balanced variety · `even` generic · `split-comp` softer complement. |
| `root_hue` | Rotates every hue together — "what colour is this world" | 30–60 desert/autumn · 120 verdant · 200–240 night/underwater · 280–330 magic/alien. The knob to re-theme a palette you otherwise like. |
| `hue_span` | Arc width the hues cover (analogous/split) | **Narrow** (40–80) → single strong theme; **wide** (180+) → varied but related. Widen if monotonous. |
| `hue_jitter` | Random wobble on hue angles | **Up** → organic, hand-picked; **0** → perfectly regular (can read sterile). Change `seed` to reroll. **Set to 0 to help freeze the palette** (see *Freezing*). |
| `perceptual_hue_spacing` | Even-angle vs even-to-the-eye hue spacing | **Toward 1** if hues look bunched (green sprawls, yellow is narrow in OKLCH). Leave ~0.5 otherwise. |
| `fg_ramp_length` | Shades per foreground colour | **3** pixel-art minimum · **4–5** smooth metal/skin/rounded forms. Lower to spend budget on more hues. |
| `bg_ramp_length` | Shades per background colour | **1–2** usual · **3** only when backdrops show real form/depth. |
| `neutral_count` | Grey/stone/metal/UI slots | **Up** for architecture, machinery, UI; **0** for organic scenes. |
| `accent_count` | High-chroma pop colours | **1–2** plenty · **0** for strictly naturalistic. |
| `tier_priority` | Which group is funded first when budget is tight | `background-first` atmospheric · `neutrals-first` UI/architecture · `ramps-first` protect foreground shading. Only matters at low `color_count`. |

### Lightness — value structure and contrast

| Parameter | What it controls | Push it this way |
|---|---|---|
| `l_dark_anchor` | Lightness of the darkest colour (outlines, deep shadow) | **Up** → soft faded darks · **down** → inky high-contrast outlines. Too high = mushy outlines; too low = crushed shadows. |
| `l_light_anchor` | Brightness ceiling | **Down** → dim, nocturnal, muted · **up** (0.95+) → bright highlights, paper-white UI. |
| `l_mid_base` | Where foreground midtones sit — overall light/dark master | **Down** → dark, moody, dungeon · **up** → bright, airy, daytime. |
| `l_step` | Lightness jump per ramp step — **this is contrast** | **Small** (0.08–0.12) → soft painterly blendable · **large** (0.2+) → punchy, readable at 1×. Raise if shading is flat, lower if harsh. |
| `l_curve` | Where ramp steps bunch up | `ease-dark` rich darks · `ease-light` rich highlights · `s-curve` max midtone form-reading · `linear` even. |
| `l_range_compress` | Squeeze ramps toward mid-grey | **Toward 1** → foggy, washed, hazy, dreamlike, faded-photo. The atmosphere/distance knob; overdo it and it all goes flat grey. |
| `l_variance_per_hue` | Different hues at different lightnesses | **Up** → natural variety · **0** → rigid systematic look. **Set to 0 to help freeze the palette.** |

### Chroma — saturation shaping

| Parameter | What it controls | Push it this way |
|---|---|---|
| `chroma_base` | Master saturation | **0** greyscale · **~0.1** muted/earthy · **~0.18** balanced · **0.3+** neon. Fastest fix for "too dull" or "too garish". |
| `chroma_peak_l` | Lightness where colour is most saturated | **Down** → vivid shadows (moody) · **up** → glowing highlights (emissive). Move toward the tones you want most colourful. |
| `chroma_curve_width` | How fast saturation falls off from the peak | **Narrow** → only midtones colourful, lights/darks grey (natural) · **wide** → colour across the whole ramp (poster/vivid). |
| `chroma_falloff_light` | Saturation change in highlights | **Positive** → sun-bleached, pastel tops · **negative** → hot, neon, emissive highlights (glow/lava/magic). |
| `chroma_falloff_dark` | Saturation change in shadows | **Negative** → rich coloured shadows (painterly) · **positive** → grey, muddy shadows. |
| `chroma_variance_per_hue` | Some hue families more saturated than others | **Up** → natural variety · **0** → uniform. **Set to 0 to help freeze the palette.** |
| `earthiness` | Pull toward ochre while cutting chroma | **Up** → dirt, rust, wood, natural muting (keeps warmth, unlike plain desaturation) · **0** → clean synthetic colour. |
| `chroma_cap` | Hard saturation ceiling (safety) | **Down** → guaranteed muted/print-safe · **up** (0.37) → most vivid the display allows. Lower it if bright colours look clipped. |

### Hue shifting — the painted-shading look

| Parameter | What it controls | Push it this way |
|---|---|---|
| `highlight_hue_target` | Hue highlights drift toward as they brighten | 90 sunlight · 200 moonlight · 40 firelight · 330 magic. Set to your light source's colour. |
| `highlight_shift_strength` | How far highlights rotate — the signature hue-shift knob | **Up** (~0.4) → lively "colours warm as they lighten" · **0** → flat tint-only shading. |
| `shadow_hue_target` | Hue shadows drift toward as they darken | 280 cool indigo · 20 warm firelit · 200 icy. Set ~complementary to the highlight target. |
| `shadow_shift_strength` | How hard shadows rotate | **Up** → dramatic warm-light/cool-shadow depth · **0** → shadows are just darker. |
| `shift_model` | How the shift is applied | `per-family` keeps hue identity (safe) · `global-attractor` unified/filmic but flattens identity on short ramps · `relative-rotation` identity + rotation. |
| `shift_direction` | Which way hues rotate | `shortest` natural but seams at the antipode · `always-cw`/`ccw` remove that seam. Change only if you see a hue break. |
| `global_temperature` | Warm/cool bias over everything | **Negative** cooler/bluer (winter, tech) · **positive** warmer (sunset, cozy). |
| `temperature_split` | Warm-light vs cool-shadow separation | **High** (0.75) natural realism · **below 0.25 inverts** → cool-light/warm-shadow, the toxic/alien look. |

### Background / atmosphere — depth and readability

| Parameter | What it controls | Push it this way |
|---|---|---|
| `bg_chroma_mult` | Background desaturation vs foreground | **Low** (0.3) → grey recessive backdrops, sprites pop · **near 1** → backgrounds as vivid as foreground (flatter). Lower it if foregrounds don't read. |
| `bg_lightness_offset` | Backgrounds lighter/darker than foreground | **Negative** dark backdrops (dungeon, night) · **positive** light backdrops (fog, snow, sky). |
| `bg_hue_shift` | How far backgrounds pull toward `atmosphere_hue` | **Up** → unified atmospheric wash · **0** → true to base hue. |
| `atmosphere_hue` | The "air colour" distant layers converge toward | 220 misty blue · 30 dusty warm · 200 underwater. |
| `atmosphere_strength` | Aerial-perspective intensity | **Up** → deep, layered, hazy depth · **0** → crisp, flat, no atmosphere. Great for parallax. |
| `fg_bg_separation_min` | Enforced min distance between any fg and any bg colour | **Up** if characters get lost against backdrops · **down** for closer, unified fg/bg. A guarantee, not a look. |

### Neutrals

| Parameter | What it controls | Push it this way |
|---|---|---|
| `neutral_temperature` | Hue tint of the greys | ~230 cool slate/steel (stone, tech) · ~60 warm taupe/sand (wood, parchment). |
| `neutral_chroma` | How tinted the greys are | **0** pure digital grey (can be sterile) · **~0.02** painted, believable greys. |
| `neutral_split` | Emit both cool AND warm neutral families | **On** above ~24 colours where stone and skin want different greys · **off** to save budget. |
| `neutral_l_spread` | Contrast within the neutral ramp | **Wide** bold stone/metal shading · **narrow** flat, quiet UI greys. |

### Accents

| Parameter | What it controls | Push it this way |
|---|---|---|
| `accent_chroma_boost` | How much accents out-saturate everything | **Up** → loud, attention-grabbing UI/FX · **down** → sits closer to the palette. |
| `accent_hue_mode` | Where accent hues are placed | `complementary` reads as alert/danger · `spectral-gap` fills the hue holes (harmonious) · `fixed-offset` set rotation. |
| `accent_l` | Accent lightness | Keep it clear of `l_mid_base` so accents read as a separate layer. **Up** bright glow · **down** deep jewel tones. |

### Hardware / output — console emulation

| Parameter | What it controls | Push it this way |
|---|---|---|
| `bits_r` / `bits_g` / `bits_b` | Per-channel bit depth | **8** modern/unlimited · **5/5/5** SNES · **3/3/3** Genesis · lower = harsher banding. Drop all three together for a period-accurate console palette. |
| `quantize_mode` | How colours snap to the legal hardware grid | `error-weighted` lowest perceptual error (best, esp. at low bit depth) · `round`/`floor` simpler. |
| `gamut_map_mode` | How out-of-sRGB colours come in range | `chroma-reduce` keeps hue+lightness (correct) · `clip` distorts hue (artifact demo only) · `reduce-l-adjust` trades lightness. |

### Quality constraints — guarantees, not looks

| Parameter | What it controls | Push it this way |
|---|---|---|
| `min_delta_e` | Min perceptual gap between any two colours | **Up** → every colour visibly distinct · **down** → allow subtle neighbours for smooth gradients. Best-effort; misses go to `warnings`. |
| `min_anchor_contrast` | WCAG contrast floor between the anchors | **Up** for accessible text/UI. A legibility guarantee. |
| `dither_evenness` | Bias ramp steps toward equal lightness gaps | **Up** for clean dithering into extra shades · **down** for by-eye ramps. |
| `force_unique_hex` | Guarantee K distinct hex values | Leave **on**; off only if you want deliberate duplicates. |

### Meta

| Parameter | What it controls | Push it this way |
|---|---|---|
| `seed` | Master seed for all randomness | Same seed = same palette every time. **Change it to reroll** the random variation while keeping every other setting. This is the only knob behind **Randomize** — it selects a variation, it doesn't add randomness. |

### Reference recolouring — how images are re-rendered into the palette

These live on the **Recolour** tab and don't change any palette colour; they decide how your
reference images are recoloured.

| Parameter | What it controls | Push it this way |
|---|---|---|
| `recolor_mode` | indexed (pixel art) vs quantize (photos) | `indexed` keeps one target colour per source colour (preserves outlines/ramps) · `quantize` decides per pixel and dithers · `auto` by colour count. Force `indexed` if pixel art breaks, `quantize` if a photo posterises. |
| `recolor_indexed_max` | Colour count `auto` switches at | **Up** treats richer images as pixel art · **down** sends more to the photo path. |
| `remap_match` | How source colours map to targets (indexed) | `delta-e` nearest (accurate but jumps when the palette changes) · **`lightness-rank` stable and value-preserving** · `optimal` best assignment, no reuse. Use `lightness-rank` for recolours that hold still as you tune. |
| `remap_preserve_order` | Force the mapping monotonic in lightness | **On** so a wildly different target palette still reads (value structure first). The key knob for recolouring into an unrelated palette. |
| `remap_overflow` | Source has more colours than target | `share` reuse targets (keeps detail) · `merge` cluster source first (cleaner). Try `merge` if `share` looks muddy. |
| `quant_dither` | Dithering in the photo path | `none` bands · `floyd-steinberg` smooth (best stills) · `bayer4`/`bayer8` stable frame-to-frame (best animations — FS "boils"). Pick bayer for GIFs. |
| `quant_dither_strength` | Dither strength | **0** hard bands · **1** smoothest. Lower if too noisy, raise if still banding. |
| `quant_lightness_weight` | Match by lightness vs hue (photo path) | **Above 1** protects value/form, lets hue drift (good when the target lacks the source's hues). Raise when recoloured photos lose depth. |
| `quant_downscale` | Pre-shrink width | **~64–128** for genuine downscaled pixel art from a photo · **0** keep resolution. |
| `gif_frame` | Which frame a *still* export uses | The animation is always recoloured whole; this only picks the frame for the single-image PNG. |

### Recipes — combinations that produce a look

- **Foggy distant background:** high `l_range_compress` (0.4+), high `atmosphere_strength`,
  low `bg_chroma_mult`, `atmosphere_hue` at your air colour, positive `bg_lightness_offset`.
- **Neon / emissive:** `chroma_base` 0.3+, negative `chroma_falloff_light`, wide
  `chroma_curve_width`, `chroma_cap` near 0.37.
- **Painted hue-shifted shading:** `highlight_shift_strength` ~0.35 with a warm
  `highlight_hue_target` (90), `shadow_shift_strength` ~0.35 with a cool `shadow_hue_target`
  (280), `temperature_split` ~0.75.
- **Authentic SNES:** `bits_r/g/b` = 5/5/5, `quantize_mode` error-weighted, `gamut_map_mode`
  chroma-reduce.
- **Muted / historical:** `earthiness` 0.4+, `chroma_base` ~0.1, narrow `chroma_curve_width`.
- **Toxic / alien:** `temperature_split` below 0.25 (cool light, warm shadow), off-natural
  `root_hue` (~90 or ~300).

### Freezing randomness and locking colours

The recolour maths is fully deterministic — it has no randomness of its own. What makes a
reference recolour *appear* to change is the **generated palette moving underneath it** when
you touch a slider. Three ways to stop that:

1. **Recolour into a fixed external palette.** On the Recolour tab, pick a loaded palette
   under **Recolour into** (or drop a palette image via *Add palette…*). An external palette
   does **not** change when you move the sliders — the recolour holds completely still while
   you tune everything else.
2. **Freeze the generated palette's randomness.** All of it lives in three knobs plus the
   seed: set `hue_jitter`, `l_variance_per_hue` and `chroma_variance_per_hue` to **0** and the
   palette becomes a pure, repeatable function of the other parameters — no wobble, no
   surprise shifts. `seed` then only matters for the Randomize button.
3. **Lock individual colours.** Click a swatch's lock in the palette pane to pin its exact
   hex; regeneration and repair never move a locked colour. Use this to hold a few key
   colours steady while the rest of the palette re-tunes.

For recolours that stay stable *even as the generated palette changes*, also set
`remap_match` to `lightness-rank` (or turn on `remap_preserve_order`) — value-based mapping
shifts far less than nearest-colour mapping when the palette moves.

**Randomize never touches the recolour settings.** The Randomize button rerolls the palette's
look but deliberately leaves the whole *Reference Recolouring* group (dither, downscale, remap
mode, …) exactly where you set it — those are output choices, not palette aesthetics. So you
can set your recolour options once and randomize the palette freely.

## Layout

| Path | Purpose |
|---|---|
| `src/core/` | DOM-free colour maths, generation, `raster`/`analysis`/`dither` — imported by both browser and Node |
| `src/core/export/` | Output format writers: gpl, pal, hex, lospec, css, json, tres, png |
| `src/ui/` | Browser app: `app sliders swatches history io randomize gallery picker recolor` |
| `src/scenes/` | The 34 gallery scenes (DOM-free) + `index` registry + `util` role accessors |
| `test/` | `node --test` suite and golden snapshots |
| `tools/` | Dev server, standalone build, headless renderer, PNG codec, drawing surfaces |
| `src/core/recolor/` | Reference-image recolouring: indexed remap, quantize, GIF codec, palette extraction |
| `saved/` | Your saved parameter sets (git-tracked) |
| `reference/` | Your reference images to recolour · `palettes/` your palette images to recolour into |
| `out/`, `dist/` | Rendered PNGs and the standalone build (gitignored) |

No runtime dependencies — Node built-ins and vanilla ES modules only. Nothing under
`src/core/` may import a Node built-in; that constraint is what lets the same code run in
the browser, under `node --test`, and in the headless renderer.
