# The board plan — implementation plan

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/board-plan/DESIGN.md`, version 1, confirmed after round 4. Every step
below cites the design node IDs it implements.

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
5. ⚠⚠ **THE CODE BEING BROKEN IS NOT A GAP — FIX IT.** If the design says what should happen and the
   code does not do it, that is a BUG, and the only open question is *how* to fix it, which is
   yours. Filing it spends an owner round to be told "yes, fix the bug". Measured: one run filed
   ~50 gaps and a large share were this. **Before filing anything, ask in order:** does the design
   already answer it (→ fix the code); would any defensible choice be invisible in the product
   (→ assume it, log one line); would the owner recognise this as a decision they want (→ only now,
   a gap). A gap asks for a RULING, never for permission — if you are filing to be told it is fine
   to proceed, write the assumption instead.

File gaps at `solatro/design/board-plan/gaps/GAP-NNN.md` using the template in
`solatro/design/board-plan/DESIGN.md` §21. Write the options in the questionnaire grammar; they
become the next round's questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## 0. What this is

The grid stops opening empty. At show start the deck deals **marks** across every cell — unplayable
grey stand-ins printed onto the cell's own zone card. Placing a card whose rank, suit, talent or hat
agrees with its cell's mark pays a bonus per agreeing property. Marks can carry effects. Two shipped
rules retire on the way (§1.6, §1.5).

`DESIGN.md` is the authority on behaviour and is cited by question id throughout. Where this plan
and the design disagree, **the design wins and this plan is wrong.**

---

## 1. Normative contracts — specified, not suggested

### 1.1 What a mark IS

*Authorised by `Q58` (⚑contract, the stage), `Q59` (⚑contract, the spotlight exclusion this
predicate exists to serve) and `Q4` (⚑contract, which slots are copied).*

A mark is the cell's **existing** `cell_types[i]` card, which already exists, is already walked by
every collection, and is already rendered under the stack (`DESIGN.md` §1a, §1b; `Q58`=(a)).

```
A cell is MARKED  ⇔  cell_types[i].rank != null or cell_types[i].suit != null
```

There is **no second array, no parallel container, and no `marked` flag.** `GridData.build_cells()`
keeps making bare `TypeGridCell` cards; the dealer writes onto them.

`TypeGridCell` gains exactly one field:

```gdscript
## True when a level or blind granted this mark rather than the deck dealing it (Q53=a).
## Read only by GameData.validate()'s deck-membership invariant, which exempts it (Q121=a).
@export_storage var granted : bool = false
```

⚠ **THERE IS NO REALIZED-MARK LEDGER, AND ADDING ONE IS WRONG.** The design's §2 sketched one; the
answers removed the need for it. A match is derived live (`Q13`=(b)), pays every time
(`Q20`=(a)), there is no board bonus (`Q44`=(b)) and no HUD progress count (`Q72`=(c)) — so nothing
has to remember anything. Everything is a function of the live board.

### 1.2 Dealing the plan

One board-wide deal, run once, from `Game._start_fresh_show()` after the grid creators have built
every grid and **before** the first Entrance refill (`Q9`, `Q10`, chart A).

> `Q9`, verbatim: *"across all existing grids at once after grid sizes are known. each grid gets its marks from the same stock. such that 2 5x5 grids use 50 different cards from the same stock, such that 50 out of 52 cards of the deck appear marked on the 2 different grids with no reused cards for marking."*

```
deal_plan(state, rng):
  cells   := every (grid, x, y) of every grid, in grid order then row-major     # Q9
  order   := shuffle(cells, rng)                     # ONE shuffle, walked start to finish  Q99, Q100
  stocks  := the Entrance's per-slot stocks                                      # sidebar QR9=a
  unused  := every card in every stock, still unmarked this show                 # Q108
  for cell in order:
      stock := next stock in round-robin, left to right, skipping exhausted ones # Q93=b, Q201-shape
      card  := an unused card of that stock, chosen with rng
      if no unused card anywhere: begin another pass — every card is unused again # Q1=b, Q102=a
      write_mark(cell, card)
