# Architecture and handoff notes

What [PLAN.md](PLAN.md) does not say, because it was written before the code existed.
Read the plan first — it is the specification. This file records the **contracts the
later phases build on** and the **decisions that extend or reinterpret the plan**, with
the reasoning, so the next person does not have to re-derive them or undo them by
accident.

Status: **Phases 1 (core), 2 (app) and 3 (gallery) complete and gated.** Phase 4 (the
artist's-palette picker) not started. Task-by-task state is in [PROGRESS.md](PROGRESS.md).
Phase 2's contracts are in §9; Phase 3's (scene interface, `Raster`, scene `util.js`) are
in §10.

Everything needed to continue this build is inside the repository. No document here
refers to a path outside it, to a machine-specific location, or to notes kept anywhere
else.

### Edits made to PLAN.md after it was written

`palette/PLAN.md` started as a copy of the original planning document. Five changes
were made so the committed copy is self-contained and does not mislead:

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

Full suite: 176 tests, ~4.5 minutes. The 10,000-case fuzz dominates. While iterating:

```bash
cd palette && PALETTE_FUZZ_N=200 npm test
```

```bash
cd palette && npm run render
```

Writes `out/presets/*.png` (labelled swatch sheets — role, hex, index), `out/strips/`
(raw 1px export strips), `out/contact-sheet.png`, `out/size-sweep.png`, and
`out/sizes/*.png`. **Read these images.** They catch things tests do not: a palette can
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

### Decisions Phase 3/4 should not re-litigate

- **Locks vs overrides in the UI.** Both live in `state`, keyed by slot id. `toggleLock`
  captures the *current* hex into `locks`; the override editor (the hex input, or the
  `ovr` pill) writes an explicit hex into `overrides`. Loading a preset or resetting to
  defaults clears both (a new structure has different slot ids); loading a seed or JSON
  takes whatever they encode. Randomize keeps both — that is what "randomize respecting
  locks" means — and deliberately skips `color_count`, ramp lengths, hardware and quality
  params (`RANDOMIZE_SKIP` in `app.js`) so the slot grid stays stable and valid.

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

## 11. Starting Phase 4 (the artist's-palette picker) — for the next agent

Phase 4 (PLAN §9, tasks 4.1–4.10) is `src/core/layout/` + `src/ui/picker.js`. Nothing in
it is written yet. What already exists that you should build on, not reinvent:

- **Render into a `Raster`** (`src/core/raster.js`), exactly like scenes — then the layout
  variants render both in the browser picker and headlessly in `tools/render.mjs`. Add a
  picker **contact sheet** to `render.mjs` mirroring `sceneSheet()` there, and read it at
  the gate. `writePNG(path, r.w, r.h, r.data)` writes a Raster to PNG.
- **Colour distance** is `deltaEOK(labA, labB)` on `entry.lab` (already on every Entry),
  from `src/core/oklch.js`. The picker arranges `palette.entries`; a cell's colour is an
  Entry, so use `entry.lab` for scoring and `entry.rgb8`/`entry.hex` for drawing.
- **Determinism**: use `makeRng(seed)` from `src/core/rng.js` for annealing and any
  stochastic layout — **never `Math.random`** (tested project-wide). Anneal from the
  palette's own seed so a layout is reproducible.
- **Scoring** (`score.js`, task 4.1): mean and worst neighbour ΔE over the grid adjacency,
  plus the blob-sizing modes (default *perceptual isolation* — area grows with a colour's
  mean ΔE to its nearest palette neighbours). The test bar (task 4.8) is concrete: full
  coverage / no holes, annealing deterministic, and **every optimized variant must beat the
  ramp-rows baseline** (variant 11) on mean-neighbour ΔE. Write that as a real assertion.
- **UI**: `picker.js` is a new view. The layout is currently three panes (Parameters |
  Gallery | Palette+I/O); add the picker either as a second tab on the gallery pane or a
  toggle in its toolbar. It needs a variant selector, blob-size mode, hover readout, click-
  to-copy, and high-res + contact-sheet PNG export (reuse the `download()` helper pattern in
  `io.js`, and the picker renders its own Raster to export).
- The picker consumes **only a `Palette`** (ARCHITECTURE §1). Don't reach into generation
  internals; `palette.entries` + `entryFor` is the whole surface you need.
