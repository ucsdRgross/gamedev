# CODE_REVIEW.md — the overseer's own read of the diff against main

Written after reading the production source directly, having verified the whole run by grep,
suite banner, snapshot and agent report and never by reading code. **Every finding below was
invisible to that method**, which is the point of the document.

The pattern: `TEST_PLAN.md` rows drove verification, so anything the design fixes that no row
covers was never checked. Contract items with no test row are the blind spot, and four of them
are unimplemented.

## A — INTEGRATION HOLES: built, tested in isolation, never wired

These all pass their own tests. None of them does anything in the running game.

| # | Finding | Evidence |
|---|---|---|
| A1 | **`InfoCard` is not on the wall at all.** It is mounted only on the map (S29). `wall.tscn` and `wall.gd` reference it **zero** times. Info mode on the wall therefore displays nothing, and J1–J6 are green against a standalone card. | `grep -c InfoCard wall.tscn wall.gd` → 0, 0 |
| A2 | **The Info button is inert.** `WallOverlay.info_toggled` has **no consumer anywhere**, and nothing outside tests ever writes `wall_info_mode`. Info mode can currently only be entered by a test setting the flag. | `info_toggled` consumers: none |
| A3 | **`WallInput.PinchTracker` is never wired.** Referenced only by its own file and its test. Touch pinch does nothing in the app. | `grep -rl PinchTracker` → 2 files |
| A4 | **Three of five `NAMES.md` `Wall` signals are never declared:** `focus_changed`, `transition_started`, `transition_landed`. The registry fixes them; they do not exist. `wall_view_entered` and `picture_enter_requested` do. | `grep "^signal"` in `wall.gd` |

## B — DEFECTS in shipped logic

| # | Finding |
|---|---|
| B1 | **`WallPacker._clears_all` cannot reject an overlap when `gap_px == 0`.** It tests `_clearance(...) < gap_px - _EPS`; `_clearance` returns 0 for touching *and* overlapping rects, so at `gap_px = 0` the test is `0 < -1e-6`, always false. Every picture then "clears" at radius 0, they all stack on the centre, and rule 6 fires `push_error` and returns a one-rect prefix. `gap_px` is author-settable and S34 exposes it, so an author sliding it to 0 gets a broken wall. Fix: reject actual intersection independently of the gap. |
| B2 | **`_SELECTED_LIFT := Vector2(0.0, -14.0)`** in `wall_picture.gd` is a tunable literal — how far a selected picture lifts is a visible design choice, S36's "highlight by lift plus outline". Same class as `_OVERFILL_MARGIN` (GAP-011) and the shadow opacity (GAP-013). §1.8 makes it a defect. |

## C — STALE COMMENTS that assert something untrue

Each claims work is unbuilt or belongs to "a later step" that has since landed. `doc_check` cannot
see these — they name no file.

- `wall_layout.gd:8` — "the packer's contract; **not yet built, parked on GAP-009**". It is built.
- `wall_input.gd:11` — the `_unhandled_input` wiring is "a later integration step". It exists.
- `wall_input.gd:64` — `PinchTracker` "Wall owns it, a later integration step". Wall does not own
  it (see A3) — the comment describes an intention, not the code.
- `wall_transition.gd:159`, `wall.gd:102`, `wall_overlay.gd:8` — same shape.
- `picture_entry.gd` class doc still says "angle" for `slot`, which GAP-010 demoted to placement
  order.

## D — What the review CONFIRMED as sound

Stated because a review that only finds fault is not a review.

- **The knob set has no drift**: 22 `wall_*` exports, 22 §5 rows, exact match both ways.
- `WallPacker` is genuinely pure — no singletons, no node access, deterministic; the bisection
  returns the smallest clearing radius and is frame-rate independent.
- `FocusStack` matches §1.4 exactly: five methods, no sixth, depth bounded by distinct ids.
- `ProfileManagerClass` uses the `settings_manager` pattern as specified, not the threaded one,
  and its one `push_error` is genuinely the single corruption path R6 asserts.
- `Pacing` is correct, including the `as SceneTree` cast that PLAN's own snippet omits.
- `InfoCard` sizes synchronously from font metrics rather than trusting a deferred layout pass —
  the fix for a real bug, and it is the right shape.

## E — The verification lesson

`TEST_PLAN.md` is not a contract checklist; it is a *test* list. **Q88/Q99 (click and `ui_accept`
to enter) shipped unimplemented for four phases** because no row covered them, and A1–A4 are the
same failure repeated. Anything fixed by `NAMES.md`, by a `Q`-answer, or by a chart node **but not
rowed in `TEST_PLAN.md` has never been systematically checked in this run.**

A future run should audit DESIGN's answered questions and `NAMES.md`'s registries against the
implementation directly, as a step, rather than assuming the test plan's coverage implies the
contract's.