```

- **Stratified by stock, exactly `cells / stocks` per stock**, remainder round-robin **left to
  right** so the earlier stocks take the extras (`Q93`=(b); the remainder rule mirrors
  `sidebar Q201`=(a) and is pre-authorised, §4).
- **No card is marked twice while any card is unmarked** (`Q108`=(a), `Q109`=(a)) — across every
  grid, and for the whole show, not per grid.
- **Repeats are uncapped** once a pass completes (`Q102`=(a)) and **may share a row, column or
  diagonal freely** (`Q101`=(a)) — no rejection, no backtracking.
- **`write_mark` copies every printed slot** — `rank`, `suit`, `skill`, `stamp` — and **never
  `statuses`** (`Q4`=(b), `Q5`=(a)). Copy with `duplicate_deep(Resource.DEEP_DUPLICATE_ALL)` and
  then `GameData.relink_card_backrefs(type_card)`; the `WeakRef` backref trap applies here exactly
  as it does everywhere else (`ARCHITECTURE_REVIEW.md` §6).
- **A mark names printed properties, never a card object** (`Q3`=(a)). Nothing stores a reference to
  the source card.

### 1.3 Randomness, and why nothing re-derives

```gdscript
## Dealt once, stored, never re-derived. Seeded so a re-entered show is the same show (Q8=a).
@export_storage var plan_seed : int = 0
```

⚠ **`Array.shuffle()` CANNOT BE SEEDED** — it uses the global RNG (`DESIGN.md` §1m,
[godot-proposals#11853](https://github.com/godotengine/godot-proposals/issues/11853)). The deal uses
a `RandomNumberGenerator` instance seeded from `plan_seed` and a hand-written Fisher–Yates over
`randi_range`. `plan_seed` is written once, at deal time, from the run seed combined with the map
node id (§4), and the DEAL RESULT is what persists — no later path calls the RNG, so replay, resume
and undo are free exactly as `draw_deck`'s stored shuffle is (`DESIGN.md` §1k).

### 1.4 The match test

*Authorised by `Q16` (⚑contract, per-property independence) and `Q13`=(b), which makes the test
live rather than frozen.*

```gdscript
## Which printed properties of `card` agree with the mark on its own cell. Empty when the cell is
## unmarked, when the coordinate is off-board, or when nothing agrees.
## Derived LIVE on every call and never cached (Q13=b): a modifier changing a card's suit emits
## `data_changed`, not a `revision` bump, so a revision-keyed cache would answer stale.
static func matches_at(state: GameData, card: CardData, coord: BoardCoord) -> int   # a bit mask
```

| Property | Agrees when | Node |
|---|---|---|
| `RANK` | `PipComparator.printed_same` on the two ranks | `QR3`=(a) |
| `SUIT` | `PipComparator.printed_same` on the two suits | `QR3`=(a) |
| `TALENT` | both carry a skill AND it is **the same script** | `Q34`=(a) |
| `HAT` | both carry a stamp AND it is **the same script** | `Q37`=(a) |

- Each property is tested and paid **independently and additively** (`Q16`=(a)); there is **no
  all-four bonus, no line bonus, and no board bonus** (`Q17`=(b), `Q42`=(b), `Q44`=(b)).
- **Every card in the cell is tested, not only height 0** (`Q15`=(b)).
- **A card an effect placed matches identically to one the player placed** (`Q14`=(a)).
- **`type` and `statuses` are NOT matchable** (`QR3`=(a) chose the four named).
- A card matching nothing leaves the mark intact underneath it (`Q18`=(a)).

**Content may loosen the test** through its own hook family, mirroring `PipComparator`'s shape
exactly — one hook per situation, **no fallback from the meld or stack families** (`Q41`=(a),
`DESIGN.md` §1j). Names in `NAMES.md`.

### 1.5 The score composition ⚑ THE CONTRACT THAT MATTERS MOST

*Authorised by `Q104`, `Q105`, `Q122` and `Q21` — every one of them ⚑contract.*

```
line score = (hand score + Σ flat bonuses) × M          where M = Σ bonus mults
                                                        and M == 0 means NO multiplication
