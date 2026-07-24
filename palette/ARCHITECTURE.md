# Architecture and handoff notes

What [PLAN.md](PLAN.md) does not say, because it was written before the code existed.
Read the plan first — it is the specification. This file records the **contracts the
later phases build on** and the **decisions that extend or reinterpret the plan**, with
the reasoning, so the next person does not have to re-derive them or undo them by
accident.

Status: **All four phases complete and gated.** Task-by-task state is in
[PROGRESS.md](PROGRESS.md). Phase 2's contracts are in §9; Phase 3's (scene interface,
`Raster`, scene `util.js`) are in §10; Phase 4's (the picker, and what its ranking actually
measured) are in §11.

Everything needed to continue this build is inside the repository. No document here
refers to a path outside it, to a machine-specific location, or to notes kept anywhere
else.

### Edits made to PLAN.md after it was written

`palette/PLAN.md` started as a copy of the original planning document. Six changes
were made so the committed copy is self-contained and does not mislead:

- **§19.2, GIF handling** — rewritten 2026-07-22 on the repo owner's instruction. A GIF is
  now recoloured **whole and shown animated**, which reverses the "single frame, no encoder"
  decision the section originally recorded (and which ARCHITECTURE §12.1 had agreed with).
  The superseded text is marked in place rather than deleted.

- **§16, the copy-paste handoff prompt** — rewritten. It pointed at an absolute path on
  the author's machine and named PLAN.md as the only document. Use the current version.
- **§2.5** — a note that the pairwise-nudge repair it describes does not converge, and
  what replaced it (§3.2 below).
- **§7** — a note that the file tree is the plan, not an inventory (§2 below).
- **§7 code style, §15 git rule, §7 stack rationale** — three references to the author's
  private notes were replaced with the substance of what they said, since those notes
  are not in the repository.

Everything else is as originally written, including the task list (§17) and the
resume-from-unknown-state procedure (§18).

---

## 1. The Palette object

This is the single contract everything downstream consumes. `src/ui/`, `src/scenes/`
and `src/core/layout/` should all take a `Palette` and nothing else.

```js
import { generatePalette } from './src/core/generate.js';

const palette = generatePalette(params, { locks, overrides });
```

`params` may be partial — missing fields fall back to defaults. `locks` and `overrides`
are both `{ [slotId]: '#RRGGBB' }` (see §5 for the difference).

```
Palette {
  params      // complete, normalised, SEED-SNAPPED parameter set (see §3)
  hues        // number[] — the base hue angles, one per hue index
  plan        // { hueCount, fgLen[], bgLen[], neutrals, warmNeutrals,
              //   accents, bridges, total }   — the allocator's decisions
  entries     // Entry[] — exactly params.color_count, in stable role order
  semantics   // { foliage: slotId, skin: slotId, … } — all 13 roles, always present
  warnings    // string[] — empty when every constraint was satisfied (see §6)
  seed        // 'PAL1-…' — round-trips back to params + locks + overrides
  locks       // copy of the input
  overrides   // copy of the input
}

Entry {
  id          // 'fg_h0_0' — structural slot id. STABLE: index and id do not move
              //   when colour parameters change. This is what locks/overrides and
              //   exported palette indices key on.
  role        // 'fg_h0_shadow' — human-readable name. Also stable.
  layer       // 'anchor' | 'fg' | 'bridge' | 'neutral' | 'neutral-warm' | 'bg' | 'accent'
  hueIndex    // index into palette.hues, or -1 for slots with no hue identity
  step, steps // position within its ramp, and the ramp's length
  lMin, lMax  // lightness window the repair pass may move this slot within
  locked      // came from `locks`
  overridden  // came from `overrides`
  fixed       // locked || overridden — repair never moves these
  oklch       // { L, C, h } REQUESTED — what the generator asked for
  actual      // { L, C, h } ACHIEVED — after gamut mapping and quantisation
  rgb8        // [r, g, b] integers 0–255
  lab         // [L, a, b] OKLab of the emitted colour — use this for deltaE
  hex         // '#RRGGBB', uppercase
}
```

**`oklch` vs `actual` is the distinction that matters.** `oklch` is the request;
`actual` is what came out the far end of gamut mapping and bit-depth quantisation.

- Showing a colour to the user, measuring distance, drawing anything → **`actual`,
  `lab`, `rgb8`, or `hex`**.
- Moving a colour (repair, future editing tools) → **`oklch`**, then re-realise.

The UI's OKLCH readout should show `actual`, because that is the colour on screen.

### Helpers

```js
paletteHexes(palette)        // string[] in stable order — the export order
entryFor(palette, 'foliage') // resolve a semantic role OR a slot id to an Entry
paletteViolations(palette)   // pairs still under their distance threshold, worst first
makeRealize(params)          // (oklch) -> the gamut-mapped, quantised entry fields
```

`entryFor` accepts either a semantic name or a slot id, which is what makes the
gallery scenes readable: `entryFor(palette, 'foliage')` is the tree's colour.

---

## 2. Module map

Everything under `src/core/` is DOM-free and imports only from `src/core/`. That is
what lets `node --test` exercise the real generator and `tools/render.mjs` render
headlessly. **Do not import a Node built-in from `src/core/`** — `src/core/export/png.js`
writes PNGs with stored DEFLATE blocks specifically so it needs no `zlib`.

| File | Role |
|---|---|
| `oklch.js` | Colour space conversions, `deltaEOK`, WCAG contrast, hex parse/format |
| `gamut.js` | Chroma-reduction gamut mapping (§2.4 of the plan), cusp lookup |
| `quantize.js` | Per-channel bit depth, including `error-weighted` |
| `hues.js` | Hue schemes, the perceptual-spacing warp, circular interpolation |
| `ramp.js` | Lightness curves, the chroma Gaussian, the three hue-shift models |
| `allocate.js` | Budget → structure. Derived hue count, the twelve rounds, deepening |
| `repair.js` | Distance / separation / uniqueness constraints |
| `roles.js` | Stable slot naming, semantic role assignment |
| `params.js` | The 58-parameter schema. **Single source of truth** |
| `seed.js` | `PAL1` encode/decode |
| `generate.js` | The pipeline, in the fixed order of plan §2.7 |
| `presets.js` | 8 emulation + 12 mood parameter sets |
| `reference.js` | 11 embedded real palettes, read-only, plus the ΔE fit score |
| `export/` | `gpl pal hex lospec css json tres png` + `index.js` registry |
| `analysis.js` | Viénot dichromat matrices, OKLCH value view, `applyView`, ramp evenness (Phase 3) |
| `dither.js` | Floyd–Steinberg + Bayer 4×4/8×8, perceptual nearest-match (Phase 3) |
| `raster.js` | DOM-free RGB8 pixel buffer + drawing primitives — the scene surface (Phase 3, §10) |
| `layout/` | The picker: grid topologies, the neighbour-ΔE objective, 15 layout variants, rendering (Phase 4, §11) |

Phase 2/3 also added `src/ui/` (`app sliders swatches history io gallery`), `src/scenes/`
(`index util` + 8 category files, all DOM-free), `tools/serve.mjs`, and `tools/build.mjs`.
All of these are in the plan's §7 layout except `src/scenes/util.js` and the file below.

### Files the plan's §7 layout does not list

| File | Why it exists |
|---|---|
| `src/core/rng.js` | The plan puts the xorshift128 PRNG in `generate.js`, but `hues.js` needs it and `generate.js` imports `hues.js`. Splitting it out avoids the cycle. `generate.js` re-exports `makeRng`. |
| `src/core/pixelfont.js` | A 3×5 bitmap font. Needed by the headless renderer and by gallery scene 26 (text legibility). Renderer-agnostic: `drawText` calls a `plot(x, y)` callback. |
| `src/core/raster.js` | The pixel-buffer surface every scene draws into (§10). The plan assumed scenes take a `CanvasRenderingContext2D`; the narrow-interface option was taken instead. |
| `src/scenes/util.js` | Semantic-role accessors (`role`, `rampOfRole`, `shade`, `anchorDark/Light`, …) so scenes address colour by meaning, not index. |
| `tools/surface.mjs` | The Phase-1 swatch-sheet helper backing the *preset* sheets in `render.mjs`. Separate from `raster.js`, which backs the *scene* sheets — both small, different callers. |
| `src/core/layout/heap.js` | A binary min-heap. Capacity assignment and organic growth both need "cheapest pending item first" over ~10⁵ items and would be quadratic with a sorted array. |
| `src/scenes/usage.js` | Per-entry pixel counts across the depictive scenes, backing the picker's `usage` blob mode. It lives in `scenes/` because `core/` may not import `scenes/` (§11). |

---

## 3. Decisions that extend the plan

Each of these was forced by something that only shows up once the code runs.

### 3.1 The generator snaps parameters to the seed grid

