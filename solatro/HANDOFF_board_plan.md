# HANDOFF — board plan (PLAN.md, every phase, S1–S17)

**Goal:** land `solatro/design/board-plan/PLAN.md` steps S1–S17 (every phase, closing included) on branch `board-plan`, one
verified step per commit. Owner ruling mid-run: do not stop at S10 — every phase is in scope.
**State:** 59 commits on `board-plan` (HEAD is this handoff commit). EVERY execution step is landed and
verified: S1-S16, the review-fix rounds (A-I), the six steps the owner's gap rulings opened
(S18-S23), and two playtest rulings (S24 the cascade reveal, S25 the standalone scene's 52-card
deck), one implementer, one full gate and one commit each; all six gaps are resolved with their
`resolution:` blocks and PLAN 1.10-bis carries every ruling verbatim. Tree clean. Last gate: ALL 48
SUITES: 4408 CHECKS PASSED, errors log empty, SECTION 8 byte-identical to the baseline captured
before S1. The owner has playtested the game view and approved the selection glow and the shimmer.
OPEN: S17 only - the closing sequence, in a NEW session at or above Opus 5 default effort (Next up
carries the prompt). Implementer sessions die to the Opus session limit every few hours; every
cut-off so far was resumed with SendMessage from the same transcript, never restarted.
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
  notes: 'The five knobs landed here because flat_bonus/mult_bonus need them (S14 keeps only plan_reveal_fraction (retired at S24)). PipComparator.modifier_script made public; CountingEnvironment moved to Tests/Support. A rank with no int value is value = NAN (is_finite); 2.5 built with PipRankNumeral.with_value. ARCHITECTURE_REVIEW §1.4 hook roster needs the on_mark_* entry at S16.'
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
  description: on_mark_covered / on_mark_hit count as activations (combo class, note_processing); TP-46..51, TP-53, TP-54. Landing-time dispatch landed at S19 (GAP-002).
  files_touched: [solatro/Scripts/card_environment.gd, solatro/Levels/game.gd, solatro/Tests/Engine/test_mark_match.gd, solatro/Tests/Support/test_grid_fixtures.gd]
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Score-time half at S9; landing-time dispatch at S19 (TP-86). Implementer red runs per row (filtered MARK MATCH, green 111): placed-card dispatch removed (TP-46), first-scoring-only (TP-49), note_processing uncharged -> loop ran to the recorder cap, no hang (TP-50), feeds_combo false (TP-51), plan_seed dropped from the undo snapshot (TP-53), RNG injected (TP-54); details in the S9 evidence file. Overseer full run: ALL 47 SUITES: 4144 CHECKS PASSED, errors log empty; MARK MATCH 111/111; COMBO 26/26; E2E RUN 35/35; exit-time leak count identical to baseline; SECTION 8 identical; per-suite banners vs the previous gate differ only in MARK MATCH. grep: no run_mark_mods/MARK_HIT in place_card_in_grid; no feeds_combo=false on the mark path.'
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
  description: the mark's look (owner ruling - a real card's colours, no rim); the reveal cell by cell in deal order (plan_reveal_fraction (retired at S24)); description names the mark; TP-60, TP-61, TP-62, TP-70; by eye TP-71, TP-74, TP-75.
  files_touched: [solatro/Cards/Types/type_grid_cell.gd, solatro/Cards/card_outline.gd, solatro/Cards/card_visual.gd, solatro/UI/play_area.gd, solatro/Levels/game.gd, solatro/Levels/game_view.gd, solatro/Scripts/board_plan.gd, solatro/Scripts/game_data.gd, solatro/Scripts/player_settings.gd, solatro/Locale/localization.csv, solatro/Tests/UI/test_plan_visuals.gd, solatro/Tests/Visual/plan_reveal_shot.gd, solatro/Tests/all_tests.tscn, solatro/Tests/Support/test_base.gd]
  verification_command: 'run_suite.sh <label>; render Tests/Visual/plan_reveal_shot.tscn and look'
  verification_kind: snapshot
  status: done
  evidence: 'Overseer full run: ALL 48 SUITES: 4236 passed, 1 FAILED (the standing WALL FOCUS line); PLAN VISUALS 30/30 (34/34 with TP-76, own commit); PIXELS 43/43; PALETTE 34/34; VISUAL LAYERS 221/221; SECTION 8 identical. By eye (overseer, 4x crop): a marked empty cell draws its art, rank pip and suit pip in full colour at full size inside the dashed ring with NO rim; a real card beside it is identical plus its dark rim and cream body (a played card frame); the unmarked cell is the bare ring. Pre-S11 crop confirms marks never had a cream body (the cell type frame is a hollow ring), so the only pixel change is the rim. TP-74 reveal measured over time by the sibling probe: 25 cells ~516 ms apart, 12.1 s total, in the walk order, not row-major. TP-75: no new palette entry; the palette-swap snapshot renders no board.'
  notes: 'Owner ruling superseded Q63 grey (PLAN 1.10). Mechanism: the outline TYPE override layer with width 0; a measured engine bug fixed on the way (CardOutline.material_of re-seeded u_outline_width after set_rim, so no per-type width override survived). The reveal lives in PlayArea.reveal_plan() via a GameView delegate; plan_reveal_order transient. ⚠ FOR THE OWNER: the 12.1 s opening (plan_reveal_fraction (retired at S24) 0.5 x get_delay) is the knob; and whether no rim alone reads as a mark at overview zoom.'
