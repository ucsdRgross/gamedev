# HANDOFF — poker patience, Phases 1-4 and 8

**Goal:** Implement `design/poker-patience/PLAN.md` steps S1–S19 (Phases 1–4) and S35–S37
(Phase 8), stopping at S37. Phases 5–7 (visual), 9 and 10 are out of scope for this run.
**State:** **Phases 1 and 2 complete; Phase 3 in progress** — **S1-S18 landed and committed**, suite green at 42 suites.
Next is S19, the biggest remaining piece: the owner's GAP-007 answer turned it from an
archive move into a REBUILD of six suites onto the grid game. Worktree `gamedev-poker-patience`
on branch `poker-patience`; one commit per verified step.
**Entry docs:** `design/poker-patience/PLAN.md` (normative §1), `DESIGN.md` (authority on
behaviour), `TEST_PLAN.md` (every test that must exist), `NAMES.md` (every identifier),
`START_HERE.md`, `HEADLESS_TESTING.md`.

## Design provenance and gap protocol

Derived from `design/poker-patience/DESIGN.md` version 2, charts confirmed 2026-08-25.
On a decision the design does not cover: reversible and clearly within intent → do it and
append one line to `ASSUMPTIONS.md`; otherwise park the thread, file a gap at
`design/poker-patience/gaps/GAP-NNN.md`, keep working unaffected threads, tell the owner.
A design/code contradiction is always a gap. Two documents disagreeing is NOT automatically
a gap — read the answer they are both restating. Do not resolve a gap by picking an answer.

## Environment

- The Godot binary on this box is **4.7.2**, not the 4.7.1 that
  `.claude/memory/machine-profiles.md` records. That memory is stale; `run_tests.py` fails
  with `FileNotFoundError` on the recorded path.
- Suite: `GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py` from the repo root.
  Runs WINDOWED, ~90 s, self-quits with the failure count.
- A fresh worktree needs `--headless --path . --import` run TWICE before the suite will
  pass (the first pass reports parse errors against autoloads not yet registered).
- ⚠ **A new `class_name` referenced from an existing script hangs the suite until you
  reimport.** This cost a long bisection during S5. The symptom is NOT a parse error: the
  run reaches `test_interaction`, `game.state` is Nil, and
  `test_game_over_interactivity`'s `while game.submits_used < Game.MAX_SUBMITS` loop
  spins forever spraying *"Invalid access to property 'submits_used' on a base object of
  type 'Nil'"* until the wrapper's timeout kills it. `--timeout 240` makes that fail fast.
  Repo rule 11 already says to reimport; this records what ignoring it looks like.

## Baseline

```
======== ALL 39 SUITES: 3134 CHECKS PASSED [23 placeholder warnings] ========
```

## Tasks

