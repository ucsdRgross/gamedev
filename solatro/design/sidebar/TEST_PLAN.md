# TEST_PLAN.md — every test that must exist

**The designer wrote this, not the implementer, because the designer knows what the feature is
for.** You **may ADD** lower-level tests for details this plan could not foresee — that is expected
and welcome. You may **not** decide a planned test is unnecessary. Removing one is a gap, not a
judgement call.

Derived from: `DESIGN.md` version 10. Suite names and paths are fixed in `NAMES.md` §8.

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/sidebar/DESIGN.md`, version 10. Every step in `PLAN.md` cites the
design node IDs it implements.

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
5. ⚠⚠ **THE CODE BEING BROKEN IS NOT A GAP — FIX IT.** If the design says what should happen and
   the code does not do it, that is a BUG, and the only open question is *how* to fix it, which is
   yours. Filing it spends an owner round to be told "yes, fix the bug". Measured: one run filed
   ~50 gaps and a large share were this. **Before filing anything, ask in order:** does the design
   already answer it (→ fix the code); would any defensible choice be invisible in the product
   (→ assume it, log one line); would the owner recognise this as a decision they want (→ only
   now, a gap). A gap asks for a RULING, never for permission — if you are filing to be told it is
   fine to proceed, write the assumption instead.

File gaps at `solatro/design/sidebar/gaps/GAP-NNN.md` using the template in `DESIGN.md`
§gap-protocol. Write the options in the questionnaire grammar; they become the next round's
questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## How to read this

- **Gate** = a self-checking acceptance test that cannot be talked past. Its step does not land
  until it is green.
- **Eye** = a by-eye verification a human signs off. **No green test is evidence about pixels**
  (project rule 4); use `/fx-verify`.
- **Fixtures are specified.** Where they are, use them exactly — invented data tests whatever it
  happened to make true.

⚠ **Every one of these must be proved RED first.** Write the assertion, watch it fail for the right
reason, then implement. A test written after the code passes it is a test that asserts the code.

---

## 1. `TestSidebar` — charts B and C

| # | Test | Fixture | Asserts | Kind | Node | Step |
|---|---|---|---|---|---|---|
| 1.1 | A bare `HudContainer` is constructible with no `Main` in the tree | `HudContainer.new()`, `add_child`, no wall | exactly one child visible after `show_hud()`; exactly one after `show_description()` | Gate | C1, C2 | S1 |
| 1.2 | A highlight opens the description | one `InfoEntry` with title "A", body "B" | container shows the description, and its title reads "A" | Gate | B1, B2 | S5 |
| 1.3 | Losing the highlight KEEPS the last entry | show entry A, then publish nothing | still showing A; the container has not swapped | Gate | B4, `Q32`=a | S5 |
| 1.4 | Click-lock, then hovering another card follows the hover | entries A then B, lock on A | shows B while hovering B | Gate | B7, `Q60`=c | S6 |
| 1.5 | …and returns to the locked card when the pointer leaves everything | as 1.4, then publish nothing | shows A again | Gate | B7 | S6 |
| 1.6 | Locking a second replaces the first | lock A, lock B, leave | shows B | Gate | B8, `Q61`=a | S6 |
| 1.7 | Each of the four dismissals reverts to the HUD | lock A, then: exit X / cancel / bare-board click / card leaves its cell while following | HUD visible in all four | Gate | B9, B10, `Q64`=a | S6 |
| 1.8 | A card leaving its cell while NOT following does NOT dismiss | armed card, `following == false`, cursor moves away | still showing the description | Gate | B11, `Q268`=a | S6 |
| 1.9 | `processing` true reverts to the HUD, lock and all | lock A, set `processing = true` | HUD visible, `is_locked()` false | Gate | B17, B18, C8 | S7 |
| 1.10 | A hover DURING processing changes nothing | as 1.9, then publish entry B | HUD still visible | Gate | B19, `Q258`=a | S7 |
| 1.11 | After processing ends the HUD holds until ANY focus event | set `processing = false`, no focus | HUD still visible; then one focus event onto the SAME card → description | Gate | B20, C9, `Q257`=b | S7 |
| 1.12 | The map's container does NOT swap on processing | map container, `processing = true` | unchanged | Gate | C10, `Q260b`=b | S7 |
| 1.13 | A board rebuild keeps the same `CardData`'s description | show A's card, force `queue_rebuild()` | still showing A's description | Gate | B13, `Q65`=a | S6 |
| 1.14 | Leaving and returning restores the screen's own description | show A on the game, go to the map, come back | shows A immediately | Gate | B15, B16, `Q19`=c, `Q20`=b | S5 |

## 2. `TestGestureMetrics` — chart M

| # | Test | Fixture | Asserts | Kind | Node | Step |
|---|---|---|---|---|---|---|
| 2.1 | Drag threshold is card-relative | card 216×286, `card_drag_threshold = 0.25` | `drag_threshold_px == 54.0` | Gate | M3, M4 | S13 |
| 2.2 | …and scales with board zoom | the same card at zoom 2.0 → 432 wide | `== 108.0` | Gate | M3 | S13 |
| 2.3 | Touch target is window-relative, uncapped | window 1920×1080, `touch_target_fraction = 0.06` | `== 64.8`, and no clamp applied | Gate | M7, M8, `Q301`=a | S13 |
| 2.4 | …and uses the SMALLER dimension | window 3840×1080 | still `64.8` | Gate | M7 | S13 |
| 2.5 | **No DPI anywhere** | — | `grep` over `solatro/**/*.gd` outside `archive/` and `addons/` for `mm_to_px`, `screen_get_dpi` returns nothing | Gate | M1, L14 | S13 |
| 2.6 | A gesture with no card uses the default card at the current zoom | bare-board swipe at zoom 1.0 | threshold equals 2.1's value | Gate | M5, `Q296`=a | S13 |

## 3. Geometry — extends an existing engine suite

| # | Test | Fixture | Asserts | Kind | Node | Step |
|---|---|---|---|---|---|---|
| 3.1 | The inset is 394 px at the picture's own aspect | windows 1280×720, 1920×1080, 2560×1440 | `board_inset_left == 394.0 ± 0.5` in all three — the window cancels | Gate | D8, D10 | S3 |
| 3.2 | Ultrawide clamps and narrows | 3840×1080, `container_size_max_px = 640` | `board_inset_left == 262.7 ± 0.5` | Gate | D7, D8 | S3 |
| 3.3 | The container moves to the top when the leftover would be taller than wide | a window where `(w - container) / h < 1` | `container_is_top` true, and `board_inset_top` is set instead | Gate | D2, D6, `Q175`=a | S3 |
| 3.4 | Deleting `%MultScore` and `%Preview` re-centres the board | before/after `_hud_authored_width()` | the board's centre moved, and the suite is green | Gate | C4, L9 | S2 |

## 4. `TestEntranceStocks` — chart H

| # | Test | Fixture | Asserts | Kind | Node | Step |
|---|---|---|---|---|---|---|
| 4.1 | An even deal | 23 cards, 5 slots | sizes `[5, 5, 5, 4, 4]` — earlier slots take the extras | Gate | H3, `Q201`=a | S19 |
| 4.2 | The deal is deterministic | the same shuffled order dealt twice | identical stocks, card for card | Gate | H2, H4, `Q202`=a | S19 |
| 4.3 | **Resume-replay still reproduces** | a saved pre-placement board, replay the pending placement | identical board, identical scoring, identical refill | Gate | H4, `Q233` | S19 |
| 4.4 | Removing a slot moves BOTTOMS only | 4 slots of 5, remove slot 1 | every remaining slot's TOP card is unchanged; sizes `[7, 7, 6]` | Gate | H5, H7, `Q204`=a, `Q207`=a | S20 |
| 4.5 | Adding a slot pulls bottoms round-robin | 3 slots of 6, add one | sizes `[5, 5, 4, 4]`; every TOP unchanged | Gate | H8, H7, `Q205`=a | S20 |
| 4.6 | An exhausted slot stays empty | drain one slot | no rebalance fires; the slot stays at 0 | Gate | H11, `Q210`=c | S20 |
| 4.7 | "Deck empty" means EVERY slot empty | one slot empty, others not | End is not revealed; nothing disarms | Gate | `Q211`=a | S19 |
| 4.8 | Stocks are walked by board iteration | a card in a stock | `on_append` reaches it, and the stage verifier passes | Gate | H13, `Q225`=a | S19 |

## 5. `TestDragPlace` — chart E

| # | Test | Fixture | Asserts | Kind | Node | Step |
|---|---|---|---|---|---|---|
| 5.1 | A sub-threshold release is a CLICK | press and release 10 px apart, threshold 54 | the card is grabbed and stays held; nothing placed | Gate | E12, E13, `Q283`=a | S16 |
| 5.2 | An over-threshold release on a LEGAL cell places | press on an Entrance card, release on an empty legal cell | `place_card_in_grid` ran; one undo step; the grid committed | Gate | E14, E16, E18 | S16 |
| 5.3 | …on an illegal cell returns the card | release on an illegal cell | back in its slot, still armed, still lifted, `following == false` | Gate | E17, `Q280`=a, `Q281`=a | S16 |
| 5.4 | …over the container returns it too | release over the container's rect | as 5.3 | Gate | E17, `Q288`=a | S16 |
| 5.5 | A touch TAP on a card needs no threshold | press and release on the card's own slot | the card is selected and lifted, not placed, not returned-with-cost | Gate | E24, `Q285`=b | S16 |
| 5.6 | A drag from a BOARD card cancels the arm implicitly | armed Entrance card, drag a board card | the Entrance disarmed; the board card is the one held | Gate | E10, E11, `Q286`=b | S16 |
| 5.7 | A CLICK on a board card still needs the cancel first | armed, click a board card | it attempts to place onto it, per your `Q122` note | Gate | E8, `Q122` note | S16 |

## 6. Arming and the lift/follow split — chart G

| # | Test | Fixture | Asserts | Kind | Node | Step |
|---|---|---|---|---|---|---|
| 6.1 | Arming moves NO focus | a fresh show | `focused_control` is null and `gui_get_focus_owner()` is unchanged after the arm | Gate | G3, `Q250`=a | S15 |
| 6.2 | Arming does NOT open a description | a fresh show | the container shows the HUD | Gate | B3, `Q240`=a | S15 |
| 6.3 | Arming calls the SAME functions as a pickup | spy on `try_grab`/`grab_cards` | both called, once each, with no extra flag | Gate | G2, `Q252`=b | S15 |
| 6.4 | The card LIFTS immediately, and does not follow | after the arm, before any input | `held != 0`, `following == false`, position is the slot centre raised by the lift | Gate | G4, G5, `Q254`=d | S14 |
| 6.5 | Any mouse motion starts following | one motion event | `following == true` | Gate | G7, `Q262`=a | S14 |
| 6.6 | A key focus onto any card also starts it | one focus event, no mouse | `following == true` | Gate | G7 | S14 |
| 6.7 | Following is a one-way latch | start following, then send a key event | still `true` | Gate | G8, `Q263`=a | S14 |
| 6.8 | The lift height is the same in both states | before and after following starts | equal y-offset | Gate | G8, `Q265`=a | S14 |
| 6.9 | A CLICKED card follows immediately | click an Entrance card | `following == true` on the same frame | Gate | G11, `Q267`=a | S14 |
| 6.10 | The arm survives undo by re-derivation | place, undo | armed slot is the leftmost present again | Gate | G16, `Q117`=a | S15 |

## 7. Automatic end — chart J

| # | Test | Fixture | Asserts | Kind | Node | Step |
|---|---|---|---|---|---|---|
| 7.1 | Reaching the goal ends the show with no button press | headless run, goal 10, a placement scoring 12 | `show_ended` true; `show_resolved` emitted once | Gate | J1, J2, `Q101`=a | S22 |
| 7.2 | The check fires only after the WHOLE placement resolves | a placement completing 3 lines | `end_show` ran once, after the last line scored | Gate | J2 | S22 |
| 7.3 | Undo rewinds an automatic end | as 7.1, then undo | back on a live board, `show_ended` false | Gate | J11, `Q109`=a | S22 |
| 7.4 | A full board still does NOT end the show | every cell filled, goal not met | `show_ended` false | Gate | J10, `Q108`=a | S22 |
| 7.5 | End is REVEALED when no action remains | deck empty, no empty cells | the End button is visible/highlighted | Gate | J9, `Q107`=c | S22 |

## 8. Removal proofs — chart L

| # | Test | Asserts | Kind | Node | Step |
|---|---|---|---|---|---|
| 8.1 | Info mode is gone | `grep -r "wall_info" solatro --include=*.gd` outside `archive/` returns nothing | Gate | L1–L4 | S9 |
| 8.2 | The in-board popup is gone | no `_focus_info`, no `wall_screen_popups` | Gate | L7 | S10 |
| 8.3 | Every millimetre knob is gone | none of the six names resolve in `player_settings.gd` | Gate | L14 | S13 |
| 8.4 | The suite COUNT did not drop | suite count ≥ 45 | Gate | L6 | S11 |
| 8.5 | Every `wall_*` action still has a reader AND a binding | `TestWallInput`'s existing assertion, still green | Gate | L1 | S9 |

## 9. By-eye verification — `/fx-verify`

⚠ **None of these can be a green test.** Render, LOOK at the image, describe what it actually
shows, or say UNVERIFIED.

| # | What to look at | Node | Step |
|---|---|---|---|
| 9.1 | The container on the game screen: HUD showing, board centred in what is left | C2, D10 | S3 |
| 9.2 | The container showing a description: name, card visual, body, exit X | C5, `Q33`=c | S5 |
| 9.3 | The container at the TOP on a narrow window, board roughly square | D6, `Q175`=a | S3 |
| 9.4 | An armed Entrance card: lifted, glowing, focus elsewhere | G4, G9 | S15 |
| 9.5 | The Entrance's face-down stocks at the capped depth | I8, `Q217`=b | S21 |
| 9.6 | The refill flip, staggered left to right — **a duration, so watch it run** | I4, I5 | S21 |
| 9.7 | A card following the cursor at the same lift it had at rest | G8, `Q265`=a | S14 |
| 9.8 | The map: name popup above a node, everything else in the sidebar | K2, K3 | S23 |

## 10. Deliberately NOT tested, and why

| Area | Why not |
|---|---|
| The exact pixel spacing inside the HUD | Deliberately the implementer's, per `PLAN.md` §2. Judged by eye at 9.1 |
| The container's colours | Flat panel now, art later (`Q78`=c). Nothing to regress |
| Translated strings | Translation is out of scope (`Q164`=a); only the CSV rows exist |
| The dummy tap effect's behaviour | It exists to prove the signal fires (`Q222`=b), not to be a mechanic |
| Controller stick scrolling, on real hardware | No automated path exists for a real stick; `todo.md` already carries this |
| Save migration | There is none — old in-flight saves are discarded (`Q224`=b) |

## 11. Design nodes with no test, triaged

Every chart node is claimed by at least one test above **except** these, which are context or
deletions already proved by §8:

- `A1`–`A11` — the chart of what the code does TODAY. Nothing to prove; it is the baseline.
- `F1` — an engine fact about Godot's event order, not our behaviour. `TestDragPlace` 5.1 exercises
  it indirectly.
- `M12` — a record that `Q123` is reversed. Proved by 2.5 and 8.3.