- id: S12
  description: the match highlight while holding a card, and the landing feedback; palette roles match_rim/match_rim_active; TP-63, TP-64, TP-65, TP-83; by eye TP-72, TP-73.
  files_touched: [solatro/UI/play_area.gd, solatro/Cards/card_visual.gd, solatro/Scripts/palette_roles.gd, solatro/Assets/Palette/roles.tres, solatro/Tests/UI/test_plan_visuals.gd, solatro/Tests/Support/test_input.gd, solatro/Tests/Support/test_game_view_host.gd, solatro/Tests/Interaction/test_interaction.gd, solatro/Tests/Visual/plan_match_shot.gd, solatro/Tests/Visual/plan_match_shot.tscn, solatro/Tests/Visual/plan_reveal_shot.gd]
  verification_command: 'run_suite.sh <label>; render Tests/Visual/plan_match_shot.tscn (OUT_DIR) and look'
  verification_kind: snapshot
  status: done
  evidence: 'Implementer red A (the refresh call deleted): PLAN VISUALS 57 passed, 6 FAILED of 63 (TP-63 x3, TP-64 x2, TP-83); red B (lights RANK|SUIT regardless of matches_at): 57/6 (TP-63 x2, TP-64 x2, TP-65 x2); green 63/63, equal counts. Overseer full run: ALL 48 SUITES: 4278 CHECKS PASSED, errors log empty; PLAN VISUALS 63/63, PALETTE 36/36 (+2 roles), PIXELS 43/43, INTERACTION 52/52; SECTION 8 identical. By eye (overseer, 4x crops of plan_match_shot): held, focused - the rank-only mark rims its rank pip cream and leaves the suit pip bare, the rank+suit mark rims both pips, the non-matching mark and every cell frame stay rimless; landed - the placed 8-of-Hoops wears gold rims on its rank and suit pips, the ordinary dark rim on its art and frame, with the focus brightening on the same cell and clearly distinct from it; overview - the cream pip rims stay legible at overview zoom. UNVERIFIED: the scoring-beam half of TP-72 (no beam held in the shot). Diff adds no modulate write, no colour literal, no design id.'
  notes: 'One derivation, PlayArea._refresh_mark_matches from set_card_zones_visuals; per-element rim through the STYLE layer (CardVisual._push_outline_ink pairs each polygon with its property), never modulate. GAP-004: no white in the palette, built against 31/6. TestInput extracted out of test_interaction.gd (shared driver); TestGameViewHost.boot_show shared by both shot scenes. Owner-visible: the covered-cell highlight is set on the data (a covered mark shows a sliver); a held STACK lights the union.'
