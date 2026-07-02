# Scoring Engine Audit — `Scripts/scoring.gd` + `Tests/test_scoring.gd`

Audit date: 2026-07-01. Companion to ARCHITECTURE_REVIEW.md (whose items B10/E1/E2 also
apply here; cross-referenced below).

## Verdict up front

The scoring engine is in noticeably better shape than the rest of the audited code:
`ScoreModel` as the single scoring authority is the right design, `build_multi` centralizes
the flush/multi packaging well, tie-break ordering is explicit and documented, and the test
file is genuinely comprehensive (standard poker parity, degenerate inputs, instance-identity
checks, sub-hand structure, self-checking leaderboard). The issues below are mostly a
handful of real bugs in the *test harness*, performance problems inherited from the
comparator dispatch, and dead abstraction.

---

## 1. BUGS

### Confirmed

- [x] **SC1. The first two test sections run CONCURRENTLY with the rest — results race.**
  [test_scoring.gd:25-26](Tests/test_scoring.gd:25) — `run_standard_5_card_poker_tests()`
  and `run_balatro_special_hand_tests()` are coroutines (they `await` inside) but are called
  **without `await`**. In GDScript that means `_ready` continues at the first suspension
  point: sections 1–2 interleave with sections 3+, `_pass`/`_fail` counters race, output
  interleaves, and `_print_summary()` (line 35) can run before sections 1–2 finish —
  failures there can be *silently excluded from the summary*. Fix: `await` both calls.
  This is the most important finding in the file: the suite may currently under-report.

