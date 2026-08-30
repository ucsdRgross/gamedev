# Poker Patience — test plan

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/poker-patience/DESIGN.md`, version 2, charts confirmed 2026-08-25.
Every row below cites the design node it proves and the plan step it gates.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent → do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise — two defensible choices differ in observable behaviour, or the choice is expensive to
   reverse, or it is an owner call → **park that thread, file a gap, keep working on unaffected
   threads, and tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.
4. ⚠ **Two documents disagreeing is NOT automatically (3).** If both are restating the same answer,
   go read that answer. Quote the note in the gap and say why it does not settle the question.

File gaps at `solatro/design/poker-patience/gaps/GAP-NNN.md`. Do not resolve a gap by picking an
answer. Do not proceed on the parked thread. Do not delete a gap.

This block, unchanged, goes into every document derived from this one.

---

## 0. The rules of this document

**The designer wrote this list, not the implementer.** An implementer deriving its own test list
re-derives the design badly and silently misses the cases it did not understand — and a missing test
looks identical to a passing one.

- **You MAY add lower-level tests** for details this plan could not foresee. That is welcome.
- **You may NOT decide a planned test is unnecessary.** Dropping one is a **gap**, not a judgement
  call.
- **Fixtures are specified.** Where this document fixes the data, use that data. Invented data tests
  whatever it happened to make true.
- **Red-then-green is mandatory for every new test**: neutralise the behaviour, watch it fail,
  restore it, watch it pass, report both. ⚠ Check the red run failed **the checks you expected** — a
  neutralisation that breaks the test rather than the behaviour aborts the function and the banner
  reads all-passed with those assertions silently missing.
- **Never use `Decks/deck.gd` in a test.** Use `TestDecks` — frozen replay contracts (`Q272`=a).
- **Compare failure SETS, not check totals.**
- The suite runs **WINDOWED**. A test that cannot run under the current renderer **FAILS with the
  reason; it never skips.**

**Legend:** **G** = self-checking gate, cannot be talked past. **E** = by-eye, a human signs it off;
no green test is evidence about pixels.

---

## 1. The fixtures

Fixed here so two sessions cannot invent two datasets.

| Fixture | Definition |
|---|---|
| `FIX-DECK-52` | A new `TestDecks` entry: standard 52, every suit at ranks 1–13, all plain, frozen. Never `Deck.deck4`. |
| `FIX-DECK-20` | 20 cards, ranks 1–5 × 4 suits, plain — the shape `deck14` has. |
| `FIX-DECK-53` | `FIX-DECK-52` plus one plain card. |
| `FIX-DECK-105` | `FIX-DECK-52` × 2 plus one plain card. |
| `FIX-GRID-1` | One 5×5 grid, empty. |
| `FIX-GRID-3` | Three 5×5 grids, empty. |
| `FIX-ROW-FLUSH` | Grid 0 row 0 filled with five cards of one suit, ranks 2,4,6,8,10 (a flush, not a straight). |
| `FIX-ROW-STRAIGHT` | Grid 0 row 0 filled 3,4,5,6,7 across mixed suits. |
| `FIX-CROSS` | Grid 0 row 2 and column 2 both one card short, sharing cell (2,2) empty — so one placement completes both. |
| `FIX-TRIPLE` | Grid 0 arranged so cell (2,2) completes row 2, column 2 **and** a diagonal at once. |
| `FIX-STACK-5` | Grid 0 cell (0,0) holding 4 cards; the 5th completes a vertical line. |
| `FIX-STACK-10` | Grid 0 cell (0,0) holding 9 cards; the 10th completes at height 10. |
| `FIX-LEVEL-3` | Grid 0 with every cell of row 0 at height 3, so a horizontal line exists at levels 0, 1 and 2. |
| `FIX-FULL-15` | Grid 0 with all 25 cells at height 15. **375 cards.** Built card by card. |
| `FIX-MIXED-H` | Three grids; grid 0 row 1 at height 6, grid 1 row 1 at height 1, grid 2 row 1 empty. |
| `FIX-SCORE-EXAMPLE` | The owner's worked example: a grid where row banks 10, then col banks 5, then special banks 2. |

---

## 2. Phase 1 — the coordinate and the container

| id | Test | Fixture | Proves | Gates | Kind |
|---|---|---|---|---|---|
| TP-01 | A coordinate round-trips grid/x/y/h | — | C1 | S1 | G |
| TP-02 | `x` is continuous: 5 columns left of (grid 1, x 0) is (grid 0, x 4) | `FIX-GRID-3` | C1, Q3 | S1 | G |
| TP-03 | The Entrance is `y == -1` of its attached grid, and the attachment moves on commit | `FIX-GRID-3` | C2 | S1 | G |
| TP-04 | Off-board reads as the four-component MIN analogue, never as (0,0,0,0) | — | C1 | S1 | G |
| TP-05 | A 3-grid board's `validate()` returns empty at mixed heights | `FIX-MIXED-H` | C1 | S2 | G |
| TP-06 | A card in two cells is reported by `validate()` with BOTH locations | `FIX-GRID-1` | C1 | S2 | G |
| TP-07 | 25 cell zone cards exist per grid and appear in `all_card_datas()` | `FIX-GRID-3` | G7 | S2 | G |
| TP-08 | `position_of()` is O(1) and rebuilds only when `revision` moved | `FIX-MIXED-H` | C1 | S3 | G |
| TP-09 | The reverse index agrees with the forward index after every mutation kind | `FIX-MIXED-H` | C1 | S3 | G |
| TP-10 | `place_card` into an empty cell bumps `revision` exactly once | `FIX-GRID-1` | A9 | S4 | G |
| TP-11 | Stacking uses `Anchor.ON_TOP` and lands at `h+1` | `FIX-STACK-5` | E7 | S4 | G |
| TP-12 | Removing from mid-stack compacts the cards above down | `FIX-STACK-5` | Q84 | S4 | G |
| TP-13 | A compaction bumps `revision` **once** for the whole compaction | `FIX-STACK-10` | Q91 | S4 | G |
| TP-14 | A compaction move carries the compaction flag; a placement does not | `FIX-STACK-5` | B2, Q83 | S4 | G |
| TP-15 | Iterator order: `draw_deck` first, then the board, row-major within a grid | `FIX-MIXED-H` | §1.10 | S5 | G |
| TP-16 | Within a cell the walk is bottom to top | `FIX-STACK-5` | Q225 | S5 | G |
| TP-17 | **A sparse grid — cards only in row 3 — is walked completely** | `FIX-GRID-1` | Q226 | S5 | G |

⚠ **TP-17 is the one that catches the early-stop bug.** Today's walk stops at the first empty row; a
grid is sparse by nature. Neutralise by restoring the early stop and watch it fail.

---

## 3. Phase 2 — line detection and scoring

| id | Test | Fixture | Proves | Gates | Kind |
|---|---|---|---|---|---|
| TP-18 | A row completes and is detected | `FIX-ROW-FLUSH` | C4 | S6 | G |
| TP-19 | A column completes and is detected | `FIX-GRID-1` | C5 | S6 | G |
| TP-20 | Both main diagonals are detected; **no broken or wrapped diagonal is** | `FIX-TRIPLE` | C6, Q97, Q98 | S6 | G |
| TP-21 | A horizontal line at height 2 is detected when every cell has a card at 2 | `FIX-LEVEL-3` | C7, Q79 | S6 | G |
| TP-22 | A cell taller than `h` still counts toward the line at `h` | `FIX-LEVEL-3` | Q79 | S6 | G |
| TP-23 | **No line crosses a grid boundary** | `FIX-GRID-3` | C10, Q87 | S6 | G |
| TP-24 | 3-D diagonals in the full family are detected | `FIX-LEVEL-3` | C9, Q86 | S6 | G |
| TP-25 | A section carries its line key and kind; `score_line` reads neither `is_row` nor `zone` | — | §1.4 | S7 | G |
| TP-26 | **Grep gate: no caller passes the old `score_line` signature** | — | §1.4 | S7 | G |
| TP-27 | A section re-derives its cards from the live board after a hook | `FIX-ROW-FLUSH` | B11 | S7 | G |
| TP-28 | Every board mutation runs a pass — arrivals **and** removals | `FIX-GRID-1` | B1, Q46 | S8 | G |
| TP-29 | A drop-only mutation scores nothing | `FIX-STACK-10` | B3, Q82 | S8 | G |
| TP-30 | The board is locked for the whole pass | `FIX-CROSS` | B18 | S8 | G |
| TP-31 | The pass runs **after** the placement has committed | `FIX-GRID-1` | §1.5 | S8 | G |
| TP-32 | One placement completing a row **and** a column scores both | `FIX-CROSS` | A/B, Q49 | S9 | G |
| TP-33 | One placement completing row, column **and** diagonal scores all three | `FIX-TRIPLE` | U4 | S9 | G |
| TP-34 | Order is rows → columns → diagonals → height, deterministically | `FIX-TRIPLE` | Q50 | S9 | G |
| TP-35 | An effect that completes another line during the pass scores it too | `FIX-CROSS` | B16, B17, Q47 | S9 | G |
| TP-36 | **A remove-and-replace loop re-scores every cycle and is bounded ONLY by the runaway guard** | `FIX-ROW-FLUSH` | B19, Q51 | S9 | G |
| TP-37 | The hand goes through `PokerHands.score()` unchanged | `FIX-ROW-STRAIGHT` | B9, Q60 | S10 | G |
| TP-38 | The spotlight cascade runs unabbreviated even for a multi-line placement | `FIX-TRIPLE` | B10, Q56 | S10 | G |
| TP-39 | The hand is re-evaluated after every spotlight effect | `FIX-ROW-FLUSH` | B11 | S10 | G |
| TP-40 | A stack of 5 scores as a 5-card hand | `FIX-STACK-5` | C8, C12 | S11 | G |
| TP-41 | **Heights 6–9 score nothing** | `FIX-STACK-10` | C13, Q80 | S11 | G |
| TP-42 | A stack of 10 scores **all ten cards**, not two fives | `FIX-STACK-10` | C12, Q61 | S11 | G |
| TP-43 | Height 10 pays the bottom five again — it is not netted off | `FIX-STACK-10` | Q81 | S11 | G |
| TP-44 | Removing then re-adding to a complete line re-triggers scoring | `FIX-ROW-FLUSH` | Q51 | S11 | G |
| TP-45 | Cards dropping down to a multiple of 5 score nothing | `FIX-STACK-10` | Q82 | S11 | G |
| TP-46 | **`FIX-FULL-15` finds exactly the expected line SET** | `FIX-FULL-15` | U35, Q267, Q268 | S11 | G |

⚠ **TP-46 is the phase-2 gate and the largest test in the plan.** Build the board card by card to
15 in all 25 cells. The expected set is **generated by an independent enumerator written in the
test**, never by the code under test (`Q268`=b) — otherwise it asserts that the code agrees with
itself. Compare as a **set**, not a count.

⚠ **TP-36 must not be written as "it terminates".** Assert that it re-scores on each cycle **and**
that the runaway guard is what stops it, so a future change to the guard fails here loudly.

Also build TP-46 at **height 3 and height 5 ceilings first** (`Q267`=b): a failure at 15 is very hard
to localise.

---

## 4. Phase 3 — the economy

| id | Test | Fixture | Proves | Gates | Kind |
|---|---|---|---|---|---|
| TP-47 | Row, col and special buckets exist per grid and are independent | `FIX-GRID-3` | D2–D4 | S12 | G |
| TP-48 | Every diagonal and special meld banks into the **one** special bucket | `FIX-TRIPLE` | D4, Q110 | S12 | G |
| TP-49 | Buckets survive `pack_scores`/`unpack_scores` round-trip | `FIX-GRID-3` | §1.7 | S12 | G |
| TP-50 | `duplicate_state()` copies the `BigNumber` buckets by hand | `FIX-GRID-3` | Q240 | S12 | G |
| TP-51 | **The owner's worked example: 0+0+0 → 10 → 50 → 100** | `FIX-SCORE-EXAMPLE` | D6, Q322 | S13 | G |
| TP-52 | A grid with rows scored and no diagonal pays its rows, **not zero** | `FIX-ROW-FLUSH` | D6 | S13 | G |
| TP-53 | A grid with **no** bucket scored contributes 0, not 1 | `FIX-GRID-1` | D8 | S13 | G |
| TP-54 | **A bucket whose VALUE is 0 is excluded from the product** even when its line completed | `FIX-ROW-FLUSH` | Q322 | S13 | G |
| TP-55 | `board_total` is the sum of grid scores | `FIX-GRID-3` | D9 | S13 | G |
| TP-56 | The HUD total is live — it changes on the line that scores it | `FIX-CROSS` | D13 | S13 | G |
| TP-57 | A first-of-its-class meld adds `combo_unique_step` | `FIX-ROW-FLUSH` | D10 | S14 | G |
| TP-58 | A repeat adds `combo_repeat_step` | `FIX-ROW-FLUSH` | D10, Q323 | S14 | G |
| TP-59 | **Melds and effects contribute on the same terms** | `FIX-ROW-STRAIGHT` | D11, Q323 | S14 | G |
| TP-60 | **Grep gate:** `MAX_SUBMITS`, `submits_used`, `score_additive`, `duplicate_class_scale` and the patience family have **zero** readers | — | D15, §1.6 | S14 | G |
| TP-61 | Undo across a Submit-era save does not resurrect `submits_used` | — | §1.6 | S14 | G |

⚠ **TP-54 is the edge the owner ruled on explicitly.** Force a line to complete and score 0, then
assert the grid still pays its other buckets. Neutralise by switching the test to touched-ness and
watch it fail.

---

## 5. Phase 4 — rules cards

| id | Test | Fixture | Proves | Gates | Kind |
|---|---|---|---|---|---|
| TP-62 | `FIX-DECK-20` → 1 grid | `FIX-DECK-20` | G2, Q4 | S15 | G |
| TP-63 | `FIX-DECK-52` → 1 grid; `FIX-DECK-53` → 2 | both | G3, Q4 | S15 | G |
| TP-64 | `FIX-DECK-105` → 3 grids | `FIX-DECK-105` | G3 | S15 | G |
| TP-65 | The cap holds: a 300-card deck still yields 3 | — | G4, Q7 | S15 | G |
| TP-66 | The grid creator builds 5×5 on `on_spotlight` | `FIX-GRID-1` | G6 | S16 | G |
| TP-67 | `on_unspotlight` removes the grid and **discards its cards** | `FIX-ROW-FLUSH` | G13 | S16 | G |
| TP-68 | A removed grid's labels go; **accumulated score does not** | `FIX-ROW-FLUSH` | G14, G15, Q126 | S16 | G |
| TP-69 | The meta card adds **and subtracts** persistent creator cards on deck change | `FIX-DECK-53` | Q202 | S16 | G |
| TP-70 | Refill is **strictly left to right** | `FIX-DECK-52` | F12, Q34 | S17 | G |
| TP-71 | A short refill fills leftmost first, leaving the right slots empty | `FIX-DECK-20` | F12 | S17 | G |
| TP-72 | Refill fires when the Entrance is empty | `FIX-DECK-52` | F9 | S17 | G |
| TP-73 | Refill also fires when **no legal move remains** with cards still held | `FIX-GRID-1` | Q33 | S17 | G |
| TP-74 | Unused cards keep their slots across a refill | `FIX-DECK-52` | F11, Q33 | S17 | G |
| TP-75 | The first placement commits the batch to that grid | `FIX-GRID-3` | F3 | S18 | G |
| TP-76 | A placement into another grid while committed is **refused** | `FIX-GRID-3` | F4 | S18 | G |
| TP-77 | The commitment lifts when no legal placement remains in that grid | `FIX-GRID-3` | F7, F8, Q32 | S18 | G |
| TP-78 | Undo lifts a commitment; nothing else does | `FIX-GRID-3` | F6, Q30 | S18 | G |
| TP-79 | The archived cards are absent from `rules1` and constructible from the archive builder | — | §1.11 | S19 | G |

---

## 6. Phases 5–7 — geometry, view, wall

| id | Test | Fixture | Proves | Gates | Kind |
|---|---|---|---|---|---|
| TP-80 | `CARD_SEPARATION` derives from the measured bottom-edge pip offset | — | E4 | S20 | G |
| TP-80b | A dealt board builds one `%GridPanel` per grid, each with `grid_width × grid_height` cell controls | `FIX-GRID-3` | J2, J7 | S20b | G |
| TP-80c | A card placed on a grid has a control, a `CardVisual` and a position | `FIX-GRID-1` | J8, J9 | S20b | G |
| TP-80d | `slot_center_global(BoardCoord)` is pure math — no control-rect reads, and it answers for an EMPTY cell | `FIX-MIXED-H` | M1, M2 | S20b | G |
| TP-80e | A card on no board reports `BoardCoord.NOWHERE`, and no `Vector3i` board position survives | `FIX-DECK-52` | M3, M4 | S20b | G |
| TP-80f | A scored grid line spawns props again, and a prop's route stays inside ONE grid | `FIX-ROW-FLUSH` | M5, M6, M7 | S20b | G |
| TP-80g | Every grid's bottom edge sits on the same floor | `FIX-GRID-3` | J6 | S20b | G |
| TP-80h | `upper_zone`/`lower_zone` have no readers: the fields are gone and the Entrance is `entrance` | — | P1, P2 | S20b | G |
| TP-80i | `Game.submit`, `_perform_submit` and the Next button have no readers | — | P3 | S20c | G |
| TP-80j | `end_show()` is the only path that resolves a show | `FIX-GRID-1` | P4 | S20c | G |
| TP-81 | A stack grows upward: card `h+1` has a smaller `y` than card `h` | `FIX-STACK-5` | E7 | S21 | G |
| TP-82 | Every cell in a row shares a **bottom** edge | `FIX-MIXED-H` | E10 | S21 | G |
| TP-83 | A tall stack pushes the rows **above** it up | `FIX-MIXED-H` | E11, Q307 | S21 | G |
| TP-84 | `slot_center_global` stays pure math — no control-rect reads | `FIX-MIXED-H` | Q255 | S21 | G |
| TP-85 | The row-shift eases rather than snapping | `FIX-MIXED-H` | E12, Q75 | S22 | G |
| TP-86 | The Entrance at `y == -1` pushes the board up when it stacks | `FIX-GRID-1` | E13, Q313 | S22 | G |
| TP-87 | A row that has nothing above it still pushes when a stack grows | `FIX-STACK-5` | Q77 | S22 | G |
| TP-88 | A jumping card lifts the whole stack above it, rigidly, by the full rise | `FIX-STACK-5` | E14, Q310 | S23 | G |
| TP-89 | A springing stack **overlaps** the rows above; the board does not re-flow | `FIX-MIXED-H` | E15, Q312 | S23 | G |
| TP-90 | A hoop rides the card that **jumped**, not the stack top | `FIX-STACK-5` | E16, Q311 | S23 | G |
| TP-91 | Row labels left; column labels below; one special label right of grid centre | `FIX-TRIPLE` | Q107, Q108, Q110 | S24 | G |
| TP-92 | A height label sits **above** the topmost card of its stack | `FIX-STACK-5` | E17, Q309 | S24 | G |
| TP-93 | **No subtotal is displayed anywhere** — no grid score, no bucket breakdown | `FIX-GRID-3` | D22, Q326 | S24 | G |
| TP-94 | A label animates on change and survives a save/reload | `FIX-ROW-FLUSH` | Q121, Q125 | S24 | G |
| TP-95 | Rows align across grids when the setting is ON | `FIX-MIXED-H` | Q245 | S25 | G |
| TP-96 | **The same board scores identically with the setting on and off** | `FIX-MIXED-H` | Q251 | S25 | G |
| TP-97 | The show opens zoomed out | `FIX-GRID-3` | H4, Q145 | S26 | G |
| TP-98 | Clicking a grid zooms in on it | `FIX-GRID-3` | H6 | S26 | G |
| TP-99 | Back zooms out a level; Forward returns to the previous view | `FIX-GRID-3` | H7, Q148 | S27 | G |
| TP-100 | Panning uses the **new** actions; `wall_back`/`wall_forward` still reach the wall | `FIX-GRID-3` | H8, Q187 | S27 | G |
| TP-101 | Every pan lands a grid centred; no cut-off grid at rest | `FIX-GRID-3` | H9, Q150 | S27 | G |
| TP-102 | The board edge bounces | `FIX-GRID-3` | H10, Q151 | S27 | G |
| TP-103 | The clamp collapses to centre on an axis that already fits | `FIX-GRID-1` | H12, Q159 | S27 | G |
| TP-104 | **One scroll container only** — no second scroller on the board | `FIX-FULL-15` | H13, Q160 | S28 | G |
| TP-105 | The camera steps between the 3 grid positions the frame holds | `FIX-GRID-3` | H22 | S31 | G |
| TP-106 | With more than 3 grids, panning shifts **which 3** are in frame | — | H24 | S28 | G |
| TP-107 | Arrow keys cross a grid boundary and the camera follows | `FIX-GRID-3` | H14, Q161 | S29 | G |
| TP-108 | In the overview, arrows select a **grid** and Enter focuses it | `FIX-GRID-3` | H15, Q162 | S29 | G |
| TP-109 | **A swipe fires once** — an emulated mouse event does not double it | — | H16, Q189 | S29 | G |
| TP-110 | A drag starting on a card places; on empty board it pans | `FIX-GRID-1` | H17, Q192 | S29 | G |
| TP-111 | Removing the focused grid refocuses the nearest survivor, preferring left | `FIX-GRID-3` | G17, Q318 | S30 | G |
| TP-112 | The remaining grids re-centre, animated | `FIX-GRID-3` | G18, Q321 | S30 | G |
| TP-113 | The board RESTS positioned on the grid the view is on — not at raw scroll 0 | `FIX-GRID-3` | `GAP-017` | S30 | G |
| TP-113 | `design_size` fits exactly 3 grids | — | H1, Q166 | S31 | G |
| TP-114 | **`SubViewport.size` never exceeds `game_picture_max_render_px`** | `FIX-FULL-15` | H3, Q169 | S31 | G |
| TP-115 | `resting_state()` returns the saved-pan pose, not the picture centre | — | H18, Q171 | S32 | G |
| TP-116 | Leaving and re-entering restores the pan, snapped to the nearest grid | — | H19, Q173 | S32 | G |
| TP-117 | A window resize re-derives the pose from the saved pan | — | Q179 | S32 | G |
| TP-118 | The wall re-packs around the wider picture | — | H20, Q180 | S33 | G |
| TP-119 | Info mode fits the window-aspect view, not the whole wide picture | — | H21, Q178 | S33 | G |
| TP-120 | `knobs_this_preview_does_not_drive` is empty when the editor is run | — | Q186 | S34 | G |

**By-eye sign-offs (E), no green test substitutes for these:**

| id | What a human must look at |
|---|---|
| TP-E1 | A covered card in a stack shows its **pip row**, readable, at every stack depth 2–15 |
| TP-E2 | A row growing tall pushes the rows above it up smoothly, with no overlap at rest |
| TP-E3 | The spring reads as a spring, not as the board lurching |
| TP-E4 | The zoomed-out view at 1, 2 and 3 grids is legible and centred |
| TP-E5 | A pan lands centred with no visible cut-off grid |
| TP-E6 | The wide picture shows no bare wall or frame at any window aspect |
| TP-E7 | Score labels do not collide with cards or with each other at height 15 |

---

## 7. Phase 8 — undo, save, resume

| id | Test | Fixture | Proves | Gates | Kind |
|---|---|---|---|---|---|
| TP-121 | Every placement is one undo step | `FIX-GRID-1` | Q230 | S35 | G |
| TP-122 | Undoing a placement that scored three lines rewinds all three | `FIX-TRIPLE` | Q231 | S35 | G |
| TP-123 | A put-it-back (no-op) placement commits no snapshot | `FIX-GRID-1` | Q16 | S35 | G |
| TP-124 | `pending_action` carries a placement and replays it from the pre-placement board | `FIX-GRID-1` | Q236 | S36 | G |
| TP-125 | A quit mid-cascade replays the whole placement including scoring | `FIX-CROSS` | Q237 | S36 | G |
| TP-126 | A replayed refill produces the identical board (no RNG in the path) | `FIX-DECK-52` | F23, Q233 | S36 | G |
| TP-127 | `validate()` catches a grid invariant violation | `FIX-MIXED-H` | Q238 | S37 | G |
| TP-128 | **A headless show and a viewed show produce byte-identical final state** | `FIX-DECK-52` | Q243 | S37 | G |
| TP-129 | The scores survive a save/reload with their values | `FIX-TRIPLE` | Q125 | S37 | G |
| TP-130 | A full headless show — deal, place every card, End — completes | `FIX-DECK-52` | U28, Q277 | S37 | G |

---

## 8. Fuzz

| id | Test | Proves | Kind |
|---|---|---|---|
| TP-131 | Seeded fuzz: place, remove and move at random; assert `validate()` stays empty, no card in two places | Q270 | G |
| TP-132 | Fuzz asserts the **set** of completed lines, never an exact total | Q269 | G |
| TP-133 | **Order independence of the SET**: the same final board reached by different orders completes the same line set | Q269 | G |
| TP-134 | A fuzz failure prints its seed | Q271 | G |

⚠ **TP-133 must assert the SET, not the total.** Owner (`Q269`): *"for testing purposes, i expect
final board score to be same score no matter the order as long as cards cannot be removed from their
spot or changed once placed."* Under those conditions the total matches too — but the moment an
effect can move a card, order changes the combo multiplier and the totals legitimately diverge.
Asserting the total unconditionally would fail for a correct reason.

---

## 9. Performance

| id | Measurement | Proves | Kind |
|---|---|---|---|
| TP-135 | `skill_spotlight_check()` cost at 1 grid vs 3 grids (75 extra cell cards), recorded in the test output | Q205 | G |
| TP-136 | `duplicate_state()` snapshot size and time at `FIX-FULL-15`, recorded | Q232 | G |

---

## 9a. Landed during Phase 0 — already written and green

| id | Test | Proves | Kind |
|---|---|---|---|
| TP-137 | `card_visual.tscn` ships **no** saved `ShaderMaterial` — neither an assignment nor a sub-resource | E5, S0 | G |

⚠ **TP-137 asserts the SCENE, not the symptom.** `CardOutline.material_of()` assigns `poly.material`,
which is a scene mutation under `@tool`, so any editor edit to the card scene bakes materials in —
capturing the suitless preview card's uniforms, including `u_frame_uv = (0,0,1,1)`, which is no frame
clamp at all. Asserting that no saved material exists catches every future re-bake rather than the one
uniform that happened to be wrong. It reads the `.tscn` as TEXT rather than loading it, because
loading would run the very `@tool` script that writes the material.

Red-then-green was run: with the baked scene restored both checks fail, for the expected reason, with
the suite's other 31 checks still passing. It lives in `Tests/Visual/test_outline.gd`.

⚠ **Not prevention — detection.** The editor can still re-bake. After any edit to the card scene,
`grep -c ShaderMaterial Cards/card_visual.tscn` must read 0.

⚠ **These RECORD numbers rather than asserting a threshold.** Owner (`Q205`): *"sure measure it as we
implement and note how much it hurts performance wise during tests."* Extend
`Tests/Engine/scoring_cost.gd` rather than writing a new harness.

---

## 10. Deliberately NOT tested

Stated as decisions, so they are not holes:

- **Card art and the bow animation** — owner-owned (`Q222`, `Q67`).
- **The exact feel of pan easing and the spring** — by-eye only (TP-E3).
- **Balance numbers** — a playtest question, not a test question (`Q278`=b).
- **The in-depth RNG generator** — not built (`todo.md`).
- **Old-save migration** — owner: *"just delete it manually or something"* (`Q213`).
- **Boosters, map, deck builder, menu, audio, worldgen** — out of scope (§4 anti-scope).

---

## 11. Node → test coverage

Every design node in the confirmed charts is claimed by at least one row above. Chart A is covered
by TP-10, TP-70–TP-78, TP-121; **B** by TP-25–TP-46; **C** by TP-18–TP-24, TP-40–TP-46; **D** by
TP-47–TP-61, TP-93; **E** by TP-80–TP-94, TP-E1–TP-E3; **F** by TP-70–TP-78, TP-126; **G** by
TP-62–TP-69, TP-111, TP-112; **H** by TP-97–TP-120, TP-E4–TP-E6.
