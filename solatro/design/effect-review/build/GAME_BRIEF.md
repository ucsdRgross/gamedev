# Solatro — the rules an effect has to fit

A circus-themed poker-solitaire deckbuilder in Godot. Read this before judging any effect.

## The board

- Cards are placed into **5×5 grids**. One grid is unlocked per **52** cards in the deck at game
  start, floored at 1 and capped at 3 — so a normal run plays **one** grid and never reaches a
  second. Multiple grids sit side by side; a zoomed-out view shows them all, a focused view one.
- The **Entrance** holds 5 incoming cards. The player picks one up and places it in any empty
  cell of a grid. The first placement **commits the grid**, and no other grid accepts a card until
  the committed one has no legal placement left. The Entrance refills only when every slot is
  empty, so the player commits all five before seeing the next five.
- A **completed line of 5 scores immediately** as a poker hand. There are **four line KINDS**
  (`ScoringSection.LineKind`), and an effect that says "row or column" is describing a quarter of
  them: **ROW**, **COL**, **DIAG** and **HEIGHT_V**.
  ⚠ **DIAG is a family of TEN directions, not two long diagonals** (`LineGeometry._DIAG_DIRECTIONS`):
  the 2 flat corner-to-corner runs, 4 runs that climb one horizontal axis plus height, and 4
  corner-to-corner 3-D climbs. A climb never descends.
  ⚠ **Lines never cross a grid boundary and never wrap.** Evaluation order for one placement is
  ROW, COL, DIAG, HEIGHT_V, and it is deterministic because the resume-replay contract depends on it.
  ⚠ **There is no line-scored memory.** A complete line scores EVERY time anything touches it, so an
  effect that removes and replaces a card in a complete line re-scores it every cycle. That is a
  legitimate archetype; the only bound is the runaway guard, which charges only REPEAT activations.
- A placed card **cannot normally be moved or stacked on**. Both are reserved for effects.

## The coordinate is four-dimensional

`(grid, x, y, height)`. Grids are aligned, so row 1 of every grid sits at the same y — "move
5 left" lands in the same cell of the grid to the left. **Height** is stacking: cards stacked on
a cell push the rows below down to make room. Five aligned at the same height is a line and
scores. A **vertical stack scores only at a multiple of 5 cards** and pays the WHOLE stack each
time — heights 6–9 pay nothing, and the bottom five being paid again at 10 is intended. Removing
a card drops the stack above it. Removing and re-adding a card re-triggers its line.

## The player's buttons

**End** (ends the show) and **Undo**, plus the Deck, Discard and Rules viewers. There is **no
Submit and no Next button** - the Entrance refills on its own. An effect that says "press Next" is
stale; one that ADDS a button is legal design space.

## Discards

**Discarding is a real board mechanic.** A card effect removes cards from the board into the
**discard pile**, either as its target or as a side effect. The discard pile is where cards go that
are not deleted from the deck outright, and it **persists to the next show**. What does NOT exist is a
player discard ACTION or a Balatro-style per-round discard BUDGET. So an effect keyed to discard
events, the discard pile, or cards leaving the board is live design space; only one that assumes a
discard budget the player spends is stale.

## Scoring

Poker hands give flat points, banked the instant a line completes. **There is no act, no Submit
and no final scoring pass** — the player ends a show with End, and the score shown is always
current.

Each grid keeps **three buckets**: row, column, and **special** (every diagonal AND every vertical
stack shares this one). A completed line adds into its bucket, so scores within a bucket ADD.

```
grid_score  = the PRODUCT of that grid's buckets whose value is > 0, and 0 when none is
board_total = the SUM of grid_score over grids
combo       = 1 + 1.0 x (first-of-its-class) + 0.5 x (repeats)
displayed   = board_total x combo          # applied at DISPLAY time, live
```

⚠ **A bucket that has not scored ADDS 0 — it never multiplies by 0.** Owner's worked example: row
+ col + special = 0+0+0; row banks 10 and it is 10; col banks 5 and it is 50; special banks 2 and
it is 100. The test is the VALUE, never touched-ness.

⚠ **What this means for an effect.** A point is worth the product of the OTHER two buckets, so
opening a grid's empty bucket is worth far more than growing a full one, and an effect that
reaches a bucket the player struggles to fill (special, i.e. diagonals and stacks) is worth more
than its raw number suggests. **Melds and effects feed the combo on the same terms** — a
first-of-its-class adds 1.0, a repeat 0.5 — and the combo never resets for the whole show, so
breadth of distinct triggers matters as much as size of numbers.

## A card's anatomy — every effect must fit ONE of these slots

| Slot | What lives there |
|---|---|
| **suit** | `PipSuit`. Permanently active. Spawns props. Defines flush identity and stacking legality. |
| **rank** | `PipRank`. Permanently active. Defines straight identity and numeric value. |
| **type** | The card's material — paper, iron, gold, glass, balloon, water. Deck behaviour and durability. |
| **stamp** | The hat / equipment slot. Modifies HOW the card's other parts fire (double trigger, active while covered, always spotlit). |
| **skill** | The talent / feat slot. The joker-equivalent and the widest slot. |
| **consumable** | A card spent for a one-shot effect instead of being placed. |
| **rule** | A card in the hidden rules deck. Changes a DEFAULT rather than adding an exception. |
| **status** | Applied at runtime, never authored — burning, juggling, injury. Only reachable via another effect. |

If an idea cannot be expressed in one of those slots, it does not belong in this corpus.

