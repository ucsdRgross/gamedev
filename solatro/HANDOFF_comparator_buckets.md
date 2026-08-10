# HANDOFF — comparator buckets

**Goal:** wire meld FORMATION to the mod comparator surface, so a rules card can decide which cards
count as the same. Done = `design/comparator_buckets/PLAN.md` phases 1–6 landed, GATES 1–7 green.

**State: landed and verified.** All twenty steps, all seven gates. `HandProfile` holds class lists;
stage 0 closes them over a two-pass deny/allow surface whose verdicts are fixed for the hand; stage 1
lets whole-hand rules rewrite the partition through `sanitize`; the straight scan searches over mixed
classes' candidate positions; adjacency arrives as extra class keys and a wrap-bounds hook; and
`is_flush` reads the same partition formation used. With no card implementing a meld hook the whole
pipeline is the identity path — zero dispatches, scoring unchanged. Suite count **31**.
**The contracts and landmines now live in `ARCHITECTURE_REVIEW.md` §3c** — this file is the stream's
state, not its rules. What remains is a playtest.

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

- **LEAK CANARY, +1 object, intermittent** — about 1 run in 6, unattributed. This work allocates
  `RankClass`/`SuitClass` per profile build. Next step: `LeakSentinel --verbose` on a failing run to
  name the survivor.
- **A playtest**, and the backlog items — both in `todo.md` under the comparator entry.
- ⚠ **The suite is not reliably green on a single run**, for reasons outside this stream: the
  run-save layer flakes about 1 run in 4–6 (`todo.md`, "Known intermittent test failures"). It
  reproduces sequentially, so it is not the overlapping-runs artefact I first took it for. Judge a
  comparator change by whether ITS suites moved, and re-run before believing a red.

## Next up

1. **Playtest** (todo.md, "Waiting on the owner"). The mechanics are proven; whether a merging card
   is fun, and whether a split meld reads as a bug (`DEFERRED.md` R2), are not test questions.
2. **Chase the leak canary** above.
3. **`DEFERRED.md` E1**, a benchmark for the scoring path — everything measured is hands of ≤8 cards.

## What this stream got wrong, and the shape of it

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
