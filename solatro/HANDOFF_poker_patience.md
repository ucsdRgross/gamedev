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
# ─── LANDED. Evidence is in the commit messages; forensics are in the gap files. ───
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
    ⚠ The runaway guard (act_event_cap, MAX_TICKS) is CORRECTNESS-critical — there is no
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
  description: 'The combo model; MAX_SUBMITS, submits_used, score_additive and the patience family retired.'
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
    save_state() is called LAST in place_card_in_grid — the scores live on `state`, so an earlier
    snapshot rewinds the board without rewinding what it scored. Guarded on `not processing` so an
    effect's placement stays part of the act that caused it.
- id: S36
  description: 'pending_action carries a placement (Entrance SLOT + coord) and replays it.'
  status: done
  notes: >
    Board.place_in_cell now LIFTS the card out of the zone column it came from, as one mutation
    with the append — the mechanical half GAP-008 named.
- id: S37
  description: 'validate() grid aliasing invariants; headless/viewed parity gate.'
  status: done
- id: S37b
  description: 'The closing pass: adversarial review, /simplify, /docs.'
  status: done
- id: S19b
  description: 'The legacy coordinate migration — SUPERSEDED, folded into S20b by GAP-009.'
  status: superseded
- id: S20
  description: 'CARD_SEPARATION re-derived from the measured bottom-edge pip offset.'
  status: done
  notes: 'TP-80 derives it from card_visual.tscn rather than asserting 16, so an art pass cannot drift it.'
- id: S20b1
  description: 'The grid view: %GridContainer, one GridPanel per grid, a CellSlot per cell.'
  status: done
  notes: 'New GRID LAYOUT suite (TP-80b, TP-80c, TP-80g, TP-80k). Verified by eye.'
- id: S20b2
  description: 'Old zone frame on cells; grid on top; Entrance on the bottom, aligned; scroll anchored bottom.'
  status: done
  notes: 'card_scale 2.5 -> 1 landed with it, so the whole board fits the window.'

# ─── PENDING ───
- id: S20b2b0
  description: >
    VALUE SEMANTICS FIRST (GAP-011=a). BoardCoord gains equals(), pack() -> Vector4i and
    is_nowhere(); cell_type_coord and Board.locate_in_cell stop returning null and return NOWHERE.
    Purely additive -- no Vector3i is swapped in this step.
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    ⚠ THIS DID NOT EXIST IN THE PLAN. It is required because BoardCoord extends RefCounted and
    defines no equality: `==` is IDENTITY, and GDScript has no operator overloading, so a mechanical
    swap breaks ~30 `== Vector3i.MIN` guards silently and makes game.gd's `full.find(coord)` return
    the whole row. game_data.gd:241-243 already documents the problem and keys on Vector4i.
    ⚠ It also OWES a source-scanning gate failing on ==/!= against a BoardCoord -- without it,
    (a) is strictly worse than the rejected (b). Additive now = provable; after the swap = not.
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
    ⚠ THE "EIGHT PRODUCT CALL SITES" NUMBER WAS WRONG and the low number is the dangerous half.
    slot_center_global has TWO real product calls (prop_layer.gd:280, :539); the rest are comments.
    The thing actually migrating is the legacy Vector3i board position: 148 refs across 29 product
    files -- the five route builders in game.gd AND their CardEffectApi mirrors, PropData.at,
    PropVisual.anchor_coord, pip_suit.gd::_spawn_origin and its five suit subclasses, the prop-effect
    write-backs. DESIGN.md 1e is corrected.
    ⚠ The 58 test refs are NOT a mechanical swap: all 58 are in test_ui_props.gd (33) and
    test_visual_layers.gd (25), whose fixtures have NO GridData, so no BoardCoord names their slots.
    They move with S20b.4.
    ⚠ GAP-012=(c): panels PUBLISH their origin on `resized` and slot_center_global reads the cache,
    so the every-frame anchor path does no tree reads. Owes a resized-followed test AND a by-eye
    check -- a stale cache is silent. REUSE LineGeometry._row for the route (it is already
    within-one-grid and left-to-right); do not write new geometry.
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
    ⚠ ATTEMPTED TWICE, BACKED OUT TWICE. READ design/grid-view/gaps/GAP-010.md BEFORE THE THIRD —
    it carries the full forensics. Short version: it WORKS by eye and the fixture rebuild WORKS (32
    failures -> 1). What defeats it is that pinning the Entrance while the legacy zones AND the
    legacy coordinate are still present gives the board THREE renderers and TWO draw layers, and
    every pooled-control, deferred-add and settings-rebuild path must be right for all of them at
    once — 1041 engine errors, a new seam each time one closed. LAND IT AFTER b.2b AND WITH b.4.
