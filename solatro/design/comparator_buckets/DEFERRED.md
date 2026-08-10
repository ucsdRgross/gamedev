# Comparator buckets — deferred work and known improvements

**This is the index of everything the confirmed design deliberately left undone.** Each entry says
what it is, which authored cards are blocked on it, the answer that deferred it, and **where in the
code the seam would be** — so picking one up needs this file and nothing else.

Read with `DESIGN.md` (behaviour authority) and `PLAN.md` (build order, contracts).
⚠ **Nothing here is a bug.** Each was scoped out on the record; the cost of forgetting is that
someone rediscovers it mid-sprint.

---

## A. Content that cannot ship until one of these lands

| # | deferred mechanism | blocked cards | deferred by | where the seam is |
|---|---|---|---|---|
| **D1** | **Multiplicity** — one card counting as several cards in a meld | **The Forged Ace** (two Aces), **Flea Circus** (five rank-1 cards) | QR5(a), confirmed Q50(a) | `Scoring._get_hand_profiles_async`. A partition puts each card in one group exactly once. Two honest routes: virtual card instances materialised before profiling, or a per-card weight on `RankClass`/`SuitClass` that every count respects (`datas.size() >= 2`, copy sizing, wrap steps). ⚠ **THREE DOORS INTO THIS, NOT ONE, AND TWO WERE OPEN.** Q89(b) closed the grouping route (a rule may pull a board card in, never invent one). The other two are MULTI-KEY MEMBERSHIP: extra rank values (Q71=c) and dual suits (Harlequin) put one card in several classes, so any meld assembled from several classes could spend it once per class — a five-card straight from three cards, or a full house whose trip and pair are the same card. Both are now barred by explicit "already spent" sets (`Scoring._unused_at`, `best_uniform_multi`, `_form_houses_at_scale`), pinned by `test_comparator.gd` section 12 and fuzz invariant 7b. **Anyone implementing D1 must go through those guards deliberately, not around them** |
| **D2** | **Class-tag grouping** — the same "which group is this in" question over class tags | **The Jongleur** (every class), **The One-Man Band** (three), **Greasepaint**, **The Joey**, **The Ringmistress**, **The Impresario** | QR6(a), confirmed Q52(a) | The closure and sanitize in `PipComparator` are written **domain-agnostic** on purpose (`keys` / `reps` / `same`), so a third domain is a new caller, not a rewrite. Group effects and leader bonuses are the consumers — DESIGN_DOC §11 |
| **D3** | **Non-card rule sources** — a modifier with no board card to live on | **The Fire Marshal** (town hazard: Flames count as Wax for a show) | QR7(a), confirmed Q53(a) | `CardEnvironment._compare_implementers` walks `CardDataIterator`, which only visits board and rules cards. Needs a run-level modifier list the iterator also visits, plus a ruling on whether undo rewinds it |
| **D4** | **Multi-meld membership** — one card scoring in several melds | **The Courier** (straddles two columns), **The Puszta Five** (every column) | Q54(a) | Not a grouping question at all — it is "which hand is this card in", which lives in `ScoringSection.of_line` and `Game.score_line`. ⚠ Do not conflate with D1 or with the pull-in rule (Q14 d), which is about one meld reaching outward |
| **D5** | **Half-step ranks and wider multi-suit** | none authored beyond **Harlequin**, which the existing multi-key path already serves | Q56(a) | The `TODO(half-step ranks)` and `TODO(multi-suit)` comments already in `Scripts/pip_comparator.gd` mark every site |

## B. Engineering improvements, no content blocked

