# Solatro Architecture Reference

Current-state reference (consolidated 2026-07-19 from the architecture review, scoring
plans, props handoffs, persistence handoff, and leak-prevention work — full historical
docs live in git history; see START_HERE.md for the retired-doc map). Companion docs:
[START_HERE.md](START_HERE.md) (agent rules + planning workflow), [LAYERING.md](LAYERING.md)
(board draw order), [HEADLESS_TESTING.md](HEADLESS_TESTING.md) (test-environment traps),
[DESIGN_DOC.md](DESIGN_DOC.md) (game design), [todo.md](todo.md) (backlog).

---

## 1. ARCHITECTURE OVERVIEW

### 1.1 The one-paragraph version

Solatro is a solitaire/Balatro hybrid. **All game state lives in plain `Resource` data
objects** (`GameData` holding arrays of `CardData`); **all game rules live in "modifier"
resources attached to cards** (skills/stamps/types/suits/statuses) invoked by name via a
broadcast system (`CardEnvironment.run_all_mods("on_xxx")`); **all visuals are rebuilt
from the data on demand** (`GameData.board_changed` → `PlayArea.queue_rebuild`). The
engine itself (`game.gd`) contains almost no rules — even scoring and drawing happen
because a rule-card in `rules_deck` implements `on_run_scorer` / `on_next`.

### 1.2 Class map

```
Main (Levels/main.gd, scene root)
 ├─ Menu / Map ................. scene switching; Map hosts WorldMapController
 │                               (Scripts/Map/) over the vendored worldgen addon; run
 │                               progression = RunState via RunManager autoload
 │                               (static Main.save_info aliases RunManager.run)
 └─ GameView (Levels/game_view.gd) .. the show's scene root: ALL UI/input/HUD/animation.
     │   Creates a headless Game child and injects itself (game.view = self); binds Game's
     │   reactive signals; buttons + card clicks call Game commands
     │   (submit/next/undo/try_grab/try_place).
     ├─ Game (Levels/game.gd) .. extends CardEnvironment; headless match logic. Mutates
     │   │                       only `state`; zero UI children; every visual touch is
     │   │                       `if view:` (view == null runs a full show — unit-tested)
     │   ├─ state : GameData ... PURE DATA (Resource): draw/discard/rules decks,
     │   │                       upper/lower zones (columns of stacks), score arrays,
     │   │                       goal/total, submits_used, combo_classes.
     │   └─ save_history ....... Array[GameData] saveable snapshots -> undo AND the
     │                           persisted run.game_history (survives quit)
     └─ PlayArea (UI/play_area.gd, %PlayArea)
         ├─ builds a Control grid mirroring GameData zones (board_changed -> queued rebuild)
         ├─ maps: ui_data (Control->CardData), data_ui, data_card (CardData->CardVisual)
         └─ CardVisual (Cards/card_visual.gd, Node2D) — lives on %CardLayer INSIDE the
             scroll content (sibling of PropLayer), so scroll carries controls, cards,
             and props together. Cards clip at the play-area rect.

CardEnvironment (Scripts/card_environment.gd, @abstract, base of Game)
 ├─ static CURRENT ............. "the environment on screen" pointer (read at boundaries)
 ├─ run_all_mods(fn,...) ....... THE event bus (instance method): iterates every CardData
 │                               in play, calls fn on its type/stamp/skill/statuses if
 │                               implemented. Implementer-cache gated: hooks nothing
 │                               implements skip the walk; the on_anything tail fires only
 │                               when a mod actually ran.
 ├─ return_first_*_result ...... same walk, first non-empty answer wins
 ├─ skill_active_check ......... toggles skill.active, fires on_active/on_deactive
 │                               (runs after EVERY mod call — owner ruling, don't batch)
 └─ _compare_implementers ...... comparator/hook implementer cache keyed on
                                 [state id, state.revision]

CardData (Cards/card_data.gd, Resource) — one card
 ├─ suit : PipSuit            rank : PipRank        (the "pips")
 ├─ skill / type / stamp : CardModifier   statuses : Array[CardModifierStatus]
 ├─ stage : {PLAY, DRAW, DISCARD, RULES, ZONE, DATA} + previous_stage
 └─ signals data_changed / stage_changed -> CardVisual updates itself

CardModifier (@abstract Resource)
 ├─ data : CardData ............ WEAKREF-BACKED property (see §6) — the backref cycle
 │                               cannot exist; saves carry no backref
 ├─ CardModifierSkill  (active flag)       e.g. SkillEvalPokerBest, SkillGrabberOgLower
 │   └─ ZoneAdder (@abstract)              adds a zone column while active
 ├─ CardModifierStamp                      e.g. StampDoubleTrigger, StampGlobal
 ├─ CardModifierType                       e.g. TypeInput (draw/drop pipeline)
 │   └─ BoosterTemplate (@abstract)        card-pack generation (map screen)
 ├─ CardModifierStatus                     merge-by-class statuses (Burning, Juggling)
 └─ PipSuit                                suit-as-modifier; dispatched ONLY via
                                           run_card_mods + spawn_props (see §4)

Board (Scripts/board.gd) ....... anchor-based move engine: locate/extract/insert_at/
                                 move_stack/place_card/add_column/remove_column +
                                 MUTATION GUIDELINES header. ALL board mutations go
                                 through Board or Game's draw/discard/deck functions.
GameData.position_of ........... LAZY revision-keyed position index — locate/
                                 find_data_vec3/is_data_topmost are O(1).
PipComparator (static) ......... every rank/suit comparison funnels through here; mods
                                 get asked first (on_compare_ranks/suits), numeric fallback.
Scoring (Scripts/scoring.gd) ... poker-hand evaluation; ScoreModel = the only place hand
                                 score math lives; Scoring.class_key(Result) = combo identity.
RunManager (autoload) .......... run lifecycle, goal curve, fame/luck, threaded save queue.
LeakSentinel (autoload, debug) . quiescent-moment card census (see §6).
```

