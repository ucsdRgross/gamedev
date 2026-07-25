# UX Phase — execution plan, handoff and task tracker

The approved subset of [IMPROVEMENTS.md](IMPROVEMENTS.md), sequenced into seven phases.
**This file is the source of truth for what is done in this phase** (the same role
[PROGRESS.md](PROGRESS.md) plays for the original build). Tick a box only when its
*done-when* condition actually holds — a green test or a rendered image, never a written file.

Approved items: **1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 17, 18, 19, 20, 21, 22, 26,
27, 28, 31, 32, 33, 34, 35**. Item 22 is an on-screen button, not a keyboard chord. Item 27
is **additive** — the existing entry paths (defaults, preset select, seed, Fit to image) all
keep working exactly as they do now.

Not in scope (not approved): 12, 16, 23, 24, 25, 29, 30.

## The goal, restated as an acceptance test

> Sit down with a look in mind, and reach it by **picking and steering** rather than by
> reading 72 tooltips and dragging sliders one at a time.

## Hard constraints (inherited — do not break)

1. **`PARAMS` field order is append-only.** New parameters go at the end; `label`, `hint`,
   `lowLabel`, `highLabel`, `optionLabels` are metadata on the spec and do not touch the seed
   payload. Reordering silently reinterprets every `PAL1-` seed ever pasted.
2. **`src/core/` is DOM-free and Node-built-in-free.** Same code runs in the browser, under
   `node --test`, and in `tools/render.mjs`. New logic goes in core with a test; only
   presentation goes in `src/ui/`.
3. **No runtime dependencies.** Vanilla ES modules only.
4. **`npm test` stays green** (370 tests at the start of this phase). Snapshot changes get
   reviewed and re-recorded deliberately (`UPDATE_SNAPSHOTS=1 npm test`), never blindly.
5. **No existing functionality is removed** — every new view is additive or a toggle.
6. Environment: prepend `C:\Program Files\nodejs` to `PATH`; run npm from `palette/`, not the
   home directory. `PALETTE_FUZZ_N=200 npm test` while iterating.

---

## Phase U1 — Parameter legibility · items 2b, 17, 13

The panel prints raw seed keys (`sliders.js` uses `spec.name` as the label). Everything here
is schema metadata plus panel chrome.

- [x] **U1.1** `ParamSpec` gains `label`, `hint`, `lowLabel`/`highLabel` (numeric) and
      `optionLabels` (enum: value → label). *Done when* `test/params.test.js` asserts every
      parameter has a non-empty label and hint, every enum option has a label, and labels are
      unique.
- [x] **U1.2** All 72 parameters carry the table from IMPROVEMENTS.md. *Done when* the
      assertions in U1.1 pass over the whole schema.
- [x] **U1.3** `sliders.js` renders `label` (with the raw `name` demoted to the tooltip
      header), end-labels under numeric sliders, and enum options by their label.
- [x] **U1.4** Basics / All toggle. `BASIC_PARAMS` lives in `params.js` (core, testable);
      *done when* a test asserts every listed name exists and Basics is a strict subset.
- [x] **U1.5** Search box filtering by label/name/hint/doc; "only changed" filter reusing the
      existing `changed` class; per-group reset button; alt-click a label to reset one.
- [x] **U1.6** `npm test` green and the app boots with the panel readable.

## Phase U2 — Preview and explanation infrastructure · items 2a, 21, 31, 32, 34

Shared machinery the later phases lean on. All the computation is core; only drawing is UI.

- [x] **U2.1** `src/core/preview.js`: `paramSweep(params, name, n)` → n parameter sets across
      one parameter's range; `sweepPalettes` helper. *Done when* `test/preview.test.js` shows
      a sweep is monotonic in the swept field and every result generates.
- [x] **U2.2** `src/core/describe.js`: `describePalette(palette, params)` → one plain-English
      paragraph, and `paramDiff(a, b)` → ordered list of meaningful differences (used by U2.5,
      U3.3, U6.2). *Done when* tested against three presets with expected phrases.
- [x] **U2.3** `src/core/colornames.js`: embedded name list + `nearestName(hex)`. *Done when*
      tested for exact-hit and nearest behaviour, and every entry parses.
- [x] **U2.4** Hover preview strips on every numeric/enum control (`src/ui/strip.js` draws a
      palette to a small canvas; sliders show 5 sweep steps + a marker at the current value).
- [x] **U2.5** Palette pane: "explain this palette" line (U2.2) and colour names on swatch
      hover (U2.3). Preset load shows what it changed (U2.2 `paramDiff`).
