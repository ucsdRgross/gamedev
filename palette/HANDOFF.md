# Handoff — Pixel Palette Creator, UX phase

Paste-able briefing for an agent with **no prior context**. Read this, then
[UX_PLAN.md](UX_PLAN.md) (the task tracker), then the two files named in "Read before you
touch X" below. Everything is in the `palette/` directory of this repository.

---

## 1. What the project is

A dependency-free, procedural **pixel-art colour palette generator** written in vanilla ES
modules. It turns 79 parameters into a structurally-sound palette in OKLCH space, proves the
palette works by drawing it into a gallery of test scenes, recolours real reference art into
it, and exports to Godot / Aseprite / the web.

- **No runtime dependencies.** Node built-ins and vanilla ES modules only. Node ≥ 22.
- **The app is a static page** (`index.html` + `src/`) served by a tiny dev server
  (`tools/serve.mjs`). `npm run build` inlines the whole thing into one double-clickable
  `dist/palette_creator.html`.
- The original build is **complete and gated**; the work in progress is a **UX phase** that
  makes the tool faster to *use*. That phase is the job.

### Layout

| Path | What it is |
|---|---|
| `src/core/` | DOM-free colour maths, generation, analysis, dithering, layout, recolour. Imported by the browser, `node --test` and the headless renderer alike |
| `src/core/export/` | Output writers: gpl, pal, hex, lospec, css, json, tres, png |
| `src/ui/` | Browser app modules (`app sliders swatches history io saves start compare wheel randomize gallery hero picker recolor variants sizes strip`) |
| `src/scenes/` | The 36 gallery scenes (DOM-free) + registry + semantic role accessors |
| `test/` | `node --test` suite (460 tests) and golden snapshots |
| `tools/` | Dev server, single-file build, headless renderer, PNG codec |
| `saved/` `reference/` `palettes/` | User saves; reference images to recolour; palette images to recolour into |
| `out/` `dist/` | Rendered PNGs and the standalone build (gitignored) |

### Documents, in reading order

| File | Role |
|---|---|
| **UX_PLAN.md** | **Source of truth for the current phase**: seven phases, checkboxes, done-when conditions, and a running handoff log. Tick a box only when its condition actually holds |
| IMPROVEMENTS.md | The usefulness audit this phase implements. 35 numbered items; the approved subset is listed at the top of UX_PLAN.md |
| PLAN.md | The original specification — colour theory, algorithms, formulas |
| ARCHITECTURE.md | How the built parts work. §9 app, §10 gallery, §11 picker, §12 recolouring, §13 fitter, §14 dithering |
| PROGRESS.md | State of the original build (all phases complete) |
| COLOR_GUIDE.md | Where each hue lives in sRGB — saturation ceilings and the lightness each colour peaks at |

**Read before you touch X:** `src/core/layout/` → ARCHITECTURE §11. `src/core/recolor/` or
`src/core/gif.js` → ARCHITECTURE §12.5–12.8. The fitter → ARCHITECTURE §13.

---

## 2. Environment (this machine)

```bash
# Node is NOT on the tool shell's PATH. Prepend it on every command:
$env:Path = "C:\Program Files\nodejs;$env:Path"      # PowerShell
export PATH="/c/Program Files/nodejs:$PATH"          # bash
```

- Node v24.18.0. **Do not downgrade below 22** — `npm test` relies on the test runner's
  built-in glob expansion (`node --test test/*.test.js`).
- **Run npm from `palette/`**, never from the user's home directory: there is an unrelated
  `package.json` above it that npm will find instead.
- `npm test` runs a 10,000-case fuzz and takes ~6 minutes. While iterating:
  `PALETTE_FUZZ_N=200 npm test` (~65 s, still 460 tests — the fit tests now run three
  seeds each, which is most of that minute).
- Run the app: `npm start` (port 5173), or `PORT=5299 node tools/serve.mjs --replace` if you
  want a port that will not collide with the user's own instance. Double-clicking `start.cmd`
  is the user's way in; a second double-click is a restart (ping/shutdown handshake).
