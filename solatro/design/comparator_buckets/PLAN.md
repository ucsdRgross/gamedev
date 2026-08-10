# Comparator buckets — implementation plan

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/comparator_buckets/DESIGN.md`, version 1, confirmed round 3. Every
step below cites the design node IDs it implements.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent → do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise — two defensible choices differ in observable behaviour, or the choice is expensive to
   reverse, or it is an owner call (balance, look, scope) → **park that thread, file a gap, keep
   working on unaffected threads, and tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.
4. ⚠ **Two documents disagreeing is NOT automatically (3).** If both are restating the same answer,
   go read that answer — the conflict is a documentation bug to fix against the source, not a
   decision to escalate. Quote the note in the gap and say why it does not settle the question; if
   you cannot, it was never a gap.

File gaps at `solatro/design/comparator_buckets/gaps/GAP-NNN.md` using the template in
`solatro/design/comparator_buckets/DESIGN.md` §16. Write the options in the questionnaire grammar;
they become the next round's questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

**Three documents, and you need all three:** `DESIGN.md` is the behaviour authority (65 answers,
nine charts); this file is the build order and the normative contracts; **`DEFERRED.md` is every
improvement and deferred feature this design left undone**, with the cards blocked on each and the
seam where each would land. When a step here says something is out of scope, `DEFERRED.md` is where
it went.

---

## 0. Two supersessions, and one interpretation to check

⚠ **Later answers overrode two earlier ones. The loser must not be implemented.**

- **Q96(c) supersedes Q20(c).** Q20 made a mixed group invisible to straights; Q96 makes it act as
  any one of its members' positions. Chart node F10.
- **Q93(d) supersedes Q23(b).** Q23 asked for both merged and unmerged readings to be scored; Q93
  chose Q3 — one reading, the merged one — and added the one-card-per-grouping rule with it.

⚠ **One interpretation the executor did not get to make, flagged for the §1 review gate.** Q83(a)
says *every* situation gets a blacklist/whitelist pair, and Q55(a) says ordering keeps
first-found-wins because numbers cannot be merged. Ordering asks "which is greater", which has
nothing to deny or allow, so §1.1 gives the deny/allow pairs to the two **sameness** situations
(melding, stacking) and leaves ordering as today's single scalar hook. If that is wrong, it is one
line in §1.1 and a gap, not a rewrite.

---

## 1. Normative contracts

**Everything in this section is specified, not suggested.** Do not invent a name, a default or a
rule that is not here; if one is missing, that is a gap.

### 1.1 The hook surface (QR3=c, Q62=a, Q97, Q80=a, Q83=a, Q55=a)

QR3(c) chose **separate hooks per situation** over one context marker. Q62(a) and the owner's Q97
note fix what that means:

> *"I only meant that you cannot directly reuse a card with a meld hook for stuff like stacking
> hooks. if i wanted a card to also have stacking rules then it needs to implement stacking hook
> too."*

So there is **no cross-situation fallback**: a card implementing a meld hook gets meld behaviour
and nothing else, and a card wanting both implements both. Q80(a) fixes how a rule declares its
kind — **by which hook it implements**, not by a flag or a return value.

```gdscript
# Cards/card_modifier.gd — the complete comparator surface. Duck-typed via has_method, so a
# name typo silently disables the rule; these spellings are the contract.

# MELD sameness, two passes (§1.2). true = "this pass answers yes for this pair".
func on_meld_ranks_deny(r1: PipRank, r2: PipRank) -> bool
func on_meld_ranks_allow(r1: PipRank, r2: PipRank) -> bool
func on_meld_suits_deny(s1: PipSuit, s2: PipSuit) -> bool
func on_meld_suits_allow(s1: PipSuit, s2: PipSuit) -> bool

# STACK legality sameness — the same two passes, its OWN hooks. No fallback from the meld ones.
func on_stack_ranks_deny(r1: PipRank, r2: PipRank) -> bool
func on_stack_ranks_allow(r1: PipRank, r2: PipRank) -> bool
func on_stack_suits_deny(s1: PipSuit, s2: PipSuit) -> bool
func on_stack_suits_allow(s1: PipSuit, s2: PipSuit) -> bool

