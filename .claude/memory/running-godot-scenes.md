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

⚠ **THE SUITE COUNT IS THE LOAD-FAILURE DETECTOR, SO A DOC THAT HARDCODES IT DISABLES THE
DETECTOR.** A parse error in one suite drops that suite silently while every other suite finishes and
the banner still reads PASSED — the count is the only signal. It was found stale in four documents at
three different values at once, every one of them lower than the truth, so any of them would have
read a real load failure as normal. **State the derivation beside the number, never the number
alone:** `grep -c 'ext_resource type="PackedScene"' solatro/Tests/all_tests.tscn`. Do not "fix" this
by deleting the number — a detector you cannot compare against detects nothing.

⚠ **A banner reading `N FAILED (0 behavior, 0 implementation)` is NOT an assertion failure.** Zero
of each means no `check()` failed; the count is the engine-error gate. Read the errors log and the
newest engine log's backtrace, not the check list. That count is also not deterministic — measured
across identical code it went 17, then 1, then 1 — so **diff the per-suite banners, not the number.**

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
- **Check no editor has the project open** — list Godot processes and inspect `MainWindowTitle`.
  See [[godot-editor-disk-sync]] for the rule on what you may and may not shut down. If the editor is
  open, write the code and ask the owner — it is their session and their unsaved work.
  ⚠ **"It hangs indefinitely" is too strong, measured once:** a single windowed SNAPSHOT scene
  (`standalone_view_shot`) run at the owner's explicit instruction while their editor sat open on the
  very scene it loads completed normally, wrote its PNG, exited 0, and rewrote no tracked file. One
  observation, on one box, for a short self-quitting scene — it does NOT license running the full
  suite alongside an editor, and asking still comes first. Recorded so the rule is not defended with
  a symptom that may not appear.

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

## ⚠ A GREEN RUN IS A SAMPLE, NOT A PROPERTY OF THE BRANCH

Measured: a branch reported `ALL 45 SUITES ... CHECKS PASSED` on the run that closed it, and **2 of
16 runs of that identical code came back with a behaviour failure.** "The suite is green" was true of
a run and false of the branch, and every number quoted from a single run inherited that.

⚠ **QUOTE THE DENOMINATOR, NOT A RATE.** The same document carried three different failure rates in
one night — each computed off whatever sample existed at that moment, each stated with confidence.
Say `2 failures in 16 runs`, never "about one in four". A rate without its denominator is how a
four-run sample becomes a claim.

⚠ **AND THE CHECK TOTAL IS NOT AN ASSERTION COUNT.** In that suite `test_fuzz.gd` holds ONE `check()`
and increments the pass counter by hand per iteration, so the headline number drifts by tens between
identical runs (3956..3995 observed). **Gate on: the suite COUNT, an EMPTY errors log, and an
unchanged failure SET** — never on the total.

⚠ **AN INTERMITTENT FAULT DESTROYS ITS OWN EVIDENCE**, because the reflex after a red or hung run is
to run it again and the harness reopens its logs with truncate. Preserve the log directory BEFORE
re-running. Solatro's wrapper now does it automatically on a stall or a failure
(`run_tests.py --stall-timeout`); elsewhere, copy it by hand.

See [[godot-editor-disk-sync]] and [[architecture-map]].
