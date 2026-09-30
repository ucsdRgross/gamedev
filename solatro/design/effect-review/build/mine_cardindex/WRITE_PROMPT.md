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
approved effect, then an unanswered one; never a rejected one (`ruling` = `rejected`). Options (b)
and (c) are then new effects for the same name, so the owner can decline the rename and keep the
concept. When nothing fits, all three options are new.

⚠ **Never write a new effect that is another live effect under a new name.** If your idea is an
existing effect, that is the rename option, not a new one.

## Names

- The name is the **generic, recognisable name**, never a brand: *Reverse*, not *Uno Reverse*;
  *Get Out of Jail Free*, not *Monopoly card*. The source game goes in the head only when the card
  is unrecognisable without it.
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
