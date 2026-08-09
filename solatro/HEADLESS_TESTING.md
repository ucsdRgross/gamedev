# Test-environment traps — READ BEFORE DEBUGGING A "HANGING" TEST

Applies to both projects (`solatro`, `worldgen`). `$GODOT_CONSOLE` is the **console** variant of
the Godot exe — the redirectable one, which must live in the same folder as the main exe because
it launches it by name. Paths per machine: `../.claude/memory/machine-profiles.md`.

## 0. The Solatro suite runs **WINDOWED**, not headless

```bash
timeout 500 "$GODOT_CONSOLE" --path solatro res://Tests/all_tests.tscn > /tmp/run.log 2>&1; echo "exit: $?"
```

It quits itself (`close_when_done`) and exits with the failure count, so it is fully scriptable —
it just needs a GPU.

### ⚠ Prefer the wrapper: `Tools/run_tests.py`

```bash
GODOT_BIN=<path to the _console exe> py solatro/Tools/run_tests.py     # or --godot <path>
```

It runs exactly the command above (windowed, kill-on-timeout) and then gates **the engine errors the
suite structurally cannot see itself**. `all_tests.gd::_scan_engine_errors` runs inside `_ready`,
BEFORE `get_tree().quit()`, so everything the engine prints while tearing down arrives after the
gate has already reported — and by then every GDScript object is gone, so no in-engine check can
ever catch it.

⚠ **Re-reading `user://logs/godot.log` after the process exits does NOT work**, which is the obvious
wrapper and is just as blind: the engine CLOSES that log during the same cleanup that emits these
errors. Measured on a clean-looking run: its `godot.log` ended at the `full logs:` line while
the process streams carried three more errors after it. So the wrapper reads the captured STDOUT and
STDERR (the engine splits teardown errors across both) and reports any error line **absent from
`godot.log`**, which is by definition one the in-run gate could not have seen. Its allowlist is
PARSED OUT of `all_tests.gd` rather than restated, so the two gates cannot drift apart.

Exit code = the suite's own failures + the exit-time errors. It found a real leak on its first run
(4 orphaned prop half-nodes holding `hoop_prop.png`; fixed in `prop_visual.gd::_notification`).

**Why:** the **PIXELS** suite (`Tests/Visual/test_pixels.gd`) renders the real effects into a
SubViewport and asserts on the image — flames point up, the hottest band is a spine and not a slab,
every ball sits on its independent oracle, a ball shades into 3+ tones with an off-centre
highlight, the hoop's halves reassemble the whole ring, a prop texel matches a card texel at three
card scales. **A dummy renderer cannot compile a shader**, so headless it reports a FAILURE telling
you to re-run windowed — it never skips. The owner's rule: *"prioritize running all tests properly
over skipping them, even if that means all tests never run headless anymore"*, because a skipped
pixel check looks exactly like a passing one in a log. Four real render bugs survived a green suite
that way.

Headless is still fine (and faster) for `--import`, for compile/parse checks, and when you only
care about the renderer-independent suites — expect exit code 1 from PIXELS and read the rest of
the log normally.

**Launch gotchas:**

- Invoke it so you WAIT for the process (PowerShell `Start-Process ... -PassThru` +
  `WaitForExit(ms)`). A plain call operator (`& $exe ...`) can hand back control while the run
  continues in the background — two overlapping runs then truncate each other's log and it looks
  like a hang. `Get-Process *odot*` shows the orphans.
- `TestLog` flushes every line, so a 0-byte log means the run has not logged yet (or another run
  just truncated it) — not that it died silently.
- **Deliberate stderr noise is expected** from LEAK CANARY (`LeakSentinel: ... unreachable`
  push_error, worldgen `_load_baked` warning, "N ObjectDB instances were leaked") and from PALETTE
  (`Palette index -5 out of range 0..31 — clamped`). Those two calls ARE the clamp contract being
  pinned: `Palette.color` reports an out-of-range index rather than returning a silent wrong
  colour. Both suites say so in their own check text.
