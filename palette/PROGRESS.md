# Build Progress

Source of truth for what is done. Check off each task **the moment its "done when"
condition is actually met** — a green test, not a written file.

If this file is missing or looks stale, rebuild it using the state-detection
procedure in [PLAN.md](PLAN.md) §18. Verify with `npm test`, never by trusting
that a file exists.

## Resume here → task 2.1

Phase 1 is complete and gated: `npm test` is green at 140 tests, `npm run render`
produces `out/*.png`, and those images were read and confirmed correct.

**Before writing Phase 2 code, read [ARCHITECTURE.md](ARCHITECTURE.md).** It documents
the `Palette` object the UI consumes, the three source files that are not in PLAN.md's
§7 layout and why, the places where the implementation deliberately extends the plan,
and the limitations that are contracts rather than bugs. Two of its sections will save
you real time: §1 (the `Palette` shape, and why `oklch` and `actual` are different) and
§8 (a decision Phase 3 needs made before any scene is written).

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

- [ ] **2.1 Dev server** — `tools/serve.mjs`: static hosting + `GET/PUT/DELETE /api/saves`.
- [ ] **2.2 Shell** — `index.html`, `src/style.css`: three-pane layout.
- [ ] **2.3 Sliders** — `src/ui/sliders.js`, generated from `params.js`, grouped/collapsible, doc string as tooltip.
- [ ] **2.4 Swatch grid** — `src/ui/swatches.js`: role, hex, OKLCH readout, lock toggle, override editor.
- [ ] **2.5 History** — `src/ui/history.js`: undo/redo + 20-deep clickable strip.
- [ ] **2.6 I/O** — `src/ui/io.js`: seed field, URL-hash sync, preset dropdown, saved dropdown, export buttons.
- [ ] **2.7 Wiring** — `src/ui/app.js`: live regeneration; randomize respecting locks and overrides.
- [ ] **2.8 Standalone build** — `tools/build.mjs` → `dist/palette_creator.html`. *Done when:* opens by double-click and generates.
- [ ] **2.9 GATE 2** — drive the UI with the browser tool; confirm every slider, seed round-trip, save/load, and export. Report to user.

## Phase 3 — Test visual gallery

- [ ] **3.1 Scene registry + gallery** — `src/scenes/index.js`, `src/ui/gallery.js`.
- [ ] **3.2 Analysis module** — `src/core/analysis.js`: Viénot colorblind matrices, value view, ramp evenness.
- [ ] **3.3 Dithering module** — `src/core/dither.js`: Floyd-Steinberg, Bayer 4×4 and 8×8.
- [ ] **3.4 Scenes 1–6** — palette structure.
- [ ] **3.5 Scenes 7–10** — form and shading.
- [ ] **3.6 Scenes 11–19** — sprites.
- [ ] **3.7 Scenes 20–24** — scenes.
- [ ] **3.8 Scenes 25–26** — UI and text legibility.
- [ ] **3.9 Scenes 27–31** — dithering and gradients.
- [ ] **3.10 Scene 32** — animated.
- [ ] **3.11 Scene 33** — photo quantization (drag-drop + 3 synthetic references).
- [ ] **3.12 Scene 34** — side-by-side reference compare with ΔE fit score.
- [ ] **3.13 Extend renderer** — every static scene to `out/`.
- [ ] **3.14 GATE 3** — render all scenes, **read the PNGs**, confirm in-browser. Report to user.

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
