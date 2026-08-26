# Poker Patience — implementation plan

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/poker-patience/DESIGN.md`, version 2, charts confirmed 2026-08-25.
Every step below cites the design node IDs it implements.

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

File gaps at `solatro/design/poker-patience/gaps/GAP-NNN.md` using the template in `DESIGN.md`
§gap-protocol. Write the options in the questionnaire grammar; they become the next round's
questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## 0. How to read this

**`DESIGN.md` is the authority on behaviour. Where this plan and the design disagree, the design
wins and this plan is wrong.** `TEST_PLAN.md` lists every test that must exist. `NAMES.md` fixes
every identifier. You should not have to design anything.

⚠ **Quote a free-text answer, never summarise it.** 41 of the 314 answers are prose with no lettered
option. Where §1 carries one it is pasted verbatim, and if you need one this plan does not quote,
read it with:

```bash
node .claude/tools/answer_sheet.mjs solatro/poker-patience --prose
```

⚠ **This plan carries design ids. THE CODE NEVER DOES.** No `Q183=a` in a comment, a doc comment or
an `@export_group` label — Godot renders the last two as Inspector UI. The code gets the RULE the
answer produced; traceability is this document's job.

---

## 1. Normative contracts

Everything in this section is specified, not suggested. Each block names the `⚑contract` question
that authorises it.

### 1.1 The board coordinate (`Q1`, `Q3`, `Q69`, `Q2`)

A board position is **four components**: `grid, x, y, h`.

Owner's words, verbatim (`Q1`):

> *"4 component coordinate, with special case for entrance since it is technically row -1 since it
> is stacked above/below the grid."*

> *"yes, continuous, with entrance being part of y lattice, dynamically changing depending on which
> grid it is currently attached to."* (`Q3`)

- `grid` — index into the grid list, left to right.
- `x` — column, 0-based, left to right (`Q2`=a).
- `y` — row, 0-based, top to bottom (`Q2`=a). **The Entrance is `y == -1`** of whichever grid it is
  currently attached to; that attachment moves with the commit.
- `h` — height in the stack, **0-based** (`Q69`=a): the first card in a cell is `h = 0`.

`x` is **continuous across grids** (`Q3`): moving 5 columns left from `(grid 1, x 0)` lands at
`(grid 0, x 4)`. One global column ordinate, from which `grid` is derived. Off-board is the
four-component analogue of `Vector3i.MIN`.

⚠ `y` counts downward while `h` counts upward. That is deliberate and it is not a bug: rows are the
new dimension (`QR1` note), height is the old column depth re-read.

Normative (`Q1`, `Q2`, `Q3`, `Q69`):

```
class BoardCoord:
    grid : int      # index into GameData.grids, left to right
    x    : int      # column, 0-based, CONTINUOUS across grids
    y    : int      # row, 0-based, top to bottom; -1 == the Entrance
    h    : int      # height in the cell's stack, 0-based

    const NOWHERE          # the off-board sentinel; NEVER (0,0,0,0)
    const ENTRANCE_ROW = -1

    step_x(n) -> BoardCoord    # crosses grid boundaries; derives `grid` from the global column
    is_entrance() -> bool      # y == ENTRANCE_ROW