- id: S13
  description: the layer view - two-state toggle, viewer only, focused and overview, held key + HUD control, ui_plan_layer; TP-66..TP-69; by eye TP-84.
  files_touched: [solatro/project.godot, solatro/UI/play_area.gd, solatro/Levels/game_view.gd, solatro/Levels/game_view.tscn, solatro/Locale/localization.csv, solatro/Locale/localization.en.translation, solatro/Tests/Support/test_input.gd, solatro/Tests/Support/test_game_view_host.gd, solatro/Tests/UI/test_plan_visuals.gd, solatro/Tests/Visual/plan_layer_shot.gd, solatro/Tests/Visual/plan_layer_shot.tscn, solatro/Tests/Visual/plan_match_shot.gd]
  verification_command: 'run_suite.sh <label>; render Tests/Visual/plan_layer_shot.tscn (OUT_DIR) and look'
  verification_kind: snapshot
  status: partial
  evidence: 'Implementer red runs, each at 98 checks: layer swap deleted -> PLAN VISUALS 96/2 (TP-67 x2); selection refusal removed -> 94/4 (TP-66 x4); both closes removed -> 96/2 (TP-69 x2); HUD toggle open-only -> 94/4 (TP-68 x4); green 98/98 then 99/99 with the localisation check. Overseer full run: ALL 48 SUITES: 4311 CHECKS PASSED, errors log empty; PLAN VISUALS 99/99; SECTION 8 identical; banners vs S12 differ only in fuzz drift and PLAN VISUALS 63 -> 99. designloop check on the worktree: 0 errors, 0 warnings. By eye (overseer, plan_layer_shot + 3x crop): focused, all 25 cells draw their marks in full colour inside the dashed frames with no played card visible, three realized cells wear gold rims on the agreeing pips only, the localised Marks button sits under Deck, the Entrance row is untouched; overview, two full grids of marks with the realized rim legible, the third grid past the right edge as in S12. Headless editor open clean. Diff removes three indented comments and adds none; no modulate write, no design id, no literal beyond 0.'
  notes: 'PARTIAL on GAP-005: every shoulder is bound (wall_back L1, wall_forward R1, grid_pan L2/R2; poker-patience Q187=(b) forbids taking the wall''s), so ui_plan_layer carries only the M key and the pad reaches the view through the HUD control (TP-68 covers it by focus + Accept). Mechanism: one flag PlayArea.plan_layer_open; the key is a peek (pressed opens, released closes), the HUD Button toggles; _select_data refuses selection while open, GameView asks _board_is_playable() before undo and end-show; queue_rebuild() and setup_gui() close it. The white border in both shots is the engine''s ScrollContainer focus panel, present in S12''s landed.png at the same pixels - pre-existing, shows in the shipped game after the first board click.'
- id: S14
  description: the knobs - confirm the five landed at S5 and plan_reveal_fraction (retired at S24) from S11 are declared once under "Balance - board plan" and read by production.
  files_touched: []
  verification_command: 'grep -c "var plan_" solatro/Scripts/player_settings.gd; grep -rl plan_<knob> solatro --include=*.gd'
  verification_kind: suite
  status: done
  evidence: 'grep: each of plan_rank_match_step, plan_rank_flat_fallback, plan_ace_value, plan_talent_mult, plan_hat_mult declared once in player_settings.gd and read by Scripts/mark_match.gd; plan_reveal_fraction (retired at S24) declared once and read by UI/play_area.gd; the group label "Balance - board plan" appears once. No code change; the S13 gate run (ALL 48 SUITES: 4311 CHECKS PASSED) is the run this tree was verified on.'
  notes: 'Nothing to add: PLAN 1.12 lists exactly these six.'
- id: S15
  description: the curve refit - scoring_sim.py models the deal, the match and the composition; scoring_parity.gd dumps marked boards; goal_g0/goal_alpha refit; GAP-041 closed by a poker-patience v3; TP-80..82.
  files_touched: [solatro/Tools/scoring_sim.py, solatro/Tools/scoring_parity.gd, solatro/design/board-plan/gaps/GAP-006.md]
  verification_command: 'Godot --path solatro res://Tools/scoring_parity.tscn (private APPDATA); py solatro/Tools/scoring_sim.py --parity <APPDATA>/Godot/app_userdata/Solatro/scoring_parity.json; py solatro/Tools/scoring_sim.py --grid-goals --trials 800 --q 0.25'
  verification_kind: suite
  status: partial
  evidence: 'TP-80 (overseer re-ran --parity on the implementer''s dump): PARITY: 1372 checks, 0 MISMATCHES - 1200 engine lines, 12 marked boards / 120 banked lines, 12 diagonal sums, 12 grid scores, 3 knobs; implementer red with the sim''s flats zeroed: 52 mismatches (35 banked lines, 6 diagonal sums, 9 grid scores, 2 knobs). TP-81/TP-82 MEASURED, not met: the ladder with marks (medians 44840 / 308083 / 76403 / 49550 / 36757 at N 20..40) still peaks at node 3 and ends at 0.10x; beatable fit goal(N) = 23400 * (N/20)^-0.32; win rates 13.0 / 11.8 / 8.5; constants left at 5376 / 0.26, no design version written; GAP-006 filed with the table. Overseer full run: see the S15 commit message. No Scripts/ file changed; SECTION 8 identical.'
  notes: 'The sim mirrors the three rank knobs (PLAN_RANK_MATCH_STEP etc.) and --parity asserts them against the engine dump, so the mirror is seam-checked. Models no hat (a sim card has no stamp) and no prop scoring (never did); parity boards are dealt from PipSuitTest so no props fire. run_suite.sh --scene does not run the parity scene (the wrapper wants a suite banner): run Godot directly with the private APPDATA. Under py 3.9.7.'
