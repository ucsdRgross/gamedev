---
name: palette-project-facts
description: palette/ pixel-art palette generator — all phases done + external-palette recolour, hue-adaptive lightness, parameters-from-image fitter; read ARCHITECTURE.md then PROGRESS.md first; npm test slow (10k fuzz)
metadata: 
  node_type: memory
  type: project
  originSessionId: 7b23bf1e-c45a-4d51-ada4-7bc4c641ecf8
  modified: 2026-07-23T22:21:14.306Z
---

`palette/` is a self-contained OKLCH pixel-art palette generator (vanilla ES modules,
zero runtime deps, `node --test`). **Every phase in the plan was completed 2026-07-22**:
core generator, browser app, 34-scene test gallery, the 15-variant artist's-palette picker,
the colour-space maps that are now the picker's default view, and reference-image
recolouring (indexed + quantize paths, own GIF codec, animations recoloured whole and played
back). Run it by **double-clicking `palette/start.cmd`** — no command line anywhere; a second
double-click restarts (ping/shutdown handshake in serve.mjs).

Post-plan additions (also 2026-07-22): recolour into an **external palette** loaded from an
image (`palettes/` folder + `/api/palettes`; `recolor/swatches.js` extraction — a ≤2px strip
is authoritative/every distinct colour, taller images are de-aliased). Recolour has **no
randomness**; the only thing that moves a recolour is the generated palette under it — an
external palette holds it still. The **Randomize button excludes the whole `recolor` group**
(`src/ui/randomize.js`, extracted from app.js to be testable, excludes by group so future
recolour params are covered). Every parameter's `params.js` doc string now gives
what/why/when/direction, shown via a custom hover tooltip in `sliders.js`; the README has a
full parameter reference + look-recipes + a "freezing randomness / locking colours" section.
PROGRESS.md now has a **"Post-plan enhancements"** section, and PLAN.md a build-status banner,
so a future contributor with no context has a single trail: PLAN (spec+status) → PROGRESS
(what shipped, incl. post-plan) → ARCHITECTURE (§12.6 external palettes, §12.7 bugs).

Post-plan additions (2026-07-23): **`hue_lightness_follow`** — hue-adaptive midtone lightness
that biases each hue toward its own sRGB gamut cusp (yellow/green/cyan only hold chroma at high
L, so at a shared `l_mid_base` they went olive; this rides them up). Default 0.5 (on); **existing
presets pin it to 0** via a loop in `presets.js` so their snapshots are unchanged (only seed
strings grew); loud-colour presets opt in — OKLAB Crayon 0.975, Neon Cyberpunk 0.7, Toxic Swamp
0.55, Sunset Desert 0.4. Mechanism is `hueMidLightness` in `generate.js` (ARCHITECTURE §3.8).
**`COLOR_GUIDE.md`** documents each hue's sRGB saturation ceiling + the lightness it peaks at
(hues are NOT equally saturable — cyan/gold ~0.15, magenta/violet/green ~0.3) with param recipes.

Two more things settled 2026-07-23:
- **Param ranges are seed-relative.** `u16ToParam` decodes `min + (u/65535)*(max-min)`, so
  changing any param's min/max silently reinterprets that field in every previously-saved PAL1
  seed string. Saved `.json`, presets and exports store real values and are safe. `l_mid_base`
  max was raised 0.80→0.92 and `l_variance_per_hue` 0.15→0.30 on that basis (owner accepted the
  seed drift). Note a ramp is clamped to fit *entirely* under `l_light_anchor`, so raising
  `l_mid_base` alone does not lift the midtone — you also need a high anchor and a small `l_step`.
- **The picker's 4 saturation slices are a COVERAGE device, not foreground/background views** —
  each map paints the nearest palette colour, so one slice reaches ~45/48 and four reach 48/48.
  The layer question is answered by the "which colours go where" bands (`layerBands()`) and, better,
  by the **`Map — by context` view**: `buildColorMap` takes an `entries` pool, so restricting the
  candidate set turns the same geometry into a per-context chart where a colour keeps its position.
  `MAP_CONTEXTS`/`buildContextMaps` (`colorspace.js`) define everything/sprites/scenery/sky/ui/fx
  from `entry.layer` + ramp position + `palette.semantics`; `contextSheet` (`render.js`) draws them.
  fg and bg are two deliberately disjoint sets with `fg_bg_separation_min` enforced between them —
  keep bg colours off sprites; the sprites/scenery rows being near-complementary IS that constraint
  made visible. And a **parameters-from-image fitter** (`src/core/fit.js`:
`paletteFit`/`inferStructure`/`makeFitter`/`fitParams` — symmetric mean-nearest-ΔE + seeded
random-restart hill climb), driven by the **Fit to image…** UI button (`io.js` runs it in rAF
slices → applies like a preset; edge decode shared via `src/ui/imagefile.js`). OKLAB Crayon was
fitted offline to a reference strip (ΔE ≈ 3.1). ARCHITECTURE §13. The layout baseline test was
also corrected: som-disc at K=32 was already seed-fragile (lost on 6/8 seeds on pristine), so the
"every optimized variant beats baseline" bar is now K≥48, best-variant at K=32.

Reading order for any work in this directory:
1. `palette/ARCHITECTURE.md` — the `Palette` object contract, the design decisions that
   extend the plan, and the limitations that are contracts rather than bugs. §11 covers
   the picker and, importantly, the dead ends that were measured and rejected.
2. `palette/PROGRESS.md` — task-by-task state.
3. `palette/PLAN.md` — the full spec.

All three docs are repo-relative and self-contained — the executing agent may work on a
different machine, so nothing may reference a local path or these memory notes.

Non-obvious operational facts:
- `npm test` takes ~6 minutes because of a 10,000-case fuzz. Use
  `PALETTE_FUZZ_N=200 npm test` while iterating. Adding parameters shifts the fuzz's random
  stream, so it explores different corners and can surface pre-existing bugs — expect that,
  and diagnose rather than loosen the assertion.
- Node is **not on the tool-shell PATH** on this machine: prepend
  `$env:Path = "C:\Program Files\nodejs;$env:Path"` to every command.
- **Needs Node ≥ 22.** The `test` script is `node --test test/*.test.js` and relies on the
  runner's own glob expansion: npm runs scripts through `cmd.exe` on Windows, which does
  not expand globs, and Node 20's runner does not either — so on Node 20 `npm test`
  silently finds no test files and exits 1. Node was upgraded to v26.4.0 on this machine.
- Run `npm` from `palette/`, not the repo root — there is an unrelated `package.json` in
  the user's home directory that npm walks up to and finds instead.
- Golden snapshots in `test/snapshots/` fail on any algorithm change by design;
  re-record with `UPDATE_SNAPSHOTS=1 npm test` only after reviewing the diff.
- `npm run render` writes inspectable sheets to `out/`. **Reading those images caught
  bugs every test passed** — a preset retune in Phase 1, and the stranded-cell bug in the
  picker in Phase 4. Do it, don't skip it.
- `min_delta_e` / `force_unique_hex` are best-effort by design and report misses in
  `palette.warnings`. Don't "fix" that into a throw.

Follows [[no-git-staging]] and [[code-style-lean-documented]]. Unlike the Godot projects
here, this one is fully self-verifiable — see [[running-godot-scenes]] for why Godot was
rejected as the authoring tool.
