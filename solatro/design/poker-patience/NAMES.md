# Poker Patience — the identifier registry

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/poker-patience/DESIGN.md`, version 2, charts confirmed 2026-08-25.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent → do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise → **park that thread, file a gap, keep working on unaffected threads, tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.
4. ⚠ Two documents disagreeing is NOT automatically (3) — read the answer they are both restating.

File gaps at `solatro/design/poker-patience/gaps/GAP-NNN.md`. Do not resolve a gap by picking an
answer. Do not delete a gap.

This block, unchanged, goes into every document derived from this one.

---

## 0. The rule

**Use these names exactly. Do not rename, do not shorten, do not "improve".** If you need a name
this registry does not fix, that is a plan defect: **stop and report `blocked`**. Two sessions
inventing two names for one thing is the most common way work fails to compose.

⚠ **No design id ever appears in code** — not in a comment, not in a doc comment, not in an
`@export_group` label (Godot renders the last two as Inspector UI). The code gets the RULE; the
plan carries the citation.

---

## 1. Core types and coordinates

| Name | Kind | Notes |
|---|---|---|
| `BoardCoord` | `class_name`, RefCounted | The four-component coordinate: `grid, x, y, h`. Replaces the `Vector3i` convention on the board. |
| `BoardCoord.grid` | `int` | Grid index, left to right. |
| `BoardCoord.x` | `int` | Column, 0-based, left to right. **Continuous across grids.** |
| `BoardCoord.y` | `int` | Row, 0-based, top to bottom. **`-1` is the Entrance.** |
| `BoardCoord.h` | `int` | Height in the stack, **0-based**. |
| `BoardCoord.NOWHERE` | `const` | The off-board sentinel. **Never `(0,0,0,0)`.** |
| `BoardCoord.ENTRANCE_ROW` | `const int = -1` | Named, never typed as a literal `-1`. |
| `BoardCoord.step(dx, dy, grid_widths)` | method | Two-axis movement over an unbounded lattice of per-grid blocks. Never clamps, never returns `NOWHERE`; whether a cell EXISTS at the result is `GameData.has_cell`, asked at landing. |
| `BoardCoord.is_entrance()` | method | `y == ENTRANCE_ROW`. |

## 2. GameData

| Name | Kind | Notes |
|---|---|---|
| `GameData.grids` | `Array[GridData]` | The grid list, left to right. `@export_storage`. |
| `GridData` | `class_name`, Resource | One grid: its size and its cells. |
| `GridData.grid_width` | `int`, default 5 | Per grid, not global. |
| `GridData.grid_height` | `int`, default 5 | Per grid, not global. |
| `GridData.cells` | `Array[ArrayCardData]` | Row-major, one entry per cell; each holds that cell's stack bottom-to-top. |
| `GridData.cell_types` | `Array[CardData]` | The 25 cell zone cards, row-major. |
| `GameData.committed_grid` | `int`, default `-1` | Which grid the Entrance is committed to; `-1` = uncommitted. `@export_storage` so undo rewinds it. |
| `GameData.scores_row` | `Array[BigNumber]` per grid | Height-0 row buckets. |
| `GameData.scores_col` | `Array[BigNumber]` per grid | Height-0 column buckets. |
| `GameData.scores_row_h` | 2-D, `[index][height]` | Raised-level row buckets. |
| `GameData.scores_col_h` | 2-D, `[index][height]` | Raised-level column buckets. |
| `GameData.score_special` | `BigNumber` per grid | **One** bucket for every diagonal and every future special meld. |
| `GameData.packed_*` | packed arrays | One pair per container above, mirroring the existing `pack_scores`/`unpack_scores` contract. |
| `GameData.grid_score(grid)` | method | Product of the buckets whose value is `> 0`; `0` when none is. |
| `GameData.board_total()` | method | Sum of `grid_score` over grids. |
| `GameData.live_total()` | method | `board_total() * combo_mult()`, as an int. **The show's score**: what the goal is measured against and what fame banks. Derived on demand -- there is no banking moment and no stored total. |
| `GameData.position_of(card)` | method | Existing name, now returning `BoardCoord`. |
| `GameData.card_at(coord)` | method | The reverse index. |
| `RunState.pending_placement_slot` | `int`, default `-1` | Which Entrance SLOT the pending placement took its card from. A placement is identified by slot, never by card: the pre-placement board a replay starts from is a restored snapshot carrying its own copies. |
| `RunState.pending_placement_coord` | `Vector4i` | Where that placement was aimed, as `(grid, x, y, h)`. |

## 3. Board

| Name | Kind | Notes |
|---|---|---|
| `Board.place_in_cell(state, card, coord)` | static | Place a card not on the board into a cell. |
| `Board.move_to_cell(state, card, coord, is_compaction)` | static | ⚠ `is_compaction` is **explicit**, never inferred. |
| `Board.remove_from_cell(state, card)` | static | Removes and compacts the cards above; bumps `revision` **once**. |
| `Board.add_grid(state, grid)` | static | Header + cells in lockstep, mirroring `add_column`. |
| `Board.remove_grid(state, index)` | static | Returns the orphaned cards for the caller to discard. |

## 4. Line detection and scoring

| Name | Kind | Notes |
|---|---|---|
| `LineKind` | enum on `ScoringSection` | `ROW`, `COL`, `DIAG`, `HEIGHT_V`. |
| `ScoringSection.kind` | `LineKind` | |
| `ScoringSection.line_key` | `StringName` | Opaque; the bucket is derived from it. **`score_line` never branches on shape.** |
| `ScoringSection.of_line_at(grid, kind, index, height)` | static | Replaces `of_line`. |
| `Game.score_line(result, section)` | method | ⚠ New signature. `is_row`, `zone` and `index` are **gone**. |
| `Game.add_line_score(section, amount)` | method | The single write path, unchanged in role. |
| `&"on_board_mutated"` | hook `StringName` | Fired after every board mutation; carries the coord and the compaction flag. |
| `&"on_card_placed"` | hook `StringName` | Fired after an arrival specifically. |
| `SkillLineDetector` | `class_name` | The detector rules card. Frame **9**. |
| `SkillEvalPokerLine` | `class_name` | Replaces `SkillEvalPokerBest`. Frame **10**. |

## 5. Rules cards

| Name | Kind | Frame | Notes |
|---|---|---|---|
| `SkillGridAllotment` | `class_name` | 11 | The meta card: counts the deck, adds/subtracts creator cards. |
| `SkillGridCreator` | `class_name` | 12 | `ZoneAdder`-shaped; builds and removes one 5×5 grid. |
| `TypeGridCell` | `class_name` | 13 | The per-cell zone card. |
| `SkillAdderInputUpper` | existing | 3 | **Unchanged.** Five of them make the Entrance five wide. |
| `TypeInput` | existing | 2 | **Unchanged except `on_next` is removed.** |

⚠ **There is no archive.** `SkillGrabberOgLower`, `SkillPlacerOgLower`,
`SkillScorerCascadeLower`, `SkillAdderInputLower` and `SkillEvalPokerBest` are simply **absent
from `rules1`**. Their scripts stay where they are and stay constructible; there is no
`Cards/Skills/Rules/Archive/` directory and no `Deck.archive_rules1`.

`rules1` is now: 5 x `SkillAdderInputUpper`, 1 x `SkillGridAllotment`, 1 x `SkillLineDetector`.
`TestDecks.standard_rules` is a frozen mirror of that composition and
`TestDecks.rules_skill_names` is what compares the two.

⚠ **Frames 9–13 are claimed here.** `Assets/skill_art.png` is 16×16 = 256 frames; 0–8 were in use.
Do not pick a frame that is not in this table.

## 6. Settings knobs

All on `Scripts/player_settings.gd`, read via `SettingsManager.settings`.

| Name | Default | Notes |
|---|---|---|
| `grid_cards_per_unlock` | `52` | |
| `grid_max_count` | `3` | |
| `grid_buffer_px` | `220.0` | Centring is fixed; the gap is a knob. |
| `grid_pan_duration` | `0.35` | |
| `grid_overview_margin` | `0.06` | |
| `grid_swipe_threshold_mm` | `8.0` | Converted through `WallInput.mm_to_px`, clamped. |
| `grid_align_rows_globally` | `false` | Per-grid sizing is the default. |
| `stack_offset_px` | `= card_separation_play_custom` | |
| `stack_soft_cap` | `20` | `push_error` past it; not a hard limit. |
| `stack_spring_rise` | `= card_jump_rise_play` | |
| `combo_unique_step` | `1.0` | |
| `combo_repeat_step` | `0.5` | |
| `combo_cap` | `0.0` (off) | |
| `game_picture_max_render_px` | `4096` | The render-target clamp. |

**Removed:** `score_additive`, `duplicate_class_scale`, `patience_max`,
`patience_track_uniques`, `patience_reset_uniques_on_act`, `multi_line_reveal_scale`
(never added — see `DESIGN.md` §24).

## 7. InputMap actions

Each needs **both** a reader and a binding, keyboard **and** joypad.

| Action | Keyboard | Joypad | Means |
|---|---|---|---|
| `grid_pan_left` | `,` | L2 | Pan one grid left |
| `grid_pan_right` | `.` | R2 | Pan one grid right |
| `grid_zoom_out` | — | — | ⚠ **Not a new action.** Intercepts `wall_back`. |
| `grid_zoom_in` | — | — | ⚠ **Not a new action.** Intercepts `wall_forward` / click. |

⚠ `wall_back` / `wall_forward` (`[`/L1, `]`/R1) keep their existing bindings and still reach the
wall. Do **not** rebind them.

## 8. Localisation keys

`Locale/localization.csv`, `<THING>` / `<THING>_DESCRIPTION` pairs as every card uses.

| Key |
|---|
| `LINE_DETECTOR_CARD` / `_DESCRIPTION` |
| `EVAL_POKER_LINE_CARD` / `_DESCRIPTION` |
| `GRID_ALLOTMENT_CARD` / `_DESCRIPTION` |
| `GRID_CREATOR_CARD` / `_DESCRIPTION` |
| `GRID_CELL_CARD` / `_DESCRIPTION` |
| `END_SHOW_BUTTON` | The End button's label; highlights when the goal is met. |
| `END_SHOW_CONFIRM` | Shown when ending below the goal. |

⚠ `SkillEvalPokerBest` and `SkillScorerCascadeLower` currently return **bare literals** from
`get_str()`. Those are being archived, so they are not fixed — but **every new card goes through
`TRANSLATION.find`.**

## 9. Test suites and fixtures

| Name | Notes |
|---|---|
| `Tests/Engine/test_grid_board.gd` / `.tscn` | Phase 1 |
| `Tests/Engine/test_line_detect.gd` / `.tscn` | Phase 2 |
| `Tests/Engine/test_grid_economy.gd` / `.tscn` | Phase 3 |
| `Tests/Engine/test_grid_cards.gd` / `.tscn` | Phase 4 |
| `Tests/UI/test_grid_layout.gd` / `.tscn` | Phase 5 |
| `Tests/UI/test_grid_view.gd` / `.tscn` | Phase 6 |
| `Tests/Wall/test_wall_saved_pan.gd` / `.tscn` | Phase 7 |
| `Tests/Engine/test_grid_fuzz.gd` / `.tscn` | Fuzz |
| `TestGridFixtures.board_digest(state)` | The board as comparable text: every cell, the Entrance, deck and discard in order, every bucket. Backs the headless/viewed parity gate and the save round-trip. |
| `TestDecks.deck_standard_52` | `FIX-DECK-52`. **Frozen.** Never `Deck.deck4`. |
| `TestDecks.deck_20` | `FIX-DECK-20` |
| `TestDecks.deck_53` | `FIX-DECK-53` |
| `TestDecks.deck_105` | `FIX-DECK-105` |

Fixture builder names match the `FIX-*` ids in `TEST_PLAN.md` §1, lowercased with underscores —
`build_fix_full_15()`, `build_fix_cross()`, and so on.

## 10. Scene node names

| Path | Notes |
|---|---|
| `%GridContainer` | The board root inside `PlayArea`; hosts one child per grid. |
| `%GridPanel` | One per grid. ⚠ **Draws nothing** — `Q14`=(b), the gap defines a grid. It is a positioning node only. |
| `%SpecialScore` | The one special-meld label, right of the grid, aligned with its centre. |
| `%PanLeft` / `%PanRight` | The on-screen pan buttons; hidden at one grid. |
