# Pair-review brief — a family-AE batch

Family AE is recognisable cards from everywhere, kept by NAME and idea only and given an effect
that fits this game. Owner rulings: every card keeps a suit and rank and still melds; a reference
must be recognisable to a general audience, not to fans of a game; a name already used by a live
effect carries ` v2` so neither effect is lost; an option beginning `Renames Qnnnn (Old Name):`
offers that existing effect this name.

## Read

`build/mine_cardindex/WRITE_PROMPT.md` (the writer's brief: the rename route, "Shapes that do
nothing", "Shapes already used up", the level-2 bar), `build/GAME_BRIEF.md` in full, the batch
module named in your task, and the AE modules already reviewed (`build/generated/g031.py` onward)
so a repeat inside the family is caught. `build/mine_cardindex/_live_index.tsv` holds every live
question with the owner's ruling. You may run `py build/mine_cardindex/levels_ae.py` and
`py build/render.py`; edit nothing.

## Questions

1. **Does each name's joke land in the default?** List drift, with a better effect.
2. **Rules fit** against `GAME_BRIEF.md` and the brief's shape lists.
3. **Renames.** Each target live, not rejected, restated faithfully, its own level 2 attached, and
   its slot noted when it differs from the row's. Any NEW option that is really a live effect's
   level 1 or level 2, or a repeat of an earlier AE row.
4. **Level 2.** Fallbacks ("twice", "two instead of one") without a `FLAGS` entry, and a level 2
   that does nothing under one option, each with a better level 2.
5. **The weakest five**, with concrete better designs: more fun, more tied to the grid and marks.

## Report

A short ANSWERS section, then ONE numbered FIX LIST that can be applied mechanically. Each item is
`eid field = new text`, the field one of `name`, `mechanic`, `a`, `b`, `c`, `default`,
`level2-a` / `level2-b` / `level2-c` / `level2-all`, `flag`. Every change you would make yourself,
most important first. One sentence per option; never ` · `; an "As (a)" must still read after (a)
changes.