- id: S16
  description: the docs pass - ARCHITECTURE_REVIEW 1.4 hook roster, 2c, 3a, 3b, 3d, new 3e (the board plan), 4, 4b, 4i, 4j, 7; START_HERE; todo; HEADLESS_TESTING suite counts; the full doc_check.
  files_touched: [solatro/ARCHITECTURE_REVIEW.md, solatro/START_HERE.md, solatro/todo.md, solatro/HEADLESS_TESTING.md, solatro/design/board-plan/ASSUMPTIONS.md]
  verification_command: 'py .claude/tools/doc_check.py'
  verification_kind: manual
  status: done
  evidence: 'Full doc_check from the worktree root: 66 living docs + 318 source files checked - 0 error(s), 9 warning(s), identical to the pre-S16 tree and to main (0 errors, 9 warnings); --changed clean on all five files. No source file touched (git status). grep: the retired rule survives in ARCHITECTURE_REVIEW only as the sentence that retires it; suite counts corrected 45 -> 48 and the logic tier 32 -> 34 in START_HERE, HEADLESS_TESTING and ARCHITECTURE_REVIEW 7. One landmine row rewritten by the overseer from what material_of used to do into the rule.'
  notes: 'Not edited, scheduled with fix H: stale code comments stating the retired talent-suppression rule at Decks/deck.gd:8,116,150,219,255 and Tests/Support/test_decks.gd:18, and DESIGN_DOC.md:475 (the owner design record) which still states it. VFX.md untouched: no living doc enumerates board shot scenes, so the three plan_*_shot scenes are listed in 3e. Logic tier: BOARD PLAN and MARK MATCH are in it, PLAN VISUALS is not (windowed).'
- id: S22
  description: GAP-006 (a) - goal_alpha 0.0, goal_g0 refit to the beatable flat value by the sim; the goals-grow-with-boosters check reads a flat curve as non-decreasing; TP-90.
  files_touched: []
  verification_command: 'run_suite.sh <label>; py solatro/Tools/scoring_sim.py --grid-goals --trials 800 --q 0.25'
  verification_kind: suite
  status: done
  evidence: 'Implementer red (filtered RUN MANAGER + MAP ROLES, 61 checks both runs): goal_alpha back to 0.26 -> 1 FAILED (the flatness property, 18720 / 21651 / 25432); goal_alpha -0.32 -> 2 FAILED (never FALL, flatness); green 61/61. Overseer full run: ALL 48 SUITES: 4351 CHECKS PASSED, errors log empty, SECTION 8 identical; banners vs fix I differ only in fuzz drift and RUN MANAGER 39 -> 40. goal_g0 18720.0 from the tool''s new FLAT line (fit_power_beatable with alpha pinned to 0 = the ladder''s own minimum, node 12''s 25th percentile); goal_alpha 0.0. No test pins a goal number; test_map_roles'' post-booster ladder check re-derived to strict only when the curve grows.'
  notes: 'A placeholder; GAP-041 stays open in poker-patience, no v3. Known: the baker''s monotone clamp masks a falling curve on the baked ladder, so only the run-manager check can see the sign. Stale: solatro/HANDOFF_phase9_goal_curve.md still quotes 5376 / 0.26 in three places - queued for the close''s docs pass.'
- id: S21
  description: GAP-005 - ui_plan_layer gains the X face button (button_index 2) held to peek; TP-89 through the viewport.
  files_touched: []
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red with the joypad event removed from project.godot: PLAN VISUALS 126 passed, 2 FAILED of 128 (X opens the layer; every marked cell draws its mark); green 128/128 at equal counts; TP-68''s 13 rows green both runs. Overseer full run: see the commit. project.godot diff is one insertion; button_index 2 was bound to nothing before (census: 0 ui_accept, 1 ui_cancel, 3 wall_info, 4 wall_overview, 9 wall_back, 10 wall_forward). No .gd production change: PlayArea asks the action, never a keycode. Headless editor open clean.'
  notes: 'The peek is M or X, both held; the HUD Marks button toggles by mouse, touch, keyboard and controller Accept.'