- id: S20b4
  description: 'Delete lower_zone and the legacy zone rendering; rebuild the fixtures onto grids.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    ⚠ THE FIXTURES GO ON A GRID, NOT THE LOWER ZONE. An interim redirect put test boards in the
    legacy lower zone, which draws in the band BETWEEN the grid and the Entrance — owner: "cards in
    random locations not on top of any zones". They are on a zone, but an invisible one.
    ⚠ Moving a fixture is only half: a prop's own `p.at` names a zone too, and redirecting one
    without the other converges on nothing.
- id: S20c
  description: 'Retire the act: Game.submit, _perform_submit, the on_run_scorer branch, the Next button.'
  files_touched: [Levels/game.gd, Levels/game_view.gd, Levels/game_view.tscn, Scripts/run_state.gd,
    Tools/spotlight_tool.gd, Tests/Engine/test_game_headless.gd, Tests/Interaction/test_interaction.gd,
    Tests/E2E/test_e2e_run.gd, Tests/Engine/test_leak_canary.gd]
  verification_command: 'py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: done
  evidence: 'ALL 43 SUITES: 3440 CHECKS PASSED, zero failures. grep: zero readers of
    submit/_perform_submit/next_button in product code. doc_check 0 errors.'
  notes: >
    Q31=(b); chart P3/P4. ⚠ Game.next()/_perform_next() STAY -- the plan retires the BUTTON, and
    _perform_next still serves the &"on_next" replay. TP-80j and TP-80i are new, both red-then-green
    verified by the overseer (RED hit "a refill does not resolve the show -- show_ended=true" and
    the gate naming play_area.gd:353 respectively). Touchscreen coverage was RESTORED, not accepted
    as lost: removing the Next button orphaned test_interaction's touch_tap() and left a section
    headed "EVERY INPUT MODE" with no touch. ⚠ The new touch test must run AFTER the mouse tests --
    a touch leaves no HOVER and the mouse selection path needs one.
```

After `S20c`, `PLAN.md` §3 governs: `S21`–`S25` (the flipped board — **this is where cards start
stacking UPWARD**), Phase 6 (zoom, pan, focus), Phase 7 (the wall), Phase 9 (goal-curve refit,
owner's call), Phase 10 (documentation).

## Verified vs assumed

- **Verified** — `ALL 43 SUITES: 3431 CHECKS PASSED`, tree clean, by the command in Environment.
- **Verified by eye** — the grid board draws: 5×5 of empty zone slots on top, the Entrance's five
  dealt cards along the bottom, each under its column (`reveal_shot`, `00_closed.png`).
- **Verified** — `py .claude/tools/doc_check.py`: 0 errors, 8 warnings (the standing style backlog).
- **Verified** — `npm --prefix designloop run check -- solatro/grid-view`: 0 errors, 0 warnings,
  0 stale, 0 dag-audit defects.
- **Assumed, not checked** — that `card_scale` 1.0 suits every OTHER screen (deck viewer, map, info
  card). Only the play area was looked at.

## The card effect API — a suite gate enforces it

A card modifier may NOT touch `Game`, `GameData` or `Board` directly — everything goes through
`CardEffectApi` as `CardModifier.api`, and a suite gate fails on any direct reference inside a
modifier. ⚠ **Extending the layer (with a `##` comment) is the sanctioned move** when a card needs
something it does not expose. See `design/card-effect-api/DESIGN.md`.

## Gaps — ten filed, ten answered

`design/poker-patience/gaps/GAP-001..009` and `design/grid-view/gaps/GAP-010`. Answers are quoted
verbatim at the top of each file and **outrank `PLAN.md` and `NAMES.md`, because they are newer.**
The three that still shape upcoming work: **GAP-008** (grab and place live on the ZONE TYPE cards,
not on rules-deck cards), **GAP-009** (the grid view REPLACES the play area, and subsumes S19b), and
**GAP-010** (the Entrance is pinned, x slaved, independently scrollable — read before `S20b.3`).