```yaml
- id: S0-repair
  description: >
    Strip the five ShaderMaterials the editor baked into Cards/card_visual.tscn during the
    last Phase 0 commit. Suit and Art captured u_frame_uv = (0,0,1,1) - no frame clamp.
    material_of() re-seeds palette/num_colors/outline_width on every call but never
    u_frame_uv, so a baked material short-circuits construction and keeps the bad value.
  files_touched: [solatro/Cards/card_visual.tscn]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    Before: ALL 39 SUITES: 3138 passed, 2 FAILED (0 behavior, 2 implementation)
      [FAIL][IMPLEMENTATION] OUTLINE: card_visual.tscn assigns no saved ShaderMaterial
      [FAIL][IMPLEMENTATION] OUTLINE: card_visual.tscn defines no ShaderMaterial sub-resource
    After:  ALL 39 SUITES: 3134 CHECKS PASSED
    grep -c ShaderMaterial Cards/card_visual.tscn  ->  0  (was 10)
    By-eye: Tests/Visual/reveal_shot.tscn 02_open_full.png rendered and looked at - every
    card's art is crisply frame-clamped (blue triangles, green crosses, black +1) and the
    pip row reads at the card bottom.
  notes: >
    This is the trap the run brief named. It was already committed on main at 69eee09, so
    the claim that Phase 0 landed green was wrong - TP-137 was red before this run began.
    Committed as b416d37 on the branch; drop that commit to handle it separately.

- id: S1
  description: >
    BoardCoord: the four-component coordinate (grid, x, y, h), NOWHERE sentinel,
    ENTRANCE_ROW = -1, step_x(n) crossing grid boundaries, is_entrance().
  files_touched:
    [solatro/Scripts/board_coord.gd, solatro/Tests/Engine/test_grid_board.gd,
     solatro/Tests/Engine/test_grid_board.tscn, solatro/Tests/all_tests.tscn]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 40 SUITES: 3166 CHECKS PASSED ========
    ============ GRID BOARD: ALL 17 CHECKS PASSED ============
    All four planned rows covered, plus TP-02's literal -5 fixture and both
    off-board clamp cases. Red-then-green proven three ways, expected checks only:
      continuity  -> "one column left of (grid 1, x 0) is (grid 0, x 4)"
      is_entrance -> the three ENTRANCE checks
      NOWHERE     -> both OFF BOARD sentinel checks
    Committed bf61cd9.
  notes: >
    REVISED after the owner answered GAP-001 and GAP-002 (commit fea5768). step_x(n) is
    replaced by step(dx, dy, grid_widths): movement is two-axis over an UNBOUNDED lattice
    of per-grid bounding blocks laid end to end, never clamping and never returning
    NOWHERE. Past the last grid it continues as if another grid were there, in y as well
    as x. Landing is a separate question - GameData.has_cell(coord) - and a landing on
    nothing discards. The provisional clamp and its two checks are gone.

- id: S2
  description: >
    GameData grid storage: GridData, the grid list, per-grid cell arrays, 25 cell zone
    cards per grid.
  files_touched:
    [solatro/Scripts/grid_data.gd, solatro/Scripts/game_data.gd,
     solatro/Cards/Types/type_grid_cell.gd, solatro/Tests/Support/test_grid_fixtures.gd,
     solatro/Tests/Engine/test_grid_board.gd, solatro/Locale/localization.csv]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 40 SUITES: 3149 CHECKS PASSED ========
    ============ GRID BOARD: ALL 31 CHECKS PASSED ============
    Hard gate: "validate() returns empty on FIX-MIXED-H" passes (3 grids, row 1 at
    heights 6 / 1 / empty).
    Red-then-green run by the overseer, expected checks and ONLY those:
      drop `all.append_array(grid.cell_types)` from all_card_datas()
        -> [FAIL] grid 0's cell zone card appears in all_card_datas()
        -> [FAIL] grid 2's last cell zone card appears in all_card_datas()
      drop the cell duplicate report from validate()
        -> [FAIL] validate() reports the duplicate card -- got []
        -> [FAIL] the report names BOTH cell locations
    Committed 6e4c6e3.
  notes: >
    validate() and all_card_datas() extended IN PLACE, not shadowed. TypeGridCell uses
    the registry-claimed frame 13; both strings go through TRANSLATION.find. The suite's
    75 duplicated per-cell checks were collapsed to one aggregate check per grid that
    names the offending cell indices.

- id: S3
  description: 'Position index and _scan_positions() extended to grids, plus the reverse index.'
  files_touched: [solatro/Scripts/game_data.gd, solatro/Tests/Engine/test_grid_board.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 40 SUITES: 3159 CHECKS PASSED ========
    TP-08 and TP-09 green; TP-09 exercises place, move and removal.
    Red: keying the reverse index one height too high fails 7 checks including
    validate()'s I4 seam check, which names both sides per card. Committed 6eb9722.
  notes: >
    Done-when: TP-08, TP-09 green. The reverse index is a second representation of one fact -
    it needs a stated invariant tying it to the forward index, and validate() must check it.

- id: S4
  description: 'Board mutation API for grid cells: place, move, remove-with-compaction.'
  files_touched: [solatro/Scripts/board.gd, solatro/Tests/Support/test_grid_fixtures.gd,
     solatro/Tests/Engine/test_grid_board.gd, solatro/design/poker-patience/ASSUMPTIONS.md]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 40 SUITES: 3210 CHECKS PASSED ========
    TP-10..TP-14 green. Exactly one `state.revision += 1` per mutation function.
    Red, expected checks only:
      bump per compacted card -> [FAIL] one revision bump covers the whole compaction
      drop the caller's flag  -> [FAIL] a caller-declared compaction move carries
                                        is_compaction == true
    Committed 7684258.
  notes: >
    Done-when: TP-10..TP-14 green. is_compaction is set BY THE MOVER, never inferred from
    before/after heights. A compaction bumps revision ONCE for the whole compaction.

- id: S5
  description: 'CardDataIterator and get_card_collections() for grids; the early stop REMOVED.'
  files_touched: [solatro/Scripts/card_data_iterator.gd, solatro/Scripts/grid_cell_walk.gd,
     solatro/Scripts/game_data.gd, solatro/Levels/game.gd,
     solatro/Tests/Engine/test_iterator.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 40 SUITES: 3231 CHECKS PASSED ========
    TP-15..TP-17 green in the ITERATOR suite; TP-17 asserts the exact expected
    sequence on a sparse grid with cards only in row 3.
    Red (THE PHASE-1 GATE): giving the grid walk an early stop at the first empty
    cell fails TP-17 (25 cards, all zone cards) and TP-15 (77 of 112).
    Committed 3b98a54.
  notes: >
    Done-when: TP-15..TP-17 green. TP-17 is the gate - a SPARSE grid, cards only in row 3,
    must be walked completely. Neutralise by restoring the early stop and watch it fail.

- id: S6
  description: 'Line enumeration: ROW, COL, DIAG, HEIGHT_V through a given cell, within one grid.'
  files_touched: [solatro/Scripts/line_geometry.gd, solatro/Scripts/scoring_section.gd,
     solatro/Tests/Engine/test_line_detect.gd, solatro/Tests/Support/test_grid_fixtures.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 40 SUITES: 3221 CHECKS PASSED ========
    TP-18..TP-24 green, plus a HEIGHT_V enumeration check beyond the planned rows
    (the kind shipped otherwise unexercised until S11).
    DIAG is 10 directions: 2 flat corner-to-corner + 4 axis climbs + 4 corner-to-corner
    3-D climbs. Reverse duplicates omitted - a line and its reverse are one line.
    Red, expected checks only:
      drop the 4 corner-to-corner climbs (the option the owner did NOT take)
        -> [FAIL] eight climbing 3-D diagonals are found ... got 4
        -> [FAIL] the found directions are literally the eight from the full family
      stop rejecting off-main diagonals
        -> [FAIL] a cell off both main diagonals finds no broken/wrapped diagonal
    Committed a06a8c3.
  notes: 'Done-when: TP-18..TP-24 green.'

- id: S7
  description: 'ScoringSection gains kind and line_key; score_line loses is_row/zone/index.'
  files_touched: [solatro/Levels/game.gd, solatro/Scripts/scoring_section.gd,
     solatro/Cards/Skills/Rules/skill_eval_poker_best.gd,
     solatro/Tests/Engine/test_line_detect.gd, solatro/Tests/all_tests.tscn]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 41 SUITES: 3248 CHECKS PASSED ========
    TP-25..TP-27 green. TP-26 is a real grep gate: walks every .gd file, counts
    top-level args per score_line call, names file:line of any four-arg one, and
    exempts only itself.
    Red, expected checks only:
      reintroduce one old-signature call -> gate names skill_eval_poker_best.gd:30,
        and 74 other checks fail with it (the change is load-bearing, not cosmetic)
      refresh() stops re-reading into cards -> the 3 TP-27 checks fail, plus 3
        pre-existing SPOTLIGHT checks that depend on the same re-read
    Committed 1bffdec.
  notes: 'Done-when: TP-25..TP-27 green; grep proves no caller passes the old signature.'

- id: S8
  description: 'The mutation broadcast, the compaction flag, and the board lock.'
  files_touched: [solatro/Levels/game.gd, solatro/Scripts/board.gd,
     solatro/Tests/Engine/test_line_detect.gd, solatro/Tests/Support/test_grid_fixtures.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    41 suites, only the known VISUAL LAYERS intermittent failing.
    TP-28..TP-31 green. TP-30 and TP-31 assert from INSIDE the handler (processing
    read true there; the placed card readable off the board there).
    Red, expected checks only:
      fire the pass before the placement commits -> [FAIL] the handler read the
        placed card off the board WHILE handling on_board_mutated
      drop the mover's flag in the broadcast -> [FAIL] the broadcast carries
        is_compaction == true, exactly what the mover passed
    Committed 93c3687.
  notes: 'Done-when: TP-28..TP-31 green.'

- id: S9
  description: 'The detector card: enumerate, score, re-scan until nothing new completes.'
  files_touched: [solatro/Cards/Skills/Rules/skill_line_detector.gd, solatro/Levels/game.gd,
     solatro/Scripts/scoring_section.gd, solatro/Locale/localization.csv,
     solatro/Tests/Engine/test_line_detect.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 41 SUITES: 3278 CHECKS PASSED ========
    TP-32..TP-36 green. TP-34 asserts the SEQUENCE (every ROW before every COL,
    every COL before every DIAG), not just membership.
    Red, expected checks only:
      reverse the scored-kind order -> both ordering checks fail
      add a line-scored memory (the FORBIDDEN thing)
        -> [FAIL] a completed line scored again on every cycle - there is no line
                  memory -- 1 scorings over 29 cycles
    Committed 0dc6dbd.
  notes: >
    Done-when: TP-32..TP-36 green. The runaway guard (act_event_cap, MAX_TICKS) is
    CORRECTNESS-critical - there is no line-scored memory and no within-pass guard, so a
    remove-and-replace effect re-scores forever without it. Do not tune it away. TP-36 must
    assert it re-scores each cycle AND that the guard is what stops it.

- id: S10
  description: 'Wire the section into Scoring.PokerHands.score() and the spotlight cascade, unchanged.'
  files_touched: [solatro/Cards/Skills/Rules/skill_line_detector.gd,
     solatro/Tests/Engine/test_line_detect.gd, solatro/Tests/Support/test_grid_fixtures.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 41 SUITES: 3306 CHECKS PASSED ========
    TP-37..TP-39 green. score_line ALREADY re-evaluates the section through
    PokerHands.score() after the cascade, so the detector passes no result of its own
    on purpose; the call site now says why.
    ⚠ TP-39 was passing VACUOUSLY as first written - it compared state.total_score,
    which is always 0 until S12, against a non-zero hand. Now reads the banked amount.
    Red (only meaningful after that fix): evaluate the hand BEFORE the cascade
      -> [FAIL] the banked hand is the RE-EVALUATED one, not the pre-swap five cards
    Committed 54a2bb5.
  notes: 'Done-when: TP-37..TP-39 green.'

- id: S11
  description: 'Height scoring: multiples of 5, whole stack, drops never score.'
  files_touched: [solatro/Scripts/line_geometry.gd, solatro/Cards/Skills/Rules/skill_line_detector.gd,
     solatro/Levels/game.gd, solatro/Scripts/game_data.gd,
     solatro/Tests/Engine/test_line_detect.gd, solatro/Tests/Support/test_grid_fixtures.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 41 SUITES: 3373 passed ======== (only the known intermittent failing)
    TP-40..TP-46 green. TP-46 runs at ceilings 3, 5 and 15 and compares SETS both ways.
    Red, with counts matching the test's own enumerator independently:
      stop scoring HEIGHT_V -> 25 missing at ceiling 5, 75 at ceiling 15
      score EVERY height    -> 75 / 100 / 300 unexpected at ceilings 3 / 5 / 15
    Committed a146980 (part 1) and 8029ffe (part 2, the gate).
  notes: >
    Done-when: TP-40..TP-46 green. TP-46 is the phase gate: build FIX-FULL-15 card by card,
    compare the completed-line SET against an enumerator written INDEPENDENTLY in the test,
    never the code under test. Build at height 3 and 5 ceilings first.

- id: S12
  description: 'The three buckets per grid and their storage, pack/unpack, duplicate_state() copy.'
  files_touched: [solatro/Scripts/game_data.gd, solatro/Scripts/scoring_section.gd,
     solatro/Levels/game.gd, solatro/Levels/game_view.gd, solatro/UI/play_area.gd,
     solatro/Tests/Engine/test_grid_economy.gd, solatro/Tests/all_tests.tscn]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 42 SUITES ======== (only the known intermittent failing)
    TP-47..TP-50 green in the new Phase 3 suite, which carries its own registration gate.
    Red: sharing the raised 2-D containers instead of hand-copying them fails TP-50 at
    1040 / 1050 -- the copy followed the original.
    Two defects found: buckets seeded at ONE (BigNumber.new() is 1, not 0) which would
    have made every unscored bucket read as scored to S13's product rule; and the legacy
    scores_col collided with the registry name, so it is renamed scores_col_legacy until
    S19b removes it.
    Committed 3a384d2.
  notes: 'Done-when: TP-47..TP-50 green.'

- id: S13
  description: 'grid_score as the product of positive buckets; board_total as their sum.'
  files_touched: [solatro/Scripts/game_data.gd, solatro/Tests/Engine/test_grid_economy.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 42 SUITES: 3392 CHECKS PASSED ========
    TP-51..TP-56 green. TP-51 walks the worked example STEP BY STEP (0, 10, 50, 100),
    which matters: under multiply-by-everything the final 100 still passes because by
    then all three terms are non-zero - only the intermediate steps catch it.
    Red, both readings the owner ruled against:
      multiply by every term including zero -> 9 checks fail
      include a term by TOUCHED-NESS not value -> 7 fail, incl. "a bucket worth 0 is
        excluded from the product even though its line scored -- got 0, wanted 10 * 5"
    Committed 54cab17.
  notes: >
    Done-when: TP-51..TP-56 green. TP-51 reproduces the owner's worked example exactly:
    0+0+0 then 10 then 50 then 100. TP-54: a bucket whose VALUE is 0 is excluded from the
    product even when its line completed - the test is the VALUE, never touched-ness.

- id: S14
  description: >
    The combo model, and the retirement of MAX_SUBMITS, submits_used, score_additive,
    duplicate_class_scale and the patience family.
  files_touched: [solatro/Levels/game.gd, solatro/Scripts/game_data.gd, solatro/Scripts/run_state.gd,
     solatro/Scripts/run_manager.gd, solatro/Scripts/player_settings.gd,
     solatro/UI/control_card.gd, solatro/Scripts/card_environment.gd,
     solatro/Locale/localization.csv, and seven test suites]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 41 SUITES: 3332 CHECKS PASSED ======== (patience suite deleted: 42 -> 41)
    Landed in three commits, suite green between each:
      c72b7f4 S14a  combo model; score_additive and duplicate_class_scale retired
      49b3eb9 S14b  the patience family retired, including the (seen)/(new) marker
      ea03db7 S14c  MAX_SUBMITS/submits_used retired; end_show() replaces the act count
    TP-57..TP-61 green. TP-60 walks every .gd/.tscn for all nine retired identifiers.
    Red: re-declaring submits_used fails the gate (naming game_data.gd:47) AND TP-61.
    ⚠ end_show() bumps revision on purpose - ending is undoable but not a board mutation,
    and save_state() only commits when revision moved, so without it undo had nothing to
    rewind to. Found by TP-61, not by inspection.
  notes: >
    Done-when: TP-57..TP-61 green; grep proves each retired identifier has zero readers.
    submits_used lives on GameData specifically so undo rewinds it - removing it touches
    undo, resume, RunState and test_persistence_fuzz. Deliberately, not incidentally.

- id: S15
  description: 'The meta allotment card (SkillGridAllotment).'
  files_touched: [solatro/Cards/Skills/Rules/skill_grid_allotment.gd, solatro/Scripts/player_settings.gd,
     solatro/Tests/Support/test_decks.gd, solatro/Tests/Engine/test_grid_cards.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 42 SUITES: 3368 CHECKS PASSED ========
    TP-62..TP-65 green. Integer ceiling (n + d - 1) / d; divisor and cap are settings.
    Red: plain truncating division fails "one card past the boundary (53) rounds up to 2".
    Committed ead7f66.
  notes: 'Done-when: TP-62..TP-65 green. Frame 11.'

- id: S16
  description: 'The grid creator card (SkillGridCreator).'
  files_touched: [solatro/Cards/Skills/Rules/skill_grid_creator.gd,
     solatro/Cards/Skills/Rules/skill_grid_allotment.gd, solatro/Scripts/board.gd,
     solatro/Scripts/game_data.gd, solatro/Scripts/card_effect_api.gd,
     solatro/Tests/Engine/test_grid_cards.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 42 SUITES ======== (only the known intermittent failing)
    TP-66..TP-69 green; TP-69 exercises BOTH directions. S15's placeholder is closed and
    its deferral comment deleted - the allotment card now adds/removes creator CARDS.
    Red, both rules:
      wipe total_score on removal -> [FAIL] the banked total is untouched by removing the grid
      never subtract creators     -> [FAIL] shrinking the deck subtracts creator cards back
                                            down to one -- got 3
    Committed fb76d84.
  notes: 'Done-when: TP-66..TP-69 green. Frame 12.'

- id: S17
  description: 'TypeInput with on_next removed, and the left-to-right refill.'
  files_touched: [solatro/Cards/Types/type_input.gd, solatro/Levels/game.gd,
     solatro/Scripts/card_effect_api.gd, solatro/Tests/Engine/test_grid_cards.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 42 SUITES: 3366 CHECKS PASSED ======== (at commit 8626cae)
    TP-70..TP-74 green. TP-70 asserts the exact card per slot, not that slots are full.
    ⚠ REVISED in S18: the trigger was evaluated PER HEADER, so the initial deal dealt ONE
    card - the Entrance stopped being empty after the leftmost drew. S17's own fixtures had
    no grids, which made the other branch trivially true, so they passed for the wrong
    reason. Game now takes the decision once; see S18.
    Committed 8626cae.
  notes: 'Done-when: TP-70..TP-74 green. Do NOT add an Entrance width property.'

- id: S18
  description: 'Commit, silent commitment, and the lift when no legal placement remains.'
  files_touched: [solatro/Levels/game.gd, solatro/Scripts/game_data.gd,
     solatro/Cards/Types/type_input.gd, solatro/Tests/Engine/test_grid_cards.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    ======== ALL 42 SUITES: 3393 CHECKS PASSED ========
    TP-75..TP-78 green. TP-76 asserts the board is untouched AND the card is still held.
    TP-78 asserts a further placement and a refill do NOT lift the commitment.
    Game.refill_entrance_if_due() now decides once and broadcasts &"on_refill"; headers each
    fill their own slot, so leftmost-first still falls out of dispatch order.
    Committed 28610a3.
  notes: 'Done-when: TP-75..TP-78 green.'

- id: S19
  description: >
    RESHAPED by the owner's GAP-007 answer. Was "move the tableau cards to an archive
    directory, add an archive rules builder". Is now: DELETE the tableau from rules1 and
    REBUILD the six suites that used it onto the grid game. No Archive/ directory, no
    Deck.archive_rules1.
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Owner verbatim: "rebuild, i dont care about archiving anymore, just replace all existing
    to fit for now without throwing errors". ⚠ TP-79 is VOID as written - it asserts the
    archived cards are constructible from a builder that will not exist. The gate becomes: a
    green suite, nothing throwing, every suite exercising the grid game.
    Leaves rules1: the 5 SkillAdderInputUpper (they make the Entrance), SkillGridAllotment,
    SkillLineDetector. Goes: the 6 lower adders, grabber, placer, cascade scorer, poker
    evaluator - and TypeInput.on_next plus _legacy_drop_to_lower, which exist ONLY as
    scaffolding to keep those six suites alive until this step.
    The six to rebuild, with their current failure counts when the scaffolding is removed:
    E2E RUN 5, MODS 4, LEAK CANARY 4, VISUAL LAYERS 3, UI PROPS 2, INTERACTION 2.


- id: S19b
  description: >
    THE LEGACY ZONE MIGRATION - not a PLAN.md step. Added because the owner's GAP-003 answer
    retires the legacy 3-component coordinate: the lower zone becomes an ordinary grid, the
    upper zone becomes the Entrance at y == -1, and position_of returns BoardCoord.
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Blast radius measured: 296 references to upper_zone/lower_zone across 29 files, plus
    Board.locate, position_of and the board-position Vector3i.MIN checks; it reaches the UI,
    props and pips. Sequenced here (not before Phase 2) because Phases 2-3 read only grids,
    and S19 first archives the tableau cards that operate the lower zone. See GAP-003.
    ⚠ Until this lands, grid work reads card_at / the grid index, never position_of.

- id: S37b
  description: >
    THE CLOSING PASS - not a PLAN.md step. Added because nothing between S1 and S37 audits
    what this run wrote: PLAN.md's own documentation phase is S40-S44, outside this run's
    range, and /plan-run's "Closing the run" is skill guidance rather than a tracked step.
  files_touched: []
  verification_command: 'py .claude/tools/doc_check.py && py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Scope: read the whole run's diff; adversarial review against DESIGN/PLAN/TEST_PLAN/NAMES
    tracing what a player actually does; run /simplify over the changed files for reuse,
    duplication and dead code; /docs pass over the new files and comments; fold ASSUMPTIONS.md
    and the resolved gaps into the living docs; confirm doc_check reports no NEW findings
    against the pre-existing backlog (measured at run start: 0 errors, 8 warnings - 343 design
    ids, 137 dated, 128 long blocks, all pre-existing). ⚠ Do NOT delete the gap files: a gap is
    closed by a new design version, not by deletion.

- id: S35
  description: 'Every placement an undo step; scores rewind with the board.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-121..TP-123 green.'

- id: S36
  description: 'pending_action carries a placement and replays it.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-124..TP-126 green.'

- id: S37
  description: 'validate() grid invariants; headless parity assertion. STOP HERE.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Done-when: TP-127..TP-130 green. TP-128 is the phase gate: a headless show and a viewed
    show produce byte-identical final state.
```

