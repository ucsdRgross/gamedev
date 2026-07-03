# HANDOFF — Solatro audit & refactor sessions (2026-07-01 → 2026-07-02)

Context + open tasks only. Details live in the referenced docs; findings there are
checkbox-tracked ([x] done, [~] declined/mitigated, [ ] open).

## Reference documents
- `ARCHITECTURE_REVIEW.md` — main audit (B/S/D/E/N items), §5 board/move redesign + status
- `SCORING_AUDIT.md` — scoring.gd audit (SC/SD/SE/G/SA items) + status addenda
- `UNIT_TESTS_PLAN.md` — test plan; per-suite DONE markers show what exists
- `STATUS_EFFECTS_PLAN.md` — per-card stackable status effects design (NOT implemented)
- `Scripts/board.gd` header — **MUTATION GUIDELINES** (the desync-prevention contract)

## Current architecture (post-refactor)
- All board mutations go through `Board` (anchor-based `move_stack` with error codes,
  `place_card`, `add_column`/`remove_column`) or Game's draw/discard/deck functions.
- Every mutation bumps `GameData.revision` AFTER the state is consistent. The bump:
  (a) emits `board_changed` → Game relays → `PlayArea.queue_rebuild()` (coalesced to one
  rebuild per frame via call_deferred; NO per-frame processing remains),
  (b) keys the SE1 compare-mod implementer cache in `CardEnvironment`.
- PlayArea rule: anything reading `ui_data`/`data_ui`/`data_card`/control tree calls
  `flush_rebuild()` first. All current readers do.
- Dispatch (`run_all_mods`, `return_first_*`, `skill_active_check`) is INSTANCE-based on
  `CardEnvironment`; `CURRENT` is only the "environment on screen" pointer (mod
  accessors, PipComparator boundary, UI).
- `GameData.validate()` (invariants I1–I5) runs after moves/undo in debug builds via
  `Game.debug_validate` — warnings are bugs.
- Undo snapshots use `duplicate_deep(DEEP_DUPLICATE_ALL)`; BigNumber (RefCounted) arrays
  copied manually. Snapshots share nothing with live state (tested).

## Test scenes (run all after touching Scripts/, Cards/, Levels/)
`Tests/`: tests.tscn (scoring), test_board.tscn, test_iterator.tscn,
test_comparator.tscn, test_dispatch.tscn, test_fuzz.tscn (seeded; set `fuzz_seed`
from a failure printout to reproduce). No CI — running them is a manual habit.

## Known intentional decisions (do not "fix")
- B10: CardDataIterator iterates LIVE collections (pinned in test_iterator §3).
- S6: same-value `stage_changed` re-emits are relied upon — no setter guard.
- N8: score-array size desync allowed (scores never shrink) — validate only flags
  too-small `scores_col`.
- D7: commented-out code is kept as reference.
- Player drops move with `trigger_mods = false` → `on_card_dropped_on`/`on_stack_cards`
  fire ONLY from automated moves (TypeInput). Confirm intentional before building
  content around player-drop triggers.

## Open tasks (rough priority)
1. **F3 dispatch-chaos fuzz + trigger-depth cap** — DoubleTrigger × EchoingTrigger
   mutual `on_trigger` has never been exercised together; most likely infinite loop in
   the codebase. See UNIT_TESTS_PLAN §8 F3; consider a max-invocations guard in
   `on_mod_triggered`.
2. **G3–G5 table tests** (ScoreModel.final_score matrix, get_loc_name, _compare_results
   ordering chain) — the tuning constants are only covered indirectly today.
3. **Status effects** — implement per STATUS_EFFECTS_PLAN.md (note: `CardData.statuses`
   is currently `Dictionary[String,int]`, plan assumed an array of modifiers — reconcile
   first). Remember: attaching a status to an in-play card must bump `state.revision`
   (Board guideline #3).
4. **Remaining §5 steps** (ARCHITECTURE_REVIEW): position index (5.4, only if profiling
   demands it), delete the Vector3i `move_data_to_coord` adapters once callers migrate.
5. **F2 move/undo interleave fuzz** (UNIT_TESTS_PLAN §8) — undo separation is tested
   directly but not fuzzed.
6. **Small/cosmetic:** SE4 single-walk wrap scan; SD6 exact-name leaderboard asserts;
   test_scoring section renumbering; migrate test_scoring to TestFactories; cap
   `save_history` growth (full deep copy per action, unbounded); a combined test-runner
   scene that instances all six suites.
7. **B10-adjacent hardening** (only if it ever bites): mods that mutate collections
   mid-dispatch are pinned as live-iteration; F3 will tell you if that needs a snapshot.

## Sharp edges to remember
- `stage` does triple duty: logical location, animation origin (`previous_stage`), S6
  re-emit channel. Re-setting an already-correct stage clobbers `previous_stage` and
  kills spawn/tween animations (bit us twice: z_dist swap fix, place_card draw-anim fix).
- First-implementer-wins mod dispatch precedence depends on board order — moving an
  unrelated card can change which of two comparator mods wins. Fine at 0–1 implementers.
- GDScript: declaration-default values BYPASS property setters (initial `state` signals
  must be wired in `_ready`; this caused the blank-board bug).
- A missed revision bump = stuck UI (visible) + stale compare cache (silent). If a card
  visual ever sticks, find the mutation path that forgot to bump.
