# Comparator buckets — assumptions taken during execution

Gap protocol rule 1: a decision the design does not cover, **reversible and clearly within intent**,
is taken and recorded here with the node it was taken under. Anything heavier is a gap instead.
One line per assumption. If one of these turns out wrong, it is a bug in exactly the named function.

- **S5 / GAP-001 (D3, Q82, Q1, Q94)** — when a self-denied value's cards sit in a class a merge rule
  built, cards are distributed into sub-classes in hand order, each taking the first sub-class holding
  no card it shares a denied value with. The owner's answer forces the plain case (three 7s, nothing
  merged → one class each); this rule extends it to the collision case, satisfying every deny exactly
  while leaving never-denied cards together. `Scoring._split_denied_rank_classes` / `_split_denied_suit_classes`.
- **S4 (Q81, §1.1)** — "printed values decide" is computed by `PipComparator.printed_same`, which
  dispatches nothing. Routing silence through `on_compare_ranks` / `on_compare_suits` would give a
  meld the ordering hooks' answer, which is the cross-situation fallback Q62(a) removed.
- **S6 (§1.8)** — the cache key uses the pair in **the order asked**, never canonicalised: nothing in
  the design promises a rule answers (a, b) the way it answers (b, a).
- **S13 (§1.7, Q71=c)** — `on_meld_extra_rank_values` composes by **union across every
  implementer**, not first-implementer-wins. §1.7 states the precedence rule for
  `on_meld_wrap_bounds` and is silent for extra values; a membership list is not a scalar verdict,
  so a second card offering another value must not be silenced by the first.
  `PipComparator.get_extra_rank_values`.
- **S8 (§1.3)** — `sanitize` takes the deny hook name and the domain as parameters. §1.3 lists the
  signature without them while step 4 of the same section mandates the deny re-check; the
  parameters are what make that step possible. `Scoring.sanitize`.
- **S7 (§1.3, §1.7)** — a card's EXTRA rank values do not survive a whole-hand grouping rule. Stage 1
  is a partition, so a card that sat in several classes lands in one, and that class's positions come
  from PRINTED values only. Q71(c) routes adjacency through stage-0 class membership and the design
  never says what a stage-1 rewrite does to it; seeding extra values here also made single-card
  groups `mixed`, which is the cost defect in `gaps/GAP-002.md`. `Scoring._rebuild_classes`.
- **S21 (§1.1, Q62, Q97)** — `PipComparator.is_suit_same` and `is_rank_same` are **deleted**, not
  kept as helpers. S21 removed their last production callers, and both answered a SAMENESS question
  by dispatching the ORDERING hooks — the cross-situation reuse Q62(a) removed and Q97 named. Keeping
  them keeps the trap that produced F1: the next stacking or melding call site reaches for the
  familiar name and silently gets the wrong hook. Callers now split three ways by what they actually
  mean — `stack_*_same` (stacking), `pair_is_same` with the meld hooks (melding), `printed_same`
  (no dispatch at all). Rank adjacency is untouched and still uses `compare_ranks` (Q55=a).
- **S23** — the wrap-bounds hook is hoisted to one ask per `_best_sequence_from_profiles` call, the
  same fix F2 names for extra values. `_compare_implementers` is uncached in base environments, and
  the assignment count is a cartesian product, so per-scan asking multiplies a full board walk by it.
- **S14 (§1.6)** — each consuming handler builds ONE unconsumed "classification" profile and threads
  it into `build_multi`. `is_flush` must read the partition the cards formed under, and the straight
  and flush handlers eat their working profile through `remove_card`. Sharing a single profile
  across the pass is DEFERRED.md E3 and stays out of scope.
