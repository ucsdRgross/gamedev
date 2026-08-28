# HANDOFF — poker patience

**Goal:** turn Solatro's two-zone tableau into the poker-patience grid game — the engine, then the
board the player sees. Done when a player can deal, place, score, undo and End a show on a grid
they can look at.

**State:** **The engine is complete, the board draws and reacts, the legacy zones are gone, and the
Entrance is PINNED.** A scored grid line fires props; the Entrance stays welded to the bottom of the
window with its slots under their columns while the board scrolls.

Landed: `S1`-`S19`, `S35`-`S37`, `S37b`, `S20`, `S20b.1`, `.2`, `.2b-0`, `.2b` (Runs A+B), the
layering port, `S20c`, `S20b.4a`, **`S20b.3`**. Tree CLEAN, suite green at **43 suites /
3462 CHECKS PASSED**, HEAD `a641f4e`.

**What is left in this phase is `S20b.4b`** — grid equivalents for the reveal machinery and the
hoop front/back split (unfinished GAP-012 scope, which unblocks the 6 layering tests still on the
Entrance), then the 5 PORTABLE fixtures. After that Phase 5 begins: `S21`-`S25`, the flipped board,
**where cards start stacking UPWARD**.

**Entry docs:** `START_HERE.md`; `design/poker-patience/{PLAN.md,DESIGN.md,TEST_PLAN.md,NAMES.md}`;
`design/grid-view/DESIGN.md` (the view's own design, answered and confirmed);
`design/card-effect-api/DESIGN.md`; `HEADLESS_TESTING.md`.

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from `design/poker-patience/DESIGN.md` version 2 and `design/grid-view/DESIGN.md` version 2.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent → do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise → **park that thread, file a gap, keep working on unaffected threads, tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.
4. ⚠ Two documents disagreeing is NOT automatically (3) — read the answer they are both restating.

File gaps at `design/<slug>/gaps/GAP-NNN.md`, options in the questionnaire grammar. Do not resolve
a gap by picking an answer. Do not delete a gap — it is closed by a new design version.

## Environment — traps that have each cost real time

- Godot here is **4.7.2**. `.claude/memory/machine-profiles.md` records 4.7.1 and is STALE; anything
  reading that path dies with `FileNotFoundError`.
- Suite: `GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400` from the repo
  root. Runs WINDOWED, ~90 s, self-quits. **Close the owner's editor first.**
- ⚠ **A new `class_name` referenced from an existing script HANGS the suite** rather than failing to
  parse. Symptom: `test_interaction` spinning on `submits_used` against a Nil. Fix: run
  `--headless --path . --import`. Always pass `--timeout` so a hang fails fast.
- ⚠ `export PYTHONIOENCODING=utf-8` before any python heredoc, or the console encoding kills the
  script MID-EDIT and leaves a source file half-written.
- ⚠ **Judge by the failure SET, never the check total** — the total varies run to run. And read the
  log for `SCRIPT ERROR` and check the SUITE COUNT even when the banner says all passed: a suite
  that fails to compile silently drops out (measured: 43 → 41, twice).
- ⚠ **NEVER RUN TWO SUITES AT ONCE, and never background one.** Two Godot processes write the same
  log, and the console banner and the log banner then DISAGREE (measured: console "3465 CHECKS
  PASSED" against the log's "3 FAILED"). Check no `Godot_v4.7.2-stable_win64_console` process is
  alive before starting, and make console and log agree before believing either.
- ⚠ **THE TEST LOG IS `...\Solatro\logs	est	est_output_all.log`.** A file of the SAME NAME sits
  directly under `Solatro\` and is months stale -- it greps clean while the banner reports failures.
  Check the mtime. `START_HERE.md` named the stale path and has been corrected.
- ⚠ **`doc_check.py --changed` is STRICTER than the full run on design-id citations.** Touch an old
  file and it reports the standing backlog as errors in that file. The full run is the gate: it
  reads 0 errors, 7 warnings. Judge a regression by the full run plus a diff check for ADDED ids.
- By-eye rendering: `<godot> --path solatro res://Tests/Visual/reveal_shot.tscn`, writes
  `user://reveal_shots/*.png`. It stands up a REAL `GameView`; it is the only thing that shows the
  board.

## Tasks

⚠ **The stale-step tooling only recognises `S<digits>`.** `designloop/src/gaps.mjs::planSteps()`
reads 23 ids out of this ledger — `S1`–`S19`, `S35`–`S37`, `S20` — and does NOT see the lettered
ones (`S19b`, `S37b`, `S20b1`, `S20b2b`, `S20c`, …). So a gap whose blast radius names a lettered
step will not appear in its stale list. The lettered convention predates this stream and is used in
`PLAN.md` too; renumbering would break the citations in `PLAN.md` and `TEST_PLAN.md`. Check
lettered steps by hand when closing a gap.

```yaml
# --- LANDED. Evidence is in the commit messages; forensics are in the gap files. ---
- id: S1
  description: 'BoardCoord: grid/x/y/h, NOWHERE, ENTRANCE_ROW, two-axis step over an unbounded lattice.'
  status: done
- id: S2
  description: 'GameData grid storage: GridData, the grid list, 25 cell zone cards per grid.'
  status: done
- id: S3
  description: 'Position index extended to grids, plus the reverse index and its invariant.'
  status: done
- id: S4
  description: 'Board mutation API for cells: place, move, remove-with-compaction.'
  status: done
- id: S5
  description: 'CardDataIterator over grids; the early stop REMOVED.'
  status: done
- id: S6
  description: 'Line enumeration: ROW, COL, DIAG (10 directions), HEIGHT_V, within one grid.'
  status: done
  notes: 'LineGeometry._row is already within-one-grid and left-to-right -- REUSE it for prop routes.'
- id: S7
  description: 'ScoringSection gains kind and line_key; score_line loses is_row/zone/index.'
  status: done
- id: S8
  description: 'The mutation broadcast, the explicit compaction flag, and the board lock.'
  status: done
- id: S9
  description: 'The detector card: enumerate, score, re-scan until nothing new completes.'
  status: done
  notes: >
    The runaway guard (act_event_cap, MAX_TICKS) is CORRECTNESS-critical -- there is no
    line-scored memory and no within-pass guard, so a remove-and-replace effect re-scores
    forever without it. Do not tune it away; S35 nearly did.
- id: S10
  description: 'Wire the section into Scoring.PokerHands.score() and the spotlight cascade.'
  status: done
- id: S11
  description: 'Height scoring: multiples of 5, whole stack, drops never score.'
  status: done
- id: S12
  description: 'The three buckets per grid, pack/unpack, duplicate_state hand-copy.'
  status: done
- id: S13
  description: 'grid_score as the product of positive buckets; board_total as their sum.'
  status: done
- id: S14
  description: 'The combo model; MAX_SUBMITS, submits_used, score_additive and patience retired.'
  status: done
- id: S15
  description: 'The meta allotment card (SkillGridAllotment).'
  status: done
- id: S16
  description: 'The grid creator card (SkillGridCreator).'
  status: done
- id: S17
  description: 'TypeInput with on_next removed, and the left-to-right refill.'
  status: done
- id: S18
  description: 'Commit, silent commitment, and the lift when no legal placement remains.'
  status: done
- id: S19
  description: 'THE REBUILD: rules1 becomes the grid game; six suites follow it.'
  status: done
- id: S35
  description: 'Every placement one undo step; scores rewind with the board.'
  status: done
  notes: >
    save_state() is called LAST in place_card_in_grid -- the scores live on `state`, so an
    earlier snapshot rewinds the board without rewinding what it scored. Guarded on
    `not processing` so an effect's placement stays part of the act that caused it.
- id: S36
  description: 'pending_action carries a placement (Entrance SLOT + coord) and replays it.'
  status: done
- id: S37
  description: 'validate() grid aliasing invariants; headless/viewed parity gate.'
  status: done
- id: S19b
  description: 'The legacy coordinate migration -- SUPERSEDED, folded into S20b by GAP-009.'
  status: superseded
- id: S37b
  description: 'The closing pass: adversarial review, /simplify, /docs.'
  status: done
- id: S20
  description: 'CARD_SEPARATION re-derived from the measured bottom-edge pip offset.'
  status: done
- id: S20b1
  description: 'The grid view: %GridContainer, one GridPanel per grid, a CellSlot per cell.'
  status: done
- id: S20b2
  description: 'Old zone frame on cells; grid on top; Entrance aligned beneath; card_scale 2.5 -> 1.'
  status: done
- id: S20c
  description: 'Retire the act: Game.submit, _perform_submit, the on_run_scorer branch, the Next button.'
  status: done
  evidence: 'ALL 43 SUITES green; grep: zero readers of submit/_perform_submit/next_button in product code.'
  notes: >
    Q31=(b); chart P3/P4. Game.next()/_perform_next() STAY -- the plan retires the BUTTON, and
    _perform_next still serves the &"on_next" replay. TP-80i (gate) and TP-80j (behavioural) are
    new and red-then-green verified. Touchscreen coverage was RESTORED, not accepted as lost.
    The new touch test must run AFTER the mouse tests: a touch leaves no HOVER and the mouse
    selection path needs one.
- id: S20bDraw
  description: 'Fix: _order_board_cards never ordered grid cards, so a card drew BEHIND its own cell.'
  status: done
  evidence: 'RED card idx 9 vs cell idx 27; GREEN margin +25 and by-eye sign-off on grid_occupied.png.'
  notes: 'Owner found this by eye. _append_grids_row_major mirrors the zone helper. TP-80m pins it.'
- id: S20bRatchet
  description: 'GAP-013=(a): the zone-only test ratchet, and the sentinel gate for BoardCoord.NOWHERE.'
  status: done
  notes: 'Eleven zone-only test files enumerated; the set may shrink, never grow.'

# --- PENDING ---
- id: S20b2b0
  description: 'BoardCoord gains equals(), pack() -> Vector4i, unpack(), is_nowhere(); null retires.'
  status: done
  evidence: 'ALL 43 SUITES green. RED: equals->identity and is_nowhere->identity each failed their
    own checks; == NOWHERE in game.gd failed the sentinel gate.'
  notes: >
    GAP-011=(a). Had to land BEFORE any Vector3i swap -- additive means provable alone. The SENTINEL
    GATE (test_game_headless.gd) is what makes (a) verifiable: nothing may write == / !=
    BoardCoord.NOWHERE, because NOWHERE is a shared instance and a rebuilt sentinel is not identical
    to it. Its needles are built by concatenation or the gate flags its own constant.
- id: S20b2b
  description: >
    THE COORDINATE MIGRATION. slot_center_global takes a BoardCoord; the prop chain rides it; routes
    stay inside one grid.
  status: done
  evidence: '[PASS] a scored grid line spawns props. ALL 43 SUITES green. By eye (grid_props.png):
    16 props draw ON the scored row, score 38 / COMBO x19.'
  notes: >
    Run A = geometry (GAP-012=c: panels publish their origin on `resized`, the function reads the
    cache, so the every-frame anchor path does no tree reads). Run B = the prop chain and routes.
    ⚠ THE RULING THAT UNBLOCKED IT: both prop suites build in upper_zone, which is the ENTRANCE, and
    BoardCoord always named that as ENTRANCE_ROW -- so _scan_grid_positions now indexes Entrance
    cards and card_at/grid_position_of answer for the whole board. PROOF IT WAS RIGHT:
    test_suit_props.gd is UNCHANGED and green.
    ⚠ The LOWER zone stays deliberately unmapped. A path that needs it is a real gap.
    Routes REUSE LineGeometry.row_cells, which structurally cannot leave its grid.
    row_slot_path_from locates via pack(): find() on a RefCounted is identity-based.
- id: S20bPort
  description: 'Tests/UI/test_visual_layers.gd gets real grid coverage; struck off ZONE_ONLY_TESTS.'
  status: done
  evidence: 'VISUAL LAYERS: ALL 195 CHECKS PASSED (was 192 -- the count went UP, so nothing was
    traded away). Ratchet list down to 11.'
  notes: >
    GAP-013=(c). 12 of 18 tests build real GridData boards; 6 are BLOCKED and left on the Entrance
    with a comment naming the code they wait on. This is the suite whose absence let a card draw
    behind its own cell through 43 green suites.

# --- PENDING ---
- id: S20b4a
  description: 'Delete the LowerZone and MiddleZone rendering; Entrance deliberately untouched.'
  status: done
  evidence: 'ALL 43 SUITES green, console and log agreeing. BY EYE: the dead band between grid and
    Entrance is GONE -- the Entrance strip now sits directly under the grid.'
  notes: >
    Landed alone so the Entrance can move later against ONE renderer. GameData.lower_zone storage
    remains, populated and serialized; nothing renders it. Same for scores_row_lower.
    ⚠ VISUAL LAYERS dropped 195 -> 188 checks. Verified NOT a loss: one line changed, zero check()
    lines removed -- it is loop iterations that used to cover the deleted zone.
- id: S20b3
  description: >
    The Entrance is a pinned %EntranceStrip outside the board's scroll, x slaved to it, with its
    own vertical scroll and its own card layer.
  status: done
  evidence: 'ALL 43 SUITES: 3462 CHECKS PASSED, console and log agreeing. BY EYE
    (grid_occupied.png): the strip is welded to the BOTTOM OF THE WINDOW, not to the grid, with its
    five slots exactly under the five grid columns.'
  notes: >
    ⚠ THIRD ATTEMPT, after two backouts. It worked because it ran against a SINGLE renderer -- the
    coordinate migrated at S20b.2b and the zones stopped rendering at S20b.4a -- and produced six
    comprehensible failures where attempt two produced 1041 engine errors. That sequencing was the
    whole bet. If anything in this area is ever reworked, keep it: one renderer at a time.
    Scene: EntranceStrip (child of PlayArea, OUTSIDE SmoothScrollContainer) > EntranceHTrack >
    EntranceVScroll > EntranceContent > { UpperZone, EntranceCardLayer }.
    GAP-010's four traps are closed: own card layer; TWO INDEPENDENT draw orderings (one shared
    index space across two layers re-queues every frame until the stack overflows); _bind_slot
    reparents a visual between layers; and the ALIGNMENT_CENTER origin disagreement, which was a
    LAYOUT problem -- test_grid_layout.gd:106-112 compares control rects, never slot_center_global.
    Renaming upper_zone -> entrance stays deferred; cosmetic.
- id: S20b4b
  description: 'Grid equivalents for the reveal and the hoop split; port the 5 PORTABLE fixtures.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Unfinished GAP-012 scope: _row_open_offset -> _row_covers_anything (the reveal) and
    _row_bounds -> PlayArea.row_card_visuals (the hoop front/back split) are still zone-indexed and
    have no grid form. They are why 6 layering tests still sit on the Entrance.
    ⚠ Only FIVE fixtures are portable -- see the ratchet's own categories.
```

After `S20c`, `PLAN.md` §3 governs: `S21`–`S25` (the flipped board — **this is where cards start
stacking UPWARD**), Phase 6 (zoom, pan, focus), Phase 7 (the wall), Phase 9 (goal-curve refit,
owner's call), Phase 10 (documentation).

## Verified vs assumed

- **Verified** - `ALL 43 SUITES: 3462 CHECKS PASSED`, tree clean, zero failures, console banner and
  log banner AGREEING (see the two-process trap in Environment).
- **Verified** - `[PASS] a scored grid line spawns props`. The check that asserted `== 0` for this
  whole stream now asserts `> 0` and passes.
- **Verified by eye** - `grid_occupied.png`: cards cover their cells, empty cells still frame, a
  stacked cell shows the strip beneath. `grid_props.png`: 16 props draw ON the scored row, score
  38 / COMBO x19. Both from `Tests/Visual/grid_layer_shot.tscn`.
- **Verified by eye, the pinned Entrance** - the strip is welded to the BOTTOM OF THE WINDOW, not
  to the grid, and its five slots sit exactly under the five grid columns while the grid fills the
  top. The large gap between them is the POINT: the strip stays put while the board scrolls.
- **Verified by eye, after the demolition** - the dead band between the grid and the Entrance is
  GONE. The Entrance strip now sits directly beneath the grid's last row; that band was where the
  deleted MiddleZone/LowerZone drew, and it is what the owner objected to (*"cards in random
  locations not on top of any zones, such as in area between grid and entrance"*).
- **Verified** - `py .claude/tools/doc_check.py`: 0 errors, 7 warnings (standing style backlog).
  Zero design ids in product code.
- ⚠ **Measured, and NOT a defect**: sampling showed 0 of 16 props moving over 90 frames. That is a
  HARNESS artefact - `run_props` is awaited inside `place_card_in_grid`, so the flight is over
  before any polling loop starts. The score changing is what proves the cascade ran. To watch
  motion you must sample DURING the placement await.
- **Assumed, not checked** - that `card_scale` 1.0 suits every OTHER screen (deck viewer, map, info
  card). Only the play area was looked at.

## The card effect API - a suite gate enforces it

A card modifier may NOT touch `Game`, `GameData` or `Board` directly - everything goes through
`CardEffectApi` as `CardModifier.api`, and a suite gate fails on any direct reference inside a
modifier. ⚠ **Extending the layer (with a `##` comment) is the sanctioned move.** See
`design/card-effect-api/DESIGN.md`.
⚠ The gate matches the substring `"Board."`, so `BoardCoord` passes but `Board.locate_in_cell` would
trip it. The five `PipSuit` subclasses are gated; `PropModifier` is not.

## The three gates a change here must satisfy

1. **Card effect API** (above) - modifiers reach the game only through `api`.
2. **The sentinel gate** - nothing anywhere writes `== BoardCoord.NOWHERE` or `!=`. `NOWHERE` is a
   shared instance and `==` on a RefCounted is IDENTITY, so a rebuilt sentinel is not equal to it.
   Use `is_nowhere()`; compare coords with `equals()`; key dictionaries and `Array.find` on
   `pack()`. Comment lines are exempt, which is how the rule can be written down.
3. **The zone-only ratchet** - `test_game_headless.gd::ZONE_ONLY_TESTS` lists the 11 test files that
   assert against the legacy renderer and never touch a grid. The set may SHRINK, never grow, and
   porting a file fails the gate until its name is struck off, so the list cannot rot.

## Gaps - fourteen filed, fourteen resolved

`design/poker-patience/gaps/GAP-001..009`, `design/grid-view/gaps/GAP-010..014`. Answers are quoted
verbatim at the top of each and **outrank `PLAN.md` and `NAMES.md`, because they are newer.**

- **GAP-010** the Entrance is pinned, x slaved, independently scrollable - ⚠ **read before S20b.3**.
- **GAP-011**=(a) `BoardCoord` keeps one type, gained value affordances - landed.
- **GAP-012**=(c) panels publish their origin on `resized`; `slot_center_global` reads the cache -
  landed for the geometry. ⚠ **NOT finished**: it also names `_row_open_offset` ->
  `_row_covers_anything` and `_row_bounds` -> `row_card_visuals` as needing grid equivalents.
  Neither exists. That is what S20b.4 owes.
- **GAP-013**=(a)+(c) the ratchet and the layering port - both landed.
- **GAP-014** NOT A GAP, resolved as a defect: a fourth option existed (name the zone the test
  measures, and stock it). Kept because it was filed correctly and the reasoning matters.

## Owner working agreements

- **Reuse, do not reinvent.** Verbatim: *"reducing duplicate code as much as possible and no
  reinventing existing setups, or using existing engine methods when available."* ⚠ Put it in every
  step brief. Declining reuse is fine ON RECORD, with the reason in the file.
- **The light layer is out of scope.**
- **No design ids in product code** - not in a comment, not in an `@export_group` label. `Tests/` is
  exempt. One leaked (`M5/M6`) and was caught and removed; the count is back to zero.
- **By-eye beats green.** The draw-order defect was found by the owner looking, not by 43 suites.
- **Old tests do not block the rebuild.** Verbatim: *"dont let tests from old version stop you since
  they need to be remade too."*

## Open bugs

- ⚠ **The reveal machinery is zone-only.** `_row_open_offset` -> `_row_covers_anything`
  (`play_area.gd`) reads the zone arrays directly, so row-opening has no grid model. **3 layering
  tests sit on the Entrance because of it.** Unfinished GAP-012 scope; S20b.4 owns it.
- ⚠ **The hoop front/back split is zone-only.** `PropLayer._apply_split` brackets only an
  Entrance-anchored prop, because `_row_bounds` -> `PlayArea.row_card_visuals` is zone-indexed, so a
  grid-anchored hoop stays UNSPLIT. **3 more layering tests sit on the Entrance.** Same GAP-012
  scope. ⚠ Not a regression - before the migration a grid fired no props at all.
- ⚠ **11 test files still assert only against the legacy renderer, but only FIVE are portable.**
  The ratchet list (`test_game_headless.gd::ZONE_ONLY_TESTS`) now marks three categories, because
  "11 files to port" is wrong and misleading: **PORTABLE** (5) are fixtures that happen to sit in a
  zone; **MACHINERY** (3 - `test_board`, `test_mods`, `test_spotlight`) test the legacy machinery
  ITSELF, which is still LIVE (find_data_vec3 has 9 product callers, get_zone_from_vec3 7,
  is_data_topmost 7, add_column/remove_column 9) - they cannot port and must not be deleted;
  **ENTRANCE-ONLY** (3) name `upper_zone`, which IS the Entrance. Three of these leaving the list
  would be a BUG, not progress.
- ⚠ **`Tools/spotlight_tool.gd` traces no cascade.** PRE-EXISTING: `git log -S place_card_in_grid`
  on it is empty - it has only ever used `move_data_to_coord` into the legacy lower zone.
- ⚠ **`Tests/Interaction/test_interaction.gd:459` is `check(true, ...)`** - a parked check that can
  never fail, unlike the props one which self-unparked. Restore it to assert `game.processing` once
  a placement is a paced, cancellable act.
- **The COMBO label draws over the End button** - visible in `grid_occupied.png`.
- **`skill_scorer_cascade_lower.gd`** is an orphan in production, still a fixture in three suites.
- **`PLAN.md` 1.1 / `TEST_PLAN.md` TP-02 state an arithmetically wrong example** - *"5 columns left
  of (grid 1, x 0) is (grid 0, x 4)"*. At width 5 it is ONE column left. Tests assert the correct
  behaviour; the docs were left unedited.

## Next up

1. **`S20b.3`** - pin the Entrance. The demolition (`S20b.4a`) is already done, so this is the first
   attempt against a SINGLE renderer. Read GAP-010 first.
2. **`S20b.4b`** - grid equivalents for the reveal and the hoop split (unfinished GAP-012 scope,
   which unblocks 6 layering tests), then port the 5 PORTABLE fixtures.
3. Then `PLAN.md` section 3: `S21`-`S25` (the flipped board - **cards start stacking UPWARD**),
   Phase 6 (zoom/pan/focus), Phase 7 (the wall). Phase 9 is the owner's call; Phase 10 is last.

### Opening prompt for the next session

```
Continue the poker-patience GRID VIEW as OVERSEER, using /plan-run.

WORKTREE: the gamedev-poker-patience worktree, branch `poker-patience`.
The repo's no-commit rule is REVERSED for you there: one commit per step whose done-when
YOU verified. Implementer subagents never commit, stage or stash.

READ IN THIS ORDER:
  1. solatro/HANDOFF_poker_patience.md - this file: state, traps, ledger, gates, open bugs.
  2. solatro/design/poker-patience/PLAN.md section 3 (steps), section 1 (contracts).
  3. solatro/design/grid-view/DESIGN.md - charts J, K, L, M, N, P.
  4. The gap files: FOURTEEN filed, all resolved. Answers are quoted verbatim at the top of
     each and OUTRANK PLAN.md and NAMES.md. ⚠ GAP-010 before touching the Entrance;
     GAP-012 for what is still UNBUILT; GAP-013 before writing any test.
  5. solatro/design/card-effect-api/DESIGN.md - modifiers reach the game only via
     CardModifier.api, and a suite gate enforces it.

GROUND TRUTH BEFORE TRUSTING ANY `done`:
    GODOT_BIN="<godot 4.7.2 console exe>" py solatro/Tools/run_tests.py --timeout 400
  Expect ALL 43 SUITES, zero failures. Last verified 3462 CHECKS PASSED, tree clean.

THE WORK: S20b.3 + S20b.4 TOGETHER (never separately - GAP-010), then PLAN.md section 3
(S21-S25 the flipped board, Phase 6, Phase 7).

NON-NEGOTIABLES, each of which caught a real defect on this stream:
  - RED-THEN-GREEN for every new test, and check the red failed the checks you EXPECTED.
    Do the red runs YOURSELF; never accept a self-reported green.
  - VERIFY VISUALS BY EYE. Tests/Visual/grid_layer_shot.tscn shows a POPULATED grid and
    prints card-vs-cell draw indices; reveal_shot.tscn shows an empty one. A green suite is
    not evidence about pixels - the owner found a card drawing behind its own cell that 43
    green suites did not.
  - NEVER run two suites at once and never background one: two processes write one log and
    the banners disagree. Check no Godot process is alive first.
  - CHECK THE SUITE COUNT (43), not just the failure set. A parse error drops a whole suite
    silently while the banner still reads plausibly.
  - CHECK THE LOG'S MTIME, and read logs/test/test_output_all.log - a stale file of the same
    name sits one directory up and greps clean.
  - AT EVERY PHASE BOUNDARY: read the diff, run an adversarial pass tracing what a PLAYER
    does, and run `py .claude/tools/doc_check.py`.
  - Every step brief names THE CALL SITE. Never accept `done` on a component whose consumer
    does not exist.
  - REUSE, don't reinvent. Declining reuse is fine ON RECORD with the reason in the file.
  - Subagents exhaust their turns on a whole step, and thrash if asked to decide while
    editing. Make them DECIDE THE SPLIT FIRST, then convert once. The agent does production
    code plus mechanical tests; YOU write the gate and intricate tests and run every red-green.

If you hit a decision no document fixes: file a gap at solatro/design/<slug>/gaps/GAP-NNN.md
following GAP-001's shape, park that thread, keep the unaffected ones moving, and QUOTE the
gap's own option text to the owner. A bug is not a gap: if exactly one choice is defensible
it is a defect - fix it and record it. And check for a FOURTH option before filing: GAP-014
was filed correctly and still turned out to be a defect.
```

## References

- `design/poker-patience/PLAN.md` - the steps; section 1 the normative contracts.
- `design/poker-patience/DESIGN.md` - the authority on the game's behaviour.
- `design/grid-view/DESIGN.md` - the view's design, its answers and its six charts.
- `design/poker-patience/TEST_PLAN.md` and `NAMES.md` - every planned test; every identifier.
- `ARCHITECTURE_REVIEW.md` - the engine's contracts (undo, pending-action replay, layering).