## Owner working agreements

- **Reuse, do not reinvent.** Verbatim: *"reducing duplicate code as much as possible and no
  reinventing existing setups, or using existing engine methods when available."* ⚠ Put it in every
  step brief — it reached nobody when it lived only in memory.
- **The light layer is out of scope.** Verbatim: *"light is out of scope as you assumed, and what
  you describe does not even seem like a bug but a possible test measuring too early."*
- **No design ids in product code** — not in a comment, not in an `@export_group` label. `Tests/` is
  exempt. This stream added zero; keep it that way.

## Open bugs

- ⚠ **A SCORED GRID LINE FIRES NO PROPS.** Every suit's `spawn_props()` opens with `_spawn_origin()`,
  which reads the legacy `Vector3i` index; grid cells are absent from it, so it returns
  `Vector3i.MIN` and no spawner is ever built. Points bank correctly; nothing flies. **Unblocks at
  `S20b.2b`**, and `Tests/UI/test_ui_props.gd` asserts the zero so it fails the day that lands.
- ⚠ **Two parked checks**, each asserted so it FAILS when its blocker lands rather than rotting: the
  props one above, and `INTERACTION`'s "no act on a grid board outlives two frames" (same root).
- ⚠ **`.claude/memory/machine-profiles.md` records Godot 4.7.1**; the box has 4.7.2. Memory file,
  outside this stream's scope.
- **`PLAN.md` §1.1 and `TEST_PLAN.md` TP-02 state an arithmetically wrong example** — *"5 columns
  left of (grid 1, x 0) is (grid 0, x 4)"*. At width 5 it is ONE column left. Both cases are
  asserted in the tests; the design docs were left unedited.

## Next up

1. **`S20b.2b`** — the coordinate migration. Unblocks props, `S20b.3` and the fixture rebuild.
2. **`S20b.3` + `S20b.4`** — together, never separately (GAP-010).
3. **`S20c`** — retire the act.

Below is the opening prompt for the next session. It assumes `/plan-run` — an overseer that holds
the plan and never reads code, plus implementer subagents that hold the code and never hold the plan.