## Verified vs assumed

- **Verified** — baseline green at 39 suites / 3134 checks, by the command above.
- **Verified** — the card scene ships no saved ShaderMaterial (`grep -c` reads 0).
- **Verified by eye** — cards render with clamped art frames and pips at the card bottom
  (`Tests/Visual/reveal_shot.tscn`, `02_open_full.png`).
- **Assumed, not checked** — that `CARD_SEPARATION = 16` is correct. Taken from `PLAN.md`
  §1.8 as instructed; not re-derived.

## The card effect API — BUILT, not parked

The owner answered all seven forks in `design/card-effect-api/BRIEF.md`, and the layer is
implemented across three commits (fb37f9f, 84d4c36): `CardEffectApi`, one instance per `Game`,
reached as `CardModifier.api`. **`CardModifier.game` is REMOVED**, all 26 card modifiers are
migrated, and a suite gate fails on any `game.` / `Game.` / `GameData` / `Board.` inside a
modifier — identified by its `extends` base, not by directory.

Design and the answers verbatim: `design/card-effect-api/DESIGN.md`.

⚠ Extending the layer is the sanctioned move when a card needs something it does not expose —
add the method with a `##` comment. S16 added three that way.

## Gaps — all SEVEN filed, all SEVEN answered by the owner

Answers are quoted verbatim at the top of each gap file and **outrank `PLAN.md` and
`NAMES.md`, because they are newer.**

