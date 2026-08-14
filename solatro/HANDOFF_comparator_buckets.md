# HANDOFF — comparator buckets

**Goal:** wire meld FORMATION to the mod comparator surface, so a rules card can decide which cards
count as the same. Done = `design/comparator_buckets/PLAN.md` phases 1–8 landed, GATES 1–8 green.

**State: landed and verified.** All twenty-six steps, all eight gates. `HandProfile` holds class lists;
stage 0 closes them over a two-pass deny/allow surface whose verdicts are fixed for the hand; stage 1
lets whole-hand rules rewrite the partition through `sanitize`; the straight scan searches over mixed
classes' candidate positions; adjacency arrives as extra class keys and a wrap-bounds hook; and
`is_flush` reads the same partition formation used. With no card implementing a meld hook the whole
pipeline is the identity path — zero dispatches, scoring unchanged. Suite count **31**.
**The contracts and landmines now live in `ARCHITECTURE_REVIEW.md` §3c** — this file is the stream's
state, not its rules.

**What remains is a BALANCE call and one UX call — not functionality.** Two adversarial reviews have run against this work. The first opened
Phase 7 and found the real defect — S21: Q83(a) gives every situation its own deny/allow pair, and the
four `on_stack_*` hooks were declared, documented and **dispatched by nothing**, while the placer and
grabber still asked `is_suit_same`, the ORDERING hook. ⚠ **That omission was PLAN's, not the
executor's** — S3 said "add the hook names" and no step said "route stacking through them". The second
review opened Phase 8: GATE 8 proved a meld rule cannot reach stacking, but nothing proved the
converse. Both phases are landed; both directions are now asserted.

**Entry docs:** `ARCHITECTURE_REVIEW.md` §3c (contracts), `design/comparator_buckets/DESIGN.md`
(behaviour authority), its `PLAN.md` (build order; ⚠ §1.8 superseded by GAP-003), `DEFERRED.md`
(what was deliberately left undone — read before concluding something is missing), `ASSUMPTIONS.md`,
`gaps/`.

⚠ PLAN §0: Q96(c) supersedes Q20(c); Q93(d) supersedes Q23(b). The superseded behaviour must not be
implemented. Three gaps were raised: **GAP-001** answered by the owner (a deny may split two printed
7s, so the closure asks self-pairs and the ceiling is k(k+1)/2), **GAP-002 withdrawn** (it was my bug,
not a design hole), **GAP-003** an owner ruling that supersedes Q41/Q90/Q91 (a verdict is fixed for
the hand; `compare_uncacheable` deleted).

