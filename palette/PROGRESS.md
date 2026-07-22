# Build Progress

Source of truth for what is done. Check off each task **the moment its "done when"
condition is actually met** — a green test, not a written file.

If this file is missing or looks stale, rebuild it using the state-detection
procedure in [PLAN.md](PLAN.md) §18. Verify with `npm test`, never by trusting
that a file exists.

## Resume here → task 4.1

Phases 1, 2 and 3 are complete and gated. `npm test` is green at **176 tests**
(core + dev-server + raster/analysis/dither + 34-scene smoke tests). The app runs under
`npm start` with the live 34-scene gallery (filter, colour-vision views, zoom, animation,
drag-and-drop photo quantization). `npm run render` writes every scene to `out/scenes/`
and per-category contact sheets to `out/scene-sheets/`, all read and confirmed.

Phase 4 renders into the same `Raster` surface (`src/core/raster.js`) and should add its
contact sheet to `tools/render.mjs`, mirroring the scene-sheet layout already there.

**Before writing Phase 4 (the artist's-palette picker), read [ARCHITECTURE.md](ARCHITECTURE.md) §10**
for the Phase 3 contracts (the scene interface, the `Raster` surface, the shared scene
`util.js` accessors). Phase 4 is `src/core/layout/` + `src/ui/picker.js`; its scoring
tests (task 4.8) require every optimized layout to beat the ramp-rows baseline.

### Environment note (this machine, 2026-07-22)
Node was not installed; installed **Node v24.18.0** via winget. Node lives at
`C:\Program Files\nodejs` but is **not on the tool-shell PATH** — prepend it every
command: `$env:Path = "C:\Program Files\nodejs;$env:Path"`. Node 24's `node --test`
rejects a bare directory, so the `test` script is now `node --test test/*.test.js`.

### Working notes

- `npm test` runs the full 10,000-case fuzz and takes about 4.5 minutes. While
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

- [ ] **4.1 Scoring** — `src/core/layout/score.js`: mean/worst neighbor ΔE, blob-sizing modes.
- [ ] **4.2 SOM** — rectangular, toroidal, hexagonal, disc (variants 1–4).
- [ ] **4.3 Annealing** — seeded deterministic swap optimizer (5).
- [ ] **4.4 Hilbert** — 3D Hilbert index + boustrophedon fill (6).
- [ ] **4.5 Projection** — MDS/PCA + Voronoi + Lloyd relaxation (7–8).
- [ ] **4.6 Organic** — ΔE-weighted region growth (9).
- [ ] **4.7 Remaining** — polar wheel, ramp-rows baseline, value spiral, treemap, sphere unwrap, Delaunay (10–15).
- [ ] **4.8 Layout tests** — full coverage, no holes; **every optimized layout beats the ramp-rows baseline**; annealing deterministic. *Done when:* green.
- [ ] **4.9 Picker UI** — `src/ui/picker.js`: variant selector, blob-size mode, hover readout, click-to-copy, high-res export, contact sheet.
- [ ] **4.10 GATE 4** — render the contact sheet, inspect it, report ranked scores to the user.
