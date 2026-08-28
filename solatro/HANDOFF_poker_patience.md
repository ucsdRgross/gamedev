# HANDOFF — poker patience

**Goal:** turn Solatro's two-zone tableau into the poker-patience grid game — the engine, then the
board the player sees. Done when a player can deal, place, score, undo and End a show on a grid
they can look at.

**State:** **The engine is complete and the loop closes.** `S1`-`S19`, `S35`-`S37`, `S37b` and now
`S20c` have landed. A show deals, refills, commits to a grid, grabs, places, scores, banks, undoes,
replays a quit mid-cascade, shows a live score, and Ends -- and **End is now the ONLY thing that
finishes a show**; the act, the Next button and `Game.submit` are gone.
**What is left is the VIEW.** `S20`, `S20b.1`, `.2` landed -- the grid draws, on top, in the old
zone frame, Entrance beneath it, `card_scale` 1 so the board fits the window.
⚠ **`S20b.2b` was audited against the live code and could NOT be executed as written**: it needs
`GAP-011` and `GAP-012` first, both now ANSWERED. It gains a new sub-step `S20b.2b-0` that did not
exist in the plan. Suite green at **43 suites**. Worktree `gamedev-poker-patience`, branch
`poker-patience`.

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
  evidence: 'ALL 43 SUITES: 3475 CHECKS PASSED. RED: equals->identity failed the two value checks;
    is_nowhere->identity failed its own; == NOWHERE in game.gd failed the sentinel gate.'
  notes: >
    GAP-011=(a). ⚠ It had to land BEFORE any Vector3i is swapped -- additive means provable alone.
    The sentinel gate (test_game_headless.gd) is what makes (a) verifiable: nothing may write
    == / != BoardCoord.NOWHERE, because NOWHERE is a shared instance and a REBUILT sentinel is not
    identical to it. Gate needles are built by concatenation or the gate flags its own constant.
- id: S20b2b
  description: >
    THE COORDINATE MIGRATION. slot_center_global takes a BoardCoord; the legacy Vector3i board
    position retires; prop routes follow it (one grid, left to right, never across the gap).
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: >
    ⚠ "EIGHT PRODUCT CALL SITES" IS WRONG and the low number is the dangerous half: slot_center_global
    has TWO real product calls (prop_layer.gd:280, :539), the rest are comments. What actually
    migrates is the legacy Vector3i board position -- 148 refs across 29 product files, including the
    five route builders in game.gd AND their CardEffectApi mirrors, PropData.at,
    PropVisual.anchor_coord, pip_suit.gd::_spawn_origin and its five suit subclasses. DESIGN.md 1e is
    corrected.
    ⚠ The 58 test refs are NOT a mechanical swap: all live in test_ui_props.gd (33) and
    test_visual_layers.gd (25), whose fixtures carry NO GridData, so no BoardCoord names their slots.
    They move with S20b.4.
    ⚠ GAP-012=(c) governs the geometry: panels publish their origin on `resized` and the function
    reads that cache, so the anchor path does no tree reads. Owes a resized-followed test AND a
    by-eye check. REUSE LineGeometry._row for routes -- do not write new geometry.
- id: S20bPort
  description: 'Port Tests/UI/test_visual_layers.gd onto grids, and strike it off ZONE_ONLY_TESTS.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    GAP-013=(c), DEFERRED to immediately after S20b.2b: 25 of its assertions go through
    slot_center_global, which has no grid form until then. The ratchet fails until the name is
    struck off, so this cannot be quietly forgotten.
- id: S20b3
  description: >
    The Entrance moves to a pinned %EntranceStrip outside the board's scroll, x slaved to it, with
    its own vertical scroll; upper_zone -> entrance.
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: >
    ⚠ ATTEMPTED TWICE, BACKED OUT TWICE. READ design/grid-view/gaps/GAP-010.md BEFORE THE THIRD.
    Short version: it works by eye and the fixture rebuild works (32 failures -> 1). What defeats it
    is pinning the Entrance while the legacy zones AND the legacy coordinate still exist -- three
    renderers, two draw layers, 1041 engine errors. LAND IT AFTER b.2b AND WITH b.4.
- id: S20b4
  description: 'Delete lower_zone and the legacy zone rendering; rebuild the fixtures onto grids.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    ⚠ THE FIXTURES GO ON A GRID, NOT THE LOWER ZONE. An interim redirect put test boards in the
    legacy lower zone, which draws in the band BETWEEN the grid and the Entrance -- owner: "cards in
    random locations not on top of any zones". They are on a zone, but an invisible one.
    ⚠ Moving a fixture is only half: a prop's own `p.at` names a zone too.
    This is also what empties ZONE_ONLY_TESTS and unblocks spotlight_tool's cascade.
