---
name: running-godot-scenes
description: "How to run Godot scenes and test suites yourself — the suite runs WINDOWED, a green banner is not proof, how to diagnose a red, hung or flaky run, and which scenes still need the owner"
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
Headless is still right for `--import`, for quick parse checks, and for solatro's LOGIC TIER
below.

## ⚠ A green banner is not proof the tests ran

A GDScript RUNTIME error inside a test function (`Invalid call ... in base 'Nil'`) aborts that
function on the spot. The remaining `check()` calls never execute, so they cannot fail, so the runner
prints `ALL N SUITES: M CHECKS PASSED` with whole tests silently missing — and
`test_output_errors.log` stays 0 bytes, because it does not catch this class.

- **Redirect STDERR as well as stdout** and treat ANY `SCRIPT ERROR` line as a failure regardless of
  the summary.
- When a section claims a check count, **diff it against the `check(` calls in the source** — only a
  per-SECTION count can detect this.

⚠ **THE SUITE COUNT IS THE LOAD-FAILURE DETECTOR, SO A DOC THAT HARDCODES IT DISABLES THE
DETECTOR.** A parse error in one suite — every warnings-as-errors slip in
[[gdscript-type-all-arrays]] is one — drops that suite silently while the banner still reads PASSED.
It was found stale in four documents at three different values at once, every one lower than the
truth. **State the derivation beside the number, never the number alone:**
`grep -c 'ext_resource type="PackedScene"' solatro/Tests/all_tests.tscn`. Do not "fix" this by
deleting the number — a detector you cannot compare against detects nothing.

⚠ **Gate on the suite COUNT, an EMPTY errors log and an unchanged failure SET — never the check
total.** `test_fuzz.gd` holds one `check()` and bumps the pass counter per iteration, so the total
drifts by tens between identical runs (3956..3995 observed).

⚠ **A banner reading `N FAILED (0 behavior, 0 implementation)` is NOT an assertion failure.** Zero
of each means no `check()` failed; the count is the engine-error gate. Read the errors log and the
newest engine log's backtrace, not the check list. That count is also not deterministic — measured
across identical code it went 17, then 1, then 1 — so **diff the per-suite banners, not the number.**

## Launching it

- Launch so you WAIT: PowerShell `Start-Process <console exe> -RedirectStandardOutput <file>
  -PassThru`, then `WaitForExit(<ms>)` with a bound above the measured full-run time below. A bare
  `& $exe ...` can return while the run continues, and two overlapping runs truncate each other's
  log so it looks hung. Always bound it with a timeout that KILLS.
- ⚠ **The `_console` exe is a wrapper: ending its PID orphans the game window.** A scene you may
  have to stop by PID launches with the non-console exe, and you end THAT PID.
- **Never pass `--quit-after <ms>`** to force-quit a scene: it keeps the process alive for the full
  duration regardless of when tests finish, which is what makes runs look hung.
- **Run ONE suite through the real runner, never its own scene:** `py solatro/Tools/run_tests.py
  --filter <NodeName>` (case-insensitive substrings of the node names in `all_tests.tscn`; several
  patterns are allowed). A lone suite scene never self-quits — `quit()` lives in `all_tests.gd` —
  and it also skips the engine-error gate and truncates the full run's log. The filter keeps all
  three.
- **Two tiers.** Inner loop: `run_tests.py --logic`, the `logic` group in `all_tests.tscn`, headless,
  no GPU and no window. Gate: the full windowed run. Measured on the sidebar branch at 48 suites
  (33 in `logic`), Box A: full windowed run ~5–6 min, one `--filter` suite ~30 s. ⚠ A tiered or
  filtered run prints `FILTERED n of <total>`, voids the suite count and gives no clean verdict, so
  it is never the gate. Which suites are out of the tier and why: `solatro/HEADLESS_TESTING.md` §0.
