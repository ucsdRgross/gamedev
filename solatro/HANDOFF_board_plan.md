# HANDOFF — board plan (PLAN.md, every phase, S1–S17)

**Goal:** land `solatro/design/board-plan/PLAN.md` steps S1–S17 (every phase, closing included) on branch `board-plan`, one
verified step per commit. Owner ruling mid-run: do not stop at S10 — every phase is in scope.
**State:** worktree `../gamedev-boardplan` created from `main` at a28c79aa; import cache warmed
(`--headless --import` twice, second pass clean). Baseline full suite running. GAP-001 filed before
S1: the deal's per-slot stocks are sidebar S19, which is outside the sidebar run in progress, so
the deal reads `draw_deck` as its one stock and TP-05/TP-06 are parked (see the gap for the ruling
still wanted). No step dispatched yet.
**Entry docs:** solatro/design/board-plan/PLAN.md (self-contained), DESIGN.md (authority on
behaviour), TEST_PLAN.md (every test that must exist), NAMES.md (every identifier),
ASSUMPTIONS.md (decisions logged), gaps/, solatro/START_HERE.md
**IMPLEMENTED-BY:** `plan-implementer` subagent — `opus` (Opus 5) at default effort, every step.
Overseer: Fable 5.1 at high effort; it writes no source.

## Provenance
- Code: `plan-implementer` — Opus 5 (default effort) for every step so far.
- Reviewer floor: Opus 5 at default effort or higher (`opus` or `fable`), same generation or newer.

## Run rules in force
- Worktree `../gamedev-boardplan`, branch `board-plan`. Overseer commits one verified step per
  commit. Implementer never stages or commits.
- ONE implementer at a time (hook-enforced; the second slot is a non-Godot reviewer only).
  Dispatch every implementer FOREGROUND (`run_in_background: false`): the lock's PostToolUse
  release only fires for foreground calls.
- The sidebar run (`../gamedev-sidebar`) is live in parallel and shares `app_userdata/Solatro`
  with this worktree: check for a running `Godot_v4.7*` process before EVERY suite run, and never
  start one while another is up. A failure observed during an overlap is not evidence.
- A stale `Godot_v4.1.2` process titled `Solatro (DEBUG)` was running when this run opened — not
  ours, never kill it.
- Every `--import` and every suite run rewrites `solatro/design/effect-review/EFFECTS.*.translation`
  and `.csv.import`. Revert before each commit: `git checkout -- solatro/design/effect-review` then
  `git clean -fq -- solatro/design/effect-review/*.translation`.
- The suite: `GODOT_BIN=<console exe> py solatro/Tools/run_tests.py`, WINDOWED, from the worktree
  root. Test logs: `%APPDATA%\Godot\app_userdata\Solatro\logs\test\test_output_all.log` and
  `test_output_errors.log` — copy them aside per run; every run truncates them.
- `main` has no `--logic` tier and no `--filter` (those live on `test-speed`/`sidebar`); every run
  here is the full windowed one.
- Suite count derivation: `grep -c 'ext_resource type="PackedScene"' solatro/Tests/all_tests.tscn`
  = 45 at the start; rises by one per suite this run adds (BOARD PLAN, MARK MATCH).

## Baseline (main @ a28c79aa, unmodified, this box)
- pending — see task S0's evidence.

## Dispatch plan (steps regrouped so each dispatch leaves the suite green; ids unchanged)
1. S1+S2 — `granted`, `plan_seed`, `BoardPlan.is_marked`, I6 in `validate()`, `PLAN_DECK`, suite
   BOARD PLAN registered with TP-16.
2. S8 (pulled forward: S1's done-when needs the `is_spotlit()` call site) + `write_mark`/`clear_mark`
   — TP-11, TP-12 (BOARD PLAN), TP-44, TP-45 in new suite MARK MATCH.
3. S3 — the planner rules card, localised.
4. S4 — `deal()`; TP-01…TP-04, TP-07…TP-10, TP-13…TP-15, TP-17, TP-18. TP-05/06 parked (GAP-001).
5. S5 — `matches_at`, the leniency comment family; TP-20…TP-27, TP-39.
6. S6 — the composition in `score_line`; TP-30…TP-38. Gate: SECTION 8 leaderboard byte-identical.
7. S7 — the suit rule; TP-40…TP-43. Re-derive `test_suit_props.gd` red-then-green.
8. S9 — the two hooks; TP-46…TP-51, TP-53, TP-54.
9. S10 — reroll / grant / swap on `CardEffectApi`; TP-52.

## Tasks
```yaml
- id: S0
  description: Baseline full suite on the unmodified worktree; capture SECTION 8's leaderboard for TP-33.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: in_progress
  evidence: ''
  notes: ''
- id: S1
  description: TypeGridCell.granted; BoardPlan.is_marked; called from validate() and is_spotlit().
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'dispatched together with S2; the is_spotlit call site lands in dispatch 2'
- id: S2
  description: GameData.plan_seed; invariant I6; TP-16.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
- id: S3
  description: SkillBoardPlanner in rules1, localised; localisation gate clean.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
- id: S4
  description: BoardPlan.deal() per PLAN 1.2 from the planner's on_game_start; TP-01..TP-18 minus TP-05/06.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'TP-05/TP-06 parked on GAP-001; write_mark/clear_mark land in dispatch 2'
- id: S5
  description: MarkMatch.matches_at, flat_bonus, mult_bonus; leniency hook comments; TP-20..27, TP-39.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
- id: S6
  description: (hand + flats) x M in score_line; TP-30..38; SECTION 8 leaderboard byte-identical.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
- id: S7
  description: suit effect fires iff SUIT matched; talent suppression retired; TP-40..43.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
- id: S8
  description: is_spotlit/blocks_spotlight false for a mark; TP-44, TP-45.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'lands in dispatch 2, before S3'
- id: S9
  description: on_mark_covered / on_mark_hit dispatched from place_card_in_grid; TP-46..51, TP-53, TP-54.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
- id: S10
  description: mark_at, reroll_mark, grant_mark, swap_marks on CardEffectApi; TP-52.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
```

## Verified vs assumed
- Import cache: verified — second `--import` pass printed no error line.
- Stocks absent on `main` and `sidebar`: verified — `git grep -il stock` empty on both.

## Open bugs
- none yet

## Files touched
- solatro/design/board-plan/gaps/GAP-001.md, ASSUMPTIONS.md (new); PLAN.md §3 S1 row and NAMES.md
  `BoardPlan` row corrected to agree.

## Next up
1. Read the baseline banner; record it above; extract SECTION 8 to a scratch file.
2. Dispatch 1 (S1+S2).
3. Dispatch 2 (S8 + write_mark/clear_mark).

Opening prompt for a cold overseer: "Resume /plan-run for solatro/design/board-plan on branch
board-plan in ../gamedev-boardplan. Read solatro/HANDOFF_board_plan.md, then git log --oneline,
git status --porcelain, and a full windowed suite run before trusting any done status."

## References
- `.claude/skills/plan-run/SKILL.md`, `.claude/skills/handoff/SKILL.md`
- `solatro/HANDOFF_sidebar.md` on branch `sidebar` — the parallel run and its stock step S19
