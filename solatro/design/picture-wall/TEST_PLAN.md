# TEST_PLAN.md — every test that must exist, planned in advance

**The designer wrote this, not the implementer.** An implementer deriving its own test list
re-derives the design badly, and the cases it misses are exactly the ones it did not understand — a
missing test looks identical to a passing one.

**The contract:**

- **You may ADD tests.** Low-level detail the plan could not foresee is yours, and welcome.
- **You may NOT decide a planned test is unnecessary.** Dropping one is a **gap**, not a judgement
  call. If a planned test turns out to be impossible or meaningless, file it and keep going.
- **Fixtures are specified.** Where this document names data, use that data. Invented data tests
  whatever the implementer happened to make true.

Conventions: `Tests/Support/test_base.gd` — `behavior_section()` / `implementation_section()`,
`check()`, `finish()`, `await_siblings_except()` and the DEADLOCK RULE. Suites register in
`Tests/all_tests.tscn`. Names are fixed in `NAMES.md`. **The suite runs WINDOWED.**

---

## §1. `TestWallPacker` — "WALL PACKER" (S4)

Pure logic, no scene, no engine singletons.

| # | Test | Fixture | Proves |
|---|---|---|---|
| P1 | packing is deterministic | the same layout + unlocked list + aspect, packed twice; compare every rect field | G-chart, `Q18`=a |
| P2 | ring capacity is computed, not authored | 8 pictures, `size_multiplier` 1.0, `design_size` 1152×648, `gap_px` 24, ring 0 circumference fitting exactly 6 → assert ring 0 holds 6, ring 1 holds 2 | G2, `Q11`=b |
| P3 | an oversized picture overflows early | as P2 but picture #4 has `size_multiplier` 2.5 → assert ring 0 holds fewer than 6 | G2, `Q11`=b |
| P4 | a partial ring keeps its authored angles | 6 slots authored, only slots 0, 2 and 5 unlocked → assert their angles equal the full-ring angles for 0, 2, 5; assert they are NOT evenly redistributed | G4, `Q13`=b |
| P5 | locked pictures produce no rect at all | as P4 → assert `pack()` returns exactly 3 rects | G6, `Q158`=a |
| P6 | the gap is measured between frame OUTER edges | two adjacent pictures with `frame_px` 8 and 48 → assert the distance between outer edges equals `gap_px` for both, i.e. centre distance differs | G5, `Q14`=a, `Q36` |
| P7 | ellipse aspect follows the window, clamped | aspects 1.0, 1.78, 5.0 with clamps 1.2/2.6 → assert 1.2, 1.78, 2.6 | G1, `Q10`=c |
| P8 | picture aspect follows the window | aspect 2.33 → assert a `keep_aspect = false` picture's rect is 2.33 | G7, `Q22`=b |
| P9 | `keep_aspect` survives a wide window | the `map` entry with `keep_aspect = true` at aspect 2.33 → assert its rect stays square | H2, `Q32`=b |
| P10 | no two rects ever overlap | the full 6-picture default layout at aspects 1.33, 1.78, 2.33, 3.55 | G-chart, `Q20`=a |
| P11 | the one-picture wall | one unlocked id → assert exactly one rect, centred | `Q19`=b |
| P12 | the floor and the range | 1280×720 and 32:9 → assert no error and no overlap | G13, `Q23`, `Q24`=b |

**Not tested here and deliberately so:** how the packer *looks*. Angles and radii are asserted
numerically; whether the result reads as a wall is by-eye (§6).

## §2. `TestWallFocus` — "WALL FOCUS" (S5)

| # | Test | Fixture | Proves |
|---|---|---|---|
| F1 | back retraces visit order | visit a, b, c → back → assert b | F1, `Q63`=a |
| F2 | a revisit MOVES rather than appends | visit a, b, c, then b → assert stack is a, c, b and depth is 3 | F2, `Q64` |
| F3 | depth never exceeds the picture count | visit 6 pictures 20 times in a shuffled order → assert depth ≤ 6 always | F2, `Q64` |
| F4 | forward returns the picture just left | visit a, b → back → forward → assert b | F3, `Q64` |
| F5 | a new visit clears forward | visit a, b → back → visit c → assert `can_forward()` is false | F3 |
| F6 | back on an empty stack returns `&""` | fresh stack → assert `&""`, and the caller's contract is wall view | F5, `Q65`=a |
| F7 | wall view is never an entry | visit a, enter wall view, visit b → back → assert a, not wall view | F4, `Q66`=b |