```

After `S20c`, `PLAN.md` §3 governs: `S21`–`S25` (the flipped board — **this is where cards start
stacking UPWARD**), Phase 6 (zoom, pan, focus), Phase 7 (the wall), Phase 9 (goal-curve refit,
owner's call), Phase 10 (documentation).

## Verified vs assumed

- **Verified** - `ALL 43 SUITES: 3475 CHECKS PASSED`, tree clean, zero failures, by the command in
  Environment. ⚠ **Judge by the SUITE COUNT and the failure SET.** Mid-run a parse error dropped
  it 43 -> 42 while the failure list still looked like a single failure.
- **Verified by eye** - a board with cards ON GRID CELLS draws correctly: every card covers its
  cell, no cell outline shows through, empty cells still frame, a stacked cell shows the strip of
  the card beneath (`Tests/Visual/grid_layer_shot.tscn` -> `grid_occupied.png`).
- **Verified** - `py .claude/tools/doc_check.py`: 0 errors, 7 warnings (standing style backlog).
- **Assumed, not checked** - that `card_scale` 1.0 suits every OTHER screen (deck viewer, map, info
  card). Only the play area was looked at.

## The card effect API - a suite gate enforces it

A card modifier may NOT touch `Game`, `GameData` or `Board` directly - everything goes through
`CardEffectApi` as `CardModifier.api`, and a suite gate fails on any direct reference inside a
modifier. ⚠ **Extending the layer (with a `##` comment) is the sanctioned move** when a card
needs something it does not expose. See `design/card-effect-api/DESIGN.md`.
⚠ The gate matches the substring `"Board."`, so `BoardCoord` passes but `Board.locate_in_cell`
would trip it. The five `PipSuit` subclasses are gated; `PropModifier` is not.

## Gaps - thirteen filed, thirteen answered

`design/poker-patience/gaps/GAP-001..009` and `design/grid-view/gaps/GAP-010..013`. Answers are
quoted verbatim at the top of each and **outrank `PLAN.md` and `NAMES.md`, because they are newer.**
Still shaping upcoming work:

- **GAP-008** grab and place live on the ZONE TYPE cards. **GAP-009** the grid view REPLACES the
  play area and subsumes S19b.
- **GAP-010** the Entrance is pinned, x slaved, independently scrollable - **read before S20b.3**.
- **GAP-011**=(a) `BoardCoord` keeps one type and gained value affordances - **landed**.
- **GAP-012**=(c) panels publish their origin on `resized`; `slot_center_global` reads the cache.
  Owes a resized-followed test AND a by-eye check - a stale cache is silent.
- **GAP-013**=(a)+(c) the zone-only ratchet - **landed**; the layering-suite port is **deferred to
  immediately after S20b.2b**, because 25 of its assertions go through `slot_center_global`.

## Owner working agreements

- **Reuse, do not reinvent.** Verbatim: *"reducing duplicate code as much as possible and no
  reinventing existing setups, or using existing engine methods when available."* ⚠ Put it in
  every step brief - it reached nobody when it lived only in memory.
- **The light layer is out of scope.**
- **No design ids in product code** - not in a comment, not in an `@export_group` label. `Tests/` is
  exempt. This stream has added zero; keep it that way.
- **By-eye beats green.** The draw-order defect was found by the owner looking, not by 43 suites.

## Open bugs

- ⚠ **A SCORED GRID LINE FIRES NO PROPS.** Every suit's `spawn_props()` opens with
  `_spawn_origin()`, which reads the legacy `Vector3i` index; grid cells are absent from it
  (`game_data.gd` scans them into a SEPARATE `_grid_pos_index`), so it returns `Vector3i.MIN` and no
  spawner is built. **Unblocks at S20b.2b**, and `Tests/UI/test_ui_props.gd:1067` asserts the zero
  so it fails the day that lands.
  ⚠ Second layer: even fixed, the route builders call `get_zone_from_vec3`, which knows only the
  two legacy zones.
- ⚠ **Ten test files still assert against the legacy renderer and never touch a grid** - the
  ratchet in `test_game_headless.gd::ZONE_ONLY_TESTS` holds the list and stops it growing. An
  ACCEPTED RISK recorded in GAP-013, not a closed hole.
- ⚠ **`Tools/spotlight_tool.gd` traces no cascade.** PRE-EXISTING: `git log -S place_card_in_grid`
  on that file is empty - it has only ever used `move_data_to_coord` into the legacy lower zone.
  Resolves when the legacy coordinate retires at S20b.4.
- ⚠ **`Tests/Interaction/test_interaction.gd:459` is `check(true, ...)`** - a parked check that
  can never fail, unlike the props one which self-unparks. Restore it to assert `game.processing`
  once a placement is a paced, cancellable act.
