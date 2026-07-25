# Usefulness Audit — how to reach the palette you wanted, faster

Audit date 2026-07-24, against the tool as built (72 parameters: 58 palette-shaping + 13
recolour + `seed`; 34 gallery scenes; picker with maps/dither/15 layouts; recolour page;
fitter; 8 export formats). **Not a performance audit.** Every item below is judged on one
question:

> **How many actions, and how much reading, stand between "I want a palette like _this_"
> and having it?**

Effort tags: **S** ≈ an afternoon, **M** ≈ a day or two, **L** ≈ a phase.

---

## The one structural observation

The tool is an excellent **forward** generator: parameters → palette. But the user's task is
almost always the **inverse**: "I have a look in my head (or on screen); find the parameters."
Today that inversion is done by hand, by dragging up to 58 sliders whose names are source
identifiers, while the evidence is a 34-card grid of small synthetic scenes.

Three inversion engines already exist in the repo and are all underexposed:

| Engine | Where | Why it is underused today |
|---|---|---|
| `fit.js` — params from a target palette | `Fit to image…`, in a collapsed drawer | Always starts from defaults, ignores current params and locks, reports only a ΔE number, all-or-nothing |
| Locks + overrides | swatch pills | Pin a hex, but no way to say "these hues, that contrast" |
| `seed` string | topbar | Reproduces a palette; cannot move *toward* one |

**Almost every high-value item below is either (a) making the inversion engines usable, or
(b) replacing slider-hunting with picking from generated candidates.** The generator is fast
and deterministic — that is exactly the property that lets you show the user twelve answers
instead of asking them for twelve numbers.

Evidence that the current loop is heavy: `saved/` is **empty**, while `saved_palettes.txt.txt`
in the project root holds a single hand-pasted `PAL1-…` seed. The save path exists and is not
being used; a text file is winning against it.

---

## Tier 1 — changes the interaction model (biggest time-to-palette win)

### 1. Variant grid: pick, don't tune · **M**
Below (or instead of) the sliders, show **9–12 live thumbnails** of neighbouring palettes:
the current parameters perturbed along a few structured directions (hue rotation, contrast,
saturation, warmth, budget split, ramp shape). Click one → it becomes the current palette and
a fresh dozen are generated around it. Shift-click → "less like this".

Why: this is the single biggest reduction in twiddling. It converts an inverse problem into
repeated visual selection, which is what the eye is good at and what a slider panel is worst
at. Ten clicks ≈ 10 halvings of the search space, with zero parameter knowledge required.

Plugs into: `generatePalette` is pure and fast; `history.js` already renders palette
thumbnails; `randomize.js` already knows which parameters are safe to move. Render each tile
as one small hero scene (not swatch bars) so the thumbnail shows the *look*, not the *list*.

### 2. Slider preview strips + human labels · **S each, huge combined**
Two halves of the same problem — "reading the description is necessary today".

**a. Preview strip on hover.** When the pointer is on a slider, render 5 tiny palettes at
that parameter's min…max (everything else held). The user *sees* what the knob does in
150 ms and never opens the tooltip. This is the highest value-per-line change in the whole
audit: one function, reuses the generator, kills most of the documentation burden.

**b. Real names.** `sliders.js:121,136` prints `spec.name` — the raw seed key — as the
label. Add `label` (and a 4-8 word `hint`, plus `lowLabel`/`highLabel`) to `ParamSpec`,
render those, and keep `name` as the seed key so nothing about the payload changes. A slider
whose two ends are named needs no prose. See the rename table at the end.

### 3. Compare two palettes, and say how to close the gap · **M** (explicitly requested)
A **Compare** mode: pin the current palette as A, choose B (a save, a preset, an external
palette image, a pasted hex list, or a `PAL1-` seed). Show three things:

1. **Aligned side-by-side** — both palettes sorted by lightness (and again by hue) so the
   holes line up visibly, plus the same gallery scene and the same recoloured reference
   image rendered in both.