```

### 1.2 Grid count and layout (`Q4`, `Q5`, `Q7`, `Q13`)

```
grid_count = clamp(max(1, ceil(deck_size_at_game_start / grid_cards_per_unlock)), 1, grid_max_count)
grid_cards_per_unlock = 52      # Q5
grid_max_count         = 3      # Q7: "yes, tunable cap, have cap be 3 for now"
```

The divisor is the owner's answer to `Q5`, in full: *"52"*. So **0–52 cards → 1 grid, 53–104 → 2, 105–156 → 3**, capped at 3 (`Q4`=d). Evaluated **once at game
start** (`Q6`=a).

**Layout is CENTRED, and the gap follows from the count** (`Q13`=d):

- 1 grid: dead centre of the picture.
- 2 grids: placed so the exact centre of the picture is the **buffer between them**.
- 3 grids: the middle grid sits exactly where a single grid would.

`grid_buffer_px` stays a knob; the centring is the contract.

### 1.3 Grid shape (`Q10`)

A grid carries **its own width and height, defaulting to 5×5** (`Q10`=b). Nothing hard-codes 5. A
line is complete when every cell in it is occupied, at the grid's own width (`Q48`).

⚠ **The Entrance does NOT have a width property** (`Q27`=a). It is five slots because `rules1` holds
five `SkillAdderInputUpper` cards, each a `ZoneAdder` adding one column. Remove one card and the
Entrance is four wide. **Do not add an Entrance width field.**

### 1.4 Line kinds and the scoring section (`Q55`, `Q47`, `Q50`, `Q78`, `Q79`, `Q80`)

`Game.score_line(result, is_row: bool, zone: Array, index: int)` is **replaced**. The bool cannot
express four kinds.

**`ScoringSection` carries an opaque line key and `score_line` stops caring what shape it is**
(`Q55`=b). The bucket a section banks into comes **from the section**, not from a branch at the call
site.

Line kinds:

| Kind | Definition |
|---|---|
| `ROW` | every cell of one row of one grid, at one height |
| `COL` | every cell of one column of one grid, at one height |
| `DIAG` | the two corner-to-corner runs of one grid, no wrapping (`Q96`=a, `Q97`=a, `Q98`=a) |
| `HEIGHT_V` | a vertical run within one cell |

**Height semantics:**

- A horizontal line at height `h` requires every cell to have a card **at** `h`; a taller stack still
  has a card at `h`, so it counts (`Q79`=a).
- A vertical stack scores **at every multiple of 5, and scores the WHOLE stack** — 5 scores the five,
  10 scores all ten, 15 scores all fifteen. **Heights 6–9 score nothing** (`Q80`=a).
- Each completion is its own payout; the bottom five being paid again at height 10 is intended
  (`Q81`=a).
- Lines **never cross a grid boundary** (`Q87`=a).
- 3-D diagonals: the full family including corner-to-corner `x±1, y±1, z+1` (`Q86`=c).

**Evaluation order when one mutation completes several lines** (`Q50`=a): **rows, then columns, then
diagonals, then height.** Deterministic; the replay contract depends on it.

⚠ **"Complete" is defined by the SCORING RULE, not by the grid.** Owner verbatim (`Q48`):

> *"depends on the scoring system. For an effect checking for lines of 5, it requires that line have
> 5. for an effect that scores on specific patterns of 2x2 card layout, it would obviously check
> every completed 2x2 card shape."*

So the detector asks its own rule what shape it needs; a line of five is what the shipped rule asks
for, not a constant the engine imposes.

**Re-scan** (`Q47`=c): after the pass's own effects run, re-scan for lines they completed and score
those too, looping until nothing new completes.

Normative (`Q55`, `Q47`, `Q50`, `Q78`, `Q79`, `Q80`):

```
enum LineKind { ROW, COL, DIAG, HEIGHT_V }

ScoringSection.kind     : LineKind
ScoringSection.line_key : StringName        # opaque; the bucket derives from it
ScoringSection.of_line_at(grid:int, kind:LineKind, index:int, height:int) -> ScoringSection

Game.score_line(result: Scoring.Result, section: ScoringSection) -> void
    # is_row, zone and index are GONE. score_line never branches on shape.

evaluation order for one mutation: ROW, then COL, then DIAG, then HEIGHT_V
re-scan: loop the whole pass until no NEW line completes
vertical scoring heights: 5, 10, 15, ...   (6-9 score nothing; the WHOLE stack scores)
horizontal-at-height h: every cell must hold a card AT h; taller stacks still count
```

⚠ **There is NO line-scored memory and NO within-pass guard** (`Q51`=a). Every completion scores,
every time. An effect that removes and replaces a card in a complete line re-scores it on every
cycle — that is a legitimate archetype. **The act-level runaway guard (`act_event_cap`, `MAX_TICKS`)
is therefore load-bearing for CORRECTNESS, not just safety. Do not tune it away.**

### 1.5 The scoring trigger (`Q46`, `Q54`, `Q57`, `Q82`, `Q83`)

**Every board mutation runs a pass — arrivals and removals alike** (`Q46`=c).

The engine fires a new broadcast after every mutation; the detector card answers it by finding and
scoring completed lines (`Q54`=a). Hook name in `NAMES.md`.

⚠ **A mutation that only DROPPED cards down scores nothing** (`Q82`=a). The mover carries an
**explicit flag** saying the move was a compaction (`Q83`=a) — never inferred by comparing heights.

Normative (`Q46`, `Q54`, `Q83`):

```
&"on_board_mutated"(coord: BoardCoord, is_compaction: bool)   # after EVERY mutation
&"on_card_placed"(coord: BoardCoord)                          # after an arrival specifically

