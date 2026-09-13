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
  fixed here. (Tally: WALL FOCUS 4 failures in 12 overseer full runs; a GRID VIEW pan-right real-key-press check failed 1 in 12, same shape, passed on immediate re-run with no code change.) Unmodified `main` had no failure (sidebar's
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
  description: MarkMatch.matches_at, flat_bonus, mult_bonus; leniency hook comments; TP-20..27, TP-35, TP-39.
  files_touched: [solatro/Scripts/mark_match.gd, solatro/Scripts/pip_comparator.gd, solatro/Scripts/player_settings.gd, solatro/Cards/card_modifier.gd, solatro/Tests/Engine/test_mark_match.gd, solatro/Tests/Engine/test_comparator.gd, solatro/Tests/Support/counting_environment.gd]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red runs (MARK MATCH of 49): always RANK|SUIT -> 8 FAILED; script identity loosened -> 2 FAILED (TP-21, TP-22); result cached on revision -> 3 FAILED (TP-23, TP-39); routed through the MELD hooks -> 2 FAILED (TP-39 dispatch count caught the fallback); ceiling/ace dropped -> 3 FAILED (TP-35). Overseer full run: ALL 47 SUITES: 4078 CHECKS PASSED, errors log empty; MARK MATCH 49/49, COMPARATOR 154/154; SECTION 8 identical; banner diff vs S4 only MARK MATCH (+ fuzz drift). grep: enum, four MARK_* constants, four hooks as comments and zero as methods, five knobs under "Balance — board plan", no literal in the bonus functions, no production caller yet (S6/S9 own them).'
  notes: 'The five knobs landed here because flat_bonus/mult_bonus need them (S14 keeps only plan_reveal_fraction). PipComparator.modifier_script made public; CountingEnvironment moved to Tests/Support. A rank with no int value is value = NAN (is_finite); 2.5 built with PipRankNumeral.with_value. ARCHITECTURE_REVIEW §1.4 hook roster needs the on_mark_* entry at S16.'
- id: S6
  description: (hand + flats) x M in score_line; TP-30..38; SECTION 8 leaderboard byte-identical.
  files_touched: [solatro/Levels/game.gd, solatro/Scripts/card_effect_api.gd, solatro/Scripts/card_environment.gd, solatro/Scripts/game_data.gd, solatro/Scripts/mark_match.gd, solatro/Tests/Engine/test_mark_match.gd, solatro/Tests/E2E/test_e2e_run.gd]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red runs (MARK MATCH of 72): flats dropped 7 FAILED (TP-30/31/34/37/38); M==0 multiplies unconditionally 19 FAILED (TP-31 banks 0); 1+sum 3 FAILED (TP-32: 18/30/42 vs 12/24/36); product 1 FAILED; gathered from section.cards 1 FAILED (TP-36); combo class registered 1 FAILED (TP-38); exclusive cover dispatch 2 FAILED of 75 (both-hooks and level checks). Overseer full runs: ALL 47 SUITES: 4115 passed, 1 FAILED (GRID VIEW pan-right real-key-press, interference-shaped) then ALL 47 SUITES: 4115 CHECKS PASSED, errors log empty; MARK MATCH 75/75; SCORING 261/261, LEADERBOARD 104 rows; SECTION 8 byte-identical to baseline (TP-33); scoring.gd identical to main (git diff main -- scoring.gd empty).'
  notes: 'Composition is Game._compose_line_score, one call from score_line. Mark hooks dispatched at score time through CardEnvironment.run_mark_mods (the never-spotlit gate lifted for the mark''s own copied modifiers); on_mark_covered fires on EVERY cover (Q46=(d)/Q51=(a) words), on_mark_hit additionally on a match, levels 0/1. add_line_mult is the mark-effect mult seam (NAMES.md, assumption). int() truncation of line*M; is_zero_approx skip. E2E parity fixture pins world_seed (the deal follows it). TP-30 fixture re-derived to a pair of sevens (a 7 outside the meld pays nothing by TP-36).'
- id: S7
  description: suit effect fires iff SUIT matched; talent suppression retired; TP-40..43.
  files_touched: [solatro/Cards/Pips/pip_suit.gd, solatro/Cards/Pips/Suits/pip_suit_hoop.gd, solatro/Cards/Pips/Suits/pip_suit_knife.gd, solatro/Cards/Pips/Suits/pip_suit_ball.gd, solatro/Cards/Pips/Suits/pip_suit_fire.gd, solatro/Cards/Pips/Suits/pip_suit_firework.gd, solatro/Levels/game.gd, solatro/Tests/Engine/test_suit_props.gd, solatro/Tests/Engine/test_mark_match.gd, solatro/Tests/Engine/test_game_headless.gd, solatro/Tests/UI/test_ui_props.gd]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red runs: gate forced always-true -> TP-40 red (spawners=1); talent suppression restored on top of the gate -> TP-41/TP-42 red (talented=0 control=4) with TP-40 green; fire once per placement -> TP-43 red; marks removed from fixtures -> SUIT PROPS 5 passed / 11 FAILED (every re-derived check named in the S7 report); UI PROPS 12 failures red then green after fixtures moved onto marked cells. Overseer full run: ALL 47 SUITES: 4131 CHECKS PASSED, errors log empty; SUIT PROPS 16/16, MARK MATCH 78/78, UI PROPS 133/133; SECTION 8 identical. grep: gate is one seam (PipSuit._spawn_origin), one spawn_props call site, prop_score_talents.gd unchanged.'
  notes: 'spawn_props became a coroutine (matches_at is one); _run_score_effects only awaits it. An Entrance card can no longer fire a suit effect (no marks there; no detected line runs through the Entrance row). test_talented_suit_suppressed retired in favour of TP-40/41/42. ARCHITECTURE_REVIEW.md 4 still states the old rule: S16 rewrites it.'
- id: S8
  description: is_spotlit/blocks_spotlight false for a mark; TP-44, TP-45.
  files_touched: [solatro/Cards/card_modifier.gd, solatro/Tests/Engine/test_mark_match.gd, solatro/Tests/Engine/test_mark_match.tscn, solatro/Tests/all_tests.tscn]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red runs: is_spotlit exclusion removed -> MARK MATCH 7 passed, 4 FAILED of 11 (all four TP-44 checks); blocks_spotlight forced true -> 8 passed, 3 FAILED of 11; exclusion below the StampGlobal return -> 11 passed, 4 FAILED of 15 (the four globally-stamped-mark checks). Overseer full runs: ALL 47 SUITES: 4032 passed, 1 FAILED (WALL FOCUS standing line) at e41fe969; ALL 47 SUITES: 4002 CHECKS PASSED, errors log empty, after the fix. SPOTLIGHT 111/111 both times; SECTION 8 identical. grep: is_spotlit()'s first statement is the mark check.'
  notes: 'Measured by the implementer: a grid card is never NATURALLY spotlit (_blocked_from_above reads position_of, which carries no grid coordinate), so TP-44 contrasts forced-spotlight pairs plus an unforced globally stamped mark; see ASSUMPTIONS.md.'
- id: S9
  description: on_mark_covered / on_mark_hit count as activations (combo class, note_processing); TP-46..51, TP-53, TP-54. Landing-time dispatch PARKED on GAP-002.
  files_touched: [solatro/Scripts/card_environment.gd, solatro/Levels/game.gd, solatro/Tests/Engine/test_mark_match.gd, solatro/Tests/Support/test_grid_fixtures.gd]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red runs per row (filtered MARK MATCH, green 111): placed-card dispatch removed (TP-46), first-scoring-only (TP-49), note_processing uncharged -> loop ran to the recorder cap, no hang (TP-50), feeds_combo false (TP-51), plan_seed dropped from the undo snapshot (TP-53), RNG injected (TP-54); details in the S9 evidence file. Overseer full run: ALL 47 SUITES: 4144 CHECKS PASSED, errors log empty; MARK MATCH 111/111; COMBO 26/26; E2E RUN 35/35; exit-time leak count identical to baseline; SECTION 8 identical; per-suite banners vs the previous gate differ only in MARK MATCH. grep: no run_mark_mods/MARK_HIT in place_card_in_grid; no feeds_combo=false on the mark path.'
  notes: 'Measured pre-existing bug, fixed mark-scoped: Game._note_mod_fired gated combo registration on _act_cancellable, set only inside _perform_next, so no modifier activation ever fed the combo in the grid game; the window is now "an act is resolving OR a line is composing". Composition is re-entrant (save/restore of line_mult_bonus) because TP-50 makes the nested api.score_line producible. board_digest now witnesses marks, plan_seed, combo set and total_score, so the E2E parity and save-reload rows assert them too. The placed card''s on_mark_hit moved to run_mark_mods (run_card_mods is the prop tick''s non-charging path).'
- id: S10
  description: mark_at, reroll_mark, grant_mark, swap_marks on CardEffectApi; TP-52.
  files_touched: []
  verification_command: 'GODOT_BIN=<console exe> py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
```

## Phase 1-3 adversarial review (Opus 5, default effort, read-only, committed tree at 7c7ae65a)
Findings and their disposition; each defect was reproduced red before it was fixed (fix A d9a97ce7, fix B 7cda6467, fix C the commit after it):
- FIXED: run_all_mods gates only the skill slot on is_spotlit(), so a mark's copied
  STAMP (StampDoubleTrigger ships in five deck rows) answers on_after_score / on_trigger and
  charges note_processing. Q59 says never. TP-44 gains a stamp case.
- FIXED: matches_at lets two EMPTY rank (or suit) slots agree (printed_same on
  null == null), so a rankless card on a suit-only mark sets RANK and flat_bonus dereferences
  rank.value. RANK/SUIT need both slots present, as TALENT/HAT already do.
- FIXED (the reviewer's suspicion reproduced red): _mark_violations hand-rolls its printer walk and omits lower_zone; reuse
  all_card_datas() filtered to playing cards.
- FIXED (test strength): run_mark_mods's skill-slot dispatch has no failing case (both
  test doubles are stamps); BOARD PLAN's start_show replicates _start_fresh_show instead of
  using it; the blocks_spotlight note naming poker-patience PLAN 1.4 as wrong was deleted in the
  card_modifier.gd comment sweep and must come back.
- DONE at S9: a mark firing registers a combo class and charges note_processing (TP-50, TP-51).
- GAP-002 filed: the landing-time dispatch S9 owes collides with add_line_mult's composing-only
  precondition; the cover/hit reading is recorded in the same gap for the owner.
- FIXED at S9 (TP-50 made it producible): a nested api.score_line from inside a mark hook cleared
  the outer accumulator; the composition is re-entrant now. RECORDED: add_grid re-seeds from
  plan_seed (deterministic, logged).
- GAP-001 gains a note: the mid-show pool shrinks with the draw pile.
- Verified clean by the reviewer: scoring.gd byte-identical to main; unmarked boards score as
  today; the composition is on the only banking path; no global RNG on the deal; save/resume
  carries marks; no design ids in code; anti-scope respected.

## Verified vs assumed
- Import cache: verified — second `--import` pass printed no error line.
- Stocks absent on `main` and `sidebar`: verified — `git grep -il stock` empty on both.

## Open bugs
- FIXED (owner report, "in tests with 3 grids i only see it filling in 1 grid"): grids added through `Board.add_grid`, the mutator every non-api path uses (the UI fixtures' `_stand_up_grids`, the visual probes), were never dealt; the mid-show deal now lives in `Board.add_grid` and `CardEffectApi.add_grid` no longer deals. Reproduced `[25, 0, 0]` red, `[25, 25, 25]` green, and by eye on `Tests/Visual/grid_layer_shot.tscn` (grid 1 bare dashed outlines before, mark art in every cell after). A real three-grid show start (deck_105) was never affected.
- Until S11 lands, a mark renders as a full-colour card face indistinguishable from a played card: the zone card already draws under the stack. Phase 5 owns the grey treatment.
- Pre-existing, found during S7, not ours: a sprung grid card (`CardVisual.anim_spring_lift`) is never reset, so it keeps `floating = false` until the next rebuild. Details in the S7 evidence file of this session; surfaces in `Cards/card_visual.gd`.

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