- [x] **U2.6** `color_count` size sweep thumbnails (8/16/24/32/48/64) as a popover; click sets
      the count.

## Phase U3 — Variation and history · items 5, 1, 28, 22

- [x] **U3.1** `varyParams(params, rng, { strength, groups })` in `src/ui/randomize.js`
      (kept DOM-free): perturbs *around* the current values, honours a fixed set, never
      rerolls `color_count`/`hue_scheme`/`hue_count` unless asked. `randomizeParams` stays as
      the wild-strength path so the existing test and button behaviour survive. *Done when*
      `test/randomize.test.js` covers: strength monotonicity, fixed-set respect, determinism.
- [x] **U3.2** Variant grid (`src/ui/variants.js`): 12 live thumbnails around the current
      palette, click to adopt, strength control, "more like this". Each tile shows the
      **context colour-space maps** (repo owner, 2026-07-24: a single scene is "way too simple
      and doesn't show the whole palette in different scenarios") — one map per context at the
      top saturation only, since all four saturations would be 24 pictures per tile. The
      gallery scenes stay available in the same selector.
- [x] **U3.3** History: cap 100, entries labelled with what changed (U2.2), persisted to
      `localStorage` and restored on load.
- [x] **U3.4** On-screen **Before / After** button: hold-or-toggle to show the previous
      palette in every view.

## Phase U4 — Seeing it · items 4, 18, 19, 7, 33

- [ ] **U4.1** Pinned hero scene above the gallery, always visible while tuning; selectable
      scene; 1× zoom added to the gallery zoom options.
- [ ] **U4.2** Larger composed mockup scene(s) (256×192: HUD + tilemap + character + text at
      three sizes + inventory) added to `src/scenes/`. *Done when* `test/scenes.test.js`
      passes for the new scenes and `npm run render` writes them.
- [ ] **U4.3** Real-art hero set: a pinned row of recoloured reference images at the top of
      the Gallery tab (reuses the recolour engine), user-selectable, with the original
      available side by side.
- [ ] **U4.4** Colour-vision side-by-side view option (colour + deutan, colour + value).
- [ ] **U4.5** Ramp view toggle in the palette pane (Grid / Ramps / by lightness / by hue),
      built on `rampsOf()`.
- [ ] **U4.6** **Freeze** toggle in the topbar: zeroes `hue_jitter`, `l_variance_per_hue`,
      `chroma_variance_per_hue` and restores them on release.

## Phase U5 — Keeping and starting · items 6, 26, 27, 11

- [ ] **U5.1** One-click **Keep**: auto-named save (`autoName(palette, params)` in core, from
      hue/count/key), no dialogue, rename later.
- [ ] **U5.2** Saved-palette **library grid** (swatch strip + scene thumbnail per save), click
      to load, shift-click to send to Compare. The existing `<select>` stays.
- [ ] **U5.3** History and library persistence across reloads; rolling autosave of accepted
      palettes.
- [ ] **U5.4** Preset **thumbnail grid** (additive — the preset `<select>` stays).
- [ ] **U5.5** Additive **start screen**: mood chips → preset + variant grid, "start from an
      image", "paste hexes". Dismissible and never blocks the existing paths.
- [ ] **U5.6** Paste ingestion: `parseHexList()` in core (accepts `#aabbcc`, `aabbcc`,
      comma/space/newline separated, lospec dumps); a paste field that can create a
      compare/recolour target or feed the fitter.

## Phase U6 — Inversion tools · items 10, 3, 9

- [ ] **U6.1** Fitter upgrades in `src/core/fit.js`: `from` (start at current params),
      `fixed` (names never perturbed), `onProgress` best-so-far palette, resumable "keep
      looking", and a returned parameter diff. *Done when* `test/fit.test.js` covers each.
- [ ] **U6.2** **Compare** mode: pin A, choose B (save, preset, external palette image, pasted
      hexes, seed); aligned side-by-side; difference report from U2.2; "how to get there" via
      U6.1 seeded from A; **morph slider** A→B (numeric lerp, enums snap at 50%).
- [ ] **U6.3** Custom hue pins: append-only `custom_hue_count` + `custom_hue_1..6`, honoured
      by `hues.js`; wheel UI with draggable pins and seeding from the current palette. The
      existing `custom` scheme keeps working (an even spread when no pins are set).

## Phase U7 — Correctness surface · items 14, 35, 15, 20, 8

- [ ] **U7.1** `src/core/diagnose.js`: near-duplicate pairs, value holes, hue gaps, unused
      colours (`sceneUsage` counts passed in), CVD collisions, contrast failures,
      requested-vs-achieved divergence — each with a machine-readable suggested fix.
- [ ] **U7.2** Report card in the palette pane rendering U7.1, each finding with a one-click
      fix that applies the parameter change or highlights the swatches.
- [ ] **U7.3** Silent no-op detection (item 35): when a parameter move produces an identical
      palette, mark the control "clamped".
- [ ] **U7.4** Dither reference's "colours worth adding" surfaced in the palette pane, with
      "add as a locked slot".
- [ ] **U7.5** Semantic names in the CSS export (`--color-foliage-mid`), role comments plus
      the `PAL1-` seed in `.gpl`/`.hex`. Snapshot review required.
- [ ] **U7.6** Direct colour editing: OKLCH mini-editor on a swatch, arrow-key nudge,
      eyedropper from any loaded reference image, pinned-colours list with "clear all".

---

## Running notes / handoff

Append here as work lands: what changed, what surprised, what the next agent must read first.

- **2026-07-24 — phase opened.** Baseline before any change: git clean at `f50d830`
  (only IMPROVEMENTS.md untracked), `npm test` reported green at 370 tests by PROGRESS.md.
  Audit in IMPROVEMENTS.md; the approved subset above is the scope. Starting at U1.1.
- **2026-07-24 — U1 done. `npm test` green at 377** (`PALETTE_FUZZ_N=200`, 17 s).
  - New `src/core/paramui.js` holds `PARAM_UI` (label / hint / low / high / enum option
    labels for all 72 parameters) and `BASIC_PARAMS` (11 names). It is a **separate file from
    `params.js` on purpose**: wording gets edited often, and `params.js` is the file where a
    stray edit silently reinterprets every PAL1 seed. `params.js` merges it in via `withUi`
    (`const SCHEMA = [...]` → `export const PARAMS = SCHEMA.map(withUi)`), so field order is
    untouched — asserted by a test that pins `seed` at index 57 and the last field name.
  - `sliders.js` now shows the label, a one-line hint, and end labels under every numeric
    slider; enum options are shown by label and the hint follows the selected option. The raw
    parameter name moved into the tooltip header (`.param-tip-name`) so it stays greppable.
  - Panel toolbar (`#params-toolbar` in index.html): search over label/name/hint/doc,
    Basics and Changed toggles, ↺ per group header, alt-click a label to reset one. Filtering
    force-opens groups that have matches and hides groups with none.
  - Verified in the running app (server on :5299): 72 controls, 11 groups, search "shadow" →
    7 controls, Basics → 11 across 5 groups, Changed → 0 at defaults and 1 after an edit,
    group reset and alt-click reset both return the default without toggling the disclosure.
  - Seven new assertions in `test/params.test.js` cover the metadata (unique labels, both
    ends named, every enum option explained, `PARAM_UI` covers the schema exactly, Basics is
    a strict subset containing the five big movers, payload order unmoved).
- **2026-07-24 — U2 done. `npm test` green at 401**; `npm run build` green (81 modules).
  - Core, all DOM-free and tested: `preview.js` (`sweepValues`/`paramSweep`/`sweepPalettes`/
    `sizeSweep`, honouring locks and overrides so a preview shows what you would actually
    get), `describe.js` (`describePalette`, `hueName`, `paramDiff`, `describeChange`,
    `summarizeDiff`) and `colornames.js` (111 named colours + a procedural fallback).
  - **Two calibrations worth keeping.** (1) `describePalette` says "around &lt;root_hue&gt;", not
    the circular mean of the chromatic entries and not `hues[0]`: the mean of a wide fan lands
    on a hue the palette may not contain, and `hues[0]` is the fan's first arm, not its centre
    (sunset-desert: root 45°, `hues[0]` 353°). (2) `deltaEOK` runs on a 0–13 scale here, so the
    colour-name cutoff is **5**, not 0.09 — at 0.09 nothing but exact hits was ever named. The
    hue-name table is calibrated to OKLCH angles (red 29°, yellow 110°, green 142°, cyan 195°,
    blue 264°, magenta 328°), not to the HSL angles those names have elsewhere.
  - `paramDiff` ranks by fraction-of-range moved; an enum/bool flip counts 0.5 and Basics get
    ×1.3, so "hue count +6" outranks "dither evenness +0.02" without enum flips always winning.
  - UI: `strip.js` (shared strip and scene-thumbnail drawing — used again by U3/U5), `sizes.js`
    (the Sizes popover). The doc tooltip and the sweep are now **one** floating panel attached
    to the whole control row; two panels anchored to the same corner fought each other. The
    sweep builds 160 ms after the pointer settles and is cached per parameter, dropped on edit.
  - Palette pane: a plain-English description line under the head; every swatch carries its
    colour name (or an honest description when nothing is within ΔE 5); a **Sizes** button
    compares this palette at 8/16/24/32/48/64 and applies the one you click. Presets, seeds,
    fits and loaded palettes report what they changed in `#change-note`.
  - Verified live: sweep shows 5 rows × 32 cells with one marked current; Sizes applies 16;
    loading Neon Cyberpunk notes "Colour of the world +265 · Colour of the light +240 · How
    the hues relate → Split complement · +22 more".
- **2026-07-24 — U3 done. `npm test` green at 411.**
  - `varyParams(params, rng, { strength, includeStructure, fixed })` perturbs around the
    current values (gaussian, σ = strength × range; enums flip with probability = strength)
    instead of resampling uniformly, and holds `hue_scheme`/`hue_count`/`tier_priority` unless
    asked. `randomizeParams` is untouched and still backs the Randomize button, which stays.
    New topbar **Vary** button (shift = bolder). `paramDistance` makes "a stronger setting
    moves further" a testable property rather than an intention.
  - **Bug found and fixed: `l_variance_per_hue` and `chroma_variance_per_hue` end in `_hue`**
    but are not angles. The wrap rule matched them by suffix, so a small negative step became
    359.98 and clamped to the parameter's *maximum* — a "gentle" variation could slam per-hue
    variance to its ceiling. Angles are now listed explicitly in `params.js`
    (`ANGULAR_PARAMS` / `isAngularParam`), with two tests pinning it.
    **`src/core/fit.js` still matches by suffix and is left alone deliberately** — see the
    open note below.
  - Variant grid: 12 tiles (the first is the current palette), each drawn as the six context
    colour-space maps at full saturation (`contextThumbSheet` in `layout/render.js`,
    `drawContextMaps` in `ui/strip.js`). ~125 ms for a whole grid at 84×42 per map; the
    gallery-scene views remain in the selector. Clicking a tile adopts it and re-centres the
    next dozen on it, which is what makes repeated clicking a search.
  - History: 100 deep, every entry labelled with what changed (the label is measured against
    the last *pushed* entry, so a drag's label describes the whole drag), persisted to
    `localStorage` under `palette.history.v1` and restored on boot unless the URL carries a
    seed. Topbar **Before** button swaps every view to the previous entry without touching the
    seed field, the URL or the history, and any real edit exits it.
  - `paramDiff` gained `minMagnitude` (the app filters user-facing summaries at 1.5% of range)
    and now scores a `seed` change as magnitude 0 — a reroll is not a described change, and
    its 0–65535 range made it outrank everything real.

### Open note for U6.1 — the fitter's own hue-wrap bug (measured, deliberately deferred)

`src/core/fit.js:111` still uses the `name.endsWith('_hue')` test that U3 fixed elsewhere, so
its search wraps `l_variance_per_hue` and `chroma_variance_per_hue` to 359.98 → clamp to max.
That accidental "jump to an extreme" is *load-bearing exploration* for the current search, and
the two fit thresholds in `test/fit.test.js` are tuned around it. Measured over five RNG seeds
(scores, lower is better):

| variant | recovery target (3000 iters) | crayon target (4000 iters) |
|---|---|---|
| as committed (buggy wrap) | 3.50 3.73 **3.10** 3.69 4.64 | 5.15 3.74 **4.11** 4.58 4.13 |
| wrap fixed, no compensation | — (seed 3 → 4.33) | 5.42 4.53 **6.17** 4.38 3.82 |
| wrap fixed + 12% uniform jumps | 3.90 3.85 **4.37** 3.08 3.93 | 4.70 5.54 **3.46** 7.07 4.64 |

(The tests use seed 3, in bold.) Fixing the wrap without compensation regresses both targets;
a uniform "jump" move recovers the crayon fit but not the recovery fit at 3000 iterations.
**Do it properly in U6.1**: fix the wrap, then re-tune the search (annealed jump rate is the
promising direction) and re-baseline the thresholds against a multi-seed benchmark rather than
a single seed. Also worth knowing: PROGRESS.md records that `l_variance_per_hue`'s ceiling was
raised from 0.15 to 0.30 because "fitting real reference palettes pinned it at the old
ceiling" — that evidence is now suspect, since this bug pinned it there by construction.