| gap | answer | state |
|---|---|---|
| GAP-001 / GAP-002 | Movement is two-axis over an UNBOUNDED lattice; `has_cell()` is the landing question; a landing on nothing discards | implemented `fea5768` |
| GAP-003 | The legacy 3-component coordinate is retired; lower zone becomes a grid, upper becomes the Entrance | **scheduled as S19b, NOT implemented** |
| GAP-004 | A diagonal is a same-rate run; corners are not part of the definition. Owner confirmed this governs the FLAT case only — the eight climbing families stand | implemented `6092a27` |
| GAP-005 | A vertical stack banks into a PER-CELL bucket, keyed by coordinate so a grid can change shape | implemented `581d02a` |
| GAP-006 | Height scores fold into the SPECIAL term: `row x col x special(diag + height) x combo`. Raised row/col levels fold into their own terms | implemented `54cab17` |
| GAP-007 | Rebuild the six suites; **the archive is cancelled entirely** | **drives S19, NOT implemented** |

⚠ `NAMES.md`'s `step_x(n)` is superseded — the shipped name is `step(dx, dy, grid_widths)`.

## Open bugs

- ⚠ **94 `I5` validate WARNINGS during undo in `test_grid_cards.gd`** — cards sitting in
  `draw_deck` still stamped `PLAY`. No check fails; confined to that one suite. Best read: the
  fixture's `_take_held` lifts a card out of the Entrance without a mutation path, leaving it
  in no collection while still stamped `PLAY`. **Resolve at S35**, which owns making a
  placement a real undo step and will replace that shortcut. Not hidden by widening anything.