```

⚠ **`ScoreModel` IS NOT TOUCHED.** `Scoring.ScoreModel.final_score()` returns one flat `int`. The
full-flush double and the copy escalation happen inside that number and are **invisible past it**
(`Q104`=(d), owner: *"scoring a meld should return the score of that hand only, with no knowledge
that it used multiplication internally to arrive at that score"*). Every existing hand scores
exactly what it scores today. **A step that edits `ScoreModel` is a defect.**

- **Flat bonuses**: a RANK match pays the printed rank value, **rounded up**, with the **Ace worth
  10** and any rank with no integer value paying a flat **10** (`Q21`=(a), `Q26`, `Q27`).
  > `Q26`, verbatim: *"its value rounded up, if it doesnt have a value convertable to int, a flat amount like 10."*
  > `Q27`, verbatim: *"ace can be worth 10"*
- **Bonus mults SUM, and the sum IS the multiplier** — not `1 + Σ`. A talent match and a hat match
  each contribute their own tunable; a mark effect saying "×2" contributes **+2**, so two of them
  make **×4** (`Q105`=(b), `Q122`, owner: *"ideally two x2 should be a x4. +2 to mult, do not
  multiply 0 ever similar to current overall scoring system."*).
- ⚠ **`M == 0` NEVER MULTIPLIES.** It is skipped, exactly as a bucket worth 0 is excluded from the
  grid product rather than zeroing it (`ARCHITECTURE_REVIEW.md` §3a). A mult of **1 is therefore
  neutral**, which is worth knowing when tuning: the useful range starts at 2.
- **Bonuses are gathered from `result.meld`, AFTER `score_line`'s re-evaluation** — only cards in
  the meld pay (`Q25`, owner: *"only cards part of a meld can score their meld bonuses."*), and the
  meld's membership can change during the spotlight cascade (`Levels/game.gd:955`).
- **Once per LINE the card scores in** (`Q23`=(a)) — which falls out for free, because the bonus is
  computed inside the line's own number.
- **A match registers NO combo class** (`Q76`=(c)).
- The composed number then goes through `Game.add_line_score` unchanged. **Bucketing, the grid
  product and the display-time combo are untouched** (`Q106`=(a)).

### 1.6 The suit rule ⚑ A SHIPPED RULE RETIRES HERE

*Authorised by `Q103` (⚑gate ⚑contract) and its note, with `Q87` and `Q30`=(b).*

```
A card's suit effect fires  ⇔  its cell's mark agrees on SUIT
```

`Q87` (owner): *"the suit pip effect itself is suppressed unless on top of a matching suit mark. if
it matches, effect triggers normally."*

- ⚠ **RETIRED: "a talented card suppresses its own suit effect"** (`ARCHITECTURE_REVIEW.md` §4). A
  suit match fires the effect regardless of talent (`Q30`=(b)), and without a match nothing fires at
  all. `Q103`'s note is the governing statement: *"different effects/marks being hit shouldnt be
  some sort of blocker for other marks being hit … hitting talent mark triggers effects based on
  talent, and hitting suit mark triggers effects based on the suit."*
- **"Triggers normally" means exactly where it fires today** — once per meld membership, through
  `Game._run_score_effects` and the existing prop simulation (§4, pre-authorised).
- **A mark never spawns props of its own accord** (`Q55`=(a)).

### 1.7 Marks that act

*Authorised by `Q50` (⚑contract, exactly two levels) and `Q111` (⚑contract, the names).*

Two hooks, duck-typed like every other (`ARCHITECTURE_REVIEW.md` §1.4), dispatched on the **mark's
own copied modifiers** (`Q49`=(a)) — never through `run_all_mods`. `Q46`, verbatim: *"both hooks for now, but mark is a bad name for this."*;
`Q111` supersedes that objection and fixes the names below:

```gdscript
## A card was placed on this marked cell, matching or not (Q46, Q51=a).
func on_mark_covered(card: CardData, coord: BoardCoord, level: int) -> void
## A card was placed on this marked cell and MATCHED it. Dispatched to BOTH the mark's modifiers
## and the placed CARD's, so an effect can require its own mark (Q47=a).
func on_mark_hit(card: CardData, coord: BoardCoord, matched: int, level: int) -> void
```

- **`level` is 0 or 1 and nothing else** — normal, and the realized form. Exactly two levels ever
  (`Q50`=(c)). A talent match fires the skill's own level-1 form (`Q33`=(b)) and additionally pays
  the flat mult (`Q35`, verbatim: *"flat mult bonus always, even for effects that have upgraded form."*).
- **Fires for as long as a card sits on the mark** — every time a line through the cell scores
  (`Q52`=(b)).
- **A mark firing IS a combo class** (`Q54`=(a)) and **counts as processing**, advancing the
  compression ramp and charging the runaway cap when it repeats (`Q57`=(a),
  `Game.note_processing`).
- **A mark's ×2 multiplies the whole line, every time that line scores** (`Q48`=(b), `Q107`=(a)) —
  contributing `+2` to `M` per §1.5.
- **A level or blind may grant a mark of a card outside the deck** (`Q53`=(a)); it sets
  `TypeGridCell.granted`.
- **Effects may reroll one cell, swap two marks, or re-deal a line** (`QR5`=(c)).

### 1.8 Marks against the engine

| Rule | Node |
|---|---|
| stage stays `CardData.Stage.ZONE` | `Q58`=(a) |
| **a mark is NEVER spotlit**, covered or not — `CardModifier.is_spotlit()` returns false for a marked cell type | `Q59`=(a) |
| a mark blocks nothing — `blocks_spotlight()` is false for it | `Q60`=(a) |
| a mark is never in a `ScoringSection`, so the beam never reaches it | `Q56`=(a) |
| a mark completes no line and scores nothing | `QR2`=(a) |
| the Entrance carries no marks | `QR6`=(a) |
| undo restores the mark and un-banks what it paid, for free | `Q62`=(a) |

⚠ **`Q59` IS LOAD-BEARING AND IT IS NOT OPTIONAL.** `is_spotlit()` returns true today for an
uncovered `Stage.ZONE` card, so without an explicit exclusion a mark's copied skill would answer
every broadcast hook on the board. The exclusion tests the mark predicate of §1.1.

### 1.9 The new invariant

In `GameData.validate()`, alongside I1–I5 (`Q61`=(b), `Q121`=(a)):

```
I6: every marked cell's zone card prints a rank or a suit
I6: every mark with `granted == false` names a card printed by some card in the deck
    (a `granted` mark is EXEMPT — that is what the flag is for)