## Tasks
```yaml
- id: S1
  description: HandProfile becomes class lists (RankClass/SuitClass, PLAN §1.4).
  status: done
- id: S2
  description: Every consumer reads classes; GATE 1.
  status: done
  evidence: 'test_scoring.gd green with ZERO edits to its expectations'
- id: S3
  description: The hook surface — ten hook names, declared as comments not methods (PLAN §1.1).
  status: done
- id: S4
  description: pair_is_same — the two passes, deny then allow, printed values on silence.
  status: done
- id: S5
  description: The closure over distinct keys, union-find; plus GAP-001's self-pair split.
  status: done
  evidence: 'GATE 2: exactly k(k+1)/2 dispatches per build, never the card-pair count'
- id: S6
  description: The verdict memo — per SCORING PASS, per gaps/GAP-003.md (not PLAN §1.8's shape).
  status: done
  evidence: 'a full scoring pass asks each distinct key pair exactly once; the NEXT pass re-asks'
- id: S7
  description: Stage 1 pipeline — whole-hand rules in board order, each seeing the previous partition.
  status: done
- id: S8
  description: sanitize — overlaps union (transitively), deny re-check, omissions, hand-order re-sort.
  status: done
- id: S9
  description: The empty return — NO_MELD through PokerHands.score to score_line banking zero.
  status: done
- id: S10
  description: Pulled-in cards join the meld; an invented one is refused (Q89=b).
  status: done
- id: S11
  description: The position model — same-value classes spend every card, mixed classes one.
  status: done
- id: S12
  description: The straight SEARCH — cartesian over mixed classes, product 1 when nothing merged.
  status: done
  evidence: 'GATE 4: one assignment with no mixed class'
- id: S13
  description: Adjacency — extra values as class keys, wrap bounds via the hook.
  status: done
- id: S14
  description: is_flush reads the partition; profile threaded into build_multi and both call sites.
  status: done
  evidence: 'GATE 5: a suit rule forms a flush AND is_flush agrees on the same cards'
- id: S15
  description: Remaining stage-0/1 doubles — spotlit gating, and the limits that must stay limits.
  status: done
- id: S16
  description: Adversarial and degenerate doubles.
  status: done
- id: S17
  description: Combination checks — two rules, both orders, deterministic each way.
  status: done
- id: S18
  description: Record the four deferrals as TODOs at the sites that would host them.
  status: done
- id: S19
  description: The mod-space fuzz — generator, permutation sweep, twelve invariants.
  status: done
  evidence: 'MOD FUZZ: 401 checks — 200 rounds uncached, 200 on a cacheable board, plus the carrier axis'
- id: S20
  description: Register the suite; expected suite count 30 -> 31.
  status: done
  evidence: '======== ALL 31 SUITES: ... CHECKS PASSED ========'

# --- Phase 7, added after the adversarial review of the landed commit --------------------
- id: S21
  description: Route stacking legality through the STACK hooks (F1 — the surface was inert).
  status: done
  evidence: 'GATE 8 both halves [PASS]: a stack deny flips a placement; the same rule as a MELD hook does not'
  notes: >-
    The placer and grabber called `is_suit_same`, which dispatches the ORDERING hook — the
    cross-situation reuse Q62(a) removed. Both now call `PipComparator.stack_suits_same`.
    ⚠ `is_suit_same` and `is_rank_same` are DELETED, not kept: they answered a sameness
    question through the ordering hook, which is the trap that left this inert for a whole
    phase. Rank ADJACENCY still uses `compare_ranks` (Q55=a). Recorded in ASSUMPTIONS.md.
- id: S22
  description: Test the stacking situation — the file contained "stack" zero times.
  status: done
  evidence: 'test_comparator.gd section 13, 8 checks [PASS]'
- id: S23
  description: Gate the extra-values dispatch (F2); same fix applied to wrap bounds.
  status: done
  notes: >-
    Both are now asked ONCE per profile build / per sequence call instead of per card / per
    assignment. `CardEnvironment.has_implementer` is the gate the closures already used.
- id: S24
  description: Attribute the leak (F3).
  status: done
  evidence: 'exit-time ObjectDB leak is 4 BEFORE any of this work and 4 now — unchanged, pre-existing'
  notes: >-
    The review noted no pre-commit baseline had been measured. There was one: the very first
    suite run of this stream, before any edit, already reported "4 ObjectDB instances were
    leaked at exit". The intermittent CANARY +1 is a separate measure and already
    self-attributes via `_report_growth` when it fires; see todo.md for the hunt's outcome.
- id: S25
  description: Strike the dead §1.8 contract (F5).
  status: done
  notes: 'Done in the plan itself by the owner; the shipped pass-memo API is what §1.8 now prints.'

# --- Phase 8, from the second review ------------------------------------------------------
- id: S26
  description: Assert the situation isolation in BOTH directions, not just meld-does-not-reach-stack.
  status: done
  evidence: 'a stack deny rule that would shatter every suit leaves both partitions and the score byte-identical [PASS]; fuzz invariant 13 exercised on ~50 of 400 rounds'
  notes: >-
    GATE 8 proved only one direction. The partitions are compared as class keys PLUS member
    identities, not counts — a reshuffle preserving counts is the only interesting way this
    could break. The fuzz covered partition VALIDITY under stack rules but never INVARIANCE;
    invariant 13 adds it, and the suite REPORTS how many rounds actually drew a meld-blind
    rule set, because an invariant that never runs reads exactly like one that passes.
```

## Verified

Run `py solatro/Tools/run_tests.py`, `GODOT_BIN` from `.claude/memory/machine-profiles.md`,
**WINDOWED**, **one run at a time**. Judge by the **suite count (31)** and the empty failure set —
the check total varies because the fuzz suites randomise.

- **GATES 1–7 all green**, each self-checking in the suite rather than asserted here.
- **PLAN §6's six in-game checks — through a REAL `Game`.** `test_game_headless.gd`'s "COMPARATOR
  RULES CARDS, THROUGH A REAL GAME" builds a board with comparator rules cards in `rules_deck` and
  calls `submit()`: the real cascade scorer, `SkillEvalPokerBest`, `score_line` and the gutters, with
  a real `_revision_key()`, a real `CardDataIterator` and real spotlight resolution. Each check is
  paired against the same board unmodded.
