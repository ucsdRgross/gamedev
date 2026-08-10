# START HERE — Solatro agent guide & planning playbook

**Read this first if you are new to this directory.** It is the distillation of every plan,
handoff and audit this project has run, so future work does not re-learn the same lessons or
re-clutter the repo with plan files. **Keep it current:** when a feature lands or a ruling
changes, update this file and ARCHITECTURE_REVIEW.md, and fold/delete the temporary plan doc.

## Read-first map

| Doc | What it is |
|---|---|
| [ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md) | Current-state architecture + every regression-critical rule (scoring §3a/§3b, props §4, palette §4i, outline §4j, undo §5, memory §6, testing §7, owner rulings §8). |
| [VFX.md](VFX.md) | **Read FIRST for any fire / juggling / prop-art / outline / FX-shader work.** The map, the runbook, the backlog and the known bugs; the rules themselves are ARCHITECTURE_REVIEW §4g/§4h/§4j. |
| [FX_HANDOFF.md](FX_HANDOFF.md) | The fire/FX-performance stream. §0d.10 prices every remaining lever and lists the things that look like levers and measure as none. |
| [HANDOFF_spotlight.md](HANDOFF_spotlight.md) | The spotlight mechanic + visuals: status ledger, open bugs, what is still owed. |
| [PERFORMANCE.md](PERFORMANCE.md) | The optimisation survey — the measured baseline, what each instrument is blind to, every angle with an honest price, and the ⛔ list. A map of angles, not an open task. |
| [LAYERING.md](LAYERING.md) | Board draw order (all-structural, no `z_index`). |
| [HEADLESS_TESTING.md](HEADLESS_TESTING.md) | Test-environment traps. **Read before debugging a "hanging" test.** |
| [todo.md](todo.md) | Open backlog — the single place open items live. |
| [DESIGN_DOC.md](DESIGN_DOC.md) | The organized game-design record (the owner's ideas). |
| [DESIGN_RECOMMENDATIONS.md](DESIGN_RECOMMENDATIONS.md) / [DESIGN_REFERENCES.md](DESIGN_REFERENCES.md) | Claude's design proposals / reference quarry. |

## Hard project rules (non-negotiable)

1. **The editor being open is fine for running things — but it REWRITES FILES.**
   - It rewrites `.tscn` / `.tres` / `project.godot` on disk. If a resource's script is not
     `@tool` it loads as a PLACEHOLDER and the editor saves back only the properties it could
     see, **silently dropping the rest**. Re-read files from disk before diagnosing, and keep
     every script the editor touches `@tool` (ARCHITECTURE_REVIEW §4g).
   - It **LOCKS vendored dlls**, so copies fail.
   - ⚠ **Never kill a Godot process without reading `MainWindowTitle` first.** Filter to titles
     that are not an editor window, or ask. A blanket `Get-Process *odot* | Kill()` has closed
     the owner's editor with unsaved work.
   - Long runs need an explicit `timeout` parameter. A run that outlives the Bash tool's 120 s
     default is not GPU starvation — it is the default.
   Run the suite yourself; that is the expected verification, not a handoff. Only the *game*
   still needs the owner.
2. **No `git add`, no commits, no staging** — the owner commits via GitHub Desktop. Just edit.
3. **Warnings are errors:** type EVERY array and EVERY for-loop variable
   (`for col : ArrayCardData in ...`).
4. **User-facing strings** go through `TRANSLATION.find` + `Locale/localization.csv`, never
   literals. **Tuning knobs** live in `Scripts/player_settings.gd` via `SettingsManager.settings`
   (setters emit `settings_changed`); animation timings are FRACTIONS of `get_delay()`, never
   wall-clock literals.
5. **Commented-out code:** TODO comment if unimplemented, delete if implemented elsewhere.
   `##` purpose comments on every new method.
6. **Board mutations** go through `Board.*` / Game deck functions and bump `GameData.revision`
   AFTER consistency (ARCHITECTURE_REVIEW §2 — a miss gives stuck UI, stale caches, stale
   positions). Per-act/per-show state that undo must rewind lives on **GameData**, never on Game.
7. **After every deep copy of cards, relink backrefs** — `duplicate_deep` does not remap WeakRefs
   (ARCHITECTURE_REVIEW §6).
8. **Tests:** TestSuite pattern; never `Decks/deck.gd` in tests (use TestDecks — frozen replay
   contracts); mind the DEADLOCK RULE; `await` every coroutine test; compare failure SETS, not
   check totals. Full suite green after every landed step, and it runs **WINDOWED**.
   **A test that cannot run under the current renderer FAILS with the reason; it never skips** —
   the owner's ruling is "prioritize running all tests properly over skipping them", because a
   skipped check is indistinguishable from a passing one in a log.
9. `addons/worldgen/` is **vendored** — never edit it here. Land changes in the `worldgen`
   project, validate there, re-copy changed files (never its README), run `--import`, then the
   full suite. See `../worldgen/START_HERE.md`.
10. Multi-modal input (mouse + keyboard + controller) is required for every UI.
11. After adding a `class_name` or editing the vendored addon: delete `.godot/` or run
    `--headless --path . --import` before trusting any run (stale class cache).

## How to plan & implement a feature here

Every successful plan in this repo followed the same shape; repeat it:

1. **Verify current code first.** Read the actual files and pin the line numbers and signatures
   the plan touches. Docs go stale — code wins. Check ARCHITECTURE_REVIEW §8 owner rulings before
   "fixing" anything odd-looking.
2. **Measure before designing balance.** For scoring/economy work, extend `tools/scoring_sim.py`
   and get numbers before proposing formulas. Mark every number with how it was produced so it
   can be re-run.
3. **Write the plan as steps that each leave the game runnable**, with per-file pseudocode, a
   migration/save-compat section, and a test plan (new suites + which existing suites must stay
   green). Put behavior and architecture changes behind explicit **owner APPROVAL lines** (yes/no
   per item); implement only the YES items. Record rulings verbatim — they become §8 material.
4. **Ask the grill questions early.** Ambiguities (identity rules, opt-in vs opt-out, UI
   placement) resolve fastest as a numbered question list with recommended defaults.
5. **Implement in order, full suite after each step.** New per-act state → GameData. New strings →
   localization CSV. New knobs → player_settings. New tests follow ARCHITECTURE_REVIEW §7.
6. **Owner verification script:** end with a short numbered in-game checklist the owner can run.
7. **Docs pass (mandatory):** update ARCHITECTURE_REVIEW.md (current state + new landmines and
   rulings), todo.md (close items, add follow-ups), DESIGN_DOC.md if the design settled, and this
   file if the workflow or rules changed.

## Doc hygiene

- Temporary plan/handoff docs are fine WHILE work is in flight. Once landed and verified: fold
  the regression-critical residue into ARCHITECTURE_REVIEW.md (rules, landmines, contracts — not
  the story of how it was built), move open items to todo.md, then **delete the plan doc.**
- **Never keep "what happened on date X" logs in a living doc.** A living doc states what IS, plus
  the rules that prevent regressions. Git history has the rest.
- Every reference must resolve: if a doc names a file, section or tool, it exists.
- When root-level `.md` files exceed ~8, repeat the consolidation this file came from: read
  everything, merge, delete.

## Decoding old §citations in code comments

Code comments still cite plan docs that no longer exist. Their content lives here now:

| Cited as | Live home |
|---|---|
| SCORING_MATH_PLAN §15a/§15b, §8c′ | ARCHITECTURE_REVIEW §3a/§3b |
| SCORING_IMPL_PLAN, SCORING_AUDIT | ARCHITECTURE_REVIEW §3 + todo.md test gaps |
| SUIT_PROPS_PLAN §1.3/§1.5/§1.6/§4.x | ARCHITECTURE_REVIEW §4 |
| PROPS_BUGFIX_HANDOFF (R1–R8) | ARCHITECTURE_REVIEW §4 |
| UNIT_TESTS_PLAN §1–§8 | ARCHITECTURE_REVIEW §7 |
| HANDOFF_worldgen_map | ARCHITECTURE_REVIEW §1.5 |
| FORMATION_LAYERING_HANDOFF | ARCHITECTURE_REVIEW §4c + LAYERING.md |
| AUDIT_PROPOSALS_HANDOFF, EFFICIENCY_AUDIT_TRACKER | ARCHITECTURE_REVIEW §2/§8 + todo.md |
| LEAK_PREVENTION_HANDOFF, PRODUCTION_LEAK_CANARY_HANDOFF | ARCHITECTURE_REVIEW §6 |

## Coding best practices

O(n) max in hot paths (flag nested scans); no recursion (flat while loops); single-pass
traversals; type everything (arrays, dicts, loop vars); PackedArrays for heavy numeric data;
`&"StringName"` for engine-name APIs in hot loops; `"%d" %` formatting over `+` concatenation in
loops; native engine methods over hand-rolled utilities; signal-driven logic over `_process`
polling (`set_process(false)` when idle); threaded file I/O; preload assets; composition over deep
inheritance; data in Resources, not hardcoded in nodes; no silent failures (`push_error` or
explicit Error returns — never a bare `pass` in an error path; `assert()` strips in release, so no
side effects in it); dirty flags over cascading signal storms; `@tool` scripts idle cheaply; strict
logic preservation in refactors. New files and architecture changes need owner approval and a
design doc first. C#/GDExtension migration candidates get flagged in comments, not converted ad hoc.

## Environment facts

Binary paths and hardware differ per computer — see `../.claude/memory/machine-profiles.md`. The
**console** variant of the Godot exe is the one whose stdout can be redirected to a file, and it
must sit in the SAME folder as the main exe, which it launches by name.

- **Full suite:** `GODOT_BIN=<console exe> py solatro/Tools/run_tests.py` — the preferred entry
  point. It runs the suite windowed with a kill-on-timeout AND gates the exit-time engine errors the
  suite cannot see itself (`all_tests.gd`'s own scan runs before `quit()`, and the engine closes
  `godot.log` during the same cleanup that emits them, so neither the suite nor a naive re-read of
  that log can ever catch them — ARCHITECTURE_REVIEW §7). Exit code = suite failures + exit-time
  errors.
  The raw form is `Godot --path solatro res://Tests/all_tests.tscn` — **WINDOWED, no `--headless`**
  (the PIXELS suite asserts on rendered pixels; headless it fails loudly instead of skipping —
  HEADLESS_TESTING.md §0). Logs:
  `%APPDATA%\Godot\app_userdata\Solatro\test_output_all.log`. Run it yourself whenever the owner's
  editor is closed. ⚠ The check total drifts between runs — **judge by the SUITE count (31) and the
  failure set**; a drop in the suite count means a suite failed to LOAD while the banner still reads
  PASSED.
- ⚠ **Always bound the launch with a hard timeout that KILLS, and grep the log for `Parse Error`
  in the same command.** A parse error in `Tests/Support/test_base.gd` does not fail the run — it
  hangs FOREVER (every suite degrades to plain `Node` and the sibling-waiters never finish). There
  is no working pre-flight check: `--check-only` false-positives on autoloads and `--import` misses
  script errors entirely. Exact commands, log signature and how to kill it safely:
  **HEADLESS_TESTING.md §0a.** A bare `& exe ...` / `WaitForExit` without a `Kill()` leaves orphans
  that truncate the next run's log. Read only the FAIL lines (`test_output_errors.log`, empty =
  green) plus the final banner.
- **Scoring sim:** `py solatro/Tools/scoring_sim.py --final --q 0.35` (Python, safe anytime).
