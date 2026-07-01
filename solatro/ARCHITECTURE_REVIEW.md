# Solatro Architecture Review

Audit date: 2026-07-01. Scope: `Levels/game.gd`, `Scripts/` (card_data_iterator, game_data,
pip_comparator, card_environment, scoring, card_data_array, mods_list), `UI/play_area.gd`,
everything in `Cards/`, plus `Levels/main.gd` for context.

---

## 1. ARCHITECTURE OVERVIEW

### 1.1 The one-paragraph version

Solatro is a solitaire/Balatro hybrid. **All game state lives in plain `Resource` data
objects** (`GameData` holding arrays of `CardData`); **all game rules live in "modifier"
resources attached to cards** (skills/stamps/types) that are invoked by name via a global
broadcast system (`CardEnvironment.run_all_mods("on_xxx")`); **all visuals are rebuilt every
physics frame** from the data (`PlayArea` reconciles Control nodes + `CardVisual` sprites
against `GameData`). The engine itself (`game.gd`) contains almost no rules — even *scoring
and drawing cards* only happens because a rule-card in `rules_deck` implements `on_run_scorer`
/ `on_next`.

### 1.2 Class map

```
Main (Levels/main.gd, scene root)
 ├─ Menu / Map ................. scene switching, PlayerSave (static Main.save_info)
 └─ Game (Levels/game.gd) ...... extends CardEnvironment; the match controller
     │
     ├─ state : GameData ....... PURE DATA (Resource): draw/discard/rules decks,
     │                           upper/lower zones (columns of stacks), score arrays,
     │                           goal/total. Emits state_changed for the HUD.
     ├─ save_history ........... Array[GameData] deep copies -> undo
     └─ PlayArea (UI/play_area.gd, %PlayArea)
         ├─ builds a Control grid mirroring GameData zones (every physics tick)
         ├─ maps: ui_data (Control->CardData), data_ui, data_card (CardData->CardVisual)
         └─ CardVisual (Cards/card_visual.gd, Node2D)
             follows its anchor Control; tweens, float anim, stage-change animations

CardEnvironment (Scripts/card_environment.gd, @abstract, base of Game)
 ├─ static CURRENT ............. global "the active environment" singleton
 ├─ static run_all_mods(fn,...)  THE event bus: iterates every CardData in play,
 │                               calls fn on its type/stamp/skill if has_method(fn)
 ├─ return_first_*_result ...... same walk, but first non-empty answer wins
 └─ skill_active_check ......... toggles skill.active, fires on_active/on_deactive

CardDataIterator (Scripts/card_data_iterator.gd)
 └─ custom _iter_* class; flattens CardEnvironment.CURRENT.get_card_collections()
    (draw deck, both zones + zone-type rows, discard, rules) into one card stream.
    2D zones are walked ROW-major (row 0 of every column first).

CardData (Cards/card_data.gd, Resource) — one card
 ├─ suit : PipSuit            rank : PipRank        (the "pips")
 ├─ skill / type / stamp : CardModifier subclasses  (the behavior slots)
 ├─ stage : {PLAY, DRAW, DISCARD, RULES, ZONE, DATA} + previous_stage
 └─ signals data_changed / stage_changed -> CardVisual updates itself

CardModifier (@abstract Resource, back-reference .data -> owning CardData)
 ├─ CardModifierSkill  (active flag; is_active() = card is in rules deck OR has
 │   StampGlobal/StampRevealing)          e.g. SkillEvalPokerBest, SkillGrabberOgLower
 │   └─ ZoneAdder (@abstract)             adds a zone column while active
 ├─ CardModifierStamp                     e.g. StampDoubleTrigger, StampGlobal
 └─ CardModifierType                      e.g. TypeInput (draw/drop pipeline), TypeStone
     └─ BoosterTemplate (@abstract)       card-pack generation (map screen)

PipComparator (static) ... every rank/suit comparison funnels through here; each call
    first asks all mods (on_compare_ranks/suits) before falling back to numeric compare.
Scoring (Scripts/scoring.gd, static) ... poker-hand evaluation: PokerHands router ->
    ExpandedGridHandler (sets/houses), MultiStraightHandler, MultiFlushHandler,
    HighCardHandler; ScoreModel = the only place score math lives; Result = hand+score.
```

### 1.3 Key data flow traces

