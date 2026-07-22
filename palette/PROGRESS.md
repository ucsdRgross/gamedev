# Build Progress

Source of truth for what is done. Check off each task **the moment its "done when"
condition is actually met** — a green test, not a written file.

If this file is missing or looks stale, rebuild it using the state-detection
procedure in [PLAN.md](PLAN.md) §18. Verify with `npm test`, never by trusting
that a file exists.

## Resume here → task 5.1

Phases 1–4b are complete and gated. **One further phase is specified and not started:**

- **Phase 5 — reference recolouring** ([PLAN.md](PLAN.md) §19, design notes in
  [ARCHITECTURE.md](ARCHITECTURE.md) §12). Recolour a folder of reference images into the
  generated palette and show them all on one page.

The delivery question ("no command line anywhere") **is settled**: option C, launcher as the
normal path — see ARCHITECTURE §12.3, which also records the two image sources the UI has to
handle and the degrade-in-standalone pattern to follow.

## Phases 1–4b are complete and gated.

`npm test` is green at **228 tests** (~4.5 minutes; the 10,000-case fuzz dominates).
`npm start` runs the app: parameters, the 34-scene gallery, and the picker — colour-space
maps by default, the 15 arrangement layouts behind the view selector.
`npm run render` writes every preset, scene, layout and map to `out/`, and prints the layout
ranking and the map coverage figures. `npm run build` produces the 463 KB single-file
`dist/palette_creator.html`, picker included.

**Before touching `src/core/layout/`, read [ARCHITECTURE.md](ARCHITECTURE.md) §11** — it
records what the ranking actually measured, the three dead ends that cost real time, why
Hilbert and treemap are classified the way they are, and why the baseline bar is asserted
over K ≥ 32 rather than at every size.

### Environment note (this machine, 2026-07-22)
Node lives at `C:\Program Files\nodejs` and is **not on the tool-shell PATH** — prepend it
on every command: `$env:Path = "C:\Program Files\nodejs;$env:Path"`.

Node was upgraded from v20.18.0 to **v26.4.0** (`winget install --id OpenJS.NodeJS`) on
2026-07-22, because the `test` script (`node --test test/*.test.js`) needs the runner's
built-in glob expansion: npm runs scripts through `cmd.exe` on Windows, which does not
expand globs, and Node 20's runner does not either — so `npm test` silently failed to find
any test file. Node ≥ 22 expands it internally. **Do not downgrade below Node 22.**

`npm` must be run from `palette/`, not the repo root — there is an unrelated `package.json`
in the user's home directory that npm walks up to and finds instead.

### Working notes

- `npm test` runs the full 10,000-case fuzz and takes about 3 minutes. While
  iterating, shorten it: `PALETTE_FUZZ_N=200 npm test`.
- Golden snapshots live in `test/snapshots/`. When an algorithm change is
  intentional, review the diff and re-record with `UPDATE_SNAPSHOTS=1 npm test`.
- Generate the sliders from `PARAMS` in `src/core/params.js` — it is the single
  source of truth and already carries group, range, step and a tooltip string.
  Hand-writing the UI duplicates it and the seed codec will drift out of sync.
- `npm run render` and **look at the output**. Both preset retunes in Phase 1 came
  from reading the contact sheet, not from a failing test.

---

## Phase 1 — Core (headlessly verifiable, no UI)

