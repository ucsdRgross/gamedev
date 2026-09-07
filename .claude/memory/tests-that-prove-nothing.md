---
name: tests-that-prove-nothing
description: "The ways a test passes while asserting nothing, and the red-then-green rule that catches all of them"
metadata:
  type: feedback
---

A green suite is the weakest evidence there is. One run produced **eight** tests that passed while
proving nothing, each of which looked fine in review; later runs added two more:

1. `await some_timer` instead of `await some_timer.timeout` — awaiting a non-signal resolves
   instantly, so the wait never happens.
2. **GDScript lambdas capture outer locals BY VALUE.** `var fired = false` then `func(): fired = true`
   writes to a copy. Box it in a one-element `Array`.
3. **A fixture chosen so the implementation passes** — a symmetric pair hiding an asymmetric defect,
   or "settle every item first" so the interesting one is never in the interesting state.
4. **A leak that is not a check failure** — a class extending `Node`, not `RefCounted`, needs an
   explicit `.free()`.
5. **A loop or sampler whose body never runs.** Assert the sample count is non-zero *before*
   asserting anything about its contents.
6. **An assertion on a local the production path never touches** — it re-proves a data structure's
   own arithmetic while being unable to fail for the wiring bug it exists to catch.
7. **A tolerance calibrated to a bug** — it passes *because* the defect exists, and goes red when
   someone fixes it.
8. **A new test that breaks a DIFFERENT suite** via global state left behind (a pause flag, a live
   node, a running tween). A failure you cannot find in your own suite means suspect your fixture.
9. **A fixture that clears the very global state the feature runs under.** Every `Main`-based test
   wrote `get_tree().paused = false` right after `add_child()`; the shipped game holds the tree
   paused for the whole session. That one habit hid a total soft-lock, a timer that never fires and
   a camera resting at the wrong zoom — all three green for a whole run. **Ask what ambient state
   the real product runs under, and whether the fixture just turned it off.**
10. **Two competing mechanisms with the SAME observable.** A test can pass because the WRONG
    mechanism happens to produce the right answer. Measured: a re-pack test passed with its fix
    removed, because a stale tween and the correct one wrote the same property every frame and the
    later one landed last. Separate them before asserting, or the test measures which writer ran
    second.

11. **The test drives an INTERNAL handler, so it proves the reader and never the ROUTE.** Measured,
    and it shipped a dead feature: a touch-swipe reader was correct and fully covered, but both its
    tests called the node's input handler directly. Driven the way the engine delivers an event —
    through the viewport — nothing happened at all, because an ancestor consumed it first. **If a
    behaviour depends on an event REACHING your code, the test must send it the way the platform
    does.** Green tests plus a feature no user could trigger.
12. **The test SETS UP the very condition whose absence is the bug.** Measured: a "no cut-off grid
    at rest" test called the centring routine itself before measuring — the one call the resting
    product never made — so it could not see that nothing positioned the view at startup. **A test
    that arranges the state it is meant to observe is a tautology.**

13. **The check asserts a field the product does not READ.** Not item 7's calibrated tolerance — a
    whole assertion pointed at a RETIRED accumulator that still moved. Measured: a status-effect
    test asserted `col_total == 3` and passed for the life of a rewrite, while the points were
    banking into a legacy total the shown score is not derived from. **It passed BECAUSE the defect
    existed**, and it certified the loss it was written to catch. Ask of every green check: *is this
    the value the player is shown, or merely one that changes?* A retired field is the most
    dangerous kind, because it still moves.

**The rule that catches every one: prove every new test red-then-green.** Neutralise the behaviour,
watch it fail, restore it, watch it pass. A test that has only ever been green may be asserting
nothing.

⚠ **Check the red run failed the checks you EXPECTED.** A neutralisation that breaks the TEST rather
than the behaviour — returning the wrong type, say — aborts the test function on the spot, and the
banner then reads `ALL N CHECKS PASSED` with the assertions silently missing. Measured: a bad cast
did exactly that while two tests never ran.

