# Unit Test Plan

Derived from ARCHITECTURE_REVIEW.md (incl. §5 move-logic redesign), SCORING_AUDIT.md, and
STATUS_EFFECTS_PLAN.md. Goal: every confirmed/suspected bug gets a regression test, every
invariant gets a property test, and chaos/fuzz suites guard the areas where enumeration
can't cover the state space.

Conventions (follow `Tests/test_scoring.gd`'s existing style):
- Non-freezing `check(ok, ctx, detail)` helpers; never `assert()`.
- **`await` every coroutine test function** (regression for SCORING_AUDIT SC1).
- Pure-logic tests (Board, comparator, GameData, iterator) must not need a scene tree —
  this depends on review §5.5 (Board extraction) and a fake environment (see T-ENV).
- Fuzz tests take a `seed` param, print it on failure, and re-run deterministically:
  `seed(reported_seed)` must reproduce. Default N iterations low in CI-style runs (100),
  cranked manually (10k) when hunting.
- Shared factories: reuse `m_card/m_stone/uc/add_noise` from test_scoring.gd — move them
  to `Tests/test_factories.gd` so every suite imports one copy.

### T-ENV. Test harness prerequisite: FakeEnvironment

A `CardEnvironment` subclass for tests: constructor takes explicit collections;
`get_card_collections()` / `get_rules_collections()` return them. Unblocks: dispatch
tests, comparator-mod tests (SCORING_AUDIT G1), TypeInput/ZoneAdder tests — all currently
untestable because mods reach for `CardEnvironment.CURRENT`. If review's environment
accessor refactor lands (see "context object" note in ARCHITECTURE_REVIEW), inject the
fake through that instead of the static.

---

## 1. Board / move logic (`Tests/test_board.gd`) — HIGHEST VALUE

Precondition: review §5 `Board` class + `Board.validate()` (invariants I1–I5). Every test
below ends with `check(board.validate())` — that's half the coverage for free.

### 1.1 `locate` / `find_data_vec3` (review B4, B5, E4)
- [ ] card in upper zone col c row r → (0,c,r); lower → (1,c,r); exact `Vector3i` type.
- [ ] zone-type header cards → z == -1 form, both zones.
- [ ] card in draw/discard/rules → NOT_FOUND from `locate` (they're not board positions).
- [ ] card in NO collection → NOT_FOUND (`Vector3i.MIN` today).
- [ ] **B4 regression:** upper_zone has MORE columns than upper_zone_type (and vice versa)
      → locate still finds cards in every column, no crash.
- [ ] after any move: position-index result == full-rescan result (I4), for every card.

### 1.2 `find_vec3_data` / `is_data_topmost` (review S2)
- [ ] out-of-range col, out-of-range row, negative row → null, no error (S2 verification).
- [ ] topmost: last card of column true; middle card false; zone header with empty column
      true; zone header with non-empty column false; card not on board false.
- [ ] upper-zone header topmost check (current code only checks `lower_zone_type`,
      [game.gd:209](Levels/game.gd:209) — this test documents/fixes that asymmetry).

### 1.3 `move_stack` matrix (review S3 — the core suite)

Fixture: two zones, 3 columns each, columns of sizes {0, 1, 4}. For EVERY case check:
resulting column contents exact, all other columns untouched, `validate()` passes, and
the returned error code.

Cross-column:
- [ ] single card onto top of another column; onto empty column (ColumnEnd); onto zone
      header of empty column.
- [ ] stack of 3 onto another column — order preserved.
- [ ] whole column (`count = -1`) onto another column; source column left empty but present.
- [ ] upper → lower and lower → upper (fires `on_card_dropped_on` only for upper→lower —
      assert via spy mod).
Same-column (the S3 danger zone — enumerate ALL of these):
- [ ] move card DOWN within column (src.row < dest position).
- [ ] move card UP within column (src.row > dest position).
- [ ] move onto the card directly beneath itself → OK_NOOP, no events, board unchanged.
- [ ] move onto itself → error (or no-op; pin the chosen policy).
- [ ] dest anchor inside the moving stack → ERR_DEST_INSIDE_STACK, board unchanged
      (replaces today's silent clamp — this test pins the policy change).
- [ ] `count` larger than cards available below src → clamped to remainder.
- [ ] `count = -1` within same column, moving middle-to-top.
Degenerate:
- [ ] moving card not on board → error, board unchanged.
- [ ] dest anchor card not on board → error, board unchanged.
- [ ] move from a 1-card column (column empties; header remains; is_data_topmost(header)
      flips to true).
- [ ] `count = 0` → error or no-op (pin it).
- [ ] ColumnStart insert (TypeInput "under everything" path) with occupied and empty column.

### 1.4 Events (Phase 4 contract)
- [ ] spy mod records `on_card_dropped_on(onto, stack)`: `onto` == the anchor card
      (non-null when dropping onto a card — regression for the pre-move-index null at
      [game.gd:142](Levels/game.gd:142)); == null/header when dropping on empty column.
- [ ] spy asserts board `validate()` passes AT THE TIME the hook fires (Phase 3 before 4).
- [ ] `trigger_mods = false` → zero hooks fired.
- [ ] rejected move → zero hooks fired.

### 1.5 Draw / discard / shuffle
- [ ] `draw_card` on non-empty deck: returns last card, stage → PLAY, deck shrinks (I1).
- [ ] `draw_card` on empty deck → null, no error.
- [ ] `discard_data`: removed from its column, appended to discard, stage DISCARD,
      `on_discard` fired BEFORE removal (pin current order or change it — it currently
      fires before the card leaves the board, which mods may rely on).
- [ ] discard a card that's mid-stack → cards above it shift down correctly (validate()).
- [ ] `shuffle_deck` with a seeded RNG: same seed → same order; `on_append` fired once per
      card in final order; deck size preserved.
- [ ] shuffle with an `on_append`-reordering mod (Heavy-card style: move to front) →
      resulting order respects the mod, size preserved, no duplicates (I1).

### 1.6 Undo / `duplicate_state` (review B11 — regression-critical)
- [ ] snapshot → mutate scores + move cards → undo → all GameData fields equal snapshot
      (field-by-field, incl. BigNumber mantissa/exponent).
- [ ] **B11 regression:** after `duplicate_state()`, for every card in the copy:
      `card.skill.data == card`, `card.type.data == card`, `card.stamp.data == card`
      (and `statuses[i].data == card` once statuses land).
- [ ] mod-internal refs rebound: `ZoneAdder.card_data`, `SkillEchoingTrigger.triggered`
      entries point into the COPY's cards, not the original's.
- [ ] undo after zone add/remove (ZoneAdder active↔inactive across the snapshot) restores
      column count AND zone_type count (I2).
- [ ] double-undo to same state, then redo-by-replay → no shared mutable objects between
      history entries (mutate current, assert history entry unchanged).

## 2. CardDataIterator (`Tests/test_iterator.gd`) (review B10, E9)

Oracle: naive flatten (loop collections, loop columns, ROW-major for 2D) — every test
compares iterator output list to oracle.
- [ ] empty collections list; all-empty collections; single empty Array[CardData].
- [ ] 1D arrays only; 2D only; mixed; null collection entries skipped.
- [ ] ragged 2D: column sizes {0, 3, 1, 0, 2} — row-major order matches oracle exactly.
- [ ] 2D with ALL columns empty (the `is_row_empty` break path).
- [ ] unrecognized collection type entries skipped without error.
- [ ] iterator is re-usable: two full passes over same instance give same result.
- [ ] **B10 pin:** document current behavior under mutation — build a mod that discards
      the next card during iteration; assert the chosen contract (after the snapshot fix:
      iteration sees the pre-mutation snapshot, exactly once each).

## 3. Dispatch / CardEnvironment (`Tests/test_dispatch.gd`) (review B10, E1, D1)

Uses T-ENV FakeEnvironment + spy modifiers that record `(hook, args, call_order)`.
- [ ] `run_all_mods("on_x")` calls type, stamp, then skill per card, in iterator order.
- [ ] skill called only when `active`; type/stamp called regardless.
- [ ] hook not implemented → not called, no error (has_method gate).
- [ ] `on_anything` fires exactly once after any other hook; `run_all_mods("on_anything")`
      does NOT recurse.
- [ ] `skill_active_check`: activation edge fires `on_active` once (not per check);
      deactivation fires `on_deactive`; no-change fires neither; a skill whose
      `is_active()` flips DURING the check doesn't infinite-loop.
- [ ] `return_first_compare_mod_result`: first implementing mod wins, later mods NOT
      called (spy call counts); no implementers → NAN.
- [ ] `return_first_data_array_result`: empty-array results are skipped, first non-empty
      wins; all-empty → [].
- [ ] **B10 regression:** a mod that MOVES its own card during `on_next` → every card
      still visited exactly once (needs snapshot fix first; until then this test pins the
      bug as expected-fail).
- [ ] statuses (when implemented): status hooks fire; self-removal mid-hook doesn't skip
      the card's remaining mods (STATUS_EFFECTS_PLAN C2).
- [ ] `CURRENT` lifecycle: two environments enter/exit tree → CURRENT restored correctly
      (pins the deck-viewer-vs-game fight noted in review D4; currently exit sets null,
      not previous — pin whichever policy you choose).

## 4. PipComparator (`Tests/test_comparator.gd`) (review B7, S-items; SCORING_AUDIT G1/G2)

No environment (NAN fallbacks) AND with FakeEnvironment (mod overrides) — run both.
- [ ] `compare_ranks/suits`: standard vs standard → numeric diff; either null → NAN;
      non-standard subclass pair → NAN.
- [ ] **B7 regression:** helper `is_suit_different(s1, s2)` (or the fixed call sites):
      NAN comparison → treated as NOT different / rejected, never "different".
- [ ] `is_rank_same`: identity; equal values distinct objects; 0.5 apart false; NAN false.
- [ ] `is_rank_next_to`: diff exactly 1 true; -1 false; 2 false; NAN false.
- [ ] `is_ace`: value 1 true; 14 false (SCORING_AUDIT SC3); 1.0 float true.
- [ ] `get_scorable_value`: wrap_ace_high true + ace → 14; false → 1; non-ace unaffected;
      null rank → -INF. (G2 — first real coverage of ace-high.)
- [ ] `is_scorable`: null card / null rank / null suit → false; full card → true.
- [ ] mod override: env with an `on_compare_ranks` mod returning 0 → is_rank_same true for
      any pair; mod returning NAN → falls through to default compare (pin fall-through!
      current code returns the mod's NAN result only via `is_nan` check — verify).
- [ ] mod-override precedence: two mods implementing the hook → first in iterator order wins.

## 5. GameData (`Tests/test_game_data.gd`)
- [ ] every scalar setter emits `state_changed` exactly once; (after review E10 fix)
      setting same value emits zero.
- [ ] `duplicate_big_number_array`: values equal, instances distinct, empty array, array
      with default-exponent entries.
- [ ] `print_board` doesn't crash on: empty zones, ragged columns, zone_type without
      columns entry (B4-adjacent), cards with null pips.

## 6. Scoring (extend `Tests/test_scoring.gd`)

Existing suite is strong — add only the SCORING_AUDIT gaps:
- [ ] G1: comparator-mod interaction under FakeEnvironment (flush detection with an
      `on_compare_suits` "all suits same" mod; straight with rank-warping mod).
- [ ] G2: ace-high tie-breaks (once SC5 decision made).
- [ ] G3: direct `ScoreModel` table tests: `final_score` over a matrix of
      (types, m, n) with hand-computed expectations; escalation boundaries (m=2 vs 3 for
      X_OF_KIND); multi-flush max() crossover point.
- [ ] G4: `get_loc_name` table test over (types, m, n, flush flags) → exact strings.
- [ ] G5: `_compare_results` full ordering chain with hand-built Results (score tie →
      meld size tie → high card tie → MULTI penalty → flush preference).
- [ ] SC1 regression: a meta-check that `_ready` awaits everything — simplest form:
      pass/fail totals asserted at the very end against a known count.

## 7. Mods / rules cards (`Tests/test_mods.gd`) — via FakeEnvironment + Board
- [ ] `TypeInput.on_can_place_stack`: target is self + topmost → stack; not topmost → [];
      target another card → [].
- [ ] `TypeInput.on_next`: drops top upper card to lower zone bottom (ColumnStart), draws
      replacement; empty draw deck → drop still works, no crash; column not found → no-op.
- [ ] `ZoneAdder` activate/deactivate: zone + type arrays grow/shrink in lockstep (I2);
      **B6 regression:** deactivate when card_data was already removed → no-op, does NOT
      remove the last column.
- [ ] `SkillGrabberOgLower` / `SkillPlacerOgLower`: alternating-suit ascending run →
      grabbed; repeated suit → []; rank gap 2 → []; upper zone target → []; single card →
      grabbed; **B7 case:** stack containing a non-standard suit → [] (not grabbed).
- [ ] `StampDoubleTrigger`: triggers exactly twice per score pass, counter resets on
      `on_after_score`; card without skill → no re-trigger.
- [ ] `SkillEchoingTrigger`: each skill echoed once; `triggered` cleared after score;
      does not echo itself into a loop with StampDoubleTrigger on the same board (pin!).
- [ ] `CardModifier.is_active`: in rules deck true; StampGlobal true; StampRevealing true;
      plain card in play false.
- [ ] `BoosterTemplate.create_one_choice`: with empty stamp/skill pools → `pick_random`
      on empty array is an error — pin current behavior (likely a real bug: basic booster
      has empty stamps/skills and calls `pick_random` on them → null with error).
      TypeBoosterBasic path must produce a valid card with rank 1–13, suit 1–4.

## 8. CHAOS / FUZZ SUITES (`Tests/test_fuzz.gd`)

All seeded + iteration-counted; every failure prints seed + action log (keep a ring
buffer of the last 50 actions, dump on failure).

### F1. Random-walk board fuzz (the big one — needs Board + validate())
Loop N times: pick a random legal-ish action —
  move random card → random anchor (incl. deliberately illegal: off-board cards, anchors
  inside stack, empty columns), draw, discard random board card, zone add/remove,
  shuffle — then assert:
  - `Board.validate()` (I1–I5) after EVERY action,
  - rejected actions leave a bit-identical board (compare a cheap board hash before/after),
  - total card count across all collections is constant forever.

### F2. Move/undo interleave fuzz (review B11 detector)
Loop: random action; save_state; occasionally undo 1–k steps. Assert after every undo:
  validate(); board hash equals the hash recorded when that history entry was created;
  every modifier's `.data` back-reference points into the current state's cards.
  (This test FAILS today — it's the executable form of B11.)

### F3. Dispatch chaos
Board seeded with hostile spy mods that randomly (seeded) move/discard/add cards from
inside random hooks. Loop `run_all_mods` over random hooks. Assert: no crash, validate()
after each dispatch, every dispatch terminates (guard: max hook invocations per dispatch;
catches on_trigger/echo/double-trigger loops).

### F4. Scoring fuzz (pure, fast, run 10k+)
Random hands: sizes 0–60, ranks −20..40 plus clusters, suits 1..8 plus unique-suit filler,
10% stones/nulls, occasional duplicates of the SAME CardData instance in the input (pin:
engine must dedupe or document). For every result:
  - meld ⊆ input cards (by identity), no duplicated instances in meld (has_dup_instances),
  - score ≥ 1 when any scorable card exists; empty/unscorable → empty results,
  - `score(hand) == score(hand.shuffled())` — order independence (same seed, both orders),
  - determinism: scoring the same hand twice gives identical (score, name, meld-set),
  - if MULTI: `sub_melds.size() == copies_count`, blocks are disjoint, each sub-meld
    re-scores standalone to `≥` its recorded per-copy score,
  - result invariant vs ScoreModel: recompute `final_score(types, copies_count, copy_size)`
    == reported score.

### F5. Iterator fuzz
Random collection sets (random counts, sizes, nulls, ragged 2D, wrong-typed entries) →
iterator output == naive-flatten oracle. 1k iterations.

### F6. Comparator fuzz
Random rank/suit values (incl. NAN-producing null/mixed-class pairs):
  - antisymmetry: `compare(a,b) == -compare(b,a)` when both non-NAN,
  - `is_rank_same(a,a)` always true; `is_rank_next_to` consistent with compare diff,
  - with a random-value `on_compare_ranks` mod: results always flow through the mod
    (never the default path) when the mod returns non-NAN.

## 9. Rollout order

1. **T-ENV FakeEnvironment + shared factories** (unblocks everything).
2. **Suite 4 (comparator) + Suite 2 (iterator)** — pure logic, no refactor needed, catch
   B7 immediately.
3. **Board extraction (review §5) with Suite 1 written AGAINST the new API** — write the
   1.3 matrix first, make old code pass through the adapter, then port.
4. **F1 + F4 fuzz** — F1 the day validate() exists; F4 immediately (needs nothing).
5. **Suite 3 (dispatch) + F3** alongside the B10 snapshot fix.
6. **Suite 1.6 + F2** alongside the B11 rebind fix (F2 is its acceptance test).
7. Suites 5–7 + remaining fuzz as touched.