| # | improvement | why it is not in scope | where |
|---|---|---|---|
| **E1** | **A benchmark for the scoring path** | ⚠ **This is the one that blocks the other two.** None exists (PERFORMANCE.md §4d); `Tests/Visual/fx_cost.gd` is the template — empty-scene floor, `WARMUP`/`FRAMES` averaging, a `_cpu_row` timing a real call | new rows in a board bench |
| **E2** | **The straight search has no cap** | `PLAN.md` §1.5 enumerates one position per mixed class as a cartesian product. Product is 1 when nothing merged, so the un-modded path is untouched. Product is 1 when nothing merged, so the un-modded path is untouched. Bounded in practice by thirteen positions; **unmeasured on a real board**, because E1 does not exist. If one makes it expensive, that is a gap to file, not a bound to invent. ⚠ A 23 s scoring pass once looked like that case arriving; it was an implementation bug instead (`gaps/GAP-002.md`, withdrawn) — a class's `member_keys` leaked in values that belonged to a card's OTHER class, so classes counted as `mixed` that had not been merged. `test_mod_fuzz.gd` prints the slowest pass every run, and `test_comparator.gd` section 11 asserts the assignment count directly, because that failure was invisible in results — every score was correct, just astronomically slow | `Scoring.MultiStraightHandler` |
| **E3** | **Profile rebuilt several times per scored line** | Q57(a). The straight and flush handlers consume their working profile destructively via `remove_card`, and each now also builds an unconsumed CLASSIFICATION profile for `is_flush`, so sharing one needs a cheap `HandProfile.duplicate()`. ⚠ **It is no longer only a cost.** The straight handlers build profiles from SUBSETS of the hand (one suit's cards at a time), and stage 0 closes over the keys actually present — so a subset can produce a different partition from the full hand's, and a run formed under one is classified against the other. Measured while writing `test_mod_fuzz.gd`: this is why invariant 8 asserts the position model rather than the finished meld | `Scoring.PokerHands.score`, `MultiStraightHandler`, `MultiFlushHandler` |
| **E4** | **SE4 — single-walk `_scan_wrap`** | The scan restarts from every rank where one pass could find the longest wrap run. Pre-existing, unrelated to this work, and speculative until E1 exists | `scoring.gd:676` |
| **E5** | **Ordinal composition** | Q55(a) keeps "first card found wins" for `on_compare_ranks`/`on_compare_suits`, because numbers cannot be unioned the way group memberships can. If two ordering rules ever need to compose, that needs its own ruling | `CardEnvironment.return_first_compare_mod_result` |

## C. Accepted risks — decided, not overlooked

| # | risk | the answer that accepted it |
|---|---|---|
| **R1** | **A grouping rule can hang a submit.** Unlimited re-entrancy, grouping outside the runaway-event cap, no backstop. Not hypothetical: `skill_eval_poker_best.gd:18` already scores rows and columns from inside scoring | Q15(b), Q19(b), Q92(b) |
| **R2** | **A split meld is invisible to the player** — three matching cards on screen, two counted, nothing explaining it. ⚠ The shape most likely to be reported as a scoring bug | Q33(a) |
| **R3** | **No cue for a merge, and none for which rule acted first** | Q30(a), Q34(a) |
| **R4** | **Points are double-counted** by design: a pulled-in card banks in its own line and in the meld that pulled it | Q87(a), Q88(a) |
| ~~**R5**~~ | ~~A card that consults randomness and forgets `compare_uncacheable` gets a stale answer~~ — **RETIRED, the risk no longer exists.** The owner rescoped the cache to the SCORING PASS (`gaps/GAP-003.md`), so a rule's answer is fixed for the hand and there is nothing to forget to declare. A random rule is now a supported, tested shape rather than a footgun | superseded: Q41(c), Q90(a), Q91(a) |

## D. Questions that reactivate if a root answer changes

These were written, never asked, and are **not** dead — each becomes live the moment its gate opens.
They are already in `DESIGN.md` §5 in the questionnaire grammar, so reopening one costs a scoped
round and no authoring.

| question | reactivates when |
|---|---|
| **Q6** — veto precedence | QR4 changes from (d) to (c) |
| **Q60, Q61** — which contexts a marker distinguishes, and what ignoring it means | QR3 changes from (c) to (a) |
| **Q66** — which counts respect a per-card weight | QR5 moves to (c), i.e. D1 above |
| **Q69** — where a run-level rule source lives | QR7 moves to (b), i.e. D3 above |
| **Q73** — what an authored priority tie means | Q10 changes from (a) board order to (b) priority numbers |

---

## How to pick one up

1. Read the row here, then the cited questions in `DESIGN.md` §5 — the answer text says *why*.
2. If it needs a new decision, it is a **gap**: file `gaps/GAP-NNN.md` using the template in
   `DESIGN.md` §16, in the questionnaire grammar. It becomes the next round's question unchanged.
3. If it is purely mechanical, it is a new plan phase citing the design nodes it implements.
4. ⚠ **Do not resolve a deferral by deciding it.** Every row here was scoped out by an owner
   answer; changing scope is an owner call.