`generatePalette` calls `snapParams`, not just `normalizeParams`. Seed payloads
quantise every parameter to 16 bits, so without snapping, `generatePalette(p).seed`
decoded and regenerated gave a palette a fraction of a step away from the original —
which defeats the point of §6 of the plan. Snapping makes the seed grid canonical, so
**palette and seed always agree exactly**. `palette.params` is therefore the snapped
set, which can differ from the input in the 5th decimal place.

### 3.2 Repair is cost-descent, not pairwise nudging

The plan describes nudging violating pairs apart and iterating to a fixed point. That
oscillates forever in the common case: a slot squeezed between two neighbours gets
pushed off one and immediately pushed back by the other, and neither pass ever
converges. `repair.js` instead scores each candidate position against **the whole
palette** and only accepts strict improvements. Because the only pairs a move affects
are the mover's own, every accepted move lowers the global cost by exactly the amount
it lowers the mover's — so the sweep provably terminates.

Three things sit on top of that:

- **`breaksRampOrder`** rejects any candidate that would move a ramp step past its
  neighbours. A ramp that is not monotonic in lightness has stopped being a ramp.
- **`relaxAlongLightness`** is a chain-breaking fallback. In a near-greyscale palette
  every colour is boxed in and no *single* move lowers the cost, but resolving the
  whole chain at once does. It sorts movable slots by lightness, spaces them, and keeps
  the result only if it genuinely reduces cost and preserves ramp order.
- **`LAYER_PRIORITY`** decides who yields. Bridges yield to everything — they are the
  remainder tier, so displacing one costs the palette least. Anchors never yield.

### 3.3 Constraint parameters that needed a scale

Two parameters are specified in the plan as `0–1` but constrain a quantity measured in
ΔE. The mappings chosen:

- `fg_bg_separation_min` → ΔE via `FG_BG_SEP_SCALE = 30` (exported from `repair.js`).
  Default 0.15 → 4.5 ΔE.
- `temperature_split` → shift multiplier `2 * value − 0.5`, range −0.5…1.5, default
  0.75 → 1.0. Below 0.25 the multiplier goes negative, which swaps the light and shadow
  targets — that is the "inverting it" the plan calls for, expressed inside a 0–1
  slider without stranding the neutral value at a range edge.

### 3.4 The perceptual hue warp

`perceptual_hue_spacing` blends toward a warp that pins the six sRGB primaries and
secondaries to evenly spaced positions, anchored on red. Red→yellow spans 80° of OKLCH
hue while yellow→green spans 33°, so even angular spacing over-samples orange and
under-samples the yellow-green region. Landmarks are computed at module load from the
actual corner colours rather than hard-coded, so they cannot drift out of sync.

### 3.5 A minimum ramp step

`rampLightness` guarantees at least `MIN_RAMP_STEP` (0.005) of lightness between
adjacent steps. Heavy `l_range_compress` otherwise collapses several steps onto the
same lightness, which leaves repair no room to separate them and makes hex uniqueness
unachievable.

### 3.6 `reduce-l-adjust` has a hard cap

That gamut mode is the only one that does not preserve lightness exactly. Its shift is
capped at `MAX_L_ADJUST = 0.02`; a larger budget let it reorder ramps whose steps are
separated mostly in chroma.

### 3.7 The gamut mapper's JND is tighter than CSS

CSS Color 4 accepts an early clipped result within 2.0 ΔE. This uses 0.1, because a
fixed ΔE budget buys a large *angular* error at low chroma, and the generator's
hue-shift invariants are asserted in degrees.

### 3.8 Hue-adaptive midtone lightness (`hue_lightness_follow`, added 2026-07-23)

