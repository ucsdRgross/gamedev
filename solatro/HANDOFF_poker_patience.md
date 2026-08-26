# HANDOFF — poker patience, Phases 1-4 and 8

**Goal:** Implement `design/poker-patience/PLAN.md` steps S1–S19 (Phases 1–4) and S35–S37
(Phase 8), stopping at S37. Phases 5–7 (visual), 9 and 10 are out of scope for this run.
**State:** Baseline repaired and green. Worktree `gamedev-poker-patience` on branch
`poker-patience`. No plan step landed yet.
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
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-01..TP-04 green.'

- id: S2
  description: >
    GameData grid storage: GridData, the grid list, per-grid cell arrays, 25 cell zone
    cards per grid.
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-05..TP-07 green; validate() empty on a 3-grid fixture at mixed heights.'

- id: S3
  description: 'Position index and _scan_positions() extended to grids, plus the reverse index.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Done-when: TP-08, TP-09 green. The reverse index is a second representation of one fact -
    it needs a stated invariant tying it to the forward index, and validate() must check it.

- id: S4
  description: 'Board mutation API for grid cells: place, move, remove-with-compaction.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Done-when: TP-10..TP-14 green. is_compaction is set BY THE MOVER, never inferred from
    before/after heights. A compaction bumps revision ONCE for the whole compaction.

- id: S5
  description: 'CardDataIterator and get_card_collections() for grids; the early stop REMOVED.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Done-when: TP-15..TP-17 green. TP-17 is the gate - a SPARSE grid, cards only in row 3,
    must be walked completely. Neutralise by restoring the early stop and watch it fail.

- id: S6
  description: 'Line enumeration: ROW, COL, DIAG, HEIGHT_V through a given cell, within one grid.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-18..TP-24 green.'

- id: S7
  description: 'ScoringSection gains kind and line_key; score_line loses is_row/zone/index.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-25..TP-27 green; grep proves no caller passes the old signature.'

- id: S8
  description: 'The mutation broadcast, the compaction flag, and the board lock.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-28..TP-31 green.'

- id: S9
  description: 'The detector card: enumerate, score, re-scan until nothing new completes.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Done-when: TP-32..TP-36 green. The runaway guard (act_event_cap, MAX_TICKS) is
    CORRECTNESS-critical - there is no line-scored memory and no within-pass guard, so a
    remove-and-replace effect re-scores forever without it. Do not tune it away. TP-36 must
    assert it re-scores each cycle AND that the guard is what stops it.

- id: S10
  description: 'Wire the section into Scoring.PokerHands.score() and the spotlight cascade, unchanged.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-37..TP-39 green.'

- id: S11
  description: 'Height scoring: multiples of 5, whole stack, drops never score.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Done-when: TP-40..TP-46 green. TP-46 is the phase gate: build FIX-FULL-15 card by card,
    compare the completed-line SET against an enumerator written INDEPENDENTLY in the test,
    never the code under test. Build at height 3 and 5 ceilings first.

- id: S12
  description: 'The three buckets per grid and their storage, pack/unpack, duplicate_state() copy.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-47..TP-50 green.'

- id: S13
  description: 'grid_score as the product of positive buckets; board_total as their sum.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Done-when: TP-51..TP-56 green. TP-51 reproduces the owner's worked example exactly:
    0+0+0 then 10 then 50 then 100. TP-54: a bucket whose VALUE is 0 is excluded from the
    product even when its line completed - the test is the VALUE, never touched-ness.

- id: S14
  description: >
    The combo model, and the retirement of MAX_SUBMITS, submits_used, score_additive,
    duplicate_class_scale and the patience family.
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Done-when: TP-57..TP-61 green; grep proves each retired identifier has zero readers.
    submits_used lives on GameData specifically so undo rewinds it - removing it touches
    undo, resume, RunState and test_persistence_fuzz. Deliberately, not incidentally.

- id: S15
  description: 'The meta allotment card (SkillGridAllotment).'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-62..TP-65 green. Frame 11.'

- id: S16
  description: 'The grid creator card (SkillGridCreator).'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-66..TP-69 green. Frame 12.'

- id: S17
  description: 'TypeInput with on_next removed, and the left-to-right refill.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-70..TP-74 green. Do NOT add an Entrance width property.'

- id: S18
  description: 'Commit, silent commitment, and the lift when no legal placement remains.'
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-75..TP-78 green.'

- id: S19
  description: >
    Move the tableau cards to the archive directory, add the archive rules builder, remove
    them from rules1, move their tests out of the suite.
  files_touched: []
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    Done-when: TP-79 green; suite count drops by exactly the moved suites and NO other
    suite changes.

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

## Open bugs

- `.claude/memory/machine-profiles.md` records Godot 4.7.1 for Box A; the box has 4.7.2 and
  no 4.7.1. Anything reading that path fails with `FileNotFoundError`. Not fixed here — it
  is a memory file, outside this run's scope.

## Files touched

```
solatro/Cards/card_visual.tscn   (S0-repair, committed b416d37)
```

## Next up

1. S1 — `BoardCoord` and its arithmetic (TP-01..TP-04).
2. S2 — `GridData` and `GameData.grids` (TP-05..TP-07).
3. S3 — the position index over grids, forward and reverse (TP-08, TP-09).

Opening prompt for the next agent:

> Resume `solatro/HANDOFF_poker_patience.md` in the `gamedev-poker-patience` worktree on
> branch `poker-patience`. Read that file, then `design/poker-patience/PLAN.md` §1
> (normative), `TEST_PLAN.md` and `NAMES.md`. Run the suite to confirm the tree is green
> before trusting any `done`. Continue from the first `pending` task. Commit one step per
> verified done-when — the repo's no-commit rule is REVERSED on this branch.

## References

- `design/poker-patience/PLAN.md` — the steps, and §1 the normative contracts.
- `design/poker-patience/DESIGN.md` — the authority on behaviour.
- `design/poker-patience/TEST_PLAN.md` — every test that must exist, fixtures fixed in advance.
- `design/poker-patience/NAMES.md` — every identifier, and the claimed art frames 9–13.