2. **A difference report in the user's terms**, not parameter terms:
   *"B is 0.06 darker overall · shadows 22% more saturated · hue families at 25/140/210 vs
   your 35/120/240 · B's ramps step 0.04 harder · B has no accent colour."*
   All of this is computable now from `rampsOf`, `analysis.js` and `entry.actual`.
3. **"How to get there"** — run `makeFitter` against B's hexes but **seeded from A's current
   parameters** (a one-line option in `fit.js`), then report the largest parameter deltas as
   an ordered, applicable list: *"chroma_base +0.06, l_step −0.03, root_hue +25 → 78% of the
   way there. [Apply top 3] [Apply all]"*.

Plus a **morph slider**: interpolate A→B parameter-wise, 0–100%, live. Trivial to implement
(numeric lerp, enums snap at 50%) and it answers "make mine a bit more like theirs" with one
drag instead of a fitting session.

### 4. A hero preview that never leaves the screen · **S–M**
While tuning, the evidence should not scroll away. Pin **one large scene** (user-selectable,
default a full mockup) directly above or beside the sliders, always visible, always current.
The 34-card grid stays as the audit view; it is not a tuning view.

Also: the gallery's minimum zoom is 2× (`index.html:55`) — pixel art has to be judged at 1×
too. Add 1×, and a "1× and 4× side by side" option for the hero.

### 5. Randomize is currently a dice roll, not an explorer · **S**
`randomize.js` draws every non-skipped parameter **uniformly across its full range**,
including `hue_scheme`, `hue_count`, `root_hue` and every shift/atmosphere knob. Most draws
are incoherent, and a press throws away whatever character the current palette had, so it is
useless once you are close to what you want. Replace with:

- **Vary strength** (Subtle / Moderate / Wild) that perturbs *around* the current values;
- **sample from plausible regions** — the presets are a real distribution of good palettes,
  and `test/fuzz.test.js`'s `feasibleParams` already encodes plausibility bounds;
- **respect what the user has decided**: never reroll `hue_scheme`/`hue_count`/`color_count`
  unless asked (a per-group "reroll just this" button on each group header is better);
- feed it straight into item 1 — "12 variants at strength X" is the same code.

---

## Tier 2 — fewer actions per session

### 6. One-click Keep, and a visual library of saved palettes · **M**
Today: type a name → press Save → it lands in a `<select>` of bare strings. Evidence says
this loses to a text file. Instead:

- a **star/Keep button** in the topbar that saves immediately with an auto-generated name
  (`warm-32-dusk-01`, derived from `root_hue`/`color_count`/`l_mid_base`) — no typing, no
  dialogue, rename later;
- a **library grid** (swatch strip + one scene thumbnail per save) instead of a dropdown;
  click to load, shift-click to send to Compare (item 3);
- **persist history** (currently 20 entries, memory only) to `localStorage` so a good palette
  three reloads ago is still recoverable; raise the cap to ~100;
- **autosave** every accepted palette into a rolling `saved/_recent/` ring.

The server side already exists (`/api/saves` GET/PUT/DELETE in `tools/serve.mjs`).

### 7. Ramp view of the swatch pane · **S**
The palette pane is a flat auto-fill grid of cards in slot order. Pixel artists think in
**ramps**. Add a view toggle — Grid / **Ramps** (one row per hue family, dark→light, neutrals
and accents on their own rows) / Sorted by lightness / Sorted by hue. `rampsOf()` in
`analysis.js` already returns exactly this grouping. Structural faults (a ramp with a dead
step, two ramps sitting at the same value) become obvious instead of needing a scene to
reveal them.

### 8. Edit a colour directly, properly · **M**
Overrides accept a typed hex only. Add, on swatch click: an **OKLCH mini-editor** (L/C/H
sliders + hex field + live gamut edge), **arrow-key nudge**, an **eyedropper** that samples
from any loaded reference image or the picker canvas, and "re-derive this ramp from this
step". Also a **pinned-colours list** ("3 locked, 1 overridden — clear all"), since locks are
invisible unless you scan every card.

This matters because the fastest path to a target palette is often "I know I want *this*
green" — one eyedrop should place it, with the generator building around it.