- The real verdict is `test_output_errors.log` (empty = green) plus the final banner. ⚠ That file
  is the SUITE's own channel, not Godot's stderr, so a deliberate `push_error` never reaches it —
  which is exactly what keeps "empty = green" a usable signal.

## 0a. ALWAYS bound the run — a parse error makes the suite hang FOREVER

**Never launch the suite without a hard timeout that KILLS it.**

**The failure mode.** A parse error in `Tests/Support/test_base.gd` does not stop the run.
`TestSuite` fails to compile, so every suite scene falls back to plain `Node` — losing
`await_siblings_except` and `finish()` — and the suites that wait on their siblings wait forever.
The run never terminates and never reports. The log signature:

```
SCRIPT ERROR: Parse Error: ...                      <- the ONE real error, near the top
   at: GDScript::reload (res://Tests/Support/test_base.gd:NNN)
SCRIPT ERROR: Invalid call. Nonexistent function 'behavior_section' in base 'Node (...)'
SCRIPT ERROR: Invalid call. Nonexistent function 'await_siblings_except' in base 'Node (...)'
```

`behavior_section` / `await_siblings_except` "not found in base **Node**" for EVERY suite ⇒
`test_base.gd` itself did not compile. Scroll to the FIRST `Parse Error`; everything after it is
cascade noise. Two parse-error classes worth knowing: passing a `Variant` where a typed parameter is
declared (warnings-as-errors — `Callable.call()` and an element of an untyped `Array` each return
one, so `check(rows[i] == x, ...)` and `check(cmp.call(a, b), ...)` are BOTH parse errors rather
than runtime ones), and a child suite declaring a `const` that already exists in `TestSuite` —
GDScript forbids shadowing an inherited const. ⚠ `REAL_SETTINGS_PATH` lives in `TestSuite` ALONE — do not reintroduce
a local copy in a suite.

⚠ **A PARSE ERROR CAN ALSO PRESENT AS A GREEN-LOOKING RUN WITH A SMALLER SUITE COUNT.** When the
broken script is one suite rather than `test_base.gd`, that suite simply fails to LOAD, every other
suite finishes normally, and the banner reads `ALL 29 SUITES: ... PASSED` instead of 30. **The SUITE
count is the stable number — the check total drifts run to run**, so only the suite count can catch
this. A `Variant` typing error in one suite drops the count to 29 while the run still reads as a pass.

**There is no working pre-flight parse check.** Both obvious candidates are useless here:

- `--check-only --script res://...` does NOT register autoloads, so every script mentioning
  `SettingsManager` / `RunManager` fails with a bogus `Identifier not found` and exits 1. Nothing
  but false positives.
- `--headless --path . --import` does NOT surface script parse errors at all — with a deliberately
  broken `.gd` in the project it prints nothing and exits **0**. (It also leaves a `.uid` next to
  any new script; delete both if you scratch-test one.)

So catch it **in the same command as the run**. Bash (`timeout` is at `/usr/bin/timeout`;
exit 124 = killed):

```bash
timeout 500 "$GODOT_CONSOLE" --path <proj> res://Tests/all_tests.tscn > /tmp/run.log 2>&1
echo "exit: $?  (0 = green, 124 = HUNG, other = failure count)"
grep -n "Parse Error" /tmp/run.log | head    # non-empty => a script did not compile
```

PowerShell — `WaitForExit(ms)` alone is NOT enough, it only stops *you* waiting; kill the process
or it keeps running and truncates the next run's log:

```powershell
$p = Start-Process $godotConsole -ArgumentList $args -RedirectStandardOutput $log -PassThru
if (-not $p.WaitForExit(300000)) { $p.Kill(); "HUNG - killed" }
Select-String -Path $log -Pattern "Parse Error" | Select-Object -First 5
```