```
Continue the poker-patience GRID VIEW as OVERSEER, using /plan-run.

WORKTREE: C:\Users\khanr\Documents\GitHub\gamedev-poker-patience  (branch `poker-patience`)
The repo's no-commit rule is REVERSED for you on this branch: commit after every step whose
done-when YOU verified, one step per commit. Commits are the only rollback points and a long
run loses sessions to API limits. Implementer subagents never commit, stage or stash.

START HERE, in this order:
  1. solatro/HANDOFF_poker_patience.md — the live ledger, self-contained, ~330 lines. It
     carries the state, the environment traps, the ledger, the open bugs and what is next.
  2. solatro/design/poker-patience/PLAN.md §3 (the steps) and §1 (normative contracts).
  3. solatro/design/grid-view/DESIGN.md — the VIEW's own design: 41 answered questions and
     six confirmed charts (J building, K the cell and row band, L the Entrance, M the
     coordinate seam, N focus and input, P what is retired). Its steps live in PLAN.md as
     S20b/S20c; there is deliberately no separate plan under design/grid-view/.
  4. The gap files. TEN are filed and ALL TEN are answered; the answers are quoted verbatim
     at the top of each and OUTRANK PLAN.md and NAMES.md because they are newer.
     ⚠ Read design/grid-view/gaps/GAP-010.md BEFORE touching the Entrance.
  5. solatro/design/card-effect-api/DESIGN.md — a card modifier may NOT touch Game, GameData
     or Board directly; everything goes through CardEffectApi as CardModifier.api, and a
     suite gate ENFORCES it. Extending the layer (with a ## comment) is the sanctioned move.

GROUND TRUTH BEFORE TRUSTING ANY `done`:
    cd C:\Users\khanr\Documents\GitHub\gamedev-poker-patience
    GODOT_BIN="C:/Users/khanr/Desktop/Godot_v4.7.2-stable_win64_console.exe" py solatro/Tools/run_tests.py --timeout 400
  Expect ALL 43 SUITES, zero failures. Last verified: 3442 CHECKS PASSED at commit d9ad559,
  tree clean, 0 script errors, 0 engine errors.

THE WORK, in this order:
  S20b.2b — THE COORDINATE MIGRATION, and do it first: S20b.3, S20b.4 and the test-fixture
        rebuild all depend on it. slot_center_global takes a BoardCoord and nothing else; the
        legacy Vector3i board position retires; the prop routes follow it (a row's route is
        that row's cells IN ONE GRID, left to right — chart M5/M6). Product surface is EIGHT
        call sites; the other 58 references are tests and move mechanically. This is what
        makes a scored grid line fire props again.
  S20b.3 + S20b.4 — TOGETHER, never separately. Pin the Entrance outside the board's scroll
        with its own layer and its own vertical scroll, x slaved to the board; delete
        lower_zone and the legacy zone rendering; rebuild the fixtures ONTO GRIDS.
        ⚠ S20b.3 has been attempted twice and backed out twice. GAP-010 records why.
  S20c — retire the act: Game.submit, _perform_submit and the Next button.
  Then PLAN.md §3 governs: S21-S25 (the flipped board — where cards start stacking UPWARD),
  Phase 6, Phase 7. Phase 9 is the owner's call; Phase 10 is last.

ENVIRONMENT TRAPS — all in the handoff, and each cost real time:
  - Godot here is 4.7.2; machine-profiles.md says 4.7.1 and is STALE.
  - A new `class_name` referenced from an existing script HANGS the suite rather than failing
    to parse. Fix: `--headless --path . --import`. Always pass --timeout so a hang fails fast.
  - `export PYTHONIOENCODING=utf-8` before any python heredoc, or the console encoding kills
    the script MID-EDIT and leaves a source file half-written.
  - ⚠ CHECK THE LOG'S MTIME. godot.log is overwritten by whichever process wrote last,
    including your own runs.
  - ⚠ A banner reading "N FAILED (0 behavior, 0 implementation)" is NOT a check failure — it
    is an unexpected engine error. Read the newest log's backtrace. This run hit 1041 of them.

NON-NEGOTIABLES that caught real defects on this stream:
  - RED-THEN-GREEN for every new test, and check the red run failed the checks you EXPECTED.
    Do the red runs YOURSELF; never accept a self-reported green.
  - VERIFY VISUALS BY EYE. Render `res://Tests/Visual/reveal_shot.tscn` and LOOK at the PNG.
    A green test is not evidence about pixels — and looking is what found the End button that
    never ended the show, the HUD stuck at zero, and a "PATIENCE 3/3" label no grep could see.
  - AT EVERY PHASE BOUNDARY: read the diff, run an adversarial review tracing what a PLAYER
    does, and run `py .claude/tools/doc_check.py --changed`. The adversarial pass has the
    highest yield of anything here.
  - Every step brief names THE CALL SITE — "what calls this, and what breaks if it is
    deleted?" Never accept `done` on a component whose consumer does not exist.
  - Call check_all_tests_registered() from a new suite's _ready, and name tests `run_*_test` —
    the gate only recognises that form. Check the SUITE COUNT: a suite that fails to compile
    silently drops out. Judge by the failure SET, never the check total.
  - NO design ids (Q123, GAP-004, step ids) in product code, including @export_group labels.
    Tests/ is exempt. This stream added zero; keep it that way.
  - REUSE, don't reinvent (owner's standing instruction) — search for an existing helper first.
  - Subagents reliably exhaust their turns on a whole step. Split them: the agent does
    production code plus the mechanical tests; YOU write the intricate/gate tests and run all
    red-then-green. Never leave a step half-applied.

If you hit a decision no document fixes: file a gap at solatro/design/<slug>/gaps/GAP-NNN.md
following GAP-001's shape, lettered options in questionnaire grammar. Park that thread, keep
working the unaffected ones, tell the owner — and QUOTE the gap's own option text when you do.
A bug is not a gap: if exactly one choice is defensible it is a defect, so fix it and record it.
Do NOT resolve a gap by picking an answer.

Use /handoff to keep the ledger current — and PRUNE it; it is capped at ~300 lines.
```

## References

- `design/poker-patience/PLAN.md` — the steps, and §1 the normative contracts.
- `design/poker-patience/DESIGN.md` — the authority on the game's behaviour.
- `design/grid-view/DESIGN.md` — the view's design, its answers and its six charts.
- `design/poker-patience/{TEST_PLAN.md,NAMES.md}` — every planned test; every identifier.
- `ARCHITECTURE_REVIEW.md` — the engine's own contracts (undo, pending-action replay, layering).