The plan builds every foreground hue around one global `l_mid_base`. That is wrong for a
whole arc of hues: in sRGB, yellow/yellow-green/green/cyan only hold chroma at high
lightness (their gamut cusps sit at L ≈ 0.75–0.96), so requesting them at a shared mid grey
and gamut-mapping the overflow away turns them **olive**. Blue/purple/red cusps already sit
near mid grey (L ≈ 0.49–0.63) and are fine. PLAN §5 half-recognised this ("real palettes
don't put yellow and blue at the same L") but implemented only *random* `l_variance_per_hue`.

`slotColors` in `generate.js` now biases each hue's `lMid` toward `gamutCusp(hue).L`
(reusing the cusp lookup already in `gamut.js`), scaled by `hue_lightness_follow` and a
capped internal gain (`HUE_L_FOLLOW_GAIN`, 0.6, so even full follow leaves a highlight step
of headroom under the light anchor). Because the target is *each hue's own* cusp, one knob
self-corrects every hue by exactly the amount it needs — no per-hue parameters. It ships
**on at 0.5 by default**, which changes the default palette (and is what makes yellows reach
gold out of the box, including under Randomize). **Existing presets pin it to 0** via a loop
in `presets.js`, so each reproduces its originally-approved snapshot byte-for-byte — *except*
the ones whose intent is loud colour, which opt in with their own value: OKLAB Crayon (0.975),
Neon Cyberpunk (0.7), Toxic Swamp (0.55), Sunset Desert (0.4). See `COLOR_GUIDE.md` for which
hues the knob actually moves and by how much.

Two consequences worth knowing:
- **Seed strings grew** (one more field, appended per §6/§12.5). Preset *colours* are
  byte-identical; only the seed field changed, and the golden snapshots were re-recorded on
  that basis.
- **The fuzz's feasibility canary needed a cap.** At full follow, a foreground ramp can ride
  up into a still-saturated, lightness-shifted background (high `bg_chroma_mult` + positive
  `bg_lightness_offset`) closely enough that fg/bg separation is no longer geometrically
  reachable in a single-hue palette — genuine infeasibility, not a repair miss. `feasibleParams`
  in `test/fuzz.test.js` caps `hue_lightness_follow` at 0.6 for the strict canary; the full
  0–1 range is still fuzzed for well-formedness in the other three-quarters of cases. Same
  class of adjustment as §12.7.

### 3.9 Two parameter ceilings raised, and what the fuzz said about it (2026-07-23)

`l_mid_base` 0.80 → **0.92** and `l_variance_per_hue` 0.15 → **0.30**. The first was a real
blocker: 0.80 made high-key palettes impossible and stopped a ramp being centred on the gamut
cusp for the whole yellow→cyan arc (cusps at L 0.86–0.96). The second was measured — fitting real
reference palettes pinned it at the old ceiling, i.e. it permitted less spread than hand-made
palettes use. Two things to know:

- **Param ranges are part of the seed contract.** `u16ToParam` decodes `min + (u/65535)·(max−min)`,
  so changing a range reinterprets that field in every previously-saved `PAL1` string. Accepted
  deliberately here (the repo owner's call); saved `.json`, presets and exports store real values
  and are unaffected, and **no preset colour moved** — only seed strings changed. If a future
  range change must not break seeds, `PAL2` with the old decoder retained is the path PLAN §6
  anticipates.
- **Raising `l_mid_base` alone does not lift the midtone.** `rampLightness` clamps a ramp to fit
  *entirely* inside the anchor window, so with the default light anchor a 3-step ramp at a normal
  `l_step` is pushed back down and the midtone lands near L 0.74 whatever you asked for. Reaching
  the high cusps also needs `l_light_anchor` near 1.0 and a small `l_step` — the recipe and its
  measured output are in `COLOR_GUIDE.md`.

The widened ranges shifted the fuzz stream into one more corner: a background ramp squeezed
against the dark anchor falls back to `MIN_RAMP_STEP` (0.005), but near black **one legal 6-bit
step is worth ~0.024 of OKLab L** — five times the requested gap — so the two steps quantise to
whichever grid point is nearer and can land out of order. The ramp-ordering assertion now compares
the requested gap against the *measured* local grid step (`gridStepL` in `test/fuzz.test.js`)
instead of a flat tolerance, so it exempts only the pairs the grid provably cannot separate (~18%)
and still catches every real inversion. Asserting otherwise would be asserting that quantisation
can represent a distinction it cannot.

---

## 4. Performance

A 64-colour palette costs about 20 ms. The whole cost is the number of `realize()`
calls repair makes, since each one runs a gamut binary search. Three things keep it
survivable, and all three matter — removing any one roughly doubles the fuzz runtime:

- `inSrgb` tests the **linear-light** values, skipping three `Math.pow` calls per
  iteration of the binary search.
- `quantizeSrgb` in `error-weighted` mode linearises the six candidate channel values
  once instead of per combination.
- `makeRealize` memoises per palette generation. Repair re-evaluates the same candidate
  positions on every sweep, so the hit rate is high.

If a change makes `npm test` dramatically slower, look here first.

---

## 5. Locks vs overrides

Functionally identical in the pipeline — both are pinned before repair (so repair moves
everything else *around* them) and re-asserted after it, so an explicitly chosen colour
is never silently relocated. Neither is gamut-mapped or quantised; the hex is used
verbatim.

The difference is intent, and it is the UI's job in Phase 2:

- **Lock** — "keep this colour when I re-randomise." Captured from the current palette.
- **Override** — "this exact hex, because I chose it."

Both are encoded in the seed, so a palette with either still round-trips.

---

## 6. Known limitations — read before "fixing" these

**`min_delta_e` and `force_unique_hex` are best-effort.** Sixty colours all 15 ΔE apart
does not fit in sRGB; sixteen near-greys on a 3-bit grid does not either. When a
constraint cannot be met the palette still has exactly K entries and `warnings`
explains what was missed. **Failures are never silent — that is the actual contract.**
Do not add a throw here.

What *is* guaranteed and asserted strictly:

- Exactly K colours for every K in 4–64, every scheme, every hue count.
- Every preset and every K at default quality settings resolves with zero warnings.
- Every emitted colour is in gamut, on the bit-depth grid, and matches `#RRGGBB`.

**`gamut_map_mode: 'clip'` genuinely breaks things.** It reorders ramps and moves
colours past the anchors, because naive per-channel clamping moves hue and lightness
arbitrarily. That is the entire reason the plan keeps it — it is a demonstration, not a
usable mode. Tests exempt it from the ordering invariants and separately assert that it
*does* distort. If `clip` ever starts passing the preservation test, the test has gone
stale.

**Three presets set `min_delta_e: 3`** (Frozen Tundra, Underwater Cave, Overcast
Coast). Strong aerial perspective packs backgrounds into one narrow band; 4 is past the
packing limit at that contrast. This is art direction, not a workaround.

---

## 7. Verifying changes

```bash
cd palette && npm test
```

Full suite: 209 tests, ~5 minutes. The 10,000-case fuzz dominates. While iterating:

```bash
cd palette && PALETTE_FUZZ_N=200 npm test
```

```bash
cd palette && npm run render
```

Writes `out/presets/*.png` (labelled swatch sheets — role, hex, index), `out/strips/`
(raw 1px export strips), `out/contact-sheet.png`, `out/size-sweep.png`, `out/sizes/*.png`,
the gallery scenes (§10), the picker layouts — `out/layouts/<tag>/*.png` plus
`out/layout-sheet-<tag>.png`, with the ranking printed to stdout — the colour-space maps,
`out/maps/<tag>-<geometry>.png`, with the coverage figures printed, and the reference
recolouring, `out/recolor-sheet-<tag>.png` plus real animated GIFs in `out/recolor/`.
**Read these images.**
They catch things tests do not: a palette can
satisfy every invariant and still be ugly or off-brief. Both preset retunes in Phase 1
came from looking at the contact sheet, not from a failing test.

Golden snapshots live in `test/snapshots/`. An intentional algorithm change shows up as
a snapshot diff — review it, then re-record:

```bash
cd palette && UPDATE_SNAPSHOTS=1 npm test
```

---

## 8. Starting Phase 2 and Phase 3 *(historical — both are now built)*

> Phases 2 and 3 are complete. This section is the original pre-build guidance; the
> decisions it poses were resolved as recorded in **§9 (app)** and **§10 (gallery)** —
> the narrow-interface `Raster` option was taken. Kept for the reasoning, not as a to-do.

**Phase 2** is `tools/serve.mjs`, `index.html`, and `src/ui/`. Generate the sliders from
`PARAMS` — do not hand-write them, the schema carries `group`, range, `step` and a
`doc` string meant to be the tooltip. Enum parameters need dropdowns, bools need
checkboxes. Wire the seed field through `encodeSeed`/`decodeSeed` and mirror it into
`location.hash`.

**Phase 3 needs a decision made early.** Scenes are specified as `render(ctx, palette)`
where `ctx` is a `CanvasRenderingContext2D` in the browser, but they must also render
headlessly for `npm run render`. `tools/surface.mjs` is not that — it is a swatch-sheet
helper with a different API. Pick one before writing 34 scenes:

- give `Surface` a Canvas2D-compatible subset (`fillStyle`, `fillRect`, `save`,
  `restore`, `translate`) so the same scene code runs both places, **or**
- define a narrower drawing interface of your own and adapt it to Canvas2D in the
  browser.

The second is less work and less deceptive, but the plan's wording assumes the first.
Either way, scenes must stay DOM-free and must address colours through `entryFor` and
the semantic roles, not by index — that is what makes the gallery a real test rather
than a decoration.

`src/core/analysis.js` and `src/core/dither.js` (tasks 3.2, 3.3) do not exist yet and
several scenes depend on them. Build those first.

---

## 9. Phase 2 (the app) — how it is wired

The UI is vanilla ES modules, no framework. One rule holds it together: **`src/ui/` owns
the DOM, `src/core/` owns the colour**. Every UI module imports the same generator the
tests exercise; none of them re-implements colour logic.

### The one state object

`src/ui/app.js` holds the entire UI state as `{ params, locks, overrides }` and nothing
else. Everything visible is derived by one call — `generatePalette(params, {locks,
overrides})` — on every change. There is no separate "current palette" state to keep in
sync; `regenerate()` recomputes it and repaints the swatch grid, the sliders (re-synced
so presets/seeds/undo move them), the seed field and the meta line. This is why the app
has no stale-state bugs: there is only one source of truth and one derivation.

Sub-modules are dumb views built once and fed the palette:

| Module | Contract |
|---|---|
| `sliders.js` | `createSliders(el, {onChange})` → `{ render(params) }`. Built from `PARAMS`; never hand-written. |
| `swatches.js` | `createSwatches(el, actions)` → `{ render(palette) }`. `actions` = toggleLock/setOverride/clearOverride/copy. |
| `history.js` | `createHistory(el, {onRestore,onChange})` → push/replaceCurrent/undo/redo/canUndo/canRedo. |
| `io.js` | `createIO(dom, actions)` → `{ updateSeed, refreshSaves }`. Owns seed field, URL hash, presets, saves, import, exports. |
| `randomize.js` | `randomizeParams(current, rng)` — DOM-free so it is testable; the Randomize skip rules live here (see below). |
| `gallery.js` `picker.js` `recolor.js` | The three middle-pane tabs — 34-scene gallery (§10), picker (§11), reference recolouring (§12). |

### Decisions Phase 3/4 should not re-litigate

- **Locks vs overrides in the UI.** Both live in `state`, keyed by slot id. `toggleLock`
  captures the *current* hex into `locks`; the override editor (the hex input, or the
  `ovr` pill) writes an explicit hex into `overrides`. Loading a preset or resetting to
  defaults clears both (a new structure has different slot ids); loading a seed or JSON
  takes whatever they encode. Randomize keeps both — that is what "randomize respecting
  locks" means.

- **What Randomize rerolls lives in `src/ui/randomize.js`, not inline in `app.js`** — pulled
  out so it is unit-testable (`test/randomize.test.js`), because `app.js` touches the DOM.
  `randomizeParams(current, rng)` skips `color_count`, ramp lengths, hardware and quality
  params (`RANDOMIZE_SKIP`, by name) so the slot grid stays stable and valid, **and the whole
  `recolor` group** (`RANDOMIZE_SKIP_GROUP`, by *group*). Excluding the recolour params by
  group rather than by name is deliberate: the repo owner was bitten by Randomize rerolling
  their dither/downscale settings, which are output choices they set deliberately, and a
  group rule means any recolour parameter added later is covered without touching this code.

- **Randomize uses the seeded PRNG.** Per the no-`Math.random` rule, randomize seeds
  `makeRng` from `Date.now()` xored with a counter and draws every value from it. The
  entropy is in the seed, not in the value stream.

- **A slider drag is one history entry.** `sliders.js` fires `onChange(name, v,
  {coalesce})`: the first `input` of a drag opens a new entry, every later `input` and the
  closing `change` coalesce into it (`history.replaceCurrent`). Typing in the number box
  or any discrete action pushes a fresh entry.

- **The value-only strip** on each swatch is the neutral gray of the same OKLCH lightness
  (`oklchToSrgb(L,0,0)`), not a luminance average — it is the perceptual value check, so
  it must use L directly.

### `tools/serve.mjs` — the saves API

Dependency-free `node:http`. `GET/PUT/DELETE /api/saves[/name]`; everything else is a
static file from the repo root with path-traversal refused. Save names are constrained to
`[A-Za-z0-9 _-]{1,64}` (`safeSaveName`, exported and tested). PUT bodies must parse as
JSON before they touch disk. The app writes the JSON exporter's output, so a saved file is
a normal palette JSON that re-imports. `test/serve.test.js` boots it on port 0 and drives
the real HTTP surface.

### `tools/build.mjs` — the standalone inliner

The "trivial inliner" is a **flat import map of base64 `data:` URLs**, not a nested
bundle. It walks the module graph from `src/ui/app.js`, rewrites every *relative* import
specifier to a bare key (`mod:src/core/oklch.js`), and emits each module once as a
`data:text/javascript;base64,…` entry in a document-level `<script type="importmap">`.
Bare specifiers resolve through the import map (relative specifiers cannot resolve against
a `data:` URL, which is why the rewrite is mandatory), so the graph loads natively with no
runtime and no per-level base64 blow-up. Result: `dist/palette_creator.html`, ~203 KB, 27
modules. File-backed saves degrade gracefully there (the `/api/saves` fetch fails and the
saves UI disables itself); seeds, export and import all work.

**Verification gap to be honest about:** the browser tool used for GATE 2 blocks `file://`
navigation, so the standalone was driven over `http://…/dist/palette_creator.html`, not by
an actual double-click. The inlined graph is protocol-independent, but a real file:// open
was not exercised end-to-end.

---

## 10. Phase 3 (the gallery) — contracts for Phase 4 and beyond

### The scene interface (the ARCHITECTURE §8 decision, resolved)

The narrow-interface option was taken. Every scene is:

```js
{ id, title, category, width, height, render(surface, palette, opts), animated?, frames? }
```

`surface` is a **`Raster`** (`src/core/raster.js`) — a DOM-free RGB8 pixel buffer with
`set/get/rect/outline/line/disc/text/blit/scaled/toImageData/rows`. Scenes draw into a
fresh `Raster(width, height)`; the browser gallery paints it to a `<canvas>` via
`scaled(zoom).toImageData(ImageData)` + `putImageData`, and `tools/render.mjs` writes it
to PNG via `writePNG(path, r.w, r.h, r.data)`. **This is the shared surface for any future
headless-renderable visual** — the picker (Phase 4) should render into a `Raster` too.

Two rules make the gallery a real test, not decoration, and both are load-bearing:

1. **Scenes address colour through `src/scenes/util.js`**, never by palette index —
   `role(palette, 'foliage')`, `rampOfRole`, `anchorDark/Light`, `shade(ramp, t)`,
   `bgByDepth`, `neutrals`, `accents`. A scene that looks right on one palette then looks
   right on all of them because it asked for *the foliage colour*, not *entry 7*.
2. **The colour-vision view is a post-process**, not each scene's job. `applyView(raster,
   view)` (analysis.js) transforms the finished buffer for `value`/`protan`/`deutan`/
   `tritan`; scenes always draw in full colour. Scenes 3 (value) and 6 (colorblind board)
   *additionally* draw their own comparisons, which is intentional, not duplication.

### `analysis.js` and `dither.js`

- Dichromat matrices are **Viénot 1999**, applied in **linear** sRGB (protan/deutan share
  their first two rows by construction — that shared row *is* the confusion axis). The
  value view is the neutral gray of the same OKLCH L, matching the swatch strip in the UI.
- Dithering matches nearest colour by **ΔE_OK** (perceptual), not RGB distance; Floyd–
  Steinberg diffuses error in sRGB (classic look), Bayer nudges by a threshold offset then
  matches. Both are deterministic and emit only palette colours — asserted in tests.

### Gallery quirks worth knowing

- `gallery.js` coalesces redraws with `requestAnimationFrame`, so **a backgrounded/unfronted
  tab does not repaint** (rAF is paused there). This is correct for real use but means
  automated checks must front the tab first. Animation uses a separate `setInterval`.
- Scene sizes are fixed per scene (designed for K=64 worst case); smaller palettes just use
  fewer cells. The smoke test `test/scenes.test.js` renders all 34 across K=4..64 and every
  preset, asserting no NaN/crash and a non-blank surface — run it after any scene edit.
- `render.mjs` renders scenes for **two** palettes (`default` and `neon-cyberpunk`) into
  `out/scenes/<tag>/` plus `out/scene-sheets/<tag>-<category>.png`. The category sheets are
  the thing to actually read at the gate.

---

## 11. Phase 4 (the picker) — what the ranking actually measured

`src/core/layout/` + `src/ui/picker.js`. The picker consumes **only a `Palette`** (§1) and
renders into a **`Raster`** (§10), so the browser view and `tools/render.mjs` draw the same
pixels from the same code.

### The shape every variant shares

A variant is a pure `(ctx) => Int32Array` — one palette-entry index per grid cell. The
shared context carries the grid, the OKLab vectors, the ΔE matrix, the per-entry cell budget
and a seeded PRNG, so a variant decides **arrangement** and nothing else:

| Module | Role |
|---|---|
| `grid.js` | Four topologies (rect / torus / hex / disc), adjacency, positions, centroids |
| `score.js` | The objective, `coverage`, the five blob modes, budget apportionment |
| `assign.js` | Capacity assignment, run fills, `compactSwaps`, `ensureCoverage` |
| `som.js` `anneal.js` `hilbert.js` `mds.js` `voronoi.js` `grow.js` `structural.js` `mesh.js` | The fifteen variants |
| `render.js` | Labels → Raster, hit-testing, the layout contact sheet, the map slice sheet |
| `index.js` | The registry, `buildLayout`, `rankLayouts`, the baseline constants |
| `colorspace.js` | The §9.1 colour-space maps — *not* an arrangement variant, see below |

**Coverage is structural, not checked-and-hoped.** `targetCounts` gives every colour at
least one cell and `assignByCapacity` caps every colour at its budget, so "every colour
appears" and "blob sizes follow the blob mode" both fall out of construction. The tests
assert it anyway, for all 15 variants × 4 palette sizes × 5 blob modes.

### Three findings that cost real time — do not re-derive them

**1. A smooth colour field must not be committed cell-by-cell.** The obvious move for a SOM
is "assign each cell to the entry its codebook vector is nearest to". It scores *terribly*
(K=32: 5.95 versus 2.6 for the projection layouts). A trained map is a gradient, so a
colour's nearest-cells form a wide band, not a patch, and the budget cap then sprays the
overflow along the whole band. The fix is `territoryCentroids` — read each colour's
territory off the map, take its centroid as a **site**, then assign cells by *distance on
the grid*. The SOM keeps deciding what goes where; the blobs come out compact.

**2. Batch SOM, not online.** A palette is a few dozen samples. The online rule spends its
late, small-radius steps memorising individual colours and leaves the field speckled —
measurably worse than the PCA projection it was initialised from, i.e. training actively
made it worse. The batch update has no learning rate to decay and stays smooth.

**3. Greedy capacity assignment strands cells, and adjacent swaps cannot rescue them.** The
last cells placed take whatever budget is left, which marooned lone near-white cells inside
dark blobs — visible on the contact sheet, and exactly what the picker exists to prevent.
Strict-improvement swaps between *neighbours* can never fix it, because getting a cell home
takes a chain of moves and every individual link scores worse. `relocateOutliers` lets the
worst 2% of cells propose a swap with any cell on the grid. That one pass moved SOM-rect
from 3.75 to 2.88 mean and its worst neighbour from 83.7 to 43.2.

### The baseline bar, and why it is asserted over K ≥ 32

Task 4.8 requires every optimized layout to beat the ramp-rows baseline. Measured, that
claim is **true for K ≥ 32 and false below it** — and the reason is a property of the
problem, not a weakness in the variants:

```
mean neighbour ΔE, default parameters      K8    K16   K24   K32   K48   K64
  ramp-rows (baseline)                    1.43   2.20  2.82  3.84  6.09  7.28
  best optimized variant                  1.75   2.10  2.43  2.57  2.84  3.02
```

Ramp-rows lays hue-ordered ramps as blocks, and **rectangles tile a rectangle perfectly**.
With few colours the blocks are large and the ordering within a ramp is already near-minimal
ΔE, so the baseline is essentially optimal — at K=8 nothing beats it. As the budget grows,
the row banding forces unrelated hues together and it degrades badly, while the blob layouts
barely move. `BASELINE_SIZES = [32, 48, 64]` encodes that, and the small-K behaviour is
asserted in its own test rather than left as a silent gap.

Two classifications follow from measurement, not intent:

- **Hilbert (6) is `optimized: false`.** The plan specifies a boustrophedon fill, and a
  serpentine turns every colour into a strip spanning the grid; strips lose to blocks on
  perimeter no matter how good the 3-D ordering is. The ordering is fine — it is the 1-D
  commit that costs it. The 2-D Hilbert traversal that *does* have that locality is what
  seeds the annealer, where it works.
- **Treemap (13) is `optimized: false` but ranks mid-table**, for the same tiling reason the
  baseline does well. `optimized` marks what is held to the bar, not what scores well.

**Cross-topology scores are not perfectly comparable.** A hex grid has six neighbours per
cell and a torus has four everywhere (no boundary relief), so both are scored over more
edges than a bounded rect grid. The ranking is still the honest single number PLAN §9 asks
for, but a hex or torus variant is carrying a slightly harder scoring surface.

### Rendering: optimise coarse, render fine

Build cost scales worse than linearly with cell count — a 192×128 grid takes 4–14 seconds
per variant, a 288×192 grid takes 12–46. So the arrangement is solved on a **96×64** grid
(the slowest variant, toroidal SOM, builds in about a second) and the *image* is produced
at display resolution by `render.js`:

```
coarse cells -> upsample by `scale` -> curvature flow -> paint
```

Painting cells as solid blocks gives blob edges that can only step along the cell grid,
which reads as a staircase. The relaxation is a **mode filter** — each pixel takes the
label most of its neighbourhood holds — which is discrete curvature flow: protrusions
erode, notches fill, staircases become curves. Radius is deliberately small (2) with the
pass count scaled to the upsample factor; a large radius costs (2r+1)² per pixel and buys
nothing several cheap passes do not.

Three things this has to respect:

- **A blob may not be eroded below `AREA_FLOOR` of its area.** Smoothing can otherwise
  erase a one-cell colour outright, and "every colour is somewhere" is the whole promise.
  Each pass that shrinks a colour past the floor is reverted for that colour alone.
- **`rectilinear` variants are not smoothed at all** (Hilbert, ramp-rows, spiral, treemap).
  Their straight edges are the information; rounding a treemap's corners makes it wrong,
  not prettier. This was visibly wrong before the flag existed.
- **Disc layouts re-test their mask per output pixel**, so the rim is a true circle rather
  than a staircase of cell corners.

`renderLayout` returns the label map alongside the pixels, and `pickAt` reads *that* — so
the hover readout matches the smoothed shape on screen, not the coarse grid under it.

Grid resolution is the one knob that trades quality against build time. If the picker ever
feels slow, lower `DEFAULT_SIZE`; if edges look soft, raise it and drop `scale` to match.
Note that **mean-neighbour scores are not comparable across grid resolutions** — a finer
grid has proportionally fewer boundary edges, so every score falls. Compare within a
resolution only. `test/layout.test.js` pins its own small grid for exactly this reason.

### Edge modes — no black outlines by default

`edges` is `'none'` (default), `'shade'`, or `'seam'`. The default draws no outline at all:
blob boundaries are defined by colour contrast, which is what the reference art this was
modelled on does. `'shade'` is the pixel-artist move — the boundary is a darker,
**hue-shifted** colour *taken from the palette itself* (midpoint, L −0.12, hue +20°, snapped
to the nearest entry), so the outline reads as a shadow that belongs to the picture. Both
are asserted to introduce no colour outside the palette. `'seam'` is the flat dark line,
kept only for diagrams. `tools/render.mjs` writes both `none` and `shade` versions of every
layout and both contact sheets, because which reads better is a judgement to make by eye.

### Color-space maps vs. arrangement layouts (PLAN §9.1 vs §9.2)

The reference tool this look was modelled on (`retroactive.me/post/palette-analysis/`)
produces its hue-brightness rectangles and polar wheels by a **completely different
mechanism** from the Phase 4 layouts, and it is worth being precise about which, because
the two cannot be tuned into each other.

**What the reference does.** Take a standard HSL picker geometry — x or angle = hue, y or
radius = lightness, saturation fixed per slice — and for each output pixel compute the
color that position represents, then paint the **nearest palette color** to it. That is
all. Nothing is arranged, nothing is optimized, no cell grid exists.

This was verified by prototyping it before committing to the design; it reproduces the
reference panels closely, including the polar wheels.

| | Color-space map (§9.1) | Arrangement layout (§9.2) |
|---|---|---|
| What decides position | Fixed — hue/lightness, as in any picker | The optimizer; moves when the palette changes |
| Predictable | Yes — you know where to look | No — must be re-read each time |
| Every color shown | **No.** Measured 43–46 of 48 per slice | **Yes**, guaranteed by construction |
| Area per color | Its Voronoi cell in color space; can be a sliver | Controlled by the blob-size mode |
| Edge quality | Exact and smooth at any resolution, free | Cell grid, needs upsampling + curvature flow |
| Cost | One nearest-color search per pixel | Up to a second per build |

**Why the map's edges are free and the layout's are not.** A map is evaluated per output
pixel from a continuous function, so its region boundaries are exact wherever you sample
them. A layout is a discrete assignment to cells, so its boundaries can only follow the
cell grid, and everything in the rendering section above exists to hide that. Raising the
map's resolution costs one linear pass; raising the layout's costs quadratically.

**The coverage trade is the real decision, and it must not be papered over.** A map can
simply fail to show a palette color — it is nobody's nearest neighbour. Do not "fix" that
by forcing colors in; it would make position stop meaning what it says, which is the only
thing the map has over the layouts. Report the count (`45/48`), report the union across
slices, and let the arrangement layouts be the view that guarantees completeness.

**No outlines, in either family.** `edges: 'none'` is the default and the maps never draw
them at all. Verified rather than assumed: an `edges:'none'` render of a 48-color palette
contains exactly 48 distinct colors and zero foreign pixels. If outlines are ever seen in
output, the file being looked at is a `-shaded.png`, which `tools/render.mjs` writes beside
every plain one.

### Phase 4b — what the maps actually do (`colorspace.js`)

`buildColorMap(palette, {geometry, saturation, size})` returns a label per pixel plus the
coverage account; `buildMapSlices` runs the default four saturations and unions them;
`mapSheet` in `render.js` composes them. Four decisions are worth not re-deriving:

- **Hue spans an inclusive 0–360 across the rectangle**, so the leftmost and rightmost
  columns are literally the same hue. The alternative (a half-open span, so the map tiles
  seamlessly) makes "the edges are the same hue" true only in spirit and untestable as
  written. The duplicated column is invisible; the assertion is exact.
- **The wheel is white at the centre and black at the rim**, matching the rectangle's
  top-to-bottom lightness. The consequence is that the outermost ring is nearly black over a
  large area, because area grows as r² while lightness falls linearly. That is what
  "radius = lightness" means, and warping the radius to even it out would cost the map the
  one thing it has — a position that means exactly what it says.
- **Coverage is counted by colour, not by slot.** A palette may hold the same hex twice
  (`force_unique_hex` is best-effort, §6) and only the lower index can win a nearest-colour
  tie, so counting slots would under-report what is visibly on screen.
- **The sheet is composed in label space and painted once.** Slices and the swatch strip are
  written into one `Int32Array`, `paintLabels` turns it into pixels, and the text is drawn
  last over background pixels only. So hover, click-to-copy and export all read one buffer,
  and no drawing step can introduce a colour that is not in the palette.

**Measured coverage, default parameters at K=48** (`npm run render` prints this):

```
              union   s1.00   s0.70   s0.40   s0.12
  rect        48/48   45/48   46/48   46/48   26/48     mean ΔE 10.2 / 7.6 / 5.7 / 4.9
  polar       48/48   45/48   46/48   46/48   26/48     mean ΔE  9.6 / 7.2 / 5.4 / 4.6
```

A single slice reaches 45–46 of 48, as §9.1 predicts. **Four slices happen to reach
everything for most palettes** — over a 200-case parameter fuzz only 13 left anything
stranded, and never more than two colours. That is a measurement, not a guarantee: the strip
still has to exist, and `test/colorspace.test.js` forces the case by building a single
saturated slice rather than waiting for a palette that happens to fail.

**The strip is labelled, not just drawn.** The colours no slice reaches are written into the
sheet's label buffer, so they are hoverable and copyable exactly like the map itself. That is
what makes the coverage trade acceptable: nothing is unreachable from the default view, and
nothing had to be forced into the geometry to achieve it.

**The "which colours go where" bands (added 2026-07-23).** `layerBands()` in `render.js` groups
every entry by its `layer` and `mapSheet` draws them as labelled rows under the slices. This
exists because the map answers *where a colour is* but cannot answer *what it is for* — position
there means hue and lightness and nothing else, so an artist reading it has no way to tell a
background colour from a foreground one. The bands are composed into the **same label buffer** as
the maps, so they hover and click-to-copy through the one `pickAt` path rather than being a
picture. Two properties are asserted in `colorspace.test.js`: the bands partition the palette
exactly (every entry in exactly one band — an artist must never find a colour absent from the
guide), and every entry is hit-testable on the finished sheet.

The layer split is load-bearing, not labelling: `bg` is generated desaturated and pulled toward
`atmosphere_hue`, and `fg_bg_separation_min` is a hard constraint repair enforces between the two
sets (PLAN §2.3). The band captions say so, because "keep background colours off your sprites" is
the actual usage rule that separation buys. Note the four saturation slices are **not** a
foreground/background device — they are the coverage mechanism described above, and conflating
the two is the misreading the bands exist to prevent.

**The by-context maps (added 2026-07-23) — the bands' answer, given the map's readability.** The
bands say *which* colours do a job but are a flat list, losing the one property that makes a map
readable: similar colours adjacent, position meaning hue and lightness. So `buildColorMap` gained
an `entries` pool — restrict which slots may be painted and the geometry is untouched, which
turns the same machinery into a per-context chart where **a colour keeps the position it has on
the full map**. `MAP_CONTEXTS` in `colorspace.js` defines six (everything, sprites, scenery, sky,
UI, FX) as predicates over `entry.layer`, ramp position and `palette.semantics`, so they are
derived from the generator's own structure rather than invented; `buildContextMaps` builds a
slice set per context and `contextSheet` in `render.js` lays them out one row per context with
the bands underneath. Four decisions worth keeping:

- **Coverage is counted against the pool, not the palette.** A context chart cannot be blamed for
  not showing a colour that does not belong in it, so `coverageOf` takes the pool. In practice
  each context shows 100% of its own set — fewer candidates means every one wins some pixel.
- **Sprites and scenery come out near-complementary, and that is the feature.** It is
  `fg_bg_separation_min` made visible; the test asserts it directly (no `bg` offered for sprites,
  no `fg` for scenery, both keeping the anchors).
- **Contexts are dropped, not faked.** Under three colours, or a set identical to one already
  shown, and the row is not drawn — at K=8 there are no background rounds, so "sprites" *is* the
  whole palette and charting it twice would imply a distinction the palette does not have.
- **Still one label buffer.** The rows and the bands are composed into the same `Int32Array`, so
  hover and click-to-copy work everywhere on the sheet through the one `pickAt` path — verified
  in-browser, where the same screen position reports a foreground colour on the sprites row and a
  neutral on the scenery row.

**Cost:** about 130 ms to build all four slices at K=64 (a slice is one nearest-colour search
per pixel, ~100 ms of which is the sRGB→OKLab conversion and is independent of K). Comparable
to a layout build, and it is spent only while the picker tab is on screen. If it ever needs
to be cheaper, lower `DEFAULT_MAP_SIZE` — the map is a continuous function, so resolution is
a straight linear trade with no quality cliff.

**A CSS bug this uncovered.** The tab switch toggles `hidden`, but every pane it hides
carries a class that sets `display` — an author rule, which beats the browser's
`[hidden] { display: none }` whatever the specificity. The gallery and the picker were both
being laid out, and the second one was squeezed into what was left (46 px). `style.css` now
carries an explicit `[hidden] { display: none !important; }`.

### Picker UI notes

The middle pane is now tabbed (Gallery | Picker), and the picker's own view selector chooses
between the two families: **`map-rect` (the default), `map-polar`, and `layout`**. The
variant / blob / edge / scale controls belong to the layout view and are hidden with it, so
the default view carries one selector and a coverage readout and nothing else. Both families
return `{ raster, labels, w, h }`, so hover, click-to-copy and export are one code path over
`pickAt`. The PNG button exports whichever view is showing — a layout by scaling its cells
up, a map by *sampling it finer*, because that is what a continuous function makes cheap.

Two things worth keeping:

- **The picker draws synchronously**, unlike `gallery.js` which coalesces through
  `requestAnimationFrame`. That is why it renders correctly in a backgrounded tab where the
  gallery does not (§10). Layout builds are deferred instead by `setActive(false)` — nothing
  is rebuilt while the tab is hidden, and the palette change is applied on the way back in.
- **`usage` blob mode** needs pixel counts from the gallery. `src/core/` may not import
  `src/scenes/`, so `src/scenes/usage.js` measures it and `app.js` passes the counts in,
  memoised per `palette.seed`. Layout code takes them as plain data and stays scene-free.

---

## 12. Phase 5 (reference recoloring) — built

Spec is [PLAN.md](PLAN.md) §19. What follows is the reasoning behind the shape it took;
§12.5 records what the build actually settled.

### 12.1 Layering — where decoding is allowed to live

`src/core/` may not import a Node built-in (§2), and that constraint decides the shape:

- **Core takes pixels, not files.** The recolor functions operate on
  `{ width, height, data }` RGB8 buffers — the same shape `Raster` already uses. They know
  nothing about PNG, JPEG, GIF or the DOM, so `node --test` exercises the real algorithm.
- **Decoding happens at the edge.** In the browser, PNG and JPEG decode for free through
  `Image` + canvas. In tests there is no canvas, so a decoder is needed — but a test file
  may import `node:zlib` freely, so a small test-only PNG decoder is fine.
- **GIF is the exception and belongs in core.** LZW decode is pure arithmetic with no
  platform dependency, and putting it in `src/core/gif.js` means the browser and the tests
  share one implementation and a committed `.gif` fixture proves both.

~~**Decided: GIF is read-only and single-frame**~~ — **superseded 2026-07-22 by the repo
owner.** A GIF is recoloured *whole* and shown animated, so `src/core/gif.js` carries an LZW
**encoder** as well as the decoder. Both are pure arithmetic and belong in core by the same
argument that put the decoder there; having the pair also means the round trip is a test
rather than a hope. `gif_frame` survives only for outputs that cannot animate — the headless
PNG renderer and the single-frame export.

### 12.2 Why two modes is not a nicety

Per-pixel nearest matching decides each pixel independently, so a single source color can
resolve to different target colors in different places. On a photograph that is invisible
and correct. On pixel art it shreds exactly what makes it good — outlines stop being one
color, anti-aliasing seams break up, ramps lose continuity. The indexed path exists to make
the mapping a property of the *color*, not of the pixel. Getting this wrong would produce
output that passes every test and looks obviously bad, so the tests assert the property
directly: **a source color must map to the same target color everywhere it appears.**

`remap_preserve_order` (monotonic in lightness) is the knob that matters most in practice —
it is what lets a palette with completely different hues still read correctly, because the
value structure is what the eye reads first.

### 12.3 The "no command line" constraint — options and the open decision

This constrains delivery, not just UI. Three ways to satisfy it:

| Option | Adding reference images | Cost |
|---|---|---|
| **A. Double-click launcher** (`start.cmd`) that boots `tools/serve.mjs` and opens the browser | Server reads `palette/reference/`, and the app can also write dropped files there via the existing saves-style API | Small; keeps saves, keeps the folder as the source of truth |
| **B. Standalone `dist/palette_creator.html`**, opened by double-click | No server, so no folder access: images come in by drag-and-drop or a folder picker, and live only in the session unless re-added | Zero infrastructure, but nothing persists and the gallery is empty on each open |
| **C. Both** — launcher as the normal path, standalone as the portable one | Folder when served, drag-and-drop when not | Two code paths in the image source |

**Decided: C, with A as the normal path.** The reference folder persists and is git-tracked
exactly like `palette/saved/` already is, and a `.cmd` that is double-clicked is not a
command line. Option B alone cannot keep a library of reference images between sessions,
which is most of the value.

So there are two image sources and the UI must handle both without branching everywhere:

- **Served** (`start.cmd` → `tools/serve.mjs`): `GET /api/reference` lists the folder,
  `PUT` writes a dropped file into it. Mirrors the existing saves API, including the
  `safeSaveName` path-traversal guard — reuse it, do not write a second one.
- **Standalone** (`dist/palette_creator.html`): the fetch fails, the UI disables the
  persist affordance and keeps drag-and-drop working in-session. This is exactly how the
  saves UI already degrades (§9), so follow that pattern rather than inventing another.

The gallery therefore reads from an in-memory list that is *seeded* from the server when
one is present, not directly from the network.

**`start.cmd` is a restart, not just a start.** Double-clicking it while it is already
running must not fail on `EADDRINUSE` — that is how someone reloads after copying files into
`reference/`. So the launcher passes `--replace`, and `serve.mjs` gained two routes for it:
`GET /api/ping` (identifies the server — `{ app: 'palette-creator', pid, port }`) and
`POST /api/shutdown` (loopback callers only, and only wired up in the standalone `main()`, so
a server embedded in a test can never be told to stop). A `--replace` start pings the port,
and *only if a palette server answers* asks it to stand down and waits for the socket to free
— it never kills a stranger that merely picked 5173. The old process drops its keep-alive
connections and exits, because a process being replaced must not outlive the handover.
Belt and braces: if the port is held by something that is not us, `listenFrom` steps to the
next port instead. The whole handshake is exercised end to end against two real child
processes in `serve.test.js`.

**Copying files in by hand needs no restart either.** The **Rescan folder** button re-lists
`/api/reference` and reconciles: folder-origin cards are dropped and re-read wholesale (so a
file deleted on disk disappears), while session-only drag-drops are left alone. Dropped files
go through `PUT /api/reference` and then the same rescan, so a dropped file and a hand-copied
one end up on identical footing.

### 12.4 Committed fixtures

Generated reference images ship with the repo so the gallery is never empty and the tests
always have real data. They must include at least one **animated** GIF and one image with a
large color count (a synthetic photograph), because those exercise the two modes and the
frame-coherence requirement. Procedurally generated at build time is acceptable and
preferable to binary blobs, provided the generator is deterministic.

### 12.5 What the build settled

| Module | Role |
|---|---|
| `recolor/image.js` | The buffer contract, `uniqueColors`, `countUniqueColors`, `mapColors`, `downscale` |
| `recolor/indexed.js` | Source-palette → target-palette assignment, applied as a lookup |
| `recolor/quantize.js` | The §19.1 knobs translated into `dither.js` calls |
| `recolor/index.js` | `chooseMode`, `recolorImage`, `recolorFrames` |
| `recolor/samples.js` | The six built-in reference images |
| `recolor/swatches.js` | Extract a palette from an image (the external-palette targets) |
| `gif.js` | LZW decode **and** encode, whole animations both ways |
| `ui/recolor.js` | The gallery page, decoding at the edge, one timer for every animation |

**The image buffer is a `Raster`, not a new type.** §12.1 above described it as
`{ width, height, data }`; using `{ w, h, data }` instead is a deliberate deviation, because
`dither.js` — which task 5.4 is required to reuse — already takes a Raster, as do the scenes,
the PNG exporters and `tools/render.mjs`. A second image type differing in two property names
would need an adapter at every boundary and buy nothing.

**Four assignment strategies, one of which is a real optimisation.** `delta-e` is
nearest-each. `lightness-rank` is positional on both palettes sorted by L. `optimal` is a
rectangular assignment solved with the Jonker–Volgenant shortest-augmenting-path method, and
when the source overflows the target the roles are **swapped** — every target claims a
distinct source first, so the whole palette appears — with the leftovers taking their
nearest. `remap_preserve_order` is a dynamic program over both palettes sorted by lightness,
not a repair pass: `dp[j]` is the cheapest way to place the sources so far with the last at
rank ≤ j (or < j when `optimal` forbids repeats). The solver is checked against brute force
over every injective mapping on small matrices, which is the only way to know it is right.

**Frame coherence is why `recolorFrames` is not a `map`.** Deciding per frame lets a colour
whose share of the picture changes between frames land on a different target in each, which
reads as the palette flickering. The mapping is built once from the frames' *combined*
colours and then applied to each — the animated form of the property the indexed path exists
to guarantee, asserted directly in `test/gif.test.js`.

**The LZW encoder and decoder are verified against something other than each other.**
`test/gif.test.js` decodes a GIF assembled byte by byte in the test file, whose LZW payload
is written by an independent literal-code emitter — because testing a decoder only against
its own encoder proves the pair agree, which is exactly what can be wrong while both are
broken. (That fixture also documents a trap: a decoder grows its dictionary whether or not
the encoder uses the new entries, so "literals only" does *not* keep the code width fixed —
the fixture emits a clear code every two data codes to hold it.) The pair was then checked
against **Chrome's own GIF decoder** in the browser: our encoder's output loaded as an
`<img>` and drawn to a canvas came back pixel-identical to our decoder's, 0 of 768 pixels
differing.

**One performance trap in the decoder.** Finding the first character of a dictionary code by
walking its prefix chain is O(string length) per code, which made decoding a 40,000-pixel
frame take 76 seconds. `first[]` carries it forward as entries are added: 51 ms.

**The gallery is lazy, and it has to be.** Six built-in samples hid a scaling problem the
first cut walked straight into: a real reference library is not small. Measured on the
owner's — 82 files, most 512×512 GIFs of 20–189 frames — decoding *one* takes 1.3–1.9 s, so
loading them all up front froze the page for two minutes and re-recolouring them on every
slider drag was worse. So a card is created from its filename alone and does its work —
fetch, decode, recolour, paint — only when it scrolls into the viewport, and the animation
timer only advances cards that are both visible and filled. Two traps this hit:

- **The viewport is the `.scroll` pane, not the content list.** The list's own rect grows to
  the full content height, so measuring visibility against *it* counts every card as on
  screen and fetches the whole library at once — the exact thundering herd the laziness
  exists to prevent. `viewport = container.closest('.scroll')`.
- **Visibility is a rect sweep, not an `IntersectionObserver`.** IO delivers no callback when
  the page is not being composited — a backgrounded tab, and headless verification — so a
  gallery built on it silently loads nothing there. A `getBoundingClientRect` sweep on scroll
  (coalesced through a `setTimeout`, because rAF is paused in a background tab too) is a few
  rectangles and works everywhere.

**Colours are counted across frames in place.** `recolorFrames` decides the mode and builds
the indexed mapping from `uniqueColorsAcross(frames)`, which tallies every frame's pixels
into one map without concatenating them — a 189-frame 512×512 GIF is 49 M pixels, and joining
it into one buffer first would cost 147 MB for nothing. The mode is chosen from the union, so
a colour that appears only in a late frame still counts (asserted in `gif.test.js`).

**Reference images are generated, not committed.** `samples.js` produces six images from
fixed seeds — flat pixel art and synthetic photographs, still and animated, covering both
recolour paths in both forms. So the gallery is never empty, the standalone build has the
same set as the served app, the tests have real data, and the repository holds no binary
blobs. `palette/reference/` is for the *user's* images only.

**The parameters are appended after `seed`.** Field order is the seed payload's order, so
appending is the only safe edit (§6). The ten §19.1 knobs change no colour in the palette —
they decide how reference images are re-rendered into it — but they are seed-encoded like
everything else, so a pasted seed reproduces the whole view. Adding them lengthened every
seed string; the golden snapshots were re-recorded after confirming that all 20 presets'
**colours** were byte-identical and only the seed string had grown.

### 12.6 Recolouring into an external palette

The recolour target is normally the generated palette, but it can be a palette **extracted
from an image** the user loads into `palettes/` (via `/api/palettes`, the same handler as
`reference/`). `recolor/swatches.js` turns an image into a minimal palette object — just
`entries[].{rgb8, lab, hex}`, which is all the recolour pipeline reads — and `ui/recolor.js`
lets a **"Recolour into"** selector choose it. Three decisions worth keeping:

- **Extraction has two paths, because a designed strip and a photo are different things.** A
  strip ≤ 2px tall is authoritative — every distinct colour is a real entry, in left-to-right
  order, nothing merged or dropped, white end-blocks kept (the repo owner's correction: "the
  1 pixel strip won't have transition pixels, every color from it will be used"). Anything
  taller is de-aliased: near-duplicates merge by a tight ΔE, and the thin blended edge pixels
  are dropped by a coverage floor. The floor is calibrated for realistic wide-swatch strips;
  a pathologically narrow-swatch strip can leak a seam, which is why the 1px form is the
  documented clean input.
- **This is the real answer to "stop the recolour changing when I tune."** An external
  palette is a fixed object — it does not move when a slider moves — so the recolour holds
  completely still. Verified in-browser: selecting an external target and then changing a
  generated-palette slider leaves every recoloured card byte-for-byte identical. The recolour
  pipeline itself has **no randomness** (no `Math.random`, no RNG anywhere in `recolor/`);
  the only thing that ever moved a recolour was the generated palette underneath it.
- **The selector reuses the lazy machinery.** External palettes are tiny, so they are
  extracted eagerly (they drive the selector and the swatch preview), but the *cards* still
  fill lazily and re-recolour into `currentTarget()` when scrolled into view. Switching target
  marks every card stale; visible ones re-recolour at once, the rest when seen.

### 12.7 Two bugs the phase surfaced

Neither is in the recolour code; both were found because new parameters shifted the fuzz's
random stream into corners it had not previously reached.

- **`l_range_compress` could drag a ramp step past an anchor.** `rampLightness` clamped the
  compressed value into `[0,1]` rather than into the anchor window, so when the anchors sat
  on one side of mid grey — a "dark" anchor above 0.5 — the pull toward 0.5 escaped the
  bound the function's own doc comment promises. Now clamped to `[lo, hi]`. No preset or
  default palette changed; the snapshots confirm it.
- **The fuzz's "anchors are the extremes" assertion was overreaching.** It is now asserted
  only on the feasible cases, at fine bit depths, under `chroma-reduce`. Each restriction is
  a measurement, not a shrug: repair legitimately moves an anchor when the constraints are
  infeasible (a requested L of 0.10 became 0.46, with a warning saying so); near black one
  legal step outweighs the gap (a dark anchor at L=0.026 quantises to #000600 = L 0.106
  while a background requested *above* it quantises to #000000 = L 0); and `reduce-l-adjust`
  moves lightness to reach the gamut by design. `generate.test.js` still asserts the
  achieved ordering under default parameters, which is where it has to hold.

### 12.8 Context-aware recolouring (`recolor/context.js`, added 2026-07-23)

Recolouring was **purely colorimetric and layer-blind**: the pipeline read `entries[].rgb8 /
lab / hex` and nothing else, so even when the target was the generated palette — which carries
`layer` on every entry — that was discarded. A source *background* colour therefore landed
wherever the ΔE happened to be smallest, which is regularly a target *foreground* slot, and
`fg_bg_separation_min` (the one hard constraint repair enforces between the two sets, PLAN
§2.3) did not survive the trip.

`recolor_context` fixes that for the **indexed path only**. It is **off by default**; every
default in the block reproduces the old mapping byte for byte, asserted directly.

**What was measured before any of it was built**, because half of the idea does not work:

- **Source-context inference is not reliable, and shipping it as an authority would be
  dishonest.** Over the 264 decodable pixel-art PNGs in `reference/`, only **23%** have an
  identifiable flat backdrop; **33% have none at all** (median border share 0.32). A finished
  illustration frequently has no foreground/background distinction to find — in
  `sunset-default.png` the entire frame is sky. Signal AUCs for bg vs fg are weak
  individually: border share 0.77, own-border 0.73, coverage 0.68, edginess 0.27. Chroma looks
  perfect (AUC 0.000) but that number is **circular** — the ground truth came from our own
  generator, which *defines* `bg` as desaturated, so it says nothing about a stranger's image.
  Outline detection ("darkest colour abuts the most others") is right **33%** of the time. The
  animation signal is degenerate: 84–97% of pixels in real GIFs are static, so static-vs-moving
  finds *the moving element*, not the background.
- **So the inference is a starting point, not an authority.** The repo owner's call was to
  apply it to every image rather than abstain on the unclear ones, and accept that some come
  out wrong — a partly-assigned image would mix two mapping regimes in one picture. `manual`
  mode lets per-colour overrides win. Do not "improve" this into a confident classifier; the
  ceiling was measured and it is low.

**The target side is where the value is, and `MAP_CONTEXTS` is the wrong tool for it.**
`RECOLOR_CONTEXTS` is a **strictly disjoint** partition of `layer`, deliberately unlike the
picker's `MAP_CONTEXTS` (§11), which overlap on purpose so a *chart* shows a colour everywhere
it is usable. Here an overlap silently destroys the guarantee: if a source-fg and a source-bg
colour can both reach the same shared neutral, they still collide. Measured over 16
scene×palette pairs with oracle source labels:

```
                              separation   collapsed<2ΔE   cross-assign   fidelity cost
source art                      6.04 ΔE          —              —              —
layer-blind (the old default)   3.21 ΔE        12/16           19%          5.16 ΔE
oracle + MAP_CONTEXTS pools     3.54 ΔE        10/16            0%          5.92 ΔE
oracle + RECOLOR_CONTEXTS       10.29 ΔE        0/16            0%          6.07 ΔE
```

The overlapping pools recover almost none of the lost separation. The disjoint ones recover
all of it, at **+18% fidelity cost** — colours land further from where they would naturally go,
which is the trade `remap_context_bias` exposes rather than hides.

**Context is a surcharge on the cost matrix, not a separate per-pool assignment.** That is the
decision that keeps it orthogonal: `applyContextPenalty` adds a penalty to out-of-pool entries
of the one source-major matrix, so `delta-e`, `optimal` **and** the monotone
`remap_preserve_order` dynamic program all honour the pools without any of them learning what
a pool is. Consequences worth knowing:

- **`bias` 0 is exactly the old behaviour**, which is what makes the feature safe to leave
  wired up while off; **1** is `HARD_PENALTY` (1000, far beyond any real ΔE — `deltaEOK` is
  reported ×100); in between is `bias × SOFT_PENALTY` (25), a genuine preference crossed only
  when the match is much better the other way.
- **The soft range must be scaled to ΔE, and the first cut got this wrong.** Interpolating
  straight to `HARD_PENALTY` made bias 0.2 a 200 ΔE surcharge — already unpayable, since black
  to white is only 100 — so **every setting from 0.2 to 1.0 produced byte-identical output**.
  The knob was a placebo and every unit test still passed; it was caught by sweeping the knob
  and looking at the images. `SOFT_PENALTY` is 25 because that is where the real trade-offs sit
  (cross-pool ΔE gains measured at ~9 on the built-in samples), which spreads the transition
  across the middle of the knob's range instead of saturating at 0.2.
  `test/recolor-context.test.js` now asserts an intermediate bias produces a mapping that is
  neither the off one nor the hard one — the only shape of test that catches this.
- **At bias 1 the pools visibly cost texture, and that is the trade, not a bug.** On the
  built-in tileset the grass tile loses its two-tone dither and flattens, and the water tile
  goes magenta, because several source colours classify into one context whose pool cannot
  express them all. `out/recolor-sheet-default-context.png` is rendered beside the plain sheet
  so this is judged by eye rather than by the ΔE number. **Around 0.2–0.4 keeps the texture and
  still buys most of the separation** — worth reaching for on tile and terrain art.
- **The penalty is finite, not `Infinity`.** The Hungarian solver subtracts duals from costs
  and `Infinity - Infinity` is `NaN`, which would corrupt the assignment silently instead of
  failing loudly.
- **`lightness-rank` is a no-op for context**, exactly as it already is for `preserveOrder` —
  it is positional and never consults the cost matrix, so there is nothing to act on.
- **`remap_context_order`** decides what happens when `remap_preserve_order` is also on: on,
  the two combine (monotonic in L *and* pool-respecting); off, preserve-order wins outright and
  context stands down for that image. Both constraints at once leaves the assignment very
  little room, which is why it is a toggle and not a decision made for the user.
- **An external target palette falls back to the blind path.** A palette extracted from an
  image is deliberately just colours (§12.6), so `targetPools` returns **null** rather than
  five empty pools — which would penalise every target equally and change nothing but the
  numbers. A context whose pool is empty is likewise left alone.
- **Contexts are decided once across every frame**, like the mapping itself. Deciding per frame
  would let a colour whose share of the picture changes between frames change *job* between
  frames, which is the animated form of the flicker the indexed path exists to prevent.

**The parameters were appended** after `hue_lightness_follow` per the append-only rule (§6).
Byte 1 of a `PAL1` payload is `PARAMS.length`, so every seed string changed — 69 → 72 fields.
Verified before re-recording the snapshots, exactly as §12.5 did for the previous append: **no
preset colour moved** (0 of 21) and **every previously-saved seed still decodes to identical
colours**, because the decoder fills missing trailing fields with defaults.

---

## 13. Parameters from an image — the fitter (`fit.js`, added 2026-07-23)

`src/core/fit.js` inverts the generator: given a list of target hexes it searches the
parameter space for the set whose generated palette is perceptually closest. DOM-free and
seeded (via `rng.js`, never `Math.random`), so `node --test` exercises the real search and
the browser runs the same code.

- **`paletteFit(candidate, target)`** is a symmetric mean-nearest ΔE in OKLab — `coverage`
  (can the candidate express the target) + `fidelity` (does it waste colours), mean of the
  two. It is the same measure `reference.js` scores embedded palettes with; that file keeps
  its own tiny copy of `meanNearest` rather than importing `fit.js`, so it stays free of the
  generator in its module graph.
- **`inferStructure(target)`** guesses `color_count`, `hue_count` (greedy 35° hue clustering
  of the chromatic colours), `fg_ramp_length` and `neutral_count`. The search tunes *colour*,
  not structure, so a good guess here is what lets it converge. The crayon strip infers to
  K=20 / 5 hues / fg-ramp 3 / 3 neutrals — a structure the allocator hits exactly.
- **The search** is a random-restart hill climb. Restarts cycle the hue **scheme**
  deterministically (a scheme is the one thing a continuous search cannot nudge its way into,
  so every scheme gets a fair share of restarts); within a restart it perturbs 1–3 knobs by
  gaussian noise scaled to their ranges, keeping strict improvements, with the step size
  annealed down. ~6000 evals ≈ under a minute at small K.
- **`makeFitter(target, opts)`** exposes the search as a resumable stepper (`step(n)`,
  `bestScore`, `bestParams`, `done`). Core stays DOM-free; the UI (`io.js`) drives it in
  `requestAnimationFrame` slices so a ~minute-long fit never freezes the page, showing
  best-score-so-far, then applies the result exactly like a preset load. `fitParams` is the
  one-call wrapper the tests and offline preset-derivation use.

**How the OKLAB Crayon preset was made.** `fitParams` was run offline against the strip's
20 colours (the target hexes are in `presets.js`), reaching a mean ΔE of ~3.1 — the fitted
values were rounded and committed as the preset, and the strip itself embedded in
`reference.js` so the reference-compare scene can score against it. The UI "Fit to image"
button (`imagefile.js` decodes at the edge → `recolor/swatches.js` extracts → `fit.js`
searches) is the same pipeline for any dropped image.