- [x] **SC2. The `Scorer` base class is a fake abstraction.**
  [scoring.gd:107-108](Scripts/scoring.gd:107) — `@abstract class Scorer` defines
  `static func score(...)`. Static functions don't participate in inheritance dispatch in
  GDScript; each handler's `static func score` *shadows* (not overrides) it, nothing ever
  calls `Scorer.score` polymorphically, and `PokerHands.score` calls each handler by name
  anyway. Meanwhile call sites are inconsistent: `MultiStraightHandler.new().score(...)`
  ([scoring.gd:331](Scripts/scoring.gd:331)) and `Scoring.PokerHands.new().score(...)`
  ([test_scoring.gd:121](Tests/test_scoring.gd:121)) allocate a throwaway instance to call
  a static; other sites call statically. Fix: delete `Scorer`, drop every `.new()`, call
  `Handler.score(...)` uniformly. (If you *want* pluggable scorers later, make `score`
  non-static — that's the only way the abstraction can ever be real.)

- [x] **SC3. Test names claim rank 14 is "the Ace" — it isn't.**
  [test_scoring.gd:269-294](Tests/test_scoring.gd:269) — tests 21-L, 31-L, 33-H, 41-H use
  `m_card(14, ...)` and label it "Ace". `PipComparator.is_ace` is `value == 1`; 14 is just
  an off-scale rank (the engine allows arbitrary ranks, so the tests still pass on score).
  But it means **ace-high tie-break behavior is never actually tested**: no test exercises
  `get_scorable_value(..., wrap_ace_high = true)` / `get_ace_alt_value()`, and a regression
  in ace-high handling would not be caught. Fix: rename the labels to "rank 14", and add a
  real ace-high test (e.g. tie-break of A-x-x-x-x vs K-x-x-x-x once ace-high is used
  anywhere — see SC10, it currently isn't).

- [x] **SC4. `_ready`'s summary prints twice with different totals.**
  [test_scoring.gd:35-36](Tests/test_scoring.gd:35) — `_print_summary()` runs, *then*
  `run_leaderboard()` adds ~90 more pass/fail entries and calls `_print_summary()` again
  (line 958). The first "ALL N CHECKS PASSED" line is misleading; combined with SC1 the
  final tally is unreliable. Fix: single summary at the true end.

### Suspicious / design decisions to confirm intentional

- [x] **SC5. Ace never counts high in tie-breaks.** Every `get_scorable_value` call in
  scoring.gd passes `wrap_ace_high = false` ([scoring.gd:383](Scripts/scoring.gd:383),
  [628](Scripts/scoring.gd:628), [654](Scripts/scoring.gd:654),
  [738](Scripts/scoring.gd:738)), so an Ace (1) loses a high-card tie to a 2, and a
  wrap-straight ending at the Ace tie-breaks as 1 rather than 14. Tests encode this
  (test 4 expects tiebreaker 11 with an Ace present; test 9 expects 9). If deliberate,
  delete the `wrap_ace_high` parameter and `get_ace_alt_value` (dead code, see SC12);
  if not, this is a latent tie-break bug.

- [x] **SC6. Asymmetric tie handling between Full-Flush and Multi-Flush in `build_multi`.**
  [scoring.gd:242](Scripts/scoring.gd:242) uses `if ff_score >= best_score` (flush label
  wins ties) while [scoring.gd:263](Scripts/scoring.gd:263) uses `if mf_score > best_score`
  (plain label wins ties). `_compare_results` separately prefers flush on ties
  ([scoring.gd:362-364](Scripts/scoring.gd:362)) — so a multi-flush tying plain gets the
  plain label inside build_multi but flush-preference between Results. Probably intended
  (full flush is strictly more informative; multi-flush relabel isn't), but worth one
  comment line saying so, since the `>=`/`>` asymmetry looks like a typo.

- [x] **SC7. `house_base(int(n / 5.0))` silently floors non-multiple-of-5 sizes.**
  [scoring.gd:56](Scripts/scoring.gd:56) — safe for all current callers (houses are built
  at size `5*s`), but `base_per_copy` is public API per its doc comment; a caller passing
  `FULL_HOUSE` with n=7 gets scale-1 pricing for 7 cards. Add an assert or document the
  contract (`n` must be `5*s`).

- [~] **SC8. `_scan_wrap` cost is O(13 × total_cards) per call, called per straight
  extraction per pool iteration.** [scoring.gd:582-621](Scripts/scoring.gd:582) — fine at
  play-area sizes; the deep-stack tests (500 cards, 15b) already make the suite noticeably
  slow because every extraction loop recomputes `_get_hand_profiles_async` + both scans on
  the shrinking pool ([scoring.gd:485-507](Scripts/scoring.gd:485)). See E-items below
  before adding bigger stress tests.

---

## 2. STRUCTURAL IMPROVEMENTS

- [x] **SD1. `MultiFlushHandler` section B re-implements `build_multi` by hand.**
  [scoring.gd:680-711](Scripts/scoring.gd:680) builds uniform-size copies, sub-melds,
  names, and scores manually — the exact job of `build_multi` (which already handles the
  m-copies/sub_melds packaging for sets, straights, houses). The only reason it can't call
  it: `build_multi` computes flushness from the cards, and here every copy IS a flush with
  distinct suits by construction. Add a `base_types` of `[FLUSH]` path to `build_multi` (or
  a `precomputed_flush` flag) and delete ~30 lines. This also removes a naming/typing drift
  risk — two places currently decide what a multi-flush Result looks like.
  DONE 2026-07-02 via `Scoring.best_uniform_multi` with base `[FLUSH]` — names/scores
  identical (pure-flush pricing short-circuits before the ALL_SAME_SUIT doubling). ONE
  observable diff: multi-flush sub_meld `types` are now `[FLUSH]` instead of
  `[FLUSH, ALL_SAME_SUIT]`; nothing asserts or reads that today.

- [x] **SD2. Duplicated "uniform copy size search" pattern.** The
  try-every-size-truncate-longer-runs loop appears three times:
  `ExpandedGridHandler.score` step 2 ([scoring.gd:399-411](Scripts/scoring.gd:399)),
  `_package_straight_result` ([scoring.gd:529-546](Scripts/scoring.gd:529)),
  `MultiFlushHandler` section B ([scoring.gd:683-711](Scripts/scoring.gd:683)).
  Extract `best_uniform_multi(groups: Array[ArrayCardData], base_types, max_rank) -> Result`
  once SD1 is done; each handler becomes "collect groups → call it".

- [x] **SD3. `_scan_linear` allocates two `PipRankNumeral`s per adjacent-key pair**
  ([scoring.gd:567-568](Scripts/scoring.gd:567)) just to reuse `is_rank_next_to`. Besides
  the churn, it means comparator-override mods (`on_compare_ranks`) see *synthetic* rank
  objects with no owning card — any mod keying off `rank.data`-adjacent state gets garbage.
  Since profile keys are already floats, compare `keys[i] - keys[i-1] == 1.0` directly and
  document that mod-modified adjacency only applies through `get_rank_profile` keys.

- [ ] **SD4. Dead parameters and dead code (overlaps review D8).**
  `get_scorable_value(r, context_pool, wrap_ace_high)` — `context_pool` is never read
  ([pip_comparator.gd:176](Scripts/pip_comparator.gd:176)); `wrap_ace_high` is never passed
  true (SC5). `Result.tie_breaker_high_card` is set from ranks *or* from scorable value in
  HighCardHandler — same scale today, but only by accident of SC5. The commented-out
  `type_filter` block in `PokerHands.score` ([scoring.gd:342-345](Scripts/scoring.gd:342))
  should be deleted or implemented. The test file's tail comment (line 1027) already
  documents the removed wild/half-step cases — good pattern, keep that, delete the rest.

- [ ] **SD5. Section numbering in the test file is scrambled** (1,2,3,4,5,6,7,**9,10,11,8**)
  and the header comment (lines 8-16) lists 8 sections while 11 exist. Pure readability;
  renumber and regenerate the header when next touching the file.

- [ ] **SD6. Loose name assertions.** `assert_result` gates on
  `name.contains(label)` ([test_scoring.gd:61](Tests/test_scoring.gd:61)) — "Straight"
  matches "Straight Flush", "Flush" matches "Flush House". Most tests compensate with score
  + types checks (good), but the leaderboard rows check name-contains only
  ([test_scoring.gd:933](Tests/test_scoring.gd:933)) — a row expecting "Straight" would
  accept "2x Straight (5)". Where exactness matters, compare `==` against
  `Scoring.get_loc_name(expected_types, m, n)` instead of substrings — that also stops
  tests breaking when translations change wording.

---

## 3. EFFICIENCY

- [ ] **SE1. The comparator-dispatch tax dominates everything** (review E2). `is_flush`,
  `rank_sort_desc_async`, `_scan_linear`, `is_rank_same` all `await`
  `PipComparator.compare_*`, and each of those walks *every card in the environment* via
  `return_first_compare_mod_result` before falling back. In the test scene
  `CardEnvironment.CURRENT` is null so the walk short-circuits — meaning the test suite's
  performance is NOT representative of in-game scoring cost. Fix in the comparator layer
  (cache the list of mods implementing `on_compare_*` per scoring pass; skip when empty),
  not in scoring.gd.

- [x] **SE2. Extraction loops recompute hand profiles from scratch each iteration.**
  `_evaluate_straight_flushes_first` / `_evaluate_mixed_straights_first` /
  `MultiFlushHandler.score` all do `while true: profiles = _get_hand_profiles_async(pool)`
  and `pool.erase(c)` per card ([scoring.gd:485](Scripts/scoring.gd:485),
  [641](Scripts/scoring.gd:641)) — O(hands × pool) rebuilds plus O(n) erases. Incremental
  fix: remove extracted cards *from the profile maps* instead of rebuilding
  (`profile.ranks.map[key].datas.erase(c)`), rebuild only the pool array at the end.

- [x] **SE3. `PokerHands.score` runs all four handlers unconditionally.**
  `MultiStraightHandler` (the most expensive) runs even when fewer than 5 distinct rank
  keys exist; `MultiFlushHandler` runs when no suit has 5 cards. Both handlers do check
  internally, but only after building a full profile. Cheap pre-gates from one shared
  profile (build it once in `PokerHands.score`, pass it down) would skip most of the work
  for typical small hands — this also de-duplicates the 3+ `_get_hand_profiles_async`
  calls per scoring.

- [ ] **SE4. `_scan_wrap` tries every start position** (13 walks/call). The best wrap walk
  always starts right after the largest gap (or anywhere on a full cycle); computing that
  start directly makes it one walk. Minor, but it's inside the hottest loop (SE2).

- [ ] **SE5. Leaderboard runs ~90 full scoring passes** including 25-card hands — fine as
  an opt-in benchmark, but it runs on every `_ready`. Consider an
  `@export var run_leaderboard_bench := false` gate so the correctness suite stays fast
  enough to run habitually. (After SC1's fix the suite gets slower-feeling because it
  actually serializes.)

---

## 4. TEST COVERAGE GAPS

Worth adding, in rough priority order:

- [~] **G1. Comparator-override path** — PARTIALLY DONE 2026-07-02: `Tests/test_comparator.gd`
  covers the mod-dispatch branch through `FakeEnvironment` (override wins, NAN fall-through,
  first-mod precedence, inactive skills skipped). Still missing: an END-TO-END scoring run
  under an active comparator mod (flush detection with an "all suits same" mod).
  Original text: no test runs with a `CardEnvironment` +
  `on_compare_ranks`/`on_compare_suits` mods active, so the entire mod-interaction branch
  of `PipComparator` (and NAN-fallthrough behavior, review B7) is untested. A minimal fake
  environment (a `CardEnvironment` subclass whose `get_card_collections` returns one rules
  card) would cover it.
- [x] **G2. Ace-high / `wrap_ace_high`** — DONE: tests 55/55b in test_scoring.gd (wrap
  straight tie-breaks 14, wheel tie-breaks 5) + `get_scorable_value` unit checks in
  test_comparator.gd §3.
- [ ] **G3. `ScoreModel` unit tests**: `final_score`/`base_per_copy`/`copy_escalation` are
  pure static functions — cheap direct assertions (X_OF_KIND escalates from 3rd copy,
  others from 2nd; `MULTI_FLUSH_COPY_MULT` max-vs-plain crossover at m where
  `2m·base > base·m·esc`) would pin the tuning constants far more precisely than
  end-to-end hands do.
- [ ] **G4. `get_loc_name` direct tests**: the localization matrix (m×n×flush flags) is
  only sampled indirectly via name-contains; a table-driven test over
  `get_loc_name(types, m, n)` outputs would catch format-string regressions exactly.
- [ ] **G5. Sort stability tie cases**: `_compare_results`' last two tiers (MULTI penalty,
  flush preference) have exactly one test each (M1, implicit); add a direct pair of
  hand-crafted `Result`s asserting the full ordering chain.
- [x] **G6. `sub_melds` re-score parity for MultiFlushHandler results** (S5 covers grid +
  straight + flush via PokerHands, but the manual sub-meld construction in SD1's code path
  is only structurally checked — after SD1 unification this collapses into existing tests).

---

## 4b. SECOND-PASS ADDENDUM (2026-07-01)

A later pass re-examined the engine looking for anything the first audit missed. Three
additions, none urgent:

- [x] **SA1. Straight/flush extraction is greedy, not optimal — document it.** Both
  straight paths ([scoring.gd:481-525](Scripts/scoring.gd:481)) and the flush extractor
  ([scoring.gd:641-665](Scripts/scoring.gd:641)) repeatedly remove the single longest
  run/largest suit group from the pool. Greedy extraction can miss the best *partition*
  (e.g. taking one maximal run that straddles two suits can destroy two straight
  flushes; taking the largest flush can starve a second suit down to 4). The two-path A/B
  in `MultiStraightHandler` (`flushes_first` vs `mixed_first`) exists precisely to hedge
  this, which deserves a comment — and a known-limitation note in the test file so a
  future "why doesn't it find X" bug report gets triaged as by-design. If exactness ever
  matters, this is a small weighted set-partition search, feasible at board sizes.

- [x] **SA2. `HandProfile` construction is the natural home for the SE2/SE3 fixes** —
  after profiling once in `PokerHands.score`, hand each handler the same profile and give
  `HandProfile` a `remove_card()` so extraction loops decrement instead of rebuilding.
  (Restates SE2/SE3 as one concrete refactor around the existing class rather than new
  machinery.)

- [x] **SA3. Test factory type sloppiness:** `m_card(rank_val: float, suit_id: float)`
  ([test_scoring.gd:89](Tests/test_scoring.gd:89)) feeds a float into
  `PipSuit.with_value(i: int)` — implicit narrowing that GDScript warns on and that
  hides intent (suits are categorical ints everywhere else). Type the params `int`;
  ranks may stay float (half-step ranks are a planned feature per the file's tail note).

## 5. SUGGESTED ORDER

1. **SC1 + SC4** (await the two sections; single summary) — five-minute fix, restores trust
   in every number the suite prints. Re-run and record the true pass/fail baseline first.
2. **SC2** (delete Scorer, uniform static calls) + **SD4** dead-code sweep.
3. **SD1 → SD2** (route MultiFlushHandler through build_multi, then extract the shared
   uniform-size search) — behavior-preserving refactor guarded by the existing suite.
4. **SE2/SE3** profile reuse (biggest real-game win together with review E2).
5. **G1–G3** new tests, then SC5 decision (ace-high) with G2 in place to lock it.

## 6. STATUS ADDENDUM (2026-07-02)

Implemented this pass: SE2 (`HandProfile.remove_card` — straight/flush extraction loops
consume ONE profile incrementally instead of rebuilding per iteration; `_best_sequence_from_profiles`
variant added), SE3 (`PokerHands.score` profiles once, pre-gates MultiStraightHandler on
>= 5 distinct rank keys and MultiFlushHandler on any suit bucket >= 5, and hands the shared
profile to ExpandedGridHandler), which together also mitigate SC8 (the wrap scan now runs
on shrinking profiles, not rebuilt pools).

Deliberately still open:
- **SE1** (skip the comparator's environment walk when no mod implements `on_compare_*`):
  needs a cache invalidation signal that doesn't exist yet (mods can appear/disappear with
  any card move). Revisit if profiling shows it matters in real games; do NOT bolt on a
  timer/heuristic cache.
- **SE4** (single-walk `_scan_wrap`): micro-optimization inside a loop SE2 already tamed.
- **SD4** (dead `context_pool` param), **SD5** (test section renumbering), **SD6**
  (exact-name leaderboard asserts): mechanical cosmetics, safe any time.
- **G3–G5** (ScoreModel / get_loc_name / _compare_results table tests), **SA1** (document
  greedy-extraction limitation), **SA3** (factory int typing).

## 7. FINAL PASS (2026-07-02, second)

- **SE1 DONE** with the owner-approved "cards haven't moved" cache:
  `GameData.revision` is bumped by every mutation path (Board.move_stack/place_card/
  add_column/remove_column, Game.draw_card/discard_data/add_deck/shuffle/return_to_map);
  `CardEnvironment._compare_implementers(hook)` caches the ordered implementer list keyed
  on `[state id, revision]` (Game provides the key; base environments/tests return an
  empty key = uncached, identical live behavior). Skills stay in the cached list and are
  gate-checked on `active` at use time, since that flag flips without a board mutation.
  CONTRACT: assigning a modifier to an in-play card outside those paths must bump
  `state.revision` (documented on the field).
- **SD4 DONE**: unused `context_pool` parameter removed from `get_scorable_value`
  (all call sites updated). Commented-out `type_filter` block kept per owner convention.
- **SA1 DONE**: greedy-extraction limitation documented on MultiStraightHandler.
- **SA3 DONE**: `m_card` suit params typed `int` in both factories.
- Still open (cosmetic only): SE4, SD5, SD6, G3–G5.