**Player clicks a card** (grab/place):
`PlayArea._on_gui_input` → `data_selected.emit(CardData)` → `Game.on_data_selected`
→ `return_first_data_array_result("on_can_grab_stack" / "on_can_place_stack")` —
i.e. the *rule cards* (e.g. `SkillGrabberOgLower`, `SkillPlacerOgLower`, `TypeInput`)
decide legality and return the stack → `Game.move_data_ontop_data` mutates
`GameData` arrays → fires `on_card_dropped_on` / `on_stack_cards` mods →
`Game.save_state()` snapshots for undo. Visuals catch up next physics tick.

**Player presses Submit**:
`Game._on_submit_pressed` → `run_all_mods("on_run_scorer")` → `SkillScorerCascadeLower`
(a rule card) walks lower-zone rows/cols → for each, `run_all_mods("on_score_row"/"on_score_col")`
→ `SkillEvalPokerBest` calls `Scoring.PokerHands.score(cards)` → best `Result` →
`Game.score_row/score_col` → `PlayArea.popup_meld / update_score / popup_score` animations.

**Player presses Next**:
`run_all_mods("on_next")` → `TypeInput.on_next` (per input-zone column): drops its upper
stack into the lower zone (`move_data_to_coord`), then `Game.draw_card()` refills.

**Undo**: every action ends in `save_state()` (full `GameData.duplicate_state()`).
Undo pops history, re-duplicates, reassigns `Game.state`; PlayArea rebuilds from scratch.

**Coordinates**: a card's location is a `Vector3i(x=0 upper/1 lower, y=column, z=row-in-stack)`;
`z == -1` means the zone/type header card. `find_data_vec3` / `find_vec3_data` /
`get_zone_from_vec3` translate between card refs and coords.

### 1.4 The extension contract (how you add a mechanic)

1. Subclass `CardModifierSkill/Stamp/Type`, implement `get_str/get_description/get_frame`.
2. Implement any hook: `on_next`, `on_run_scorer`, `on_can_grab_stack`,
   `on_can_place_stack`, `on_card_dropped_on`, `on_stack_cards`, `on_score_row`,
   `on_score_col`, `on_score`, `on_after_score`, `on_trigger`, `on_append`, `on_discard`,
   `on_game_start/end`, `on_compare_ranks/suits`, `on_anything`, `on_active/on_deactive`,
   `on_get_possible_*` (boosters). Dispatch is duck-typed via `has_method` — no interface
   enforces signatures, and there is NO single authoritative list (the comment block in
   `card_modifier.gd` is stale — many signatures there still say `Card`, a class that no
   longer exists).
3. Attach the modifier to a `CardData` in `rules_deck` (always active) or give the card
   `StampGlobal`/`StampRevealing` (see `CardModifier.is_active()`).

---

## 2. BUGS

### Confirmed

- [ ] **B1. Upper-zone row scores are written to the lower-zone score array.**
  [game.gd:260-262](Levels/game.gd:260) — `score_row` does
  `var score_zone := state.scores_row_lower; if zone == state.upper_zone: score_zone = state.scores_row_lower`.
  The `if` branch assigns the *same* array. Should be `state.scores_row_upper`.
  Consequence: `scores_row_upper` is never written; upper-zone scoring silently corrupts
  lower-row scores. Fix: assign `scores_row_upper` in the branch.

- [ ] **B2. Cards animate to the DISCARD pile when moved to the DRAW deck.**
  [card_visual.gd:206-209](Cards/card_visual.gd:206) — the `data.Stage.DRAW` case in
  `on_stage_changed` targets `discard_ui`. Copy-paste from the DISCARD case; should be
  `deck_ui`. (The `_ready` positioning above it, line 169-170, gets it right.)

- [ ] **B3. Dead code in `CardVisual.data` setter — stage animation never triggers from it.**
  [card_visual.gd:35-42](Cards/card_visual.gd:35) — after `data = value`, the guard
  `if data == value: return` is *always* true, so the `on_stage_changed()` call below is
  unreachable. Also line 41 tests `if is_node_ready and data:` — missing `()`, so it tests
  the Callable (always truthy) instead of calling it. Fix: decide the intended early-out
  (probably compare against the *old* value before assignment) and call `is_node_ready()`.

