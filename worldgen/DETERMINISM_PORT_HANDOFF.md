# Deterministic terrain port — handoff (written 2026-07-18)

> **STATUS: COMPLETE 2026-07-18.** All four steps ported, `deterministic_terrain`
> default **true**, vendored into Solatro (24 suites / 1291 checks green). Acceptance
> test passed: the two-renderer bake now matches byte-for-byte on `graph.json` *and*
> on `land/water/composite.png`. Full-chain divergence from the old GPU look:
> max|d|~0.028, land/water mask flips 71 px (0.027%). Erosion was row-parallelised
> (deterministic by construction) taking enabled steps 2076 -> 527 ms. Measurements
> and the per-step notes now live in `DETERMINISM_FINDINGS.md` §Option A; this file is
> kept as the record of the task as briefed.

For an agent with ZERO prior context. Goal: make map generation produce the SAME
result on every machine. Step 1 of 4 is done; you are doing steps 2-4.

## Why this exists

The four heightmap steps (Landmass, Tectonics, Peaks, Erosion) are GPU shader passes
read back at float32. GLSL leaves `sin`/`cos`/`atan`/`pow`/`exp`/`smoothstep`/`texture`
precision implementation-defined, so **the same seed yields a different map on
different hardware** — and not just cosmetically: measured against another machine's
committed debug images, graph edge routes and node markers physically move (6.8% of
pixels differ, 3.5% structural). Solatro generates each player's map at runtime
(`solatro/Scripts/Map/world_map_controller.gd:64`), so seeds are not shareable and bug
reports don't reproduce. Everything downstream of the heightmap (Rivers, Graph,
Biomes) is already deterministic CPU code. Full evidence: `DETERMINISM_FINDINGS.md`.

Owner decision: port the four GPU steps to CPU/C++. Acceptance bar: **graph node data
(connections + biome) identical across machines; visuals may differ slightly.**
Windows-only determinism is acceptable.

## ⚠️ The contract here is NOT bit-identity

Every other doc in this repo (`GDEXTENSION_PORT_HANDOFF.md` etc.) demands
bit-identical output vs a GDScript twin. **That rule does not apply to this work.**
Reproducing a GPU's `pow`/`atan` from C++ is exactly the thing that cannot be done
across vendors — it is the problem, not the standard. Your contract is:

1. **Repeatable** — byte-identical heights run to run, and across renderers.
2. **Close to the current GPU look** — measured and reported, not asserted. This is a
   one-time, accepted change in how maps look.
3. **Graph-stable** — the land/water mask is what the graph is built from, so the
   flip count is the number that actually matters.

## Environment (verified on this box)

- Worldgen project: `C:\Users\khanr\Documents\GitHub\gamedev\worldgen`
- Solatro (vendored consumer): `C:\Users\khanr\Documents\GitHub\gamedev\solatro`
  — NEVER edit `solatro/addons/worldgen/` directly; it is a vendored copy.
- Godot 4.7: `C:\Users\khanr\Desktop\Godot_v4.7-stable_win64.exe`
- Build (from `worldgen/worldgen_native/`), **`scons` is NOT on PATH**:
  ```
  python -m SCons platform=windows target=template_debug
  python -m SCons platform=windows target=template_release
  ```
- `worldgen_native/godot-cpp/` is **gitignored and may be absent**. Restore per
  `worldgen_native/BUILD.md`: shallow-clone godot-cpp master, then copy
  `api/extension_api.json` + `api/gdextension_interface.h` over
  `godot-cpp/gdextension/`. First build ~30 min; then incremental (seconds).
- If SCons says "is up to date" for a file you edited during a running build, delete
  `src/*.obj` and rebuild.
- If a scene reports "WorldgenNative class not registered", the project is missing
  `.godot/extension_list.cfg` — run `Godot --headless --path <project> --import` once.
- Run worldgen scenes **WINDOWED** (no `--headless`) — `frame_post_draw` never fires
  headless, and the GPU comparison arm needs it. `--import` headless is fine.
- The user runs GitHub Desktop: **do not `git add`/commit/stage**. Just edit files.

## What is already done (step 1 of 4)

- `WorldSettings.deterministic_terrain` — new toggle, **default false** so nothing
  changes for anyone until the port is complete.
- `terrain_landmass` in `worldgen_native/src/worldgen_native.{h,cpp}` — CPU twin of
  `landmass.gdshader`. Bound in `_bind_methods`.
- `addons/worldgen/core/steps/landmass.gd` — early-return branch taking the CPU path,
  writing `gen.height_buffer` directly and skipping the SubViewport entirely (no
  material, no `flush`, no frame waits).
- `tests/deterministic_terrain_test.{gd,tscn}` — the gate. Measured:
  ```
  [PASS] CPU terrain is byte-identical across runs (262144 px)
     seed 12356  CPU vs GPU: max|d|=0.00049 mean|d|=0.000113  land/water flips=75 (0.029%)
     seed 777    CPU vs GPU: max|d|=0.00049 mean|d|=0.000108  land/water flips=77 (0.029%)
  ```
  The ~0.00049 max delta is ≈2^-11 — dominated by the GPU render target storing
  **half floats**, not by shader math. Visually imperceptible.

The seam pattern to copy (from `landmass.gd`):

```gdscript
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	if settings.deterministic_terrain and GenerationStep._native:
		gen.height_buffer = GenerationStep._native.terrain_landmass(
			gen.noise_img("landmass").get_data(), ..., settings.map_width, ...)
		gen._save_snapshot_bridge("Landmass")
		return
	... existing GPU path untouched ...
```

