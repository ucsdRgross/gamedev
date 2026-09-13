# HANDOFF — board plan (PLAN.md, every phase, S1–S17)

**Goal:** land `solatro/design/board-plan/PLAN.md` steps S1–S17 (every phase, closing included) on branch `board-plan`, one
verified step per commit. Owner ruling mid-run: do not stop at S10 — every phase is in scope.
**State:** 30 commits on `board-plan` (HEAD 772dad91). Phases 1-4 (S1-S10) and S11 landed and
verified, one commit per step, plus three Phase 1-3 review fixes (A-C), the owner's three-grid bug
fix, and Phase 4 review fix D. Tree clean. OPEN: one intermittent engine error from S11's reveal
(see Open bugs; the next thing to fix), three queued Phase 4 review fixes (E, F, G under Next up),
then S12 (the match highlight, under the owner's white-outline ruling), S13, S14, S15, S16, S17.
Three gaps open for the owner: GAP-001 (stocks are sidebar S19; TP-05/06 parked), GAP-002 (mark
hook timing versus the mult seam; the landing-time dispatch parked; S9 partial), GAP-003 (re-deal
a line unnamed). Owner rulings mid-run are in PLAN 1.10 (marks keep a real card's colours and only
lose their outline; a matching mark takes a WHITE outline while a card is selected; marks keep the
zone type art). Implementer sessions die to the Opus session limit every few hours; every cut-off
so far was resumed with SendMessage from the same transcript, never restarted.
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
  status: partial
  evidence: 'Score-time half DONE; landing-time dispatch PARKED on GAP-002. Implementer red runs per row (filtered MARK MATCH, green 111): placed-card dispatch removed (TP-46), first-scoring-only (TP-49), note_processing uncharged -> loop ran to the recorder cap, no hang (TP-50), feeds_combo false (TP-51), plan_seed dropped from the undo snapshot (TP-53), RNG injected (TP-54); details in the S9 evidence file. Overseer full run: ALL 47 SUITES: 4144 CHECKS PASSED, errors log empty; MARK MATCH 111/111; COMBO 26/26; E2E RUN 35/35; exit-time leak count identical to baseline; SECTION 8 identical; per-suite banners vs the previous gate differ only in MARK MATCH. grep: no run_mark_mods/MARK_HIT in place_card_in_grid; no feeds_combo=false on the mark path.'
  notes: 'Measured pre-existing bug, fixed mark-scoped: Game._note_mod_fired gated combo registration on _act_cancellable, set only inside _perform_next, so no modifier activation ever fed the combo in the grid game; the window is now "an act is resolving OR a line is composing". Composition is re-entrant (save/restore of line_mult_bonus) because TP-50 makes the nested api.score_line producible. board_digest now witnesses marks, plan_seed, combo set and total_score, so the E2E parity and save-reload rows assert them too. The placed card''s on_mark_hit moved to run_mark_mods (run_card_mods is the prop tick''s non-charging path).'
- id: S10
  description: mark_at, reroll_mark, grant_mark, swap_marks on CardEffectApi; TP-52.
  files_touched: [solatro/Scripts/card_effect_api.gd, solatro/Scripts/board.gd, solatro/Tests/Engine/test_board_plan.gd]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red runs (BOARD PLAN of 101): reroll drawing draw_deck[0] instead of the deal -> the fewest-copies check red; swap without relink -> the backref check red; grant with granted false -> the flag check and I6 red. Overseer full run: ALL 47 SUITES: 4193 CHECKS PASSED, errors log empty; BOARD PLAN 101/101; SECTION 8 identical; per-suite banners vs S9 differ only in BOARD PLAN. grep: four api functions with the registry signatures; BoardPlan.deal still has two call sites; Board.deal_marks shared by the late grid and the reroll; no global RNG.'
  notes: 'A content surface with NO shipped caller yet (by design). The three writers bump revision once each. QR5 follow-ups never asked: a reroll or swap MAY touch an occupied cell (logged assumption). grant_mark writes over an existing mark without a prior clear (write_mark assigns every slot).'
- id: S11
  description: the mark's look (owner ruling - a real card's colours, no rim); the reveal cell by cell in deal order (plan_reveal_fraction); description names the mark; TP-60, TP-61, TP-62, TP-70; by eye TP-71, TP-74, TP-75.
  files_touched: [solatro/Cards/Types/type_grid_cell.gd, solatro/Cards/card_outline.gd, solatro/Cards/card_visual.gd, solatro/UI/play_area.gd, solatro/Levels/game.gd, solatro/Levels/game_view.gd, solatro/Scripts/board_plan.gd, solatro/Scripts/game_data.gd, solatro/Scripts/player_settings.gd, solatro/Locale/localization.csv, solatro/Tests/UI/test_plan_visuals.gd, solatro/Tests/Visual/plan_reveal_shot.gd, solatro/Tests/all_tests.tscn, solatro/Tests/Support/test_base.gd]
  verification_command: 'run_suite.sh <label>; render Tests/Visual/plan_reveal_shot.tscn and look'
  verification_kind: snapshot
  status: done
  evidence: 'Overseer full run: ALL 48 SUITES: 4236 passed, 1 FAILED (the standing WALL FOCUS line); PLAN VISUALS 30/30; PIXELS 43/43; PALETTE 34/34; VISUAL LAYERS 221/221; SECTION 8 identical. By eye (overseer, 4x crop): a marked empty cell draws its art, rank pip and suit pip in full colour at full size inside the dashed ring with NO rim; a real card beside it is identical plus its dark rim and cream body (a played card frame); the unmarked cell is the bare ring. Pre-S11 crop confirms marks never had a cream body (the cell type frame is a hollow ring), so the only pixel change is the rim. TP-74 reveal measured over time by the sibling probe: 25 cells ~516 ms apart, 12.1 s total, in the walk order, not row-major. TP-75: no new palette entry; the palette-swap snapshot renders no board.'
  notes: 'Owner ruling superseded Q63 grey (PLAN 1.10). Mechanism: the outline TYPE override layer with width 0; a measured engine bug fixed on the way (CardOutline.material_of re-seeded u_outline_width after set_rim, so no per-type width override survived). The reveal lives in PlayArea.reveal_plan() via a GameView delegate; plan_reveal_order transient. ⚠ FOR THE OWNER: the 12.1 s opening (plan_reveal_fraction 0.5 x get_delay) is the knob; and whether no rim alone reads as a mark at overview zoom.'
