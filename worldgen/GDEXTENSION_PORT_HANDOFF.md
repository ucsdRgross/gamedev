# Worldgen C++ / GDExtension port — implementation handoff

Written 2026-07-17 for the agent (or human) who picks up the port. Context: the 2026-07
efficiency audit took every behavior-identical GDScript win (P14 batch, measured ~6.5%);
the remaining generation time is pure-CPU GDScript hot loops that need native code.
Owner-endorsed in `solatro/todo.md` §Performance.

**STATUS: PHASE 1 (Rivers, item 1) DONE 2026-07-17.** Toolchain installed (MSVC 19.51
+ SCons 4.10). `worldgen_native/` GDExtension built and vendored; `fill_depressions`,
`flow_accumulate_mfd`, `_box_blur`, `_dilate_lake` are native with GDScript fallbacks.
A/B bit-identical on seeds 12356/777/424242 (`tests/native_ab_test.tscn`); fallback
verified with dlls renamed away; all worldgen scenes + full Solatro suite (23 suites,
1254 checks) green. Timing seed 12356 (addon_node_test, enabled-steps avg):
**5287 -> 1829 ms**; Rivers_Only ~3.4 s -> **256 ms** (native fns run in 4-21 ms each,
25-400x). Graph is now the top cost (933 ms, 51%) — items 2-4 below remain.
Build notes: `worldgen_native/BUILD.md` (godot-cpp master pinned via 4.7 API dump —
upstream has no 4.6/4.7 branch). Phase 2 (Graph/MapField) handoff:
`GDEXTENSION_PHASE2_HANDOFF.md`.

**PHASE 2 (Graph/MapField, item 2) DONE 2026-07-17.** Native `label_landmasses`,
`map_distance_transform`, `poisson_land_samples` + `jittered_land_samples`,
`measure_land` (profiling showed `_measure_land` was 113 ms — bigger than the three
planned targets combined post-port; `_build_masks` left in GDScript at 15 ms).
Poisson determinism solved by instantiating the ENGINE's own RandomNumberGenerator
from godot-cpp (`Ref<RandomNumberGenerator>`), so the random sequence is identical
by construction — no RNG reimplementation. A/B bit-identical on seeds
12356/777/424242 incl. a confine_main variant (30 checks). Timing seed 12356
(addon_node_test, enabled-steps avg): **1829 -> 1212 ms**; Graph 933 -> **383 ms**
(remaining Graph cost is the solver — out of scope per Phase 2 handoff). Per-fn
native-vs-gd ms: labels 1 vs 182, dt 2 vs 150, poisson 6 vs 139, measure 0 vs 107.
Biomes (~300 ms, 25%) is now the top single step — Phase 3.

**PHASE 3 (Biomes, item 3) + RIVERS RESIDUAL CLEANUP DONE 2026-07-18.** Native
`biome_build_cells` (the entire warped Dial flood + orphan labeling + stats/adjacency
of `BiomeRegions.build_cells`; paint_cells left in GDScript at 3 ms — RNG/dict-heavy
and cheap). adj Dictionaries are built natively with the exact GDScript insertion
order so `for nb in adj[c]` iteration downstream matches. Rivers residual: the five
inline execute() loops were extracted into StepRivers methods with native twins —
`river_downsample` / `river_seed_field` (humidity read via the engine's own
Image.get_pixel from C++) / `river_depth_stamp` / `river_lake_surfaces` /
`river_apply_water`. A/B gate now 48 checks x nothing-lost, 3 seeds, all
bit-identical. Timing seed 12356 (addon_node_test, enabled-steps): **1212 -> 879 ms**
(from 5287 pre-port); Biomes 300 -> **33 ms**, Rivers_Only 263 -> **63 ms**. Graph
(~380-500 ms, run-to-run variance) is now ~57% of step time — all solver, which
stays GDScript unless the owner approves a Phase 4 renegotiation. Remaining native
candidates: map_painter `_paint` (Phase 4, owner-gated).

## Ground rules (same as all worldgen work)

- Land HERE (`C:\richard\gamedev\worldgen`) first, validate, then re-copy changed files
  into `solatro/addons/worldgen/` — NEVER edit Solatro's vendored copy. Keep Solatro's
  `addons/worldgen/README.md` vendored banner (copy changed files, not the README).
- **Outputs must stay bit-identical** to the GDScript implementation, or get explicit
  owner approval for any divergence. Verify with buffer-compare harnesses (pattern: the
  P14 items were verified by running old + new on the same seed and diffing the raw
  buffers/images — see UPSTREAM_EFFICIENCY_TODO.md item 1 notes).
- The GDScript implementations STAY in the repo as the fallback path (see "Fallback"
  below). The port must be a drop-in acceleration, not a replacement.

## Port candidates, in impact order (measured seed 12356, GTX 1070 box)