- **`skill_scorer_cascade_lower.gd`** is an orphan in production (nothing references it) but is
  still constructed as a fixture in three suites. Archiving it is nobody's step yet.
- **The COMBO label draws over the End button** - seen in `grid_occupied.png`.
- **`PLAN.md` 1.1 and `TEST_PLAN.md` TP-02 state an arithmetically wrong example** - *"5 columns
  left of (grid 1, x 0) is (grid 0, x 4)"*. At width 5 it is ONE column left. The tests assert the
  correct behaviour; the design docs were left unedited.

## Next up

1. **`S20b.2b`** - the coordinate migration. Now unblocked: value semantics landed, and GAP-012
   settles how a grid cell's origin is derived. Unblocks props, the layering port, and S20b.3.
2. **The `test_visual_layers.gd` port to grids** (GAP-013 (c)) - immediately after, before S20b.4
   redoes the fixtures.
3. **`S20b.3` + `S20b.4`** - together, never separately (GAP-010).

Then `PLAN.md` 3 governs: `S21`-`S25` (the flipped board - **cards start stacking UPWARD**),
Phase 6, Phase 7. Phase 9 is the owner's call; Phase 10 is last.

### Opening prompt for the next session

```
Continue the poker-patience GRID VIEW as OVERSEER, using /plan-run.

WORKTREE: the gamedev-poker-patience worktree, branch `poker-patience`.
The repo's no-commit rule is REVERSED for you there: one commit per step whose done-when
YOU verified. Implementer subagents never commit, stage or stash.

READ IN THIS ORDER:
  1. solatro/HANDOFF_poker_patience.md - this file: state, traps, ledger, open bugs, next.
  2. solatro/design/poker-patience/PLAN.md section 3 (steps) and section 1 (contracts).
  3. solatro/design/grid-view/DESIGN.md - charts J, K, L, M, N, P.
  4. The gap files. THIRTEEN filed, ALL THIRTEEN answered; answers are quoted verbatim at
     the top of each and OUTRANK PLAN.md and NAMES.md. Read GAP-010 before the Entrance,
     GAP-011/012 before the coordinate, GAP-013 before writing any test.
  5. solatro/design/card-effect-api/DESIGN.md - modifiers reach the game ONLY through
     CardModifier.api, and a suite gate enforces it.

GROUND TRUTH BEFORE TRUSTING ANY `done`:
    GODOT_BIN="<godot 4.7.2 console exe>" py solatro/Tools/run_tests.py --timeout 400
  Expect ALL 43 SUITES, zero failures. Last verified 3475 CHECKS PASSED, tree clean.

THE WORK: S20b.2b (the coordinate migration) -> the test_visual_layers port -> S20b.3 and
S20b.4 together -> then PLAN.md section 3 (S21-S25, Phase 6, Phase 7).

NON-NEGOTIABLES, each of which caught a real defect on this stream:
  - RED-THEN-GREEN for every new test, and check the red failed the checks you EXPECTED.
    Do the red runs YOURSELF; never accept a self-reported green.
  - VERIFY VISUALS BY EYE. Tests/Visual/grid_layer_shot.tscn shows a POPULATED grid;
    reveal_shot.tscn shows an empty one. A green suite is not evidence about pixels - the
    owner found a card drawing behind its own cell that 43 green suites did not.
  - CHECK THE SUITE COUNT, not just the failure set. A parse error drops a whole suite
    silently while the banner still reads plausibly.
  - CHECK THE LOG'S MTIME, and read logs/test/test_output_all.log - a stale file of the
    same name sits one directory up and greps clean.
  - AT EVERY PHASE BOUNDARY: read the diff, run an adversarial pass tracing what a PLAYER
    does, and run `py .claude/tools/doc_check.py`.
  - Every step brief names THE CALL SITE. Never accept `done` on a component whose
    consumer does not exist.
  - REUSE, don't reinvent (owner's standing instruction).
  - Subagents exhaust their turns on a whole step. Split them: the agent does production
    code plus the mechanical tests; YOU write the gate and intricate tests and run every
    red-then-green.

If you hit a decision no document fixes: file a gap at solatro/design/<slug>/gaps/GAP-NNN.md
following GAP-001's shape, park that thread, keep the unaffected ones moving, and QUOTE the
gap's own option text to the owner. A bug is not a gap: if exactly one choice is defensible
it is a defect - fix it and record it.
```

## References

- `design/poker-patience/PLAN.md` - the steps; section 1 the normative contracts.
- `design/poker-patience/DESIGN.md` - the authority on the game's behaviour.
- `design/grid-view/DESIGN.md` - the view's design, its answers and its six charts.
- `design/poker-patience/TEST_PLAN.md` and `NAMES.md` - every planned test; every identifier.
- `ARCHITECTURE_REVIEW.md` - the engine's contracts (undo, pending-action replay, layering).