- id: S12
  description: the match highlight while holding a card, and the landing feedback; palette roles match_rim/match_rim_active; TP-63, TP-64, TP-65; by eye TP-72, TP-73.
  files_touched: []
  verification_command: 'run_suite.sh <label>; then /fx-verify by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: ''
- id: S13
  description: the layer view - two-state toggle, viewer only, focused and overview, held shoulder button + HUD control, ui_plan_layer; TP-66..TP-69.
  files_touched: []
  verification_command: 'run_suite.sh <label>; then /fx-verify by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: ''
- id: S14
  description: the knobs - confirm the five landed at S5 and add plan_reveal_fraction (S11).
  files_touched: []
  verification_command: 'grep -c plan_ solatro/Scripts/player_settings.gd'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
- id: S15
  description: the curve refit - scoring_sim.py models marks and matches; goal_g0/goal_alpha refit; GAP-041 closed by a new poker-patience design version; TP-80..82.
  files_touched: []
  verification_command: 'Tools/scoring_parity.gd --parity'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: ''
- id: S16
  description: the docs pass - ARCHITECTURE_REVIEW 3a/3d/4 and 1.4 hook roster, START_HERE, todo; doc_check full.
  files_touched: []
  verification_command: 'py .claude/tools/doc_check.py'
  verification_kind: manual
  status: pending
  evidence: ''
  notes: ''
- id: S17
  description: the closing sequence of /plan-run, every numbered item recorded.
  files_touched: []
  verification_command: 'see /plan-run Closing the run'
  verification_kind: manual
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

## Phase 4 adversarial review (Opus 5, default effort, read-only, committed range 7c7ae65a..2a207cf3)
Findings and their disposition; each defect is reproduced red before it is fixed:
- FIX (own commit, the reroll surface): reroll_mark clears the cell and re-runs the deal, whose
  fewest-copies rule then offers the very identity it just cleared (the sole lowest), so a reroll
  returns the same face most of the time on a 20-card board; and with an empty draw pile (or a
  plan_seed 0 board) the clear happens and nothing is dealt, deleting the mark. Rule adopted: the
  offer excludes the identity being replaced, and the cell is cleared only once a card is in hand.
  The three writers assert the cell exists (mark_at may return null).
- FIX (own commit): the mark exclusion lives only in run_all_mods; the comparator dispatches,
  active_implementers, return_first_data_array_result, has_card_data and skill_spotlight_check still
  walk cell_types, so a mark copying a modifier with a leniency or placement hook would answer
  board-wide and has_card_data would report a mark as on the board. Exclude marked cell cards at the
  dispatch walker, once.
- FIX (own commit): _pip_same refuses an absent pip before the deny/allow hooks are asked, which
  closes the leniency shape pre-authorised row 9 requires (PipComparator asks the hooks first). Ask
  the hooks first; require both present only for printed_same; flat_bonus treats a null rank as the
  no-integer-value case so a leniency-rescued rankless card pays the fallback.