- [ ] **B4. `find_data_vec3` iterates the wrong array for the upper zone.**
  [game.gd:186](Levels/game.gd:186) — `for col : int in state.upper_zone_type.size():`
  then indexes `state.upper_zone[col]`. The lower-zone loop (line 190) correctly uses
  `state.lower_zone.size()`. If `upper_zone_type` and `upper_zone` ever disagree in length
  (e.g. mid `ZoneAdder.on_active`, which appends to the two arrays in separate statements),
  this indexes out of bounds. Fix: iterate `state.upper_zone.size()`.

- [ ] **B5. `find_data_vec3` returns float `Vector3`s from an `-> Vector3i` function.**
  [game.gd:183-193](Levels/game.gd:183) — four `return Vector3(...)` statements. Godot
  converts implicitly today, but it's a silent truncation hazard and a warning generator.
  Fix: `Vector3i(...)` everywhere.

- [ ] **B6. `ZoneAdder.on_deactive` can `remove_at(-1)`.**
  [zone_adder.gd:29-35](Cards/Skills/Rules/zone_adder.gd:29) — `find(card_data)` result is
  not checked; if the zone card was removed by anything else, `index == -1` →
  `remove_at(-1)` / `pop_at(-1)` removes the *last* (wrong) column, silently desyncing
  `zone_type` from `zone`. Fix: `if index == -1: return`.

- [ ] **B7. NAN comparisons make incomparable suits "different", enabling illegal stacks.**
  [skill_grabber_og_lower.gd:17](Cards/Skills/Rules/skill_grabber_og_lower.gd:17) and
  [skill_placer_og_lower.gd:17](Cards/Skills/Rules/skill_placer_og_lower.gd:17) —
  `PipComparator.compare_suits` returns `NAN` when suits aren't comparable, and
  `NAN != 0` is `true`, so the "different suit" half of the check passes for any
  non-standard suit pair. (`abs(NAN) == 1` is false so rank saves you today, but the same
  pattern applied to ranks/suits independently is a trap.) Fix: check `is_nan()` explicitly.

- [ ] **B8. `PlayArea.popup_score` can divide by zero.**
  [play_area.gd:363-371](UI/play_area.gd:363) — `meld_size` counts only meld cards present
  in `data_card`; if none are (cards just discarded/freed), `combo_pos /= 0` → NaN position.
  Fix: `if meld_size == 0: return`.

- [ ] **B9. `return_to_map` loses cards still on the board and doesn't await mods.**
  [game.gd:244-250](Levels/game.gd:244) — only `draw_deck + discard_deck` are saved back to
  `Main.save_info.card_datas`; any card still in `upper_zone`/`lower_zone` is permanently
  lost from the player's deck. Also `run_all_mods("on_game_end")` is not awaited, so mods
  that restore state on game end (e.g. `SkillHungryHippo.on_game_end` returns consumed
  cards) race the save. Fix: sweep zones into `draw_deck` first, and `await` the mods call.

- [ ] **B10. `run_all_mods` iterates live collections that mods mutate.**
  [card_environment.gd:30-44](Scripts/card_environment.gd:30) + CardDataIterator —
  the iterator keeps integer indices into `GameData`'s actual arrays; hooks like
  `on_next` (`TypeInput` moves/draws cards) and `on_discard` mutate those arrays
  mid-iteration → cards get skipped or visited twice, and out-of-range indices are
  possible. This is the most structural bug in the codebase. Fix: snapshot the card list
  before dispatch (`var all := []; for d in CardDataIterator.new(): all.append(d)`), or
  queue mutations until after the walk.

- [ ] **B11. Undo history: modifier back-references point at the wrong card copies.**
  [game_data.gd:38-43](Scripts/game_data.gd:38) — `duplicate(true)` deep-copies the
  `CardData`s and their sub-resources, but `Resource.duplicate` does **not** remap
  cross-references: each duplicated `CardModifier.data` (`@export_storage var data`) still
  points at the CardData instance from the *previous* state object (same for
  `ZoneAdder.card_data`, `SkillEchoingTrigger.triggered`, `SkillHungryHippo.consumed_cards`).
  After one undo, `data == self.data` checks and zone lookups in mods compare against stale
  objects. This is why `duplicate_big_number_array` already exists as a manual patch — the
  same problem applies to modifiers but is unpatched. Fix: after duplicating, walk every
  copied CardData and re-run `with_skill/with_type/with_stamp`-style rebinding
  (`copy.skill.data = copy` etc.), or write an explicit `CardData.clone()`.