Rivers_Only is ~60-75% of step time; Graph ~15-23%. From `UPSTREAM_EFFICIENCY_TODO.md`:

1. `addons/worldgen/core/steps/rivers.gd` — hydrology. The big three inner loops:
   `fill_depressions` (priority-flood over the downscaled height grid),
   `flow_accumulate_mfd` (multi-flow-direction accumulation), and the lake
   labeling/dilation passes. Biggest single win; port these first and measure before
   touching anything else.
2. `addons/worldgen/core/graph/graph_placement.gd` — MapField: landmass labeling,
   chamfer distance transform, Poisson land sampling. Pure data, already thread-safe.
3. `addons/worldgen/core/biomes/biome_regions.gd` — region flood fill / voting.
4. `addons/worldgen/painting/map_painter.gd` `_paint` — per-pixel classifier ONLY if
   ported wholesale to C++. ⚠️ Do NOT convert its `set_pixel` calls to raw byte writes
   in GDScript — measured ~3x SLOWER there (one C++ call beats 4 indexed stores).
   Also: RGBA8 `set_pixel` TRUNCATES (`int(clamp(v*255))`), not rounds — a C++ rewrite
   must reproduce that exactly or images won't be bit-identical.

## Bit-identical trap: float widths

GDScript floats are 64-bit doubles; standard Godot builds use `real_t = float` (32-bit)
in much of core. Do the math in the C++ port in **double** wherever the GDScript did
arithmetic, and only narrow where the GDScript itself stored into 32-bit
(PackedFloat32Array elements). This is the most likely source of "almost identical"
outputs — decide the width per expression by reading the GDScript, not by habit.
Iteration ORDER also matters for the priority-flood and voting passes (ties!) — keep the
exact queue/tie-break order of the GDScript.

## Suggested structure

- `worldgen_native/` (new, in this repo): `SConstruct`, `src/`, godot-cpp as a git
  submodule or sibling checkout pinned to the `4.7` branch.
- Ship the built library + `worldgen.gdextension` inside `addons/worldgen/bin/` so the
  vendor-copy into Solatro carries it (win64 template_debug + template_release at
  minimum; other platforms only if the owner asks).
- Expose ONE class (e.g. `WorldgenNative extends RefCounted`) with static-style methods
  taking/returning packed arrays: e.g.
  `fill_depressions(height: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array`.
  Packed arrays cross the GDExtension boundary by COW reference — no copying cost.

## Fallback wiring (required)

At each call site in the .gd step, branch once:
`if ClassDB.class_exists(&"WorldgenNative"): <native call> else: <existing GDScript path>`
(cache the check in a static). Solatro must keep working if the .dll is missing or the
platform is unsupported; the test scenes must pass BOTH ways (run once with the .dll
renamed away).

## Validation checklist (per ported function)

1. A/B harness in this repo: run GDScript + native on the same inputs (seed 12356 at
   least, plus a couple of random seeds), diff the output buffers element-by-element.
   Zero tolerance unless owner-approved.
2. Worldgen test scenes — run WINDOWED, never `--headless` (Godot 4.7 headless never
   fires `frame_post_draw`; pipeline scenes stall forever — see solatro/HEADLESS_TESTING.md):
   `Godot --path . res://tests/<scene>.tscn` for generate_up_to / graph_placement /
   biome scenes; `addon_bake_test`/`addon_node_test` have no quit() — kill after PASS.
   `graph_spec_test`'s full 1500-spec fuzz takes ~17 min; the sampled 300-spec run is
   the normal gate.
3. Timing: addon_node_test prints per-step times; baseline (2026-07-17, seed 12356,
   enabled steps avg) is ~5287 ms with Rivers dominating. Record before/after in this
   file.
4. Re-copy to Solatro (changed files + new bin/, not README), run `--import`, then the
   full Solatro suite:
   `C:\richard\Godot_v4.7-stable_win64_console.exe --headless --path C:\richard\gamedev\solatro res://Tests/all_tests.tscn`
   (exit code = failure count; ALL 23 SUITES green is the bar).
5. Update: this file's STATUS, UPSTREAM_EFFICIENCY_TODO.md, solatro/todo.md, and
   solatro's tracker/handoff per its ground rules.

## Reference docs

- `PIPELINE.md` (this repo) — step architecture.
- `UPSTREAM_EFFICIENCY_TODO.md` — the 2026-07-17 GDScript batch notes (incl. what NOT
  to redo, e.g. set_pixel vs byte writes).
- `solatro/HEADLESS_TESTING.md` — headless traps (frame_post_draw, class cache).
- godot-cpp: https://github.com/godotengine/godot-cpp (branch `4.7`), GDExtension docs:
  https://docs.godotengine.org/en/4.7/tutorials/scripting/gdextension/
