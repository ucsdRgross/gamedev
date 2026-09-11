# The board plan — the identifier registry

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/board-plan/DESIGN.md`, version 1, confirmed after round 4. Every step
in `PLAN.md` cites the design node IDs it implements.

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

**Use these exactly. Do not rename, do not "improve", do not shorten.**

## The word

**`mark`** is the word, player-facing and in code (`QR7`, owner: *"the composition mark hitting the
mark (didnt know hitting the mark was official term, so am okay with mark terminology now)"*, and
`Q111`: *"mark is fine … on_mark_hit would be fine"*).

⚠ **"ghost" is FORBIDDEN.** `Ghost Light` is already a stamp that does not block the spotlight.
⚠ "blocking", "rehearsal" and "running order" were considered and rejected (`QR7` (b)(c)(d)).

## Classes and files

| Name | File | What |
|---|---|---|
| `BoardPlan` | `Scripts/board_plan.gd` | static; owns `deal()` and nothing else |
| `MarkMatch` | `Scripts/mark_match.gd` | static; owns `matches_at()` and the property enum |
| `SkillBoardPlanner` | `Cards/Skills/Rules/skill_board_planner.gd` | the rules-deck card whose `on_game_start` calls `BoardPlan.deal()` |
| `TestBoardPlan` | `Tests/Engine/test_board_plan.gd` | suite name `BOARD PLAN` |
| `TestMarkMatch` | `Tests/Engine/test_mark_match.gd` | suite name `MARK MATCH` |
| `TestPlanVisuals` | `Tests/UI/test_plan_visuals.gd` | suite name `PLAN VISUALS` |

## Methods and signatures

```gdscript
# Scripts/board_plan.gd
static func deal(state: GameData, rng: RandomNumberGenerator) -> void
static func write_mark(type_card: CardData, source: CardData, granted: bool) -> void
static func clear_mark(type_card: CardData) -> void
static func is_marked(type_card: CardData) -> bool      # THE predicate; validate() and is_spotlit() both call it

# Scripts/mark_match.gd
enum Property { RANK = 1, SUIT = 2, TALENT = 4, HAT = 8 }
static func matches_at(state: GameData, card: CardData, coord: BoardCoord) -> int   # bit mask of Property
static func flat_bonus(card: CardData, matched: int) -> int      # the rank term of PLAN §1.5
static func mult_bonus(card: CardData, matched: int) -> float    # the talent + hat terms

# Cards/Types/type_grid_cell.gd
@export_storage var granted : bool = false

# Scripts/game_data.gd
@export_storage var plan_seed : int = 0
```

## Hooks

Duck-typed, dispatched on the mark's own copied modifiers and (for `on_mark_hit`) the placed card's.
`Q111`'s answer kept the word **mark** for both: `on_mark_hit` for a match, and its sibling for a
plain cover.

```gdscript
func on_mark_covered(card: CardData, coord: BoardCoord, level: int) -> void
func on_mark_hit(card: CardData, coord: BoardCoord, matched: int, level: int) -> void
```

The leniency family, declared as **COMMENTS** on `CardModifier` (never as methods —
`ARCHITECTURE_REVIEW.md` §3c), mirroring `PipComparator`'s deny/allow shape:

```gdscript
func on_mark_ranks_deny(r1: PipRank, r2: PipRank) -> bool
func on_mark_ranks_allow(r1: PipRank, r2: PipRank) -> bool
func on_mark_suits_deny(s1: PipSuit, s2: PipSuit) -> bool
func on_mark_suits_allow(s1: PipSuit, s2: PipSuit) -> bool
```

Spelling constants live once, as `MarkMatch.MARK_RANKS_DENY` and siblings. **Never retype a
StringName at a call site** — a typo silently disables the mechanic.

## Settings keys

`Scripts/player_settings.gd`, `@export_group("Balance — board plan")`:

`plan_rank_match_step` · `plan_rank_flat_fallback` · `plan_ace_value` · `plan_talent_mult` ·
`plan_hat_mult` · `plan_reveal_fraction`

## CardEffectApi additions

```gdscript
func mark_at(coord: BoardCoord) -> CardData          # the cell type card, or null
func reroll_mark(coord: BoardCoord) -> void          # QR5=c
func grant_mark(coord: BoardCoord, source: CardData) -> void   # Q53=a; sets granted
func swap_marks(a: BoardCoord, b: BoardCoord) -> void          # QR5=c
```

## Localisation keys

`Locale/localization.csv`:

`BOARD_PLANNER_CARD` · `BOARD_PLANNER_CARD_DESCRIPTION` · `PLAN_LAYER_TOGGLE` ·
`PLAN_LAYER_TOGGLE_HINT` · `GRID_CELL_CARD_MARKED_DESCRIPTION`

⚠ **No user-facing string is ever a literal** (`START_HERE.md` rule 4).

## InputMap action

`ui_plan_layer` — held to peek, and bound for keyboard, mouse and controller alike (`Q117`=(c)).

## Palette roles

`Scripts/palette_roles.gd`, named for MEANING and never for colour:

`mark_ink` — the mark's faded body · `mark_rim` — its outline · `match_rim` — the outline an element
takes while it matches · `match_rim_active` — the realized form of `Q64`

## Test ids

`TP-NN` throughout `TEST_PLAN.md`. Suite banners: `BOARD PLAN`, `MARK MATCH`, `PLAN VISUALS`.

## Design ids stay OUT of the code

⚠ `Q122`, `QR1=e`, `GAP-041` and every other design id belong in **this plan**, never in a comment,
a doc comment or an `@export_group` label. The code gets the RULE the answer produced. See
`.claude/memory/design-ids-stay-out-of-code.md`; `doc_check.py` enforces it.