- id: S18
  description: GAP-001 (b1) - BoardPlan.stocks_of(state) splits draw_deck round-robin by the sidebar rule (earlier slots take the extras, no RNG); deal() reads it; TP-05, TP-06 unparked, TP-85. Deleted when the sidebar stocks land.
  files_touched: []
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red (BOARD PLAN, 111 checks all runs): stocks_of returning one stock -> 5 FAILED (TP-85 sizes [23] and order, TP-05 identity precondition and counts [25], TP-06 [26]); a contiguous-chunk split -> 2 FAILED (TP-85 every-fifth-card order, TP-05 per-stock identities); green 111/111. Overseer full run: ALL 48 SUITES: 4349 CHECKS PASSED, errors log empty, SECTION 8 identical; banners vs S21 differ only in fuzz drift and BOARD PLAN 104 -> 111. Slot count read from the state''s Entrance zone (upper_zone.size(), floored at 1 for the engine fixtures with no Entrance); no RNG in the partition (TP-08 green); a real show''s deal changes identity for the same seed because it now offers five stocks, TP-07 determinism green.'
  notes: 'A taken identity now leaves EVERY stock''s offer (PLAN 1.2 ''every card in every stock, still unmarked''), which the 105-card three-grid gate needed once there was more than one stock. TP-85 uses slice(0, 23): TEST_PLAN''s slice(23) is 29 cards in Godot. Deleted when the sidebar''s per-slot stocks land.'
- id: S20
  description: GAP-003 - CardEffectApi.reroll_line(section) and reroll_grid(grid): every cell, covered included, through Board.deal_marks; TP-88.
  files_touched: []
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red (BOARD PLAN, 124 checks all runs): the per-cell walk stopping after the first cell -> 3 FAILED (row, live match, diagonal); a bump per cell -> 3 FAILED (row 10->15, diagonal 0->5, grid 0->25); green 124/124. Overseer full run: see the commit. Offer at the first reroll of the covered row: 4 identities.'
  notes: 'All three rerolls share CardEffectApi._redraw_marks (Board.redraw_mark per cell, one bump after the batch). ScoringSection gained line_cells (a diagonal does not reduce to index + height), written by both grid constructors; LineGeometry.col_cells public; the two card collectors share _cards_on_cells. Only test callers today, by design.'
- id: S19
  description: GAP-002 - the two act hooks also fire at LANDING from place_card_in_grid (the parked S9 half); a mark mult is the query on_mark_line_mult summed into M during composition; add_line_mult retired; TP-86, TP-87; TP-32/TP-50 doubles moved onto the query. S9 becomes done.
  files_touched: []
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red (MARK MATCH, 146 checks all runs): landing dispatch removed -> 7 FAILED, all TP-86 (0 covers / 0 hits on the matching, plain and effect-placed landings, levels -1, no card recipient, no class, no processing); the query not asked -> 4 FAILED (TP-87 x4 and TP-32''s three doubles, M stays 0); green 146/146. Overseer full run: ALL 48 SUITES: 4404 CHECKS PASSED, errors log empty, SECTION 8 identical; banners vs S20 differ only in fuzz drift and MARK MATCH 133 -> 146. add_line_mult and line_mult_bonus: 0 occurrences repo-wide. TP-46..51, TP-53, TP-54, TP-79, TP-32 counts unchanged before/after.'
  notes: 'Landing dispatch: Game._run_mark_landing after the card settles and before _broadcast_board_mutation (inside the act, so undo and the replay cover it). Query: CardEnvironment.run_mark_query (charges nothing, feeds_act_combo false), summed into a LOCAL accumulator in _compose_line_score - no sentinel, no save/restore. S9 is done with this. Marks acting on neighbouring cells: a content shape the query serves, not built.'
