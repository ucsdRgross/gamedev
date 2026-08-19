---
name: running-godot-scenes
description: "How to run Godot scenes and test suites yourself — the suite runs WINDOWED, a green banner is not proof, and which scenes still need the owner"
metadata:
  node_type: memory
  type: feedback
---

**Run the test suite yourself. Do not hand it off.**
`Godot --path solatro res://Tests/all_tests.tscn` — **WINDOWED, never `--headless`.**
`all_tests.gd` calls `get_tree().quit(failure_count)` the instant every suite finishes, so it
self-terminates; exit code = failure count. Binary path: [[machine-profiles]].

Headless is wrong for the suite because the PIXELS suite renders effects into a SubViewport and
asserts on the image — a dummy renderer cannot compile a shader, so that suite fails and tells you
to re-run windowed. That is deliberate: **a test that cannot run under the current renderer FAILS,
it never skips**, because a skipped check reads exactly like a passing one. Headless is still
right for `--import` and quick parse checks.

## ⚠ A green banner is not proof the tests ran

A GDScript RUNTIME error inside a test function (`Invalid call. Nonexistent function 'x' in base
'Nil'`) aborts that function on the spot. The remaining `check()` calls never execute, so they
cannot fail, so the runner prints `ALL N SUITES: M CHECKS PASSED` with entire tests silently
missing — and `test_output_errors.log` stays 0 bytes, because it does not catch this class.

So:
- **Redirect STDERR as well as stdout** (`Start-Process -RedirectStandardError`) and treat ANY
  `SCRIPT ERROR` line as a failure regardless of the summary.
- When a section claims a check count, **diff it against the `check(` calls in the source.**
  The total drifts run to run (the fuzz suites emit a data-dependent number), so only a
  per-SECTION count can detect this.

## Launching it

- Launch so you WAIT: PowerShell `Start-Process <console exe> -RedirectStandardOutput <file>
  -PassThru`, then `WaitForExit(300000)`. A bare `& $exe ...` can return while the run continues,
  and two overlapping runs truncate each other's log so it looks hung (`Get-Process *odot*` finds
  the orphans). Always bound it with a timeout that KILLS.
- **Never pass `--quit-after <ms>`** to force-quit a scene: it keeps the process alive for the
  full duration regardless of when tests finish, which is what makes runs look hung. Individual
  suite `.tscn`s do not self-quit — run `all_tests.tscn` instead of a lone suite.
- **One run at a time.** ⚠ Not merely slower — **overlapping runs FABRICATE FAILURES in suites that
  have nothing to do with your change**, because they share `user://logs/godot.log`, the test output
  logs and `user://run_save/run.tres`. Measured: whole runs printing `NO SUITE BANNER — the run did
  not reach its own verdict`, which vanished on serialising. **A failure observed while two runs
  overlapped is not evidence.** `tasklist | grep Godot_v4` (or `Get-Process *odot*`) before starting,
  including before a background batch — the easy way to break this is to start a second batch while
  the first is still draining.
  ⚠ **The converse trap:** do not then explain away a real intermittent failure as "that was the
  concurrency". The persistence suite's flakes reproduce under strictly sequential runs too.
- **Before any run, check no editor has the project open** — `Get-Process *odot*`, inspect
  `MainWindowTitle`. A run alongside the open editor hangs indefinitely. **Never kill a process
  whose title shows an editor window**; an orphan titled `Solatro (DEBUG)` is safe to kill.
  If the editor is open, write the code and ask the owner to run it.

## Reading the result

**Never read the full output — it is too much.** The runner ends with one of two lines:
`ALL %d SUITES: %d CHECKS PASSED` on success, or `ALL %d SUITES: %d passed, %d FAILED
(%d behavior, %d implementation)` on failure. Grep for which one was taken —
⚠ **and grep BOTH streams: the FAILING banner and every `[FAIL]` line go to STDERR, not stdout.**
A stdout-only grep on a red run returns nothing at all, which reads exactly like a hang. The
passing banner goes to stdout, so "no match" on a stdout grep means red or crashed, never green. Read the full log
only when it failed, to locate the failing suite. `test_output_errors.log` empty = green;
LEAK CANARY's stderr `push_error`/ObjectDB-leak lines are deliberate.