# ORDERING — UNCHANGED. A scalar delta, first implementer wins (Q55=a). Sort order and high card
# keep asking exactly what they ask today.
func on_compare_ranks(r1: PipRank, r2: PipRank) -> float
func on_compare_suits(s1: PipSuit, s2: PipSuit) -> float

# WHOLE-HAND grouping, stage 1 (§1.3).
func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]
func on_meld_group_suits(cards: Array[CardData], groups: Array[Array]) -> Array[Array]

# ADJACENCY (§1.7).
func on_meld_extra_rank_values(card: CardData) -> Array[float]
func on_meld_wrap_bounds(low: float, high: float) -> Vector2

# CACHE opt-out (§1.8) — a property, not a hook.
var compare_uncacheable : bool = false
```

⚠ The two existing hook names `on_compare_ranks` / `on_compare_suits` **keep their current meaning
and their current callers** (`pip_comparator.gd:77`, `:47`). Nothing about ordering, sort or high
card changes. Melding stops calling them.

### 1.2 The two passes (QR4=d, Q81=a, Q82=a, Q84=a, Q1=a)

The owner's QR4 answer, verbatim:

> *"On first returned true. Certain types of legality are either blacklist or whitelist types.
> First checks blacklist type mods, first true means effect is blacklisted. Then checks whitelist,
> where first returned true is accepted."*

```gdscript
## Is this pair the same, for `situation`? Chart D.
## PASS 1 — every deny implementer in board order; the FIRST true forbids the pair outright and
##          stops the pass (Q84=a). A deny beats printed sameness too (Q82=a), which is how a
##          rule splits two ordinary 7s.
## PASS 2 — every allow implementer in board order; the FIRST true merges the pair, stopping.
## NEITHER — printed values decide, exactly as today (Q81=a).
## Skills are skipped while not spotlit (Q5=a). Deny and allow are separate implementer lists,
## each cached per board revision by the existing SE1 mechanism.
## Asked once per DISTINCT PRINTED VALUE PAIR, never per card pair (Q1=a): pips printing the
## same value are interchangeable to the rule, exactly as they already share a bucket today.
static func pair_is_same(a: Variant, b: Variant, deny: StringName, allow: StringName) -> bool
```

Both passes stop at the first `true`; the remaining rules of that kind are **not asked**, so their
side effects do not fire and they do not feed the patience counter (Q84=a).

### 1.3 The whole-hand hook, and sanitize (Q10=a, Q11=a, Q12=a, Q13=d, Q85=a, Q14=d, Q16=a, Q94=a, Q18=a, Q15=b, Q19=b)

Stage 1 runs after stage 0, once per implementing card, **in board order** (Q10=a), each seeing the
partition the previous one left (Q16=a). Any board or rules card's hook applies whether or not its
own card is in the hand (Q18=a).

```gdscript
## Sanitize a whole-hand rule's answer. Runs after EVERY stage. No dispatch; pure.
## 1. EMPTY RETURN (Q13=d, Q85=a) — an empty or absent array is not an error and not "no change":
##    it means NO MELD IS POSSIBLE from this hand. Profiling returns the NO_MELD sentinel,
##    PokerHands.score returns [], and Game.score_line banks ZERO for the line.
## 2. FOREIGN CARDS (Q14=d, Q89=b) — a named CardData that is not in this hand is ACCEPTED and
##    joins the meld, provided it is reachable from the environment's collections. A CardData that
##    is not on the board at all is REFUSED with push_error: a rule may pull a card in, never
##    invent one.
## 3. OVERLAPS (Q12=a) — groups sharing a card are unioned into one.
## 4. DENY RE-CHECK (Q94=a) — after unioning, every pair the union created is re-asked against the
##    DENY pass only. A denied pair splits the union back apart; the deny wins.
## 5. OMISSIONS (Q11=a) — a card the rule did not name keeps its grouping with the other cards its
##    previous group still holds. Naming three cards means "put these three together", never
##    "shatter the rest".
## 6. ORDER (landmine) — members are re-sorted into hand order before the next stage, so a rule's
##    return order can never change which card a handler picks first.
static func sanitize(proposed: Array[Array], previous: Array[Array], hand: Array[CardData]) -> Array[Array]
```

⚠ **No depth limit and no runaway accounting** (Q15=b, Q19=b, Q92=b). A rule may call
`Scoring.PokerHands.score` from inside its own hook, without bound, and grouping dispatches are not
counted against the per-act event cap. This is deliberate and is recorded in §5.

### 1.4 What a class is (QR2=a, Q20 superseded by Q96=c, Q21=a, Q22=a, Q24=a)

Splitting is allowed (QR2=a, Q4=a, Q82=a), so **two classes may carry the same printed value** and
the current `Dictionary[float, ArrayCardData]` cannot hold them. `HandProfile` changes shape.

```gdscript
# Scripts/scoring.gd — replaces RankMap.map / SuitMap.map (scoring.gd:150-153).
class RankClass:
	var key : float                       # identity: the SMALLEST printed value in this class
	var mixed : bool = false              # true when members do NOT share one printed value
	var member_keys : Array[float] = []   # every printed value present; the Q96 candidate set
	var datas : Array[CardData] = []      # members, always in HAND ORDER
