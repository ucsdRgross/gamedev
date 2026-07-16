# Solatro Architecture Review

Audit date: 2026-07-01. Scope: `Levels/game.gd`, `Scripts/` (card_data_iterator, game_data,
pip_comparator, card_environment, scoring, card_data_array, mods_list), `UI/play_area.gd`,
everything in `Cards/`, plus `Levels/main.gd` for context.

**Update 2026-07-10:** the Game/GameView split landed (`Levels/game_view.gd` — headless `Game`
logic node owned by a detachable UI view; `score_row`/`score_col` unified into `score_line`;
headless unit tests in `Tests/Engine/test_game_data.gd` / `test_game_headless.gd`). §1.2/§1.3
below are refreshed; resolves **S1**, **N3**, the score half of **E7**, and **D5/E3**'s
rebuild churn — see the per-item notes.

---

## 1. ARCHITECTURE OVERVIEW

### 1.1 The one-paragraph version

Solatro is a solitaire/Balatro hybrid. **All game state lives in plain `Resource` data
objects** (`GameData` holding arrays of `CardData`); **all game rules live in "modifier"
resources attached to cards** (skills/stamps/types) that are invoked by name via a global
broadcast system (`CardEnvironment.run_all_mods("on_xxx")`); **all visuals are rebuilt from the data on
demand** (`GameData.board_changed` → `PlayArea.queue_rebuild` reconciles Control nodes +
`CardVisual` sprites against `GameData`). The engine itself (`game.gd`) contains almost no rules — even *scoring
and drawing cards* only happens because a rule-card in `rules_deck` implements `on_run_scorer`
/ `on_next`.

### 1.2 Class map

