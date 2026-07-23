# Procedural Pixel-Art Palette Creator

## Context

There is no palette tooling in this repo. Palettes for the Godot projects here (`solatro/`, `necroma/`, `worldgen/`, …) are currently ad-hoc, and there is no way to reproduce or re-tune one after the fact.

This plan builds a self-contained interactive tool at `gamedev/palette/` that:

- generates structurally-sound retro palettes from ~50 tunable parameters in OKLCH space,
- **proves** they work by applying them live to a gallery of 34 test visuals,
- exports to every format the Godot projects and Aseprite need,
- round-trips through a pasteable seed string so any palette can be re-tuned months later,
- and verifies itself with an automated test suite requiring no manual playtesting.

Everything needed to build it is specified below — color theory, algorithms, formulas, and structure.

---

## Build status — this plan is fully implemented

> **All phases in this document are built, tested and gated** (Phases 1–4 plus the two
> follow-ons, 4b colour-space maps and 5 reference recolouring). This file remains the
> **specification**; it is not a to-do list any more. Read it for *what* the tool is and
> *why* each algorithm is the way it is.
>
> For a newcomer picking this up:
> - **[PROGRESS.md](PROGRESS.md)** is the task-by-task record of what shipped, and the place
>   to start. It also lists the **post-plan enhancements** that are not in the §17 task list
>   below (external-palette recolouring, the double-click restart, the lazy recolour gallery,
>   the per-parameter documentation, and the Randomize-excludes-recolour fix).
> - **[ARCHITECTURE.md](ARCHITECTURE.md)** explains how the built code actually works and
>   records the decisions and dead ends behind it (§9 app, §10 gallery, §11 picker, §12
>   recolouring).
> - Two places in this spec were changed after the fact by the repo owner and are marked
>   inline where they occur: **§19.2** (a GIF is recoloured whole and shown animated, not as a
>   single still) and the note beside it. The original text is struck through, not deleted.
>
> If you are adding a *new* feature, follow the existing conventions (§7 stack rules, the
> `Palette` contract in ARCHITECTURE §1, tests written alongside code, no Node built-ins under
> `src/core/`) and record it in PROGRESS.md's post-plan section.

---

# Part I — Design specification

## 1. Why OKLCH

Palettes are generated in **OKLCH** (a cylindrical form of OKLab), not HSL/HSV.

| Axis | Range | Meaning |
|---|---|---|
| `L` | 0.0 – 1.0 | Perceptual lightness — visual weight and contrast |
| `C` | 0.0 – ~0.37 | Chroma — color purity/saturation |
| `h` | 0° – 360° | Hue angle — color identity |

HSL's `L` is not perceptual: HSL yellow and HSL blue at `L=50%` differ enormously in apparent brightness, so a ramp built in HSL has uneven value steps and reads badly in grayscale. OKLab is perceptually uniform, so equal `ΔL` steps *look* equally spaced — which is the entire basis of a readable pixel-art ramp.

Unlike a generic color-wheel generator, this tool enforces constraints that mirror low-color retro hardware and traditional game-art workflow. The rules follow.

## 2. Core color rules

### 2.1 Hue shifting (temperature curves)

Flat ramps that only change lightness look plastic. Real shading shifts hue:

- **Highlights (+L):** hue drifts warm (toward ~90°, sunlight gold), chroma slightly drops to simulate light washout.
- **Shadows (−L):** hue drifts cool (toward ~280°, deep indigo), chroma is maintained or *boosted* to keep shadows rich rather than muddy.

Three shift models are supported, because a single global attractor is insufficient:

| Model | Behavior | Use |
|---|---|---|
| `global-attractor` | Every hue interpolates toward one fixed target angle | Strong cohesion; the classic look |
| `relative-rotation` | Every hue rotates by a fixed **signed** amount | Preserves hue identity across long ramps |
| `per-family` | Warm / yellow / green / cyan-blue / violet / magenta families each use their own light & shadow targets | Closest to how painters actually work |

A global attractor is the most cohesive but has a real failure mode: at 4–5 step ramps every hue's highlight converges to the same yellow, erasing hue identity. `relative-rotation` exists specifically to fix that. Additionally, shortest-path hue interpolation is **discontinuous at the antipode** — a base hue of 279° and one of 281° shift in opposite directions when the target is 280°. The `shift_direction` parameter (`shortest` / `always-CW` / `always-CCW`) removes that discontinuity when it matters.

### 2.2 Palette compression and universal anchors

Pure black and white are never used. Instead:

- **Universal Dark Anchor** — deep indigo, `L ≈ 0.12`. Serves as shared shadow for all hues, outline color, and dark background void.
- **Universal Light Anchor** — warm cream, `L ≈ 0.95`. Serves as shared extreme highlight for all hues and bright particle FX.

At small budgets, secondary hues *compress* their ramps by routing through these shared anchors instead of owning private extremes. This is what makes a 12-color palette feel cohesive rather than like twelve unrelated colors.

Compression has a cost the generator must guard against: when several hues route into the same anchor, adjacent slots can collapse into near-duplicates, wasting budget. See §2.5.

### 2.3 Context separation

- **Foreground** (player, enemies, interactive objects): high chroma, high internal contrast.
- **Background** (terrain, parallax, scenery): chroma multiplied by `bg_chroma_mult` (default 0.4), lightness offset, hue pulled toward an atmospheric color.

This is the primary mechanism for foreground readability, and it is enforced as a **hard constraint** (`fg_bg_separation_min`), not left to chance — the generator repairs any fg/bg pair that falls below the minimum perceptual distance.

### 2.4 Gamut mapping — do not clip channels

Most of the OKLCH cylinder is outside sRGB. `L=0.6, C=0.25, h=140` is not a displayable color. The naive fix — convert to linear sRGB and clamp each channel to [0,1] independently — is **wrong** and must not be used: clamping R, G, and B separately moves the color to a different hue *and* a different lightness in an unpredictable direction. The emitted color then no longer matches the computed one, which silently invalidates every hue-shift and lightness invariant the generator is built on.

The correct approach (CSS Color 4 gamut mapping): hold `L` and `h` fixed and binary-search `C` downward until the color is displayable.

```
gamut_map(L, C, h):
    if L >= 1.0: return WHITE
    if L <= 0.0: return BLACK
    if in_srgb(L, C, h): return to_srgb(L, C, h)

    lo, hi = 0, C
    while hi - lo > 1e-4:
        mid = (lo + hi) / 2
        if in_srgb(L, mid, h):
            lo = mid
        else:
            clipped = clip(to_linear_srgb(L, mid, h))
            if deltaEOK(clipped, oklch(L, mid, h)) < 0.02:
                return clipped          # close enough, accept
            hi = mid
    return clip(to_linear_srgb(L, lo, h))
```

The result preserves hue and lightness, sacrificing only saturation — exactly the tradeoff an artist would make.

### 2.5 Perceptual distance and the repair pass

Perceptual difference is measured as Euclidean distance in **OKLab**, reported ×100 for readable numbers:

```
ΔE_OK = 100 · √( (ΔL)² + (Δa)² + (Δb)² )
```

After allocation, a repair pass enforces `min_delta_e` between **every pair** in the palette. Any violating pair is separated by nudging the lower-priority slot's `L` (and `C` if `L` is pinned), then re-gamut-mapped and re-checked, iterating to a fixed point. Without this, compressed palettes waste slots on colors that are visually identical.

> **As built, this is not what `repair.js` does.** Pairwise nudging does not converge —
> a slot squeezed between two neighbours is pushed off one and immediately pushed back
> by the other. The implementation scores candidate positions against the whole palette
> and accepts only strict improvements, which provably terminates. See
> [ARCHITECTURE.md](ARCHITECTURE.md) §3.2 before changing it back.

