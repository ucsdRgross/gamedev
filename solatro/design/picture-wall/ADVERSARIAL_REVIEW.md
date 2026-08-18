# ADVERSARIAL_REVIEW.md — an independent rival's findings

Commissioned after `CODE_REVIEW.md`, against the full diff, the design, the charts, the plan and
the tests. **It found six critical defects the overseer's own read missed**, and seven further
instances of the exact failure mode `RUN_POSTMORTEM.md` §1 already names. The suite is green and
`doc_check` is clean throughout — neither is evidence about any of this.

## CRITICAL — all break the running app in its default path

| # | Defect | Site |
|---|---|---|
| C1 | **Alt-tab freezes the live screen permanently.** `NOTIFICATION_APPLICATION_FOCUS_IN` calls `mark_for_rerender()` on *every* picture, forcing `UPDATE_ONCE` — including the focused one, which must stay `UPDATE_ALWAYS`. Nothing restores it. E7/Q208=b says every **frozen** picture, not every picture. **N6's fixture sets all pictures to `UPDATE_DISABLED` first, so the test cannot see it.** | `wall.gd:492`, `wall_picture.gd:262` |
| C2 | **Reduced motion never arrives.** `sample_at()`'s reduced branch returns a *constant* midpoint position for every `elapsed`, including the last, and nothing sets the camera afterward. The camera parks between the two pictures forever. **No cross-fade exists at all.** T12 asserts only constant zoom — which is what the bug produces. | `wall_transition.gd:171`, `main.gd:224` |
| C3 | **Info mode persists across a quit.** `wall_info_mode` is a `PlayerSettings` field, so toggling it writes `user://settings.tres`. Next launch every transition silently takes the info branch while the card is hidden and the button reads un-pressed. Violates J1 verbatim ("NOT persisted across sessions") and **anti-scope item 9**. | `main.gd:285` |
| C4 | **`wall_jump_N` breaks the one-`ALWAYS` invariant.** It calls `focus()` without unfocusing the current picture, moving the camera, or touching the stack — two live screens. Its test fixture has *no picture focused*. Also indexes child order, which diverges from placement order after an unlock. | `wall.gd:204` |
| C5 | **Concurrent transitions.** `Main._focus_picture()` news a `WallTransition` per call, so `request()`'s `is_active` guard never sees the other one. Two tweens fight over one camera; both land; two `focus()` calls. Q56=b unenforced. `input_unlocked` — the signal S16 exists for — **has no consumer**. | `main.gd:224` |
| C6 | **The layout tool edits a resource the game never loads.** `layout_default.tres` has zero production readers; `Main` calls the hardcoded `Wall.initial_layout()`. Every hour in the tool is discarded, and `initial_layout()` is itself a §1.8 violation — the whole authored pattern typed into a `.gd`. | `wall_editor.gd:67`, `wall.gd:46` |

## MAJOR

- **S17 is entirely unwired** — no `size_changed` handler anywhere; `WallTransition.retarget()` has no
  caller. Resize or fullscreen and the focused picture stops overfilling, exposing its frame at rest.
- **Keyboard Back does Wall** — `ui_cancel` jumps to wall view without consulting the `FocusStack`.
  Violates Q65=a and I5/Q100=a.
- **Four InputMap actions have no readers** — `wall_overview`, `wall_back`, `wall_forward`,
  `wall_info`. Tab, L1/LB, R1/RB and `I` all do nothing; **controller has no Back, Forward or Wall.**
- **`clamp_pan()` has no caller** — free pan does not exist. Two tests guard unreachable maths (G10).
- **`update_filter(true)` is never called** — the filter never swaps, so the focused picture samples
  `NEAREST` through every zoom. That is the shimmer QR7=c/H4/H5 exist to suppress. S13 is dead.
- **`touch_target_px()` has no caller**, and its own comment asserts a live call site that does not
  exist. Overlay buttons are hardcoded 80×32; the mandatory GAP-004 clamp never runs.
- **The map's info card can never be dismissed** and ignores info mode. `Main` resets a *different*
  InfoCard instance. The old auto-hide was removed and nothing replaced it.
- **Info mode on the wall still shows nothing** — no `WallPicture` implements `get_info()`, so
  CODE_REVIEW A1 was only half-closed. J9 (retarget on mid-transition toggle) unimplemented.
- **Five knobs nothing reads**: `WallLayout.view_margin` (contradicting GAP-008=a, which put the
  crop bias there deliberately), `wall_frame_thickness_fraction`, `wall_live_screen_cap`,
  `wall_design_height`, `wall_selection_repeat_delay` — the last meaning **held-stick repeat does
  not exist**.

## MINOR
Entering wall view leaves nothing visibly selected · `selection_visible` has no renderer · easing
curves are hardcoded literals though S34 must expose them · the Info button is text, not the
magnifying glass J1 names · a duplicated comment block at `wall.gd:180` · `wall_editor.gd:37` typo
· PLAN §1.10 still names the non-existent `wall_transition_delay_scale`.

## What the rival confirmed sound

`WallPacker` line by line, including CODE_REVIEW B1's fix (`intersects()` now checked independently
of `gap_px`) and `_rebalanced_angles`'s purity · `FocusStack` against §1.4 exactly · `ProfileManager`
against §1.5 · the `Pacing` sweep · **all twelve GAP answers implemented as the answers state**,
including GAP-013 per the corrected text rather than the mislabelled summary · S2's pre-bound outcome
· `info_zoom_state`'s monotonicity proof, re-derived independently · `WallInput.route`'s post-transform
shift · `PinchTracker` now genuinely wired · anti-scope items 1–8 and 10 clean.

## The lesson, sharpened

`CODE_REVIEW.md` §E said contract items with no test row are the blind spot. That was right and
**still understated it**: the overseer then read the code and *still* missed six criticals, because
it read for contract conformance and not for "what happens when a player alt-tabs, resizes, presses
Escape, or clicks twice". **Reading code is not the same as tracing user journeys**, and neither a
green suite nor a conforming implementation catches an unwired feature.
