# HANDOFF — board plan (PLAN.md, every phase, S1–S17)

**Goal:** land `solatro/design/board-plan/PLAN.md` steps S1–S17 (every phase, closing included) on branch `board-plan`, one
verified step per commit. Owner ruling mid-run: do not stop at S10 — every phase is in scope.
**State:** worktree `../gamedev-boardplan` created from `main` at a28c79aa; import cache warmed
(`--headless --import` twice, second pass clean). Baseline recorded below. GAP-001 filed before
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
- The sidebar run (`../gamedev-sidebar`) is live in parallel on this box and runs the suite
  often. Godot on Windows takes its data dir from the `APPDATA` environment variable and the
  wrapper expands the same variable, so EVERY run here sets `APPDATA` to a private directory
  (this session: a scratch `appdata/`) — its own `settings.tres`, `run_save`, `godot.log` and test
  logs. Measured: two runs on one shared `app_userdata` truncated each other's logs and pushed the
  full run past the wrapper's 600 s default. Residual risk: two windowed runs can still steal
  each other's focus, so a GRID VIEW real-key-press failure during an overlap is not evidence.
- A stale `Godot_v4.1.2` process titled `Solatro (DEBUG)` was running when this run opened — not
  ours, never kill it.
- Every `--import` and every suite run rewrites `solatro/design/effect-review/EFFECTS.*.translation`
  and `.csv.import`. Revert before each commit: `git checkout -- solatro/design/effect-review` then
  `git clean -fq -- solatro/design/effect-review/`.