```
Main (Levels/main.gd, scene root)
 ├─ Menu / Map ................. scene switching; Map hosts WorldMapController
 │                               (Scripts/Map/) over the vendored worldgen addon; run
 │                               progression = RunState via RunManager autoload
 │                               (static Main.save_info aliases RunManager.run)
 └─ GameView (Levels/game_view.gd) .. the show's scene root: ALL UI/input/HUD/animation.
	 │   Creates a headless Game child and injects itself (game.view = self); binds Game's
	 │   reactive signals (state_bound/processing_changed/submit_label_changed/show_resolved);
	 │   buttons + card clicks call Game commands (submit/next/undo/try_grab/try_place).
	 ├─ Game (Levels/game.gd) .. extends CardEnvironment; headless match logic. Mutates
	 │   │                       only `state`; zero UI children; every visual touch is
	 │   │                       `if view:` (view == null runs a full show — unit-tested
	 │   │                       by Tests/Engine/test_game_headless.gd)
	 │   ├─ state : GameData ... PURE DATA (Resource): draw/discard/rules decks,
	 │   │                       upper/lower zones (columns of stacks), score arrays,
	 │   │                       goal/total. Emits state_changed for the HUD.
	 │   └─ save_history ....... Array[GameData] "saveable" snapshots -> undo AND the
	 │                           persisted run.game_history (survives quit; see §1.4)
	 └─ PlayArea (UI/play_area.gd, %PlayArea)
		 ├─ builds a Control grid mirroring GameData zones (board_changed -> queued rebuild)
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
`PlayArea._on_gui_input` → `data_selected.emit(CardData)` → `GameView._on_data_selected`
(selection UI lives in the view; guarded on `game.processing`) → `Game.try_grab` /
`Game.try_place` → `return_first_data_array_result("on_can_grab_stack" / "on_can_place_stack")`
— i.e. the *rule cards* (e.g. `SkillGrabberOgLower`, `SkillPlacerOgLower`, `TypeInput`)
decide legality and return the stack → `Game.move_data_ontop_data` mutates
`GameData` arrays → fires `on_card_dropped_on` / `on_stack_cards` mods →
`Game.save_state()` snapshots for undo. Visuals catch up via the queued rebuild.

**Player presses Submit**:
`GameView` button → `Game.submit()` → `run_all_mods("on_run_scorer")` → `SkillScorerCascadeLower`
(a rule card) walks lower-zone rows/cols → for each, `run_all_mods("on_score_row"/"on_score_col")`
→ `SkillEvalPokerBest` calls `Scoring.PokerHands.score(cards)` → best `Result` →
`Game.score_line` (data always; paced visuals only `if view:` —
`view.animate_meld / update_line_score / show_meld_score / reset_meld`).

**Player presses Next**:
`run_all_mods("on_next")` → `TypeInput.on_next` (per input-zone column): drops its upper
stack into the lower zone (`move_data_to_coord`), then `Game.draw_card()` refills.

**Undo**: every action ends in `save_state()`, which pushes a *saveable* snapshot
(`GameData.to_saveable()`) and requests a background disk save. Undo pops history,
rebuilds a runtime state from the new top (`_runtime_state` → `duplicate_state` +
`restore_runtime`), reassigns `Game.state`; PlayArea rebuilds from scratch. The full
history persists (see §1.5), so closing the game cannot rewind a mistake.

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

### 1.5 Meta layer: world map, run, persistence (added 2026-07)

The map screen is a traversable procedural world (Slay-the-Spire style) generated by the
vendored **worldgen addon** (`addons/worldgen/`, canonical home is the separate `worldgen`
project — re-copy to update, never edit here). Around it sits a run/progression layer:

```
RunManager (autoload, Scripts/run_manager.gd) — owns the current run + all persistence
 ├─ run : RunState (Scripts/run_state.gd, Resource) — the whole saved document:
 │    world_seed, current_node_id, lap, fame, overscore_ratio_sum, traveled edges,
 │    card_datas/rule_datas (run deck), pending_goal/pending_node_id (show being played),
 │    game_history: Array[GameData] (the in-progress show's FULL undo stack), game_submits
 ├─ balance formulas: goal_for(progress,lap,boss), record_win, luck()  (DESIGN_DOC §15)
 └─ background save queue: request_save() (coalesced, threaded) / save_run() (sync) /
	  _build_payload() (independent copy) / _exit_tree() flush.  user://run_save/

Map (Levels/map.gd, extends CardEnvironment) — the map SCREEN + booster CardEnvironment
 └─ WorldMapController (Scripts/Map/world_map_controller.gd, Node2D)
	  ├─ WorldMap2D (addon)  generate→bake once / reload_from_bake; overlay() = the DAG
	  ├─ Camera2D (pan/zoom/follow) + MapPlayerToken (walks edge curves)
	  ├─ MapNodeRoles (Scripts/Map/map_node_roles.gd) — deterministic role/goal/booster
	  │    assignment into WorldGraphNode.meta, re-derived every populate (never saved)
	  └─ traversal: reachable set (direction-aware, reverse adjacency on odd laps),
		   4 edge visual states (traveled/next/usable/hidden), keyboard+mouse selection
MapHoverPanel (UI/map_hover_panel.gd)   — node tooltip + booster preview + card inspector
DeckPicker (UI/deck_picker.gd)          — menu New Run deck list
```

**Flow.** Menu → `new_run(deck)`/`continue` → `RunManager` → `Map.start_run` → controller
generates/reloads the map, assigns roles, places the token. Clicking/keyboard-selecting a
reachable node → `move_to` → `node_entered`: a **game/boss node** stashes `pending_goal`
and enters `Game`; a **booster node** opens a take-all `ChoiceViewer`. `Game` runs 3 acts
(submits); win → `record_win` (fame) → back to map; loss → run over → menu (save cleared).
End node = boss; winning it flips to an endless reverse lap on the same graph.

**Persistence & anti-cheat.** Every committed action saves the whole run — including the
undo history — to `user://run_save/run.tres` on a background thread (coalesced), so closing
the game can't rewind a mistake and undo survives a quit. Serialization notes: the
`CardModifier.data` self-cycle is unlinked/relinked (`GameData.to_saveable`/
`restore_runtime`); `BigNumber` scores are un-exported runtime-only, persisted as parallel
typed `packed_*_mant`/`packed_*_exp` arrays on `GameData` (`pack_scores`/`unpack_scores`).
The atomic write uses a `run.tmp.tres` temp file — the `.tres` extension is required, as
`ResourceSaver` picks its format from the extension. See the handoff doc
`HANDOFF_worldgen_map.md` for the full picture, file map, and open follow-ups.

### 1.6 Suit props & statuses (added 2026-07, Suit-Props plan Phases 0–6; refreshed 2026-07-13)

Suits became a **fourth kind of `CardModifier`** (`PipSuit`), and a new **prop simulation** rides
on top of the scorer. The full reference (file map, tick loop, view pipeline, knobs, landmines,
recipes) is `PROPS_BUGFIX_HANDOFF.md`; key facts for anyone extending this:

- **`PipSuit` is dispatched ONLY via `run_card_mods` + `spawn_props`** — never through the
  suit-blind `run_all_mods` iterator. It is the one dispatch path that sees suits. Suits are
  nominal (`get_suit_index()` = palette/art slot only); the old **ordinal `compare_suits` was
  removed** (settles the B7 / D8 suit scaffolding). Switch by constructing the exact class
  (`PipSuitHoop.new()`, …) or indexing `PipSuit.STANDARD` (`from_index` deleted 2026-07-13).
- **`on_score` / `on_after_score` are now broadcast** by `Game._run_score_effects` per scored
  meld (previously commented out) — this activates `SkillExtraPoint` / `StampDoubleTrigger` /
  `SkillEchoingTrigger`, which were dormant before.
- **Statuses** (`CardModifierStatus`, an `Array` on `CardData`) merge by class, self-scope their
  targeted hooks (`if target != data: return`), and are heard both by the `run_all_mods`
  broadcasts and by `run_card_mods` prop passes. **The suit self-cycle (`CardModifier.data`) and
  the status back-refs are unlinked/relinked in all four save/restore sites** (game_data.gd +
  run_manager.gd) — same discipline as the pre-existing modifier cycle.
- **The prop simulation lives in the data layer:** `Game.run_props(spawners)` is one deterministic,
  integer-ticked loop (spawn → move → 3-phase pass → finish → sync) with an `act_overrun` runaway
  cap + `note_processing` weighting and **time-compression** in `get_delay()` (shrinks the
  per-step delay under a long resolve, read live so animations retime mid-flight). Headless
  (`view == null`) the whole submit resolves in one frame. Props are transient (never serialized);
  a quit mid-act replays from the pre-act board.
- **The view layer is `PropLayer`** (`UI/prop_layer.gd`, under the scroll content so props ride
  the scroll): per-frame interpolation against the live tick duration, spawn/teleport/void
  animations, and a card-reaction state machine (jump/spin) aggregated from prop hints. The Game
  is one tick ahead of the view and awaits `PropLayer.tick_done` each tick — guarded by
  `view.prop_tick_pending()` so an events phase that outlasts the animation (persistent-signal
  emission already fired) skips the await instead of hanging. Every visual carries an
  `anchor_coord` re-pinned to live slot geometry per frame (relayout-proof); batch mates spread
  via `PropFormation` lane offsets (an @tool node under PropLayer, plotted in the editor);
  `PropLayer.manual_step` + two GameView debug buttons let the owner step prop ticks one at a time.
- **CardVisuals moved into the scroll content too (2026-07-13):** cards live on `%CardLayer`
  (Node2D inside TopLevelVBox, sibling of PropLayer), so the scroll transform carries controls,
  cards, and props together — no more scroll-lag chase. Consequence: cards clip at the play-area
  rect like props (the deck/discard fly-in is invisible outside it). The §1.2 class-map line
  placing CardVisual under PlayArea's root predates this.
- **Board draw order is 100% structural (no z_index anywhere), 2026-07-15:** the whole board sits
  on ONE canvas (no `CanvasLayer`), so every board CanvasItem is kept at `z_index == 0` and order
  is decided by sibling position + parent nesting: `TopLevelVBox` children run `CardLayer →
  PropLayer → OverlayLayer` (later = on top); CardVisuals hold row-major child order in CardLayer
  (`move_child`, not z); a prop can render a **back half** parented into CardLayer beneath its
  occupied card so a card passes *through* it (the hoop ring). Full exhaustive reference:
  **`LAYERING.md`**.
- **Card text surface is the focus inspector panel** (play_area.gd), a permanent OverlayLayer child
  re-pinned beside its anchor control every frame — native `tooltip_text` popups were removed
  (they blocked board clicks). Any display-only Control under the scroll content must claim the
  SmoothScroll addon's `_smooth_scroll_default_mouse_filter_set` meta BEFORE `add_child` or the
  addon rewrites it into a click-blocking hit-target.
- **Reactions key on `card.skill` by design:** only talented cards ever JUMP (hoop pass) or SPIN
  (knife pass) — a fully plain deck shows no poses at all. A talented card also suppresses its
  own suit's prop emission (`PipSuit._spawn_origin`), so an all-talent suit spawns nothing.
  Decks are loop-built in `Decks/deck.gd` (each `_build_deckN()` documents its niche): `deck11`
  (the `get_deck()` default) mixes plain + talent cards per suit so every kind spawns AND reacts;
  `deck12` is the only Firework grant path (kind 4 is outside `PipSuit.STANDARD`, never random);
  `deck13` is the Burning/Juggling status stress deck. deck9/deck10 show zero hoops by
  construction (every hoop card is talented) — documented on their builders.
- **`submits_used` lives ON `GameData`** (`@export_storage`) so undo/history snapshots rewind the
  act count; `Game.submits_used` is a forwarding property. Any new per-show counter that undo must
  rewind belongs on GameData, not Game.
- **Extension contract (zero engine edits):** a new prop behavior = one `PropModifier`; a new
  prop-suit = one `PipSuit` subclass (+ optional `PropVisual`, palette entry); a new status = one
  `CardModifierStatus` subclass. The tick loop, dispatch, scoring seam, pacing, compression, and
  tests stay closed. UI-facing strings go through `TRANSLATION.find` (CSV keys); shared tuning
  knobs (e.g. `prop_tick_fraction`) live in `PlayerSettings`.

### 1.7 Undo & game-over contract (added 2026-07-13)

Undo is live in every state; `Game.undo()` dispatches on three:

- **Mid-act cancel:** pressing Undo while Submit/Next resolves sets `act_cancelled`
  (allowed only inside the `_act_cancellable` span of `_perform_submit/_perform_next`).
  The resolution FAST-FORWARDS — `get_delay()` returns 0 (read live, so animations snap),
  `score_line`/`_run_score_effects` early-return, `run_props` breaks like `act_overrun`,
  and `PropLayer` releases a manual-step hold — then the performing function calls
  `_restore_pre_act_board()`: state is rebuilt from `save_history[-1]` (the pre-act
  snapshot; the act only commits at its END), `pending_action` clears, the view aborts
  stranded prop visuals (`PropLayer.abort_all`) and rebuilds. Nothing pops from history.
  Mods keep mutating the doomed state during the unwind — safe, it's replaced wholesale.
- **Game over (`_resolved`):** Undo emits `show_unresolved` (view drops the outcome
  overlay), unlocks, then falls through to a NORMAL undo of the final Submit's snapshot.
  Because of this, **fame banks in `exit_show()` (Continue), not `_resolve_game()`** — the
  win stays undoable, and a quit-at-win-screen resume (which re-runs `_resolve_game`) can't
  double-bank fame (that was a live bug before).
- **Otherwise locked** (resume load, replay tail before the cancellable span): ignored.

View side: the win/lose overlays live INSIDE `PlayContainer` (full-rect Labels + dim
ColorRect, `mouse_filter` STOP) so they cover exactly the board; Submit/Next stay disabled
(`processing` holds), the Undo button is never disabled, deck/discard/rules viewers stay
usable, `PlayArea.disable_board_focus()` strips card focus so keyboard/controller can't
reach covered cards — and LOCKS it (`board_focus_locked`, re-applied at the end of every
`set_card_zones`) because the final Submit's discard queues a deferred rebuild that lands
after the overlay and would otherwise re-enable focus; `enable_board_focus()` on dismissal.
Continue holds focus.
Guarded by `test_game_headless` (cancel + game-over-rewind semantics) and the
`Tests/Interaction/` suite (real input events through every modality).

---

## 2. BUGS

### Confirmed

- [x] **B1. Upper-zone row scores are written to the lower-zone score array.**
  [game.gd:260-262](Levels/game.gd:260) — `score_row` does
  `var score_zone := state.scores_row_lower; if zone == state.upper_zone: score_zone = state.scores_row_lower`.
  The `if` branch assigns the *same* array. Should be `state.scores_row_upper`.
  Consequence: `scores_row_upper` is never written; upper-zone scoring silently corrupts
  lower-row scores. Fix: assign `scores_row_upper` in the branch.

- [x] **B2. Cards animate to the DISCARD pile when moved to the DRAW deck.**
  [card_visual.gd:206-209](Cards/card_visual.gd:206) — the `data.Stage.DRAW` case in
  `on_stage_changed` targets `discard_ui`. Copy-paste from the DISCARD case; should be
  `deck_ui`. (The `_ready` positioning above it, line 169-170, gets it right.)

- [x] **B3. Dead code in `CardVisual.data` setter — stage animation never triggers from it.**
  [card_visual.gd:35-42](Cards/card_visual.gd:35) — after `data = value`, the guard
  `if data == value: return` is *always* true, so the `on_stage_changed()` call below is
  unreachable. Also line 41 tests `if is_node_ready and data:` — missing `()`, so it tests
  the Callable (always truthy) instead of calling it. Fix: decide the intended early-out
  (probably compare against the *old* value before assignment) and call `is_node_ready()`.

- [x] **B4. `find_data_vec3` iterates the wrong array for the upper zone.**
  [game.gd:186](Levels/game.gd:186) — `for col : int in state.upper_zone_type.size():`
  then indexes `state.upper_zone[col]`. The lower-zone loop (line 190) correctly uses
  `state.lower_zone.size()`. If `upper_zone_type` and `upper_zone` ever disagree in length
  (e.g. mid `ZoneAdder.on_active`, which appends to the two arrays in separate statements),
  this indexes out of bounds. Fix: iterate `state.upper_zone.size()`.

- [x] **B5. `find_data_vec3` returns float `Vector3`s from an `-> Vector3i` function.**
  [game.gd:183-193](Levels/game.gd:183) — four `return Vector3(...)` statements. Godot
  converts implicitly today, but it's a silent truncation hazard and a warning generator.
  Fix: `Vector3i(...)` everywhere.

- [x] **B6. `ZoneAdder.on_deactive` can `remove_at(-1)`.**
  [zone_adder.gd:29-35](Cards/Skills/Rules/zone_adder.gd:29) — `find(card_data)` result is
  not checked; if the zone card was removed by anything else, `index == -1` →
  `remove_at(-1)` / `pop_at(-1)` removes the *last* (wrong) column, silently desyncing
  `zone_type` from `zone`. Fix: `if index == -1: return`.

- [x] **B7. NAN comparisons make incomparable suits "different", enabling illegal stacks.**
  [skill_grabber_og_lower.gd:17](Cards/Skills/Rules/skill_grabber_og_lower.gd:17) and
  [skill_placer_og_lower.gd:17](Cards/Skills/Rules/skill_placer_og_lower.gd:17) —
  `PipComparator.compare_suits` returns `NAN` when suits aren't comparable, and
  `NAN != 0` is `true`, so the "different suit" half of the check passes for any
  non-standard suit pair. (`abs(NAN) == 1` is false so rank saves you today, but the same
  pattern applied to ranks/suits independently is a trap.) Fix: check `is_nan()` explicitly.

- [x] **B8. `PlayArea.popup_score` can divide by zero.**
  [play_area.gd:363-371](UI/play_area.gd:363) — `meld_size` counts only meld cards present
  in `data_card`; if none are (cards just discarded/freed), `combo_pos /= 0` → NaN position.
  Fix: `if meld_size == 0: return`.

- [x] **B9. `return_to_map` loses cards still on the board and doesn't await mods.**
  [game.gd:244-250](Levels/game.gd:244) — only `draw_deck + discard_deck` are saved back to
  `Main.save_info.card_datas`; any card still in `upper_zone`/`lower_zone` is permanently
  lost from the player's deck. Also `run_all_mods("on_game_end")` is not awaited, so mods
  that restore state on game end (e.g. `SkillHungryHippo.on_game_end` returns consumed
  cards) race the save. Fix: sweep zones into `draw_deck` first, and `await` the mods call.

- [~] **B10. (BY DESIGN per owner, 2026-07-01 — live iteration is the intended semantics
  for now; revisit only if a concrete mis-visit bug appears.)
  `run_all_mods` iterates live collections that mods mutate.**
  [card_environment.gd:30-44](Scripts/card_environment.gd:30) + CardDataIterator —
  the iterator keeps integer indices into `GameData`'s actual arrays; hooks like
  `on_next` (`TypeInput` moves/draws cards) and `on_discard` mutate those arrays
  mid-iteration → cards get skipped or visited twice, and out-of-range indices are
  possible. This is the most structural bug in the codebase. Fix: snapshot the card list
  before dispatch (`var all := []; for d in CardDataIterator.new(): all.append(d)`), or
  queue mutations until after the walk.

- [x] **B11. Undo history: modifier back-references point at the wrong card copies.**
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
  **FIXED 2026-07-01** using `Resource.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)`
  (Godot 4.4+) in `duplicate_state()` and `Array.duplicate_deep(...)` in `add_deck` (N7):
  deep duplicate remaps ALL cross-references consistently — modifier `.data` backrefs AND
  mod-internal refs (`ZoneAdder.card_data`, `SkillEchoingTrigger.triggered`,
  `SkillHungryHippo.consumed_cards`) — so no manual rebind is needed. `BigNumber` is
  RefCounted (owner's own class), invisible to duplicate_deep; the manual
  `duplicate_big_number_array` copy stays.

### Suspicious — verify in-engine before fixing

- [x] **S1. `Game.state` initializer + setter side effects.**
  [game.gd:11-15](Levels/game.gd:11) — in Godot 4 the declaration initializer invokes the
  setter, which calls `_on_state_changed()` → `%Goal/Label` before the node is in the tree.
  If you see `get_node: Node not found` errors at game start, this is why. Also: the setter
  never disconnects the old state's `state_changed`, and re-assigning the same GameData
  would double-connect. Fix: guard with `is_node_ready()`, disconnect old state.
  **RESOLVED 2026-07-10 by the Game/GameView split:** the `state` setter no longer touches
  UI — it only emits `state_bound`; the view rebinds through `GameView._bind_state`
  (disconnect-old / connect-new, the N9 discipline).

- [x] **S2. `find_vec3_data` uses `Array.get(index)` on possibly out-of-range indices.**
  **VERIFIED + FIXED 2026-07-02:** test_board.gd's out-of-range probes confirmed that
  `Array.get()` returns null but ALSO pushes an engine error on out-of-range indices.
  Both `find_vec3_data` and `is_data_topmost` now use explicit bounds checks instead.

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

- [x] **S5. `update_card_zone_visuals` hard-indexes `data_card[connected_data]`.**
  [play_area.gd:208](UI/play_area.gd:208) — if a visual failed `is_instance_valid` during
  `set_card_zone` the key exists (recreated), but any path where visuals lag data by a frame
  (deferred `add_child` in `CardVisual.add_child_card_visual`) makes this a KeyError crash
  candidate. Use `.get()` with a null check.

- [ ] **S6. (Owner reverted an applied guard on 2026-07-01 — same-value re-sets emitting
  `stage_changed` are relied upon; do not re-apply without discussion.)
  `CardData.stage` setter always overwrites `previous_stage`,** even when the new
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

- [x] **D3. Split `game.gd`'s responsibilities.** It is simultaneously: board mutation
  engine (`move_data_to_coord` family), match lifecycle (deck setup, undo, save), scoring
  presentation (`score_row/score_col`), and HUD glue (`_on_state_changed`). Extract a
  `Board` (pure functions over GameData: find/move/topmost) — this also makes the move
  logic unit-testable, which S3 needs.
  **DONE in two landings:** `Scripts/board.gd` (anchor-based move engine, see §5 STATUS
  2026-07-02) and the 2026-07-10 Game/GameView split (HUD/input/animation out of game.gd;
  headless Game unit-tested in Tests/Engine/).

- [ ] **D4. Kill the global-singleton reach-through.** `CardEnvironment.CURRENT` +
  `get_current_game()` appears in ~15 files, including deep inside `CardVisual._process`.
  You can't ever have two environments (deck viewer + game already fight over `CURRENT` —
  note `_enter_tree` overwrites it and `_exit_tree` only restores null). At minimum, pass
  the environment into `run_all_mods` as a parameter instead of static state; mods already
  receive nothing and fetch everything.

- [x] **D5. Replace per-physics-frame GUI rebuild with dirty flagging.**
  [play_area.gd:95-99](UI/play_area.gd:95) — the comment admits it: "since we cannot
  directly detect if array contents have changed." You *can*: every mutation already funnels
  through Game (after D2). Emit one `board_changed` signal from Game after each
  `move/discard/draw/undo` and call `set_card_zones()` from that. Keeps
  `set_card_zones_visuals` (cheap part) in process if needed for focus effects.
  **DONE (landed with the revision counter):** `GameData.revision` setter emits
  `board_changed` → `PlayArea.queue_rebuild()` (coalesced, deferred); direct
  `set_card_zones`/`flush_rebuild` for undo/resume paths.

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

- [x] **D12. Kill the `var game : Game = CardEnvironment.CURRENT if ... else null`
  boilerplate with a base-class accessor.** Every game-related modifier re-derives the
  game (5+ call sites in Cards/ alone; three different spellings:
  `get_current_game()`, the ternary, and raw `CURRENT`). Add to `CardModifier`:

  ```gdscript
  var game : Game:
	  get: return CardEnvironment.get_current_game()
  var env : CardEnvironment:
	  get: return CardEnvironment.CURRENT
  ```

  Mod bodies become `if not game: return` — one line, one spelling, and when the
  environment stops being a static singleton (D4), only the accessor changes, not fifty
  call sites. Longer-term (with D1's hook-contract work): pass a context object as the
  first argument of every hook (`func on_next(ctx: CardEnvironment)`), which makes mods
  testable without any global and removes the null-check entirely — but that touches
  every hook signature, so do the accessor now and fold the context param into D1's
  signature pass. Related: mods that *mutate* game state (`TypeInput.draw_card`
  appending to zone arrays, `ZoneAdder`) must go through the Game/Board API regardless —
  see D2 and §5.5; the accessor is for *reading*, not a license to keep direct writes.

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

- [x] **E3. `_physics_process` rebuild churn** (see D5). `set_card_zones` clears and
  refills three dictionaries and touches every Control 60×/sec even when nothing moved.
  This is the biggest steady-state cost in the project.
  **DONE with D5:** rebuilds only run on `board_changed` (revision bump), coalesced per frame.

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

- [~] **E7. `game_data.gd:print_board` duplicates the upper/lower dump** — extract
  `_zone_to_csv(types, zone)` and call twice. `score_row`/`score_col` in game.gd are also
  near-identical → one `score_line(result, score_zone, index)` after B1 is fixed.
  **PARTIAL 2026-07-10:** the score half landed as `Game.score_line(result, is_row, zone,
  index)`; the `print_board` duplication remains.

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

## 5. MOVE LOGIC REDESIGN (`move_data_to_coord` and friends)

The current implementation ([game.gd:130-179](Levels/game.gd:130)) is the highest-risk
function in the codebase: it interleaves validation, source lookup, same-column index
compensation, extraction, and insertion in one body, and the compensation math
(`z_dist`, `cards_in_stack = z_dist - 1`, `dest.z -= cards_in_stack`) has at least three
under-specified edge cases (see S3). The structural problem is that **the destination is
expressed as an index into an array that the move itself mutates** — every same-column
move needs after-the-fact patching, and every new edge case adds another patch.

### 5.1 Root cause and the fix

Fix the representation, not the patches: **express destinations as anchors (card
references), not indices.** A card reference stays valid across the extraction; an index
does not. The whole compensation block disappears.

```
Public API (what callers use — note callers already think in anchors:
move_data_ontop_data(moving, dest_card) is the main entry point):

	move_stack(moving: CardData, count: int, dest: Anchor) -> Error

	Anchor is one of:
	  OnTop(card: CardData)      # insert directly above this card
	  ColumnEnd(x, col)          # append to a column (covers dest.z == -1 today)
	  ColumnStart(x, col)        # insert at row 0 (TypeInput's "under everything")
```

### 5.2 The algorithm (four phases, strictly ordered)

```
move_stack(moving, count, dest):
  # PHASE 1 — RESOLVE (read-only; fail fast, mutate nothing)
  src := locate(moving)                     # (zone, col, row) — from the position index,
											#   not a linear scan (see 5.4)
  if src == NOT_FOUND: return ERR_NOT_ON_BOARD
  count := clamp(count, 1, column_size(src) - src.row)   # -1 means "rest of column"
  stack := the `count` cards at src.row.. (NOT yet removed)

  # PHASE 2 — VALIDATE (all preconditions in one place, still read-only)
  if dest is OnTop and dest.card in stack: return ERR_DEST_INSIDE_STACK
  if dest is OnTop and locate(dest.card) == NOT_FOUND and dest.card not in zone_types:
	  return ERR_DEST_NOT_ON_BOARD
  if dest resolves to exactly (src position): return OK_NOOP   # explicit no-op, no events

  # PHASE 3 — MUTATE (two primitive operations, nothing else)
  extract(src.zone, src.col, src.row, count)      # one splice
  insert_at(resolve(dest), stack)                 # anchor resolved AFTER extraction —
												  #   this is the entire "compensation"
  for c in stack: c.stage = PLAY                  # (or ZONE — derive from dest)

  # PHASE 4 — NOTIFY (after the board is consistent)
  update position index for affected columns
  if trigger_mods:
	  emit on_card_dropped_on / on_stack_cards    # board is already valid when mods run
  return OK
```

Why each phase boundary matters:
- **Resolve/Validate before any mutation** → a rejected move provably leaves the board
  untouched (today the out-of-bounds branch at [game.gd:132-137](Levels/game.gd:132)
  `assert(false)`s *after* nothing, but the same-column clamp silently mutates intent).
- **Anchor resolved after extraction** → same-column up-moves, down-moves, and
  cross-column moves are literally the same code path. No `z_dist`. The only rule left is
  the Phase-2 "dest inside moving stack" rejection — which today is a silent clamp
  (`cards_in_stack = z_dist - 1`), a policy no caller actually depends on and which S3
  flags as untested. Make it an error; if a mod legitimately needs "move the part of the
  stack above X", it should say so explicitly with a smaller `count`.
- **Events after consistency** → mods triggered by the move observe a valid board
  (today `on_card_dropped_on` receives `onto_card` computed from *pre-move* indices,
  [game.gd:142](Levels/game.gd:142), which is `null` whenever `dest.z == 0` — with
  anchors, the onto-card IS the anchor, no lookup at all).

### 5.3 Board invariants (assert these; they make everything else testable)

Define once, in a debug-only `Board.validate()` called after every mutation
(and by every fuzz test in UNIT_TESTS_PLAN.md):

  I1. Every CardData appears in EXACTLY ONE of: draw_deck, discard_deck, rules_deck,
	  a zone column, a zone_type row.  (No duplicates, no orphans.)
  I2. upper_zone.size() == upper_zone_type.size(); same for lower. (Dies with D10.)
  I3. card.stage matches its container (DRAW ⇔ draw_deck, ZONE ⇔ zone_type row, ...).
  I4. Position index (5.4), if present, agrees with a full rescan.
  I5. No null entries inside any column/deck array.

The current code cannot check I1 cheaply because membership is only discoverable by
linear scan — which is also why `find_data_vec3` exists (E4). Same fix serves both:

### 5.4 Position index

Maintain `Dictionary[CardData, Vector3i]` (plus a stage tag) updated by the two
primitives (`extract`/`insert_at` re-index only the affected column's tail — O(column),
not O(board)). `locate`, `find_data_vec3`, `is_data_topmost` become O(1) lookups, and I1
becomes a size comparison. This is what makes `Board.validate()` cheap enough to leave on
in debug builds and in fuzz loops.

### 5.5 Where it lives

Per D3: a `Board` class (plain RefCounted or static funcs over GameData) owning
`locate / extract / insert_at / move_stack / validate` and the position index, with
`Game` delegating. `Game` keeps the mod-event firing (Phase 4) so `Board` stays pure and
unit-testable without a scene tree — which UNIT_TESTS_PLAN.md depends on. `TypeInput`,
`ZoneAdder`, `discard_data`, and `draw_card` placement then route through `Board` methods
instead of raw array writes (closes D2's bypass list).

Migration order: (1) add `Board.validate()` + call it after every current mutation —
this alone will surface latent S3 bugs; (2) add the position index + swap `find_data_vec3`
internals; (3) introduce `move_stack` with anchors, port `move_data_ontop_data` /
`move_data_to_coord` callers one by one (keep the old function as a thin adapter:
`Vector3i` dest → anchor); (4) port the direct-array-write mods; (5) delete the adapter.

**STATUS 2026-07-02:** (1) done as `GameData.validate()` + `Game.debug_validate` after
moves/undo. (3) done: `Scripts/board.gd` implements `Anchor` + the four-phase
`move_stack` with error codes; `Game.move_stack` fires the Phase-4 events;
`move_data_to_coord` / `move_data_ontop_data` are thin adapters over it. Policy changes
that landed with it (all covered in Tests/test_board.gd): dest-inside-moving-stack is now
`ERR_DEST_INSIDE_STACK` (was a silent clamp), rejected moves push_warning + leave the
board bit-identical (was `assert(false)`/crash), `on_card_dropped_on` for `z == -1`
appends now receives the actual landing card (was always null), and same-position drops
are explicit `OK_NOOP`s (the pre-fix code swapped the card with the one beneath it).
(4) done 2026-07-02: `Board.place_card` / `add_column` / `remove_column`; TypeInput's
draw placement and ZoneAdder's add/remove route through them (and `discard_data` is now
off-board-safe, fixing ZoneAdder's latent discard-after-pop crash). Also 2026-07-02:
dispatch de-statics — `run_all_mods` / `return_first_*` / `skill_active_check` are now
INSTANCE methods iterating `CardDataIterator.new(self)`; `CURRENT` remains only as the
"environment on screen" pointer read at boundaries (mod accessors, PipComparator, UI).
Remaining: (2) position index, (5) delete the Vector3i adapters when convenient.

---

## 6. SECOND-PASS FINDINGS (2026-07-01, widened to Map/Main/Deck/save/settings)

A later pass over the same code plus the connected files not covered above
(`Levels/map.gd`, `Levels/main.gd`, `Decks/deck.gd`, `Scripts/player_save.gd`,
`Scripts/settings_manager.gd`, `Scripts/translation.gd`). Numbered N* to keep the
original B/S/D/E numbering stable.

### Confirmed

- [x] **N1. `Map.get_rules_collections()` returns the wrong shape — rules never count as
  active on the map screen.** [map.gd:17-18](Levels/map.gd:17) returns
  `[Main.save_info.rule_datas]` — a list *containing* one array — while the base contract
  ([card_environment.gd:24](Scripts/card_environment.gd:24)) and `Game`'s override return
  a flat `Array[CardData]`. So `is_data_in_rules(data)` (`data in get_rules_collections()`)
  is always false on the Map, and `CardModifier.is_active()` fails for every rules card
  there — any booster/choice logic that consults mod activity on the map silently gets
  "inactive". The return type also silently loosens `Array[CardData]` → `Array`. Fix:
  `return Main.save_info.rule_datas`, and type both overrides identically. (Same drift
  exists for `get_card_collections`: base says `Array[Variant]`, Game says `Array` —
  harmless today, tighten while there.)

- [x] **N2. `Game` scenes are never freed — every run leaks the whole game.**
  [main.gd:44-55](Levels/main.gd:44) — `switch_scene` only `remove_child`s the outgoing
  scene. That's intentional for the reused `menu_scene`/`map_scene`, but `enter_game`
  creates a fresh `Game` per run ([main.gd:24-27](Levels/main.gd:24)) and `game_ended`
  switches back to the map without freeing it: the Game node, its PlayArea, every
  CardVisual, the GameData history, and its `Deck.new()` (see N6) stay allocated forever.
  Fix: in `game_ended()`, `current_scene.queue_free()` before switching (or make
  `switch_scene` take an `owns_old_scene` flag).

- [x] **N3. Cards can be moved while scoring/next is resolving.** `_on_next_pressed`,
  `_on_submit_pressed`, and `undo_pressed` all guard on `processing`
  ([game.gd:108,120,230](Levels/game.gd:108)) — but `on_data_selected`
  ([game.gd:55](Levels/game.gd:55)) does not. During a multi-second scoring animation the
  player can grab and re-place stacks, mutating the zones the cascade scorer is iterating
  (compounds B10) and then `save_state()` mid-pass, corrupting undo history. Fix:
  `if processing: return` at the top of `on_data_selected` (and probably ungrab on
  processing start).
  **FIXED 2026-07-10 (split):** every Game command (`submit/next/undo/try_grab/try_place`)
  guards `processing` in Game, and `GameView._on_data_selected` early-returns while busy.
  Covered by `test_game_headless.test_command_guard_blocks_input`.

- [x] **N4. `TypeInput.on_next` assumes upper column i maps to lower column i.**
  [type_input.gd:24-29](Cards/Types/type_input.gd:24) — `drop_card` finds its own column
  index in `upper_zone_type`, then drops to `Vector3i(1, col, -1)` — the *lower* zone at
  the same index. Nothing guarantees the zones have equal column counts (they're built by
  independent `SkillAdderInputUpper`/`Lower` rule cards — remove one lower adder and the
  counts diverge), at which point the drop lands in the wrong column or trips
  `move_data_to_coord`'s out-of-bounds assert. Fix: make the pairing explicit — either the
  upper input card stores a reference to its paired lower zone card, or `drop_card`
  clamps/validates and no-ops when no matching lower column exists. (The §5 anchor API
  makes this natural: the dest anchor is the paired zone card, not an index.)

- [x] **N5. `CardModifier.is_active()` has no "uncovered/topmost" rule — most stamps and
  skills on ordinary play cards are permanently inert.** [card_modifier.gd:99-106](Cards/card_modifier.gd:99)
  returns true only for: rules-deck cards, `StampGlobal`, `StampRevealing`. A regular play
  card with `SkillExtraPoint` or `StampDoubleTrigger` and no stamp (most of `deck5`/`deck7`
  in [deck.gd](Decks/deck.gd)) fails every `is_active()` check, so `on_score`/`on_trigger`
  early-return: **those decks' mechanics do nothing today.** `StampRevealing`'s description
  ("Trigger effects even when covered") implies the intended default is "active while
  uncovered/topmost", but that condition was never implemented. Fix: add the topmost check
  (`CardEnvironment.CURRENT is Game and game.is_data_topmost(data)`) as the default-active
  condition, keeping Revealing as the covered-override — then test deck5/deck7 actually
  fire. Decide explicitly whether cards in the draw/discard decks should be "active" for
  Global (currently they are — the iterator includes both decks).

- [ ] **N6. Every `Game` instantiates ALL nine test decks.**
  [game.gd:9](Levels/game.gd:9) `@export var deck : Deck = Deck.new()` + `Deck`'s member
  initializers ([deck.gd](Decks/deck.gd)) build `rules1` and `deck1`–`deck9` — hundreds of
  CardData/Pip/Modifier resources — per game, per run, only for `get_deck()` to return one
  of them. Combined with N2 they leak. Fix: make deck definitions static factory
  *functions* (built on demand), which also collapses the ~500 lines of copy-pasted
  builder chains into loops — see N-E1.

- [x] **N7. `add_deck`'s `duplicate(true)` has the same back-reference problem as B11 —
  at game start, not just on undo.** [game.gd:91-96](Levels/game.gd:91) deep-duplicates
  `Main.save_info`'s cards into `state`. The duplicated modifiers' `.data` back-references
  (set by `with_skill` at deck construction) are cyclic (`card.skill.data == card`), and
  `Resource.duplicate(true)`'s handling of shared/cyclic sub-resources is exactly the
  hazard B11 describes — the play-copies' `skill.data` may point at the *save-file*
  originals, breaking every `data == self.data` self-guard from turn one. Verify in-engine
  (`print(card.skill.data == card)` after add_deck); fix with the same rebind pass as B11.
  This upgrade makes the B11 rebind fix a **prerequisite for correct mod behavior at all**,
  not just for undo.

### Smaller / verify

- [~] **N8. (DECLINED per owner, 2026-07-01 — desync is allowed so scores are never lost.) Score arrays never shrink.** `resize_score_zone` ([game.gd:252-257](Levels/game.gd:252))
  only grows; when a `ZoneAdder` deactivates and removes a column, `scores_col` keeps the
  removed column's total and every later column's score stays shifted relative to the
  board. Shrink (or re-key scores by zone card rather than index — the D10 `Zone` struct
  does this for free).
- [~] **N9. Resource-signal connect-without-disconnect pattern** (generalizes S1):
  `Game.state` setter, `SettingsManagerClass.settings` setter
  ([settings_manager.gd:8-11](Scripts/settings_manager.gd:8)), and `CardVisual.with_data`
  all connect to a resource's signal and never disconnect the previous resource —
  re-assignment double-fires or keeps dead objects reachable. Adopt one idiom:
  disconnect-old / connect-new in every resource-holding setter.
  **PARTIAL 2026-07-10:** the game-state case is fixed (`GameView._bind_state` disconnects
  the old state on every swap); `SettingsManagerClass.settings` and `CardVisual.with_data`
  still open.
- [x] **N10. No persistence:** resolved — runs now persist as `RunState`
  (Scripts/run_state.gd) via the `RunManager` autoload (Scripts/run_manager.gd) to
  `user://run_save/` (run.tres + the worldgen map bake). Loss clears the save; the menu's
  Continue gates on `RunManager.has_save()`. Note the standard Godot caveat: loading
  `.tres` from `user://` can execute embedded script paths (same exposure as
  settings.tres). `PlayerSave` remains only as the Deck Maker profile container.
- [x] **N11. Map layer/goal math:** superseded — the triangle map and `layer` are gone.
  Goals now come from `RunManager.goal_for(progress, lap, is_boss)` (float math, int
  clamp at the end; lap scaling capped to avoid int64 overflow in endless mode).
- [x] **N12. Map-generated cards have no `type`:** superseded — the triangle map's random
  card generation is gone. Map-acquired cards now come from booster packs
  (`BoosterTemplate.create_one_choice`), where `type` is a luck-gated roll by design.

### New efficiency / line-count items

- [ ] **N-E1. `Decks/deck.gd` is ~500 lines of copy-pasted builder chains.** A tiny
  data-driven factory (`for suit in 4: for rank in 13: ...`, plus a
  `standard(suit, rank, mods...)` helper) reproduces deck1–deck9 in ~60 lines, and makes
  N6's lazy construction trivial.
- [ ] **N-E2. `CardVisual._process` calls `CardEnvironment.get_current_game()` (and a
  dictionary lookup) every frame per card** ([card_visual.gd:231-237](Cards/card_visual.gd:231))
  — cache the play_area reference on `_ready`/context change; the existence check belongs
  to the D5 dirty-flag rework anyway.

---

## 7. SUGGESTED EXECUTION ORDER

1. Quick confirmed fixes, each independent: **B1, B2, B3, B4, B5, B6, B7, B8** (one small
   edit each; test by playing one round + one undo).
2. **B9** (return_to_map sweep) — small, prevents real save-data loss.
3. **B10 + E1** together (snapshot iteration in `run_all_mods`) — one change to
   card_environment.gd; retest Next/Submit heavily.
4. **D7** dead-code purge (mechanical, huge readability win, zero risk).
5. **D2 → D5 → E3/E4** (single mutation API, then dirty-flag GUI) — medium effort.
6. **B11/D6** (undo redesign) — the deep one; do after D2 so commands are easy to record.
7. Remaining D/E items opportunistically.

Second-pass insertions: **N7 verification belongs in step 0** (if add_deck back-refs are
broken, the B11 rebind fix jumps to the front of the queue — it gates correct mod behavior
everywhere). **N1, N2, N3 join step 1** (small, independent, confirmed). **N5** needs a
design decision (what "active" means for play cards) before deck5/deck7 content can work —
decide it alongside the D1 hook-contract pass.

---

## 8. SHARP EDGES & WORKING AGREEMENTS (salvaged from HANDOFF.md, 2026-07-02 era; still true)

Working agreements (do not "fix" — owner rulings, see the [~] items above):
- B10 live iteration, S6 same-value `stage_changed` re-emits, N8 score-array desync, D7
  commented-out code kept as reference.
- Player drops move with `trigger_mods = false` → `on_card_dropped_on`/`on_stack_cards` fire
  ONLY from automated moves (TypeInput). Confirm intentional before building content around
  player-drop triggers.
- All board mutations go through `Board` (see `Scripts/board.gd` header **MUTATION
  GUIDELINES**) or Game's draw/discard/deck functions; every mutation bumps
  `GameData.revision` AFTER the state is consistent. The bump (a) drives the coalesced
  PlayArea rebuild, (b) keys the compare-mod implementer cache. **A missed revision bump =
  stuck UI (visible) + stale compare cache (silent).**
- Anything reading PlayArea's `ui_data`/`data_ui`/`data_card`/control tree calls
  `flush_rebuild()` first.

Sharp edges:
- `stage` does triple duty: logical location, animation origin (`previous_stage`), S6
  re-emit channel. Re-setting an already-correct stage clobbers `previous_stage` and kills
  spawn/tween animations (bit us twice).
- First-implementer-wins mod dispatch precedence depends on board order — moving an
  unrelated card can change which of two comparator mods wins. Fine at 0–1 implementers.
- GDScript: declaration-default values BYPASS property setters (initial `state` signals
  must be wired in `_ready`; this caused the blank-board bug).
- Godot 4 delivers key/joypad events ONLY to the focused control — they never bubble to
  ancestor Controls (mouse events do). A `gui_input` handler on a container root will
  silently never see `ui_accept`/`ui_cancel`; board-wide keyboard/controller handling
  belongs in `_unhandled_input` (caught by the interaction suite 2026-07-13 — keyboard
  card selection had been dead code).
- `ui_accept`/`ui_cancel` are explicitly OVERRIDDEN in project.godot to bind joypad A/B —
  the engine defaults here didn't include them (also caught by the interaction suite:
  controller accept/cancel did nothing). Overriding a built-in ui_* action REPLACES its
  defaults, so the overrides re-list the full keyboard set (Enter/KP-Enter/Space; Escape);
  keep that in mind when editing them in the project-settings input map.
- Statuses must not call `move_data_*`/`discard_data` from hooks dispatched by
  `run_all_mods` (B10 live iteration) — defer via a queued action. And always
  `duplicate()`/`.new()` a status at the point of application (S7 shared-instance trap;
  `add_status` defensively duplicates foreign-`data` statuses).
