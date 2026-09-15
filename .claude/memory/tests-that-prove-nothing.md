---
name: tests-that-prove-nothing
description: "The ways a test passes while asserting nothing, and the red-then-green rule that catches all of them"
metadata:
  type: feedback
---

A green suite is the weakest evidence there is. Every test below passed review while proving nothing:

1. `await some_timer` instead of `await some_timer.timeout` — awaiting a non-signal resolves
   instantly, so the wait never happens.
2. **GDScript lambdas capture outer locals BY VALUE.** `var fired = false` then `func(): fired = true`
   writes to a copy. Box it in a one-element `Array`.
3. **A fixture chosen so the implementation passes** — a symmetric pair hiding an asymmetric defect,
   or "settle every item first" so the interesting one is never in the interesting state.
4. **A leak that is not a check failure** — a class extending `Node`, not `RefCounted`, needs an
   explicit `.free()`.
5. **A loop or sampler whose body never runs, or a chosen target that is degenerate.** Assert the
   sample count is non-zero *before* asserting anything about its contents, and that a picked target
   has extent: `Rect2.encloses` accepts a zero-area rect, so a zero-height cell passed vacuously.
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
    ⚠ **Event ORDER is part of "the way the platform does".** Godot delivers a touch's emulated
    mouse form (`device == -1`) BEFORE the `InputEventScreenTouch`, at press and at release; helpers
    pushed the reverse twice on one branch.
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

14. **The test is the only caller.** A production function whose ONLY callers are tests is dead
    code that its own suite makes look live — the suite is green, the function is exercised, and
    nothing in the shipped game ever reaches it. Measured on one branch: THREE of them, one with a
    whole suite devoted to it, one unreachable from shipped content because the API exposes no
    wrapper for it. ⚠ This inverts the usual reading of coverage: **the tests are not evidence the
    code is used; they can be the only thing using it.** Ask of any function a test exercises: who
    else calls this?

15. **A FILTERED run read as a full one.** `--filter` and `--logic` void the suite count, the only
    load-failure detector, so only the full unfiltered windowed run is a verdict —
    [[running-godot-scenes]].

16. **A settle that waits two process frames.** Both can land inside one physics tick, so the value
    has not moved yet (1 failure in 4 runs). Await `physics_frame` or the moved value itself. Same
    shape: a `queue_free`d node stays a child, and a container's extent lags, until the frame ends.

17. **A test defined but never registered in `_ready`.** It never runs and cannot fail. Solatro's
    suites call `check_all_tests_registered()` to make that a failure.

18. **A reviewer's "none" is a claim too.** A test-surface review reported no test-only production
    names while a later pass found one. Grep the negative before recording it.

**The rule that catches every one: prove every new test red-then-green**, and **compare PER-SUITE
check counts across the red and green runs** — a suite whose count dropped had assertions silently
skipped, which the drifting total cannot show. The procedure and its two traps (a red run that
failed the wrong checks; adjusting a test a fix turned red) are `/plan-run`'s "Red-then-green is
mandatory". Applies to any suite in any project here.

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

Diagnosing a red, hung or flaky RUN (not a test): [[running-godot-scenes]].