class RankMap:
	var classes : Array[RankClass] = []   # NOT keyed — two classes may share a key

class SuitClass:
	var key : String                      # identity: the lexicographically smallest member key
	var mixed : bool = false
	var member_keys : Array[String] = []
	var datas : Array[CardData] = []
class SuitMap:
	var classes : Array[SuitClass] = []
```

- Tie-breaks and "the meld's high card" read the class **maximum** (Q21=a), not `datas[0]`.
- Two split classes sharing a value are two independent classes; both keep all their cards
  (Q22=a, Q24=a).
- `HandProfile.card_rank_keys` / `card_suit_keys` (`scoring.gd:134`) become
  `Dictionary[CardData, Array[RankClass]]` / `[SuitClass]` — direct references, so `remove_card`
  stays O(1).

### 1.5 How a straight reads classes (Q93=d, Q95=a, Q96=c)

The owner's Q93 answer, verbatim:

> *"Q3. groupings count as 1 card in a straight. 5 groupings where each one is connected straight
> wise should be a straight choosing 1 card from each grouping."*

and Q95(a) confines that to merged groups, leaving today's behaviour alone:

```gdscript
## Positions a class offers the straight scanners, and how many cards it can spend there.
## SAME-VALUE class (mixed == false): position = key, and it contributes EVERY card it holds —
##   three 7s still give the wrap scan three steps at position 7, exactly as today (Q95=a).
## MIXED class (mixed == true): contributes EXACTLY ONE card (Q93=d), at ANY ONE of its
##   member_keys — whichever choice makes the longest run (Q96=c). It is NOT invisible; Q96
##   supersedes Q20(c).
```

⚠ **This turns `_scan_linear` / `_scan_wrap` from a walk into a search.** Specified exactly:

```
best := the empty run
for every assignment of one member_key to each MIXED class:      # cartesian product
        positions := same-value classes (all their cards) + this assignment (one card each)
        best := longer of best, _scan_linear(positions), _scan_wrap(positions)
return best
```

The product is `prod(member_keys.size())` over mixed classes only, and is **1 when no rule merged
anything**, so the un-modded path runs the existing scan once and is unchanged. Assignments are
enumerated in ascending member_key order so the result is deterministic. There is **no cap**: if a
real board ever makes this expensive, that is a gap to file, not a bound to invent.

### 1.6 Classification (Q25=a, Q26=a, Q27=a)

```gdscript
## Scoring.is_flush (scoring.gd:244) no longer walks pairs. It asks the SAME partition formation
## used (Q25=a): true iff every card in the meld sits in ONE suit class.
## The Full Flush x2 applies even when a rule is what merged those suits (Q26=a).
## Multi-Flush counts SUIT CLASSES, not printed suits, so a suit-merging rule collapses the
## distinct-suit requirement and Multi-Flush disappears (Q27=a).
static func is_flush(meld: Array[CardData], profile: HandProfile) -> bool
```

`build_multi` (`scoring.gd:259`) gains the profile as a parameter and passes it to both call sites
(`:273`, `:291`). No caller may call `is_flush` without a profile.

### 1.7 Adjacency (QR8=b, Q71=c, Q72=b)

Adjacency came into scope, and by the route that needs **no new scanner machinery** (Q71=c):

```gdscript
## Extra printed values this card also counts as. They become ordinary class keys during
## profiling, so the existing scan finds them with no change to adjacency logic at all (Q71=c).
## A card returning [5.0, 9.0] participates at 5 and 9 as well as its own value.
func on_meld_extra_rank_values(card: CardData) -> Array[float]