- **The pass memo**, including that every pass opened is closed (a stranded depth would silently
  share one hand's verdicts with the next and nothing would look wrong).
- **The fuzz on a CACHEABLE board as well as an uncached one.** `FakeEnvironment` never cached, so
  before this the suite exercised a path the game never took.
- **Performance:** slowest scoring pass, printed every run, ~20–50 ms. It was 23 s until the
  `member_keys` defect in GAP-002 was found.

## Open

- **LEAK CANARY, +1 object, intermittent** — unattributed, and this stream is a suspect because it
  allocates `RankClass`/`SuitClass` per profile build. Rate, instrumentation and next step live in
  `todo.md` under "Known intermittent test failures"; do not restate them here.
- **A playtest**, and the backlog items — both in `todo.md` under the comparator entry.
- ⚠ **The suite is not reliably green on a single run**, for reasons outside this stream: the
  run-save layer flakes about 1 run in 4–6 (`todo.md`, "Known intermittent test failures"). It
  reproduces sequentially, so it is not the overlapping-runs artefact I first took it for. Judge a
  comparator change by whether ITS suites moved, and re-run before believing a red.

## Next up

1. **The balance call** (todo.md). `Tests/Engine/scoring_cost.tscn` prints what a rule is WORTH:
   a rank-merging rule multiplies a scored line by x2.0 / x3.5 / x6.0 / x5.1 at 5 / 8 / 13 / 30
   cards, and every line of a submit gets it. Extra rank values alone are x1.0. ⚠ The only other
   open judgement is `DEFERRED.md` R2 — whether an unexplained split reads as a bug to a human.
   Everything else about this feature is asserted in the suite.
2. **Chase the leak canary** above.
3. **`DEFERRED.md` E6 — an owner call, and the one number this stream owes.** The IDENTITY path is
   the path every real game takes (no shipped card implements a meld hook) and it costs **~2x what
   it did before this work**: 30 cards, no rules, 5.01 ms → 9.15 ms, and 1.9–2.7x at every smaller
   size. Measured, not diagnosed — suspects in `DEFERRED.md` E6, numbers in `PERFORMANCE.md` §4d.
   ⚠ E1 is DONE (`Tests/Engine/scoring_cost.tscn`, 5/8/13/30 cards), so E2/E3/E4 are measured now.

## What this stream got wrong — now folded into ARCHITECTURE_REVIEW §10

⚠ **§10 is the durable copy; this file gets deleted after the playtest.** It catalogues the
assumptions that cost time (a double that could not cache, "cannot run in the real game", a hook
surface nobody routed, a 23 s measurement escalated without checking it against the design's own
words, a suspected defect never tested, an intermittent failure explained away) and names the check
that now fails for each. The cross-project halves went into
`.claude/memory/no-mocks-in-tools.md` and `design-answers-need-a-claimant.md`.

## The short version

Worth two minutes before trusting the rest. Three defects reached "reported as done":

- **A 23 s scoring pass** I filed as a gap against the DESIGN's uncapped search. The owner rejected
  the premise; §1.5 already specified the product is 1 when nothing merged, and my code violated it.
  I had a plausible explanation and stopped.
- **One card spending several steps in one meld** — I reasoned it might be possible and did not test
  it until asked. It was, in three separate places.
- **"The cache can't be tested"** and **"nothing can run in the actual game"** — both false. A
  cacheable environment is four lines; the real-`Game` harness already existed.

Every one was invisible in results: scores were correct throughout. The new checks assert
*mechanisms* — assignment counts, dispatch counts, card identity — rather than outcomes, for that
reason.

## References

- `ARCHITECTURE_REVIEW.md` §3c — the landed contracts and landmines.
- `design/comparator_buckets/` — DESIGN (65 answers, nine charts), PLAN (§1 contracts, §2 gates,
  §3 test roster), DEFERRED (D1–D5, E1–E5, R1–R4), ASSUMPTIONS, gaps/GAP-001…003.
- `.claude/memory/running-godot-scenes.md` — run the suite yourself, windowed, one at a time.
