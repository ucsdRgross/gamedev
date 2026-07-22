# Pixel-Art Palette Creator

Procedural retro palette generator in OKLCH space. Generates structurally-sound
pixel-art palettes from 58 tunable parameters, proves they work by applying them to a
gallery of test visuals, and exports to Godot, Aseprite, and the web.

**Status: Phase 1 of 4 complete.** The generator, all colour maths, presets, exports and
the headless renderer are done and tested. The browser app, the test-visual gallery and
the artist's-palette picker are not built yet.

| Document | What it is |
|---|---|
| [PLAN.md](PLAN.md) | The specification — colour theory, algorithms, formulas, task list |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The `Palette` contract, design decisions, known limitations |
| [PROGRESS.md](PROGRESS.md) | Task-by-task state. Source of truth for what is done |

New to the project? Read PLAN.md for *what* is being built, then ARCHITECTURE.md for
*how the built part works* and what the next phase has to build on. Everything you need
is in this directory — no setup outside the repository, and nothing to install.

## Requirements

Node 20 or newer, and nothing else. There are no dependencies to install and no build
step; `npm test` works on a fresh clone. Node 20 is required for `node --test` with a
directory argument and for the test runner's TAP output.

## What works today

```bash
npm test
```

140 tests: colour-space round-trips against published reference values, gamut mapping,
bit-depth quantisation, generator invariants across every palette size from 4 to 64,
seed round-trips, export round-trips, golden snapshots, and a 10,000-case fuzz. Takes
about 4.5 minutes; `PALETTE_FUZZ_N=200 npm test` shortens the fuzz while iterating.

```bash
npm run render
```

Writes labelled swatch sheets, export strips, a preset contact sheet and a budget sweep
to `out/*.png` for direct inspection. These are meant to be looked at — a palette can
pass every test and still be wrong.

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

```bash
npm start   # Phase 2 — no tools/serve.mjs yet
npm run build
```

- **Phase 2 — App.** Browser UI: sliders, swatch grid with lock/override, undo/redo,
  seed field with URL-hash sync, save/load, export buttons, standalone build.
- **Phase 3 — Gallery.** 34 test visuals with value-only, colourblind and zoom toggles.
- **Phase 4 — Picker.** 15 artist's-palette layout algorithms with objective scoring.

## Layout

| Path | Purpose |
|---|---|
| `src/core/` | DOM-free colour maths and generation — imported by both browser and Node |
| `src/core/export/` | Output format writers: gpl, pal, hex, lospec, css, json, tres, png |
| `test/` | `node --test` suite and golden snapshots |
| `tools/` | Headless renderer, PNG codec, drawing surface |
| `saved/` | Your saved parameter sets (git-tracked) |
| `out/` | Rendered PNGs (gitignored) |

No runtime dependencies — Node built-ins and vanilla ES modules only. Nothing under
`src/core/` may import a Node built-in; that constraint is what lets the same code run
in the browser, under `node --test`, and in the headless renderer.