### 2.6 Hardware bit-depth constraints

Default output is free 24-bit (8/8/8). Independent per-channel bit-depth sliders (`bits_r`, `bits_g`, `bits_b`, each 1–8) reproduce older hardware: 5/5/5 ≈ SNES, 3/3/3 ≈ Genesis, 2/2/2 ≈ EGA-ish, and asymmetric setups like **4/2/3** are expressible.

```
levels = 2^bits
quantize(v) = round(v/255 · (levels-1)) / (levels-1) · 255
```

`quantize_mode = error-weighted` instead evaluates the two nearest legal values per channel (8 combinations) and picks the one minimizing `ΔE_OK` to the ideal color — noticeably better than rounding at low bit depths.

**Ordering matters:** quantization runs *after* gamut mapping, and the repair pass (§2.5) **re-runs afterward**, because quantization can collapse two distinct colors onto the same legal grid point.

### 2.7 Pipeline order

```
parameters + seed
  → hue set (scheme, spacing, jitter)
  → budget allocation (tiers)
  → per-slot OKLCH (lightness curve, chroma curve, hue shift)
  → gamut map           (§2.4)
  → bit-depth quantize  (§2.6)
  → repair / dedupe     (§2.5)
  → apply locks & manual overrides
  → stable role ordering
  → Palette
```

Locks and overrides are applied late and are exempt from repair — an explicitly chosen color is never silently moved.

---

## 3. Budget-driven allocation model

The palette must contain **exactly K colors** for any `K` in 4–64. In pixel art no color exists without a job, so allocation is by priority, and **leftover budget deepens the existing structure rather than emitting filler**.

This is the critical design decision. A hue-count-driven allocator that runs out of tiers and pads the remainder with high-chroma singletons produces garbage: request 32 colors with 3 hues that way and you get 20 structured colors plus 12 unrelated neons. Instead, hue count is *derived from* the budget, and every tier is **re-entrant** — extra budget lengthens ramps, splits neutrals, and extends background ramps.

### 3.1 Derived hue count

`hue_count` is auto-derived from K (and manually overridable):

| K | hues |
|---|---|
| 4–7 | 1 |
| 8–11 | 2 |
| 12–15 | 3 |
| 16–23 | 4 |
| 24–39 | 5 |
| 40–55 | 6 |
| 56–64 | 8 |

### 3.2 Allocation rounds

Two slots go to the universal anchors first (§2.2). The remaining budget `R = K − 2` is claimed by these rounds in order. Each round is **partially fillable** — if budget runs out mid-round, slots are claimed in hue-priority order (hue 1 first), so the count is always exact.

| # | Round | Slots |
|---|---|---|
| 1 | Foreground midtones | `hue_count` |
| 2 | Foreground shadows | `hue_count` |
| 3 | Foreground highlights | `hue_count` |
| 4 | Core neutrals (mid, dark, light) | up to `neutral_count` |
| 5 | Background midtones | `hue_count` |
| 6 | Background shadows | `hue_count` |
| 7 | Foreground deep shadows (ramp → 4) | `hue_count` |
| 8 | Foreground bright highlights (ramp → 5) | `hue_count` |
| 9 | UI/FX accents | `accent_count` |
| 10 | Warm neutral split | up to `neutral_count` |
| 11 | Background ramp extension | `hue_count` |
| 12 | Bridge midtones between adjacent ramps | remainder |

### 3.3 Worked budgets

```
K=4   →  2 anchors + 1 fg mid + 1 fg shadow                                = 4
K=8   →  2 anchors + 2 mid + 2 shadow + 2 highlight                        = 8
K=12  →  2 anchors + 3 mid + 3 shadow + 3 highlight + 1 neutral            = 12
K=16  →  2 anchors + 4 mid + 4 shadow + 4 highlight + 2 neutral            = 16
K=32  →  2 anchors + 5 mid + 5 shadow + 5 highlight + 3 neutral
         + 5 bg mid + 5 bg shadow + 2 accent                               = 32
K=64  →  2 anchors + 8 hues × 5-step fg (40) + 8 hues × 2-step bg (16)
         + 6 neutrals (cool + warm split)                                  = 64
```

At `K=12` every slot does multiple duties through shared anchors — zero duplicate shadows, zero isolated hue silos. At `K=32` foreground, background, and UI layers are fully separated. At `K=64` ramps are long enough for metal and skin, and neutrals split warm/cool.

### 3.4 Stable slot ordering

Slots are ordered deterministically by role, never by generation order. Nudging a slider must not reorder exported indices — otherwise re-importing the palette into Aseprite reshuffles finished artwork.

### 3.5 Semantic roles

On top of structural slots (`fg_hue_2_mid`) sits a semantic layer: `foliage`, `skin`, `stone`, `metal`, `wood`, `water`, `fire`, `blood`, `gold`, `sky`, `ui_good`, `ui_bad`, `ui_neutral`. These are auto-assigned by hue proximity and reassignable from a dropdown.

This is what makes the test gallery meaningful: the tree in a scene renders in whatever slot is assigned `foliage`, so you immediately see whether your greens work. Exports carry both names.

---

## 4. Formula reference

**Hue angle distance** (signed, shortest path):

```
Δh = ((h_target − h_current + 540) mod 360) − 180
```

**Hue interpolation** (weight `w` ∈ [0,1]):

```
h_new = (h_current + w · Δh) mod 360
```

**Relative rotation** (identity-preserving alternative, `σ` = fixed sign, `s` = degrees):

```
h_new = (h_current + σ · s) mod 360
```

**Lightness ramp** — `n` steps, index `i`, `t = i/(n−1)`, easing `f`:

```
linear      f(t) = t
ease-dark   f(t) = t²
ease-light  f(t) = 1 − (1−t)²
S-curve     f(t) = t²(3 − 2t)

L_i = L_lo + f(t) · (L_hi − L_lo)
```

where `L_lo` / `L_hi` extend from `l_mid_base` by `l_step` per step, clamped inside the anchors.

**Chroma curve** — Gaussian peak plus directional falloff:

```
G(L) = exp( −(L − chroma_peak_l)² / (2 · chroma_curve_width²) )
C    = chroma_base · G(L)
       − chroma_falloff_light · max(0, L − L_mid) / l_step
       − chroma_falloff_dark  · max(0, L_mid − L) / l_step
C    = clamp(C, 0, chroma_cap)
```

Negative `chroma_falloff_dark` **boosts** shadow chroma. The Gaussian peak matters: real pigments are most saturated in the upper-mid lightness range, so a flat chroma value makes highlights look chalky and shadows look dead.

**Default shift constants** (all overridable):

```
highlight:  L += 0.22   C −= 0.03   w = 0.25   target 90°
shadow:     L −= 0.28   C += 0.02   w = 0.35   target 280°
```

Shadow lightness is floored at `l_dark_anchor + min_delta_e_margin`, **not** at the anchor value itself — flooring exactly at the anchor makes shadows of dark base colors collapse into duplicates of `universal_dark`.

**WCAG contrast ratio** (relative luminance from linear sRGB):

```
Y = 0.2126·R_lin + 0.7152·G_lin + 0.0722·B_lin
ratio = (Y_light + 0.05) / (Y_dark + 0.05)
```

**OKLab → linear sRGB** (standard Björn Ottosson matrices):

```
l' = L + 0.3963377774·a + 0.2158037573·b
m' = L − 0.1055613458·a − 0.0638541728·b
s' = L − 0.0894841775·a − 1.2914855480·b
l, m, s = l'³, m'³, s'³

R = +4.0767416621·l − 3.3077115913·m + 0.2309699292·s
G = −1.2684380046·l + 2.6097574011·m − 0.3413193965·s
B = −0.0041960863·l − 0.7034186147·m + 1.7076147010·s
```