## Live hooks an effect can fire on

`on_score` · `on_score_row` / `on_score_col` · `on_after_score` · `on_board_mutated` (the grid
mutation broadcast the line detector answers) · `on_card_placed` (fires AFTER the line detector has
already scored, so a bonus that must be inside the meld's own number cannot come from here) ·
`on_next` (entrance refresh) · `on_refill` · `on_spotlight` / `on_unspotlight` ·
`on_stage_changed` (deck/play/discard/rules/zone) · `on_card_dropped_on` ·
`on_trigger` / `on_mod_triggered` (any effect anywhere fires) · `can_grab` / `can_place` ·
`stack_*_allow` / `_deny` · `meld_*_allow` / `_deny` / `_group` / `_wrap_bounds` ·
`on_compare_ranks` / `on_compare_suits` · prop lifecycle (`on_spawned`, `on_pass_card`,
`on_dropped_by`, `on_finish`, `on_lap_completed`) · `on_game_end` · `on_map_picked`

## ⚠ The board plan — CONFIRMED DESIGN, not yet built

`design/board-plan/` is confirmed and handed off. Judge an effect against it, and say when an idea
only works on the pre-plan board.

- At show start the **deck deals every cell a MARK**: an unplayable grey copy of one of your own
  cards, drawn evenly across the five Entrance stocks, no card marked twice while any is unmarked.
- Placing a card that agrees with its mark on **rank, suit, talent or hat** pays per agreeing
  property, independently and additively. A rank match pays FLAT points; a talent or hat match pays
  a MULT. **Bonus mults SUM and a sum of 0 never multiplies.**
- ⚠⚠ **A SUIT EFFECT NOW FIRES ONLY WHEN ITS SUIT MARK IS MATCHED.** This retires the old rule that
  a talented card suppresses its own suit effect. Any effect whose premise is "when this card scores,
  its suit does X" is now conditional, and an effect that grants or bypasses that condition is
  valuable rather than redundant.
- A mark is **never a card**: it completes no line, scores nothing, is never spotlit, and blocks
  nothing.
- A level or blind **may grant marks of cards outside your deck** (that is the hazard/blessing seam).

## ⚠ The Entrance is five per-slot STOCKS — confirmed design, not yet built

`design/sidebar/` §17 is answered and runs FIRST. The deck is split evenly across the five slots by
one shuffle dealt round-robin; each slot draws its own stock top-down and flips a face-down card up
in place. "The deck is empty" means every slot's stock is empty. **So the player partly controls
draw order** by choosing which slot to play from — an effect that keys on draw order has something
real to key on now.

⚠ **The union of the stocks IS the deck** — it is ONE shuffle dealt round-robin, so "the top of
the deck", "the bottom of the deck" and "reorder the deck" all still mean something. A
deck-order effect is NOT stale just because the deck is dealt into five piles; it is stale only if
it needs a single DRAW POINTER, which is the thing that became five.

⚠ **The Entrance's WIDTH is not fixed.** `add_column` / `remove_column` exist and the sidebar
design explicitly allows a future effect to widen or narrow it, so an effect that changes the
Entrance from five slots is legal design space, not a contradiction.

## Spotlight

A card's abilities only fire while it is **uncovered** ("spotlit"). A covering card hides what is
under it unless one of its modifiers opts out. Scored cards are forced spotlit during scoring.

## Props

Suits spawn **props** — physical objects that travel the board and interact with cards. Hoops
sweep a row and re-score skill cards. Knives sweep from the opposite edge and score non-skill
cards. Balls arc down a column and apply Juggling. Flames apply Burning, which multiplies the
prop effects of the card that carries it.

## Classes

Cards belong to one of eleven classes, each with a mechanical identity: Magician (creation and
deletion), Acrobat (movement), Animal Trainer (stacking and eating), Clown (pip manipulation),
Dancer (formations), Escape Artist (negative effects), Fortune Teller (deck manipulation),
Special Effects (points and combo), Concessions (positive effects), Costume Designer (stamps and
equipment), Producer (token and money cards).

## What makes an effect GOOD here

- It uses the grid. Coordinates, lines, adjacency, height, cross-grid reach.
- It has **its own identity** and does not overlap another effect's design space.
- It is expressible in one sentence of pure mechanics — trigger, action, number.
- It composes with the +1-per-trigger combo rather than just inflating one number.

## Standing owner rulings an effect may not contradict

- **Overscore is retired.** Punishing overperformance breeds sandbagging. An effect that raises
  future goals because you scored well is against a ruling, not merely unbalanced. Scale
  REWARDS, never goals. (A goal that rises with something else - gold held, time taken - is fine.)

## What makes an effect BAD here

- It is a pure numeric reskin of another effect (`+3 Mult if Hearts` vs `+3 Mult if Spades`).
- It depends on a **hand of cards the player holds**, on a **per-round discard budget**, on an **ante
  ladder**, on a **Submit button**, on an **act structure**, or on an **upper/lower tableau** — none
  of those exist. A **blind** does exist, as a level modifier a level draws (`blinds.csv`); the ante
  ladder that selected them does not.
- It ASSUMES the board clears by itself — nothing clears the grid mid-show by default.
  An effect that DELIBERATELY destroys or discards cards is fine; one whose premise is
  "after the line clears" or "the scored cards are removed" is stale.
- It restates something the grid already does, or something the board plan already does.
- It is art direction, sound, UI polish, or engineering work rather than a mechanic.
- It is a restatement of a rule the game already has.
