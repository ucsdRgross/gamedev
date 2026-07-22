# Architecture and handoff notes

What [PLAN.md](PLAN.md) does not say, because it was written before the code existed.
Read the plan first — it is the specification. This file records the **contracts the
later phases build on** and the **decisions that extend or reinterpret the plan**, with
the reasoning, so the next person does not have to re-derive them or undo them by
accident.

Status: **Phase 1 (core) complete and gated.** Phases 2–4 not started.
Task-by-task state is in [PROGRESS.md](PROGRESS.md).

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

### Three files the plan's §7 layout does not list

| File | Why it exists |
|---|---|
| `src/core/rng.js` | The plan puts the xorshift128 PRNG in `generate.js`, but `hues.js` needs it and `generate.js` imports `hues.js`. Splitting it out avoids the cycle. `generate.js` re-exports `makeRng`. |
| `src/core/pixelfont.js` | A 3×5 bitmap font. Needed by the headless renderer now and by gallery scene 26 (text legibility matrix) later, so it belongs in `core` rather than `tools`. Renderer-agnostic: `drawText` calls a `plot(x, y)` callback. |
| `tools/surface.mjs` | An RGB pixel buffer with `rect`/`outline`/`text`/`blit`, backing `render.mjs`. **Phase 3 will need more than this** — see §8. |

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

Full suite: 140 tests, ~4.5 minutes. The 10,000-case fuzz dominates. While iterating:

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

## 8. Starting Phase 2 and Phase 3

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