is_compaction is set BY THE MOVER and is never inferred from before/after heights.
A pass whose mutation is_compaction == true scores nothing.
```

⚠ **The pass runs AFTER the placement has committed.** Owner's words (`Q57`), verbatim:

> *"run_all_mods specifically expects to run over mutating live collections so i see no issue and
> question is a misunderstanding. Since scorer will default live in rules deck, it is last thing it
> checks regardless and all other effects will fire first anyways."*

The board is locked (`processing = true`) for the whole pass (`Q58`=a).

### 1.6 The economy (`QR5`, `Q322`, `Q323`, `Q129`, `QR4`, `Q132`)

Owner's words, verbatim (`QR5`):

> *"each grid gets its own row x col x diag = grid score
> hud shows total grid score from each grid added together as left number, multiplied by the combo
> number on the right. Since gameplay has changed, lets have each unique effect add +1 the first
> time, and repeat non-unique effects worth 0.5, all tunables.
> hud always shows most updated scores."*

Per grid, three buckets: **row**, **col**, **special**. Owner verbatim (`Q110`):

> *"I changed my mind. All diagonal type scores go to a single label to the right of the grid aligned
> with center of the grid, opposite side of row labels. This is the special meld score bucket.
> future special meld scores will also go to this bucket, regardless of if its diagonal or not,
> simply because having a unique label for every special meld would be impossible to place on screen
> and make sense. in data it is also one bucket"*

```
grid_score  = product of every bucket whose value is > 0
            = 0 when no bucket is > 0
