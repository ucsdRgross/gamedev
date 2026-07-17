# Headless testing on this machine — READ BEFORE DEBUGGING A "HANGING" TEST

Findings from the 2026-07 efficiency audit sessions (last updated 2026-07-17).
Applies to Godot 4.7 (`C:\richard\Godot_v4.7-stable_win64_console.exe`) and both
projects (`solatro`, `worldgen`).

## 1. `--headless` never fires `RenderingServer.frame_post_draw` (Godot 4.7)

Any `await RenderingServer.frame_post_draw` stalls FOREVER headless. Verified
2026-07-17: worldgen's pipeline test scenes print their banner and then produce
nothing for 9+ minutes — they are parked on the first GPU `flush()` await
(`worldgen/addons/worldgen/core/world_generator.gd::flush`).

- Consequences: every worldgen scene that generates a world (generate_up_to,
  graph_placement, biome_*, addon_*) MUST run windowed:
  `Godot --path <project> res://tests/<scene>.tscn` (no `--headless`).
- Solatro suite status (investigated 2026-07-17, same day): the hang did NOT reproduce
  — 6 consecutive full headless runs (23 suites) all exited cleanly by themselves,
  ~20 s each, exit 0. Code audit backs it up: nothing in `Scripts/` or `Tests/` awaits
  `frame_post_draw`; the only awaiters are the vendored worldgen `flush()` paths, which
  no Solatro test touches. RunManager's saver thread is properly joined in
  `_exit_tree`. Treat the historical "hangs after the final banner" as either fixed by
  the audit-era changes or an environment fluke; if it recurs, capture it with
  `--verbose` before killing.
- Workaround if it ever recurs: the suite prints its final banner and results BEFORE
  any hang; read `%APPDATA%\Godot\app_userdata\Solatro\test_output_all.log` and kill
  the process. Exit code (when it does exit) = failure count.

## 2. Stale global class cache ("Could not find type X" cascades)

`.godot/global_script_class_cache.cfg` goes stale when class-bearing scripts change
outside the editor (e.g. agent edits, re-copying the vendored addon). Symptoms range
from silent suite skips to hard parse-error cascades ("Identifier X not declared").
Fix FIRST, before debugging code:

    Godot --headless --path <project> --import

(`--import` itself exits cleanly headless.) Hit again 2026-07-17 after editing
worldgen addon scripts: worldgen tests failed with "GraphSpec not declared" until the
re-import.

## 3. Headless window size is (0,0)

`DisplayServer.window_get_size()` is (0,0) headless (root window clamped to 100x100)
while `canvas_items` stretch keeps the canvas at design size. Anything converting
window<->canvas coordinates (e.g. `Input.parse_input_event` synthetic clicks) breaks.
This root-caused the 10 INTERACTION failures (fixed 2026-07-16 with a `to_window()`
helper in `Tests/UI/test_interaction.gd` — pattern to reuse for future synthetic input).

## 4. Misc

- Windowed test runs work fine on this box (OpenGL 3.3, GTX 1070) and are how the
  worldgen suite was validated; expect a window to flash up.
- Suite check TOTALS vary run-to-run (data-dependent suites). Compare FAILURE SETS,
  not counts.
- Worldgen scenes `addon_bake_test`/`addon_node_test` never call `quit()` (by design,
  they are also demos); kill them after the PASS lines.