**Coordinates:** a card's location is `Vector3i(x=0 upper/1 lower, y=column, z=row)`;
`z == -1` = the zone/type header card. `Vector3i.MIN` = not on board.

### 1.3 Key data flows

- **Grab/place:** `PlayArea._on_gui_input` → `GameView._on_data_selected` (guarded on
  `game.processing`) → `Game.try_grab/try_place` →
  `return_first_data_array_result("on_can_grab_stack"/"on_can_place_stack")` — rule cards
  decide legality → `Board.move_stack` mutates GameData → mods fire → `save_state()`.
- **Submit:** `Game.submit()` → `run_all_mods("on_run_scorer")` → `SkillScorerCascadeLower`
  walks lower-zone rows/cols → `SkillEvalPokerBest` → best `Result` → `Game.score_line`
  (data always; paced visuals only `if view:`) → props (§4) → `apply_act_score`.
- **Next:** `run_all_mods("on_next")` → `TypeInput.on_next` per input column: drop upper
  stack into the lower zone, then `draw_card()` refills.
- **Undo:** every action ends in `save_state()` (saveable snapshot + background disk
  save). History is capped: `MAX_UNDO_HISTORY=100` hard, `Game.undo_cap=25` mod-adjustable
  (a mod-raised cap does NOT persist across resume). Full undo/game-over contract: §5.

### 1.4 The mod-hook extension contract

1. Subclass `CardModifierSkill/Stamp/Type/Status` (or `PipSuit`), implement
   `get_str/get_description/get_frame`.
2. Implement any hook: `on_next`, `on_run_scorer`, `on_can_grab_stack`,
   `on_can_place_stack`, `on_card_dropped_on`, `on_stack_cards`, `on_score_row`,
   `on_score_col`, `on_score`, `on_after_score`, `on_trigger`, `on_append`, `on_discard`,
   `on_game_start/end`, `on_compare_ranks/suits`, `on_anything`, `on_active/on_deactive`,
   `on_get_possible_*` (boosters), `on_prop_passing/on_prop_passed` (props),
   `on_mod_triggered`. Dispatch is duck-typed via `has_method` — a typo in a StringName
   silently disables a mechanic; there is no signature check.
3. Attach to a `CardData` in `rules_deck` (always active), or rely on the default-active
   rule: **a play card's modifiers are active while the card is topmost/uncovered**;
   `StampRevealing` overrides covered, `StampGlobal` is active from anywhere (incl. decks).
4. `combo_key(hook)` on the modifier controls combo participation (§3): default = the
   script path (counts once per act); return `""` to opt out (engine rules mods do).
5. Warnings-as-errors gotchas: class-ref arrays in a func body must be
   `var … : Array[GDScript]` not `const`; duck-typed hook calls on a typed base go
   through `obj.call(&"hook", …)`.

### 1.5 Map, run & persistence layer

```
RunManager (Scripts/run_manager.gd) — owns RunState + all persistence
 ├─ run : RunState — the whole saved document: world_seed, current_node_id, lap, fame,
 │    traveled edges, card_datas/rule_datas (run deck), pending_goal/pending_node_id,
 │    game_history (the in-progress show's undo stack), game_submits, game_history_trimmed
 └─ background save queue: request_save() (coalesced, threaded) / save_run() (sync);
      atomic temp-file rename; _exit_tree() flush.  user://run_save/
Map (Levels/map.gd, extends CardEnvironment) — map screen + booster CardEnvironment
 └─ WorldMapController — WorldMap2D (addon) generate→bake once / reload_from_bake;
      Camera2D pan/zoom/follow; MapPlayerToken walks edge curves;
      MapNodeRoles — deterministic role/goal assignment into node.meta,
      re-derived every populate (NEVER saved — graph.json doesn't round-trip meta)
```

**Flow:** Menu → new_run/continue → Map. Game/boss node → stash `pending_goal` → `Game`
(3 acts/submits); win → `record_win` (fame) at **Continue** → map; loss → run over → menu
(save cleared). Booster node → take-all `ChoiceViewer`. End node = boss; winning flips to
an endless reverse lap on the same graph (even lap forward, odd lap reversed; traveled
history stored in forward orientation).