### Suspicious — verify in-engine before fixing

- [ ] **S1. `Game.state` initializer + setter side effects.**
  [game.gd:11-15](Levels/game.gd:11) — in Godot 4 the declaration initializer invokes the
  setter, which calls `_on_state_changed()` → `%Goal/Label` before the node is in the tree.
  If you see `get_node: Node not found` errors at game start, this is why. Also: the setter
  never disconnects the old state's `state_changed`, and re-assigning the same GameData
  would double-connect. Fix: guard with `is_node_ready()`, disconnect old state.

- [ ] **S2. `find_vec3_data` uses `Array.get(index)` on possibly out-of-range indices.**
  [game.gd:196-201](Levels/game.gd:196) — the null-checks suggest an expectation that
  `.get()` returns null out-of-range; verify that's true on your Godot build (for
  `Dictionary` yes, for `Array` this has historically been an error). If it errors, both
  `find_vec3_data` and `is_data_topmost` (line 216) can crash on stale coords.

- [ ] **S3. `move_data_to_coord` same-column shift math.**
  [game.gd:142-156](Levels/game.gd:142) — the `z_dist`/`cards_in_stack` clamp (`= z_dist - 1`)
  and the later `dest.z -= cards_in_stack` compensation only trigger on
  `z_dist > -1`, but `z_dist == 0` (dropping onto own position) and negative-`z_dist`
  same-column moves take different paths. Worth unit-testing with: move down within column,
  move up within column, move onto self, move whole column (`cards_in_stack = -1`).

- [ ] **S4. `PlayArea.separation` typed `int`, getter returns a float product.**
  [play_area.gd:10-15](UI/play_area.gd:10) — `separation * SettingsManager.settings.card_scale`
  is a float if `card_scale` is; returning it from an `int` property either truncates or
  errors depending on strictness. Same pattern in `CardVisual.card_separation_play`.

- [ ] **S5. `update_card_zone_visuals` hard-indexes `data_card[connected_data]`.**
  [play_area.gd:208](UI/play_area.gd:208) — if a visual failed `is_instance_valid` during
  `set_card_zone` the key exists (recreated), but any path where visuals lag data by a frame
  (deferred `add_child` in `CardVisual.add_child_card_visual`) makes this a KeyError crash
  candidate. Use `.get()` with a null check.

- [ ] **S6. `CardData.stage` setter always overwrites `previous_stage`,** even when the new
  value equals the old ([card_data.gd:38-42](Cards/card_data.gd:38)). Re-setting the same
  stage erases the real previous stage and re-emits `stage_changed`. Guard with
  `if value == stage: return`.

- [ ] **S7. `ModsList.skills` holds shared singleton instances.**
  [mods_list.gd](Scripts/mods_list.gd) — `SkillExtraPoint.new()` etc. are single instances;
  `with_data()` mutates them. If any code assigns from this list to more than one card
  without `.duplicate()`, all those cards share one skill object (shared `active`,
  `triggered`, `data`). Verify every consumer duplicates.

---

## 3. STRUCTURAL / DESIGN IMPROVEMENTS (priority order)

- [ ] **D1. Give the mod-hook system a real contract.** One typo in a `StringName` silently
  disables a mechanic; signatures aren't checked; the only documentation is a stale comment
  block ([card_modifier.gd:28-97](Cards/card_modifier.gd:28) — delete or rewrite it, several
  signatures reference the removed `Card` class). Minimum: a single `const HOOKS` list +
  a doc comment per hook with its exact signature, used by every `run_all_mods` call site.
  Better: empty virtual methods on `CardModifier` (has_method always true, so add a
  companion `overrides(fn)` check, or accept the dispatch cost) so the editor checks
  signatures for you.

- [ ] **D2. Make state mutation go through one API.** Mods currently mutate `GameData`
  arrays directly (`TypeInput.draw_card` appends to `upper_zone[col].datas`,
  `ZoneAdder` appends to zone arrays). That bypasses `move_data_to_coord`'s bookkeeping and
  the `on_stack_cards` events, and is what makes B10 dangerous. Route all placement through
  `Game.move_*` / a new `Game.add_card_to_zone`, and make those functions defer-safe.