- id: S23
  description: GAP-004 - the activated rim SHIMMERS - a new outline alert kind interpolating (blended, owner exception to 4i) through a ramp of palette entries over a fraction of get_delay(); TP-91 measured over time; /fx-verify.
  files_touched: []
  verification_command: 'run_suite.sh <label>; render plan_match_shot and a movement probe'
  verification_kind: snapshot
  status: done
  evidence: 'Implementer red: blend replaced by a sample -> OUTLINE 38 passed, 2 FAILED of 40 (midpoints not the blend; a midpoint equals the resting ink); the wiring removed from _alert_of -> PLAN VISUALS 130/1 of 131 (exactly the activated elements run the shimmer: drew 0 of 3); green 40/40 and 131/131 at equal counts. Overseer full run: ALL 48 SUITES: 4388 CHECKS PASSED, errors log empty, SECTION 8 identical; banners vs S19 differ only in fuzz drift, banner order, PALETTE 36 -> 39, OUTLINE 37 -> 40, PLAN VISUALS 128 -> 131. Movement (plan_match_shot print): the rank-pip rim pixel over one 2.00 s loop shows 8 distinct colours (#f6c720 .. #58dadf .. #f7c510, out and back to gold), the control pixel on an unmatched mark 1 colour; 79 pixels of the pip box moved over a quarter loop, 0 of the control box. By eye (overseer, compare_s23.png at 5x): phase 0 gold rims on the landed 8-of-Hoops rank and suit pips, half a loop later the same two pips cyan, art, frame and neighbouring marks identical. Headless editor open clean.'
  notes: 'CardOutline.Alert.SHIMMER, built by CardAlert.shimmer(), applied per element in CardVisual._alert_of to the elements wearing match_rim_active and nothing else; blends between consecutive entries of Assets/Palette/ramp_match.tres (6, 31, 3, 15, 12, 9; gold first so phase 0 IS the flat activated ink) - the one BLENDED ramp, owner-ruled, stated at the shader; OutlineStyle.shimmer_period_fraction 2.0 of get_delay(). One new uniform (the ramp strip); phase reuses u_alert_clock. fx_cost not measured: the branch is uniform-gated and reached only by activated-rim fragments.'
- id: S24
  description: playtest ruling - the opening reveal is a cascade over get_delay() x plan_reveal_multiplier (1.0, replaces plan_reveal_fraction (retired at S24)); cells start total/N apart on one Tween and their spins overlap; TP-92.
  files_touched: [solatro/UI/play_area.gd, solatro/Scripts/player_settings.gd, solatro/Tests/UI/test_plan_visuals.gd, solatro/Tests/Visual/plan_reveal_shot.gd]
  verification_command: 'run_suite.sh <label>; render Tests/Visual/plan_reveal_shot.tscn and read its timing print'
  verification_kind: snapshot
  status: done
  evidence: 'Implementer red (PLAN VISUALS, 139 checks all runs): the loop awaiting each spin -> 5 FAILED (dealt every cell after 15.0 s, start drift 12.7 s, last start 14.7 s of 2.0 s, 0 of 25 overlaps, total 15.0 s vs 2.68 s budget); the multiplier ignored -> 3 FAILED (start times, TP-70a cell-by-cell, TP-76 precondition); green 139/139. Overseer full run: see the S24 commit. Timing (shipped get_delay 1.00 s): stagger 40 ms by design, the shot printed 21 cells ~36 ms apart, 0.71 s first start to last, reveal done after 0.74 s wall clock, against S11 12.1 s; consecutive starts advance 16-50 ms with up to 25 spins in flight.'
  notes: 'anim_spin is handed the full get_delay() (its spin length is derived from it); a spin whose visual a rebuild frees dies with its tween. The first cell lands the frame after reveal_plan() is scheduled. TP-70a and TP-76 re-fixtured at OBSERVABLE_REVEAL_MULTIPLIER 10.0 because the whole cascade is shorter than two frames at suite pacing. DESIGN.md is untouched (the implementer edited its tunable row; reverted - the design is the frozen v1 authority and PLAN 1.12 carries the retirement).'
- id: S25
  description: owner request - the standalone GameView scene (game_view.tscn run directly) boots with the standard 52-card deck instead of deck14, for playtesting; the run's start deck and the goal-curve fixtures untouched.
  files_touched: []
  verification_command: 'run_suite.sh <label>'
  verification_kind: suite
  status: done
  evidence: 'Implementer red with get_deck() pointed back at deck14: GAME HEADLESS 73 passed, 2 FAILED of 75 (52 cards; 4 suits x 13 ranks once); green 75/75. Overseer full run: see the S25 commit. Deck.get_deck() readers unchanged (game.gd add_deck''s blank-save fallback, leak_sentinel); a real run fills Main.save_info.card_datas from RunManager.new_run and never reaches it; the run deck check reads TestDecks.deck_20().size() (20).'
  notes: 'get_deck() returns the shipped deck4 (the full standard 52). No .tscn touched: game_view.gd''s standalone boot builds Game with the default Deck.new(). Verified through the production accessor in a test, not by an F6 boot.'