- [x] **1.1 Scaffold** — `package.json` (`type: module`; scripts `test`/`start`/`build`/`render`), `.gitignore`, `README.md`. *Done when:* `npm test` runs without erroring.
- [x] **1.2 PNG encoder** — `tools/png.mjs` using `node:zlib`. *Done when:* an 8×8 RGB PNG round-trips.
- [x] **1.3 Color math** — `src/core/oklch.js`: OKLCH↔OKLab↔linear sRGB↔sRGB, hex parse/format, `deltaEOK`, WCAG luminance and contrast.
- [x] **1.4 Color math tests** — `test/oklch.test.js`: dense round-trip grid, published reference values, known contrast pairs. *Done when:* green.
- [x] **1.5 Gamut mapping** — `src/core/gamut.js` per PLAN §2.4.
- [x] **1.6 Gamut tests** — `test/gamut.test.js`: all output in-gamut; **hue and lightness preserved within tolerance**. *Done when:* green.
- [x] **1.7 Quantization** — `src/core/quantize.js` per PLAN §2.6, including `error-weighted`.
- [x] **1.8 Quantization tests** — legal-grid membership for every R/G/B bit combination 1–8. *Done when:* green.
- [x] **1.9 Parameter schema** — `src/core/params.js`: all ~50 parameters from PLAN §5. Single source of truth for UI sliders and seed field order.
- [x] **1.10 Hue generation** — `src/core/hues.js`: 7 schemes, perceptual spacing, jitter, all `shift_direction` modes.
- [x] **1.11 Ramps** — `src/core/ramp.js`: lightness curves, chroma Gaussian + directional falloff, all three `shift_model` variants.
- [x] **1.12 Allocator** — `src/core/allocate.js`: derived hue-count table + 12 partially-fillable rounds (PLAN §3).
- [x] **1.13 Repair** — `src/core/repair.js`: `min_delta_e`, `fg_bg_separation_min`, `force_unique_hex`, iterated to fixed point.
- [x] **1.14 Roles** — `src/core/roles.js`: stable ordering + semantic auto-assignment.
- [x] **1.15 Pipeline** — `src/core/generate.js`: pure `params -> Palette` in PLAN §2.7 order, plus xorshift128 PRNG (`src/core/rng.js`).
- [x] **1.16 Generator tests** — exact count for **every** K in 4–64 across all schemes; anchor extremes; hue-shift direction; ramp monotonicity; `min_delta_e`; anchor contrast; fg/bg separation; hex format. *Done when:* green.
- [x] **1.17 Seed codec** — `src/core/seed.js`: `PAL1` encode/decode with locks and overrides (PLAN §6).
- [x] **1.18 Seed tests** — round-trip over randomized parameter sets; forward-compatibility. *Done when:* green.
- [x] **1.19 Presets** — `src/core/presets.js`: 8 emulation-flavored + 12 mood parameter sets.
- [x] **1.20 Reference palettes** — `src/core/reference.js`: 11 embedded real palettes + ΔE fit score.
- [x] **1.21 Exporters** — `src/core/export/`: gpl, pal, hex, png, json, css, tres, lospec.
- [x] **1.22 Export tests** — every format parses back to identical colors; `.tres` valid; PNG strip decodes to exactly K pixels. *Done when:* green.
- [x] **1.23 Fuzz tests** — 10,000 randomized parameter sets, all invariants hold. *Done when:* green.
- [x] **1.24 Snapshots** — golden hex output per preset + cross-process determinism.
- [x] **1.25 Headless renderer** — `tools/render.mjs` emitting palette strips for every preset to `out/`.
- [x] **1.26 GATE 1** — `npm test` green; `npm run render` produces PNGs; **read the PNGs and confirm the palettes look correct**; report to user.

## Phase 2 — App