## Extend or break the wrap-around cycle (Q72=b). Receives the current bounds — by default
## PipComparator.get_ace_base_value() and get_wrap_top_value() — and returns the bounds to use.
## Return Vector2(NAN, NAN) to break the wrap so no run may cross the top.
## First implementer wins (the Q84 shape); skills gated on spotlit.
func on_meld_wrap_bounds(low: float, high: float) -> Vector2
```

⚠ Extra values are **class membership**, so a card carrying them appears in several classes at
once — the same path `Harlequin`'s dual suits already use, and `remove_card` must clear every one.

### 1.8 The cache (Q40=b, Q41=c, Q90=a, Q91=a, Q42=a)

> ⚠ **SUPERSEDED BY `gaps/GAP-003.md` — OWNER RULING, AND EVERYTHING BELOW IS THE OLD SHAPE.**
> The cache is scoped to the **scoring pass**, not the board revision: a rule is asked at most once
> per distinct key pair per HAND and its answer is fixed for that hand. So a rule consulting
> randomness has already been decided before meld finding starts, and **`compare_uncacheable`,
> the spotlight-epoch key and the never-cache rule for base environments are all deleted** — they
> existed only to make a board-scoped cache safe. Q41(c), Q90(a) and Q91(a) no longer hold; the
> memo lives on `PipComparator` (`begin_pass` / `end_pass` / `ask_pass`), not on `CardEnvironment`.
> The SE1 implementer cache below is UNAFFECTED — "does anything implement this hook" is a
> different question with a different lifetime.

Q40(b) builds it now rather than waiting for a benchmark. The owner's Q41 answer, verbatim:

> *"cache everything except cards that consult rng then"*

```gdscript
## CardEnvironment — pair-verdict cache. Key: [deny/allow hook name, ordered key pair].
## Invalidated when _revision_key() changes, exactly like the SE1 implementer cache, and ALSO
## when any skill's spotlit flag flips (a spotlight epoch counter joins the key) — spotlit
## changes without a revision bump (card_environment.gd:162) and a cached verdict would go stale.
## Base environments (tests, map) return an empty revision key and are NEVER cached.
##
## OPT-OUT (Q90=a): `compare_uncacheable` is a property on CardModifier, read once per board
## revision. If ANY implementer of the hook being asked is uncacheable, that hook's verdicts are
## not stored at all for that revision.
## A card that consults randomness and forgets to set it gets a stale answer for the rest of the
## revision — a content bug like any other, not an engine guard (Q91=a).
## WHOLE-HAND rules are NEVER cached (Q42=a): they read board state by design.
func compare_cache_get(hook: StringName, a_key: Variant, b_key: Variant) -> Variant
func compare_cache_put(hook: StringName, a_key: Variant, b_key: Variant, verdict: bool) -> void
```

### 1.9 Pulled-in cards (Q14=d, Q87=a, Q88=a, Q89=b)

```gdscript
## A card pulled into this meld from elsewhere on the board:
##  - joins this meld's Result.meld and CONTRIBUTES ITS POINTS (Q88=a);
##  - is NOT removed from its own row or column, and scores there in the same pass too (Q87=a) —
##    double-counting is the intended effect, not a bug to guard;
##  - must already exist on the board. Inventing a card is refused (Q89=b), which is what keeps
##    QR5 (multiplicity) genuinely out of scope.
```

⚠ `Game.score_line` (`Levels/game.gd:821`) banks per line, so a pulled-in card's points land in
both lines' gutters. That follows from Q87(a) and Q88(a) together and is intended.

---

## 2. Phases and steps

Every step leaves the game runnable and the full suite green.

⚠ **Each phase builds the doubles its own gate needs.** Gates 2 to 5 are self-checking, which means
they are tests, which means the doubles they name exist by the end of that phase — not in Phase 6.
Phase 6 is the **remaining** roster: the adversarial set, the degenerate inputs and the
combinations, which are the cases no single phase's gate reaches.

### Phase 1 — the class refactor, no behaviour change

- **S1 — HandProfile becomes class lists.** (implements Q20, Q21, Q22, Q24, QR2) Replace
  `RankMap.map` / `SuitMap.map` with `classes` arrays per §1.4, one class per distinct printed
  value, `mixed = false`, members in hand order. Update the reverse index and `remove_card`.
  *Done when:* `scoring.gd` compiles with no dictionary-keyed bucket access left.
- **S2 — every consumer reads classes.** (implements C8, Q95) The eight call sites: the straight
  gate `:406`, flush gate `:412`, grid `:460`, suit loops `:570` / `:731`, `_scan_linear` `:634`,
  `_scan_wrap` `:659` — `cnt[v]` **sums cards across every class whose key is v** — and `:468`,
  which switches from `datas[0]` to the class maximum (Q21).
  *Done when:* **the whole suite is green with byte-identical scoring results.**

⚠ **GATE 1, self-checking:** `test_scoring.gd` passes unchanged, with no edits to its expectations.
A single changed expected value means the refactor altered behaviour and must be fixed, not
re-baselined.

### Phase 2 — stage 0: the two passes and the cache

- **S3 — the hook surface.** (implements §1.1, QR3, Q62, Q97, Q80, Q83) Add the ten hook names and
  `compare_uncacheable` to `Cards/card_modifier.gd` as documented no-ops. Leave
  `on_compare_ranks/suits` untouched (Q55).
- **S4 — `pair_is_same`.** (implements D1, D2, D3, D4, D5, D6, D7, QR4, Q81, Q82, Q84, Q5) The two
  passes per §1.2, over deny/allow implementer lists, skills gated on spotlit.
- **S5 — the closure.** (implements C5, Q1, Q2, Q3) Transitive closure over **distinct keys**, one
  representative pip per key (Q1=a), union-find with path compression, smaller root wins so the
  class key is the minimum. Skip the dispatch when a pair is already merged.
- **S6 — the cache.** (implements I1, I2, I5, I6, I7, I9, Q40, Q41, Q90, Q91, Q42) Per §1.8,
  including the spotlight epoch in the key and the never-cache rule for base environments.

⚠ **GATE 2, self-checking:** with no card implementing any meld hook, a counting probe records
**zero** comparator dispatches during profiling and results are byte-identical to Phase 1. With one
deny rule that always answers false, dispatches per profile build are **≤ k(k+1)/2** for k distinct
keys — never the card-pair count.

⚠ The ceiling is `k(k+1)/2`, not the `k(k−1)/2` this gate first stated, because the closure asks
each **self-pair** `(k, k)` as well: a deny there is how a rule splits two ordinary 7s (Q82=a, D3).
Owner ruling, `gaps/GAP-001.md`. DESIGN §1d's ceilings move with it — 91 rank pairs and 15 suit
pairs, still independent of board size.

### Phase 3 — stage 1: whole-hand rules

- **S7 — the pipeline.** (implements C6, E1, E11, E12, Q10, Q16, Q18) Apply each implementer in
  board order after stage 0, feeding each the previous partition.
- **S8 — sanitize.** (implements E2, E4, E5, E6, E7, E10, Q11, Q12, Q94) Per §1.3 steps 3–6,
  including the deny re-check after unioning.
- **S9 — the empty return.** (implements E3, Q13, Q85) The NO_MELD sentinel through
  `PokerHands.score` to `Game.score_line` banking zero.
- **S10 — pulled-in cards.** (implements E8, E9, Q14, Q87, Q88, Q89) Per §1.9, with the
  board-reachability check that refuses an invented card.

⚠ **GATE 3, self-checking:** every adversarial double in §3 degrades as specified — the suite's
engine-error scan stays clean except where a `push_error` is itself the assertion — and a rule
returning its input unchanged produces a byte-identical result to no rule at all.

### Phase 4 — straights and adjacency

- **S11 — the position model.** (implements F1, F3, F4, F6, F7, Q93, Q95) Same-value classes spend
  every card; mixed classes spend one.
- **S12 — the search.** (implements F5, F8, F10, Q96) The cartesian enumeration in §1.5,
  deterministic in ascending member_key order, product 1 when nothing is mixed.
- **S13 — adjacency.** (implements H1, H2, H3, H4, H5, QR8, Q71, Q72) Extra values as class keys
  during profiling; wrap bounds via the hook.

⚠ **GATE 4, self-checking:** with no mixed classes the straight scanners run **exactly once** per
call (assert the assignment count is 1), and every existing straight test in `test_scoring.gd`
passes unchanged.

### Phase 5 — classification

- **S14 — `is_flush` reads the partition.** (implements G1, G2, G3, G4, G5, G6, Q25, Q26, Q27)
  Thread the profile into `build_multi` and both call sites.

⚠ **GATE 5, self-checking:** the paired fixture where a suit rule merges five distinct suits scores
**as a flush** and `is_flush` agrees — the two can no longer disagree on the same cards.

### Phase 6 — the rest of the roster

The doubles each gate named already exist by here. These are the cases no single gate reaches.

- **S15 — the remaining stage-0 and stage-1 doubles.** (implements Q4, Q5, Q23, Q30, Q33, Q34, Q63)
  Including the ones that pin a *limit* rather than a feature: Q33 and Q34 assert that nothing is
  shown to the player, so a later cue cannot appear by accident.
- **S16 — adversarial and degenerate doubles.** (implements Q15, Q19, Q92) `ReentrantMod` is the
  one that matters: `skill_eval_poker_best.gd:18` already scores from inside scoring, and Q92(b)
  means nothing catches it if it runs away.
- **S17 — combination checks.** (implements QR1, Q17, Q57) Two rules on one board, both orders,
  deterministic each way.
- **S19 — the mod-space fuzz suite.** (implements QR2, QR4, Q2, Q10, Q16, Q22, Q84, Q93, Q95, Q96)
  `Tests/Engine/test_mod_fuzz.gd` per §3b: the generator across every axis, the permutation sweep,
  and the twelve invariants. Follows `test_fuzz.gd`'s seed/log/reproduce conventions.
- **S20 — register the suite.** (implements Q92) Add `Tests/Engine/test_mod_fuzz.tscn` and a child
  of `Tests/all_tests.tscn`. ⚠ **The expected suite count goes 30 → 31.** Every gate below and
  START_HERE.md's "judge by the SUITE count (30)" line move with it, or the next agent reads a
  dropped suite as green.

⚠ **GATE 6:** `py solatro/Tools/run_tests.py` with `GODOT_BIN` set to this machine's console exe
(the ONLY home for that path is `.claude/memory/machine-profiles.md`) — **31 suites** once S20
lands, 30 before it, failure set empty. Judge by the suite count, not the check total: a drop means
a suite failed to LOAD while the banner still reads PASSED.

⚠ **GATE 7, the fuzz gate:** `test_mod_fuzz.gd` green over at least 200 iterations at a random
seed, with the seed printed. A failure prints the seed and the last actions; reproduce by setting
`fuzz_seed`. **Do not raise a bound or relax an invariant to go green** — every invariant in §3b
holds for any rule set by construction, so a failure is a real defect in the pipeline.

### Out-of-scope confirmations carried into the code

- **S18 — record the deferrals.** (implements QR5, QR6, QR7, Q50, Q52, Q53, Q54, Q55, Q56)
  One `TODO` per deferred mechanism at the site that would host it: multiplicity in
  `_get_hand_profiles_async`, class tags beside the closure, non-card rule sources in
  `_compare_implementers`, multi-meld membership in `ScoringSection`. Each names the question that
  deferred it, so the next person meets the decision instead of the absence.

---

## 3. Test plan

The roster from the confirmed answers. Doubles model authored cards where one exists; the
unsourced ones are marked. **Every case is paired with the same cards unmodded, on the same
`CardData` instances.**

**Stage 0:** `AllRanksSame`, `AllSuitsSame` (The Best Bower), `WithinOne` (non-transitive),
`ParityMatch` (two classes, not one), `NeverSame` (gate on, nothing merges — the dispatch ceiling),
`UnrelatedHook` (gate must not fire), `SpySkillCompare` (spotlit), `DenyTwoSevens` (a deny rule
splitting printed-same cards, Q82).

**Stage 1:** `AtMostOnePartner` *(unsourced — the SPLIT exerciser)*, `StampedLoner` *(unsourced)*,
`TurkCopiesBelow`, `CleverHansCopiesNeighbour`, `HumbugWhileCovered`, `WildcardJoinsRow`,
`RedWagonRuns` (now expected to **succeed**, per QR8), `IdentityPartition`, `PullsInNeighbour`
(Q14=d), `NoMeldPossible` (Q13=d).

**Adversarial:** `BadPartition`, `NullPartition`, `AliasingMod`, `MutatingMod`, `SuspendingMod`,
`ReentrantMod` — ⚠ not hypothetical, `skill_eval_poker_best.gd:18` already scores from inside
scoring — `BoardMutatingMod`, `InventsACard` (must be refused, Q89), `LyingUncacheable` (consults
randomness without declaring it; must produce the stale answer Q91 specifies, not an engine error).

**Degenerate inputs, each with a rule installed:** empty hand, one card, all stones, every card
already in one class, a 30-card board.

**Combinations:** merge-then-split (`AllRanksSame` + `AtMostOnePartner`); two deny rules and two
allow rules together (the two passes, Q84's stop-at-first); deny beating a sanitize union (Q94);
`Harlequin` + a suit merge (one appearance, not two); three rules stacked, both board orders,
deterministic each way; unspotlit skill plus type rule; `ReentrantMod` with
`skill_eval_poker_best`; any grouping rule plus `is_flush` (Q25); everything removed afterwards
(no cached partition survives).

**Straights:** three 7s still give the wrap scan three steps (Q95); a mixed class contributes one
card at its best position (Q96); a split pair gives two positions (Q22); an all-ranks-same rule
kills the straight (Q3, Q93).

**Must stay green unchanged:** `test_scoring.gd` in full, `test_dispatch.gd`, `test_patience.gd`,
`test_spotlight.gd`, `test_game_headless.gd`, `test_fuzz.gd`.

### 3b. The mod-space fuzz — ANY rules, in ANY order

⚠ **The roster above tests rules someone imagined. This tests the space they live in.** Every
double in §3 models a card that might ship; these deliberately do not. Their job is to occupy the
corners of the functionality space — every hook kind, every return shape, every carrier, every
order — so that a card nobody has drafted yet cannot find an unhandled combination.

New suite `Tests/Engine/test_mod_fuzz.gd`, following `test_fuzz.gd`'s conventions exactly: an
exported `fuzz_seed` (0 = randomize, always printed), an exported `iterations`, an action log with
the last N entries dumped on failure, **and the seed printed on success too, so any failure is
reproducible by setting `fuzz_seed`**.

**The generator.** Each round builds 0–4 `FuzzRule` modifiers by drawing independently from every
axis, so the cross-product — not a curated list — is what gets exercised:

| axis | draws |
|---|---|
| hook kind | meld-deny · meld-allow · meld-group · stack-deny · stack-allow · extra-values · wrap-bounds · none |
| domain | ranks · suits · both |
| predicate | always · never · same-parity · within-N · above-threshold · depends on a card property · depends on board position · seeded-random (genuinely random; nothing to declare — GAP-003) |
| group-rule shape | merge-all · split-all · singletonise · pull in a board card · return empty · return overlapping groups · return a foreign card · identity · reorder members · drop cards |
| carrier | type · stamp · status · skill (spotlit and not) |
| ~~cacheability~~ | ~~declares `compare_uncacheable` · does not~~ — **the axis is gone** (GAP-003): there is no second cacheability state to draw from |

**The order sweep.** For every generated rule set, run **every permutation** when there are ≤ 4
rules, and a seeded sample beyond. "Any order" is the claim; permutation is the only honest test of
it.

**The invariants — asserted after every scoring pass, for every rule set, in every order.** These
hold no matter what the rules do, which is what makes them worth asserting against random input:

1. **The partition is a partition.** Every scorable card sits in exactly one class per domain
   (except the declared multi-key case), no class is empty, and no card appears twice in one class.
2. **Class keys are legitimate.** Every class key is a printed value of one of its own members, or
   a value that member declared via `on_meld_extra_rank_values` (§1.7).
3. **The reverse index agrees.** `remove_card` over every card leaves every class list and both
   reverse maps empty — the check that catches a card being handed to two melds.
4. **Determinism.** The same seed, board and rule order produce an identical Result name, score and
   meld set across two consecutive runs.
5. **Order changes the answer, never the stability.** Two different permutations may legitimately
   differ (Q10=a), but each permutation is identical to itself across runs.
6. **Reversibility.** Removing every rule restores the unmodded baseline exactly — name, score and
   meld. A cached partition surviving a rule's removal fails here.
7. **Meld membership is legal.** Every card in `Result.meld` is in the hand, or is a board card a
   pull-in rule named (Q14=d). An invented `CardData` never appears (Q89=b).
8. **Straights obey the position model.** Any `STRAIGHT` result occupies consecutive positions and
   takes **at most one card** from each mixed class (Q93=d, Q96=c), and every card from a
   same-value class it uses (Q95=a).
9. **Flush agreement.** A Result carrying `FLUSH` satisfies `is_flush` on the same cards and
   profile (Q25=a) — formation and classification cannot disagree.
10. **Score sanity.** Finite, non-negative, and `copies_count` × `copy_size` consistent with the
    meld size.
11. **The engine error stream is clean**, except for the `push_error` cases a rule deliberately
    provokes, which are allowlisted by message.
12. **Termination.** Each scoring pass completes inside a wall-clock bound. ⚠ **This is the only
    thing standing between R1 and a hung suite** — Q92(b) declined a runtime backstop, so a
    runaway grouping rule is caught at test time or not at all. A timeout here is a real finding,
    not a flaky test.

---

## 4. Deliberately out of scope — the index is `DEFERRED.md`

Multiplicity (QR5=a) — The Forged Ace, Flea Circus. Class-tag grouping (QR6=a) — The Jongleur,
Greasepaint. Non-card rule sources (QR7=a) — The Fire Marshal. Multi-meld membership (Q54) — The
Courier, The Puszta Five. Half-step ranks and wider multi-suit (Q56). The repeated profile rebuild
per scored line (Q57). Player-facing cues for merges, splits and rule order (Q30, Q33, Q34).

## 5. Accepted risks, recorded not hidden

- **A grouping rule can hang a submit** (Q15=b, Q19=b, Q92=b): unlimited re-entrancy, no runaway
  accounting, no backstop.
- **The straight search has no cap** (§1.5). Bounded in practice by thirteen positions and by how
  many mixed classes a board holds; unmeasured, because **no benchmark exists for the scoring
  path** (PERFORMANCE.md §4d).
- **A split meld is invisible to the player** (Q33=a): three matching cards on screen, two counted,
  nothing explaining it.
- **Double-counted points** (Q87=a, Q88=a): a pulled-in card banks in two lines.

## 6. Owner verification, in the running game

1. Put a rank-merging rules card on the board; confirm a hand of five distinct ranks scores as a
   set, not High Card.
2. Remove it; confirm the same hand scores as it did before.
3. With a suit-merging rule, confirm five distinct suits score as a flush **and** take the Full
   Flush x2.
4. With a deny rule, confirm two printed 7s stop counting as a pair.
5. With a merging rule out, confirm a five-card run no longer scores as a straight.
6. Confirm a normal board with no rules cards plays exactly as it does today.