- id: S17
  description: the closing sequence of /plan-run, every numbered item recorded. Hand to a NEW session at or above Opus 5 default effort (the READY FOR CLOSING block is in the last overseer message and in Next up).
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
- FIXED (fix E, TP-77): the mark exclusion lives only in run_all_mods; the comparator dispatches,
  active_implementers, return_first_data_array_result, has_card_data and skill_spotlight_check still
  walk cell_types, so a mark copying a modifier with a leniency or placement hook would answer
  board-wide and has_card_data would report a mark as on the board. Now one walk,
  `CardEnvironment._dispatch_mods`, drops a marked cell's COPIED modifiers (the cell's own type stays:
  `on_can_place_stack` rides the same walk); `has_card_data` is false for a mark. Recorded, no
  producer: a copied skill arriving with `spotlit == true` would fire `on_unspotlight` once in
  `skill_spotlight_check` (needs a draw-deck card with StampGlobal and an `on_unspotlight` skill; none exists).
- FIXED (fix F, TP-78): _pip_same refuses an absent pip before the deny/allow hooks are asked, which
  closes the leniency shape pre-authorised row 9 requires (PipComparator asks the hooks first). Ask
  the hooks first; require both present only for printed_same; flat_bonus treats a null rank as the
  no-integer-value case so a leniency-rescued rankless card pays the fallback.
- FIXED (fix G, TP-79): the widened combo window ("a line is composing", read off the accumulator) also
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

## Phase 5-6 adversarial review (Opus 5, read-only, 70425565..13267a24)
Findings and their disposition; each defect is reproduced red before it is fixed:
- FIXED (fix H, TP-63 two-grid case): the held-card highlight lights marks in grids the placement will refuse -
  `_refresh_mark_matches` walks every grid while `place_card_in_grid` refuses any grid but
  `state.committed_grid` (and `try_place` still returns true, so the card drops back). Q66=(a)
  "every cell it would match": a cell the show cannot reach is not one. Rule adopted: the highlight
  walks only the committed grid once one is committed. TP-63 gains a two-grid case.
- FIXED (fix I, TP-67 inspection check): in the marks layer only the CardVisual is hidden; focus and inspection on a
  covered cell still target the hidden played card (`card_info(ui_data[focused_control])`), and the
  focus brighten lands on an invisible visual. PLAN 1.10 "a covered mark is available on inspection,
  and through the layer view". Rule adopted: while the layer is open, a covered cell's focus and
  inspection target its mark. TP-67 gains an inspection check.
- DISMISSED (no producer): `game_state.grids[gi]` read without a null guard in the highlight walk -
  `pop_at` renumbers, nothing produces a null entry; hard rule 7 forbids the guard.
- RECORDED in todo.md (no producer today): a card an effect moves off a marked cell keeps its last
  activated rims until the next rebuild; the M-key peek closes only on release, so focus loss while
  held may leave the layer open until the next press or mutation; the debug undo/redo bar is not
  gated by `_board_is_playable()`.
- CORRECTED (ASSUMPTIONS S15/TP-80): the parity's engine deal is not a fewest-copies deal, because
  `PipSuitTest.id` is a plain var `duplicate_deep` drops (every dumped mark prints suit 0); the
  0-mismatch parity is unaffected because the sim scores the marks the engine dumped. What parity
  proves: the RANK flat from `place_card_in_grid` through `_compose_line_score` to `grid_score` on
  12 boards x 12 lines including the Ace path; not SUIT, TALENT, HAT, any M != 0, the NAN fallback,
  stacked cells, the mark hooks, or the sim's own deal.
- PLAN DRIFT noted: private helpers added during execution (`CardEnvironment._dispatch_mods`,
  `PlayArea._wear_match_rim`, `CardVisual._rim_of` / `_match_style` / `_match_styles`,
  `TypeGridCell._marked` / `_mark_outline`) are not in NAMES.md; the public names all match.
- Verified clean by the reviewer: fix E's single walk and every legality/prop/spotlight path; fix
  G's eight `_note_mod_fired` call sites; fix F's uncached pass order; the reveal's remaining
  `CURRENT` reads are on paths the reveal never calls; the S12 derivation from every route and the
  Entrance never walked; S13's one flag, both closes, the two gated commands, nothing saved.

