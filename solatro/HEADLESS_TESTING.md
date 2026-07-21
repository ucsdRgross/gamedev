# Headless testing on this machine — READ BEFORE DEBUGGING A "HANGING" TEST

Findings from the 2026-07 efficiency audit sessions (last updated 2026-07-20).
Applies to Godot 4.7.1 (`C:\Users\khanr\Desktop\Godot_v4.7.1-stable_win64.exe`; the
`_console` variant, which is the redirectable one, must live in the same folder as the
main exe — it launches it by name) and both projects (`solatro`, `worldgen`).

## 0. The Solatro suite runs fine headless — agents should run it

Re-verified 2026-07-20: `--headless res://Tests/all_tests.tscn` completed in ~40 s,
quit itself, 25 suites / 0 failures (check TOTALS drift run-to-run — 1332 and 1367 both
seen on 2026-07-20; the suite COUNT and the failure set are the stable signals, never the
check total). Two launch gotchas, both cost time
that day:

- Invoke it so you WAIT for the process (PowerShell `Start-Process ... -PassThru` +
  `WaitForExit(ms)`); a plain call operator (`& $exe ...`) can hand back control while
  the run continues in the background — two overlapping runs then truncate each other's
  log and it looks like a hang. `Get-Process *odot*` shows the orphans.
- `TestLog` flushes every line, so a log that is 0 bytes means the run has not logged
  yet (or another run just truncated it) — not that it died silently.
- Deliberate stderr noise is expected from LEAK CANARY (`LeakSentinel: ... unreachable`
  push_error, worldgen `_load_baked` warning, "4 ObjectDB instances were leaked").
  The real verdict is `test_output_errors.log` (empty = green) + the final banner.

## 0a. ALWAYS bound the run — a parse error makes the suite hang FOREVER

**Never launch the suite without a hard timeout that KILLS it.** This is not paranoia; it
is the single most likely way to lose an hour (cost one on 2026-07-20).

**The failure mode.** A parse error in `Tests/Support/test_base.gd` does not stop the run.
`TestSuite` fails to compile, so every suite scene falls back to plain `Node` — losing
`await_siblings_except` and `finish()` — and the suites that wait on their siblings wait
forever. The run never terminates and never reports. The signature in the log is:

```
SCRIPT ERROR: Parse Error: ...                      <- the ONE real error, near the top
   at: GDScript::reload (res://Tests/Support/test_base.gd:NNN)
SCRIPT ERROR: Invalid call. Nonexistent function 'behavior_section' in base 'Node (...)'
SCRIPT ERROR: Invalid call. Nonexistent function 'await_siblings_except' in base 'Node (...)'
```

`behavior_section`/`await_siblings_except` "not found in base **Node**" for EVERY suite ⇒
`test_base.gd` itself did not compile. Scroll to the FIRST `Parse Error` — everything after
it is cascade noise. Two parse errors that hit that day, both worth knowing:
`duplicate()` on an inferred `Variant` (warnings-as-errors), and a child suite declaring a
`const` that already exists in `TestSuite` (GDScript forbids shadowing an inherited const —
UI PROPS, VISUAL LAYERS and LEAK CANARY each declare `REAL_SETTINGS_PATH`, so adding that
name to the base class breaks all three).

**There is no working pre-flight parse check** — both obvious candidates were tested on
2026-07-20 and both are useless here:

- `--check-only --script res://...` does NOT register autoloads, so every script that
  mentions `SettingsManager`/`RunManager` fails with a bogus `Identifier not found` and
  exits 1. Nothing but false positives.
- `--headless --path . --import` does NOT surface script parse errors at all: with a
  deliberately broken `.gd` in the project it printed nothing and exited **0**.
  (It also leaves a `.uid` next to any new script — delete both if you scratch-test one.)

So catch it **in the same command as the run**: bound it, then grep the log. Bash tool
(`timeout` is present at `/usr/bin/timeout`; exit 124 = it was killed):

```bash
timeout 300 "$GODOT_CONSOLE" --headless --path <proj> res://Tests/all_tests.tscn > /tmp/run.log 2>&1
echo "exit: $?  (0 = green, 124 = HUNG, other = failure count)"
grep -n "Parse Error" /tmp/run.log | head    # non-empty ⇒ a script did not compile
```

PowerShell equivalent — `WaitForExit(ms)` alone is NOT enough, it only stops *you* waiting;
kill the process or it keeps running and truncates the next run's log:

```powershell
$p = Start-Process $godotConsole -ArgumentList $args -RedirectStandardOutput $log -PassThru
if (-not $p.WaitForExit(300000)) { $p.Kill(); "HUNG - killed" }
Select-String -Path $log -Pattern "Parse Error" | Select-Object -First 5
```

A fast fail-fast while the run is still going: `grep -c "Parse Error" <log>` a few seconds
in. Non-zero means kill it now — it will never finish. Before killing, `Get-Process *odot*`
and check `MainWindowTitle` is EMPTY: never kill a process with an editor window title
(START_HERE rule 1). A killed run can leave BOTH the console launcher and the main exe.

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