- [ ] **D3. Split `game.gd`'s responsibilities.** It is simultaneously: board mutation
  engine (`move_data_to_coord` family), match lifecycle (deck setup, undo, save), scoring
  presentation (`score_row/score_col`), and HUD glue (`_on_state_changed`). Extract a
  `Board` (pure functions over GameData: find/move/topmost) — this also makes the move
  logic unit-testable, which S3 needs.

- [ ] **D4. Kill the global-singleton reach-through.** `CardEnvironment.CURRENT` +
  `get_current_game()` appears in ~15 files, including deep inside `CardVisual._process`.
  You can't ever have two environments (deck viewer + game already fight over `CURRENT` —
  note `_enter_tree` overwrites it and `_exit_tree` only restores null). At minimum, pass
  the environment into `run_all_mods` as a parameter instead of static state; mods already
  receive nothing and fetch everything.

- [ ] **D5. Replace per-physics-frame GUI rebuild with dirty flagging.**
  [play_area.gd:95-99](UI/play_area.gd:95) — the comment admits it: "since we cannot
  directly detect if array contents have changed." You *can*: every mutation already funnels
  through Game (after D2). Emit one `board_changed` signal from Game after each
  `move/discard/draw/undo` and call `set_card_zones()` from that. Keeps
  `set_card_zones_visuals` (cheap part) in process if needed for focus effects.

- [ ] **D6. Undo via full deep-copy is fragile (B11) and heavy.** Consider command-pattern
  undo (each move records its inverse) — it eliminates the reference-remapping problem
  entirely, makes saves cheap, and you already have a single mutation choke point after D2.

- [ ] **D7. Delete the dead code.** Roughly a third of the audited lines are commented-out
  history: [pip_comparator.gd:199-265](Scripts/pip_comparator.gd:199) (entire old class),
  the disabled `Scoring.HalfStepRank`/`MultiSuit` match arms throughout pip_comparator,
  [card_visual.gd:329-365](Cards/card_visual.gd:329),
  [skill_scorer_cascade_lower.gd:33-140](Cards/Skills/Rules/skill_scorer_cascade_lower.gd:33)
  (~110 lines), [type_stone.gd:8-31](Cards/Types/type_stone.gd:8),
  [card_modifier.gd:108-147](Cards/card_modifier.gd:108), `skill_hungry_hippo.gd`'s gutted
  `on_card_dropped_on`. Git already remembers it. This alone cuts several hundred lines.

- [ ] **D8. `PipComparator`'s speculative abstractions.** `get_rank_profile`,
  `get_suit_profile`, `get_rank_split_bounds`, `_get_suit_objects` are all `match` statements
  with only a default arm — they exist for commented-out future card types. Either implement
  those types or collapse each to its one-line default; the "decoupled closure matrix"
  comments oversell no-op functions and mislead readers. Also `get_scorable_value`'s
  `context_pool` param is never used — drop it.

- [ ] **D9. Editor-tool code doesn't belong in `card_visual.gd`.** Lines 367-673 (~300 lines:
  mesh baking, star-skeleton generation) are `@tool` editor utilities inside the runtime
  card class. Move to `Cards/editor/card_mesh_baker.gd` (an `EditorScript` or separate tool
  node) so the gameplay file is readable.

- [ ] **D10. Unify the zone pair into one structure.** `upper_zone_type` + `upper_zone`
  (and lower) are parallel arrays that must be resized in lockstep (source of B4/B6).
  A `Zone` resource `{type_card: CardData, columns: Array[ArrayCardData]}` — or a
  `Column {header: CardData, cards: Array[CardData]}` — removes the desync class of bugs
  and simplifies `find_data_vec3`, the iterator, and `set_card_zone`.

- [ ] **D11. `Scoring` naming/comment pass.** The file is good structurally (ScoreModel as
  the single scoring authority is the right call) but headers like "CENTRAL STRATEGY ROUTER
  PARALLEL ENGINE" and "TYPE & SCORING VALIDATION MATRICES (DECOUPLED CLOSURES)" describe
  nothing that's there — nothing is parallel and there are no closures. Rewrite the section
  banners to say what the code does.

---

## 4. EFFICIENCY & LINE-COUNT REDUCTIONS