⚠ When a fix makes an existing test fail, **investigate before adjusting it** — see item 7.

⚠ **Compare PER-SUITE counts across the red and green runs.** If every suite reports the same number
of checks in both, nothing aborted; a suite whose count DROPPED in the red run had assertions
silently skipped. This is the sharpest cheap evidence available, and it is stronger than the total,
which drifts whenever a randomised suite is in the run.

Applies to any suite in any project here. See [[running-godot-scenes]] for what a banner does and
does not prove.

## ⚠ RED-THEN-GREEN IS NECESSARY, NOT SUFFICIENT

It proves a check RESPONDS to the change. It does not prove the check measures what a player sees.

Measured: a row-label alignment check went red without its fix (5 failures) and green with it, and
was **still measuring the wrong thing** — its fixture banked one score per row, so the grid-wide
level count never exceeded one, so the overflow that causes the defect could not occur. The suite
said fixed; the rendered board plainly showed the bug. **Only the by-eye gate caught it.**

⚠ **THE FIXTURE MUST VARY THE QUANTITY THAT DRIVES THE DEFECT, NOT THE ONE THAT DESCRIBES IT.**
The visible symptom was uneven CARD DEPTHS; the driving variable was uneven BANKED SCORE LEVELS.
Specifying the symptom produced a check that passed against a broken implementation.
Same shape elsewhere: a zoom-dependent bug is invisible while the harness never leaves zoom `1.0`,
because `1.0 * anything == anything`.

## ⚠ RUN THE SUITE ALONE TO DISCRIMINATE CROSS-SUITE INTERFERENCE

When a failure is reproducible but its cause resists explanation, **run that suite by itself.**
Measured: two checks failed at every commit on a branch and survived five different diagnoses
(a settings value, contention, chain serialisation, a real geometry defect, a settling instrument).
The suite alone passed 74/74 with a 0.0 px delta. **Deterministic interference reads exactly like a
deterministic bug** — a constant value looks like geometry and is not.
⚠ The tell is a **rotating casualty**: the same suites pass alone and fail together while WHICH
check fails changes run to run. That is one problem, not several.

⚠ **A RUN CAN ALSO STALL WITH NO OUTPUT AT ALL, AND THAT LOOKS LIKE A BROKEN BUILD.** Measured: a
suite printed its banner and then emitted ZERO checks for 27 minutes until the global timeout killed
the run, reporting `NO SUITE BANNER — the run did not reach its own verdict`. Run alone the same
suite passed 215/215 in a minute. **A slow suite still streams checks; a silent one after its banner
is stalled.** It was 1 run in 6, so a single timeout is not evidence a branch is broken — re-run
before concluding, and never revise a commit's claimed green result on one sample.

⚠ **DO NOT NAME A CAUSE YOU HAVE NOT MEASURED.** That stall was blamed first on concurrent suites
(the suite had none — every sibling it excluded waited for IT) and then on an unbounded settle loop
(every wait on the path was bounded). Both were reasoned, both were written into a living doc, and
both were wrong. What the evidence actually supported was much narrower: the log flushes per line, so
the stall sat between two consecutive log writes, in a window with no loop, no await and no branch.

⚠ **PRESERVE THE LOGS BEFORE RE-RUNNING.** The harness reopens its log with truncate, so every
subsequent run destroys the evidence of the stalled one. Copy the log directory aside the moment a
run looks stuck — otherwise the only artefact of a 30-minute hang is that it happened.

⚠ **A GLOBAL TIMEOUT IS NOT A WATCHDOG.** With only a whole-run wall clock, ONE stalled suite eats
the entire budget and the runner discards the verdict of every other suite — the 44 that were fine
report nothing. A per-suite silence detector that NAMES the quiet suite turns a 30-minute mystery
into an attributable failure, and is worth building before chasing the cause.