**Persistence rules (regression-critical — don't reintroduce the bugs):**
- Every committed action saves the whole run including undo history (anti-cheat: closing
  can't rewind). The run deck is cached; re-copied only on `mark_deck_dirty()`.
- `ResourceSaver.save` picks format from the EXTENSION — the atomic-write temp file must
  be `run.tmp.tres`, never `run.tres.tmp` (fails `ERR_FILE_UNRECOGNIZED`, silently writes
  nothing).
- `has_save()` gates on `run.tres` ALONE — the `map/` bake is a regenerable deterministic
  cache of `world_seed`; requiring it makes Continue fragile.
- `BigNumber` is RefCounted (not serializable): score arrays persist as parallel
  `packed_*_mant` (PackedFloat64Array) + `packed_*_exp` (PackedInt64Array) via
  `pack_scores()`/`unpack_scores()`. Packed arrays are COW value types — assign built
  arrays back, don't mutate a parameter.
- Saves carry NO modifier backrefs: `to_saveable()`/`_to_saveable_cards` null `data`;
  `restore_runtime()`/`_relink_cards` relink after load (shared helpers
  `GameData.unlink_card_backrefs`/`relink_card_backrefs` are THE slot list — extend both
  when adding a modifier slot).
- **Pending-action replay:** Submit/Next persist a `RunState.pending_action` marker with
  the pre-action board before awaiting; killed mid-resolution → `_resume_show` replays
  the action with input locked. Requires those actions stay deterministic (no RNG in
  scoring; draws come from the ordered deck). `save_state` clears the marker on commit.
  ⚠️ **The patience auto-Next is the one case where the marker's board is NOT the Next's
  real pre-action board** (§4e): the emptying move and its auto-Next commit as ONE snapshot,
  so `_begin_action(&"on_next")` persists a history whose top is the board from before the
  MOVE. A kill inside that span therefore resumes by replaying Next on the pre-move board —
  the uncommitted move is lost (consistent with any other in-flight action) but the round
  still advances. Narrow, accepted; do not "fix" it by committing the move separately
  without re-deciding owner ruling A5 (that reintroduces the patience-0 undo state).
- Per-act score gutters reset in `apply_act_score`; their labels only resync via
  `PlayArea.update_score_controls()` (the revision-bump rebuild does NOT touch them).
- Loading `.tres` from `user://` can execute embedded script paths — standard Godot caveat.

### 1.6 UI layer facts

- Card viewers = a container + a `CardsViewer` (`UI/cards_viewer.gd`); `ControlCard` is
  one card. Roots differ (CanvasLayer/Control/PanelContainer) so no shared base class.
- CardVisuals add via `call_deferred` — a freshly built board isn't animatable for a
  frame; resume waits on `PlayArea.board_visuals_ready` before replaying an action.
- **Multi-modal input is a hard project rule:** every UI works with mouse + keyboard +
  controller; modals steal focus and restore on close; `ui_cancel` closes; selectable
  elements are focus stops.
- Card text surface is the **focus inspector panel** (permanent OverlayLayer child,
  re-pinned per frame); native tooltips were removed deliberately (they blocked clicks).
- Board draw order is 100% structural (no z_index anywhere) — see LAYERING.md.
- ⚠️ **Board controls are POOLED per slot** (`PlayArea.set_card_zone` creates/frees Controls
  per column/row index and `_bind_slot` rebinds them to whatever CardData now occupies the
  slot). Therefore **any per-card control property must be re-derived in `_bind_slot`, never
  just set-and-later-unset.** `mouse_filter` broke this rule: `grab_cards` set
  `MOUSE_FILTER_IGNORE` and only `ungrab_cards` cleared it — by the card's NEW position — so a
  rebuild while a grab was live (auto-Next, §4e) stranded the filter on a control that then
  belonged to a different card: one permanently uninteractable card per auto-Next, surviving
  undo, healed only by a restart (owner bug 2026-07-20). Pinned by INTERACTION's
  `test_auto_next_leaves_no_dead_controls`. Game also tells the view to `release_grab()`
  before an auto-Next, so the board never mutates under a live grab in the first place.

---

## 2. THE MOVE ENGINE (Board)

`Scripts/board.gd`: destinations are **anchors** (card references), not indices —
`OnTop(card)` / `ColumnEnd(x,col)` / `ColumnStart(x,col)`. Four phases strictly ordered:
RESOLVE (read-only) → VALIDATE (read-only; rejected moves leave the board bit-identical)
→ MUTATE (extract + insert; anchor resolved AFTER extraction) → NOTIFY (events fire on a
consistent board). Policies (all pinned by Tests/Engine/test_board.gd): dest inside the
moving stack = `ERR_DEST_INSIDE_STACK`; same-position drop = `OK_NOOP` (no events);
`on_card_dropped_on` receives the real landing card.

**Invariants** (`GameData.validate()`, debug builds + fuzz suites):
I1 every card in exactly one container; I2 zone/zone_type lockstep; I3 stage matches
container; I4 position index agrees with a full rescan; I5 no null entries.

**MUTATION GUIDELINES (sacred — a miss = stuck UI + stale caches + stale positions):**
- All board mutations go through `Board.*` or Game's draw/discard/deck functions.
- Every mutation bumps `GameData.revision` AFTER the state is consistent. The bump drives
  the coalesced PlayArea rebuild, keys the compare-implementer cache, AND invalidates the
  lazy position index (`position_of`) — a missed bump now returns STALE positions, not
  slow-but-correct scans.
- `revision` is ALSO the change detector for commits (2026-07-20): `Game._last_saved_revision`
  holds the revision the last committed snapshot carried, and `save_state()` RETURNS EARLY
  when they match. So a legal-but-`OK_NOOP` placement pushes no undo entry ("an undo that
  visually does nothing") and does not advance the committed-action count
  `history_trimmed + save_history.size()` that `entity_side_for_row` hashes. The `state`
  setter resets the baseline to -1 (a swapped-in state is uncommitted until proven otherwise);
  `undo()`, `_restore_pre_act_board()` and `_resume_show()` re-baseline explicitly right after
  assigning, because those boards ARE history's top. **A mutation that forgets its revision
  bump now also loses its undo entry.**
- Anything reading PlayArea's `ui_data`/`data_ui`/`data_card`/control tree calls
  `flush_rebuild()` first.
- Statuses/mods must not call `move_data_*`/`discard_data` from hooks dispatched by
  `run_all_mods` (live iteration, §8) — defer via a queued action. Always
  `duplicate()`/`.new()` a status at the point of application (`ModsList` holds shared
  singleton instances; `add_status` defensively duplicates foreign-`data` statuses).

---

## 3. SCORING & GOALS (settled design; formerly SCORING_MATH_PLAN §15 / SCORING_IMPL_PLAN)

Implemented 2026-07-17. `tools/scoring_sim.py` is the calibration oracle
(`py tools/scoring_sim.py --final --q 0.35`); re-run and re-fit `goal_g0`/`goal_alpha`
whenever deck/booster content changes. Do NOT touch `Scoring.ScoreModel` hand formulas
casually — `test_scoring.gd` SECTION 8 leaderboard pins them.

### 3a. Act scoring (§15a — code comments cite this section number)

```
act payout = row_total × col_total × combo        (rounded ONCE per act payout)
combo      = 1.0 + combo_step × U                 (resets every act; combo_step = 0.1)
U          = distinct meld CLASSES scored this act
             + distinct mod effects on their FIRST activation this act
```

- **Meld class** (`Scoring.class_key`) = archetype + sub-hand size + copy count, with
  flush-variant flags (`:FF`/`:MF`). Rank and suit do NOT differentiate. Lone high cards
  never enter U. Duplicate-class melds still score base — they just don't raise U.
- U lives on **GameData** (`combo_classes : Array[String]`) so undo/act-cancel/replay
  reset it for free — the same reason `submits_used` lives on GameData: **any per-show
  counter that undo must rewind belongs on GameData, not Game.**
- `Game.register_combo(key)` is idempotent; empty keys never register. Mods feed U via
  the `_note_mod_fired` dispatch hook + explicit `register_combo(combo_key())` calls at
  prop/status `add_line_score` seams.
- Fallback lever δ (`duplicate_class_scale`, ships 1.0 = off): duplicate-class melds
  score ×δ — only lower if playtest shows dumping crushes everything.
- `score_additive` (ships OFF): payout = `(R + C) × combo` instead — flips par policy to
  even play at small decks; needs `goal_g0≈43, goal_alpha≈0.48` retune to playtest.
- UI: combo label inside `%MultScore` (hidden at x1.0, empties after payout), pulses on
  `combo_changed`.

### 3b. Goal curve (§15b)

```
goal(node) = G0 × (N̂(node)/N0)^ALPHA × difficulty × BOSS_MULT^is_boss × LAP_MULT^lap
N̂(node)   = N0 + BOOSTER_YIELD × boosters_on_path(node)
```

- Goals scale with **opportunities** to grow (booster nodes on the path), not purchases —
  skipping boosters leaves you under the curve; that is the pressure.
- Calibrated: `N0=20, G0≈130, ALPHA≈4.2, BOOSTER_YIELD=5` against the 20-card start deck
  (`deck14`: ranks 1–5 × 4 suits, no talents).
- **Monotone clamp** per path in `MapNodeRoles` (a spread extension can weaken par play;
  the ladder must never descend). Boss ≥ every game goal of the lap.
- `difficulty` is THE run-win-rate dial (±15% ≈ one persona band); future per-player
  difficulty ships as opt-in tiers (Stakes-style), never automatic in-run adjustment.
- **Overscore is retired — a standing design ruling:** punishing overperformance breeds
  sandbagging (Oblivion/Homeworld precedent; the sim confirmed skilled play became
  self-defeating). If in-run responsiveness is ever wanted, scale REWARDS, never goals.
  `LAP_MULT^lap` is the owner-required endless pressure; the victory-lap stretch before
  the wall is intended feel.
- All balance knobs live in `Scripts/player_settings.gd` "Balance —" groups, read live
  via `SettingsManager.settings` (combo_step, duplicate_class_scale, score_additive,
  difficulty, goal_g0/alpha/n0, booster_yield, boss_mult, lap_mult, luck_cap, fame_half).
- Fame: `record_win` banks the full total as fame; fame → `luck()` (saturating) gates
  booster stamp/skill/type rolls. No real rarity system yet.

Open playtest questions (not decidable in the sim): arrangement capacity reality (decides
where in the 1.0–1.6 dump-vs-even range the game sits), difficulty default, combo_step
0.1 vs 0.2 feel, mod-activation U generosity, Burning/prop cascades as a combo source,
the δ trigger, spread-extension boosters as archetype pivots.

---

## 4. SUIT PROPS & STATUSES (formerly PROPS_BUGFIX_HANDOFF / SUIT_PROPS_PLAN)

Suits are prop-spawners: a scored card's suit fires **once per meld membership** (row and
column each). A talented card (`data.skill`) suppresses its OWN suit effect. Suits are
**nominal** — construct the exact class (`PipSuitHoop.new()`, …) or index
`PipSuit.STANDARD = [Hoop, Knife, Ball, Fire]`; Firework is special/excluded (never
rolled randomly; `deck12` is its only grant path). There is no suit ordering and no
`from_index` — deliberately deleted.

**Behavior:** Hoop sweeps its row scoring talents; Knife mirrors from the opposite edge
scoring plain cards (self-scores its spawner by design); Ball/Fire are ballistic (mancala
walk picks targets at spawn) dropping Juggling/Burning statuses; Burning multiplies the
target's own suit-effect count (the same-act fire cascade — row-scored Burning buffing
later columns — is intended); Firework rises its column and banks column score.
Side/target picks hash resume-persisted state (`entity_side_for_row` hashes
`game_history_trimmed + size` — replay-stable, no RNG). Props are transient (`PropData`,
never serialized); a quit mid-act replays the act from the pre-act board.

### 4a. Architecture in 6 lines

- `Game.run_props(spawners)` (game.gd) — the DATA simulation: integer ticks, one step
  AHEAD of the view. Per tick: SPAWN → MOVE → `view.begin_prop_tick(...)` (NOT awaited) →
  EVENTS (3-phase pass per mover: `on_prop_passing` (card, may `negate_pass`) →
  `on_pass_card` (prop, the effect) → `on_prop_passed` (card, always)) → FINISH →
  `skill_active_check` → `if view and view.prop_tick_pending(): await tick_done`.
  Runaway caps: `MAX_TICKS` (2048) + `act_event_cap` via `note_processing`.
- Emission order IS hook order (`live_props` is an Array — the determinism guarantee).
  Prop behavior = composed `PropModifier`s; spawn plans = `PropSpawner`
  (origin/remaining/batch_size/interval/max_live/factory — factory is PURE, routes
  precomputed at spawn-plan time). Score writes go through `add_line_score` (the single
  line-score write path; gutter points ARE multiplied by the opposite axis).
- `PropLayer` (UI/prop_layer.gd, Node2D inside the scroll content) — ALL prop animation:
  per-frame interpolation against the LIVE tick seconds
  (`game.get_delay() * prop_tick_fraction`, re-read every frame), spawn/teleport/void
  exits, formation offsets, card reactions. Every visual carries an `anchor_coord`
  re-pinned to live slot geometry per frame (relayout-proof).
- `PlayArea.slot_center_global(v)` = PURE MATH (zone hbox origin + column/row pitch +
  half card size; NO control reads — control rects zig-zag and must never come back).
- `PropVisual.travel_curve(a,b,u)` = THE one movement function (lerp minus
  `arc_height·4u(1-u)`); kinds differ only by `arc_height` and `_draw_body`.
- Statuses (`CardModifierStatus`) merge by class, self-scope targeted hooks
  (`if target != data: return`), draw via `StatusLayer` (runtime CardVisual child).

### 4b. Landmines (check FIRST for any prop/UI bug)

1. **SmoothScrollContainer rewrites every entering Control to `MOUSE_FILTER_PASS`** —
   display-only Controls under the scroll content MUST
   `set_meta("_smooth_scroll_default_mouse_filter_set", true)` BEFORE `add_child`.
2. **The play-area rect clips** everything (cards AND props). Off-rect staging/exits are
   invisible; staging is compressed to ≤ ~1.5 slot pitches behind the route entry. If
   props "disappear", suspect clipping before code.
3. **Never read control rects for slot geometry.** A fanned card is a full card TALL
   behind its visible strip — "which card is under this point" picks wrong rows. Use the
   prop's anchor slot + `body_size` overlap (`_apply_split`/`_body_over_any_card`); the
   hoop's bracket row = its ANCHOR SLOT row, geometry only decides WHETHER to split.
4. **`tick_done` is a persistent signal** — await only while `view.prop_tick_pending()`.
5. Per-show counters undo must rewind live on GameData (see §3a).
6. Despawn is kind-dependent: route travelers exit one slot pitch along their travel line
   (re-pinned, never a fixed-pixel tween); ballistic props poof in place.
7. Props with `ticks_per_slot > 1` move CONTINUOUSLY via `span_ticks`/`t_goal` ratchet.
8. The focus inspector panel is a permanent prop_layer child — keep it
   `MOUSE_FILTER_IGNORE`/`FOCUS_NONE` + the addon meta; never reparent under controls.
9. The spin reaction is an INFINITE tween — never `custom_step(INF)` it; its revolution
   time floors get_delay() at 0.2s (zero-duration looping tweens trip Godot's guard).
10. Only talents jump/spin (reaction hooks key on `card.skill`); an all-talent suit
    spawns nothing (suppression) — deck9/deck10 show zero hoops BY CONSTRUCTION.

### 4c. Formations & knobs

Per-kind spawn patterns: `PropFormationData`/`PropFormationSet` loaded from
`Cards/Props/Formations/<kind>.tres`; missing file = slot-line flight. Points are stored
in full-card normalized space (separation-agnostic); offsets are view-only, derived from
LIVE settings every frame; hoops always skip formations (card center). Author via
`Cards/Props/Tools/formation_editor.tscn` (@tool scene, inspector-only).

Timing: `base_delay` (master), `prop_tick_fraction` (seconds per prop tick), per-suit
`ticks_per_slot` (data speed), per-ACTIVATION compression
(`compress_ratio ^ (act_calls/compress_step_calls)`, instant past `compress_soft_calls` —
no wall-clock anywhere; animations retime mid-flight). All knobs + animation flourishes
are PlayerSettings fractions of `get_delay()` — never wall-clock literals.
`PropLayer.manual_step` + GameView debug buttons step prop ticks one at a time.

### 4d. Recipes — "to change X, edit Y"

- New prop kind: `Cards/Props/Visuals/<kind>_visual.gd` + extend `_make_visual`'s match +
  launch from a suit's `spawn_props()`.
- New prop effect: new `PropModifier` (hooks: `on_spawned/on_pass_card/on_finish/
  reaction_for`); score through `game.add_line_score`.
- New card counter-effect: `on_prop_passing`/`on_prop_passed` on a CardModifier.
- Re-route mid-flight: `prop.set_route(...)` / `prop.teleport(...)` from any hook —
  never touch `at`/`route` from the view.
- New status: one `CardModifierStatus` subclass. New suit: one `PipSuit` subclass
  (+ optional visual + palette entry). The tick loop/dispatch/pacing stay closed.

---

## 4e. PATIENCE (idle-move pressure, 2026-07-20)

"The audience won't watch you shuffle the board forever." Per-round counter on **GameData**
(`patience`, `patience_seen_mods`) so undo/history/saves rewind it with the board.

- **Spend point is `Game.try_place` ONLY** — never Submit/Next (owner ruling). A placement
  that actually changed the board either HOLDS the counter (a qualifying modifier triggered)
  or spends one; an `OK_NOOP` placement costs nothing (nothing changed → §2 detector).
- **What "triggered" means:** `try_place` moves with `trigger_mods = false`, so the only
  dispatch a placement performs is the legality query `on_can_place_stack`. That is why
  `_note_mod_fired` fires from EVERY dispatch path (`return_first_*`, `run_card_mods`), not
  just `run_all_mods` — ⚠️ landmine: those paths pass `feeds_combo = false`, so they inform
  patience but must never register a §3a combo class. Keep that flag when adding a path.
- Gating: the triggering card's stage must be enabled (`patience_influence_*`, default PLAY
  only), the hook must not be in `patience_disabled_hooks`, and its `combo_key` must be
  non-empty (engine mods opt out of combo AND patience together). With
  `patience_track_uniques`, only the FIRST trigger of a key each round holds — repeats are
  boring. Seen keys clear on Next, or after a Submit with `patience_reset_uniques_on_act`.
- **0 auto-presses Next**, which refills to `patience_max`. The emptying move and its
  auto-Next commit ONE snapshot together (owner ruling A5): patience 0 is never a playable
  board, so undo lands before the move with patience intact and can't buy an extra action.
- Raising `patience_max` mid-round also grants the LIVE counter (`patience_max_increased` →
  `Game._on_patience_max_increased`); lowering it never takes any away (owner ruling A1).
- Patience mutators deliberately do NOT bump `revision` (owner ruling A2 — patience only ever
  moves alongside a real board change). The one exception is a Next on a board where nothing
  moved: `_perform_next` bumps there so the refill still commits.
- The auto-Next fires INSIDE `try_place`, i.e. while the player's grab is still live — Game
  calls `view.release_grab()` first, and see the pooled-control landmine in §1.6.
- View: `%Patience` label in `game_view.tscn` (owner tunes placement in the editor — never
  create HUD elements in code), fed by `Game.patience_changed`. Card descriptions mark each
  modifier `(seen)`/`(new)` inside a show while uniques are tracked (`ControlCard.describe_card`).
- ⚠️ **Known commit gap:** `_perform_next`'s "nothing moved" revision bump is gated on the
  PATIENCE COUNTER changing (`patience_before != state.patience`), not on the seen-set. So a
  Next that only clears a non-empty seen-set — patience already full because every move that
  round was interesting — on a board where `on_next` moved nothing commits nothing, and a
  resume brings the stale seen-set back. Narrow (needs an inert `on_next`); widen the guard to
  the seen-set size if it ever bites.
- Suite: `Tests/Engine/test_patience.gd`.

---

## 4f. BOOSTER REROLLS (2026-07-20)

`ChoiceViewer.Data.rerolls` is ONE shared free-reroll pool for the whole pack, seeded from
`settings.booster_reroll_pool` by `BoosterTemplate.on_map_picked`. `ChoiceViewer.reroll(i)`
re-calls the SAME generator (`create_one_choice`, awaited — it is a coroutine), replaces
`current_choices[i]`, spends one charge, swaps that slot's `ControlCard` in place and grays
every button out at zero. Generation is global-RNG, so a reroll needs no seed handling, and
shown cards persist nothing until Confirm — no save wiring. Multi-modal: the buttons are focus
stops and focus is restored after a swap (to the same slot, or Confirm once the pool empties).
Covered by `Tests/UI/test_ui_viewers.gd`.

---

## 5. UNDO & GAME-OVER CONTRACT

Undo is live in every state; `Game.undo()` dispatches on three:

- **Mid-act cancel:** Undo during Submit/Next resolution sets `act_cancelled` (only
  inside the `_act_cancellable` span). The resolution FAST-FORWARDS (`get_delay()` → 0,
  `score_line`/`_run_score_effects` early-return, `run_props` breaks, manual-step hold
  releases), then `_restore_pre_act_board()` rebuilds from `save_history[-1]` (acts
  commit only at their END). Nothing pops from history. Mods keep mutating the doomed
  state during the unwind — safe, it's replaced wholesale (and deliberately NOT unlinked).
- **Game over:** Undo emits `show_unresolved` (view drops the overlay) then falls through
  to a normal undo of the final Submit. Consequence: **fame banks in `exit_show()`
  (Continue), not `_resolve_game()`** — the win stays undoable, and a quit-at-win-screen
  resume (which re-runs `_resolve_game`) can't double-bank fame.
- Otherwise locked (resume load, replay tail): ignored.

View side: win/lose overlays cover exactly the board (`PlayContainer` Labels + dim,
mouse_filter STOP); Undo never disabled; `PlayArea.disable_board_focus()` strips + LOCKS
card focus (`board_focus_locked` — the final Submit's deferred rebuild would otherwise
re-enable it); `enable_board_focus()` on dismissal.

---

## 6. MEMORY & LEAK RULES (weakref backrefs, 2026-07-18)

- `CardModifier.data` is a **WeakRef-backed property** — the CardData↔modifier RefCounted
  cycle cannot exist; the old unlink-at-every-drop-site discipline is deleted. But:
  **`duplicate_deep` does NOT remap a WeakRef** — every deep-copy site must relink copies
  (`GameData.relink_card_backrefs` per card). Current sites: `duplicate_state`,
  `add_deck`, `new_run`, deck_builder preview. **Add any new deep-copy site to that
  list** — a missed relink = modifiers pointing at the ORIGINAL cards.
- Saves stay backref-free (`to_saveable`/`_to_saveable_cards` null `data`); relink after
  every load.
- `Scripts/leak_sentinel.gd` autoload (debug builds): quiescent-moment alive-vs-reachable
  card census; push_errors a stage/modifier histogram naming any leak source. Knobs in
  player_settings.gd; quiet under the test runner.
- Regression net: `Tests/Engine/test_leak_canary.gd` — bare Game cycles + the PRODUCTION
  SESSION CANARY (full simulated session per cycle, asserts OBJECT_COUNT returns to
  baseline). Runs LAST and ALONE (OBJECT_COUNT is engine-global). Owner ruling:
  test-only leaks do not matter; production coverage is what counts.
- Anywhere a modifier/status is held WITHOUT its card, the weakref lets the card die
  early — such a holder must keep the CardData itself.

---

## 7. TESTING

Run: `Godot --headless --path solatro res://Tests/all_tests.tscn` — exit code = failure
count; the bar is ALL suites green (count the run's own banner; 25 as of 2026-07-20 —
PATIENCE joined, and it runs unordered like the other engine suites).
Check TOTALS vary run-to-run (fuzz suites) — **compare failure sets, not counts.** Never
run headless while the owner's editor has the project open (see START_HERE.md).
Environment traps (stale class cache, frame_post_draw, headless window size):
**HEADLESS_TESTING.md**.

Conventions (formerly UNIT_TESTS_PLAN):
- Every suite extends `Tests/Support/test_base.gd` (`SolatroTest`); non-freezing
  `check(ok, ctx, detail)`, never `assert()`; each suite ends with `finish()`.
  Checks are tagged BEHAVIOR (what the game does — a failure means the game is wrong or
  a rule changed on purpose) vs IMPLEMENTATION (pins how — may just be a stale pin after
  a refactor) via `behavior_section()`/`implementation_section()`.
- **`await` every coroutine test function** (unawaited sections race the summary).
- Fuzz tests take a seed, print it on failure, reproduce with `seed(reported_seed)`.
- **⚠️ THE DEADLOCK RULE** (`Tests/Support/test_base.gd`): suite ordering uses
  `await_siblings_except` — waiting is a directed dependency; excludes must stay
  consistent across ALL suites or the run hangs. Chain: everything else → INTERACTION →
  UI PROPS → E2E → LEAK CANARY (last + alone). A new suite name needs the same exclude
  treatment everywhere.
- **Tests never ride `Decks/deck.gd`** (the owner's freely-changing playtest deck) —
  frozen compositions live in `Tests/Support/test_decks.gd`; existing TestDecks functions
  are replay contracts — add new ones, never edit. Shared factories:
  `Tests/Support/test_factories.gd`; fake env: `Tests/Support/fake_environment.gd`.
- Disk tests use `SolatroTest.backup_real_save()`/`restore_real_save()` — never a
  save-existence `[SKIP]` guard. Suites that touch settings back up `settings.tres`.
  Settings isolation is TWO paired steps (`SettingsManager` writes `settings.tres` on EVERY
  knob write, so a suite that scribbles on the live resource is editing the player's real file
  line by line):
  1. `backup_real_settings()` / `restore_real_settings()` PARK the real file for the suite's
     duration, so every write lands in a throwaway and an aborted run can never strand the
     player's knobs. The backup name is per-suite (`suite_name()`) and self-healing on the next
     run — a single shared path would let concurrent suites swallow each other's parked file.
  2. `snapshot_settings(prefix)` / `restore_settings_snapshot()` put the LIVE resource back for
     later suites. ⚠️ **Scope the prefix to the knobs your suite owns** (`"patience_"`,
     `"booster_"`): suites that don't `await_siblings_except` run CONCURRENTLY against ONE
     shared PlayerSettings, so restoring a full snapshot stomps another suite's in-flight
     knobs. Only a suite that waits for its siblings (INTERACTION) may snapshot everything.
- Test speed: `all_tests.gd @export speed_base_delay` → `TestLog.speed_base_delay`;
  deliberately-slow sampling tests keep their own absolute delays (they need real
  frames).
- Interaction suite: every event goes through `Input.parse_input_event` — window
  coordinates, not canvas (`to_window()` helper; headless window is (0,0)).
- Leak attribution: `Tests/Support/leak_probe.tscn -- <suite.tscn>` runs one suite and
  quits; exit-leak count attributes per suite.
- The prop flight-sampling pattern for "prop moved weirdly" reports:
  `test_ui_props._sample_flight` — continuous per-frame sampler against a row band +
  x-span envelope with a mid-flight relayout poke. Extend it, don't invent new rigs.

---

## 8. SHARP EDGES & OWNER RULINGS (do not "fix")

Standing owner rulings:
- **B10:** `run_all_mods` iterates LIVE collections mods may mutate — by design; no
  snapshotting. (Hence: no board mutations from broadcast hooks — defer.)
- **S6:** same-value `stage` re-sets DO re-emit `stage_changed` — relied upon.
- **N8:** score arrays never shrink on zone removal — desync allowed so scores are never
  lost.
- **skill_active_check runs after every mod call** (not batched per event) — skills whose
  conditions become true must trigger immediately.
- **Commented-out code policy:** TODO comment if it refers to unimplemented logic, delete
  if the implementation exists elsewhere. (`##` purpose comments on methods.)
- `Game._restore_pre_act_board` deliberately does NOT unlink the doomed state.
- Player drops move with `trigger_mods = false` → `on_card_dropped_on`/`on_stack_cards`
  fire ONLY from automated moves (TypeInput).
- The Deck Maker (`UI/deck_builder.gd`) is kept for a future refactor despite being
  orphaned.

Sharp edges:
- `stage` does triple duty: logical location, animation origin (`previous_stage`), S6
  re-emit channel. Re-setting an already-correct stage clobbers `previous_stage` and
  kills spawn/tween animations.
- First-implementer-wins mod dispatch precedence depends on board order.
- GDScript declaration-default values BYPASS property setters (wire initial signals in
  `_ready`).
- **Godot key/joypad events reach ONLY the focused control — they never bubble.**
  Board-wide keyboard/controller handling belongs in `_unhandled_input`.
- `ui_accept`/`ui_cancel` are OVERRIDDEN in project.godot to add joypad A/B; overriding a
  built-in ui_* action REPLACES its defaults, so the overrides re-list the full keyboard
  set — keep that when editing the input map.
- `String.contains("")` is not reliably true; GDScript lambdas capture locals by value
  (mutate shared reference types in place).
- Anything fetched from `WorldMap2D`: the controller pins `overlay.z_index = 1` (child
  order isn't reliable). Never `bake_to_files()` after `reload_from_bake()` (corrupts
  graph.json); bake once after initial generation, then `release_generator()`.
- Deterministic Submit/Next is load-bearing for pending-action replay AND prop-side
  hashing — do not introduce RNG into act resolution.