- [ ] **E1. `run_all_mods` fires a full `on_anything` pass after every event**
  ([card_environment.gd:42-44](Scripts/card_environment.gd:42)), and every mod call is
  followed by a full `skill_active_check()` walk (line 37, 41). One user action can trigger
  dozens of complete board scans. Cache the flattened card list once per dispatch (also
  fixes B10), and only run `skill_active_check` once per event, not per mod.

- [ ] **E2. Comparator dispatch is O(all cards) per comparison.**
  `PipComparator.compare_ranks/suits` call `return_first_compare_mod_result`, which walks
  every card in play *per pair compared*. Scoring compares pairs in nested loops
  (`is_flush`, straight scans, sorts) → scoring one board is O(cards² × board). Fix: at
  the start of a scoring pass, collect the (rare) mods implementing
  `on_compare_ranks/suits` once into an array and consult only those; skip the walk
  entirely when the array is empty (the common case).

- [ ] **E3. `_physics_process` rebuild churn** (see D5). `set_card_zones` clears and
  refills three dictionaries and touches every Control 60×/sec even when nothing moved.
  This is the biggest steady-state cost in the project.

- [ ] **E4. `find_data_vec3` linear-scans the whole board** and is called repeatedly per
  move (`move_data_to_coord` calls it, callers call it first too — `move_data_ontop_data`
  computes it, then `move_data_to_coord` computes the source again). Pass coords through
  instead of re-finding, or maintain a `CardData -> Vector3i` dictionary updated on move.

- [ ] **E5. `save_state` deep-duplicates the entire game state after every single action.**
  With big decks this is the per-click hitch. Superseded by D6; short-term, duplicate lazily
  (only when undo is pressed... not possible — so D6 is the real fix) or cap history length.

- [ ] **E6. `set_card_zone` / `update_card_zone_visuals` duplicate their body for
  index 0 vs 1..n** ([play_area.gd:158-182](UI/play_area.gd:158)): the "map the zone card"
  block and the "map row cards" block are identical except for the data source. Extract
  `bind_control(c: Control, d: CardData)`; same for the visual settings. ~40 lines saved,
  one place to fix S5.

- [ ] **E7. `game_data.gd:print_board` duplicates the upper/lower dump** — extract
  `_zone_to_csv(types, zone)` and call twice. `score_row`/`score_col` in game.gd are also
  near-identical → one `score_line(result, score_zone, index)` after B1 is fixed.

- [ ] **E8. `BoosterTemplate` repeats the gather-and-broadcast pattern 10×**
  ([booster_template.gd](Cards/Types/booster_template.gd)) — `create_one_choice` and
  `view_choices` each list all five `get_possible_X` + `run_all_mods("on_get_possible_x")`
  pairs. One helper returning a struct/dictionary of the five arrays halves the file. Note
  also: those `run_all_mods` calls aren't awaited — results may be consumed before async
  mods finish; make the helper `await`.

- [ ] **E9. `CardDataIterator.should_continue` recurses** for every empty/finished
  collection; a `while` loop is cheaper and immune to deep recursion. Cosmetic, but it's
  also the file you'll touch for B10/E1 anyway.

- [ ] **E10. GameData scalar setters emit `state_changed` unconditionally**
  ([game_data.gd:6-25](Scripts/game_data.gd:6)) → five HUD label updates per emission,
  multiple emissions per scoring pass. Guard `if value == goal: return` per setter, or
  batch with `call_deferred`-style single emit per frame.

- [ ] **E11. Editor-only, low priority:** `card_visual.gd`'s bake tool `get_v_idx` lambda
  is O(V²) vertex lookup; use a `Dictionary[Vector2i, int]` of quantized positions.

---

## 5. SUGGESTED EXECUTION ORDER

1. Quick confirmed fixes, each independent: **B1, B2, B3, B4, B5, B6, B7, B8** (one small
   edit each; test by playing one round + one undo).
2. **B9** (return_to_map sweep) — small, prevents real save-data loss.
3. **B10 + E1** together (snapshot iteration in `run_all_mods`) — one change to
   card_environment.gd; retest Next/Submit heavily.
4. **D7** dead-code purge (mechanical, huge readability win, zero risk).
5. **D2 → D5 → E3/E4** (single mutation API, then dirty-flag GUI) — medium effort.
6. **B11/D6** (undo redesign) — the deep one; do after D2 so commands are easy to record.
7. Remaining D/E items opportunistically.