```

### 1.10 Presentation

| Rule | Node |
|---|---|
| an empty cell draws its mark inside the existing empty-cell frame, **grey and faded like a ghostly outline**, and need not sit exactly in the palette. `Q112` verbatim: *"all four. should be same size as a normal card."* | `Q63`=(d), `Q112` |
| all four printed properties are drawn, per that same `Q112` note | `Q112`, `Q4`=(b) |
| a covered mark is available on **inspection**, and through the layer view | `Q19` |
| the **layer view** is a **two-state toggle** — the played board, or the marks — with no notion of stack depth | `Q113`=(b) |
| it is a **viewer**: input is locked to looking | `Q115`=(a) |
| it works **focused AND in the overview** | `Q116`=(b) |
| opened by a **held shoulder button AND a HUD control** every input mode reaches | `Q117`=(c) |
| holding a card **highlights every cell it would match** | `Q66`=(a) |
| `Q67` verbatim: *"each art in card has an outline already, selection takes over the outline to show which ones match"* | `Q67` |
| `Q68` verbatim: *"each partial art has its own outline that highlights"* | `Q68` |
| on landing, `Q64` verbatim: *"activated art gets special outline, pips get their outline replaced with a different version to indicate activated"* — no popup, no card-level alert | `Q64` |
| a card matching nothing says **nothing** | `Q65`=(a) |
| the plan is **revealed cell by cell** at show start, slot-machine | `Q69`=(a) |
| **no** HUD progress count, **no** destination on an Entrance card, deck viewer **unchanged** | `Q72`=(c), `Q70`, `Q73`=(a) |
| colour alone is acceptable for these states | `Q71`=(b) |
| no tutorial | `Q74`=(a) |

⚠ **`modulate` IS NOT AVAILABLE for the grey.** It is the focus highlight (`Cards/card_visual.gd:117`)
and it propagates to direct `CanvasItem` children, so it would tint the real card stacked on the
mark (`DESIGN.md` §1c, §1m). Use the palette and the outline shader's three override layers
(`ARCHITECTURE_REVIEW.md` §4i, §4j).

### 1.11 Naming

*Authorised by `QR7` (⚑contract) and `Q111` (⚑contract).*

The word is **mark**, player-facing and in code. `QR7`, verbatim: *"the composition mark hitting the mark (didnt know hitting the mark was official term, so am okay with mark terminology now)"*. `Q111`, verbatim:
*"mark is fine, i found out after i made that comment that mark is official terminology for stage choreography since thats what they call marks on the floor on_mark_hit would be fine"*. ⚠ **"ghost" is forbidden** — `Ghost Light` is already a stamp. Every identifier is
fixed in `NAMES.md`.

```
mark          the mechanic, the noun, and the code word
on_mark_hit   the match hook
ghost         FORBIDDEN - Ghost Light is already a stamp
blocking      rejected - collides with blocks_spotlight
```

### 1.12 Tunables

All in `Scripts/player_settings.gd`, `@export_group("Balance — board plan")`, read live through
`SettingsManager.settings`. Durations are fractions of `get_delay()`, never wall-clock.

| Knob | Start | Meaning |
|---|---|---|
| `plan_rank_match_step` | `1.0` | rank match pays `rank × this`, rounded up |
| `plan_rank_flat_fallback` | `10` | a rank with no integer value pays this |
| `plan_ace_value` | `10` | the Ace's value as a rank bonus |
| `plan_talent_mult` | `1.0` | a talent match's contribution to `M` (⚠ 1 is neutral — see §1.5) |
| `plan_hat_mult` | `1.0` | a hat match's contribution to `M` |
| `plan_reveal_fraction` | `0.5` | one cell's share of the opening deal, as a fraction of `get_delay()` |

⚠ **Derived, never registered:** how many marks a board carries (`grid_width × grid_height` per
grid), and how many per stock (`cells / stocks`). A stored count is a second representation of the
grid's own shape.

---

## 2. Node tree and module layout

**Nothing new hangs in the scene tree at the data layer.** The mark is data on a card that already
exists in `GridData.cell_types`, and it renders through the control `PlayArea._bind_stack()` already
binds it into (`UI/play_area.gd:1682`, `:2762`). That is the whole reason this design was shaped
this way and it is the single largest saving in the plan.

Two view-layer additions, and both are stated here rather than in a table cell because **where they
hang decides what they can see**:

| New thing | Hangs | Owns / outlives |
|---|---|---|
| the mark's grey rendering | **inside the existing cell-slot control**, as the binding of `cell_types[i]` that `_bind_stack` already performs | nothing new; it dies with the slot, and the slot is pooled and rebound, so **derive its look on bind and never cache it** (`ARCHITECTURE_REVIEW.md` — pooled per-slot controls) |
| the layer-view toggle | **`PlayArea`**, as a mode flag plus a HUD control | `PlayArea` itself; it is a rendering mode over the SAME controls, not a second board. It must survive a `flush_rebuild()` and it must be off when the board is rebuilt from a restored save |

⚠ **The layer view is a MODE, not a screen.** `Q115`=(a) makes it a viewer, so it does not need drop
targets, prop paths or animations to be correct at layer depth — it needs the existing controls
drawn differently and input refused. Building it as a second scene is the expensive wrong turn.

---

## 3. File map — one row per step

Function names are durable; line numbers are a starting point read at the time of writing and will
drift.

| Step | Files |
|---|---|
| S1 | `Cards/Types/type_grid_cell.gd` (add `granted`), `Scripts/grid_data.gd` (mark predicate helper) |
| S2 | `Scripts/game_data.gd` (`plan_seed`, `validate()` I6 at `:448`), `Cards/Skills/Rules/skill_board_planner.gd` (new) |
| S3 | `Decks/deck.gd` `_build_rules1()` (add the planner card), `Locale/localization.csv` |
| S4 | `Scripts/board_plan.gd` (new — the deal), `Scripts/card_effect_api.gd` (the accessors it needs) |
| S5 | `Scripts/mark_match.gd` (new — `matches_at`, the property enum, the two bonus terms), `Cards/card_modifier.gd` (the leniency hook comment block) |
| S6 | `Levels/game.gd` `score_line` (`:955`), `add_line_score` (`:1074`) — composition only |
| S7 | `Levels/game.gd` `_run_score_effects` (`:1137`), `Cards/Pips/pip_suit.gd`, `Cards/Props/Mods/prop_score_talents.gd` |
| S8 | `Cards/card_modifier.gd` `is_spotlit()` / `blocks_spotlight()` |
| S9 | `Levels/game.gd` `place_card_in_grid` (`:726`) — the two hook dispatches |
| S10 | `Scripts/card_effect_api.gd` (reroll / grant surface) |
| S11 | `Cards/card_visual.gd`, `Shaders/Styles/outline_default.tres`, `UI/play_area.gd` `_bind_stack` |
| S12 | `UI/play_area.gd` (highlight while holding), `Cards/card_outline.gd` |
| S13 | `UI/play_area.gd` (layer mode), `Levels/game_view.gd` (the HUD control), `Scripts/input_map` action |
| S14 | `Scripts/player_settings.gd` (`Balance — board plan` group) |
| S15 | `Tools/scoring_sim.py`, `Scripts/run_manager.gd` (`goal_for` constants) |
| S16 | `ARCHITECTURE_REVIEW.md` §3a/§3d/§4, `START_HERE.md`, `todo.md`, `solatro/design/poker-patience/gaps/GAP-041.md` |

---

## 4. Decisions already made, so you do not have to

The gap rehearsal ran over the whole design. These are pre-authorised: **do them, do not ask.**

| # | Decision | Because |
|---|---|---|
| 1 | Cells that do not divide evenly by the stock count deal **round-robin left to right**, earlier stocks taking the extras | mirrors `sidebar Q201`=(a); invisible in the product |
| 2 | A stock with fewer cards than its share contributes what it has; the round-robin continues past it | the only behaviour that terminates |
| 3 | `plan_seed` = the run's own seed combined with the map node id | `Q8`=(a) wants "a re-entered show is the same show"; the map regenerates per run, so node id alone is not stable across runs |
| 4 | The opening reveal walks **the shuffled deal order**, not row-major | it is what actually happened, and it makes the randomness legible |
| 5 | The reveal is a no-op when `view == null` | project rule: every effect runs headless |
| 6 | `matches_at` is **derived on every call with no cache** | a modifier changing a card's suit emits `data_changed`, not a `revision` bump, so a revision-keyed cache answers stale — and `Q13`=(b) requires the match to be live |
| 7 | "Triggers normally" in `Q87` means **once per meld membership**, exactly where suit effects fire today | `Q29` was gated on `Q28`=(a\|b\|c) and never asked; the owner's own word settles it |
| 8 | Bonuses are gathered from `result.meld`, not `section.cards` | `Q25`: only cards part of a meld pay, and the section is a superset |
| 9 | The leniency hooks mirror `PipComparator`'s deny/allow shape exactly | `Q41`=(a) says "in the shape §1j requires" |
| 10 | The `level` argument is an `int` on the hook, not a separate method name | one seam serves `Q33`=(b), `Q50`=(c) and any later upgrade |
| 11 | `on_mark_covered` fires for the cover hook on **every** re-score too, matching `Q52`=(b) | `Q52` did not distinguish the two hooks; treating them the same is the only reading that is not arbitrary |
| 12 | A save written before this feature resumes as a **plan-less board** and plays exactly as today | `DESIGN.md` §20 left it to implementation; a wipe would destroy runs in flight |
| 13 | The realized-match state is **not persisted**, because it does not exist | §1.1 |
| 14 | A realized cell in the marks layer draws its mark **plus the activated outline** of `Q64` | consistent with `Q19`'s "viewable even when everything is covered" |
| 15 | The mark's grey is a **palette role plus an outline override**, never `modulate` | §1.10 |
| 16 | `TypeGridCell.combo_key()` stays `""` — a mark's own COPIED modifier supplies the combo class, not the cell type | `Q54`=(a) wants the effect to count, not the furniture |
| 17 | The layer view closes itself on any board mutation | it is a viewer (`Q115`=(a)) and a board that changes underneath a frozen view is a bug factory |

**Expected gap count for this run: 0–3.** A run that files more than three has found a category the
rehearsal missed, and that is a defect in this section, not bad luck.

---

## 5. Phases

Steps within a phase are sequential unless marked parallel. **Phases 1–4 are pure logic with hard
gates. Phase 5 is visual and needs its own run at higher effort.**

### Phase 1 — the mark exists (implements `Q58`, `Q61`, `Q121`, `Q3`, `Q4`, `Q5`)

**S1 — the mark predicate.** *(implements A10, E1, E6, QR7, Q58, Q61, Q111, Q121)*  `TypeGridCell.granted`; the mark predicate as one named helper both `validate()` and
`is_spotlit()` call. **Done-when:** the predicate is called from at least those two sites.

**S2 — plan seed and invariant I6.** *(implements A12, E6, Q8, Q61, Q121)*  `GameData.plan_seed`; invariant I6 in `validate()`. **Done-when:** a hand-built state with a
mark of a card outside the deck fails I6, and the same state with `granted = true` passes.

**S3 — the planner rules card.** *(implements A1, A2, Q9)*  the planner rules card, added to `rules1` and localised. **Done-when:** a fresh show has one
`SkillBoardPlanner` in `state.rules_deck` and `run check`'s localisation gate is clean.

### Phase 2 — the deal (implements `QR1`=(e), `Q1`, `Q8`, `Q9`, `Q93`, `Q99`–`Q102`, `Q108`–`Q110`)

**S4 — the deal.** *(implements QR6, A3, A4, A5, A6, A7, A8, A9, A11, A13, A14, A15, A16, A17, QR1, Q1, Q2, Q3, Q4, Q5, Q6, Q9, Q10, Q11, Q12, Q93, Q96, Q99, Q100, Q101, Q102, Q108, Q109, Q110)*  `BoardPlan.deal()` per §1.2, driven from the planner's `on_game_start`, ordered after the
grid creators. **Done-when:** the acceptance gates in `TEST_PLAN.md` TP-01…TP-08 are green,
including the determinism gate.

### Phase 3 — matching and the economy

> `Q24`, verbatim: *"meld score should be a base. flush double can only multiply base value and should not have any insight to bonuses. take base meld score, then add additional rank bonuses, with any mult done after all flat bonuses have been added. all mult can be added together basically."*
>
> `Q36`, verbatim: *"flat mult bonus same as talent."*
 (implements `Q13`–`Q27`, `Q104`, `Q105`, `Q122`, `Q41`)

**S5 — the match test and the leniency family.** *(implements B2, B3, B4, B5, B6, B9, B10, B20, QR3, Q13, Q14, Q15, Q16, Q17, Q18, Q20, Q34, Q37, Q41, Q45)*  `matches_at` + the leniency hook family (declared as COMMENTS on `CardModifier`, never as
methods — a real no-op opts every modifier in, `ARCHITECTURE_REVIEW.md` §3c).

**S6 — the score composition.** *(implements C1, C4, C5, C6, C7, C8, C9, C13, B11, B12, B13, B14, B17, B18, B19, Q21, Q22, Q23, Q24, Q25, Q26, Q27, Q35, Q36, Q42, Q44, Q76, Q104, Q105, Q106, Q122)*  the composition in `score_line`, per §1.5. **Done-when:** TP-20…TP-27 green, and
`test_scoring.gd` SECTION 8's leaderboard is **byte-identical to before this branch** — that is the
gate proving `ScoreModel` was not touched.

### Phase 4 — the suit rule and marks that act (implements `Q87`, `Q30`, `Q28`, `Q46`–`Q57`, `Q59`, `Q60`)

**S7 — the suit rule.** *(implements B15, E9, D12, Q28, Q30, Q55, Q87, Q103)*  the suit rule of §1.6, and the retirement of the talent suppression.
**S8 — the spotlight exclusion.** *(implements E2, E3, E4, E5, QR2, Q56, Q59, Q60)*  `is_spotlit` / `blocks_spotlight` exclusion.
**S9 — the two hooks.** *(implements D2, D3, D4, D5, D6, D7, D8, D9, QR4, Q33, Q46, Q47, Q48, Q49, Q50, Q51, Q52, Q54, Q57, Q62, Q107)*  the two hooks dispatched from `place_card_in_grid`.
**S10 — the reroll and grant surface.** *(implements D10, D11, QR5, Q53, Q121)*  the reroll and grant surface on `CardEffectApi`.

**Done-when (phase):** TP-30…TP-45 green, and the FULL suite is green — this phase changes a shipped
rule, so `test_suit_props.gd` and `test_spotlight.gd` are expected to need re-derivation, and each
re-derived assertion must be shown red-then-green.

### Phase 5 — presentation (implements `Q63`–`Q74`, `Q112`, `Q113`, `Q115`–`Q117`, `Q19`)

**S11 — the mark's look.** *(implements F1, F2, F3, Q19, Q63, Q69, Q71, Q112)* the mark's look.

**S12 — the match highlight and landing feedback.** *(implements F9, F10, F11, F12, F13, F14, F15, F16, Q64, Q65, Q66, Q67, Q68, Q70, Q72, Q73, Q74)* the match highlight and the landing feedback.

**S13 — the layer view.** *(implements F4, F5, F6, F7, F8, Q19, Q113, Q115, Q116, Q117)* the layer view.

**S14 — the knobs.** *(implements §1.12)* the knobs.

⚠ **Every step here ends in `/fx-verify`.** No green test is evidence about pixels; render, look at
the image, describe what it shows, or say UNVERIFIED.

### Phase 6 — the curve (implements `Q75`=(a), `Q120`=(c))

**S15 — the curve refit.** *(implements Q75, Q120)*  extend `Tools/scoring_sim.py` to model marks and matches; refit `goal_g0` / `goal_alpha`;
**close `GAP-041` with the result.** ⚠ The gap belongs to `poker-patience`, so closing it is a new
design version there with a `resolution:` block — **not an edit to the gap file in place.**

**S16 — the docs pass.** *(implements Q77, Q80, Q81, Q82)*  the docs pass: `ARCHITECTURE_REVIEW.md` §3a (the composition), §3d (unchanged, confirm),
§4 (the retired suppression), `START_HERE.md`, `todo.md`. Then `py ../.claude/tools/doc_check.py`.

### Phase 7 — closing (ALWAYS LAST, never skipped)

**S17 — the closing sequence.** *(implements F16, E10, E11)*  Run the closing sequence in `/plan-run` in order, dispatching the reading work to
subagents one at a time. The adversarial review MUST run on a model that did not implement.

**Done-when (phase):** every numbered item in that sequence has run and its output is recorded in
the handoff; `doc_check.py` is clean on a FULL run; no reviewer finding is left unreproduced.

---

## 6. Anti-scope — do NOT do these, however tempting

- **Do not touch `Scoring.ScoreModel`.** §1.5. If a hand's score changes, you have a bug.
- **Do not add a realized-match ledger, a progress counter, or a HUD figure.** §1.1, `Q72`=(c).
- **Do not add a board bonus, a line bonus or a full-match bonus.** `Q17`=(b), `Q42`=(b), `Q44`=(b).
- **Do not make marks score, complete lines, or take the spotlight beam.** `QR2`=(a), `Q56`=(a).
- **Do not mark the Entrance.** `QR6`=(a).
- **Do not change how cards are drawn, or reorder the draw deck toward the plan.** `Q79`, verbatim:
  *"out of scope, already in the sidebar design plan which will run first"*
- **Do not show a card's destination anywhere.** `Q70`: *"no idea what you mean by fate. matching
  properties gets highlighted and thats it"*.
- **Do not change the deck viewer.** `Q73`=(a).
- **Do not change `GridData`'s size or shape.** `Q78`, verbatim: *"sure you can add tests that test non square grids, like adding 1 extra cell at every 5x5 edge one by one at random locations. new cells should randomly choose new mark from deck that hasnt been used as a mark yet, evenly distributed across stocks too."*
- **Do not build a tutorial or a first-run prompt.** `Q74`=(a).
- **Do not build a plan-saving card.** `Q81`, verbatim: *"a possible future card that saves what you actually played that game on the board as new plan"* — recorded for later, not built here.
- **Do not use `modulate` for the mark.** §1.10.
- **Do not "improve" a name from `NAMES.md`.**

---

## 7. Dependency order

```
S1 → S2 → S3 → S4        Phases 1–2, strictly sequential
S5 → S6                  Phase 3, needs S4 for fixtures
S7, S8, S10  parallel    Phase 4, after S6
S9                       after S8 (the spotlight exclusion must exist before hooks dispatch)
S11, S12, S13 parallel   Phase 5, after S9
S14                      any time after S6
S15 → S16                Phase 6, after Phase 4
S17                      last
```
