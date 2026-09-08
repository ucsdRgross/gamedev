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
- A **completed line of 5 scores immediately** as a poker hand. Lines are: the 5 rows, the
  5 columns, and the 2 long diagonals.
- A placed card **cannot normally be moved or stacked on**. Both are reserved for effects.

## The coordinate is four-dimensional

`(grid, x, y, height)`. Grids are aligned, so row 1 of every grid sits at the same y — "move
5 left" lands in the same cell of the grid to the left. **Height** is stacking: cards stacked on
a cell push the rows below down to make room. Five aligned at the same height is a line and
scores. A **vertical stack scores only at a multiple of 5 cards** and pays the WHOLE stack each
time — heights 6–9 pay nothing, and the bottom five being paid again at 10 is intended. Removing
a card drops the stack above it. Removing and re-adding a card re-triggers its line.

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

`on_score` · `on_score_row` / `on_score_col` · `on_after_score` · `on_line_complete` (new) ·
`on_place` (new) · `on_next` (entrance refresh) · `on_spotlight` / `on_unspotlight` ·
`on_stage_changed` (deck/play/discard/rules/zone) · `on_card_dropped_on` ·
`on_trigger` / `on_mod_triggered` (any effect anywhere fires) · `can_grab` / `can_place` ·
`stack_*_allow` / `_deny` · `meld_*_allow` / `_deny` / `_group` / `_wrap_bounds` ·
`on_compare_ranks` / `on_compare_suits` · prop lifecycle (`on_spawned`, `on_pass_card`,
`on_dropped_by`, `on_finish`, `on_lap_completed`) · `on_game_end` · `on_map_picked`

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

## What makes an effect BAD here

- It is a pure numeric reskin of another effect (`+3 Mult if Hearts` vs `+3 Mult if Spades`).
- It depends on a hand of cards the player holds, on discards-per-round, or on blinds/antes —
  none of those exist in this game.
- It is art direction, sound, UI polish, or engineering work rather than a mechanic.
- It is a restatement of a rule the game already has.
