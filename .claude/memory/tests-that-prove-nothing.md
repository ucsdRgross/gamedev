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
   Same shape: a check that cannot fail at all - `check(true, ...)`, an assertion on a constant, or
   a comparison of two things that are equal when both are empty.
6. **An assertion on a local the production path never touches** — it re-proves a data structure's
   own arithmetic while being unable to fail for the wiring bug it exists to catch. Same shape: an
   EXPECTED value computed by the production function under test (`viewport.size ==
   wp.render_size(...)`) - it cannot fail for a wrong formula. Assert an engine-visible property
   the formula is meant to produce, measured independently.
7. **A tolerance calibrated to a bug** — it passes *because* the defect exists, and goes red when
   someone fixes it.
8. **A new test that breaks a DIFFERENT suite** via global state left behind (a pause flag, a live
   node, a running tween) — **or via a no-op BROADCAST**: a teardown that writes a shared setting
   to the value it already holds, into a setter that emits unconditionally, restyles every live
   listener in the suites still running. Measured: one suite's `finish()` turned a pixel check red
   in the suite after it, deterministically, with nothing "left behind". A failure you cannot
   find in your own suite means suspect your fixture — and your teardown. Discriminate with the
   runner's filter: the two suites together red, the victim alone green.
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
    pushed the reverse twice on one branch. ⚠ **After a pad route, assert the FOCUS OWNER in the
    viewport the pad moves on next** - two rows asserted only the state change and both features
    stranded the pad ([[godot-key-events-no-bubble]]).
    ⚠ **A wheel notch is a press AND a release.** Godot's viewport keeps mouse focus from any button
    press until its release, the wheel's included, so a pushed press alone sends the NEXT click to
    the control under the notch, not to what the pointer is over. Push both, as `_push_wheel_notch`
    does. Measured (4.7.2, Windows): a harness's press-only notches sent a Deck click to the list
    behind it; the platform sends the release.
12. **The test SETS UP the very condition whose absence is the bug.** Measured: a "no cut-off grid
    at rest" test called the centring routine itself before measuring — the one call the resting
    product never made — so it could not see that nothing positioned the view at startup. **A test
    that arranges the state it is meant to observe is a tautology.** Measured again: a determinism
    fixture called `seed(...)` on the global generator before the show started, which the shipped
    deck shuffle never does, so "the same node deals the same board" was true only in the test.

13. **The check asserts a field the product does not READ.** Not item 7's calibrated tolerance — a
    whole assertion pointed at a RETIRED accumulator that still moved. Measured: a status-effect
    test asserted `col_total == 3` and passed for the life of a rewrite, while the points were
    banking into a legacy total the shown score is not derived from. **It passed BECAUSE the defect
    existed**, and it certified the loss it was written to catch. Ask of every green check: *is this
    the value the player is shown, or merely one that changes?* A retired field is the most
    dangerous kind, because it still moves — and it survives rewrites: a branch re-fixtured that
    very test and left the assertion on the retired field, while the test beside it carried the
    comment explaining why not to.

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

16. **A settle that waits N process frames.** Two can land inside one physics tick, so the value
    has not moved yet (1 failure in 4 runs); and N frames is a frame-rate-dependent TIME — 30
    frames measured 45 ms on a box running the windowed suite at ~660 fps, under the 50 ms a
    delta-integrated scroll needed for its first whole pixel, so a check green for months went red
    on identical bytes. Await `physics_frame`, summed delta, or the moved value itself. Same shape:
    a `queue_free`d node stays a child, and a container's extent lags, until the frame ends.

17. **A test defined but never registered in `_ready`.** It never runs and cannot fail. Solatro's
    suites call `check_all_tests_registered()` to make that a failure.

18. **A reviewer's "none" is a claim too.** A test-surface review reported no test-only production
    names while a later pass found one. Grep the negative before recording it.

19. **A strict comparison against a value the product places EXACTLY on the boundary.** The
    isolation buffer put a neighbour's edge precisely at the view's edge, and `>` flipped on the
    last float ULP (`-393.9999` red, `-394.0000` green) — 3 runs in 7, on identical bytes,
    diagnosed as a settle race until a print showed everything at rest. Decide the touching case
    explicitly (`is_equal_approx`), and **measure a flake before changing the wait**: the
    diagnosis is a claim, the print is the evidence.
20. **A test that BRANCHES on what the product did, and passes on both branches.** `if viewer
    still open: assert A else: assert B` - measured: the product took each branch in 3 of 6 full
    gates on unchanged code, so the gate stayed green while the game behaved two ways. The only
    trace was a per-suite count that moved by 3. Two possible outcomes is a finding: pin the
    product to one and assert only that one. Same shape: a gate that SKIPS its later checks when a
    walk fails shrinks the per-suite count instead of going red.
21. **A teardown that frees the scene while an awaited product flow is still running.** A row
    pressed Travel, asserted, and freed Main while the token was still walking onto a node whose
    arrival builds a viewer: an intermittent RID / GL texture / PagedAllocator leak at exit (1 run
    in 5), invisible to every check. See the flow through before teardown, and read the EXIT
    PROFILE of every run, filtered ones included.
22. **A row measured in the HARNESS's window, not the player's.** Solatro's booted-Main fixtures run
    inside a test SubViewport whose content scale is 1, while the shipped window's scale varies
    (0.52 at 600x1000 under canvas_items/expand). A "draws at the UI size" or layout row that passes
    there has proven the harness's geometry; the real window differs by its content scale. For a
    size, scale or layout claim, assert it at a real window size in an embedded `Window` stretched as
    the root is (below), or state in the row that it is harness-scale only - and cover the real
    window with a shot.
    ⚠ A suite inside the gate's shared run cannot resize the OS window: the full gate did not grant
    `window_set_size`, and every suite shares that window - which stays at the project's base size,
    so the ROOT's content scale there is 1, the harness's own. Host the row in an embedded `Window`
    carrying the root's `content_scale_*` (Solatro: `TestMainHost.boot_in_players_window`): measured
    1.111 at 1280x720 and 0.521 at 600x1000. Make it `unfocusable` and place it off the root's rect,
    or it takes the root's input while it lives. A mutant that only multiplies by the content scale
    must turn such a row red while every harness row stays green.

**The rule that catches every one: prove every new test red-then-green** — neutralise the
behaviour, watch the test fail, restore it, watch it pass, report both — and **compare PER-SUITE
check counts across the two runs**: a suite whose count dropped had assertions silently skipped,
which the drifting total cannot show. Applies to any suite in any project here.

- ⚠ **The red run must fail the checks you EXPECTED.** A neutralisation that breaks the TEST rather
  than the behaviour aborts the test function, and the banner reads all-passed with those
  assertions silently missing.
- ⚠ **When HEAD cannot run the new test** (new node paths, a restructured scene), "it could not be
  red on HEAD" is no exemption: prove it red with a MUTANT on the new code that breaks exactly the
  property the row claims (the old formula back, the overlap restored, the container swapped), one
  mutant per PROPERTY the row claims; a second only when the row's assertions could pass
  independently. Measured: four mutants on one restructured menu each turned their row red.
- ⚠ **A fix that turns an existing test red is investigated before the test is touched** - item 7's
  calibrated tolerance was found exactly that way.

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