## §3. `TestWallProfile` — "WALL PROFILE" (S7)

| # | Test | Fixture | Proves |
|---|---|---|---|
| R1 | unlock is idempotent and reports newness | unlock `&"deck"` twice → assert true then false | K1, `Q153`=a |
| R2 | a round-trip through `ResourceSaver` preserves the set | unlock 3 ids, save, load into a fresh `PlayerProfile` → compare sets | §1.5, `Q152`=a |
| R3 | the format is slot-keyed | unlock into slot 0 → assert slot 1 reads empty | `Q151`=b |
| R4 | the debug flag bypasses the file | `wall_unlock_all = true` with an empty profile → assert every id unlocked and **the file is not written** | `Q159`=a |
| R5 | a missing profile file is not an error | delete `user://profile.tres`, construct → assert defaults, no `push_error` | §1.5 |
| R6 | a corrupt profile file degrades to defaults | write garbage to the path → assert defaults and exactly one `push_error` | START_HERE "no silent failures" |

⚠ R6 is not in the design. It is here because this repo's coding rules forbid silent failure paths,
and a persistence layer without a corruption test is one.

## §4. `TestWallPause` — "WALL PAUSE" (S12)

| # | Test | Fixture | Proves |
|---|---|---|---|
| U1 | the tree is paused and stays paused | construct the wall → assert `get_tree().paused` | D1, `QR6`=a |
| U2 | the shell keeps running | assert `Wall`, `%Camera2D`, `WallOverlay` are `PROCESS_MODE_ALWAYS` | D2 |
| U3 | exactly one screen is live | focus each of 3 pictures in turn → assert exactly one root is `ALWAYS` each time | D4, `Q74`=a |
| U4 | wall view leaves zero live | enter wall view → assert no screen root is `ALWAYS` | D8, `Q74`=a |
| U5 | **`Pacing.wait` does not tick while paused** | `paused = true`, await `Pacing.wait(0.1)` with a 0.5 s escape → assert it did NOT fire | D6, `Q75`=b |
| U6 | a bare `create_timer` DOES tick while paused | the same, with `get_tree().create_timer(0.1)` → assert it fired | D6 — **this is the test that proves the trap is real**, and it must stay green or `Pacing` is pointless |
| U7 | info mode does not pause the focused screen | enable info mode at rest → assert the focused root is still `ALWAYS` | D9, `Q138`=a |

⚠ **U6 asserts engine behaviour rather than ours.** It is deliberate: if a future Godot changes
`process_always`'s default, U6 goes red and tells us `Pacing` can be retired — which no test of our
own code could ever say.

## §5. `TestWallTransition` — "WALL TRANSITION" (S14–S18)

| # | Test | Fixture | Proves |
|---|---|---|---|
| T1 | total duration derives from `base_delay` | `base_delay` 1.0 then 2.0 → assert the second transition is twice as long | C15, `Q46`=b |
| T2 | **an act fast-forward does NOT compress it** | start a transition, set `Game.act_cancelled = true` → assert the duration is unchanged | C15, `Q46`=b — the specific trap `Q46` (c) would have caused |
| T3 | phases overlap | sample camera zoom and position per frame → assert position starts changing before zoom stops | C7, `Q47`=b |
| T4 | zoom-out shows both frames | pictures on opposite rings → assert the peak-zoom visible rect contains both frames plus the margin | C8, `Q48`=b |
| T5 | travel duration is distance-independent | adjacent vs opposite pictures → assert equal durations | C10, `Q50`=a |
| T6 | the source pauses when its frame edge enters view | per-frame sample → assert the pause frame is the first frame the outer edge is inside the visible rect | C9, `Q72`=a |
| T7 | the destination unpauses on first visibility | per-frame sample → assert it unpauses during travel, not at the end | C11, `Q73`=c |
| T8 | input unlocks before the tween finishes | assert the unlock frame < the finish frame, and ≥ the frame both picture and frame are fully in view | C13, `Q58` |
| T9 | a new destination is ignored mid-flight | request b then c → assert it lands on b | C5, `Q56`=b |
| T10 | requesting the current picture does nothing | → assert no tween is created | C3, `Q55`=a |
| T11 | a mid-flight resize retargets | resize at 50 % progress → assert it lands on the new rect with no discontinuity > 1 frame of travel | C16, `Q26`=a |
| T12 | reduced motion removes all zoom | flag on → assert camera zoom is constant for the whole transition | K8, `Q172`=a |
| T13 | **the soak**: 20 random transitions | after each, assert exactly one `ALWAYS` screen and a valid focus stack | phase-3 gate |

