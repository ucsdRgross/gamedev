# Handoff — Pixel Palette Creator, UX phase

Paste-able briefing for an agent with **no prior context**. Read this, then
[UX_PLAN.md](UX_PLAN.md) (the task tracker), then the two files named in "Read before you
touch X" below. Everything is in `C:\richard\gamedev\palette`.

---

## 1. What the project is

A dependency-free, procedural **pixel-art colour palette generator** written in vanilla ES
modules. It turns 72 parameters into a structurally-sound palette in OKLCH space, proves the
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
| `src/ui/` | Browser app modules (`app sliders swatches history io randomize gallery picker recolor variants sizes strip`) |
| `src/scenes/` | The 34 gallery scenes (DOM-free) + registry + semantic role accessors |
| `test/` | `node --test` suite (411 tests) and golden snapshots |
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
  `PALETTE_FUZZ_N=200 npm test` (~17 s, still 411 tests).
- Run the app: `npm start` (port 5173), or `PORT=5299 node tools/serve.mjs --replace` if you
  want a port that will not collide with the user's own instance. Double-clicking `start.cmd`
  is the user's way in; a second double-click is a restart (ping/shutdown handshake).
- Snapshots: `UPDATE_SNAPSHOTS=1 npm test` — only after reviewing the diff deliberately.
- `npm run render` writes every preset, scene, layout, map, dither sheet and recoloured
  reference to `out/`. **Look at the output**; a palette can pass every test and still be wrong.

---

## 3. Where the work stands

`npm test` **green at 411** (was 370 at the start of the phase). `npm run build` green.
**Nothing is committed** — the whole phase is in the working tree. The user has not asked for
commits; do not commit unless asked.

Phases **U1, U2, U3 are done**. **U4, U5, U6, U7 are not started.** Full detail, including
per-task done-when conditions, is in UX_PLAN.md; the running notes at the bottom of that file
record what was built and what surprised.

### What U1–U3 added (so you do not re-derive it)

**New core modules** (all DOM-free, all tested):

- `src/core/paramui.js` — `PARAM_UI` (label / hint / low / high / enum option labels for all 72
  parameters) and `BASIC_PARAMS`. Deliberately **separate from `params.js`**, which is
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

## 5. Open issue you will trip over: the fitter's hue-wrap bug

`src/core/fit.js:111` decides which parameters wrap at 360° with
`name === 'root_hue' || name.endsWith('_hue') || name.endsWith('_hue_target')`.
That test wrongly catches **`l_variance_per_hue`** and **`chroma_variance_per_hue`**, which are
not angles: a small negative step becomes 359.98 and then clamps to the parameter's *maximum*.

The same bug was fixed in `src/ui/randomize.js` (it made a "gentle" variation slam per-hue
variance to its ceiling) by listing the real angles explicitly — `ANGULAR_PARAMS` /
`isAngularParam` in `src/core/params.js`, with two tests pinning it.

**It is still present in `fit.js` on purpose.** The accidental jump-to-an-extreme is
load-bearing exploration for that search, and both thresholds in `test/fit.test.js` are tuned
around it. Measured over five RNG seeds (lower is better; the tests use seed 3, in bold):

| variant | recovery target, 3000 iters | crayon target, 4000 iters |
|---|---|---|
| as committed (buggy wrap) | 3.50 3.73 **3.10** 3.69 4.64 | 5.15 3.74 **4.11** 4.58 4.13 |
| wrap fixed, no compensation | (seed 3 → 4.33) | 5.42 4.53 **6.17** 4.38 3.82 |
| wrap fixed + 12% uniform jumps | 3.90 3.85 **4.37** 3.08 3.93 | 4.70 5.54 **3.46** 7.07 4.64 |

Fix it in **U6.1**, where the fitter is being reworked anyway: correct the wrap, re-tune the
search (an annealed jump rate is the promising direction — bold early in a restart, none at the
end), and re-baseline the test thresholds against a multi-seed benchmark instead of one seed.
Related: PROGRESS.md says `l_variance_per_hue`'s ceiling was raised 0.15 → 0.30 because fitting
real palettes "pinned it at the old ceiling" — that evidence is suspect, since this bug pinned
it there by construction.

---

## 6. What to do next

Work **U4 → U5 → U6 → U7** in order; each phase's tasks and done-when conditions are in
UX_PLAN.md. Summary:

- **U4 — Seeing it.** Pinned hero scene above the gallery that never scrolls away while
  tuning; 1× zoom (the gallery currently starts at 2×); new composed 256×192 mockup scenes
  (HUD + tilemap + character + text at three sizes + inventory); a pinned row of **real**
  reference art recoloured into the palette; side-by-side colour-vision views; a Ramps view in
  the palette pane (built on `rampsOf()` in `analysis.js`); a Freeze toggle that zeroes
  `hue_jitter` / `l_variance_per_hue` / `chroma_variance_per_hue`.
- **U5 — Keeping and starting.** One-click **Keep** with an auto-generated name; a visual
  library of saves; persistence and an autosave ring; a preset thumbnail grid; a dismissible
  start screen with mood chips; `parseHexList` paste ingestion. Context: `saved/` is **empty**
  while `saved_palettes.txt.txt` in the project root holds a hand-pasted seed — the save path
  is losing to a text file, and that is the problem U5 exists to fix.
- **U6 — Inversion tools.** Fitter upgrades (`from`, `fixed`, `onProgress`, resumable
  "keep looking", returned diff) **plus the hue-wrap fix above**; Compare A/B with a difference
  report, a morph slider and "how to get there"; custom hue pins as seven append-only
  parameters (`custom_hue_count`, `custom_hue_1..6`) honoured by `hues.js`.
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