followed by the sRGB transfer function — and **gamut mapping per §2.4, never bare clamping**.

---

## 5. Complete parameter list

Every parameter gets a slider (or dropdown/toggle), is encoded in the seed string, and is covered by the randomizer.

### Structure

| Parameter | Range | Why it matters |
|---|---|---|
| `color_count` K | 4–64 | Total budget. 4 = Game Boy, 16 = CGA/Arne, 32 = Endesga, 64 = AAP-64. |
| `hue_count` | auto / 1–8 | How many distinct color identities. Too many at low K yields mud; too few yields monotony. |
| `hue_scheme` | even / analogous / complementary / split-comp / triadic / tetradic / custom | The single biggest driver of palette *mood*. Even reads generic; analogous reads cohesive; complementary reads punchy. |
| `root_hue` | 0–360° | Rotates the whole palette. The main "what color is this world" knob. |
| `hue_span` | 0–360° | Width of the analogous arc. Narrow = strongly themed (all-swamp, all-desert). |
| `hue_jitter` | 0–30° | Breaks mathematical regularity; makes palettes feel hand-picked rather than computed. |
| `perceptual_hue_spacing` | 0–1 | Blends math-even spacing toward perceptually-even. OKLCH hue is *not* perceptually uniform — yellow occupies a narrow band while green sprawls, so even spacing at 0 can yield three near-identical greens. |
| `fg_ramp_length` | 2–5 | Steps per foreground ramp. 3 is the pixel-art minimum; 5 is needed for metal and skin. |
| `bg_ramp_length` | 1–3 | Background ramps are shorter — depth needs less internal detail. |
| `neutral_count` | 0–6 | Stone/metal/UI-border slots. |
| `accent_count` | 0–4 | High-chroma UI/FX pops. |
| `tier_priority` | ordering | Which round claims budget first when K is tight. |

### Lightness

| Parameter | Range | Why it matters |
|---|---|---|
| `l_dark_anchor` | 0.02–0.30 | The universal dark. Too high and outlines go mushy; too low and shadow detail disappears. |
| `l_light_anchor` | 0.80–1.00 | The universal light; the palette's brightness ceiling. |
| `l_mid_base` | 0.30–0.92 *(max raised from 0.80, 2026-07-23)* | Where foreground midtones sit — the **darkness/brightness** master knob. The old 0.80 ceiling made high-key palettes impossible and blocked centring a ramp on the gamut cusp for the whole yellow→cyan arc (cusps at L 0.86–0.96). See COLOR_GUIDE.md. |
| `l_step` | 0.05–0.40 | Lightness delta per ramp step. This *is* **contrast**: small = soft/painterly, large = punchy and readable at 1×. |
| `l_curve` | ease-dark / linear / ease-light / S-curve | Where steps cluster. Clustering in shadow gives rich darks; S-curve maximizes midtone separation. |
| `l_range_compress` | 0–1 | Squeezes the palette toward mid-gray. High = foggy/washed/dreamlike. |
| `l_variance_per_hue` | 0–0.30 *(max raised from 0.15, 2026-07-23)* | Lets hues sit at different lightnesses, at random — real palettes don't put yellow and blue at the same L. Fitting real reference palettes pinned this at the old 0.15 ceiling, i.e. it allowed less spread than hand-made palettes actually use. (The *principled* version of this is `hue_lightness_follow`.) |
| `hue_lightness_follow` *(added post-plan, 2026-07-23)* | 0–1 | The **principled** form of the line above: biases each hue's midtone toward the lightness where that hue's chroma actually peaks in sRGB (its gamut cusp), so yellow/green/cyan ride up into the saturated zone instead of turning olive at a shared mid grey, while blue/red barely move. Default 0.5. Most presets pin it to 0 to preserve their originally-tuned look; the default palette, OKLAB Crayon, Neon Cyberpunk, Toxic Swamp and Sunset Desert use it. See ARCHITECTURE §3.8 and COLOR_GUIDE.md. |

### Chroma / saturation

| Parameter | Range | Why it matters |
|---|---|---|
| `chroma_base` | 0.00–0.37 | Master **saturation**. 0 = grayscale, 0.30+ = neon. |
| `chroma_peak_l` | 0.30–0.90 | Lightness at which chroma peaks (§4). Prevents chalky highlights and dead shadows. |
| `chroma_curve_width` | 0.1–1.0 | How sharply chroma falls off away from the peak. |
| `chroma_falloff_light` | −0.10–0.20 | Highlight washout. Positive = sun-bleached; negative = hot/neon/emissive. |
| `chroma_falloff_dark` | −0.10–0.20 | Negative **boosts** shadow chroma — what makes shadows rich rather than muddy. |
| `chroma_variance_per_hue` | 0–0.15 | Some hue families more saturated than others; avoids the flat "everything at C=0.18" look. |
| `earthiness` | 0–1 | Chroma reduction *plus* a hue pull toward ochre/umber (40–70°). Distinct from simply lowering saturation, which yields dead gray instead of earth tones. |
| `chroma_cap` | 0.05–0.37 | Ceiling before gamut mapping; keeps colors reachable in sRGB. |

### Hue shifting / temperature

| Parameter | Range | Why it matters |
|---|---|---|
| `highlight_hue_target` | 0–360° (def 90) | Where lights drift. 90° = sunlight; 200° = moonlight; 330° = magic/alien. |
| `highlight_shift_strength` | 0–1 (def 0.25) | *The* signature parameter of hue-shifted pixel art. |
| `shadow_hue_target` | 0–360° (def 280) | Where darks drift. 280° = classic cool indigo; 20° = warm firelit interiors. |
| `shadow_shift_strength` | 0–1 (def 0.35) | How hard shadows drift. |
| `shift_model` | global-attractor / relative-rotation / per-family | See §2.1. |
| `shift_direction` | shortest / always-CW / always-CCW | Removes the antipode discontinuity (§2.1). |
| `global_temperature` | −1–1 | Warm/cool bias on everything. |
| `temperature_split` | 0–1 | Warm-light/cool-shadow separation strength. **Inverting it** (cool lights, warm shadows) is exactly what makes toxic/alien/underwater palettes read as deliberately *wrong*. |

### Background / atmosphere

| Parameter | Range | Why it matters |
|---|---|---|
| `bg_chroma_mult` | 0.1–1.0 (def 0.4) | Background desaturation — the primary tool for foreground readability. |
| `bg_lightness_offset` | −0.3–0.3 | Pushes backgrounds darker (dungeon) or lighter (fog/snow). |
| `bg_hue_shift` | 0–1 | Pull toward the atmospheric hue with distance. |
| `atmosphere_hue` | 0–360° | The fog / aerial-perspective color distant layers converge toward. |
| `atmosphere_strength` | 0–1 | Aerial perspective intensity. |
| `fg_bg_separation_min` | 0–1 | Enforced minimum ΔE between any fg and any bg color — makes "does the player pop?" a constraint, not a hope. |

### Neutrals

| Parameter | Range | Why it matters |
|---|---|---|
| `neutral_temperature` | 0–360° (def 230) | Cool slate ↔ warm taupe. Governs stone, metal, skin bases, UI chrome. |
| `neutral_chroma` | 0.00–0.06 | 0 = pure gray (reads digital/sterile); slightly tinted neutrals are what make a palette feel painted. |
| `neutral_split` | bool | Emit both cool and warm neutral families. Essential above ~24 colors — stone and skin want different neutrals. |
| `neutral_l_spread` | 0.1–0.5 | Contrast within the neutral ramp. |

### Accents