- ⚠ **`VISUAL LAYERS`: "a light stays on its card's art square every frame while that card
  moves"** fails roughly 1 run in 3, measuring 2.5–3.0 px against a `worst < 1.0` tolerance.
  **Pre-existing and out of scope** (owner: the light is out of scope, and it may be the test
  measuring too early). Exposed — not caused — by stripping the card scene's baked materials:
  3/3 clean with the bake, ~1-in-3 without. **The tolerance was calibrated with the bug
  present, so it was NOT widened.** Judge every suite run by failure SET with this one
  excluded, and confirm it is the only failure.
- `.claude/memory/machine-profiles.md` records Godot **4.7.1** for Box A; the box has **4.7.2**
  and no 4.7.1. Anything reading that path dies with `FileNotFoundError`. Memory file, outside
  this run's scope.
- **`PLAN.md` §1.1 and `TEST_PLAN.md` TP-02 state an arithmetically wrong example** —
  *"5 columns left of (grid 1, x 0) is (grid 0, x 4)"*. At width 5 it is ONE column left. The
  owner's source answer `Q3` contains no such example. Both cases are asserted in the tests;
  the design docs were left unedited.

## Files touched

`git diff --stat 69eee09..HEAD` from the worktree root. New product files:
`Scripts/board_coord.gd`, `grid_data.gd`, `grid_cell_walk.gd`, `line_geometry.gd`,
`card_effect_api.gd`; `Cards/Types/type_grid_cell.gd`;
`Cards/Skills/Rules/skill_line_detector.gd`, `skill_grid_allotment.gd`,
`skill_grid_creator.gd`. New suites: `Tests/Engine/test_grid_board.gd`,
`test_line_detect.gd`, `test_grid_economy.gd`, `test_grid_cards.gd`;
fixtures in `Tests/Support/test_grid_fixtures.gd`.