### 9. Let the user state the hues directly · **S–M**
`hue_scheme: 'custom'` is misleading: `hues.js:54` spreads hues evenly over `span` — there is
no way to specify custom hues at all. Either rename that option (`fan`/`spread`) or, far
better, **make it real**: a hue field (`25, 140, 210, 320`) or a hue wheel with draggable
pins, optionally **seeded by eyedropping an image**. Naming the 3–5 hue families is the most
direct expression of intent there is, and today it must be approximated with
`root_hue` + `hue_span` + `scheme` + `jitter` — four coupled knobs for one decision.

### 10. Make the fitter a tool instead of a black box · **M**
`fit.js` is the strongest inversion engine here; five changes make it usable:
- **start from the current parameters** (option in `makeFitter`) → "make mine more like this";
- **honour locks/overrides and a "keep these fixed" set** (e.g. keep my `color_count`,
  `hue_scheme` and bit depth; fit only chroma+lightness);
- **live preview** of best-so-far palette during the search, not just a ΔE number;
- **"keep looking"** to continue from where it stopped, and **undo the fit** as one step;
- **report the diff** it applied (which parameters moved and by how much) — otherwise the
  user learns nothing and cannot adjust from there.

### 11. Ingest palettes without files · **S**
`Fit to image…` and `Add palette…` both require a file on disk (`palettes/` currently holds
only a README). Add: **paste a hex list** (any of `#aabbcc`, `aabbcc`, comma/newline/space
separated), **paste an image from the clipboard**, **drag a URL**, and accept a **lospec
slug/URL**. Then the whole flow "I saw a palette I like" → compare/fit/recolour-target is
Ctrl+V instead of download-save-locate-open.

### 12. Copy-all and quick output · **S**
No "copy every hex" button exists — copying a 32-colour palette means 32 swatch clicks.
Add: **Copy all hexes**, **Copy as CSS vars**, **Copy PNG strip to clipboard**, **Copy share
link** (the seed is already mirrored into the URL hash).

### 13. Basics / Advanced, plus search · **S**
72 parameters in 11 groups is a wall. The README already names the five big movers
(`hue_scheme`, `root_hue`, `color_count`, `l_mid_base`, `chroma_base`) — the UI does not
reflect that at all. Add:
- a **Basics** view: ~10 controls (the five above plus `l_step`, `earthiness`,
  `highlight_shift_strength`, `bg_chroma_mult`, `hue_count`), everything else under Advanced;
- a **search box** filtering by label/name/doc text ("type *shadow*");
- **"only show what I changed"** — `markChanged` already tags these (`sliders.js:191`), so
  this is a CSS filter and a checkbox, and it answers "what actually makes this palette look
  like this?";
- **per-group reset** and alt-click-to-reset-one-parameter.

---

## Tier 3 — correctness, and knowing *why* a palette is wrong

### 14. A palette report card with one-click fixes · **M**
The pane shows constraint *warnings* today. Promote it to a diagnostic that names problems
**and offers the fix**, since every one of these is already computable:

| Finding | Data source today | Offered fix |
|---|---|---|
| Two colours are near-duplicates (ΔE < x) | `deltaEOK` over entries | "raise `min_delta_e` to 5.2" / "spread these two" |
| A hole in the value structure | lightness histogram of `entry.actual.L` | "lower `l_step`" / "add a step to ramp N" |
| Hue gap of >90° | hue histogram | "add a hue at 190°" / "raise `hue_count`" |
| Colours no scene ever uses | **`sceneUsage()` already computes this** | "drop `color_count` by 2" / show which slots |
| Two colours collide under deutan/protan | `simulateColorblind` | "raise separation" / highlight the pair |
| Text pairs below WCAG | `min_anchor_contrast` machinery | show the failing pairs as a matrix |
| Requested vs achieved colour diverged | `entry.oklch` vs `entry.actual` **both already stored** | flag the swatch: "chroma reduced 0.31→0.22 to fit sRGB" |

The last row is a genuine correctness gap: when gamut mapping or bit-depth quantisation moves
a colour, the sliders keep showing what you asked for and the swatch shows what you got, with
nothing connecting them. Surfacing the delta per swatch explains most "why won't this get more
saturated?" dead ends — the answer is in `COLOR_GUIDE.md` but should be on the swatch.