- FIX (own commit): the widened combo window ("a line is composing", read off the accumulator) also
  admits every broadcast inside a NESTED composition (a mark effect re-scoring a line), so
  on_score / on_after_score of any board card would feed the combo there and nowhere else. Pass the
  mark-hook activation explicitly instead of inferring it from the accumulator.
- RECORDED, no producer today: spawn_props now awaits the comparator dispatch, so a coroutine
  leniency hook could interleave two suits' spawner construction; add_line_mult off a composition
  drops the mult silently in release (GAP-002 decides its lifetime).
- GAP-003 filed: "re-deal a line" (QR5=(c)'s third capability) has no signature in NAMES.md and no
  test row; both derived docs dropped it.
- S9 is PARTIAL, not done: the score-time dispatch, combo class and processing charge landed; the
  landing-time dispatch from place_card_in_grid is parked on GAP-002. The ledger says so now.
- Verified clean by the reviewer: the suit gate (one seam, five subclasses, no talent term); the
  re-entrant accumulator at any depth; flat_bonus/mult_bonus paths; is_spotlit/blocks_spotlight
  after the ordering fix; write_mark/clear_mark; swap_marks' relink; Board.add_grid -> deal_marks
  ordering (a grid added during the opening walk is dealt exactly once, by the planner); I6's
  printer filter; TP-53's digest witnesses; TP-54 through the real replay; the counts_as_activation
  split keeps every question-asking path out of the combo; NAMES.md identifiers all match.

## Verified vs assumed
- Import cache: verified — second `--import` pass printed no error line.
- Stocks absent on `main` and `sidebar`: verified — `git grep -il stock` empty on both.

## Open bugs
- OPEN, fix first: S11's reveal, intermittent (1 in 3 full runs since S11): `SCRIPT ERROR: Invalid
  call. Nonexistent function 'get_delay' in base 'Nil'. at: CardVisual.anim_spin
  (res://Cards/card_visual.gd:839), from reveal_plan (res://UI/play_area.gd:1720)`, logged while
  "EFFECTS FOLLOW THEIR HOST'S MODULATE" and the wall-editor tool's TP-120 checks ran: a PlayArea
  hosted WITHOUT a Game reached the reveal with a non-empty pending list. Reproduce by finding the
  no-Game host (the wall editor tool, test_fx_attachment, the placeholder-content path) whose state
  carries a plan; fix at one seam (pacing through the accessor a hosted board already resolves, or
  no reveal where nothing dealt); a PLAN VISUALS check red on the current code (the engine error is
  the red); full gate.
- Pre-existing, found during S7, not ours: a sprung grid card (`CardVisual.anim_spring_lift`) is
  never reset, so it keeps `floating = false` until the next rebuild; surfaces in
  `Cards/card_visual.gd`.
- FIXED (owner report, "in tests with 3 grids i only see it filling in 1 grid"): the mid-show deal
  lives in `Board.add_grid`; `CardEffectApi.add_grid` no longer deals.
- For the owner's eye: the 12.1 s opening reveal (`plan_reveal_fraction` 0.5 x `get_delay`) and
  whether "no rim" alone reads as a mark at overview zoom. `PipRankNumeral.get_str()` prints
  "NumeralRank5.0" in the mark's description (pre-existing wart).

## Files touched
- solatro/design/board-plan/gaps/GAP-001.md, ASSUMPTIONS.md (new); PLAN.md §3 S1 row and NAMES.md
  `BoardPlan` row corrected to agree.

## Next up
1. Fix the reveal's null-game engine error (Open bugs, first item). One commit, full gate.
2. Phase 4 review fix E: the mark exclusion lives only in `run_all_mods`; `_compare_implementers`,
   `active_implementers`, `return_first_data_array_result`, `has_card_data` and
   `skill_spotlight_check` still walk `cell_types`. Exclude a marked cell's zone card at the
   dispatch walker once (never in `all_card_datas`, which relinking needs). Test: a mark copying a
   modifier with a leniency / placement hook answers no comparator dispatch; `has_card_data` is
   false for a mark. Red-then-green, full gate, one commit.
3. Fix F: `MarkMatch._pip_same` refuses an absent pip BEFORE the deny/allow hooks (PLAN 4 row 9
   says mirror `PipComparator`, which asks the hooks first). Ask the hooks first, require both
   present only for `printed_same`; `flat_bonus` treats a null rank as the no-integer-value case so
   a leniency-rescued rankless card pays the fallback. Test: an `on_mark_ranks_allow` test modifier
   rescues a rankless card. One commit.
4. Fix G: the widened combo window in `Game._note_mod_fired` ("an act is resolving OR a line is
   composing", read off `line_mult_bonus`) also admits every broadcast inside a NESTED composition.
   Pass the mark-hook activation explicitly (the `counts_as_activation` split already exists in
   `_run_own_mods`) instead of inferring it from the accumulator. Test: a mark effect that
   re-scores a line while a board card implements `on_after_score` with a combo key registers only
   the mark's class. One commit.
5. S12: the match highlight and landing feedback. Owner ruling (PLAN 1.10): at rest a mark has no
   outline; while a card is picked up, a mark it matches takes a WHITE outline, read with Q67/Q68
   (each matching ELEMENT lights its own outline) so the white lands on the matching elements.
   `match_rim` (white) and `match_rim_active` palette roles per NAMES.md; landing feedback per Q64
   (the realized card's art takes a special outline, pips swap to an activated outline; no popup);
   a miss is silent (Q65=(a)); no Entrance destination (Q70). TP-63, TP-64, TP-65; by eye TP-72,
   TP-73 (`/fx-verify`, PNGs looked at and described). Files per PLAN 3 S12.
6. S13: the layer view (Q113=(b) two states, Q115=(a) viewer, Q116=(b) focused and overview,
   Q117=(c) held shoulder button AND a HUD control, `ui_plan_layer` action, closes on any board
   mutation, off after a restored save). TP-66..TP-69. The sidebar branch is rebuilding the HUD in
   parallel: keep the HUD control minimal and behind `GameView`, expect a merge.
7. S14: confirm the five knobs from S5 plus `plan_reveal_fraction` from S11 are all read; nothing
   else to add.
8. S15: the curve refit (`Tools/scoring_sim.py`, `goal_g0` / `goal_alpha`, TP-80..TP-82; close
   GAP-041 through a NEW poker-patience design version, never an in-place edit).
8b. The comment sweep of the files this run touched (list in "Run rules in force"), one
    dispatch, no behaviour change, full gate; keep every rule and measured number, drop the story.
9. S16: the docs pass (ARCHITECTURE_REVIEW 3a composition, 3d, 4 the retired suppression and the
   new suit rule, 1.4 hook roster gains `on_mark_*`; START_HERE; todo; the full
   `py .claude/tools/doc_check.py` clean).
10. S17: hand to a NEW session at or above Opus 5 default effort for the closing sequence
    (`/plan-run` "Closing the run"), with the READY FOR CLOSING block.

## How this run operates (read before dispatching)
- Overseer never reads source; verifies by bounded grep, its own full suite run, the SECTION 8
  byte-diff against a captured baseline (re-capture it from a main-only run if the scratchpad is
  gone: SECTION 8 of SCORING is the 104-row leaderboard block), and by eye for visual steps.
- Every dispatch is a `plan-implementer` brief quoting the step, the rulings VERBATIM, the test
  rows, the call site, the comment and complexity rules, the run script, and the standing
  interference lines. Implementers run the suite through a script that exports a private
  `APPDATA` (Godot on Windows reads its data dir from it) so the parallel sidebar session's runs
  do not collide; recreate it from "Run rules in force" if the scratchpad is gone.
- One implementer at a time (the lock is shared with the other session through the main
  checkout's project dir). A cut-off implementer is resumed with SendMessage; check
  `git status --porcelain` first and tell it what the tree holds.
- ⚠ OWNER RULING (reaffirmed after S11): A FILE AN IMPLEMENTER EDITS LEAVES COMPLIANT WITH THE
  COMMENT RULES, THE WHOLE FILE. This run's briefs from S4 onward wrongly told implementers that
  legacy findings on untouched lines were deferred (a line from an older sidebar handoff); that
  deferral is superseded. Every brief from here on says "sweep the file"; the sidebar branch does.
  Debt this run left in files it touched (doc_check --verbose counts): game.gd 349, play_area.gd
  642, card_visual.gd 211, game_data.gd 108, pip_comparator.gd 59, card_environment.gd 55,
  player_settings.gd 50, board.gd 44, card_outline.gd 33, deck.gd 26, pip_suit.gd 8,
  card_effect_api.gd 9, test_decks.gd 7. A sweep dispatch for those files (one commit, full gate,
  no behaviour change, reviewer floor applies because a sweep can delete a load-bearing note - it
  did once at S8) is owed before S16. The owner plans a full pass over every untouched file
  separately (todo.md, Doc hygiene backlog).
- Commit after every verified step with the evidence in the message; revert the effect-review
  import noise first (`git checkout -- solatro/design/effect-review` then
  `git clean -fq -- solatro/design/effect-review/`).
- The standing interference lines (WALL FOCUS Info-mode toggle; a GRID VIEW pan-right real-key
  check) fail 1 run in about 3 when the other session's windowed Godot is up and pass alone; a run
  whose only failure is one of them meets the gate. Any engine error is red.

## References
- `.claude/skills/plan-run/SKILL.md`, `.claude/skills/handoff/SKILL.md`
- the sidebar run’s own handoff, on branch `sidebar` only — the parallel run and its stock step S19