## Snapshot scenes — run them and READ the PNGs

`Tests/Visual/fx_snapshot.tscn` (shader FX) and `Tests/Visual/prop_art_snapshot.tscn` (prop and
pip art) both `quit()` themselves and run reliably WINDOWED. Output:
`%APPDATA%\Godot\app_userdata\Solatro\{fx,prop_art}_snapshots\*.png` — read them with the Read
tool; crop and upscale with PIL when something is too small to judge. `cd` to the REPO ROOT first
(`--path solatro` is relative and fails from inside `solatro/`). Prefer making the harness measure
its own capture over eyeballing pixel positions. See [[verify-visuals-by-eye]].

## Testing an EDITOR-ONLY claim without opening the GUI

`<binary> --path solatro --editor --quit-after 400 res://<scene>.tscn` opens the project in EDITOR
mode, builds the scene, prints every script error to stdout and quits. This is the only way to see
a `@tool` / placeholder-script problem — nothing that RUNS can, because at runtime every class
works whether it is `@tool` or not. A/B it by reverting the change and running again. ⚠ Requires
the owner's editor CLOSED, and it is the ONE case where `--quit-after` is correct.

A `@tool` scene can also be run by a throwaway harness that instantiates it and saves
`get_viewport().get_texture().get_image()` — much cheaper than the editor, but its runtime
behaviour differs (a `CardVisual` frees itself, effects build their own attachments), so treat a
runtime capture as evidence about only the parts you verified. See [[no-mocks-in-tools]].

## worldgen gate scenes

They run fine from Claude when launched **WINDOWED**: `<binary> --path <worldgen>
res://tests/<x>.tscn`. `native_ab_test`, `generate_up_to_test`, `graph_placement_test`,
`biome_regions_test`, `biome_assign_test` and `graph_spec_test` all `quit()` themselves.
`addon_bake_test` / `addon_node_test` have no `quit()` — launch via `Start-Process
-RedirectStandardOutput`, wait ~90–120 s, then `Stop-Process`. The "never headless" rule for
worldgen is about headless specifically (`frame_post_draw` never fires there), not about running
these at all.

## Gameplay and generation scenes still go to the owner

`main.tscn` and the param-search harness frequently produce no or partial output under Claude's
invocation, so you end up waiting on output that never comes. Add debug `print()`s, cite their
exact `file:line`, and ask the owner to run the scene and paste the console output. In multi-phase
work, PAUSE at each verification gate and have them run it before starting the next phase — do not
batch phases ahead of reality.

## Traps

- **Scene filename ≠ script name** — `test_scoring.gd`'s scene is `test_score.tscn`. Glob
  `Tests/**/<name>.tscn` before invoking a single suite.
- **A stale `.godot/` class cache turns a whole run into noise** — hundreds of `Could not find type
  X` parse errors, every suite failing for a reason that is not real. Two ways in: adding a
  `class_name`, and **checking out a branch on the OTHER machine for the first time** (this repo
  travels between two boxes, so that is routine, not exotic). Fix: delete `.godot/`, then run
  `--headless --path . --import` **twice** — the first pass still reports parse errors while it is
  building the cache it needs, the second comes back clean. Do this BEFORE trusting any baseline;
  a run against a stale cache tells you nothing about your change.
- **Disk/save tests must always run full.** `SolatroTest.backup_real_save()` /
  `restore_real_save()` move any real `run.tres` to a `.testbak` sibling before the disk section
  and restore it after; `test_run_manager`, `test_persistence_fuzz` and `test_e2e_run` all call
  them. Never reintroduce a save-existence `[SKIP]` guard — it made results depend on unrelated
  player saves.
- `test_ui_props.gd` backs up `settings.tres` before touching `SettingsManager.settings` (which
  saves to disk on EVERY change) and waits for all sibling suites except E2E — E2E waits for
  everyone, so waiting on it deadlocks.
- The SmoothScroll addon force-rewrites any Control entering its subtree to `MOUSE_FILTER_PASS`.
  Display-only Controls under the play-area scroll content must pre-claim
  `set_meta("_smooth_scroll_default_mouse_filter_set", true)` before `add_child`, or they become
  click-blocking hit-targets.

See [[godot-editor-disk-sync]] and [[architecture-map]].
