# Pixel-Art Palette Creator

Procedural retro palette generator in OKLCH space. Generates structurally-sound
pixel-art palettes from 58 tunable parameters, proves they work by applying them to a
gallery of test visuals, and exports to Godot, Aseprite, and the web.

**Status: Phases 1–3 of 4 complete and gated.** The generator, the browser app, and the
34-scene test gallery are done and tested (176 tests green). The artist's-palette picker
(Phase 4) is not built yet.

| Document | What it is |
|---|---|
| [PLAN.md](PLAN.md) | The specification — colour theory, algorithms, formulas, task list |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The `Palette` contract, design decisions, per-phase notes (§9 app, §10 gallery, §11 Phase-4 start) |
| [PROGRESS.md](PROGRESS.md) | Task-by-task state. Source of truth for what is done |

New to the project? Read PLAN.md for *what* is being built, then ARCHITECTURE.md for
*how the built part works* and what the next phase has to build on. Everything you need
is in this directory — no setup outside the repository, and nothing to install.

## Requirements

Node 20 or newer, and nothing else — no dependencies to install. The `test` script uses
`node --test test/*.test.js` (a glob, because Node 24 no longer accepts a bare directory
argument).

## Running it

**Double-click `start.cmd`.** It boots the local server and opens the app in your browser —
no command line needed for anything, including adding your own reference images.

The rest is for working on the code.

```bash
npm test
```

276 tests: colour-space round-trips against published reference values, gamut mapping,
bit-depth quantisation, generator invariants across every palette size from 4 to 64, seed
round-trips, export round-trips, the dev-server API, the raster/analysis/dither modules, a
34-scene smoke test, the picker layouts and colour-space maps, the recolour paths, the GIF
codec, golden snapshots, and a 10,000-case fuzz. Takes about 6 minutes;
`PALETTE_FUZZ_N=200 npm test` shortens the fuzz while iterating.

```bash
npm start
```

Starts the dependency-free dev server (default `http://localhost:5173/`) and serves the
browser app: live parameter sliders, a swatch grid with lock/override, undo/redo and a
history strip, seed field with URL-hash sync, save/load against `saved/*.json`, all eight
export formats, the **34-scene test gallery** (category filter, colour-vision views, zoom,
animation, drag-and-drop photo quantization), the **artist's-palette picker** (colour-space
maps by default, 15 arrangement layouts behind a selector), and the **recolour page** —
every reference image re-rendered in the generated palette, animations included, playing.

```bash
npm run render
```

Writes labelled swatch sheets, export strips, a preset contact sheet, a budget sweep, every
gallery scene (per-scene PNGs plus per-category contact sheets, for two palettes), the picker
layouts and colour-space maps, and the recoloured reference images — including real animated
GIFs in `out/recolor/` — to `out/` for direct inspection. These are meant to be looked at: a
palette can pass every test and still be wrong.

```bash
npm run build
```

Inlines the whole app into one double-clickable `dist/palette_creator.html` (a flat import
map of base64 data-URL modules — no bundler). Seeds and export/import work there; the
file-backed save API does not (there is no server behind it).

```js
import { generatePalette, paletteHexes } from './src/core/generate.js';
import { presetParams } from './src/core/presets.js';
import { runExport } from './src/core/export/index.js';

const palette = generatePalette(presetParams('snes'));
paletteHexes(palette);              // ['#0D0A18', '#3A2100', …]
palette.seed;                       // 'PAL1-…' — paste back to reproduce exactly
runExport('tres', palette);         // Godot resource, ready for solatro/ or necroma/
```

## Not built yet

- **Phase 4 — Picker.** 15 artist's-palette layout algorithms (SOM, annealing, Hilbert
  sort, Voronoi, organic growth, …) with objective mean/worst-neighbour ΔE scoring and a
  contact sheet. See ARCHITECTURE.md §11 for where to start.

## Layout

| Path | Purpose |
|---|---|
| `src/core/` | DOM-free colour maths, generation, `raster`/`analysis`/`dither` — imported by both browser and Node |
| `src/core/export/` | Output format writers: gpl, pal, hex, lospec, css, json, tres, png |
| `src/ui/` | Browser app: `app sliders swatches history io gallery` |
| `src/scenes/` | The 34 gallery scenes (DOM-free) + `index` registry + `util` role accessors |
| `test/` | `node --test` suite and golden snapshots |
| `tools/` | Dev server, standalone build, headless renderer, PNG codec, drawing surfaces |
| `saved/` | Your saved parameter sets (git-tracked) |
| `out/`, `dist/` | Rendered PNGs and the standalone build (gitignored) |

No runtime dependencies — Node built-ins and vanilla ES modules only. Nothing under
`src/core/` may import a Node built-in; that constraint is what lets the same code run in
the browser, under `node --test`, and in the headless renderer.
