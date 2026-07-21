# START HERE — Solatro agent guide & planning playbook

**Read this first if you are new to this directory.** It is the distillation of every
plan, handoff, and audit this project has run (2026-07). It exists so future work does
not re-learn the same lessons or re-clutter the repo with plan files. **Keep it current:
whenever a feature lands or a ruling changes, update this file + ARCHITECTURE_REVIEW.md,
and fold/delete any temporary plan docs (see "Doc hygiene" below).**

## Read-first map

| Doc | What it is |
|---|---|
| [START_HERE.md](START_HERE.md) | This file — rules, workflow, learnings. |
| [ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md) | Current-state architecture + every regression-critical rule (scoring §3a/§3b, props §4, undo §5, memory §6, testing §7, owner rulings §8). |
| [LAYERING.md](LAYERING.md) | Board draw order (all-structural, no z_index). |
| [HEADLESS_TESTING.md](HEADLESS_TESTING.md) | Test-environment traps on this machine. READ BEFORE DEBUGGING A "HANGING" TEST. |
| [todo.md](todo.md) | Open backlog. |
| [DESIGN_DOC.md](DESIGN_DOC.md) | The organized game-design record (owner's ideas). |
| [DESIGN_RECOMMENDATIONS.md](DESIGN_RECOMMENDATIONS.md) / [DESIGN_REFERENCES.md](DESIGN_REFERENCES.md) | Claude's design proposals / historical-reference quarry. |

## Hard project rules (non-negotiable — every past handoff restated these)

1. **Never run headless Godot while the owner's editor has the project open** — the two
   instances starve each other. Check `Get-Process *odot*` + `MainWindowTitle`; never
   kill a process with an editor window title. With the editor CLOSED, run the suite
   yourself (see Environment facts) — that is the expected verification, not a handoff.
   Only the *game* still needs the owner (an agent shouldn't play it). The open
   editor also LOCKS vendored dlls (copies fail) and rewrites `.tscn`/`project.godot` on
   disk — do scene/project edits with the editor closed, and re-read files from disk
   before diagnosing (the editor may have rewritten them).
2. **No `git add`, no commits, no staging** — the owner commits via GitHub Desktop.
   Just edit files.
3. **Warnings are errors:** type EVERY array and EVERY for-loop variable
   (`for col : ArrayCardData in ...`).
4. **User-facing strings** go through `TRANSLATION.find` + `Locale/localization.csv`,
   never literals. **Tuning knobs** live in `Scripts/player_settings.gd` via
   `SettingsManager.settings` (setters emit `settings_changed`); animation timings are
   FRACTIONS of `get_delay()`, never wall-clock literals.
5. **Commented-out code policy:** TODO comment if unimplemented, delete if implemented
   elsewhere. `##` purpose comments on every new method.
6. **Board mutations** go through `Board.*`/Game deck functions and bump
   `GameData.revision` AFTER consistency (ARCHITECTURE_REVIEW §2 — a miss = stuck UI +
   stale caches + stale positions). Per-act/per-show state that undo must rewind lives on
   **GameData**, never on Game.
7. **After every deep copy of cards, relink backrefs** (`duplicate_deep` does not remap
   WeakRefs — ARCHITECTURE_REVIEW §6).
8. **Tests:** TestSuite pattern, never `Decks/deck.gd` in tests (use TestDecks — frozen
   replay contracts), mind the DEADLOCK RULE, `await` every coroutine test, compare
   failure SETS not check totals. Full suite green after every landed step.
9. `addons/worldgen/` is **vendored** — never edit it here. Land changes in the
   `worldgen` project, validate there, re-copy changed files (never its README), run
   `--import`, then the full suite. See `../worldgen/START_HERE.md`.
10. Multi-modal input (mouse + keyboard + controller) is required for every UI.
11. After adding a `class_name` or editing the vendored addon: delete `.godot/` or run
    `--headless --path . --import` before trusting any run (stale class cache).

## How to plan & implement a feature here (the distilled workflow)

Every successful plan in this repo followed the same shape; repeat it:

1. **Verify current code first.** Read the actual files and pin line numbers / signatures
   the plan touches ("Audit facts this plan is built on"). Docs go stale — code wins.
   Check ARCHITECTURE_REVIEW §8 owner rulings before "fixing" anything odd-looking.
2. **Measure before designing balance.** For scoring/economy work, extend
   `tools/scoring_sim.py` (Python, safe to run anytime) and get numbers before proposing
   formulas. Mark every number with how it was produced so it can be re-run.
3. **Write the plan as steps that each leave the game runnable**, with per-file
   pseudocode, a migration/save-compat section, and a test plan (new suites + which
   existing suites must stay green). Put behavior changes and architecture changes behind
   explicit **owner APPROVAL lines** (yes/no per item) — the owner rules on each;
   implement only the YES items. Record rulings verbatim; they become §8 material.
4. **Ask the grill questions early.** Ambiguities (identity rules, opt-in vs opt-out,
   UI placement) got resolved fastest as a numbered question list with recommended
   defaults.
5. **Implement in order, full suite after each step.** New per-act state → GameData.
   New strings → localization CSV. New knobs → player_settings. New tests follow the
   conventions in ARCHITECTURE_REVIEW §7.
6. **Owner verification script:** end the work with a short numbered in-game checklist
   the owner can run (they run scenes; you don't).
7. **Docs pass (mandatory):** update ARCHITECTURE_REVIEW.md (current state + new
   landmines/rulings), todo.md (close items, add follow-ups), DESIGN_DOC.md if design
   settled, and this file if the workflow/rules changed.

## Doc hygiene (prevents the clutter this file replaced)

- Temporary plan/handoff docs are fine WHILE work is in flight, but once landed and
  verified: fold the regression-critical residue into ARCHITECTURE_REVIEW.md (rules,
  landmines, contracts — not the story of how it was built), move open items to todo.md,
  then **delete the plan doc**. Git history keeps the full text.
- Never keep "what happened on date X" logs in living docs — git has them. A living doc
  states what IS, plus the rules that prevent regressions.
- Periodically (or when root-level .md files exceed ~8), repeat the consolidation this
  file came from: read everything, merge, delete.

## Retired docs → where their content lives now

Code comments still cite these by section number; the full texts are in git history
(deleted 2026-07-19):

| Retired doc | Live home |
|---|---|
| SCORING_MATH_PLAN.md §15a/§15b (+§8c′ overscore rationale) | ARCHITECTURE_REVIEW §3a/§3b |
| SCORING_IMPL_PLAN.md, SCORING_AUDIT.md | ARCHITECTURE_REVIEW §3 + todo.md test gaps |
| SUIT_PROPS_PLAN.md (§1.3/§1.5/§1.6/§4.x, Phases) | ARCHITECTURE_REVIEW §4 |
| PROPS_BUGFIX_HANDOFF.md (landmines, R1–R8 reference) | ARCHITECTURE_REVIEW §4 |
| UNIT_TESTS_PLAN.md (§1–§8 suite specs, conventions) | ARCHITECTURE_REVIEW §7 |
| HANDOFF_worldgen_map.md (map/run/persistence) | ARCHITECTURE_REVIEW §1.5 |
| FORMATION_LAYERING_HANDOFF.md | ARCHITECTURE_REVIEW §4c + LAYERING.md |
| AUDIT_PROPOSALS_HANDOFF.md, EFFICIENCY_AUDIT_TRACKER.md, efficiency_audit.txt | ARCHITECTURE_REVIEW §2/§8 + todo.md; coding best practices below |
| LEAK_PREVENTION_HANDOFF.md, PRODUCTION_LEAK_CANARY_HANDOFF.md | ARCHITECTURE_REVIEW §6 |

## Coding best practices (kept from the efficiency-audit charter)

O(n) max in hot paths (flag nested scans); no recursion (flat while loops); single-pass
traversals; type everything (arrays, dicts, loop vars); PackedArrays for heavy numeric
data; `&"StringName"` for engine-name APIs in hot loops; `"%d" %` formatting over `+`
concatenation in loops; native engine methods over hand-rolled utilities; signal-driven
logic over `_process` polling (`set_process(false)` when idle); threaded file I/O;
preload assets; composition over deep inheritance; data in Resources, not hardcoded in
nodes; no silent failures (push_error / explicit Error returns — never bare `pass` in an
error path; note `assert()` strips in release, don't put side effects in it); dirty flags
over cascading signal storms; `@tool` scripts idle cheaply; strict logic preservation in
refactors; new files / architecture changes need owner approval + a design doc first.
C#/GDExtension migration candidates get flagged in comments, not converted ad hoc.

## Environment facts

- Godot 4.7.1, `C:\Users\khanr\Desktop\Godot_v4.7.1-stable_win64.exe`. The console
  variant (`Godot_v4.7.1-stable_win64_console.exe`) is the one whose stdout can be
  redirected to a file — it must sit in the SAME folder as the main exe (it launches it
  by name); a copy lives on the Desktop next to it. Repo:
  `C:\Users\khanr\Documents\GitHub\gamedev` (docs mentioning `C:\richard\gamedev` are
  from the owner's other machine — same repo).
- Full suite: `Godot --headless --path solatro res://Tests/all_tests.tscn` — exit code =
  failure count. Logs: `%APPDATA%\Godot\app_userdata\Solatro\test_output_all.log`.
  **An agent may and should run this itself** whenever the owner's editor is closed
  (verified 2026-07-20: clean self-terminating run, 25 suites / 0 failures, ~40 s; the
  check total drifts between runs — judge by the suite count and the failure set).
  ⚠️ **ALWAYS bound the launch with a hard timeout that KILLS, and grep the log for
  `Parse Error` in the same command** — a parse error in `Tests/Support/test_base.gd` does
  not fail the run, it makes it hang FOREVER (every suite degrades to plain `Node` and the
  sibling-waiters never finish). There is no working pre-flight check: `--check-only`
  false-positives on autoloads and `--import` misses script errors entirely. The exact
  commands, the log signature, and how to kill it safely: **HEADLESS_TESTING.md §0a.**
  A bare `& exe ...` / `WaitForExit` without a `Kill()` also leaves orphans that truncate
  the next run's log. Read only the FAIL lines (`test_output_errors.log`, empty = green)
  plus the final banner.
- Scoring sim: `py solatro/tools/scoring_sim.py --final --q 0.35` (Python, safe anytime).