To fail fast while a run is still going: `grep -c "Parse Error" <log>` a few seconds in. Non-zero
means kill it now — it will never finish. Before killing, `Get-Process *odot*` and check
`MainWindowTitle` is EMPTY: **never kill a process with an editor window title** (START_HERE rule
1). A killed run can leave BOTH the console launcher and the main exe.

## 0b. The VISUAL instruments are separate runs, and one of them is a diff

None of these are in `all_tests.tscn` — they need a window and a GPU, and they write PNGs rather
than asserting. Three scenes write reviewable panels, each to its own directory under
`%APPDATA%\Godot\app_userdata\Solatro\`:

```bash
"$GODOT_CONSOLE" --path solatro res://Tests/Visual/fx_snapshot.tscn        # -> fx_snapshots/       18 panels
"$GODOT_CONSOLE" --path solatro res://Tests/Visual/prop_art_snapshot.tscn  # -> prop_art_snapshots/  8 panels
"$GODOT_CONSOLE" --path solatro res://Tests/Visual/fx_behind.tscn          # -> fx_behind/           5 panels
py solatro/Tools/snapshot_diff.py save    # stash the panels you trust
py solatro/Tools/snapshot_diff.py diff    # re-run the scenes first, then prove nothing moved
```

**For a change that must NOT alter the picture, the diff is the instrument and your eye is not.**
The reverse also holds: for a change that is supposed to look different, the diff says nothing.

⚠ **FOUR PANELS DIFFER ON UNCHANGED CODE**, and the tool lists them as `noisy` rather than counting
them: `02_fire_rotation`, `05f_ball_rotation` and `behind_prop_turned` (every ROTATED host is
nondeterministic — cause unknown, FX_HANDOFF §12), plus `09_embers` (randomised particles, by
design). A clean run reads:

```
0 of 27 comparable panels differ (4 known-noisy skipped, 3 of 3 sets compared)
```

⚠ **`fx_cost.tscn` is a bench, not a test** — it prints a table of ms/frame and quits. On Box B
take three runs and the MINIMUM (its GPU timer is bimodal by ~1.3–1.5x); Box A is steady to ~2–3 %.

## 0c. THE VISUAL LOG — behaviour over TIME, which no snapshot can show

A PNG proves what one frame looked like. It cannot answer *"did those five beams appear together or
one after another"*, *"did the board rebuild under the light"*, or *"why did that section light
nothing"* — those are questions about ORDER, and the instrument for them is `EventLog`
(`Scripts/event_log.gd`), not a picture and not a green test.

```bash
"$GODOT_CONSOLE" --path solatro res://Tools/spotlight_tool.tscn -- --trace   # -> user://logs/spotlight_trace/
```

**Two log roots under `%APPDATA%\Godot\app_userdata\Solatro\logs\`, deliberately separate:**

| Folder | Written by | Answers |
|---|---|---|
| `logs\test\` | `TestLog` | what `check()` said — PASS/FAIL, sections, banners |
| `logs\events\<run>\` | `EventLog` | what the game DID — `summary.log`, `visual_log.log`, `visual_log_by_frame.log` |

(`logs\godot*.log` are Godot's own engine logs and belong to neither.)

⚠ **`EventLog` is GENERIC** — not the spotlight's, and not only the visual layer's. `<run>` names a
capture, so scripted scenarios, a mod being debugged and an owner playtest coexist and are referred
to by path.

**Two channel GROUPS, one timeline:**

| Group | Channels | Fires headless? |
|---|---|---|
| `GROUP_VISUAL` | `spotlight` `light` `board` `prop` `score` | no — these have pixels |
| `GROUP_DATA` | `act` `move` `mod` `state` `input` | **yes** |

`EventLog.begin()` records everything; `begin(EventLog.GROUP_DATA)` gives a headless-meaningful
capture. ⚠ **They share ONE timeline on purpose** — the question worth asking is *"did the data
layer do X before or after the visual layer did Y"*, and two separate logs cannot answer it.

**Recording a playtest (debug builds only).** Three buttons, top-right of `GameView`: `Rec` toggles
a capture and WRITES it on stop (printing the folder), `<< Undo` is an **uncapped** debug rewind,
`Redo >>` steps forward again. The loop they serve: *see a bug → debug-undo past it → Rec → redo
the action → Stop → send the folder*. ⚠ The debug history is separate from `save_history`, which
stays capped — raising `undo_cap` to serve debugging would change the game to serve the tool.

⚠ **`f=` IS THE ORDERING TRUTH, NOT `t=`.** Same frame = one moment on screen = parallel. One frame
per event = sequential. A wall-clock gap cannot distinguish those (0.3 ms is either one frame's
work or two frames at 3000 fps), and the act speed-up makes that ambiguity the normal case rather
than the edge case. The frame counter is also exact under `--headless`, where wall-clock means
nothing.

⚠ **READ `EventLog.summary()` FIRST** — it is a few dozen lines however long the capture ran. The
per-event tally is often the whole diagnosis: `score_line 12` against `lights_set 4` says eight
sections lit nothing, which is a bug found without opening the event list. Recording stops at
`max_events` (20000) with a warning rather than growing without bound; if you hit it, narrow the
channels passed to `begin()` rather than raising the cap.

**To add a channel to something:** `EventLog.event(EventLog.CH_BOARD, "what", "detail")`. It is
free when disabled (one static bool), but build the detail string only behind `EventLog.is_on(ch)`
if it costs anything — arguments evaluate before the guard inside `event()` can reject them.

## 1. `--headless` never fires `RenderingServer.frame_post_draw`

Any `await RenderingServer.frame_post_draw` stalls FOREVER headless — the scene prints its banner
and then produces nothing, parked on the first GPU `flush()`
(`worldgen/addons/worldgen/core/world_generator.gd::flush`).

- Every worldgen scene that generates a world (`generate_up_to`, `graph_placement`, `biome_*`,
  `addon_*`) MUST run windowed: `Godot --path <project> res://tests/<scene>.tscn`, no `--headless`.
