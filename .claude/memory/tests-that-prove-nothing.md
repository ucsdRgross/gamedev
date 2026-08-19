---
name: tests-that-prove-nothing
description: "Ten ways a test passes while asserting nothing, and the red-then-green rule that catches all of them"
metadata:
  type: feedback
---

A green suite is the weakest evidence there is. One run produced **eight** tests that passed while
proving nothing, each of which looked fine in review; a later run added the ninth:

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
   node, a running tween). If the banner reports a failure you cannot find in your own suite,
   suspect your fixture's side effects.
9. **A fixture that clears the very global state the feature runs under.** Every `Main`-based test
   in solatro wrote `get_tree().paused = false` right after `add_child()`; the shipped game holds
   the tree paused for the whole session. That one habit hid a total soft-lock, a timer that never
   fires, and a camera resting at the wrong zoom — all three green, for a whole run. Ask what
   ambient state the real product runs under, and whether the fixture just turned it off.

10. **Two competing mechanisms with the SAME observable.** A test can pass because the WRONG
   mechanism happens to produce the right answer. Measured: a re-pack test passed with its fix
   removed, because the stale tween and the correct one wrote the same property every frame and the
   later one landed last — the defect was real and invisible. Separate the two before asserting
   (there, by making the stale animation outlive the correct one) or the test is measuring which
   writer ran second.

**The rule that catches all ten: prove every new test red-then-green.** Neutralise the behaviour,
watch it fail, restore it, watch it pass. A test that has only ever been green may be asserting
nothing. ⚠ **Check the red run failed the checks you EXPECTED.** A neutralisation that breaks the
test instead of the behaviour — one that returns the wrong type, say — aborts the test function on
the spot, and the banner then reads `ALL N CHECKS PASSED` with the assertions silently missing.
Measured: a bad cast did exactly that while two tests never ran. When a fix makes an existing test fail, investigate before adjusting it — see item 7 above.

Applies to any suite in any project here. See [[running-godot-scenes]] for what a banner does and
does not prove.