- [x] **2.1 Dev server** — `tools/serve.mjs`: static hosting + `GET/PUT/DELETE /api/saves`. Covered by `test/serve.test.js` (7 tests: CRUD round-trip, traversal refusal, bad-name/bad-body/404). *Green.*
- [x] **2.2 Shell** — `index.html`, `src/style.css`: three-pane layout (params / palette / save+export). Computed style confirmed `display:grid`, 3 panes, dark theme.
- [x] **2.3 Sliders** — `src/ui/sliders.js`, generated from `PARAMS`, grouped/collapsible, doc string as tooltip. 48 range + enum/bool controls rendered from schema.
- [x] **2.4 Swatch grid** — `src/ui/swatches.js`: role, hex, OKLCH readout, value-only strip, lock toggle, inline override editor, semantic tags.
- [x] **2.5 History** — `src/ui/history.js`: undo/redo + 20-deep clickable strip; slider drags coalesce to one entry. Undo/redo/restore driven and confirmed.
- [x] **2.6 I/O** — `src/ui/io.js`: seed field + `#seed=` URL-hash sync, preset dropdown, saved dropdown backed by `/api/saves`, JSON import, all 8 export buttons.
- [x] **2.7 Wiring** — `src/ui/app.js`: live regeneration on any change; randomize respects locks/overrides (uses seeded PRNG, never `Math.random`).
- [x] **2.8 Standalone build** — `tools/build.mjs` → `dist/palette_creator.html`. Flat import-map + base64 data-URL modules. Loads and generates with no server (verified over http; file:// double-click not drivable via the browser tool but is protocol-independent).
- [x] **2.9 GATE 2** — drove the UI in the browser: every slider moves output, seed round-trips exactly, save/load/delete hit the dev server, all 8 exports produce correct files, randomize keeps locked colours, override + undo/redo + presets + reset all work. Reported to user.

## Phase 3 — Test visual gallery

- [x] **3.1 Scene registry + gallery** — `src/scenes/index.js` (34 scenes, 8 categories) + `src/ui/gallery.js`: scrollable, category filter, colour-vision view select, zoom, animate toggle, drag-drop photo quant. Driven in-browser.
- [x] **3.2 Analysis module** — `src/core/analysis.js`: Viénot dichromat matrices (linear-RGB), OKLCH value view, `applyView`, ramp evenness. `test/analysis.test.js` green.
- [x] **3.3 Dithering module** — `src/core/dither.js`: Floyd–Steinberg + Bayer 4×4/8×8, perceptual nearest-match. `test/dither.test.js` green.
- [x] **3.4 Scenes 1–6** — `src/scenes/structure.js`: swatch grid, ramp strips, value view, OKLCH scatter, ΔE heatmap, colorblind board.
- [x] **3.5 Scenes 7–10** — `src/scenes/form.js`: lit spheres per ramp, iso cube, cylinder, material studies.
- [x] **3.6 Scenes 11–19** — `src/scenes/sprites.js`: 16/32 char, outline modes, sprite-over-every-bg, palette-swap, items, combat, skin, foliage.
- [x] **3.7 Scenes 20–24** — `src/scenes/worlds.js`: parallax, dungeon, day/dusk/night, tileset, full screenshot.
- [x] **3.8 Scenes 25–26** — `src/scenes/ui.js`: UI mockup + WCAG text-legibility matrix.
- [x] **3.9 Scenes 27–31** — `src/scenes/gradients.js`: dither pairs, Bayer ramps, sky gradient, 1px noise, zoom.
- [x] **3.10 Scene 32** — `src/scenes/motion.js`: animated water cycle / torch flicker / day-night sweep.
- [x] **3.11 Scene 33** — `src/scenes/benchmark.js` photo-quant: 3 procedural references (sphere/flesh/hazy) + gallery drag-drop.
- [x] **3.12 Scene 34** — `src/scenes/benchmark.js` reference-compare: our palette vs 2 nearest embedded refs with ΔE fit scores.
- [x] **3.13 Extend renderer** — `tools/render.mjs` writes every scene ×2 palettes to `out/scenes/` + 8 category contact sheets to `out/scene-sheets/`.
- [x] **3.14 GATE 3** — rendered all scenes, read the PNGs (all 8 category sheets), confirmed the live gallery in-browser (filter/view/zoom/anim/palette-follow). Reported to user.

## Phase 4 — Artist's-palette picker

- [x] **4.1 Scoring** — `src/core/layout/score.js`: mean/worst neighbor ΔE + boundary-crossing fraction, `coverage`, all 5 blob modes, `targetCounts` apportionment. Plus `grid.js` (4 topologies, adjacency, positions), `assign.js` (capacity assignment, run fills, `compactSwaps`), `heap.js`. `test/layout-score.test.js` green (15 tests).
- [x] **4.2 SOM** — `som.js`: **batch** Kohonen map over rectangular, toroidal, hexagonal and disc grids (variants 1–4), committed via territory centroids + shape relaxation. *(See ARCHITECTURE §11 — the online rule and direct field-commit were both tried and are measurably worse.)*
- [x] **4.3 Annealing** — `anneal.js`: seeded swap optimizer (5), 2-D-Hilbert start, boundary-biased proposals, shrinking window, strict-improvement finish. Deterministic under a fixed seed; asserted.
- [x] **4.4 Hilbert** — `hilbert.js`: 3-D Hilbert index (Skilling) + boustrophedon fill (6), plus the 2-D cell traversal the annealer starts from. Bijection and adjacency asserted.
- [x] **4.5 Projection** — `mds.js` + `voronoi.js`: classical MDS via power-iteration PCA, capacity Voronoi (7), Lloyd relaxation with torus-correct circular centroids (8).
- [x] **4.6 Organic** — `grow.js`: ΔE-weighted multi-source Dijkstra with seeded per-cell jitter (9), plus straggler settling.
- [x] **4.7 Remaining** — `structural.js` (polar wheel 10, ramp-rows baseline 11, value spiral 12, squarified treemap 13, Lambert sphere unwrap 14) + `mesh.js` (Bowyer–Watson Delaunay with barycentric blending, 15).
- [x] **4.8 Layout tests** — `test/layout.test.js` green (18 tests): full coverage and no holes for every variant × K × blob mode; every optimized layout beats the ramp-rows baseline over the K ≥ 32 sweep **and outright at K = 64**; annealing deterministic under a fixed seed. **Read ARCHITECTURE §11 before changing this bar** — the small-K behaviour is asserted deliberately, not overlooked.
- [x] **4.9 Picker UI** — `src/ui/picker.js` + a tabbed middle pane (Gallery | Picker): variant selector, blob-size mode, cell size, hover readout (role · hex · OKLCH) with a live swatch, click-to-copy, high-res PNG export and contact-sheet export. `src/core/layout/render.js` draws the layout and the sheet; `tools/render.mjs` writes `out/layouts/<tag>/` + `out/layout-sheet-<tag>.png` and prints the ranking. `src/scenes/usage.js` supplies the `usage` blob mode's counts.
- [x] **4.11 Look pass** (added after gate 4, from reference art) — **no black outlines**: `edges` is now `none` (default) / `shade` (a darker hue-shifted colour taken from the palette itself) / `seam`, and `render.mjs` writes both `none` and `shade` versions of every layout and contact sheet. **Smooth edges**: layout grid raised to 96×64 and rendering upsamples then relaxes boundaries with curvature flow, so blobs have clean curves instead of staircases; disc rims are true circles; `rectilinear` variants are exempt so their straight edges survive. Made affordable by capping the outlier-rescue budget, which was the quadratic term. See ARCHITECTURE §11.
- [x] **4.10 GATE 4** — `npm test` green (208). Rendered and **read** both layout contact sheets (`out/layout-sheet-default48.png`, `out/layout-sheet-neon.png`); reading the first one is what exposed the stranded-cell bug that `relocateOutliers` now fixes. Drove the picker in-browser: all 15 variants render with scores identical to the headless run, all 5 blob modes change blob areas as intended (spread 1.2× equal → 15.7× usage), all 4 cell sizes, hover readout and swatch correct, click-to-copy falls back cleanly when the clipboard is blocked, both PNG exports produce valid files, and the layout is not rebuilt while the tab is hidden. Verified in the standalone build too. Ranked scores reported to the user.

## Phase 4b — Colour-space maps (PLAN §9.1)

The default picker view. Standard HSL picker geometry, every pixel painted with the nearest
palette colour. Rendered per output pixel, so edges are exact and smooth for free and there
is no cell grid, no upsampling and no smoothing pass. **No outlines, ever.**

Measured coverage at K=48, both geometries: **45–46 of 48 per slice, 48/48 across the four
default slices.** The per-slice shortfall is the design working as specified — do not "fix"
it by forcing colours in; that is what the swatch strip is for.

- [x] **4b.1 Colour-space sampling** — `src/core/layout/colorspace.js`: `hslToSrgb`, `mapSample`, `buildColorMap`, `buildMapSlices`, `mapPickAt`, `mapFidelity`. Hue spans an **inclusive** 0–360 across the rectangle so the two side columns are literally the same hue; the wheel is white at the centre and black at the rim. Coverage is counted by *colour*, not by slot. See ARCHITECTURE §11 "Phase 4b" for why each of those is the way it is.
- [x] **4b.2 Map tests** — `test/colorspace.test.js` green (14 tests): HSL against its published definition, both geometries asserted literally (side columns identical, top row is white's nearest colour and bottom row is black's, the disc's corners unpainted, hue 0 up and clockwise), only palette colours emitted with a deliberately non-palette background to catch foreign pixels, `shown`/`missing` checked against the actual pixels, determinism, and resolution changing sampling without changing geometry.
- [x] **4b.3 Slices + coverage** — `mapSheet` in `render.js` composes the four slices in **label space** and paints once, so the sheet cannot introduce a foreign colour and every pixel on it is hit-testable. Colours no slice reaches get a labelled swatch strip beside the maps — hoverable and copyable, not merely visible. `tools/render.mjs` writes `out/maps/<tag>-<geometry>.png` and prints the coverage table.
- [x] **4b.4 Picker integration** — a view selector (`Map — hue × lightness` / `Map — colour wheel` / `Arrangement layout`) with maps first and the layout controls hidden with their view. Hover, click-to-copy and PNG export are one code path over `pickAt` because both families return `{ raster, labels, w, h }`. Maps export by sampling finer rather than scaling up. Fixed a real CSS bug found on the way: `[hidden]` was losing to the class rules that set `display`, so the gallery and picker were both being laid out (ARCHITECTURE §11).
- [x] **4b.5 GATE 4b** — `npm test` green (228). Rendered and **read** `out/maps/default48-{rect,polar}.png` and `out/maps/neon-*.png`; the first read caught the em-dash drawing as a box glyph. Drove the picker in-browser: maps are the default view, both geometries render, hover readout matches the pixel under the cursor exactly (checked against `getImageData`), background reads as nothing, click-to-copy degrades cleanly, view switching and layout controls behave, both exports produce valid PNGs, and the map follows preset and slider changes. Coverage figures reported to the user.

## Phase 5 — Reference-image recolouring (PLAN §19)

- [ ] **5.1 Image buffer contract** — recolour operates on `{ width, height, data }` RGB8 buffers in `src/core/`; no DOM, no Node built-ins, no file formats. Decoding stays at the edges (ARCHITECTURE §12.1).
- [ ] **5.2 Indexed remap** — `src/core/recolor/indexed.js`: extract source colours, map source palette → target palette once, apply as a lookup. `remap_match` (delta-e / lightness-rank / optimal), `remap_preserve_order`, `remap_overflow`.
- [ ] **5.3 Indexed tests** — output contains only target colours; **a source colour maps to the same target colour everywhere**; `remap_preserve_order` is genuinely monotonic in lightness. *Done when:* green.
- [ ] **5.4 Quantize** — `src/core/recolor/quantize.js`: per-pixel nearest with `quant_dither` (none / floyd-steinberg / bayer4 / bayer8), `quant_dither_strength`, `quant_lightness_weight`, `quant_downscale`. Reuses `src/core/dither.js`.
- [ ] **5.5 Quantize tests** — only target colours emitted; dithering deterministic; `quant_lightness_weight` demonstrably trades hue accuracy for value accuracy. *Done when:* green.
- [ ] **5.6 Mode selection** — `recolor_mode` auto / indexed / quantize, `auto` deciding on the source's unique-colour count. Tested: pixel art picks indexed, a photograph picks quantize.
- [ ] **5.7 GIF decoder** — `src/core/gif.js`: LZW decode, all frames returned, `gif_frame` selecting first/last/index. **Read-only and single-frame — no encoder** (decided 2026-07-22, PLAN §19.2). No dependencies (ARCHITECTURE §12.1).
- [ ] **5.8 GIF tests** — an animated fixture decodes to the right frame count and dimensions; `gif_frame` selects the frame it claims to; a decoded frame recolours like any other image. *Done when:* green.
- [ ] **5.9 Example references** — committed/generated example images including an animated GIF and a large-colour-count synthetic photograph, so the gallery is never empty and the tests have real data.
- [ ] **5.10 Import without a command line** — double-clickable `start.cmd` boots the server and opens the browser; drag-and-drop plus a folder picker in the app; images persist to `palette/reference/` through a `GET/PUT /api/reference` endpoint reusing `safeSaveName`. Degrades to in-session-only in the standalone build, like the saves UI (ARCHITECTURE §12.3).
- [ ] **5.11 Recolour gallery page** — every reference image together, user's and generated, original beside recoloured, with mode and unique-colour count, updating live with the palette.
- [ ] **5.12 Parameters** — the §19.1 knobs into `params.js` so they are seed-encoded and slider-driven like everything else.
- [ ] **5.13 GATE 5** — tests green against the committed examples; the gallery rendered and **read**; driven end to end in the browser with no command line.