- **Solatro awaits `frame_post_draw` too**, in the PIXELS suite and the two snapshot scenes — so
  headless they would hang exactly like worldgen's. All three therefore CHECK
  `DisplayServer.get_name()` first: PIXELS reports a failure telling you to re-run windowed, and
  the snapshot scenes `push_error` + quit. **Never "fix" a new visual test by making it skip under
  headless** — run it properly instead (§0). Without those guards, a headless snapshot run sits
  past a 2-minute timeout having written nothing, while stale PNGs from an earlier windowed run sit
  on disk looking like output.

## 2. Stale global class cache ("Could not find type X" cascades)

`.godot/global_script_class_cache.cfg` goes stale when class-bearing scripts change outside the
editor (agent edits, re-copying the vendored addon). Symptoms range from silent suite skips to hard
parse-error cascades ("Identifier X not declared"). Fix FIRST, before debugging code:

    Godot --headless --path <project> --import

(`--import` itself exits cleanly headless.)

## 3. Headless window size is (0,0)

`DisplayServer.window_get_size()` is (0,0) headless (root window clamped to 100x100) while
`canvas_items` stretch keeps the canvas at design size. Anything converting window↔canvas
coordinates — e.g. `Input.parse_input_event` synthetic clicks — breaks. Use the `to_window()`
helper in `Tests/UI/test_interaction.gd`; reuse that pattern for any future synthetic input.

## 4. Misc

- Windowed test runs work fine on both boxes; expect a window to flash up.
- Suite check TOTALS vary run-to-run (data-dependent suites). Compare FAILURE SETS, not counts.
- Worldgen scenes `addon_bake_test` / `addon_node_test` never call `quit()` (by design — they are
  also demos); kill them after the PASS lines.