- The suite: `APPDATA=<private dir> GODOT_BIN=<console exe> py solatro/Tools/run_tests.py
  --timeout 900`, WINDOWED, from the worktree root. Test logs under
  `<APPDATA>\Godotpp_userdata\Solatro\logs	est\` — copy them aside per run; every run
  truncates them.
- `test-speed` is merged (fast-forward), so `--logic` (headless tier, inner loop) and
  `--filter <Node>` exist here; the gate is still the full windowed run. The GRID LAYOUT
  physics-tick settle from sidebar 6bca9197 is carried as its own commit.
- Suite count derivation: `grep -c 'ext_resource type="PackedScene"' solatro/Tests/all_tests.tscn`
  = 45 at the start; rises by one per suite this run adds (BOARD PLAN, MARK MATCH).

## Baseline (main @ a28c79aa + test-speed b8b8831b + the GRID LAYOUT settle, this box)
- Full windowed run, isolated `APPDATA`, `--timeout 900`, ~4 min wall clock:
  `ALL 45 SUITES: 4005 passed, 1 FAILED (1 behavior, 0 implementation) [23 placeholder warnings]`
  (second run: 3974 passed, same 1 failure — the check total drifts; the failure SET does not).
- The one failure is STANDING on this base and predates the board plan: `[FAIL][BEHAVIOR] WALL
  FOCUS: pressing it again turned Info mode back OFF`. Fails 2 of 2 full runs; passes 1 of 1 run
  alone (`--filter WallFocus`, 130/130). Tally so far: 3 failures in 5 full runs, and every failing
  run had the other session's Godot up — window-focus interference is the likeliest cause; not
  fixed here. (Tally: 4 failures in 7 overseer full runs; 0 in the implementers' 6.) Unmodified `main` had no failure (sidebar's
  baseline).
- Exit-time: wrapper exit 3; `[exit-time] note: WARNING: 135 ObjectDB instances were leaked at
  exit` (pre-existing).
- SECTION 8 leaderboard captured from both baseline runs, identical: 104 rows, `SCORING: ALL 261
  CHECKS PASSED`. The TP-33 gate diffs every later run's SECTION 8 block against it.
- **Gate for every step:** suite count ≥ 45 (46 after BOARD PLAN, 47 after MARK MATCH), failure
  set exactly {that WALL FOCUS check} or empty, errors log otherwise empty, no new exit-time line.

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
  status: done
  evidence: 'see Baseline above: 45 suites, failure set = {WALL FOCUS Info-mode toggle}, SECTION 8 identical across 2 runs'
  notes: 'WALL FOCUS passes alone; interference from test-speed pacing, not ours'
- id: S1
  description: TypeGridCell.granted; BoardPlan.is_marked; called from validate() and is_spotlit().
  files_touched: [solatro/Cards/Types/type_grid_cell.gd, solatro/Scripts/board_plan.gd]
  verification_command: 'grep -c BoardPlan.is_marked solatro/Scripts/game_data.gd solatro/Cards/card_modifier.gd'
  verification_kind: suite
  status: done
  evidence: 'grep -c BoardPlan.is_marked: game_data.gd = 1, card_modifier.gd = 1 (via _is_mark(), asked by is_spotlit() and blocks_spotlight()).'
  notes: 'S1 spans dispatches 1 and 2'
- id: S2
  description: GameData.plan_seed; invariant I6; TP-16.
  files_touched: [solatro/Scripts/game_data.gd, solatro/Tests/Support/test_decks.gd, solatro/Tests/Engine/test_board_plan.gd, solatro/Tests/Engine/test_board_plan.tscn, solatro/Tests/all_tests.tscn]
  verification_command: 'APPDATA=<private> GODOT_BIN=<console exe> py solatro/Tools/run_tests.py --timeout 900'
  verification_kind: suite
  status: done
  evidence: 'Implementer red run (I6 append neutralised): BOARD PLAN 5 passed, 2 FAILED of 7, both TP-16 checks, per-check count 7 = green run. Overseer full run: ALL 46 SUITES: 4001 passed, 1 FAILED (the standing WALL FOCUS line only); BOARD PLAN: ALL 7 CHECKS PASSED; SECTION 8 identical to baseline. grep: "I6:" in game_data.gd = 1, var plan_seed = 1, var granted = 1, suite count 46.'
  notes: 'I6 lives in GameData._mark_violations() (extracted so no indented block comment); _modifier_script() helper, 4 call sites; plan_deck() builds its own 20 cards.'
- id: S3
  description: SkillBoardPlanner in rules1, localised; localisation gate clean.
  files_touched: [solatro/Cards/Skills/Rules/skill_board_planner.gd, solatro/Decks/deck.gd, solatro/Locale/localization.csv, solatro/Locale/localization.en.translation, solatro/Tests/Support/test_decks.gd, solatro/Tests/Engine/test_board_plan.gd]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red: planner out of both builders -> BOARD PLAN 20 passed, 3 FAILED of 23; CSV key renamed -> 22/23 (name came back as the bare key); planner out of _build_rules1 only -> E2E RUN mirror gate 34/35. Overseer full run: ALL 47 SUITES: 4030 CHECKS PASSED, errors log empty; BOARD PLAN 23/23; SECTION 8 identical. grep: class_name once, zero hooks declared, one planner in deck.gd, both CSV rows.'
  notes: 'on_game_start order = rules_deck array order, and creators build grids inside that walk (spotlight sweep after every mod), so the planner is LAST in rules1 and a BOARD PLAN check pins it after the allotment. get_frame() 13 and the description copy are logged assumptions. Legacy comment debt in deck.gd/test_decks.gd (27 findings) left in place: draining it deletes owner-facing playtest notes, an owner call.'
- id: S4
  description: BoardPlan.deal() per PLAN 1.2 from the planner's on_game_start; TP-01..TP-18 minus TP-05/06.
  files_touched: [solatro/Scripts/board_plan.gd, solatro/Cards/Skills/Rules/skill_board_planner.gd, solatro/Scripts/card_effect_api.gd, solatro/Scripts/pip_comparator.gd, solatro/Scripts/game_data.gd, solatro/Tests/Engine/test_board_plan.gd]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red runs (BOARD PLAN of 67): planner hook parked 62/4 FAILED (TP-01, TP-07); within-pass unused test removed 56/11 FAILED (TP-02, 03, 04, 09, 14, 15); RNG unseeded 65/1 (TP-07); Fisher-Yates swapped for Array.shuffle() 65/2 (TP-08, TP-07); add_grid deal removed 63/3 (TP-14, TP-04); save walker skipping cell types 64/2 (TP-17). Overseer full run: ALL 47 SUITES: 4067 CHECKS PASSED, errors log empty; BOARD PLAN 67/67; SECTION 8 identical; per-suite banners vs S3 differ only in BOARD PLAN (and BOARD FUZZ drift). grep: no global RNG call in board_plan.gd; BoardPlan.deal has exactly two call sites (planner on_game_start, CardEffectApi.add_grid); plan_seed written once.'
  notes: 'TP-01/TP-07 go through the real show start; TP-14 and half of TP-04 through the real add_grid. Re-derived by measurement (ASSUMPTIONS.md): TP-14 counts (ten identities at 3 copies, ten at 2, max 3), TP-09 measures repeat-cell spread, TP-08 has a mirror half. Pass boundaries count copies off the board (design "cycling"); identical for the opening deal. Two api accessors: board_state(), plan_seed_for_node() = hash(Vector2i(world_seed, current_node_id)) forced off 0, read from Main.save_info. Known property for the owner: the deal draws over the deck in its shuffled order, so "same node, same plan" holds while the deck order is the same (Q8 note anticipates this). TP-05/TP-06 still parked on GAP-001.'
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
  files_touched: [solatro/Cards/card_modifier.gd, solatro/Tests/Engine/test_mark_match.gd, solatro/Tests/Engine/test_mark_match.tscn, solatro/Tests/all_tests.tscn]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red runs: is_spotlit exclusion removed -> MARK MATCH 7 passed, 4 FAILED of 11 (all four TP-44 checks); blocks_spotlight forced true -> 8 passed, 3 FAILED of 11; exclusion below the StampGlobal return -> 11 passed, 4 FAILED of 15 (the four globally-stamped-mark checks). Overseer full runs: ALL 47 SUITES: 4032 passed, 1 FAILED (WALL FOCUS standing line) at e41fe969; ALL 47 SUITES: 4002 CHECKS PASSED, errors log empty, after the fix. SPOTLIGHT 111/111 both times; SECTION 8 identical. grep: is_spotlit()'s first statement is the mark check.'
  notes: 'Measured by the implementer: a grid card is never NATURALLY spotlit (_blocked_from_above reads position_of, which carries no grid coordinate), so TP-44 contrasts forced-spotlight pairs plus an unforced globally stamped mark; see ASSUMPTIONS.md.'
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
- the sidebar run’s own handoff, on branch `sidebar` only — the parallel run and its stock step S19