- **One run at a time.** ⚠ Overlapping runs **FABRICATE FAILURES in unrelated suites** — they share
  `user://logs/godot.log`, the output logs and `user://run_save/run.tres`. Measured: whole runs
  printing `NO SUITE BANNER`, which vanished on serialising. **A failure observed while two runs
  overlapped is not evidence.** Check for live Godot processes before starting, including before a
  background batch. The converse trap is under "Diagnosing" below.
- **Check no editor has the project open** — list Godot processes and inspect `MainWindowTitle`.
  See [[godot-editor-disk-sync]] for what you may and may not shut down. If the editor is open, write
  the code and ask the owner — the rule is their unsaved work. Do not defend it with "it hangs":
  measured once, a short self-quitting snapshot scene run at the owner's instruction beside their
  open editor exited 0 and rewrote no tracked file.

## Reading the result

**Never read the full output.** The runner ends with `ALL %d SUITES: %d CHECKS PASSED` or
`ALL %d SUITES: %d passed, %d FAILED (...)`. Grep for which —
⚠ **and grep BOTH streams: the FAILING banner and every `[FAIL]` line go to STDERR.** A stdout-only
grep on a red run returns nothing, which reads exactly like a hang; the passing banner goes to
stdout, so "no match" there means red or crashed, never green. Read the full log only when it
failed, to locate the suite. `test_output_errors.log` empty = green; LEAK CANARY's stderr
`push_error`/ObjectDB lines are deliberate.

## ⚠ Diagnosing a red, hung or flaky run

**A green run is a sample, not a property of the branch.** Measured: a branch reported
`ALL 45 SUITES ... CHECKS PASSED` on the run that closed it, and 2 of 16 runs of that identical code
failed. **Quote the denominator** — `2 failures in 16 runs`, never "about one in eight".

- **Preserve the logs BEFORE re-running.** The harness reopens its logs with truncate, so the reflex
  re-run destroys the evidence. Solatro's wrapper copies them on a stall or a failure
  (`run_tests.py --stall-timeout`); elsewhere copy the log directory by hand.
- **No banner, or a stall, is not yet YOUR crash — re-run once before bisecting.** A slow suite still
  streams checks; one silent after its banner is stalled. Measured: 3 hangs and 4 passes across
  identical trees; a suite silent for 27 minutes in 1 run of 6 passed 215/215 alone in a minute. If
  the failure follows the change across several runs, it is yours. ⚠ Never re-run until it passes
  and call that a result.
- **Run the failing suite ALONE to discriminate cross-suite interference.** Measured: two checks
  failed at every commit through five different diagnoses; alone the suite passed 74/74 with a
  0.0 px delta. Deterministic interference reads exactly like a deterministic bug. The tell is a
  **rotating casualty** — WHICH check fails changes run to run.
- **Do not name a cause you have not measured** — concurrency included. Overlapping runs do fabricate
  failures, but the persistence suite's flakes reproduce under strictly sequential runs too, and one
  stall was blamed first on concurrency and then on an unbounded loop, both written into a living
  doc and both wrong. State only what the evidence bounds.
- **A global timeout is not a watchdog.** One stalled suite eats the whole budget and discards every
  other suite's verdict. A per-suite silence detector that NAMES the quiet suite belongs in the
  WRAPPER, never the harness the suites run under — solatro's is `run_tests.py --stall-timeout`.

## Snapshot scenes — run them and READ the PNGs

Snapshot scenes run WINDOWED and quit themselves; solatro's list and output paths:
`solatro/HEADLESS_TESTING.md` §0b. Read the PNGs with the Read tool; crop and upscale with PIL when
too small to judge. Prefer making the harness measure its own capture over eyeballing pixel
positions. See [[verify-visuals-by-eye]].

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
- **A stale `.godot/` class cache turns a whole run into noise** — fix it before trusting any
  baseline: `solatro/HEADLESS_TESTING.md` §2.
- Solatro's suite ordering (the deadlock rule), settings and save backups, and the SmoothScroll
  mouse-filter pre-claim: `solatro/ARCHITECTURE_REVIEW.md` §7 and §4b.

See [[godot-editor-disk-sync]] and [[architecture-map]].