Useful fact: the noise/warp maps are CPU-baked **L8 at exactly map_width x map_height**
and the shaders sample them at pixel centres, so bilinear sampling degenerates to a
direct texel fetch — there is no filtering behaviour to reproduce. Read the bytes.

## Remaining work, in order

Shaders live in `addons/worldgen/shaders/`; steps in `addons/worldgen/core/steps/`.

### 1. `tectonics.gd` — TWO shaders, and the one real trap

`tectonic_blueprint.gdshader` (38 ln) → writes **plate ids**, consumed by
`gen.read_plate_ids_from_image()` which unpacks `blue` channel as `idx / MAX_PLATES`
(see `world_generator.gd`). Your CPU twin must produce `plate_id_buffer` too, not just
height.

`tectonic_deformation.gdshader` (71 ln) → height.

**⚠️ TRAP:** the deform pass reads `gen.viewport_texture("landmass")` — the GPU
*viewport*, not `height_buffer`. On the CPU path that viewport is never rendered. Your
CPU twin must read `gen.height_buffer` instead. This is why the toggle is currently
unsafe for a full generation and must stay default-false until you finish.
(`peaks_valleys.gd` does NOT have this problem — it already reads
`gen.height_texture()`, i.e. the buffer.)

Inputs: `gen.plate_tex` / `gen.plate_land_tex` are small `FORMAT_RGBAF` images
(`MAX_PLATES x 1`, built in `world_generator.gd` ~line 408) — pass their data through.

### 2. `peaks_valleys.gd` / `peaks_and_valleys.gdshader` (70 ln)

Chains cleanly (reads `gen.height_texture()` from the buffer). Note it currently goes
through `height_texture()`, which converts to **RGBAH (half float)** — your CPU path
reads `height_buffer` at full float32, which is *more* precise. That is fine and
slightly better; just be aware it is a deliberate divergence from the GPU path.

### 3. `erosion.gd` / `erosion.gdshader` (276 ln) — the bulk

Directional-gabor erosion with an octave loop. Heaviest port, but still a **single
full-screen pass** — no ping-pong iteration. Two flushes exist only because
`output_mode` 0 = final eroded height and 1 = the erosion field on its own, stashed as
the `erosion_field` noise map for the debug viewer. Your CPU version should produce
both (or at minimum mode 0 plus a mode-1 image, or the viewer's debug slot breaks).
Contains `atan` x3, `sin` x2, `cos` x2, `pow` x2, `fract` x2, `exp`, `smoothstep` — do
all of it in `double`, store `float`.

## Definition of done

1. All four steps have CPU twins; `deterministic_terrain` flipped to **default true**.
2. `tests/deterministic_terrain_test.tscn` extended to run a FULL generation (not just
   `generate_up_to(LANDMASS)`) and assert byte-identical `height_buffer` across runs.
3. **The real acceptance test:** bake the same seed under two renderers and confirm
   `graph.json` is byte-identical:
   ```
   Godot --path <worldgen> res://tests/addon_bake_test.tscn
   Godot --path <worldgen> --rendering-method forward_plus --rendering-driver d3d12 res://tests/addon_bake_test.tscn
   ```
   Bake output: `%APPDATA%\Godot\app_userdata\worldgen\worldgen_bake_test\`. Hash
   `graph.json` from each. On the GPU path today `land.png`/`composite.png` already
   differ between renderers while `graph.json` happens to survive — after the port
   nothing should differ at all. (`addon_bake_test` has no `quit()`; launch it, wait
   ~110 s, then kill it.)
4. Re-measure and record the **land/water flip count** for the full chain. Deltas
   compound across four steps; that number, not the height delta, decides whether the
   graph moves.
5. Regression gates, run WINDOWED, all green with the toggle in BOTH positions:
   `native_ab_test` (57 checks — must stay bit-identical; you have not touched those
   functions), `generate_up_to_test`, `graph_placement_test`, `biome_regions_test`,
   `biome_assign_test`, `graph_spec_test`, `addon_bake_test`, `addon_node_test`.
   ⚠️ Only `native_ab_test` propagates a failure exit code; the other seven call bare
   `get_tree().quit()` and **always exit 0** — you must READ their output.
6. Fallback still works with the dlls renamed to `.off` (GPU path resumes).
7. Vendor into Solatro **only once complete**: copy changed `.gd` files (not the
   README) + `addons/worldgen/bin/` into `solatro/addons/worldgen/`, then
   `--headless --import`, then
   `Godot --headless --path <solatro> res://Tests/all_tests.tscn` — exit code =
   failure count, expect **ALL 24 SUITES green**. ⚠️ Close any open Godot editor
   first: it LOCKS the vendored dll and the copy will fail.
8. Update `DETERMINISM_FINDINGS.md` (Option A section), `GDEXTENSION_PORT_HANDOFF.md`
   STATUS, `solatro/todo.md` (the open-risk section — close it), and
   `solatro/EFFICIENCY_AUDIT_TRACKER.md` (dated entry) with before/after numbers.

## Things that will confuse you if nobody says them

- **The committed `placement_debug/` + `biome_debug/` PNGs do not match what your
  machine generates, and that is expected** — they came from a different box. They are
  a valid SAME-machine regression check only. Do not "fix" them, and do not treat a
  diff against them as a regression. (Proven: the very commit that generated them
  cannot reproduce them here.)
- Docs across these repos reference `C:\richard\gamedev\...` paths — that is the other
  machine. Real paths are under `C:\Users\khanr\Documents\GitHub\gamedev\`.
- Godot warnings are errors in this project: type every `for` loop variable
  (`for x: T in ...`) and every Array element type.
- `addon_bake_test` warns "EXR export is editor-only" — expected, not a failure.
