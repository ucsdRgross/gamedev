# Card effect API — the design

Derived from `BRIEF.md` plus the owner's answers to its seven forks, given 2026-08-27.
**This supersedes the "not yet actionable" note in `BRIEF.md`.**

## The owner's answers, verbatim

1. **Instance.**
2. *"reads too makes sense in case a parameter is removed in game and prevents everything
   immediately breaking, because abstraction method will still return something"*
3. *"new class makes more sense. This will theoretically be more verbose to support all possible
   effects, so dont want to clutter existing game file which should focus on being the data
   holder and foundation for everything else"*
4. *"Wrap everything for now including delay to keep it clean. reminder that effects should
   mainly modify game data layer, and that visual layer remains optional layer on top of
   everything."*
5. **`CardModifier.game` removed** — *"should point to new layer"*.
6. **Enforced.**
7. *"we dont have that many cards yet, so all cards at once is fine."*

## The rules these produce

- **One instance per `Game`**, created by the game and handed to modifiers. Not a singleton:
  the suites build bare `Game.new()` objects constantly and each needs its own.
- **Reads go through it as well as writes.** The reason is resilience, not purity: if a
  property disappears from `Game` or `GameData`, the wrapper still answers, so every card does
  not break at once. A wrapper method is therefore allowed to return a sensible empty value
  rather than propagate a missing member.
- **A new class**, not a widening of `CardEnvironment` and not more surface on `Game`. `Game`
  stays the data holder and the foundation; the API layer is expected to grow verbose as it
  covers more effects, and that verbosity lives on its own.
- **It wraps everything cards touch, including `get_delay()`.** ⚠ But the layering rule stands:
  **effects modify the DATA layer; the visual layer is optional on top.** An effect that cannot
  run headless is wrong.
- **`CardModifier.game` is REMOVED.** Modifiers reach the layer instead.
- **The boundary is ENFORCED**, not documented — a suite gate fails on any direct `Game`
  reference inside `Cards/`, the way this project already gates the retired identifiers and the
  old `score_line` signature.
- **Every existing card migrates at once.** 26 files today.

## Names — chosen here, not fixed by any registry

⚠ No document fixed these; they are the overseer's choice and are cheap to change **now** and
expensive later. Say so if you want different ones.

| Name | What |
|---|---|
| `CardEffectApi` | `class_name`, `RefCounted`. The layer. One per `Game`. |
| `Game.effect_api` | The game's own instance. |
| `CardModifier.api` | What every modifier reaches for. Replaces `CardModifier.game`. |

## The surface — measured from what cards actually use today

Nothing speculative: this is the complete set of members `Cards/` reaches for, so the first
version wraps exactly this and grows as effects need more.

**Board reads** — `grids`, `upper_zone`, `lower_zone`, `upper_zone_type`, `lower_zone_type`,
`draw_deck`, `position_of`, `revision`, `total_score`, `forced_spotlight`,
`find_data_vec`, `get_zone_from_vec`, `is_data_topmost`, `row_slot_path`, `row_slot_path_from`,
`column_rise_path`, `mancala_targets`, `entity_side_for_row`

**Board and deck mutation** — `move_data_to_coord`, `discard_data`, `draw_card`

**Scoring** — `score_line`, `add_line_score`, `register_combo`

**Dispatch** — `run_all_mods`, `on_mod_triggered`

**The act guard** — `act_overrun`, `act_cancelled`

**Presentation** — `get_delay`, and whatever `view` access survives review (a card reaching
`game.view` directly is the case the layering rule is aimed at)

## Sequencing

Runs **before S16**, so the remaining poker-patience cards are born on the new framework rather
than migrated a second time. Staged, suite green between each:

1. `CardEffectApi` with the measured surface; `Game` creates one; `CardModifier.api` added
   alongside the existing `game` property.
2. All 26 card files migrated to `api`.
3. `CardModifier.game` removed, and the enforcement gate added.

## Resolved during implementation

- **`game.view` is NOT wrapped, and needs no wrapper.** The measurement settled it: the only
  code reaching `game.view` is `card_visual.gd`, a `Node2D`. That is the card's visual node,
  not a modifier, and it does not use this layer. No card EFFECT touches the view at all, so
  the layering rule holds with no accessor for it.
- **The gate scans by `extends`**, not by directory: a file is a modifier when its base is one
  of the CardModifier types. That is what keeps the visual node and the prop classes out of
  scope without an allowlist that would rot.
