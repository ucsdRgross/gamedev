# Writing brief — the card index (family AE)

Family AE turns **recognisable cards from everywhere** into Solatro questions: the Human Card
Index's everyday cards, the famous cards and pieces of card, board, dice and casino games,
Stacklands' generic cards, and the cards Dungeons & Degenerate Gamblers borrowed. The source
card's own rules almost never fit a 5×5 poker grid. **Keep only its name and the idea the name
carries**, then give it an effect that fits Solatro.

## Read first

1. `build/GAME_BRIEF.md`, in full: the board, the four line kinds, the buckets that multiply, the
   slots, the live hooks, the marks, level 2, the house wording, and the Entrance stocks. Every
   rule there binds every option you write.
2. `build/mine_cardindex/_live_index.tsv`: every live question with its owner ruling. Search it
   (grep the concept's name, its synonyms and its mechanic words) before writing anything.
3. A handful of rows in `build/generated/g030.py` to see the house style: short, plain, concrete.

## One question per concept

A concept arrives as: name, sources, what it is in the original, a route hint, and a slot hint.

**The head** (the `mechanic` field) is one line saying what the card is to a player who has never
played the source game, e.g. *"The card that turns play around."* Never cite game lore beyond the
thing everyone knows about the card.

**Three options, (a) (b) (c)**, three versions of the same idea: three reaches, three mechanisms or
three strengths, whichever fork is worth putting to the owner. **(d) reject is added by the
renderer; do not write it.** The default is your recommendation and is never d.

**The rename route.** When a live, non-rejected effect in `_live_index.tsv` already does what the
name promises, option (a) offers the rename, worded exactly:

    Renames Q1234 (Old Name): <that effect's recommended or approved option, restated in one line>

The owner choosing it means that existing effect wears this name; nothing else changes. Prefer an
approved effect, then an unanswered one; never a rejected one (`ruling` = `rejected`), and never
one another AE row already offers (grep `Renames Q<id>` under `build/generated/`). Options (b)
and (c) are then new effects for the same name, so the owner can decline the rename and keep the
concept. When nothing fits, all three options are new.

⚠ **Never write a new effect that is another live effect under a new name.** If your idea is an
existing effect, that is the rename option, not a new one.

## Names

- The name is the **generic, recognisable name**, never a brand or a game's title: *Reverse*, not
  *Uno Reverse*; *Block Tower*, not *Jenga*. An ordinary word a game also uses (Chance, Railroad)
  is fine. When the name had to change, the head opens "After <source>:" so the reference stays
  visible (owner ruling, `GAME_BRIEF.md`).
- ⚠ **Duplicate names are allowed, lost effects are not.** If the name already belongs to a live
  question (case-insensitive, ignoring a leading "The") or to another AE row, append ` v2`
  (then ` v3`) to the new one. The rename option does not count: a rename is the same effect.

## What the owner has ruled for this family

- **Every card keeps a suit and a rank** and still takes part in melds. A resource, token or
  object concept is a **type** (a material: Wood, Brick, Stone) or a **skill** (a talent: Wheat,
  Villager), so it stays modifiable and meldable. Never write a card that has no suit or rank.
- Recognisable to a general audience, not to fans of the source game.
- A token is any card, named by the effect or chosen by the player, and the effect says whether a
  card it creates stays in the deck or is a ghost that leaves when the show ends.

## Shapes that do nothing — check every option against these

- **"When the show ends"** pays after the goal is met, or never: a show ends the moment its goal
  is met, and a lost show ends the run. Pay at a placement or an Entrance refill instead.
- **"Turn"**: write placement or Entrance refill.
- **A discard or destroy ACTION**: the player has none; an effect that waits on one waits on
  another effect.
- **"Every grid"** is void in a normal run, which plays one grid; **"all marks"** is a flat bonus
  fixed at the deal. Count matched or uncovered marks.
- **A payout outside a line names its bucket.**
- **Taking points out of a bucket** is unruled (Q-question "Charge-back" in class AE11 asks it).
  Until it is ruled, write the debit as floored: "..., to no lower than 0".
- **Nearest / farthest** always has ties: add "you choose among ties".
- **A match bonus is points AND a mult**: only its points go in a bucket ("rank-match points").

## Shapes already used up in this family

Five everyday cards already pay "a step for every Entrance refill it waited" (For Rent, Coat Check,
Overdue Notice, Bookmark, Time Card), and several re-score a line when a card returns. Do not write
another clock of that kind; reach for a different mechanism. The Undo button exists, so "take back
a placement" alone is not an effect.

Four cards already score a line, remove a card of it, and score it again when the cell refills
(Ace of Spades, Card Shark, Fifty-Two Pickup, Eviction Notice), and three give a sixth placement
beside the five in the Entrance (VIP Pass, Key Card, Dummy). Both shapes are used up too.

Four options already let a line score short of five cards (Skip, Doctor's Note, Zero, Half), with
The Courier and Four Fingers live. Used up as well.

An effect that needs the discard pile to hold cards does nothing in a run with no discarder: do
not make it the default.

**A free re-score clock** is the commonest hidden engine: anything that moves, swaps or slips a
card into a complete line at every refill scores that line again each time, because a complete
line scores whenever anything touches it. Say so in the option when you mean it, and bound it
(a cue, a charge, a placement you spend) when you do not.

**A rank or suit row whose option (a) is a rename**: the head must say so ("(a) is the live X
whole; for (b) and (c) level 1 is ..."), because the renderer prints every option of a rank row as
a level-2 addition.

## Code facts the reviews measured

- **Undo rewinds up to 25 placements, scores included** (`Levels/game.gd`, `undo_cap`). A chance
  the player could re-roll by undoing must be "drawn from the show's seed", said in the head.
  ⚠ Undo also crosses an Entrance refill, so anything revealed in answer to a player's choice (a
  guess, a hit or miss, a peek) can be read and undone for free. The owner accepts that until
  playtesting (`GAME_BRIEF.md`); still, do not lean on a wrong guess's cost as the only tension.
- **Only placement, move and removal re-score a line** (`Levels/game.gd`,
  `_broadcast_board_mutation`). A rank, suit or talent change touches nothing.
- **A covered card does not fire.** An effect on a card that something is placed on must sit on
  top (put the other card beneath it) or say it works while covered.
- **The default stacking rule** allows a card one rank apart on a DIFFERENT suit
  (`Cards/Skills/Rules/skill_placer_og_lower.gd`); any other stack needs "whatever the stacking
  rules say".
- **The Entrance refills when it is empty or no held card has a legal placement**, so sending the
  rest of the Entrance away is a free re-draw unless it costs something.
- **A suit's prop fires only on a suit-mark match** (the board plan), so "when three props cross"
  almost never happens; Hoops sweep rows only.
- ⚠ **The discard pile**: `GAME_BRIEF.md` says it persists to the next show; the code returns it
  to the run deck at show end (`Levels/game.gd`, `returned.append_array(state.discard_deck)`).
  Unruled. Write "to the discard pile" as out for this show, and do not build an effect on a
  discard pile that grows across shows.

## Slots and level 2

`suit`, `rank`, `type`, `stamp`, `skill`, `consumable`, `hazard`, `structure`, `status`. Most
concepts are skills; a material is a type; a one-shot object is a consumable; a curse, bomb or
rival is a hazard; a pack, minigame or run rule is a structure.

For every **skill and stamp** write a level 2 (its form while its card sits on a mark it matches):
one string when it is true of all three options, a 3-tuple when the options differ in mechanism,
and for a rename option the renamed effect's own level 2 from its question's head. A **suit or
rank** gets `"SUIT"` or `"RANK"` and options written as the level-2 addition. Type, consumable,
hazard, structure and status get `None`. `GAME_BRIEF.md` § "What makes a good level 2" is the bar:
a level 2 reaches further (its line, the next refill, the height), fires again, lets the player
choose, changes the mark, or turns a cost into a gain. ⚠ "Twice", "two instead of one" and "×2"
are the fallback; the pilot batch used them in a third of its level 2s. Use one only with a
`FLAGS` entry saying why nothing better fits.

## Output

A Python module, UTF-8, written with the Write tool:

```python
# -*- coding: utf-8 -*-
# Family AE, <class title>. (eid, name, cls, slot, mechanic, a, b, c, default)
SOURCE = "<the source group, e.g. party card games>"
ROWS = [
('CI0001', 'Reverse', 'AE3', 'skill',
 'The card that turns play around.',
 'Renames Q0520 (Reverse Card): ...',
 '...',
 '...',
 'b'),
]
# eid -> level 2: a str, a 3-tuple, "SUIT", "RANK", or None
LEVEL2 = {
 'CI0001': ('...', '...', '...'),
}
# optional: eid -> one line the owner sees as a flag, for a kept concept whose effect is weak
FLAGS = {}
```

`py build/mine_cardindex/levels_ae.py` checks the v2 rule against every live name and every AE
row, and fails naming each collision. Run it before you report.

It checks names only. **Your report names, per concept, the nearest live question by MECHANISM**
(grep the option text of `_live_index.tsv` for the trigger and the action, not the name), so the
reviewer checks a claim instead of re-deriving it. A new option that is another live effect's
level 1 or level 2 is a duplicate: make it the rename option or replace it.

The eids and the class are given in your batch. Never use ` · ` inside a field, and keep each
option to one sentence. Report, per concept: route taken, the Q-id renamed if any, and any concept
you could not make into a good effect (say why rather than writing a weak one).
