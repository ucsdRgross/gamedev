# Card effect API — the abstraction layer between modifiers and the game

**Status: REQUESTED, not designed.** This is the braindump plus a measurement of the current
seam. It is the input a `/flowchart-design` round would consume. **No step implements it yet.**

## The owner's request, verbatim

> *"card effects should be primarily script focused and never directly edit game values except
> via dedicated helper methods in the game itself. We likely need a dedicated class file to
> serve as layer between card modifiers and the game scene, specifically for which all
> modifiers will use to implement their effects while never directly touching the game file.*
>
> *the game when instanced will also generate an instance of this abstraction layer, static or
> not, which all card modifiers in the game will utilize to implement their effects. This helps
> us in the future to prevent duplicated code and makes it easy to update many cards at the same
> time if a general interaction changes due to theoretical updates to the game code.*
>
> *This will require all old cards to use this new framework as well."*

## What the code looks like today — measured, not assumed

A partial seam already exists and is routinely bypassed:

- **`CardEnvironment`** (`Scripts/card_environment.gd`) is already the modifier-facing
  abstraction for DISPATCH — 24 methods, and `Game` extends it.
- **`CardModifier.game` is typed `Game`**, the concrete scene script, not `CardEnvironment`.
  That property is the hole: every modifier can reach the whole game through it.
- **`CardModifier`'s own doc comment already states the rule as guidance:** *"State MUTATION
  should still go through Game's API (move_data_*, discard_data, ...)"*. It is unenforced, and
  the measurement below is what that costs.

**26 card files touch `game.` directly.** What they reach for:

| use | count | what it is |
|---|---|---|
| `game.state` | 25 | the board — **mostly reads**, some writes |
| `game.find_data_vec` / `get_zone_from_vec` / `row_slot_path` / `mancala_targets` / … | ~14 | board QUERIES |
| `game.score_line` / `add_line_score` / `register_combo` | 5 | scoring |
| `game.run_all_mods` / `on_mod_triggered` | 4 | dispatch |
| `game.act_overrun` / `act_cancelled` | 4 | the runaway guard |
| `game.discard_data` / `draw_card` / `move_data_to_coord` | 4 | deck and board mutation |
| `game.view` / `get_delay` | 2 | presentation |

So the surface a façade must cover is **board queries, board mutation, deck operations,
scoring, dispatch, the act guard, and presentation** — six or seven distinct concerns, not one.

## Why this is not yet actionable — the forks a questionnaire must settle

Each of these changes what gets built, and getting one wrong means migrating every card twice.

1. **Static or per-instance?** The request explicitly leaves this open (*"static or not"*).
   An instance per `Game` is testable and supports more than one game object at a time (the
   test suites build bare `Game.new()` objects constantly); a static singleton has cheaper call
   sites and no plumbing. This is the single most expensive decision to reverse.
2. **Reads too, or writes only?** *"never directly edit game values"* is about WRITES;
   *"never directly touching the game file"* is about EVERYTHING. `game.state` reads are 25 of
   roughly 60 total uses, so the answer roughly doubles or halves the work.
3. **New class, or widen `CardEnvironment`?** The dispatch abstraction already exists and
   `Game` already extends it. A second abstraction beside it means two layers to keep honest;
   widening it means changing a type every modifier already sees.
4. **Does it wrap presentation?** `game.view` and `game.get_delay` are animation, not rules.
   A rules-only façade leaves cards reaching for the view; a total façade has to model
   animation too.
5. **What happens to `CardModifier.game`?** Retyped to the façade, removed outright, or kept
   for reads with writes moved? Removing it is the only option that makes the rule enforceable
   rather than advisory — and it is also the most invasive.
6. **Is the boundary ENFORCED or documented?** A grep gate in the suite can fail on any
   `game.` inside `Cards/`, the way this project already gates the retired identifiers and the
   old `score_line` signature. Guidance alone is what produced today's 26 files.
7. **Migration sequencing.** All cards at once, or new cards first and old ones as they are
   touched? The poker-patience run has S16–S19, S35–S37 outstanding, several of which create
   cards.

## Recommendation

**Run a short questionnaire — roughly the seven questions above, not a full flowchart round.**
The intent is unambiguous and the *shape* is clear; what is not settled is a handful of
structural choices whose cost is asymmetric. Migrating every card is a large, mostly mechanical
change, and doing it twice because the layer turned out to be static-when-it-should-be-instanced
is the failure worth spending an hour of questions to avoid.

## Meanwhile

New cards written before the layer exists should keep their contact with `Game` **narrow and
funnelled**, so migration is a rename rather than a redesign. The poker-patience cards so far
touch only `game.state`, `Board.*`, `game.discard_data` and `game.score_line`.