board_total = sum of grid_score over grids
combo       = 1 + combo_unique_step * (firsts) + combo_repeat_step * (repeats)
displayed   = board_total  x  combo          # two numbers, live
```

⚠ **A bucket that has not scored ADDS 0 — it never multiplies by 0.** Owner's worked example,
verbatim (`Q322`):

> *"row + col + diag = 0 + 0 + 0. Row gets 10 score. it is now 10 + 0 + 0 = 10. Col gets 5 score. It
> is now 10 \* 5 + 0 = 50. Diag gets 2 score. It is now 10 \* 5 \* 2 = 100."*

⚠ **The test is the VALUE, never touched-ness.** Owner (`Q322`): *"if score is 0 do not multiply
regardless of if 0 is somehow a returned actual score from something."* A bucket worth 0 is excluded
from the product even when a line genuinely completed and scored 0.

**Combo** (`Q323`=b): `combo_unique_step = 1.0` for a first-of-its-class, `combo_repeat_step = 0.5`
for a repeat. **Melds and effects contribute on the same terms.** Both are `PlayerSettings` knobs.

⚠ **The multiplier is applied at DISPLAY time, not at banking time.** Owner verbatim (`Q129`):

> *"no. total always shows current combined grid score times current combo"*

So a line scored early is not worth less than one scored late; the product is recomputed live.

**Banking** (`QR4`=a): each line banks straight in; there is no end-of-show multiply and no act.
`combo_classes` accumulates for the whole show and nothing resets it (`Q130`=a).

**Retired:** `MAX_SUBMITS` and `submits_used` entirely (`Q132`=b); `score_additive` and its settings
field (`Q136`=a); `duplicate_class_scale` (`Q135`=b); the whole patience family (`Q26`=a).

⚠ `submits_used` lives on `GameData` **specifically so undo rewinds it**. Removing it touches undo,
resume, `RunState`, and `test_persistence_fuzz`. Do it deliberately, not incidentally.

### 1.7 Score storage (`Q124`, `Q125`, `Q126`)

Owner's words, verbatim (`Q124`):

> *"flat row and col scores, 2d arrays for row height and col height scores, and single variable for
> special meld scores. Doesn't seem like we need dictionary yet unless 2d array doesnt work"*

Per grid: flat arrays for row and column at height 0; 2-D arrays indexed `[index][height]` for the
raised levels; **one variable** for special melds. All follow the existing `BigNumber` +
`pack_scores()` / `unpack_scores()` contract (`Q125`=a).

⚠ `BigNumber` is `RefCounted` and invisible to `duplicate_deep`. Every new score container needs the
same manual copy `duplicate_state()` already does for the existing three (`Q240`=a).

**On grid removal** (`Q126`), owner verbatim:

> *"If a grid gets removed, then the score labels within the grid are removed as well. However,
> accumulated score is not lost."*

### 1.8 Card geometry after the flip (`Q306`, `Q307`, `Q309`)

**`CardVisual.CARD_SEPARATION`** is re-derived **from the bottom edge, with the same arithmetic
mirrored** (`Q306`=a).

✅ **MEASURED — Phase 0 has landed and the value is CONFIRMED at 16. Do not re-derive it.**

From the shipped `card_visual.tscn`: the card face spans y ∈ [−27, +27]; the pip row sits at
`position.y = 18` with a ±5 polygon, so it spans y ∈ [13, 23]. Card bottom edge is 27, so the margin
below the pips is **27 − 23 = 4** art units — identical to the 4-unit top margin the old layout had.

```
4 (margin to the bottom edge) + 10 (outlined pip) = 14
14 + 2 (idle-rig clearance)                       = 16   # CARD_SEPARATION, unchanged
```

**The board's row pitch does not move**: strip 40 px + separation 10 px = 50 px at `card_scale` 2.5,
exactly as §1i measured. Step S20 is therefore a comment re-derivation, not a value change.

**Row band anchor** (`Q307`=b): a row is measured from its **bottom edge**, the band grows **upward**,
and growth **pushes every row above it up** — the whole board grows upward from the Entrance.

**Height score label** sits **above the topmost card of its stack**, rising as the stack grows
(`Q309`=a).

**Draw order is UNCHANGED** — owner verbatim (`Q308`): *"draw order shouldnt change, so newest at top
is still in front."* This is correct: the card above overlaps the lower card's **top** region, and
the pips are at its **bottom**, so they stay readable.

### 1.9 The Entrance (`Q27`, `Q207`, `Q34`, `Q29`, `Q28`, `Q33`)

- Five slots, emergent from five `SkillAdderInputUpper` cards (§1.3).
- `TypeInput` keeps its class; **only `on_next` is removed** (`Q207`=a, `Q44`=a).
- **Refill is strictly left to right, no randomisation.** Owner verbatim (`Q34`):
  > *"lets just abandon the randomized refill for now then since I realize it doesnt make sense with
  > current way effect processing works from left to right. Use current system where leftmost draws
  > first, then next on right since it is next card triggering draw effect."*
- **Refill fires when the Entrance is empty OR no legal move remains**, with unused cards keeping
  their slots — owner verbatim (`Q33`): *"yes, refill happens when no more legal moves or empty
  entrance, with unused cards staying"*. A card leaving keeps its slot empty (`Q45`=a).
- **The first placement commits the batch to that grid** (`Q29`=a). The commit is **silent** — no
  confirmation (`Q29`=a), no dimming or marking of other grids (`Q25`=b), no separate indicator
  (`Q43`=b). Owner verbatim (`Q31`): *"yes, the entrance hand/row visibly detaches from the grid.
  choosing a grid causes it to move closer to committed grid"* — that movement is the only signal.
- Slot *i* aligns with column *i* **visually only**; a card from any slot may go in any column
  (`Q28`=b).
- The commitment lifts when **no legal placement remains in that grid** (`Q32`=b).
- Deck exhausted: slots stay **visible and empty**, unmarked (`Q36`=a).

### 1.10 Iterator order (`Q223`, `Q224`, `Q225`, `Q226`, `Q227`)

`Game.get_card_collections()` keeps **`draw_deck` first** (`Q223`=b). Within a grid the walk is
**row-major, as today** (`Q224`=b). Within a cell, **bottom to top** — index order, oldest first
(`Q225`=a).

⚠ **The early stop is REMOVED** (`Q226`=a). Today's 2-D walk stops at the first completely empty row;
a grid is sparse by nature and that stop would be an outright bug. Walk every cell of every grid.

Cell zone cards live in a `*_zone_type`-equivalent collection near the end (`Q227`=a).

### 1.11 Rules cards (`Q201`, `Q202`, `Q203`, `Q204`, `Q208`, `Q209`, `Q214`, `Q217`, `Q218`)

- A **meta card** counts the deck at game start and adds or subtracts persistent grid-creator cards.
  This mirrors what already ships — owner verbatim (`Q201`): *"yes, that is how current setup exists
  as well with meta cards in rule deck building pre grid board as well."* And on persistence, owner
  verbatim (`Q202`):
  > *"Sure lets have it persist. On game start, the meta card checking deck size will add or subtract
  > existing persistent grid creation cards based on current deck size. Removing that card would mean
  > grid count is no longer linked to deck size between games, which makes sense to me."*
- The **grid creator** is `ZoneAdder`-shaped: `on_spotlight` builds the grid, `on_unspotlight` removes
  it and discards its cards (`Q203`=a). **25 cell zone cards per grid**, each a real card (`Q204`=a).
- The **line detector** knows the geometry and enumerates lines itself (`Q217`=b). **Every**
  implementer runs, so two detectors score a line twice — a legitimate content lever (`Q218`=b).
  **One detector covers every shape**, height included (`Q219`=a, `Q220`=b).
- **Leaving the default rules deck** (`Q208`=b): the 6 lower adders, the grabber, the placer, the
  cascade scorer, **and** the poker evaluator (its `on_score_row`/`on_score_col` signature does not
  survive §1.4).
- **Archive** (`Q209`=c): moved directory **and** an archive rules builder. Their tests move with them
  and no longer run in the suite (`Q210`).
- New card frames come from `Assets/skill_art.png` (16×16 = 256 frames; 0–8 used). **Frame numbers
  are fixed in `NAMES.md`** (`Q214`=b). The owner supplies real frame art later (`Q222`).

### 1.12 Input (`Q187`, `Q189`, `Q198`, `Q199`)

- **Panning gets its OWN new actions**, leaving `wall_back`/`wall_forward` (`[`/L1, `]`/R1) alone
  (`Q187`=b). Names and bindings in `NAMES.md`.
- **Back/Forward are intercepted for the ZOOM levels**, not for panning — owner verbatim (`Q148`):
  > *"clicking on a grid zooms in, back button same with picture wall zooms outs, forward button
  > returns to same view as before. reusing buttons so basically intercepting."*
- **Touch swipe reads `InputEventScreenDrag` and ignores emulated events by `device == -1`**
  (`Q189`=a). Do **not** change `emulate_mouse_from_touch` — the wall's own pan reads the mouse form.
- New actions go in `_unhandled_input` (`Q198`=a) and need **both** a reader and a binding, keyboard
  **and** joypad, with a test asserting both halves (`Q199`=a).

### 1.13 The view and the wall (`QR3`, `Q145`, `Q160`, `Q166`, `Q168`, `Q169`, `Q171`)

Owner's specification, verbatim (`Q160`):

> *"one scroll container inside the picture to deal with tall stacks and potentially infinite grids
> or very large grids. Camera will pan over 3 possible grid positions since that is size of picture
> frame, and user can then choose to further scroll to reveal more of a single grid. choosing to pan
> left and right will shift current view of 3 grids left or right if there are more than 3 grids off
> edge of picture frame."*

- The show **opens zoomed out** (`Q145`). Clicking a grid zooms in; then left/right pans.
- `design_size` sized for **exactly 3 grids** (`Q166`=a); height is the board's natural height or the
  aspect minimum, **whichever is larger** (`Q168`=c).
- ⚠ **The render target is CLAMPED** (`Q169`=a) with `size_2d_override` keeping the layout at full
  size — the same mechanism `WallPicture.unfocus()` already uses. An oversized `SubViewport` fails
  **silently** in GL Compatibility (`DESIGN.md` §1m′ row 1). Knob: `game_picture_max_render_px`.
- **`WallPicture.resting_state()` returns the pose for the picture's SAVED PAN OFFSET** (`Q171`=a) —
  same shape, position shifted along the picture's width. ⚠ Every mover aims at `resting_state()`;
  a move computed against anything else lands wrong and is then cut. The saved pan is session state
  on the `WallPicture` (`Q172`=a) and is re-snapped to the nearest grid on restore (`Q173`=b).

### 1.14 Cross-grid alignment (`Q245`, `Q253`)

**Each grid sizes its own rows by default**, and the setting turns global alignment ON (`Q245`=b).
Key is `(grid, row)` with a shared maximum derived from it (`Q253`=b). Knob:
`grid_align_rows_globally`.

⚠ The setting must **not** affect scoring, and a test asserts the same board scores identically with
it on and off (`Q251`=b).

---

## 2. Phases and steps

Dependency order. Phases 1–4 and 8 are pure logic with hard gates. Phases 5–7 are visual and need
iteration against a preview. Phase 0 is the owner's.

### Phase 0 — the card flip (OWNER-EXECUTED, blocks everything)

**S0** *(implements E1, E2, E3, E4)* — Owner: pips to the bottom, art/talent to the top; skeleton
and animations recreated.

**Done-when** (`Q315`=c): the new `card_visual.tscn` is committed; `test_outline` is green; the
pip-row offset from the **bottom** edge is measured and handed over as the input to §1.8; and
`test_pixels`' deformed-pose signature is **re-derived** and recorded.

### ✅ S0 IS COMPLETE. Do not redo it. Evidence:

- Pips at `position.y = +18` (was −18), art at `−6` (was `+6`). The flip is in.
- `CARD_SEPARATION` measured and **confirmed at 16** — §1.8.
- Full suite green: **39 suites, 3120 checks, 0 failures**, `test_outline` and `test_pixels`
  included.
- **`test_pixels`' pose signature did NOT need re-deriving** — the existing pinned values still
  pass, so the re-baked rig deforms within the same envelope. `Q315`=(c) asked for a re-derivation;
  the honest outcome is that none was required, and the pinned numbers stand.

⚠ **One regression landed and was fixed during S0, and the trap is still live.**
`CardOutline.material_of()` assigns `poly.material`, which is a scene mutation — and `CardVisual` is
`@tool`, so **any editor edit to the card scene bakes ShaderMaterials into `card_visual.tscn`**. The
bake captures the uniform state of the scene's SUITLESS preview card, which leaves `Suit` and `Art`
with `u_frame_uv = (0,0,1,1)` — no frame clamp — and the art then samples its neighbouring sheet
frames.

Mitigated, not prevented: `material_of()` now re-seeds its uniforms on every call and marks new
materials `resource_local_to_scene`, and `test_outline` asserts the scene ships no saved material.
**If you touch `card_visual.tscn`, check `grep -c ShaderMaterial Cards/card_visual.tscn` is 0.**

⚠ No code phase may begin against the old art.

### Phase 1 — the coordinate and the grid container

**S1** *(implements C1, C2, C15)* — The four-component coordinate type and its arithmetic, including
continuous `x` across grids and the `y == -1` Entrance case. **Done-when:** `TP-01`–`TP-04` green.

**S2** *(implements C1, G6, G7)* — `GameData` grid storage: the grid list, per-grid cell arrays, and
the 25 cell zone cards per grid. **Done-when:** `TP-05`–`TP-07` green; `state.validate()` returns
empty on a fixture board with 3 grids at mixed heights.

**S3** *(implements C1)* — Position index and `_scan_positions()` extended to grids, plus the reverse
index (coordinate → card, `Q239`=b). **Done-when:** `TP-08`, `TP-09` green. ⚠ The reverse index is a
second representation of one fact — it needs a stated invariant tying it to the forward index, and
`validate()` must check it.

**S4** *(implements C1)* — `Board` mutation API for grid cells: place, move, remove-with-compaction.
Reuses `Anchor.ON_TOP` for stacking (`Q94`=a). Compaction bumps `revision` **once** (`Q91`=a) and
carries the compaction flag of §1.5. **Done-when:** `TP-10`–`TP-14` green.

**S5** *(implements §1.10)* — `CardDataIterator` and `get_card_collections()` for grids: `draw_deck`
first, row-major within a grid, bottom-to-top within a cell, **early stop removed**. **Done-when:**
`TP-15`–`TP-17` green, including the full-sequence assertion on a sparse fixture.

### Phase 2 — line detection and scoring

**S6** *(implements C3, C4–C9, B4)* — Line enumeration: every kind of §1.4, through a given cell,
within one grid. **Done-when:** `TP-18`–`TP-24` green.

**S7** *(implements B8, §1.4)* — `ScoringSection` gains its line key and kind; `score_line` loses
`is_row`/`zone`/`index`. **Done-when:** `TP-25`–`TP-27` green; **grep proves no caller passes the old
signature.**

**S8** *(implements B1, B2, B3, B18, §1.5)* — The mutation broadcast, the compaction flag, and the
board lock. **Done-when:** `TP-28`–`TP-31` green.

**S9** *(implements B4, B16, B17, B19)* — The detector card: enumerate, score, re-scan until nothing
new completes. **Done-when:** `TP-32`–`TP-36` green, including the runaway-guard bound of §1.4.

**S10** *(implements B9, B10, B11)* — Wire the section into `Scoring.PokerHands.score()` and the
existing spotlight cascade, **unchanged** (`Q56`=a, `Q60`=a). **Done-when:** `TP-37`–`TP-39` green.

**S11** *(implements C12, C13, B12)* — Height scoring: multiples of 5, whole stack, drops never score.
**Done-when:** `TP-40`–`TP-46` green.

### Phase 3 — the economy

**S12** *(implements D1–D4, §1.7)* — The three buckets per grid and their storage, including
pack/unpack and the `duplicate_state()` manual copy. **Done-when:** `TP-47`–`TP-50` green.

**S13** *(implements D5–D9, §1.6)* — `grid_score` as the product of positive buckets, `board_total`
as their sum. **Done-when:** `TP-51`–`TP-56` green, including the owner's worked example verbatim as
a fixture.

**S14** *(implements D10, D11, D14, D15)* — The combo model, and the retirement of `MAX_SUBMITS`,
`submits_used`, `score_additive`, `duplicate_class_scale` and the patience family. **Done-when:**
`TP-57`–`TP-61` green; **grep proves each retired identifier has zero remaining readers.**

### Phase 4 — rules cards

**S15** *(implements G1–G5, §1.11)* — The meta allotment card. **Done-when:** `TP-62`–`TP-65` green.

**S16** *(implements G6, G7, G13, §1.11)* — The grid creator card. **Done-when:** `TP-66`–`TP-69`
green.

**S17** *(implements F1, F12, F13, §1.9)* — `TypeInput` with `on_next` removed and the left-to-right
refill. **Done-when:** `TP-70`–`TP-74` green.

**S18** *(implements F3, F4, F7, F8)* — Commit, silent commitment, and the lift when no legal
placement remains. **Done-when:** `TP-75`–`TP-78` green.

**S19** *(implements §1.11 archive)* — Move the tableau cards to the archive directory, add the
archive rules builder, remove them from `rules1`, move their tests out of the suite. Owner verbatim
on the tests (`Q210`): *"moved, should no longer run as part of tests"*. **Done-when:** `TP-79`
green; suite count drops by exactly the moved suites and **no other suite changes**.

### Phase 5 — geometry and the flipped board (VISUAL)

**S20** *(implements E4, §1.8)* — `CARD_SEPARATION` re-derived from Phase 0's measurement.
**Done-when:** `TP-80` green; by-eye sign-off that a covered card shows its pips.

**S21** *(implements E7–E11, §1.8)* — Upward stacks, shared bottom edge, rows pushed up.
**Done-when:** `TP-81`–`TP-84` green plus by-eye.

**S22** *(implements E12, E13)* — `_row_open` inverted, Entrance at `y == -1` pushing the board up.
**Done-when:** `TP-85`–`TP-87` green.

**S23** *(implements E14, E15, E16)* — The spring: rigid lift of the stack above, overlapping rather
than re-flowing, hoop rides the jumping card. **Done-when:** `TP-88`–`TP-90` green plus by-eye.

**S24** *(implements D22, E17, §1.7)* — Score labels: rows left, columns below, one special-meld
label right of the grid centre, height labels above their stacks. **No subtotals anywhere.**
**Done-when:** `TP-91`–`TP-94` green plus by-eye.

**S25** *(implements §1.14)* — Cross-grid alignment setting. **Done-when:** `TP-95`, `TP-96` green,
including the scoring-invariance assertion.

### Phase 6 — the view (VISUAL)

**S26** *(implements H4, H6, H22)* — Two view modes; opens zoomed out; click a grid to zoom in.
**S27** *(implements H7, H8, H9, H10)* — Back/Forward intercepted for zoom; new pan actions; snap.
**S28** *(implements H13, H23, H24)* — The one scroll container, and panning shifting the 3-grid
window.
**S29** *(implements H14, H15, H16, H17)* — Keyboard/controller selection across grids; touch swipe.
**S30** *(implements G16, G17, G18)* — Refocus when the focused grid is removed, and re-centring.

**Done-when (phase):** `TP-97`–`TP-110` green, plus a by-eye pass at 1, 2 and 3 grids.

### Phase 7 — the wall (VISUAL)

**S31** *(implements H1, H2, H3)* — `design_size`, height rule, and the render-target clamp.
**S32** *(implements H18, H19)* — The saved pan and `resting_state()`.
**S33** *(implements H20, H21)* — Re-pack around the wide picture; Info mode fits the window-aspect
view.
**S34** — `Tools/wall_editor.tscn` drives every new wall knob (`Q186`=a).

**Done-when (phase):** `TP-111`–`TP-120` green; `knobs_this_preview_does_not_drive` still empty.

### Phase 8 — undo, save, resume

**S35** *(implements §1.7, `Q230`, `Q231`)* — Every placement an undo step; scores rewind with the
board.
**S36** *(implements `Q236`, `Q237`)* — `pending_action` carries a placement and replays it.
**S37** *(implements `Q238`, `Q243`)* — `validate()` grid invariants; headless parity assertion.

**Done-when (phase):** `TP-121`–`TP-130` green.

### Phase 9 — the goal-curve refit (its own phase, owner's call)

**S38** — Extend `Tools/scoring_sim.py` to the grid model and the §1.6 economy.
**S39** — Refit `goal_g0` / `goal_alpha` and record the derivation.

**Done-when:** the sim runs end to end and the fitted constants are committed with the command that
produced them.

### Phase 10 — the documentation and CSV rewrite (`QR8`=a)

**S40** — `ARCHITECTURE_REVIEW.md` amended in place (`Q279`=a): §1 class map, §2 move engine,
§3 scoring, §5 undo, §7 testing, §8 rulings.
**S41** — Alternate versions of `DESIGN_DOC.md`, `DESIGN_RECOMMENDATIONS.md`, `DESIGN_REFERENCES.md`.
Owner verbatim (`Q281`): *"alternate versions, lets archive the older versions for now"* (`Q280`).
**S42** — `CARD_CATALOG.csv`: reset the seen-flag **only where the card's premise depended on the
tableau** (`Q284`=b); mark impossible rows superseded, never delete (`Q285`=a); add the new axis
columns (`Q286`=a).
**S43** — `gam draft.txt` re-read and appended (`Q282`); the accepted-ideas CSV mined from the
curated/random CSVs plus catalog rows flagged seen-and-approved (`Q287`=b); a post-grid curated
effects CSV alongside the pre-grid one (`Q288`=a).
**S44** — `START_HERE.md`, `PICTURE_WALL.md`, `LAYERING.md` updated (`Q290`=b); `doc_check.py` clean
of **new** findings (`Q289`=a).

**Done-when (phase):** `py .claude/tools/doc_check.py` reports no new findings, and an independent
audit pass reads the **code**, not the rewrite (`Q291`=a).

---

## 3. Acceptance gates — objective and self-checking

One per phase, none talk-past-able.

| Phase | Gate |
|---|---|
| 0 | `test_outline` green on the new art; `test_pixels` pose signature re-derived and **not all zero** |
| 1 | `state.validate()` empty on a 3-grid fixture at mixed heights; iterator emits the exact expected sequence |
| 2 | The 15-height enumeration fixture (`TP-46`) finds exactly the expected line SET, compared as a set |
| 3 | The owner's worked example (`0+0+0 → 10 → 50 → 100`) reproduces exactly |
| 4 | A 52-card deck yields 1 grid, a 53-card deck 2, a 105-card deck 3, capped at 3 |
| 5 | A covered card's pip row is visible in a rendered screenshot (by-eye, signed off) |
| 6 | Panning lands every grid centred at 1, 2 and 3 grids; no cut-off grid at rest |
| 7 | A focused wide picture's `SubViewport.size` never exceeds `game_picture_max_render_px` |
| 8 | A headless show and a viewed show produce byte-identical final state |
| 9 | The sim runs and the fitted constants are committed with their command |
| 10 | `doc_check.py` reports no new findings |

---

## 4. Anti-scope — do NOT do these

- **Do not touch the suit-prop system, statuses, or the VFX/shader layer** beyond what
  `slot_center_global` forces (`Q294`).
- **Do not touch the comparator-bucket system** (`Q295`).
- **Do not redesign the outline shader.** It is direction-agnostic; the flip does not affect it
  (`DESIGN.md` §1m′ row 8).
- **Do not change `emulate_mouse_from_touch`** — it would break the wall's own pan (§1.12).
- **Do not add an Entrance width property** (§1.3).
- **Do not "fix" the FX mask by reading it from alpha** — it is rig-derived on purpose.
- **Do not tune away the runaway guard** — it is correctness-critical (§1.4).
- **Do not migrate old saves.** Owner verbatim (`Q213`): *"just delete it manually or something."* That is the whole migration story.
- **Do not build card art.** Owner verbatim (`Q222`): *"no, i will personally handle the frame art
  myself"*. The bow animation is a `todo.md` item (`Q67`), not a step.
- **Do not touch boosters, the map, the run economy, the deck builder, the menu, audio, worldgen**
  (`Q293`, `Q296`, `Q297`, `Q298`, `Q300`).
- **Do not build the in-depth RNG generator** — `todo.md` item, decoupled from the Entrance (§1.9).

---

## 5. Parallelism

- **Phase 0 blocks everything.**
- **Phases 1 → 2 → 3 are strictly sequential.**
- **Phase 4 depends on 1 and 2**, and can run in parallel with 3.
- **Phase 5 depends on 0 and 1.** Phases **5, 6, 7 are sequential** among themselves (each builds on
  the last's geometry).
- **Phase 8 depends on 1–4** and can run in parallel with 5–7.
- **Phase 9 depends on 3.** **Phase 10 depends on everything** and runs last.