### 15. Surface the dither reference's recommendation where decisions are made · **S**
The dither view already computes *"the colours worth adding to close the rest"*. That is a
direct, actionable palette improvement buried two tabs deep behind a Rebuild button. Show the
top suggestion in the palette pane ("adding a colour near `#7A9C3F` would cover the largest
gap — [add it]"), and let it be added as a locked slot.

### 16. Hardware depth as one decision, not three sliders · **S**
`bits_r`/`bits_g`/`bits_b` are three sliders that are almost always set together, and the
docs for all three say "set it with the other two". Replace with a **Target hardware**
dropdown (Modern 8/8/8 · SNES 5/5/5 · Genesis 3/3/3 · Master System 2/2/2 · NES fixed ·
Custom…), custom revealing the three sliders. Three controls and three tooltips collapse into
one choice whose options are named after what the user actually wants.

### 17. Enum values in plain language · **S**
Options render as raw identifiers (`ease-dark`, `per-family`, `spectral-gap`,
`error-weighted`, `reduce-l-adjust`). Give each option a label + one-line effect in the
schema: `ease-dark` → *"Bunch steps in the shadows (rich darks)"*; `per-family` → *"Keep each
hue's identity (safe)"*; `spectral-gap` → *"Fill the hue gaps (harmonious)"*. Same change as
the parameter labels, same file.

### 18. Real art as the yardstick, not only synthetic scenes · **M**
The 34 scenes are diagnostics — swatch grids, heatmaps, 16×16 sprites, 128×96 vignettes. The
repo already holds ~300 real pixel-art references and a recolour engine that renders them
into the palette with original-beside-recoloured. Close the gap:
- promote a **pinned hero set** of 5 real artworks (a landscape, a character portrait, a dark
  interior, a bright exterior, a UI-heavy screenshot) to the top of the Gallery tab, so the
  palette is always being judged on real composition, not only on generated shapes;
- add **larger composed mockups** to the scene set (256×192: HUD + tilemap + character +
  text at three sizes + inventory grid), since a palette can pass 34 small scenes and still
  fall apart in a full screen;
- let the user **pin/star scenes**, so tuning shows the two or three scenes they care about
  instead of scrolling past 30.

### 19. Colour-vision views side by side · **S**
`gallery-view` is a dropdown, so checking colourblind safety means switching back and forth
from memory. Offer "Colour + Deutan side by side" (and value) as one option — comparison is
the whole point, and the renderer already produces both.

### 20. Semantic names in exports · **S**
`roles.js` assigns `foliage`, `skin`, `stone`, `ui_good`… and `export/json` carries them, but
the CSS export emits positional names. Emit `--color-foliage-mid`, `--color-ui-bad`, and let
`.gpl`/`.hex` carry role names as comments plus the `PAL1-` seed, so any exported file can be
traced back to the parameters that made it.

---

## Tier 4 — low-hanging fruit and parity with other tools

21. **Colour names** ("dusty rose", "deep teal") from a small embedded name list, on each
    swatch and in saved-palette titles — makes palettes memorable and searchable. **S**
22. **Before/after ghost**: hold a key to see the palette as it was before the current edit.
    History exists; this is the same data with a keybinding. **S**
23. **More export targets**: Adobe `.act`/`.ase`, paint.net `.txt`, Aseprite `.aseprite`
    palette, and a proper **1px-per-colour lospec PNG strip** (your own `swatches.js` reads
    that format back, so it round-trips). **S**
24. **Export the gallery / hero scene as PNG** — the picker can export, the gallery cannot,
    and the gallery image is what you would actually show someone. **S**
25. **Keyboard**: `R` vary, `1/2/3` tabs, `[`/`]` step through history, `F` fit, `C` copy all,
    `space` new variants. Currently only undo/redo are bound. **S**
26. **Preset picker as a thumbnail grid** rather than a `<select>` of 21 names — you cannot
    choose a look from a word. **S**
27. **Mood-first start screen**: chips (dungeon · sunset · forest · neon · pastel · console ·
    monochrome) → preset + variant grid; or "start from an image"; or "start from a
    screenshot". Removes the "58 sliders at defaults" cold start. **M**
28. **Undo depth and granularity**: a slider drag coalesces correctly, but 20 steps is thin
    once variant-grid clicking exists; raise it and label history entries with what changed. **S**
29. **Per-swatch "where is this used"**: click a colour → highlight it in every gallery scene
    (`sceneUsage` already counts pixels per entry; the per-scene map is the same loop). Answers
    "can I delete this colour?" **M**
30. **Contrast checker widget**: pick any two swatches → WCAG ratio + ΔE + how they read under
    each CVD, with a text sample. The data exists across `analysis.js` and the text-matrix
    scene; it is the *interactive* version that is missing. **S**
31. **Palette size sweep in-app**: show the same parameters at K = 8/16/24/32/48/64 as
    thumbnails (`npm run render` already writes exactly this sheet offline) so choosing
    `color_count` is a glance, not five drags. **S**
32. **"Explain this palette"**: one paragraph generated from the parameters and measurements
    — *"32 colours, 4 analogous hues around warm orange, dark-key with strong contrast,
    cool-shadow hue shifting, muted backgrounds"*. Useful as a save name, as a diff in
    Compare, and as a sanity check that the parameters say what you think. **S**
33. **Lock the recolour target while tuning** is documented as the workaround for "the
    recolour keeps moving"; make it a one-click **"Freeze"** toggle in the topbar that zeroes
    `hue_jitter`/`l_variance_per_hue`/`chroma_variance_per_hue` (README already prescribes
    exactly this trio) and restores them on release. **S**
34. **Show the parameter set that a preset changed** when loading one (a diff against
    defaults), so presets teach the parameters instead of being opaque jumps. **S**
35. **Warn on silent no-ops**: e.g. raising `l_mid_base` alone does not lift the midtone
    because the ramp is clamped inside the anchor window (documented in PROGRESS.md). When a
    slider's effect is being swallowed by another constraint, say so on the slider —
    *"clamped by `l_light_anchor`"* — instead of leaving the user dragging a dead control.
    This is the single most frustrating class of bug in any parameter UI. **M**

---

## Concrete parameter rename table (item 2b)

Keep `name` (seed key) unchanged; add `label`, `hint`, and slider end-labels.

| `name` (keep) | `label` (show) | Low end ← → High end |
|---|---|---|
| `color_count` | Number of colours | fewer/retro ← → richer |
| `hue_count` | How many colour families | themed ← → rainbow |
| `hue_scheme` | How the hues relate | *(named options)* |
| `root_hue` | Overall colour of the world | *(hue wheel)* |
| `hue_span` | How wide the hues spread | one mood ← → varied |
| `hue_jitter` | Hand-picked wobble | machine-regular ← → organic |
| `perceptual_hue_spacing` | Even to the eye vs even by angle | by angle ← → by eye |
| `fg_ramp_length` | Shades per foreground colour | flat ← → smooth |
| `bg_ramp_length` | Shades per background colour | flat ← → deep |
| `neutral_count` | Grey / stone / metal slots | organic ← → architectural |
| `accent_count` | Pop colours | none ← → loud |
| `tier_priority` | Spend the budget on… | *(named options)* |
| `l_dark_anchor` | Darkest colour | inky ← → faded |
| `l_light_anchor` | Brightest colour | dim ← → paper-white |
| `l_mid_base` | Overall brightness | dungeon ← → daylight |
| `l_step` | Shading contrast | soft/painterly ← → punchy |
| `l_curve` | Where the shades bunch up | *(named options)* |
| `l_range_compress` | Haze / washed-out | crisp ← → foggy |
| `l_variance_per_hue` | Random brightness variety | systematic ← → natural |
| `hue_lightness_follow` | Let each hue find its brightest form | olive/uniform ← → vivid gold & leaf-green |
| `chroma_base` | Saturation | greyscale ← → neon |
| `chroma_peak_l` | Most colourful at | shadows ← → highlights |
| `chroma_curve_width` | Colour across the ramp | midtones only ← → whole ramp |
| `chroma_falloff_light` | Highlights | neon/emissive ← → sun-bleached |
| `chroma_falloff_dark` | Shadows | rich & coloured ← → muddy grey |
| `chroma_variance_per_hue` | Saturation variety between hues | uniform ← → natural |
| `earthiness` | Earthy / dirt & rust | clean ← → weathered |
| `chroma_cap` | Saturation ceiling (safety) | print-safe ← → max vivid |
| `highlight_hue_target` | Colour of the light | *(hue wheel: sun/moon/fire/magic)* |
| `highlight_shift_strength` | Hue-shifted highlights | flat tint ← → painted |
| `shadow_hue_target` | Colour of the shadows | *(hue wheel)* |
| `shadow_shift_strength` | Hue-shifted shadows | just darker ← → dramatic |
| `shift_model` | How hues rotate | *(named options)* |
| `shift_direction` | Rotation direction | *(named options)* |
| `global_temperature` | Warm / cool bias | winter ← → sunset |
| `temperature_split` | Warm light vs cool shadow | inverted/toxic ← → natural |
| `bg_chroma_mult` | Background saturation | recessive ← → as vivid as sprites |
| `bg_lightness_offset` | Background brightness | dark backdrop ← → light backdrop |
| `bg_hue_shift` | Backgrounds pull to the air colour | true hue ← → atmospheric wash |
| `atmosphere_hue` | Colour of the air | *(hue wheel)* |
| `atmosphere_strength` | Distance haze | flat ← → deep layers |
| `fg_bg_separation_min` | Keep sprites readable on backdrops | unified ← → guaranteed pop |
| `neutral_temperature` | Tint of the greys | *(hue wheel: slate ↔ taupe)* |
| `neutral_chroma` | Greys: digital vs painted | pure grey ← → painted |
| `neutral_split` | Separate warm and cool greys | *(toggle)* |
| `neutral_l_spread` | Contrast within the greys | quiet UI ← → bold stone |
| `accent_chroma_boost` | How loud the accents are | blends in ← → shouts |
| `accent_hue_mode` | Where accents sit | *(named options)* |
| `accent_l` | Accent brightness | jewel ← → glowing |
| `bits_r/g/b` | *(fold into "Target hardware")* | — |
| `quantize_mode` | Snapping to hardware colours | *(named options)* |
| `gamut_map_mode` | Handling impossible colours | *(named options)* |
| `min_delta_e` | Minimum difference between colours | subtle neighbours ← → all distinct |
| `min_anchor_contrast` | Text legibility floor | — |
| `dither_evenness` | Even ramp steps (dither-friendly) | by eye ← → mathematically even |
| `force_unique_hex` | No duplicate colours | *(toggle)* |
| `seed` | Variation number | *(reroll button)* |

---

## Suggested order of work

1. **#2a preview strips + #2b labels** — cheapest, and it removes most of the reading. Do first.
2. **#1 variant grid** — the interaction-model change; reuses #5.
3. **#5 vary-around-current** — prerequisite quality for #1.
4. **#4 hero preview** — makes 1/2/5 legible while tuning.
5. **#3 compare + how-to-get-there** — needs #10's "fit from current".
6. **#6 keep/library** — stops good results being lost, which is what the text file is doing now.
7. Then Tier 3 in any order; #14 (report card) and #35 (silent no-ops) are the two that make
   the tool feel *correct* rather than merely capable.

## Deliberately not recommended

- **More parameters.** The count is not the problem; the mapping from intent → parameter is.
  Two exceptions, both of which *remove* knobs: custom hue pins (#9, replaces four coupled
  knobs with one direct statement) and target-hardware (#16, three sliders → one choice).
- **Rewriting the picker.** The maps/dither/layout work is strong and specialised; it needs
  surfacing (#15), not redesigning.
- **Changing the seed payload order.** Every item here is additive to `ParamSpec`
  (`label`/`hint`/end-labels) or lives in the UI. Field order stays append-only.