| Parameter | Range | Why it matters |
|---|---|---|
| `accent_chroma_boost` | 0–0.15 | How much accents out-saturate everything else; drives UI/FX pop. |
| `accent_hue_mode` | complementary / spectral-gap / fixed-offset | Complementary accents read as alerts; spectral-gap accents fill the hue holes the primaries left. |
| `accent_l` | 0.4–0.9 | Accent lightness. |

### Hardware / output

| Parameter | Range | Why it matters |
|---|---|---|
| `bits_r` / `bits_g` / `bits_b` | 1–8 each (def 8/8/8) | Independent per-channel depth. 5/5/5 ≈ SNES, 3/3/3 ≈ Genesis, and asymmetric like 4/2/3 is expressible (§2.6). |
| `quantize_mode` | round / floor / error-weighted | Error-weighted picks the legal value with lowest ΔE_OK from the ideal — clearly better at low bit depth. |
| `gamut_map_mode` | chroma-reduce / clip / reduce+L-adjust | Chroma-reduce is the correct default; `clip` exists only to demonstrate the artifact. |

### Quality constraints

| Parameter | Range | Why it matters |
|---|---|---|
| `min_delta_e` | 0–15 | Minimum perceptual distance between any two colors; prevents wasted near-duplicate slots. |
| `min_anchor_contrast` | 1–21 | WCAG contrast floor between anchors — guarantees text legibility. |
| `dither_evenness` | 0–1 | Biases ramp steps toward uniform ΔL so adjacent pairs checkerboard into convincing intermediates. |
| `force_unique_hex` | bool | Hard guarantee of K distinct hex values. |

### Meta

| Parameter | Notes |
|---|---|
| `seed` | Integer feeding a deterministic PRNG (xorshift128 — **not** `Math.random`) for jitter and randomization. |
| `locks[]` | Per-slot lock flags; survive re-randomize. |
| `overrides{}` | Per-slot manual hex; applied last, exempt from repair. |
| `role_assignments{}` | Semantic name → slot mapping. |

---

## 6. Seed string

Format `PAL1-<base64url payload>`, ~140 characters, versioned:

```
[ver:u8][paramCount:u8][params: u16 quantized, fixed field order]
[lockCount:u8][ (slotIndex:u8, rgb:u24) × n ]
[overrideCount:u8][ (slotIndex:u8, rgb:u24) × n ]
```

Encoding the **full parameter set** rather than just an RNG seed is deliberate: a bare RNG seed produces a different palette the moment the algorithm changes, which defeats the purpose of re-tuning later. Old decoders are retained when `PAL2` is introduced, so a seed pasted a year from now still resolves.

The seed also lives in the URL hash (bookmarkable) and inside every `saved/*.json` and JSON export.

---

# Part II — Implementation

## 7. Stack and layout

**Local HTML app**, vanilla ES modules, `<canvas>` rendering, zero runtime dependencies.