- Snapshots: `UPDATE_SNAPSHOTS=1 npm test` — only after reviewing the diff deliberately.
- `npm run render` writes every preset, scene, layout, map, dither sheet and recoloured
  reference to `out/`. **Look at the output**; a palette can pass every test and still be wrong.

---

## 3. Where the work stands

`npm test` **green at 460** (was 370 at the start of the phase). `npm run build` green.
U1–U3 are committed (`3942c4b`); **U4, U5 and U6 are in the working tree, uncommitted**. The
user has not asked for commits; do not commit unless asked.

Phases **U1–U6 are done**, with nothing outstanding. **U7 is not started.** Full detail,
including per-task done-when conditions, is in UX_PLAN.md; the running notes at the bottom of
that file record what was built and what surprised.

### What U1–U3 added (so you do not re-derive it)

**New core modules** (all DOM-free, all tested):

- `src/core/paramui.js` — `PARAM_UI` (label / hint / low / high / enum option labels for every
  parameter) and `BASIC_PARAMS`. Deliberately **separate from `params.js`**, which is
  seed-critical: wording gets edited often, and a stray edit in `params.js` silently
  reinterprets every `PAL1-` seed ever pasted. `params.js` merges it in via `withUi`.
- `src/core/preview.js` — `sweepValues` / `paramSweep` / `sweepPalettes` / `sizeSweep`. "What
  does this knob do" answered as five generated palettes rather than a sentence.
- `src/core/describe.js` — `describePalette` (one plain-English line read off the colours),
  `hueName`, `paramDiff`, `describeChange`, `summarizeDiff`.
- `src/core/colornames.js` — 111 named colours + `nearestName` + a procedural fallback
  (`describeColor`); `colorLabel` picks between them.

**New UI modules:** `src/ui/strip.js` (shared palette strips, scene thumbnails and
**context-map thumbnails**), `src/ui/sizes.js` (the Sizes popover), `src/ui/variants.js` (the
variant grid).

**Changed:** `params.js` (metadata merge, `BASIC_PARAM_NAMES`, `optionLabel`, `ANGULAR_PARAMS`,
`isAngularParam`), `sliders.js` (labels, hints, end labels, hover sweep, search / Basics /
Changed / resets), `swatches.js` (colour names), `history.js` (100 deep, labels,
serialize/restore), `randomize.js` (`varyParams`, `paramDistance`), `app.js` (variants tab,
Vary and Before buttons, change notes, history persistence), `layout/render.js`
(`contextThumbSheet`), `index.html`, `style.css`.

### What U4 added

- `src/core/arrange.js` — `arrangeEntries(palette, mode)` regroups the swatches as Grid /
  Ramps / by lightness / by hue. The invariant the tests pin is **conservation**: every mode
  returns every entry exactly once.
- `analysis.js` — `applyViewSpec` / `viewParts` / `VIEW_PAIRS`. `'color|deutan'` renders both
  views into one raster side by side, so the gallery paints a pair like any single view.
- `src/ui/hero.js` — the pinned block above the gallery grid: a selectable scene at its own
  zoom, plus a row of real reference art recoloured live beside its original. Prefs persist
  under `palette.hero.v1`.
- `recolor.js` gained `listSources` / `framesFor` / `onSourcesChange` so the hero borrows the
  reference library instead of fetching and decoding the same files a second time.
- `params.js` gained `FREEZE_PARAMS`; the topbar **Freeze** button zeroes all three.

**Three traps U4 hit — read before touching the hero or the gallery:**

1. **`requestAnimationFrame` does not fire when the page is not being composited.** The hero
   coalesces with `setTimeout`, matching `recolor.js`. The gallery still uses rAF, so it draws
   nothing in a hidden/headless tab — expected, not a bug in a real window.
2. **The reference library arrives in stages.** `onSourcesChange` fires first with only the
   built-ins. Pruning pinned art against that partial list deletes every folder pin.
3. **Freeze cannot be detected by value alone** — a preset that is already unjittered would
   otherwise leave the button on, holding the previous palette's values.

### What U5 added

- `src/ui/saves.js` — the save **store**, with two backends behind one interface: the dev
  server's `saved/` folder when one answers, `localStorage` when it does not. Saving used to
  be disabled outright without a server, so the standalone build could not keep anything.
  `where()` reports which backend is live; that difference is never hidden.