## §6. `TestWallInput` — "WALL INPUT" (S19–S23)

| # | Test | Fixture | Proves |
|---|---|---|---|
| I1 | a click routes to the right screen coordinate | a `Button` at a known spot inside a picture; click its wall-space centre at zoom 0.5, 1.0, 2.0 → assert the button reports pressed **at all three** | I1, GAP-001 — the risk that caused the gap |
| I2 | non-focused pictures never receive input | click over a background picture → assert its viewport got zero events | I2, `Q95`=a |
| I3 | the focused screen gets first refusal on `ui_cancel` | a screen that consumes Escape → assert the wall does NOT go back | I5, `Q100`=a |
| I4 | a screen that ignores Escape lets Back through | → assert the wall goes back | I5, `Q100`=a |
| I5 | arrow selection is spatial | 6 pictures at known angles, selection at the top → press Down → assert the geometrically nearest below | I4, `Q98`=a |
| I6 | selection wraps | step past the last → assert the first | I4, `Q106`=a |
| I7 | `wall_jump_3` enters the third picture in ring order | → assert focus | I4, `Q104`=a |
| I8 | the wheel is never consumed by the wall | wheel over a focused map picture → assert the map zoomed and the wall did not | I3, `Q89`=a |
| I9 | the cursor appears only after a key press | fresh wall, mouse only → assert no selection indicator; press an arrow → assert one | I10, `Q105`=b |
| I10 | most-recent-device wins | mouse move then controller input → assert only the controller indicator | I10, `Q124`=a |
| I11 | **pinch is derived from two touches** | two synthetic `InputEventScreenTouch` ids, distance +40 px over 3 events with threshold 24 → assert one pinch-out | I8b, GAP-003 |
| I12 | **`InputEventMagnifyGesture` is never listened for** | push one → assert nothing happens | I8b — it does not fire on Windows and must not be relied on |
| I13 | touch target size is clamped | DPI 1 (absurd low), DPI 10000 (absurd high) → assert the result is the configured min and max | I8c, GAP-004 |
| I14 | the wall is deaf while a screen is focused | arrows with focus inside a screen → assert no wall selection change | I9, `Q103`=a, `Q115`=a |

## §6b. `TestWallFocus`, overlay group — (S35, S38)

Added with `S35`–`S39`, which the first pass of this plan missed entirely. They live in
`TestWallFocus` rather than a new suite because they are all stack semantics wearing UI.

| # | Test | Fixture | Proves |
|---|---|---|---|
| F8 | Back is *visibly* disabled at the bottom | empty stack → assert the control reports disabled, not merely inert | F7, `Q65` — the repo's own review lesson: a control that silently does nothing is the defect |
| F9 | Forward is visibly disabled with nothing ahead | → assert disabled | F3 |
| F10 | Back closes a popup before leaving the picture | open a popup, press Back twice → assert popup closed, then picture left | F8, `Q164`=a |
| F11 | the Wall button leaves a popup open behind it | open a popup, press Wall, return → assert the popup is still open | F9, `Q165`=a |
| F12 | an unlock mid-session leaves the stack valid | visit 3 pictures, unlock a 4th, re-pack → assert Back still returns the right ids | K4, `Q156`=a |
| F13 | wall state does not survive a quit | write focus, simulate relaunch → assert focus is the start-menu picture and no wall field was persisted | K6, `Q145`=b |

## §7. `TestWallRender` — "WALL RENDER" (S10, S11)

