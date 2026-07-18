# Worldgen native port — Phase 4 handoff (Graph edge routing / map painting)

Written 2026-07-18 for an agent with NO prior context. ⚠️ BOTH targets here are
OWNER-GATED — confirm the owner wants them before writing code. Read
`GDEXTENSION_PORT_HANDOFF.md` STATUS first (phases 1-3 + NoiseBake are DONE);
this doc only adds what Phase 4 needs.

## Where the time is (measured 2026-07-18, seed 12356, addon_node_test box)

Setup ~380 ms (NoiseBake native) + enabled steps ~645-880 ms. The Graph step
(~290-720 ms, heavy run-to-run variance) breaks down as:

    field (MapField, native)   ~22 ms
    GraphSpec.build_nodes       ~0 ms
    GraphPlacement.place        ~2 ms   <- the "solver" — NOT worth porting
    GraphDetail.compute_curves ~323 ms  <- 90% of the step: A* edge ROUTING

**Correction to earlier docs:** phase 2/3 STATUS notes guessed the residual was
the placement solver. Profiling shows `place()` is 2 ms; the cost is
`compute_curves` in `addons/worldgen/core/graph/graph_detail.gd`. Ignore any
"solver, owner-gated" wording elsewhere — routing is the real target.

Separately: map painting (NOT in the step timing; runs on a worker thread when
`threaded_paint`) is ~307 ms per paint — `_paint` land pass 207 + water pass 88
+ deco 9 + merge 3 (map_painter.gd / world_map_2d.gd `_paint_task`).

## Target A: GraphDetail.compute_curves (~323 ms -> expect ~10-30 ms)

`graph_detail.gd` (319 lines, all static, pure data). Per edge: A* over a
downscaled grid (`route_downscale`, default 4) with `_cell_cost` (land/water
penalty, slope weight, occupancy penalty, border/backtrack penalties), a binary
heap (`_heap_push`/`_heap_pop`), then `_los_simplify` + `_chaikin` smoothing and
`_stamp` of the taken route into `occ` so later routes avoid earlier ones.

- NO RNG anywhere in the file — fully deterministic. That removes the hardest
  bit-identity risk; this is closer to the Phase 1 numeric ports than to the
  RNG-laced Poisson work.
- State threaded through: `occ` / `node_occ` / `excl` are Dictionaries keyed by
  cell ints / Vector2i. A native port can keep them as flat byte/int grids
  internally — but the ROUTE ORDER (edge iteration order in compute_curves) and
  every tie-break in the heap must match exactly. GDScript `_heap_pop` tie
  behavior (equal f) and the neighbor expansion order in `_route` are the
  bit-identity hot spots — read them line by line.
- `_cell_cost` reads `field.dt` / `field.height` / `field.water` — pass the
  MapField's arrays in, same as the Phase 2 functions.
- Float widths: costs accumulate in GDScript doubles; heap stores f as float?
  READ THE CODE — `hf: Array` holds GDScript floats (doubles). Keep double.
- Suggested seam: port `_route` (+ its helpers `_cell_cost`, heap, heuristic)
  as ONE native call `route_edge(...) -> PackedVector2Array`, keep
  compute_curves' per-edge loop, stamping, and simplify/chaikin in GDScript
  first; measure; only pull more across the boundary if the per-call overhead
  shows. (~60 edges per map -> call overhead is negligible.)
- A/B gate: extend `tests/native_ab_test.gd` — build a real ctx/field via the
  GDScript path at 3 seeds, route every edge both ways, compare
  PackedVector2Array bytes per curve (`to_byte_array()` equality).

## Target B: map_painter `_paint` (~295 ms of the ~307 ms paint)

Only worth it if the owner cares about paint latency (it's OFF the main thread
already — it costs wall time on bakes/repaints, not gameplay frames).

- Port the WHOLE per-pixel classifier loop in `map_painter.gd _paint` to C++,
  writing into the Image via its raw RGBA8 data.
- ⚠️ RGBA8 `set_pixel` TRUNCATES: `int(clamp(v*255))` per channel — a native
  writer must reproduce exactly (bytes compared in the A/B).
- ⚠️ Do NOT instead convert set_pixel to per-byte GDScript writes — measured
  ~3x SLOWER (P14 finding, see UPSTREAM_EFFICIENCY_TODO.md item 1).
- Colors come from WorldHeightColorizer bands / biome band ramps — either pass
  flattened band tables in, or (simpler, engine-identical) pass the Resource
  objects and call their methods from C++, same pass-the-engine-object trick as
  the RNG/FastNoiseLite ports.
- `WorldBiomeDeco.scatter` (9 ms) and `merge_layers` (3 ms, already one C++
  blit) are NOT worth touching.

## Ground rules (identical to phases 1-3 — non-negotiable)

- Land in `C:\richard\gamedev\worldgen`, never edit Solatro's vendored copy.
- Bit-identical outputs, zero tolerance: arithmetic in double, narrow to float
  only where GDScript stored float32; exact loop/tie-break order.
- Build: `cd worldgen_native && scons platform=windows target=template_debug &&
  scons platform=windows target=template_release` (see `worldgen_native/BUILD.md`
  — godot-cpp master pinned via the 4.7 API dumps in `worldgen_native/api/`;
  re-copy them into godot-cpp/gdextension/ after any re-clone; `.gdignore`).
- Every call site keeps its GDScript fallback behind `if GenerationStep._native`.
- Gates (run WINDOWED — NEVER --headless for worldgen scenes, frame_post_draw
  never fires): `tests/native_ab_test.tscn` (extend it), generate_up_to,
  graph_placement, biome_regions, biome_assign, graph_spec (sampled 300 normal /
  full 1500 ~17 min), addon_bake + addon_node (no quit() — kill after PASS).
- Fallback gate: rename both dlls in `addons/worldgen/bin/` to `.off`, run
  generate_up_to_test (~150 s, slow NOT hung), restore.
- Vendor: copy changed .gd files (not README) + `addons/worldgen/bin/` into
  `C:\richard\gamedev\solatro\addons\worldgen\`, run `--headless --import`
  (twice if uid errors), then the full suite:
  `C:\richard\Godot_v4.7-stable_win64_console.exe --headless --path
  C:\richard\gamedev\solatro res://Tests/all_tests.tscn` — exit code = failure
  count; ALL suites green (24 as of 2026-07-18; count the run's own banner).
- On completion update: `GDEXTENSION_PORT_HANDOFF.md` STATUS, this file,
  `solatro/todo.md` §Performance, `solatro/EFFICIENCY_AUDIT_TRACKER.md` (dated
  entry), with before/after timings.