The decisive property: **all color math and generation lives in DOM-free modules under `src/core/`**, importable by both browser and Node. `node --test` therefore exercises the real generator, and `tools/render.mjs` renders every test visual to PNG headlessly (Node's built-in `zlib` backs a minimal PNG encoder) so correctness is verifiable without manual playtesting.

Godot was rejected for the authoring tool: headless Godot rendering is unreliable on the author's machine, which would defeat the self-verification requirement. Godot is still an *export target* (§10).

A dependency-free Node static server (`npm start`) hosts the app and provides the save/load endpoint for `palette/saved/`. `npm run build` inlines everything into one double-clickable `dist/palette_creator.html` (seed strings work there; file-backed saves do not).

```
palette/
  package.json            # no deps; scripts: start, test, build, render
  README.md
  index.html
  src/
    core/                 # DOM-free, Node-importable
      oklch.js            # OKLCH <-> OKLab <-> linear sRGB <-> sRGB, deltaEOK
      gamut.js            # CSS Color 4 chroma-reduction gamut mapping (§2.4)
      quantize.js         # per-channel bit-depth reduction (§2.6)
      hues.js             # hue schemes, perceptual spacing, circular interpolation
      ramp.js             # ramp construction, shift models, chroma/lightness curves
      allocate.js         # budget-driven round allocator, K = 4..64 (§3)
      repair.js           # min-deltaE dedupe/nudge pass (§2.5)
      roles.js            # stable slot ordering + semantic role assignment (§3.4-3.5)
      params.js           # parameter schema: name, range, default, group, doc (§5)
      seed.js             # PAL1 encode/decode (§6)
      generate.js         # pure function: params -> Palette (§2.7)
      analysis.js         # contrast, colorblind sim (Vienot), value view, ramp metrics
      dither.js           # Floyd-Steinberg, Bayer 4x4/8x8
      layout/             # artist's-palette picker (§9)
        som.js  anneal.js  hilbert.js  mds.js  voronoi.js  grow.js  score.js
      presets.js          # parameter-set presets (§11)
      reference.js        # embedded real palettes, read-only, for comparison
      export/
        gpl.js  pal.js  hex.js  png.js  json.js  css.js  tres.js  lospec.js
    scenes/
      index.js            # registry: id, title, category, render(ctx, palette)
      *.js                # 34 scenes (§8)
    ui/
      app.js  sliders.js  swatches.js  gallery.js  picker.js  history.js  io.js
    style.css
  test/
    *.test.js             # node --test
    snapshots/            # golden hex outputs for determinism
  tools/
    render.mjs            # headless: every scene -> PNG for inspection
    png.mjs               # minimal PNG encoder (node:zlib)
    serve.mjs             # static server + /api/saves
  saved/                  # user parameter sets (git-tracked JSON)
  out/                    # rendered PNGs (gitignored)
  dist/                   # standalone single-file build (gitignored)
```

Code style: no unused code — delete it rather than leaving it — and a short JSDoc purpose comment on every exported function.

> **The tree above is the plan, not an inventory.** Phase 1 added three files it does
> not list — `src/core/rng.js`, `src/core/pixelfont.js` and `tools/surface.mjs` — each
> for a reason recorded in [ARCHITECTURE.md](ARCHITECTURE.md) §2. They are not strays.

## 8. Test visual gallery

Scrollable, filterable by category, rendered live from the current palette. Every scene has a grayscale value-only toggle and protan/deutan/tritan colorblind toggles.

**Palette structure**
1. Swatch grid — role name, hex, OKLCH readout, lock/override affordances
2. Ramp strips — stacked and aligned so ΔL evenness is directly comparable
3. Grayscale value-only view — the single most important pixel-art check
4. OKLCH scatter plots — L×C plane and polar hue wheel; exposes clustering and gaps
5. ΔE adjacency heatmap — all pairs, numeric; finds near-duplicates instantly
6. Colorblind simulation board (Viénot dichromat matrices)

**Form and shading**
7. Lit sphere per ramp — the classic volume test
8. Isometric cube — 3 faces from one ramp; proves the ramp gives form
9. Cylinder / bevel study — soft-curvature falloff
10. Material studies — gold, silver, bronze, wood, stone, cloth, glass, water; each needs a differently-shaped ramp (metal needs a hard specular jump)

**Sprites**
11. 16×16 character sprite
12. 32×32 character sprite
13. Outline modes — none / universal-dark / colored / selective
14. **Sprite over every background color** — same sprite tiled against each palette color; the definitive readability test
15. Palette-swap row — same sprite through every foreground ramp; proves all ramps are equally usable
16. Item icon row — sword, potion, coin, key, gem; small-scale readability
17. Busy combat scene — enemy vs player vs pickup; does the player pop?
18. Skin-tone study — a face at several flesh variants; exposes palettes that can't do believable skin
19. Foliage study — trees and grass; greens are the hardest thing to get right

**Scenes**
20. Parallax landscape — 3 depth layers plus atmospheric haze
21. Dungeon interior — warm torchlight against cool ambient shadow
22. Day / dusk / night sweep of one scene — tests support for lighting states
23. Tileset sheet — grass/dirt/stone/water 16×16, tiled 4×4 to check seams and pattern noise
24. Full fake game screenshot — everything at once

**UI**
25. UI mockup — health/mana bars, buttons (normal/hover/pressed/disabled), panels, tooltip, inventory grid, minimap
26. Text legibility matrix — pixel font in every color on every background, with WCAG pass/fail overlay

**Dithering and gradients**
27. Dither pair matrix — every adjacent ramp pair checkerboarded
28. Bayer gradient ramps — 4×4 and 8×8 ordered dithering between ramp steps
29. Sky gradient with ordered dithering — the classic hardest gradient
30. 1px noise/checkerboard — behavior at maximum spatial frequency
31. Zoom comparison — 1× / 2× / 4×, confirms it holds up scaled

**Motion**
32. Animated — palette-cycled water, torch flicker, day-night sweep; catches ramps that band or strobe only in motion

**Benchmarking**
33. Photo quantization — drag-and-drop any image (including your own game art) re-rendered in the palette with Floyd-Steinberg and Bayer dithering. Ships with 3 procedurally-generated references (lit sphere study, flesh gradient field, hazy landscape) so it works with nothing added to the repo. The harshest test available — exposes gaps no hand-made sprite will.
34. Side-by-side reference compare — same scene in your palette vs DB16/DB32, Endesga 32, PICO-8, Sweetie 16, NES, Game Boy DMG, C64, Resurrect 64, Apollo, Vinik24, with a numeric ΔE fit score

## 9. Artist's-palette color picker

The picker has **two families**, which solve the problem in opposite ways. §9.1 is the
default view and the one that looks like a color picker; §9.2 is the optimizer.

### 9.1 Color-space maps — the default view

A standard color-picker geometry where **every pixel is painted with the nearest palette
color** to the color that position represents. Nothing is arranged and nothing is
optimized: position means exactly what it means in any other picker, so you always know
where to look.

Geometry is HSL, because that is what "white on one side, black on the other, hues through
the middle" describes:

- **Rectangular** — x = hue (0–360, so the left and right edges are the same hue and the
  map wraps), y = lightness (white at the top edge, black at the bottom), saturation fixed
  per slice.
- **Polar** — angle = hue (wrapping is free), radius = lightness, saturation fixed per
  slice. A round painter's wheel.
- Several **saturation slices** shown together, as a palette's colors do not all live at
  one saturation.

Rendered per output pixel, so boundaries are exact and smooth at any resolution — there is
no cell grid, no upsampling and no smoothing pass. **No outlines are drawn**, ever: regions
meet directly and are read by color contrast alone.

**The honest cost:** a color only appears where it is the nearest one, so a palette color
whose neighbors crowd it out can occupy a sliver or be absent from a given slice entirely.
Full coverage is *not* guaranteed and must not be faked. Each map reports how many palette
colors it shows (e.g. `45/48`), and the union across slices is reported too.

### 9.2 Arrangement layouts — the optimizer

A separate generator solving a different problem: *it is hard to find the color you want when it is surrounded by colors significantly different from it.* Arranging the palette so neighbors are perceptually close is a **spatial optimization**, not color generation. Colors may repeat, and blobs vary in size.

Unlike §9.1 these **guarantee every color appears** with a controllable area, but a color's
position is not predictable — it moves when the palette changes. That is the trade: §9.1 is
predictable but may hide a color; §9.2 shows everything but must be re-read each time.

**Objective:** minimize mean `ΔE_OK` between spatially adjacent cells. Every variant reports that score plus a worst-neighbor score, so variants are **ranked objectively** instead of eyeballed.

**Blob sizing:** tunable, defaulting to *perceptual isolation* — a color's area grows with its mean ΔE to its nearest palette neighbors, so the colors hardest to hunt for get the biggest targets. Alternate modes: equal-area, ∝ role importance, ∝ usage frequency across the test scenes, ∝ chroma.

**Variants** — all high-resolution exportable, all interactive in-app (hover reads out role and hex, click copies):

1. Kohonen SOM, rectangular grid — smooth continuous color field snapped to nearest palette entry
2. Kohonen SOM, **toroidal** — wrapped edges, no boundary distortion
3. Kohonen SOM, hexagonal grid
4. Kohonen SOM, circular disc — a round painter's palette
5. Simulated-annealing swap grid — direct minimization of Σ neighbor ΔE from a heuristic start
6. Hilbert-curve sort — OKLab → 3D Hilbert index → boustrophedon fill; strong locality, fully deterministic
7. MDS/PCA projection + Voronoi blobs — 3D OKLab reduced to 2D
8. Lloyd-relaxed Voronoi — rounder, more even blobs
9. Organic region growth — ΔE-weighted flood fill from seeds; irregular painterly splotches, closest to a physical palette
10. Polar hue wheel — hue = angle, lightness = radius, chroma = ring band
11. Ramp-rows — one ramp per row, hue-ordered; the "organized" **baseline** the optimized layouts must beat
12. Value-sorted spiral
13. Squarified treemap — area by hue-family slot count
14. Sphere unwrap — OKLab projected to a sphere, equal-area (Lambert) unwrapped
15. Delaunay mesh with barycentric blending, snapped to palette

A contact sheet renders all variants together with their scores for at-a-glance comparison.

## 10. Exports

Single-button downloads; picker layouts and PNG strip also export from their own panels.

- **Godot `.tres`** — Resource with named color roles, droppable into `solatro/`, `necroma/`, etc.
- **PNG strip** — 1px per color; the universal drag-into-anything format
- **PNG picker layouts** — high-resolution, per variant plus contact sheet
- **GIMP `.gpl`** — read natively by Aseprite
- **JASC `.pal`**, plain **`.hex`**
- **JSON** — role → hex, full OKLCH values, complete parameter set, and seed; round-trips back into the tool
- **CSS custom properties**
- **Lospec-compatible** plain hex list

Ordering is stable and role-keyed (§3.4), so re-exporting after a tweak never reshuffles indices in finished artwork.

## 11. Presets

Presets are **full parameter sets**, so every slider stays live and meaningful when one is loaded.

- *Emulation-flavored:* NES-ish, Game Boy DMG, CGA, EGA, C64, Genesis, SNES, PICO-8-ish — each pairing a parameter set with matching per-channel bit depths
- *Mood:* Sunset Desert, Frozen Tundra, Toxic Swamp, Neon Cyberpunk, Autumn Forest, Underwater Cave, Blood Moon Horror, Pastel Cozy, Monochrome Ink, Sepia Western, Candlelit Dungeon, Overcast Coast

Separately, **real reference palettes are embedded read-only** (DB16, DB32, Endesga 32, PICO-8, Sweetie 16, NES, Game Boy DMG, C64, Resurrect 64, Apollo, Vinik24) purely as comparison targets with a ΔE fit score. That score doubles as an automated regression metric.

## 12. Editing workflow

- **Lock** any swatch — it survives re-randomize, so a color you love is never destroyed by hitting random.
- **Override** any swatch to an exact hex or OKLCH; overrides are exempt from the repair pass.
- Locks and overrides are baked into the seed string, so the palette still round-trips.
- Undo/redo plus a 20-deep history strip of recent palettes; click any entry to restore.
- Saves are real `.json` files in `palette/saved/` written through the dev server — git-tracked, survive browser clears, inspectable from tests. The dropdown reads the folder live.

## 13. Automated tests

`node --test` against the real `src/core/` modules — no browser, no manual playtesting.

**Color math**
- OKLCH → sRGB → OKLCH round-trips within tolerance across a dense sample grid
- Known-value checks against published OKLab reference conversions
- Every emitted color is in-gamut, and **gamut-mapped output preserves hue and lightness within tolerance** — the test that naive channel clamping fails (§2.4)
- Bit-depth quantization output always lands on the legal grid, for all R/G/B bit combinations

**Generator invariants**
- Exact count: exactly K colors for every K in 4–64, across all hue schemes and hue counts
- `universal_light` has the highest L; `universal_dark` the lowest
- Highlight hue is closer to the highlight target than the midtone hue is (per shift model)
- Ramps are monotonic in L
- All pairs satisfy `min_delta_e`; all hex values unique when `force_unique_hex`
- Anchor contrast ≥ `min_anchor_contrast`
- fg/bg separation ≥ `fg_bg_separation_min`
- All output matches `#RRGGBB`

**Determinism**
- Same params + seed → byte-identical output across processes
- Golden snapshots in `test/snapshots/` for every preset; any algorithm change surfaces as a diff
- Seed round-trip: `decode(encode(p)) === p` over randomized parameter sets, including locks and overrides
- Old `PAL1` seeds still decode after schema additions

**Fuzz**
- 10,000 randomized parameter sets: no NaN, no crash, no out-of-gamut color, exact count, all invariants hold

**Exports**
- Every format parses back to the same colors (GPL / PAL / HEX / JSON round-trip)
- Emitted `.tres` is valid Godot resource syntax
- PNG strip decodes to exactly K pixels of the right colors

**Layout**
- Every picker variant covers its canvas with no holes and no unassigned cells
- Optimized layouts score strictly better on mean neighbor ΔE than the `ramp-rows` baseline
- Annealing is deterministic under a fixed seed

**Visual verification**
`npm run render` writes every scene and picker variant to `out/*.png` at several palette sizes, which I read and inspect directly. `npm start` plus the browser tool drives the live UI for interaction checks.

## 14. Phases

Each phase ends runnable and verifiable.

**Phase 1 — Core.** All of `src/core/`: color math, gamut mapping, quantization, hue schemes, ramps, allocator, repair, roles, param schema, seed codec, presets, reference palettes, exports. Plus `tools/png.mjs` and `tools/render.mjs`.
*Gate:* `node --test` green; PNG strips for every preset rendered to `out/` and visually inspected.

**Phase 2 — App.** `index.html`, all sliders wired live, swatch grid with lock/override, undo/redo and history, randomize respecting locks, preset dropdown, seed field with URL-hash sync, save/load against `palette/saved/`, all export buttons, dev server.
*Gate:* `npm start`, drive the real UI in the browser, confirm every slider moves output and every export downloads correctly.

**Phase 3 — Gallery.** All 34 test visuals, scrollable and filterable, with value-only / colorblind / zoom toggles, animation, drag-and-drop photo quantization, and side-by-side reference compare.
*Gate:* every scene rendered headlessly to `out/` and inspected; visually confirmed in-app.

**Phase 4 — Picker.** All 15 layout variants, scoring, blob-sizing modes, contact sheet, interactive hover/click, high-res export.
*Gate:* scoring tests pass; contact sheet rendered and inspected; ranked results reported back to you.

**Phase 4b — Color-space maps (§9.1).** The rectangular and polar HSL maps, saturation
slices, per-pixel rendering, no outlines, coverage reporting. This becomes the picker's
default view; the §9.2 arrangement layouts stay as alternates.
*Gate:* maps rendered and inspected against the reference look; coverage figures reported.

**Phase 5 — Reference recoloring (§19).** Indexed remap and quantize, PNG/JPEG/GIF
including animation, the all-references gallery page, and drag-and-drop image import with
no command line anywhere.
*Gate:* tests green against committed example images; the gallery rendered and inspected;
driven in the browser end to end.

## 15. Verification

```bash
cd palette && npm test
```

```bash
cd palette && npm run render
```

```bash
cd palette && npm start
```

Git: files are written and edited only — nothing is staged or committed without asking. The repo owner commits through GitHub Desktop.

---

# Part III — Handoff

## 16. Copy-paste handoff prompt

Paste this into a fresh session, from anywhere in the repo. It works whether the build has not started or is halfway through any phase, and on any machine that has the repo checked out.

> **Updated after Phase 1.** The original version of this prompt pointed at an absolute
> path outside the repo and named PLAN.md as the only document. Both are now wrong:
> the plan travels with the code as `palette/PLAN.md`, and `palette/ARCHITECTURE.md`
> records the contracts and decisions that only exist once there is an implementation.
> Use the block below, not a copy taken before Phase 1 was gated.

```text
Implement the Procedural Pixel-Art Palette Creator in the `palette/` directory of
this repository. All paths below are relative to the repository root.

DOCUMENTS — all three live in palette/, alongside the code. There is no design
document anywhere else, and nothing you need is outside the repository.
  palette/PLAN.md          The specification. Color theory, algorithms, formulas,
                           the full parameter list, file layout, test requirements,
                           the task list (§17), and the resume procedure (§18).
  palette/ARCHITECTURE.md  How the built part actually works: the Palette object
                           every later phase consumes, the decisions that extend
                           the plan and why, performance notes, and the known
                           limitations that are contracts rather than bugs.
  palette/PROGRESS.md      Task-by-task state. The source of truth for what is done.

FIRST ACTION — determine where the build stands:
  1. If palette/PROGRESS.md exists, read it, then read palette/ARCHITECTURE.md
     before writing code that touches src/. Continue from the first unchecked task.
  2. If palette/PROGRESS.md is missing but palette/ has files, rebuild it: copy the
     task list from PLAN.md §17, then run the state-detection procedure in PLAN.md
     §18 to check off what is genuinely complete. Verify by running `npm test`, not
     by trusting that a file exists — a file can be a stub.
  3. If palette/ does not exist at all, start at task 1.1 and copy the plan in as
     palette/PLAN.md so the spec lives beside the code.

WORKING RULES:
  - Update palette/PROGRESS.md as you go — check off each task the moment its
    "done when" condition is actually met. This is what makes the work resumable.
  - Tests are written alongside the code they cover, never batched at the end.
    `npm test` must be green before you check off any task.
  - Phases have gates (PLAN.md §14). Stop at each gate, run the gate checks, and
    report results before starting the next phase.
  - Never stage or commit anything. Write and edit files only; the repo owner
    commits through GitHub Desktop. Ask before committing.
  - No runtime dependencies. Node built-ins only (node:test, node:zlib, node:http,
    node:fs). Vanilla ES modules in the browser, no framework, no bundler beyond
    the trivial inliner in tools/build.mjs.
  - Nothing under src/core/ may import a Node built-in. That constraint is what
    lets the same code run in the browser, under `node --test`, and headlessly.
  - Every exported function gets a one-line JSDoc purpose comment. Delete unused
    code rather than leaving it.

FIVE THINGS THAT WILL SILENTLY RUIN THIS IF YOU GET THEM WRONG:
  1. NEVER clamp R/G/B independently to fit sRGB. Use the chroma-reduction gamut
     mapping in PLAN.md §2.4. Independent clamping changes hue and lightness and
     invalidates every invariant the generator is built on.
  2. The allocator is BUDGET-driven, not hue-count-driven (PLAN.md §3). Leftover
     budget must deepen existing structure — longer ramps, split neutrals,
     extended background ramps — never spray filler accent colors.
  3. Pipeline order is fixed (PLAN.md §2.7): gamut map -> bit-depth quantize ->
     repair. Repair MUST run after quantization, because quantization can collapse
     two distinct colors onto the same legal grid point.
  4. The seed string encodes the FULL parameter set, not an RNG seed (PLAN.md §6).
     A bare RNG seed stops reproducing the palette the instant the algorithm
     changes, which defeats the entire point of re-tuning later.
  5. Use the seeded PRNG in src/core/rng.js, never Math.random, anywhere.
     Determinism is a tested requirement.

VERIFYING YOUR OWN WORK — you do not need the user to playtest:
  cd palette && npm test        # node --test, all invariants + fuzz
  cd palette && npm run render  # writes out/*.png — READ these images yourself
  cd palette && npm start       # then drive the real UI with the browser tool
`npm test` runs a 10,000-case fuzz and takes several minutes; while iterating use
`PALETTE_FUZZ_N=200 npm test`. Golden snapshots in test/snapshots/ fail on any
algorithm change by design — review the diff, then re-record with
`UPDATE_SNAPSHOTS=1 npm test`. Only hand something to the user when you cannot
verify it any of those ways.
```

## 17. Task list

Copy verbatim into `palette/PROGRESS.md` on first run and maintain it there. Each task's **done when** is the checkoff condition.

### Phase 1 — Core (headlessly verifiable, no UI)

- [ ] **1.1 Scaffold** — `package.json` (`type: module`; scripts `test`/`start`/`build`/`render`), `.gitignore` (`out/`, `dist/`, `node_modules/`), `README.md`. *Done when:* `npm test` runs and reports zero tests without erroring.
- [ ] **1.2 PNG encoder** — `tools/png.mjs` using `node:zlib`. *Done when:* a test writes an 8×8 RGB PNG that decodes back to the same pixels.
- [ ] **1.3 Color math** — `src/core/oklch.js`: OKLCH↔OKLab↔linear sRGB↔sRGB, hex parse/format, `deltaEOK`, WCAG relative luminance and contrast ratio.
- [ ] **1.4 Color math tests** — `test/oklch.test.js`: dense round-trip grid, published reference values, contrast ratios against known pairs. *Done when:* green.
- [ ] **1.5 Gamut mapping** — `src/core/gamut.js` per plan §2.4.
- [ ] **1.6 Gamut tests** — `test/gamut.test.js`: all output in-gamut; **hue and lightness preserved within tolerance** for known out-of-gamut inputs. *Done when:* green.
- [ ] **1.7 Quantization** — `src/core/quantize.js` per plan §2.6, including `error-weighted` mode.
- [ ] **1.8 Quantization tests** — legal-grid membership for every R/G/B bit combination 1–8. *Done when:* green.
- [ ] **1.9 Parameter schema** — `src/core/params.js`: all ~50 parameters from plan §5 with name, group, type, range, default, and doc string. Single source of truth — the UI generates sliders from this, and the seed codec reads its field order from this.
- [ ] **1.10 Hue generation** — `src/core/hues.js`: all 7 schemes, perceptual spacing blend, jitter, circular interpolation, all three `shift_direction` modes.
- [ ] **1.11 Ramps** — `src/core/ramp.js`: lightness curves, chroma Gaussian + directional falloff, all three `shift_model` variants (plan §4).
- [ ] **1.12 Allocator** — `src/core/allocate.js`: derived hue-count table and the 12 partially-fillable rounds (plan §3).
- [ ] **1.13 Repair** — `src/core/repair.js`: `min_delta_e`, `fg_bg_separation_min`, `force_unique_hex`, iterated to a fixed point.
- [ ] **1.14 Roles** — `src/core/roles.js`: stable ordering + semantic auto-assignment.
- [ ] **1.15 Pipeline** — `src/core/generate.js`: pure `params -> Palette` in the order of plan §2.7, plus the xorshift128 PRNG.
- [ ] **1.16 Generator tests** — `test/generate.test.js`: exact count for **every** K in 4–64 across all schemes and hue counts; anchor L extremes; hue-shift direction; ramp L monotonicity; `min_delta_e`; anchor contrast; fg/bg separation; `#RRGGBB` format. *Done when:* green.
- [ ] **1.17 Seed codec** — `src/core/seed.js`: `PAL1` encode/decode including locks and overrides (plan §6).
- [ ] **1.18 Seed tests** — round-trip over randomized parameter sets; forward-compatibility (a `PAL1` payload still decodes after fields are appended). *Done when:* green.
- [ ] **1.19 Presets** — `src/core/presets.js`: 8 emulation-flavored + 12 mood parameter sets (plan §11).
- [ ] **1.20 Reference palettes** — `src/core/reference.js`: 11 embedded real palettes, read-only, plus the ΔE fit-score function.
- [ ] **1.21 Exporters** — `src/core/export/`: gpl, pal, hex, png, json, css, tres, lospec.
- [ ] **1.22 Export tests** — every format parses back to identical colors; `.tres` is valid Godot syntax; PNG strip decodes to exactly K pixels. *Done when:* green.
- [ ] **1.23 Fuzz tests** — 10,000 randomized parameter sets: no NaN, no throw, no out-of-gamut color, exact count, all invariants hold. *Done when:* green.
- [ ] **1.24 Snapshots** — `test/snapshots/`: golden hex output per preset, plus a cross-process determinism test.
- [ ] **1.25 Headless renderer** — `tools/render.mjs` emitting palette strips for every preset to `out/`.
- [ ] **1.26 GATE 1** — `npm test` fully green; `npm run render` produces PNGs; **read the PNGs and confirm the palettes look correct**; report to user.

### Phase 2 — App

- [ ] **2.1 Dev server** — `tools/serve.mjs`: static hosting plus `GET/PUT/DELETE /api/saves` writing `palette/saved/*.json`.
- [ ] **2.2 Shell** — `index.html`, `src/style.css`: three-pane layout (params / swatches / gallery).
- [ ] **2.3 Sliders** — `src/ui/sliders.js`, generated automatically from `params.js`, grouped and collapsible, with the doc string as tooltip.
- [ ] **2.4 Swatch grid** — `src/ui/swatches.js`: role, hex, OKLCH readout, lock toggle, manual override editor.
- [ ] **2.5 History** — `src/ui/history.js`: undo/redo plus a 20-deep clickable strip.
- [ ] **2.6 I/O** — `src/ui/io.js`: seed field, URL-hash sync, preset dropdown, saved-palette dropdown backed by `/api/saves`, all export buttons.
- [ ] **2.7 Wiring** — `src/ui/app.js`: live regeneration on any change; randomize that respects locks and overrides.
- [ ] **2.8 Standalone build** — `build.mjs` inlining everything into `dist/palette_creator.html`. *Done when:* the file opens by double-click and generates palettes.
- [ ] **2.9 GATE 2** — `npm start`, drive the UI with the browser tool: every slider changes output, seed round-trips, save/load works, every export downloads a correct file. Report to user.

### Phase 3 — Test visual gallery

- [ ] **3.1 Scene registry + gallery** — `src/scenes/index.js`, `src/ui/gallery.js`: scrollable, category filters, per-scene toggles.
- [ ] **3.2 Analysis module** — `src/core/analysis.js`: Viénot colorblind matrices, grayscale value view, ramp evenness metrics.
- [ ] **3.3 Dithering module** — `src/core/dither.js`: Floyd-Steinberg, Bayer 4×4 and 8×8.
- [ ] **3.4 Scenes 1–6** — palette structure: swatch grid, ramp strips, value view, OKLCH scatter plots, ΔE heatmap, colorblind board.
- [ ] **3.5 Scenes 7–10** — form and shading: sphere, iso cube, cylinder, material studies.
- [ ] **3.6 Scenes 11–19** — sprites, outline modes, sprite-over-every-background, palette swap, icons, combat scene, skin, foliage.
- [ ] **3.7 Scenes 20–24** — parallax, dungeon, day/dusk/night, tileset, full screenshot.
- [ ] **3.8 Scenes 25–26** — UI mockup and text legibility matrix with WCAG overlay.
- [ ] **3.9 Scenes 27–31** — dither pair matrix, Bayer ramps, sky gradient, 1px noise, zoom comparison.
- [ ] **3.10 Scene 32** — animated: water cycling, torch flicker, day-night sweep.
- [ ] **3.11 Scene 33** — photo quantization: drag-and-drop plus 3 procedurally-generated reference images.
- [ ] **3.12 Scene 34** — side-by-side reference compare with ΔE fit score.
- [ ] **3.13 Extend renderer** — `tools/render.mjs` renders every static scene to `out/`.
- [ ] **3.14 GATE 3** — render all scenes, **read the PNGs yourself**, then confirm in-browser. Report to user.

### Phase 4 — Artist's-palette picker

- [ ] **4.1 Scoring** — `src/core/layout/score.js`: mean and worst neighbor ΔE; blob-sizing modes.
- [ ] **4.2 SOM** — `som.js`: rectangular, toroidal, hexagonal, and disc variants (1–4).
- [ ] **4.3 Annealing** — `anneal.js`: seeded, deterministic swap optimizer (5).
- [ ] **4.4 Hilbert** — `hilbert.js`: 3D Hilbert index + boustrophedon fill (6).
- [ ] **4.5 Projection** — `mds.js` + `voronoi.js`: MDS/PCA projection, Voronoi, Lloyd relaxation (7–8).
- [ ] **4.6 Organic** — `grow.js`: ΔE-weighted region growth (9).
- [ ] **4.7 Remaining** — polar wheel, ramp-rows baseline, value spiral, treemap, sphere unwrap, Delaunay (10–15).
- [ ] **4.8 Layout tests** — full coverage with no holes; **every optimized layout beats the ramp-rows baseline** on mean neighbor ΔE; annealing deterministic under fixed seed. *Done when:* green.
- [ ] **4.9 Picker UI** — `src/ui/picker.js`: variant selector, blob-size mode, hover readout, click-to-copy, high-res PNG export, contact sheet.
- [ ] **4.10 GATE 4** — render the contact sheet, inspect it, and report the ranked scores to the user.

## 18. Resuming from an unknown state

If `palette/PROGRESS.md` is missing or stale, rebuild it from observed reality rather than from filenames — a file can exist and be a stub.

1. **Does `palette/` exist?** No → start at task 1.1.
2. **Run `cd palette && npm test`.**
   - Command fails to run at all → task 1.1 is incomplete.
   - Tests run: note exactly which test files exist and pass. A task is complete **only if** its test file exists and is green. Tasks 1.3–1.24 are each gated by a named test file, so the highest contiguously-passing task number is your resume point.
3. **Run `npm run render` and read `out/`.** Palette strips present and correct → Phase 1 gate passed. Scene PNGs present → Phase 3 is underway; count which of the 34 scenes rendered.
4. **Check `src/ui/`.** Absent → Phase 2 not started. Present → run `npm start` and drive the UI: whichever of the 2.3–2.8 features actually respond determines the resume point.
5. **Check `src/core/layout/`.** Count implemented variants against the list of 15 in task 4.2–4.7.
6. **Write the reconstructed `palette/PROGRESS.md`** with everything verified-complete checked off, then continue from the first unchecked task.

Partial work inside a single task is safe to redo — tasks are sized so that restarting one costs little. When in doubt, redo the task rather than assume it finished.

---

# Part IV — Phase 5: reference-image recoloring

## 19. Recoloring reference art

The generator's real test is not a swatch sheet — it is whether the palette holds up on
work an artist would recognise. Phase 5 takes a folder of reference images (expert pixel
art, photographs, the user's own files) and re-renders every one of them in the generated
palette, then shows them all together on one page: **a complete visual gallery of what the
chosen palette looks like in practice.**

### 19.1 Two modes, because one algorithm is wrong for half the inputs

**Per-pixel nearest-color matching is the wrong algorithm for pixel art.** It decides each
pixel independently, so one source color can land on different target colors in different
places, which destroys outlines, anti-aliasing seams and ramp continuity — precisely the
things that make expert pixel art good. Photographs are the opposite case and want exactly
that per-pixel treatment.

**Indexed remap** — for pixel art and anything with a small color count.
1. Extract the source's own unique colors (typically 8–64).
2. Map *source palette → target palette* as one assignment, decided once.
3. Apply it as a lookup, so every instance of a source color becomes the same target color.

The artist's structure survives intact. Parameters:
- `remap_match` — `delta-e` (nearest in OKLab) | `lightness-rank` (sort both palettes by L
  and match by position) | `optimal` (assignment minimizing total ΔE, no target reused
  while unused ones remain).
- `remap_preserve_order` — force the mapping to be monotonic in lightness, so the source's
  value structure survives even when the hues are completely different. This is the knob
  that makes a wildly different palette still read correctly.
- `remap_overflow` — what to do when the source has more colors than the target: `share`
  (nearest, reuse freely) | `merge` (cluster the source colors down first).

**Quantize** — for photographs and anything with a large color count.
- `quant_dither` — `none` | `floyd-steinberg` | `bayer4` | `bayer8`
- `quant_dither_strength`
- `quant_lightness_weight` — weight on L versus chroma in the match metric. Raising it
  preserves the value structure at the cost of hue accuracy.
- `quant_downscale` — optional pre-scale to a pixel-art resolution.

`recolor_mode` is `auto` | `indexed` | `quantize`; `auto` picks by the source's unique-color
count against `recolor_indexed_max`.

### 19.2 Formats

PNG, JPEG and **GIF**.

> **Changed 2026-07-22, by the repo owner, superseding what this section originally said.**
> A GIF is recoloured **in its entirety and shown animated** — every frame, played back at
> the source's own timing. The original decision (decode all frames, recolour and show only
> one) is no longer the spec. `gif_frame` survives only for the *still* outputs that cannot
> animate — the headless PNG renderer and single-frame export.

Reading a GIF needs an LZW decoder, which is ours to write (no dependencies). The decoder
returns **every** frame, already composited against its predecessor and disposal method, so
a caller gets whole displayable frames rather than the sparse patches the file stores. Each
frame carries its own delay.

The decoder lives in `src/core/`, and so does the encoder that writes the recoloured
animation back out as a GIF — LZW is pure arithmetic with no platform dependency, and having
both means an encode/decode round trip is a test rather than an assumption.

Both are therefore usable from the browser and from `node --test`.

### 19.3 The gallery page

One page showing **every reference image together** — the user's own files and the
generated ones — each as original alongside recolored, with the mode and unique-color
count. This is the "what does this palette actually look like" view, and it updates live
with the palette like everything else.

Generated references ship with the repo so the page is never empty and the tests always
have something to assert on. The user's images are added without touching the command line
(§19.5).

### 19.4 Tests

Tests must confirm recoloring genuinely works, on real image data rather than mocks:
- Committed example reference images — including a GIF — that the tests decode and recolor.
- Indexed remap: output contains **only** target-palette colors; a source color always maps
  to the same target color everywhere; `remap_preserve_order` really is monotonic in L.
- Quantize: output contains only target-palette colors; dithering is deterministic.
- GIF: an animated fixture decodes to the right frame count and dimensions, and `gif_frame`
  selects the frame it says it does.
- Auto mode picks `indexed` for pixel art and `quantize` for a photograph.

### 19.5 No command line

**Everything must work without typing a command**, including adding reference images. This
constrains delivery, not just UI:
- Reference images are added by drag-and-drop or a folder picker in the app itself.
- The recolor gallery, its parameters and its exports are all in the app.
- Whatever starts the app must be double-clickable.

See ARCHITECTURE §12 for the delivery options and the decision taken.