- `autoName` in `describe.js` and `src/core/library.js` (`SAVE_NAME_RE`, `isSaveName`,
  `toSaveName`, `pushAutosave`) — one-click **Keep** with a name read off the colours, and the
  autosave ring.
- `src/core/hexlist.js` — `parseHexList` / `hexListPalette`.
- `src/ui/start.js` — the **Start tab**: mood chips, the preset thumbnail grid, the kept
  library, the "recently passed through" ring, and the paste field. Opens by default only for
  a genuinely first-time visitor.
- `io.js` now returns `loadSave` / `save` / `fitTo` / `pickImage`; the Start tab calls those
  rather than owning copies. `recolor.js` gained `addTarget(palette)` for pasted colours.

**Three traps U5 hit:**

1. **The library rebuild is re-entrant** — Keep rebuilds it while the previous read is still
   in flight. Clear-then-append-after-await shows every save twice; `buildSaves` carries a
   generation counter.
2. **"First visit" is not "no localStorage."** The seed is mirrored into the URL hash, so a
   plain reload always carries one. The test is no restored history *and* no hash seed.
3. **`autoName` cannot reuse `describePalette`'s bands.** Measured over all 21 presets the
   mean chroma of the coloured entries spans 0.036–0.166, so bands drawn for the 0–0.37 range
   would call every palette "mid" and nothing "vivid".

### What U6 added

- **`fit.js`**: the hue-wrap bug is fixed (`isAngularParam`), the search re-tuned with an
  annealed single-knob jump (`JUMP_RATE = 0.2`, measured over eight seeds), and the thresholds
  re-baselined as a mean over three seeds plus a per-seed ceiling. New options `from`, `fixed`,
  `onProgress`, `keepLooking(n)`, and a returned `diff`. **`from` makes restart 0 the caller's
  own parameters untouched**, so a fit from your palette can only improve on it.
- **`src/core/morph.js`** — `morphParams` / `morphSnapPoints`. Numbers travel, angles take the
  short way, enums *and `seed`* snap at 0.5.
- **`src/ui/compare.js`** — the Compare tab. A is a snapshot; B can be a preset, a save, a
  pasted seed, pasted colours, a loaded palette image, or **live** (tracks the sliders).
- **`src/ui/wheel.js`** — the hue wheel: click to pin, drag to move, click a pin to remove,
  and "take the palette's hues".
- **`params.js`** grew for the first time this phase: `custom_hue_count` + `custom_hue_1..6`
  appended after `remap_context_bias`, plus `CUSTOM_HUE_PARAMS` and `customHues()`.

**Three traps U6 hit:**

1. **A drag commits on every `pointermove`**, so testing "did the pointer move?" against the
   pin's *current* position calls every drag a click — the wheel deleted pins instead of
   moving them. Compare against where the press began.
2. **An external palette has no semantic roles**, so no gallery scene can draw it. Compare
   shows a large strip for a colours-only side rather than inventing a role mapping.
3. **A pinned hue needs three separate exemptions** in `hues.js` — from the perceptual warp,
   from the jitter, and from the separation pass — or it is not actually pinned.

**Three calibrations that are easy to get wrong again:**

1. `describePalette` says "around `root_hue`", not the circular mean of the chromatic entries
   and not `hues[0]` — the mean of a wide fan lands on a hue the palette may not contain, and
   `hues[0]` is the fan's first arm, not its centre (sunset-desert: root 45°, `hues[0]` 353°).
2. `deltaEOK` runs on a **0–13** scale in this codebase. The colour-name cutoff is 5. At 0.09
   (the value that looks right if you assume a 0–1 scale) nothing but exact hits is ever named.
3. Hue names are calibrated to **OKLCH** angles (red 29°, yellow 110°, green 142°, cyan 195°,
   blue 264°, magenta 328°), not the HSL angles those names have elsewhere.

---

## 4. Hard constraints — do not break these

1. **`PARAMS` field order is append-only.** The index of a parameter in that array *is* its
   position in the `PAL1-` seed payload. New parameters go at the **end**. Reordering or
   removing one silently reinterprets every seed anyone has ever saved or pasted. Presentation
   metadata (`label`, `hint`, `lowLabel`, `highLabel`, `optionLabels`) is attached after the
   array is built and does not touch the payload; a test pins `seed` at index 57 and the last
   field name.
