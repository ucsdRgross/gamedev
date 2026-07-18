# Worldgen native port — Phase 2 handoff (Graph / MapField)

**STATUS: DONE 2026-07-17.** All of MapField's hot path is native:
`_label_landmasses`, `_build_distance_transform`, `build_land_samples` (Poisson +
jittered), plus `_measure_land` (profiling: masks 15 / label 2 / measure 113 /
dt 2 / samples 4 ms after the first three ports — measure_land was the real
remaining cost; `_build_masks` stays GDScript at 15 ms). The RNG problem in item 3
was solved by using the engine's own RandomNumberGenerator from godot-cpp
(`Ref<RandomNumberGenerator>` + set_seed) — identical sequence by construction.
A/B gate extended (labels/sizes/seeds/main_label, measure_land, dt, poisson,
poisson-confine_main, jittered; 30 checks, 3 seeds, all bit-identical).
Before/after seed 12356 (addon_node_test): Graph **933 -> 383 ms**, enabled steps
**1829 -> 1212 ms**. Graph solver NOT ported (per scope rule below). All scene
gates + fallback (~150 s, dlls off) + Solatro 23-suite run green — see
GDEXTENSION_PORT_HANDOFF.md STATUS. Next: Phase 3 (Biomes, ~300 ms / 25%).

Written 2026-07-17 for an agent with NO prior context. Phase 1 (Rivers) is DONE —
read `GDEXTENSION_PORT_HANDOFF.md` STATUS first; this doc only adds what Phase 2 needs.

## Where you are

- Repo: `C:\richard\gamedev\worldgen` (canonical). Solatro vendors it at
  `C:\richard\gamedev\solatro\addons\worldgen\` — NEVER edit the vendored copy;
  land here, validate, re-copy changed files (not README.md) + `addons/worldgen/bin/`.
- A working GDExtension already exists: `worldgen_native/` (SConstruct, src/,
  godot-cpp master pinned to the Godot 4.7 API via the dumps in `worldgen_native/api/`
  — see `worldgen_native/BUILD.md`, including the re-clone rule and the `.gdignore`
  gotcha). Build:
  `cd worldgen_native && scons platform=windows target=template_debug && scons platform=windows target=template_release`
  Output lands in `addons/worldgen/bin/` automatically.
- The native class is `WorldgenNative` (src/worldgen_native.cpp). GDScript reaches it
  through `GenerationStep._native` (see `core/world_gen_step.gd`) — a cached instance,
  null when the dll is missing. EVERY call site keeps its GDScript path as fallback:
  `if _native: return _native.foo(...)` then the original code.
- Current timing (owner's box, seed 12356, addon_node_test): enabled steps ~1829-2898 ms,
  **Graph 933-1633 ms = 51-56% (the target)**, Biomes ~20% (Phase 3),
  Rivers_Only 256-395 ms (done).

## Phase 2 target: `addons/worldgen/core/graph/graph_placement.gd` MapField

MapField (class at top of file, built in `MapField.from_generator`) is pure data and
already thread-safe. Hot candidates, port in this order and MEASURE after each
(addon_node_test prints per-step times; kill the scene after the PASS lines — no quit()):

1. `_label_landmasses()` — connected-component labeling over the water mask.
2. `_build_distance_transform(ds)` — two-pass signed chamfer DT on a downscaled grid.
3. `build_land_samples(spacing, seed, poisson)` — blue-noise/Poisson land sampling.
   ⚠️ Uses the generator's seeded RNG — the native port must consume random numbers in
   EXACTLY the same sequence/order or outputs diverge. If it uses RandomNumberGenerator,
   pass the seed/state in and replicate Godot's RNG (Xoshiro/PCG — check the class) or
   keep the RNG calls in GDScript and port only the deterministic geometry around them.
4. `_build_masks()` — trivial O(n) loops; port only if profiling says so.

Do NOT port the graph solver itself (place/_create_edges/_connect_rows...) — it is
RNG- and Dictionary-heavy; renegotiate scope with the owner first if MapField alone
doesn't dent the 51%.

## Ground rules (same as Phase 1 — non-negotiable)

- **Bit-identical outputs.** GDScript arithmetic is 64-bit double; PackedFloat32Array
  storage is float32. In C++: load elements to double, compute in double, cast to float
  only on store. `int(x)` truncates toward zero. Keep exact loop order and tie-breaks.
  Zero tolerance unless the owner approves a divergence.
- Add each ported function to the A/B gate `tests/native_ab_test.gd` (pattern is
  there: run native + forced-GDScript (`GenerationStep._native = null`, restore after)
  on real generated inputs, seeds 12356/777/424242, diff element-by-element, print
  native-vs-gd ms). Run WINDOWED: `C:\richard\Godot_v4.7-stable_win64_console.exe --path . res://tests/native_ab_test.tscn`
  — NEVER --headless for worldgen scenes (frame_post_draw never fires; they stall).
- Fallback gate: rename both dlls in `addons/worldgen/bin/` to `.off`, re-run
  `res://tests/generate_up_to_test.tscn` — it PASSES but takes ~150 s without the dll
  (slow, NOT hung; give it 5+ min before declaring a hang). Restore the dlls after.
- Scene gates with the dll: generate_up_to, graph_placement_test, biome_regions_test,
  biome_assign_test, graph_spec_test (sampled 300 is the normal gate; full 1500 ~17 min),
  addon_bake_test + addon_node_test (no quit() — kill after PASS lines).
- Vendor to Solatro: copy changed .gd files + `addons/worldgen/bin/` into
  `solatro/addons/worldgen/`, then
  `C:\richard\Godot_v4.7-stable_win64_console.exe --headless --path C:\richard\gamedev\solatro --import`
  (run twice if the first prints uid errors), then the full suite:
  `...win64_console.exe --headless --path C:\richard\gamedev\solatro res://Tests/all_tests.tscn`
  — exit code = failure count; bar is ALL 23 SUITES green (1254 checks as of Phase 1).
- Any board/game mutation rule, tracker etiquette, etc.: `solatro/todo.md` +
  `solatro/EFFICIENCY_AUDIT_TRACKER.md` (append a dated entry when you land).
- Update on completion: `GDEXTENSION_PORT_HANDOFF.md` STATUS, this file, solatro/todo.md
  §Performance, EFFICIENCY_AUDIT_TRACKER.md, and record before/after Graph timings.

## Remaining phases after this one

- Phase 3: DONE 2026-07-18 — `biome_build_cells` native (flood 337 -> ~9 ms; Biomes
  step 300 -> 33 ms). paint_cells (the voting/RNG part) stays GDScript: measured 3 ms.
- Rivers residual cleanup: DONE 2026-07-18 — execute()'s five loops extracted into
  StepRivers methods with native twins (Rivers_Only 263 -> 63 ms). See
  GDEXTENSION_PORT_HANDOFF.md STATUS for details.
- Phase 4 (only if owner asks): `painting/map_painter.gd` `_paint` wholesale in C++.
  ⚠️ RGBA8 `set_pixel` TRUNCATES (`int(clamp(v*255))`) — must reproduce exactly.
  Do NOT convert set_pixel to per-byte GDScript writes (measured ~3x slower).