## Bloat review of the reveal fix and fixes E-G (Opus 5, read-only, 70425565..5b153b62)
- QUEUED for the close's simplify pass: `MarkMatch._pip_same` computes two `pip_cache_key`s that
  `ask_pass` never reads under `memoise = false`. Not a defect; one suite run is not worth it alone.
- DISMISSED: "`anim_spin(delay)`'s parameter carries nothing the callee could not read" - TP-76
  reproduces exactly the case the reviewer could not find (an environment leaving the tree mid-reveal
  nulls `CardEnvironment.CURRENT`); the parameter is load-bearing and its red run proves it.
- DISMISSED: "`flat_bonus`'s `not card.rank` has only a test caller" - the producing caller is the
  leniency hook family PLAN 1.4 mandates as a content surface; TP-78 is that caller until content
  ships one.

## Queued for the close (S17)
- /docs: `solatro/HANDOFF_phase9_goal_curve.md` quotes the retired 5376 / 0.26 in three places; the
  curve is now the S22 placeholder (18720 / 0).
- /simplify: `MarkMatch._pip_same` computes two `pip_cache_key`s that `ask_pass` never reads under
  `memoise = false` (bloat review).
- /simplify: the residual 8-line dup_check pair between `plan_match_shot.gd` and `plan_layer_shot.gd`
  (`_ready`'s four locals), and the `test_plan_visuals.gd:437` / `test_ui_props.gd:1135` GameView
  teardown pair (a repo-wide shape at ~30 sites).
- /fx-verify: the scoring-beam half of TP-72 is UNVERIFIED (no shot holds a beam on a realized cell).
- Tool fidelity, not a defect: `PipSuitTest.id` is dropped by `duplicate_deep`, so the parity's
  engine deal is not a fewest-copies deal and every dumped mark prints suit 0 (ASSUMPTIONS S15).

## Verified vs assumed
- Import cache: verified — second `--import` pass printed no error line.
- Stocks absent on `main` and `sidebar`: verified — `git grep -il stock` empty on both.

## Open bugs
- FIXED (TP-76): the reveal's `get_delay` on Nil. `CardVisual.anim_spin` re-read the global
  `CardEnvironment.CURRENT` between awaited cells, and any screen leaving the tree clears it; the
  spin now takes the delay `PlayArea.reveal_plan` already resolved. Red: 24 engine errors with the
  fix parked; green: PLAN VISUALS 34/34, full gate `ALL 48 SUITES: 4233 CHECKS PASSED`.
- Pre-existing, found during S7, not ours: a sprung grid card (`CardVisual.anim_spring_lift`) is
  never reset, so it keeps `floating = false` until the next rebuild; surfaces in
  `Cards/card_visual.gd`.
- FIXED (owner report, "in tests with 3 grids i only see it filling in 1 grid"): the mid-show deal
  lives in `Board.add_grid`; `CardEffectApi.add_grid` no longer deals.
- For the owner's eye: the board window's focus border (the engine's `ScrollContainer` focus
  panel) shows after the first board click, in either layer - pre-existing, visible in every
  by-eye shot that clicked the board.
- For the owner's eye: the 12.1 s opening reveal (`plan_reveal_fraction (retired at S24)` 0.5 x `get_delay`) and
  whether "no rim" alone reads as a mark at overview zoom. `PipRankNumeral.get_str()` prints
  "NumeralRank5.0" in the mark's description (pre-existing wart).

## Files touched
- solatro/design/board-plan/gaps/GAP-001.md, ASSUMPTIONS.md (new); PLAN.md §3 S1 row and NAMES.md
  `BoardPlan` row corrected to agree.

## Next up
S18-S25 are landed. S17: open a NEW session at or above Opus 5 default effort and paste:

    Run the closing phase of /plan-run for the branch board-plan in ../gamedev-boardplan
    (sibling of the main checkout). The code was implemented by Opus 5 (plan-implementer)
    at default effort. You are the reviewer, and you must be at or above that: same
    generation or newer, same effort or higher. A weaker reviewer on stronger code is net
    negative, not merely useless. Start by reading .claude/skills/plan-run/SKILL.md "The
    reviewer's model floor" and then "Closing the run", and work its numbered list in order.
    Read solatro/HANDOFF_board_plan.md first: "How this run operates" (the private-APPDATA
    suite script, the standing interference lines) and "Queued for the close".

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