## Next up

1. **S19 — the rebuild.** The biggest remaining piece. Delete the tableau from `rules1`,
   remove `TypeInput.on_next` and `_legacy_drop_to_lower`, and rebuild the six suites onto
   the grid game. No archive directory, no builder. TP-79 is void.
2. **S35** — every placement an undo step; scores rewind with the board (TP-121..TP-123).
   ⚠ Also resolves the 94 `I5` warnings above.
3. **S36** — `pending_action` carries a placement and replays it (TP-124..TP-126).
4. **S37** — `validate()` grid invariants; **headless parity** (TP-127..TP-130). ⚠ TP-128 is
   the phase gate: a headless show and a viewed show produce byte-identical final state.
5. **S19b** — the legacy coordinate migration (GAP-003). 296 references across 29 files.
6. **S37b** — the closing pass: full diff review, adversarial review, `/simplify`, `/docs`.

⚠ **S19 and S19b overlap heavily.** Both remove the legacy two-zone board. Doing S19's rebuild
first and then S19b means touching the same six suites twice. **Consider merging them**, or
doing S19b first so the rebuild lands directly on `BoardCoord`. That is a judgement call the
next overseer should make deliberately, not stumble into.

## References

- `design/poker-patience/PLAN.md` — the steps, and §1 the normative contracts.
- `design/poker-patience/DESIGN.md` — the authority on behaviour.
- `design/poker-patience/TEST_PLAN.md` — every test that must exist, fixtures fixed in advance.
- `design/poker-patience/NAMES.md` — every identifier, and the claimed art frames 9–13.