| # | Test | Fixture | Proves |
|---|---|---|---|
| N1 | every SubViewport is explicitly NEAREST | construct the wall → assert `canvas_item_default_texture_filter == NEAREST` on all of them | §1.7 — the trap documented four times in this repo |
| N2 | a non-focused picture stops rendering but keeps its texture | focus away → assert `UPDATE_DISABLED` **and** a non-null, non-zero-size texture | E3, `Q82`=a |
| N3 | an unvisited picture has rendered once | fresh wall → assert every texture is non-null before any focus | E4, `Q78`=b |
| N4 | wall-view size is written down, and clamped | shrink a picture's footprint to 10 px → assert `SubViewport.size` short axis is 64 | §1.8, GAP-002 |
| N5 | **no `SubViewportContainer` exists anywhere in the wall** | walk the tree → assert none | GAP-001=b — the design decision this suite defends |
| N6 | restore-from-minimise re-renders | emit the restore notification → assert every picture went `UPDATE_ONCE` | E7, `Q208`=b |
| N7 | the filter swaps on zoom, not on pan | pan only → assert filter unchanged; zoom → assert it changed | H6, `Q34` |

## §8. `TestWallInfo` — "WALL INFO" (S26–S29)

| # | Test | Fixture | Proves |
|---|---|---|---|
| J1 | the card shows nothing before the first hover | → assert hidden | J5, `Q131` |
| J2 | the card keeps the last entry across empty space | hover a, then hover nothing → assert a is still shown | J5, `Q131` — the "does not blink" requirement |
| J3 | leaving info mode resets to nothing | → assert hidden | J6, `Q131` |
| J4 | the card sizes to its content | a short and a long entry → assert different heights | J4, `Q130` |
| J5 | info zoom reveals the bottom frame only | → assert the bottom frame edge is inside the visible rect and the top edge is NOT | J2, `Q128` |
| J6 | a transition in info mode does not zoom | → assert constant zoom | J10, `Q137`=a |
| J7 | the map's hover still works after migration | hover a map node → assert an `InfoEntry` with the node's preview | J8, `Q134`=c — the regression S29 risks |

## §9. Existing suites that must stay green (regression watch)

These are not new. They are named because specific steps threaten them, and "the full suite is
green" is too coarse to plan against.

| Suite | Threatened by | Why |
|---|---|---|
| every suite | **S6** | `Pacing` rewrites every timer call site in the show's pacing |
| `TestGameHeadless`, `TestActScore`, `TestCombo` | **S31** | the board moves into a viewport and gains freeze/resume |
| `TestPixels`, `TestOutline` | **S10, S13** | they assert on rendered pixels; `Q196`=a says they build their own viewport and are unaffected — **this is the test of that claim** |
| `TestVisualLayers` | **S31** | `LightLayer` must stay the last sibling (`LAYERING.md:77-83`) |
| `TestLeakCanary` | **S30, S31** | every screen now stays alive for the session (`Q203`=a); the sentinel's idea of a leak changes |
| `TestMapTraversal` | **S29, S30** | the map's camera and hover panel both move |
| `TestUiViewers` | **S30** | the popups now live inside a SubViewport |

## §10. By-eye verification — no test gates these

Repo rule 6: no green test is evidence about pixels. Each needs a human sign-off with a description
of what the image actually shows.

1. **The filter swap (S13)** — does a picture shimmer during a transition, and is it crisp at rest?
2. **The frames (S24)** — does the nine-slice corner art hold at the largest and smallest picture?
3. **Shadows (S25)** — do all pictures read as lit from one direction?
4. **The transition (S14)** — does the arc read as travel rather than as a cut?
5. **The opening reveal (S30)** — does the save-select zoom-out land well?
6. **The info card (S27)** — does the self-sizing read as "each notecard is unique"?
7. **The wall at 32:9 and at 1280×720** — does the ellipse clamp save it?

## §11. Deliberately NOT tested, and why

- **Frame appearance, wall colour, shadow direction.** Art direction; §10 covers them by eye.
- **Audio (S33).** Cross-fade correctness is a listening judgement, and this repo has no audio test
  harness. Adding one is out of scope for this run.
- **The layout tool (S34).** Editor tools in this repo are not covered by the suite
  (`Tools/fx_editor.gd`, `Tools/spotlight_tool.gd` have none). Consistency beats novelty here.
- **Multi-slot profiles.** Only slot 0 exists (`Q213`=a); R3 pins the format so the untested path
  cannot silently change shape.
- **Screen internals at new aspects.** `Q211`=a puts screen redesign out of scope, so testing it
  would assert behaviour nobody has committed to.
