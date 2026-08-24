---
name: running-godot-scenes
description: "How to run Godot scenes and test suites yourself — the suite runs WINDOWED, a green banner is not proof, and which scenes still need the owner"
metadata:
  node_type: memory
  type: feedback
---

**Run the test suite yourself. Do not hand it off.**
`Godot --path solatro res://Tests/all_tests.tscn` — **WINDOWED, never `--headless`.**
`all_tests.gd` calls `get_tree().quit(failure_count)` when every suite finishes, so it
self-terminates; exit code = failure count. Binary path: [[machine-profiles]].

Headless is wrong because the PIXELS suite renders into a SubViewport and asserts on the image, and
a dummy renderer cannot compile a shader. That suite FAILS rather than skipping — **a test that
cannot run under the current renderer must fail, because a skipped check reads like a passing one.**
Headless is still right for `--import` and quick parse checks.

## ⚠ A green banner is not proof the tests ran

A GDScript RUNTIME error inside a test function (`Invalid call ... in base 'Nil'`) aborts that
function on the spot. The remaining `check()` calls never execute, so they cannot fail, so the runner
prints `ALL N SUITES: M CHECKS PASSED` with whole tests silently missing — and
`test_output_errors.log` stays 0 bytes, because it does not catch this class.

- **Redirect STDERR as well as stdout** and treat ANY `SCRIPT ERROR` line as a failure regardless of
  the summary.
- When a section claims a check count, **diff it against the `check(` calls in the source.** The
  total drifts run to run (the fuzz suites emit a data-dependent number), so only a per-SECTION
  count can detect this.

## Launching it

- Launch so you WAIT: PowerShell `Start-Process <console exe> -RedirectStandardOutput <file>
  -PassThru`, then `WaitForExit(300000)`. A bare `& $exe ...` can return while the run continues, and
  two overlapping runs truncate each other's log so it looks hung. Always bound it with a timeout
  that KILLS.
- **Never pass `--quit-after <ms>`** to force-quit a scene: it keeps the process alive for the full
  duration regardless of when tests finish, which is what makes runs look hung. Individual suite
  `.tscn`s do not self-quit — run `all_tests.tscn`, not a lone suite.
- **One run at a time.** ⚠ Overlapping runs **FABRICATE FAILURES in unrelated suites** — they share
  `user://logs/godot.log`, the output logs and `user://run_save/run.tres`. Measured: whole runs
  printing `NO SUITE BANNER`, which vanished on serialising. **A failure observed while two runs
  overlapped is not evidence.** Check for live Godot processes before starting, including before a
  background batch.
  ⚠ **The converse trap:** do not then explain away a real intermittent failure as concurrency. The
  persistence suite's flakes reproduce under strictly sequential runs too.
- **Check no editor has the project open** — list Godot processes and inspect `MainWindowTitle`. A
  run alongside the open editor hangs indefinitely. See [[godot-editor-disk-sync]] for the rule on
  what you may and may not shut down. If the editor is open, write the code and ask the owner to run.

## Reading the result

**Never read the full output.** The runner ends with `ALL %d SUITES: %d CHECKS PASSED` or
`ALL %d SUITES: %d passed, %d FAILED (...)`. Grep for which —
⚠ **and grep BOTH streams: the FAILING banner and every `[FAIL]` line go to STDERR.** A stdout-only
grep on a red run returns nothing, which reads exactly like a hang; the passing banner goes to
stdout, so "no match" there means red or crashed, never green. Read the full log only when it
failed, to locate the suite. `test_output_errors.log` empty = green; LEAK CANARY's stderr
`push_error`/ObjectDB lines are deliberate.

## Snapshot scenes — run them and READ the PNGs

`Tests/Visual/fx_snapshot.tscn` (shader FX), `prop_art_snapshot.tscn` (prop and pip art) and
`wall_editor_snapshot.tscn` (the picture-wall tool) all `quit()` themselves and run WINDOWED.
Output goes to `$OUT_DIR` or `%APPDATA%\Godot\app_userdata\Solatro\*_snapshots\` — read them with the
Read tool; crop and upscale with PIL when too small to judge. `cd` to the REPO ROOT first
(`--path solatro` is relative). Prefer making the harness measure its own capture over eyeballing
pixel positions. See [[verify-visuals-by-eye]].

## Testing an EDITOR-ONLY claim without opening the GUI

`<binary> --path solatro --editor --quit-after 400 res://<scene>.tscn` opens in EDITOR mode, builds
the scene, prints every script error and quits. **The only way to see a `@tool`/placeholder problem**
— nothing that RUNS can, because at runtime every class works whether it is `@tool` or not. A/B it by
reverting and running again. ⚠ Requires the owner's editor CLOSED, and it is the ONE case where
`--quit-after` is correct.

A `@tool` scene can also be run by a throwaway harness that saves
`get_viewport().get_texture().get_image()` — cheaper than the editor, but its runtime behaviour
differs, so treat a runtime capture as evidence about only the parts you verified.
See [[no-mocks-in-tools]].

## worldgen gate scenes

Run fine WINDOWED: `<binary> --path <worldgen> res://tests/<x>.tscn`. `native_ab_test`,
`generate_up_to_test`, `graph_placement_test`, `biome_regions_test`, `biome_assign_test` and
`graph_spec_test` self-quit. `addon_bake_test`/`addon_node_test` do not — launch via
`Start-Process`, wait ~90–120 s, then end that one verified PID. The never-headless rule here is
about headless specifically (`frame_post_draw` never fires there), not about running them at all.

## Gameplay and generation scenes still go to the owner

`main.tscn` and the param-search harness frequently produce no or partial output under Claude's
invocation. Add debug `print()`s, cite their exact `file:line`, and ask the owner to run and paste
the console output. In multi-phase work, PAUSE at each verification gate — do not batch phases ahead
of reality.

## Traps

- **Scene filename ≠ script name** — `test_scoring.gd`'s scene is `test_score.tscn`. Glob
  `Tests/**/<name>.tscn` before invoking a single suite.
- **A stale `.godot/` class cache turns a whole run into noise** — hundreds of `Could not find type
  X`, every suite failing for no real reason. Two ways in: adding a `class_name`, and **checking out
  a branch on the OTHER machine for the first time** (routine here). Fix: delete `.godot/`, then
  `--headless --path . --import` **twice** — the first pass still reports errors while building the
  cache. Do this BEFORE trusting any baseline.
- **Disk/save tests must always run full.** `SolatroTest.backup_real_save()`/`restore_real_save()`
  park any real `run.tres` before the disk section. Never reintroduce a save-existence `[SKIP]`
  guard — it made results depend on unrelated player saves.
- `test_ui_props.gd` backs up `settings.tres` (which saves on EVERY change) and waits for all sibling
  suites except E2E — E2E waits for everyone, so waiting on it deadlocks.
- The SmoothScroll addon force-rewrites any Control entering its subtree to `MOUSE_FILTER_PASS`.
  Display-only Controls under the play-area scroll content must pre-claim
  `set_meta("_smooth_scroll_default_mouse_filter_set", true)` before `add_child`.

See [[godot-editor-disk-sync]] and [[architecture-map]].