2. **`src/core/` is DOM-free and must not import Node built-ins.** That constraint is what lets
   the same code run in the browser, under `node --test`, and in the headless renderer. New
   logic goes in core **with a test**; only presentation goes in `src/ui/`.
3. **No runtime dependencies.** Vanilla ES modules only, no bundler.
4. **`npm test` stays green.** Snapshot changes get reviewed and re-recorded deliberately.
5. **Nothing existing is removed.** Every addition in this phase is additive or a toggle — the
   user said so explicitly. The old Randomize button, the preset `<select>`, the gallery scene
   views and every existing entry path all still work.
6. **Generate the UI from the schema.** Sliders come from `PARAMS`; hand-writing a control
   duplicates the schema and the seed codec drifts out of sync.

---

## 5. Resolved: the fitter's hue-wrap bug (fixed in U6.1)

`src/core/fit.js` used to decide which parameters wrap at 360° by suffix, which wrongly caught
**`l_variance_per_hue`** and **`chroma_variance_per_hue`** — a small negative step became 359.98
and then clamped to the parameter's *maximum*. That accidental "jump to an extreme" was
load-bearing exploration, and the fit thresholds had been tuned around it against a single seed.

**Fixed 2026-07-24.** `fit.js` now uses `isAngularParam`; the exploration it lost is replaced by
an explicit annealed jump (one knob per candidate, rate 0.2 falling to 0 across each restart);
and the thresholds are a mean over three seeds plus a per-seed ceiling. The full eight-seed
table is in UX_PLAN's U6 note.

**Still worth knowing:** PROGRESS.md records that `l_variance_per_hue`'s ceiling was raised
0.15 → 0.30 because fitting real palettes "pinned it at the old ceiling". That evidence remains
suspect — the bug pinned it there by construction — so the raised ceiling has never actually
been justified by a clean measurement. Re-deriving it is a loose end nobody has picked up.

---

## 6. What to do next

Work **U6 → U7** in order; each phase's tasks and done-when conditions are in
UX_PLAN.md. Summary:

- **U6 — Inversion tools.** Fitter upgrades (`from`, `fixed`, `onProgress`, resumable
  "keep looking", returned diff) **plus the hue-wrap fix above**; Compare A/B with a difference
  report, a morph slider and "how to get there"; custom hue pins as seven append-only
  parameters (`custom_hue_count`, `custom_hue_1..6`) honoured by `hues.js`.
  Two carried-over hooks: U5.2's **shift-click a library card → send it to Compare** belongs
  here, and `io.js` already exposes `fitTo(hexes)` so a pasted or saved palette can seed the
  search without another copy of the fit loop.
  Note `hue_scheme: 'custom'` currently just spreads hues evenly over `hue_span` — there is no
  way to specify custom hues at all today.
- **U7 — Correctness surface.** `diagnose.js` (near-duplicates, value holes, hue gaps, unused
  colours via `sceneUsage`, CVD collisions, contrast failures, requested-vs-achieved
  divergence) rendered as a report card where each finding applies its own fix; clamp / no-op
  detection on sliders; the dither reference's "colours worth adding" surfaced; semantic names
  in exports; an OKLCH swatch editor with an eyedropper.

### Working rules for this phase

- Put new logic in `src/core/` with a test in `test/`; keep `src/ui/` to presentation.
- After each phase: run `PALETTE_FUZZ_N=200 npm test`, check the app boots, **tick the boxes in
  UX_PLAN.md and append a running note** saying what changed, what surprised you, and anything
  the next agent must read first. That file is the memory of this phase.
- Match the surrounding comment style: comments say **why**, not what. Several files open with
  a paragraph explaining the design decision behind them; keep that up.
- Verify in the running app, not only in tests. `PORT=5299 node tools/serve.mjs --replace` and
  drive it, or `npm run render` and look at the PNGs.

### The one-line goal, to check any decision against

> Sit down with a look in mind, and reach it by **picking and steering** — not by reading 72
> tooltips and dragging sliders one at a time.
