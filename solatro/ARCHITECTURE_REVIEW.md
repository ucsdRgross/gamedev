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
   (re-pinned, never a fixed-pixel tween); ballistic props poof in place. **The exit fade runs
   ALONG the leg** (`prop_exit_fade_share`, alpha driven from `t` in `_drive_exiting`), never as
   a tween after arrival — the void point is past the clipping rect (landmine 2), so a fade that
   started there played entirely off-screen and the prop read as vanishing. **In-place flourishes
   have a real-seconds floor** (`PropLayer.MIN_FLOURISH_SECS`): nothing awaits them, and at
   `base_delay = 0.1` a 0.12 fraction is 12 ms — under one frame.
7. Props with `ticks_per_slot > 1` move CONTINUOUSLY via `span_ticks`/`t_goal` ratchet.
8. The focus inspector panel is a permanent prop_layer child — keep it
   `MOUSE_FILTER_IGNORE`/`FOCUS_NONE` + the addon meta; never reparent under controls.
9. The spin reaction is an INFINITE tween — never `custom_step(INF)` it; its revolution
   time floors get_delay() at 0.2s (zero-duration looping tweens trip Godot's guard).
10. Only talents jump/spin (reaction hooks key on `card.skill`); an all-talent suit
    spawns nothing (suppression) — deck9/deck10 show zero hoops BY CONSTRUCTION.
11. **The hoop rides ONE CARD-JUMP above its slot centre** (`PropVisual.rides_card_jump` →
    `CardVisual.card_jump_rise_play`, applied through the live lane offset), so a card that
    jumps lands its centre exactly in the ring — the card jumps INTO the hoop (owner
    2026-07-28). `CardVisual.CARD_JUMP_RISE` is the ONE source of that number: `anim_jump`
    tweens it and PropLayer reads it. Hardcode it in either place and the card jumps through
    the side of the ring. So a hoop's resting position is NOT its bare slot centre — tests that
    assert a landing point must add the visual's own `lane_offset`.

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

## 4g. VISUAL EFFECTS — the shader FX layer (2026-07-27)

**Picking up visual-effects work? Start at [VFX.md](VFX.md)** — the map, the runbook, the open
backlog and the known bugs. This section is the CONTRACT it sends you to; the two are not copies of
each other.

Status effects render as pixel-art shader quads. `res://Shaders/` holds the programs and the
style/spec `.tres` presets; `res://UI/Fx/` holds the code. **Draw placement and the
no-rotating-grid rule live in [LAYERING.md](LAYERING.md)** — this section is the contract.

**The emitter/effect contract.** Emitters (a card silhouette, a ring, a blade, a juggled ball) are
shapes on screen; effects (fire today, frost later) decorate them; emitters NEST — a card's
Juggling status produces ball emitters, and a ball is itself an emitter fire can decorate. Adding
an effect is one `.gdshader` + one `FxStyle` preset. Adding a prop shape is one branch in
`shape_radius` plus one `fx_shape()` override. Neither touches the other.

**Statuses declare their own FX** via `CardModifierStatus.fx_request() -> Array[FxRequest]`,
mirroring `draw_icon`. `FxAttachment` renders requests and never learns which effects exist, so a
new visual status is a new class and nothing else. `StatusJuggling` returns TWO (its balls, and
the fire riding them), which keeps the dependency inside the one class that owns both.

**Rules that prevent regressions:**

- **Shared `Shader`, per-node `ShaderMaterial`.** Never `.duplicate()` a shader — that recompiles
  the program per card. `FxAttachment.warm()` pays every first-use compile up front.
- **The clock is script-driven**, accumulated as `delta * FxAttachment.pacing()`. Never the shader
  built-in `TIME`: it is wall-clock, ignores the act-compression ramp, and keeps running through a
  paused SceneTree. Transition length is `delay * prop_tick_fraction * fx_transition_fraction`,
  re-derived live from the Game (never through `play_area.prop_layer` — a viewer card has none and
  must ease exactly like a board card).
- **`u_count` is a FLOAT.** It partitions the emitting width into n cells, so an integer step from
  3 to 4 re-partitions the width and teleports every existing flame. Tweening the stack count is
  not enough; the count itself has to be continuous. Reaching zero FADES before the quad is freed.
- **Nothing ever freezes** for grabbed / held / hovered / mid-move / mid-flip. Pacing only scales
  the clock, never zeroes it.
- **One shared phase clock per host.** The balls quad and the ball-fire quad read the same
  `_phase` and the same geometry from one `FxJuggle.geometry()` call, and both call
  `fx_ball_at` from `fx_common.gdshaderinc`. Two copies of the arc maths is the bug that makes
  flames trail their balls by a frame — the shared include prevents it structurally.
- **FIRE IS THE ART'S MASK, RAISED — and that is the whole emitter** (owner design 2026-07-30,
  "raise the mask"; it replaces the contour/skirt model whole). Per fragment:

  ```
  floor(x) = the surface this column stands on, eroded by `sink`   — ONE down-march
  top(x)   = floor(x) - height * dome(u(x))                        — the ogee, art y up = minus
  fire(p)  = top(p.x) <= p.y <= floor(p.x)
  ```

  Everything the old model needed a special case for falls out of that:
  - **EVERY upward-facing surface burns, anywhere in the art.** The test is local and vertical, so
    the hoop's inner-bottom arc — the floor of the ring's hole, which faces up — lights from the same
    code that lights the outer top arc. A per-column CONTOUR can only ever return the topmost surface
    in a column, and the skirt's angular cut discarded the rest by construction: *"having it check
    the top half of the image is insufficient because what if there are also top sections in other
    parts of the image, like bottom top of the hoop"* (owner). **"The surface faces up" is the
    definition; "the top half of the image" never was.** Pinned by
    `test_pixels.test_every_upward_surface_burns`, which fails against everything shipped before it.
  - **1 STACK = 1 TENDRIL PER SURFACE**, with no segment finder and no second mechanism: each column
    simply grows a flame on whatever it has, so a ring gets one crown on its top arc and another on
    its inner-bottom arc.
  - **NO ENORMOUS FLAME** (owner: *"no enormous flame allowed"*), structurally: a flame is exactly
    `height` long in every column on every shape, so one can never leap the hole in a ring. The same
    PIXELS check asserts the hole's middle stays empty.
  - **TIPS POINT UP BY CONSTRUCTION** (ruling 1) — because the march is WORLD-down, not because of
    any per-shape branch. A rotating host turns only the mask LOOKUP (the no-rotating-grid rule).
  - **Shape following is IN the shader.** Nothing is baked at `_ready`, so a host that turns cannot
    emit off a stale outline — *"which has chance to fail if object rotates maybe"* (owner).
  - `sink` is now an **EROSION of the mask**, not an offset added to a contour: the base is the
    surface plus `sink`, and a fragment already inside the art is lit only while it is within `sink`
    of the surface above it. Same knob, same meaning, honest implementation.
- **⚠ THE PER-CELL ANCHOR WAS MEASURED AND DROPPED — the owner's pre-ruled fallback, not an
  omission.** The design also called for the arch to be anchored ONCE per cell at the highest surface
  in it (three more down-marches, and they must start above the whole shape: an anchor that depended
  on the fragment's own height would differ down a column and tear the flame). Measured on the target
  integrated GPU with `Tests/Visual/fx_cost.tscn`, 20 burning hosts:

  | ×20 hosts | shipped contour | mask shift | mask + anchor |
  |---|---|---|---|
  | hoop | 0.67 ms | 1.21 ms | **22.52 ms** |
  | card | 1.13 ms | 1.53 ms | 1.81 ms |
  | knife | 0.64 ms | 0.36 ms | 0.62 ms |

  21 ms on the one shape it exists for — more than a whole 60 fps frame, for 20 props and nothing
  else on screen. Owner ruling given in advance: *"If not possible without performance drop, then
  dont do engulf trick with height checking and just stick with mask shifting to find bases."* So it
  is dropped WHOLE rather than approximated at reduced sample counts, which is what produced the two
  builds the owner rejected. **What goes with it is ENGULF** — a flame no longer drapes down to a
  lower surface in its own cell — and the arch now RIDES the surface it stands on, so on a steep flank
  it is shorter. Nothing is ever tilted or sheared: `rise` is a world-vertical distance and the ogee
  is evaluated in world x. **Do not re-propose the anchor without a new measurement.**
- **`mask()` IS THE ONE EXTENSION POINT: one branch per shape, and BALLS is one of them.** Analytic
  for the kinds that have it (`SHAPE_BOX`, `SHAPE_RADII`, `SHAPE_BALLS` — a card should not pay a
  texture tap for a step function); an **ALPHA SAMPLE of the sheet** for `SHAPE_SPRITE`, which is
  every textured prop kind, the hoop included. The sprite mask is what retires `Shape.PROFILE` and
  its baked per-column table, and it is the only representation that knows a ring has a HOLE.
  `measure_sprite_silhouette` survives only to tighten `body` to the art's bounding box — a frame is
  mostly transparent padding, and a comb spanning the frame put flames in empty space beside the
  blade.
  - **NO BALL SPECIAL CASE. `u_mode` and `MODE_BALLS` are deleted** (owner 2026-07-30: *"fire effect
    should be unified and identical in how it treats everything, so no special ball case"*). A ball
    is a `Shape` whose mask is the union of the discs, positioned from the same `fx_ball_pos` in the
    include, and the march / comb / ogee / onion shells / ramp above it are literally the same code a
    card runs. `FxRequest.shape` is how ball fire says "my mask is the balls, not the card I ride on".
  - **`mask()` returns the LEVEL of the surface it hit**, which is ruling 21 as one rule instead of
    two code paths: a silhouette answers `u_level`, a ball answers its own texel from `u_ball_fire`.
    ⚠ **`MASK_DARK` IS GONE (2026-07-31).** It was solid-but-unlit, so an unlit ball occluded without
    emitting (ruling 3) — and it was half of why a lit ball's plume disappeared and came back: an
    unlit ball won the one-ball-per-fragment lookup, the march reported "solid, emits nothing", and
    the fragment was forced dark. Fire resolves the nearest **LIT** ball now (`lit_only` in
    `fx_nearest_ball`), so an unlit ball is never the answer here and the sentinel has no producer
    left. Ruling 3 still holds where it matters — an unlit ball emits nothing and is dark because of
    it; what was given up is its occlusion of a plume passing behind it, which the owner pre-ruled as
    the cheaper of the two (FX_HANDOFF §2).
  - **The nearest ball is resolved ONCE per fragment and handed to every mask lookup.** The
    closed-form ball lookup is by far the most expensive thing in the file and a march never leaves
    its column, so re-running it at every march step would cost more than the whole rest of the
    shader.
- **ONE COMB across the host's silhouette — and ONE FLAME PER BALL, anchored to the ball.** The comb
  divides the host's bounding box AT THE LIVE ROTATION into `u_count` cells (a uniform cannot carry
  that width: a 90-degree-rotated card combed across its unrotated width left a third of its edge
  bare). `u_count` means TENDRILS on every quad, and the ball count rides as its own uniform.
  - ⚠ **A BALL IS NOT A CELL OF THAT COMB, and pretending it was is the whole of FX_HANDOFF §2**
    (fixed 2026-07-31). `u_emit_width` used to TILE the comb at ball pitch, on the reasoning that
    each ball would catch roughly one cell. But a comb is anchored to the QUAD and **a ball moves**:
    which cell a ball caught changed as it flew, so its flame changed identity (and with it its
    desync phase and flicker), and it thinned to nothing whenever the ball crossed a cell boundary,
    where the arch's own outline is zero. Worse, `tendril`'s grow-in ramp — `(id >= floor(cells)) ?
    fract(cells) : 1.0`, which is a SPANNING comb's rule and only a spanning comb's — read `cells = 1`
    on the tiled ball comb and multiplied the flame height by **zero** for every cell past the first:
    a ball's plume died the moment it travelled right of the quad's centre and came back when it
    crossed to the left. That is the owner's *"fire on balls sometimes disappears, then reappears
    later"*, and `06b_ball_fire_cycle` is the shot that shows it (a single frame never could).
    A ball's arch is anchored to the ball's own snapped centre now, `u_emit_width` is just how wide
    it is (one diameter), and `grow`/`fan` are passed in by the caller rather than derived from a
    comb the ball is not in.
  - ⚠ **`fire_ball.tres`'s `merge = true` and `base_width = 2.0` were workarounds for that straddle**
    — with the plume beside its ball, merge fused the two half-cells and a double-wide base covered
    the gap. Both are now inert or overwide: merge is skipped for balls (a ball has no neighbouring
    cell to fuse with) and `base_width 2.0` makes a flame twice its ball's width. They are ART
    numbers, so they are left for the owner rather than retuned here.
- **The mask MIRRORS with the art.** `FxAttachment.flipped` tracks `PropVisual.face_travel`, because
  the mask IS the drawing now — a blade heading right would otherwise emit off the outline it no
  longer has. One sign, re-pushed only when it actually changes.
- **Embers come off EVERY fire, and their spec is split per host scale** (owner 2026-07-29: *"all
  fire effects should leave embers like card is currently"*). `ember.tres` is card-sized;
  `ember_prop.tres` serves props AND balls — ParticleEngine is a board-level node, so a spec's sizes
  and speeds are SCREEN units and the card's ember is ~2.5x too big beside a knife. Data, not a code
  path: there is no per-host scaling anywhere in the emitter.
  - **BALL embers spawn on the BALL, and that is why `FxJuggle.ball_pos` exists.** The host of ball
    fire is the CARD, so the host-top-edge spawn every other effect uses would pour embers off the
    card while the flames are out on the balls. Embers are PARTICLES — spawned by GDScript into
    world space — so the shader cannot answer "where is the burning ball" at all. `ball_pos` is
    therefore the ONE script-side copy of the path, and nothing else may call it. The drift is pinned
    rather than warned about: `test_ball_pos_matches_the_oracle` holds it to `PixelProbe.ball_positions`
    (transcribed from the spec, not from the include), which `test_pixels.gd` holds to the rendered
    frame — so disagreeing with `juggle.gdshader` fails headless in milliseconds.
  - The sources are the LIT balls, not the ball count (`FxRequest.lit`, built beside the fire
    texture from the same levels). An unlit ball is not on fire and has nothing to shed (ruling 3).
  - `fx_snapshot`'s `09_embers` is the visual proof, and it is the one shot that RUNS LIVE: particles
    are spawned at random times and simulated forward, so there is no clock to park and a single
    frame of a fresh attachment has emitted nothing. Like `02_fire_rotation` it is for EYE review, not
    for diffing.
- **Fire is OPAQUE over its host; `sink` is the knob for how much art it covers.** Every shipped
  style sets `inner_alpha = 1.0` (owner 2026-07-29: seeing the card through the flame "looks very
  bad"). `FxStyle.sink` is how far the base goes DOWN into the art — positive sinks it in and
  guarantees no seam, 0 plants it on the contour, negative lifts it clear so the flames cover
  nothing. Reach for `sink`, never for the alpha.
- **⚠ `base_width` MUST exceed 1.0 or every tendril is an island.** A tendril's dome reaches exactly
  zero at its cell boundary, and so does its neighbour's — so at `base_width = 1.0` there is a
  guaranteed hairline of zero heat at every seam, at every height, which the ramp's transparent cut
  widens into a visible gap. Measured at 12 stacks: 13 separate segments with 1–9 px between them
  right down to the base. **`u_merge` cannot fix it** — `max(0, 0)` is still 0 — which is why the
  40-stack panel showed the seams even with auto-merge on. At 1.3 the domes overlap, the seam lands
  where the dome is well above the cut, the base fuses into one mass, and the outermost tendrils
  cover the host's full width (measured: 0–1 px uncovered, was visibly short). Merge then does what
  its docs claim. Owner ruling 2026-07-28.
- **Guard the noise.** `fire.gdshader` early-outs on `heat <= 0.0` before `fx_fbm`. Most fragments
  in a quad are empty and fbm is seven taps; this one branch is the biggest saving in the shader
  and the easiest to drop in a refactor.
- **The quad is sized to the host's DIAGONAL** when the host can rotate (a 38×50 card is 62×62 at
  45°, and `anim_spin_start` turns it through every angle). Pinned hosts skip that ~1.6× fill.
  Props pass `host_rotates = false` — **no prop rotates any more**; directional art mirrors instead
  (see §4h) — so they all keep the cheaper box bound.
- **Fire is ONION-SHELLED, never row-layered** (owner 2026-07-27: *"each layer wraps around the
  other, like actual candle lights"*). `heat` is distance ACROSS the flame relative to the flame's
  own half-width AT THAT HEIGHT, so every iso-heat contour is a scaled copy of the outline and each
  colour wraps the one inside it. Height is only the weak secondary term (`onion_rise`); leading
  with height is what stacked the colours into horizontal stripes. The half-width comes from
  INVERTING the same ogee the outline uses — one arch read two ways, so the shells cannot drift from
  the silhouette.
- **A ball's CENTRE is snapped to the pixel lattice** (`fx_pixel_snap`, 2026-07-28). `fx_local`
  quantizes to a grid anchored on the QUAD while the ball centre moves continuously, so without this
  every ball rasterizes at an arbitrary sub-pixel phase: measured on `05c_ball_sphere`, one ball's row
  widths ran `31/44/…/87` down one half and `87/…/34/9` up the other, and the silhouette wobbled as it
  travelled. Snapped, the same ball measures perfectly symmetric. The RADIUS is deliberately NOT
  snapped (owner 2026-07-28) — it varies with the count and quantizing it would make balls pop
  between sizes.
  - **⚠ Undo the Y FLIP when snapping.** `fx_local` quantizes and THEN negates y, so the art-space y
    lattice is `extent.y/2 - (j+0.5)·cell` while x is `(k+0.5)·cell - extent.x/2`. Those coincide only
    when `extent/pixel` is a whole number, which it generally is not (62.4 at pixel 1.0). Snapping y
    with the x formula lands between rows and the asymmetry survives — it did, on the first attempt.
  - **⚠ The ball-fire quad must snap on the BALL quad's lattice**, not its own: the two have different
    reaches and different `pixel`. `FxRequest.partner_reach` / `partner_pixel` carry it, pushed as
    `u_partner_extent` / `u_partner_pixel`. Snapping a plume on its own grid puts it half a pixel off
    its ball and makes it jitter as the ball moves.
- **A lit ball's plume sits ON TOP of the ball, and every arc runs under ONE gravity.** The plume's
  `rise` is measured from the ball's top (`- radius + sink`), not its bottom — from the bottom it
  wrapped the whole ball and hid it. And each arc's share of the cycle is proportional to sqrt of its
  own height, the flight time one gravity gives it, instead of the near-equal shares that made the
  tall throw and the flat carry take the same time: measured spread across arcs 1.92x → 1.26x, with
  the ease now applied to every arc including the carry (exempting it gave it its own character).
  `ball_top_fraction` survives as the throw's hang-time bias about the physical 0.5.
- **Balls are SPHERES.** The fragment is lifted onto the hemisphere (`z = sqrt(1 - |nd|²)`) and shaded
  by that normal, then the Lambert term is QUANTIZED into `ball_bands` hard tones spanning
  `ball_shade → ball_lit`, with a half-vector threshold (`ball_spec`) for a highlight that sits on
  the surface. A straight two-tone split plus a dot reads flat however it is coloured. The spin
  rotates the LIGHT (the shading frame) after quantization — never the grid.
- **⚠ A shader that writes `COLOR` must multiply the MODULATE back in.** The renderer folds a
  CanvasItem's modulate into `COLOR` before `fragment()` runs, so overwriting `COLOR` silently
  discards it: the focus highlight stopped at the card's own art (ruling 10 quietly unimplemented)
  and an exiting prop's flames stayed opaque while the prop faded. Both shaders now capture
  `vec4 tint = COLOR;` first and end with `COLOR = col * tint;`. Any new effect shader must too —
  the PIXELS suite asserts it for fire and balls.
- **The ball period is REAL SECONDS** (`FxStyle.ball_period_secs`), not a fraction of `base_delay`.
  Act compression still quickens the pattern, because the clock feeding `_phase` is already
  pacing-scaled — multiplying by `base_delay` as well made one whole cycle 0.12 s at the owner's
  0.1 speed setting and the balls unreadable. How fast juggling LOOKS is an art decision; how fast
  the game STEPS is the player's.
- **Every effect must be DESYNCED from every other host.** `FxAttachment` rolls a per-HOST `_seed`
  (pushed to every quad it owns, never per-quad — the balls and the flames riding them must agree),
  a per-host `_ball_dir`, and a RANDOM starting `_phase`. Any new motion term has to fold the seed in
  or it runs in lockstep across the board: that is what the tendril sway PHASE **and rate**, the
  whole-effect pulse, and the ball spin all do (owner 2026-07-28 — the spin was keyed on the ball
  index alone, so every card's ball 0 turned together, and `_phase` starting at 0 meant two cards
  with the same count juggled as one).
- **Balls cross because the ARC LADDER alternates, NOT because of a per-ball mirror** (fixed
  2026-07-28). `fx_ball_dir` returns the host's own `u_ball_dir` for every ball; that direction is a
  coin flip per host, so the pattern runs one way on one card and the other on the next.
  **⚠ Do not reintroduce the odd-ball mirror.** It made sense when the loop was one throw plus one
  carry, but consecutive arcs already run opposite ways and consecutive balls sit in consecutive arcs
  — so when the ball count is near the arc count the two alternations CANCEL and every ball travels
  the same way, leaving half the pattern empty. Measured at the counts where n == arcs: **2/2, 4/4
  and 6/6 balls unanimous** with the mirror, an even split without it (owner report: "at ball counts
  below 10 all balls go left to right, then right to left in one group"). `test_pixels.gd` guards
  those three counts by name. With one direction group, `fx_nearest_ball` is arcs × 2 bracketing
  integers — 16 evaluations at the eight-arc ceiling, half what it was, still no loop over the count.
- **Turbulence scrolls UP.** Art y is negative upward, so the noise sample is `p.y + t·scroll`;
  minus (the original) drifted the grain DOWNWARD and read as the fire falling.
- **Nothing may reach more than half a card separation past its host** — that is what keeps the card
  behind visible (owner 2026-07-28). Card fire: `height` = `CARD_SEPARATION * 0.5` = 7. Juggling:
  `ball_arc_max` = 32 = half a card plus half a separation, measured to the topmost ball's EDGE
  (the radius comes out of the budget), which also ceilings the count-driven arc growth. Prop-hosted
  styles are in PROP art units (≈2.5× smaller than a card's), so the same rule is a different number
  there. A lit ball's PLUME is explicitly out of the budget (owner).
- **The ball loop is an ARC LADDER, not one throw and one carry.** Lanes appear between the two as
  the count rises (`FxJuggle.arcs`, tunable via `ball_arcs_per_count` / `ball_arcs_max`), at evenly
  spaced heights from the throw down to the carry, and the balls travel all of them — so a bigger
  count spreads them through the space instead of stretching one arc (owner 2026-07-28). Every arc
  starts and ends at `(±span/2, 0)`, which is what lets any number of them chain into one closed
  loop; they ALTERNATE direction, so **the count must be even** or the loop would not close in x.
  Gravity eases every arc except the lowest. The arc count is where the shader's cost now lives —
  `fx_nearest_ball` does fixed work PER ARC (bounded by `FX_MAX_ARCS`), still never per ball.
  ⚠ It is an integer and it STEPS: crossing a lane boundary re-shapes the path, the one place
  ruling 16's "no visual jumps" does not hold.
- **Gravity on the throw is a time warp, and it must stay INVERTIBLE.** `fx_arc_ease` maps time
  along the tall arc to distance along it as `0.5 + 0.5·sign(d)·|d|^g` about the apex, so the ball
  decelerates into the top of the throw and accelerates out (`FxStyle.ball_gravity`; 1 = the old
  constant speed). The path itself is unchanged — the eased value drives BOTH axes. The exponent
  form was chosen because `fx_nearest_ball` recovers a ball index from a fragment's x in closed
  form, which needs this mapping inverted analytically (`fx_arc_ease_inv`, exponent `1/g`); a
  smoothstep or a sine ease would have no closed-form inverse and would break the no-loop lookup
  that makes unlimited balls free. The CARRY is never eased — nothing is falling there.
- **`@tool` hosts:** `CardVisual` and `PropVisual` both run in the editor. FX construction is
  guarded by `Engine.is_editor_hint()` and sets no `owner`, or the editor would save FX nodes into
  `card_visual.tscn`.

**`StatusJuggling.ball_fire` — the invariant.** `ball_fire.size() == stacks`, ALWAYS. A ball's
flame is the BALL's own effect at the level it was spawned with; it is never read from the card's
`StatusBurning`, and a burning card does not light its balls. **Ball index is ball identity**
(ball i renders at `phase + i/n`): append on add, remove from the END — removing from the middle
re-indexes every later ball and makes flames jump between them. Four touch points:

1. `PropDropStatus.on_pass_card` → `status.on_dropped_by(prop)` carries the prop's `fire_stacks`.
2. `CardData.add_status` merges via `merge_from`, which CONCATENATES the levels as the stacks add.
3. The `stacks` setter calls `fit_to_stacks()`, truncating from the end.
4. `fire_levels()` re-fits on READ, so a save written before `ball_fire` existed loads correctly
   (no migration file). Writes go through the `ball_fire` setter, which emits `data_changed` —
   only the `stacks` setter used to, so a ball catching fire without the count changing would
   never refresh the visual.

**`ParticleEngine` is the game's ONE particle path** (`UI/Fx/particle_engine.gd`, the
`ParticleLayer` node). Shared infrastructure that outlives this feature: every particle from any
source is spawned through `emit()`/`spawn()` and simulated in one O(n) pass over a fixed-size ring
buffer of `PackedFloat32Array`s under `MAX_PARTICLES`, rendered by ONE `MultiMeshInstance2D`
written as a single `multimesh.buffer` assignment. Do not add a `CPUParticles2D`/`GPUParticles2D`
anywhere else. Particles are **world-space by design**: an emitter moving, despawning or being
freed never moves or removes what it already emitted, so emitters own no particles and have
nothing to release. `ParticleEngine.CURRENT` may be null (a viewer has no play area) — `spawn()`
no-ops rather than crashing, and "no engine" is a supported state.

**Tuning.** ~35 art levers per effect live in `.tres` presets under `Shaders/Styles/`, written to a
material ONCE. **One class per EFFECT, not one class for all of them** (2026-07-31): `FxStyle` is the
shared half — `pixel`, `brightness`, `opacity`, the embers, and a virtual `apply()` — and
`FxFireStyle` / `FxJuggleStyle` carry their own knobs and override `apply()`. A flag on one fat class
was tried first and reverted: the inspector filter needs a per-kind name table as soon as there is a
third effect, and one shared `apply()` pushes every kind's parameters at every material (measured:
~140 bytes per unused parameter, per MATERIAL — so the waste scales with hosts on screen, not with
the number of styles). `FxRequest.style` is still the base, so nothing in the attachment layer knows
which effect it is carrying; only the clock, the host rotation, the lag vector, the phase and the
eased data values are pushed per frame. Player-facing knobs (`fx_transition_fraction`,
`fx_intensity`) live in `player_settings.gd`; `fx_intensity` reaches zero as a genuine
photosensitivity control, and flicker/pulse are separate levers so they can be reduced without
dimming everything.

**Shader pixels are covered TWO ways now.** The **PIXELS** suite (`Tests/Visual/test_pixels.gd`, in
all_tests) renders the real effects into a SubViewport and ASSERTS on the image — the fire draws and
draws upward, its hottest band is a tall spine and not a wide slab (the onion/rows discriminator; a
"core hotter than rim" check does NOT discriminate, verified by mutation), every ball lands on the
shared spec oracle at 1/3/8/50, a ball shades into 3+ tones with an off-centre highlight, the hoop
halves reassemble pixel-for-pixel, and a prop texel matches a card texel at three card scales. It
FAILS rather than skips under a dummy renderer, which is why the suite runs windowed (§7). The
snapshot harness below stays for the judgements a number cannot make.

**Tuning FX by hand: `UI/Fx/Tools/fx_editor.tscn`** (2026-07-28, owner request — *"a way to visualize
fire and juggling purely in editor … so I can fine tune parameters"*). Open the scene in the editor
and it renders a burning card, a juggling card and a burning prop through the SHIPPING path
(`FxFire.request` / `FxJuggle.requests` into a real `FxAttachment`) — never a private copy of the
maths, which is the mistake that made flames trail their balls. Stacks, ball count, lit balls, both
bodies, zoom and a `time_scale` (0 freezes the animation while the shapes stay live) are inspector
knobs; editing any `FxStyle` re-pushes immediately.

**⚠⚠ EVERY FX SCRIPT MUST STAY `@tool`, AND THIS ONE DESTROYS DATA.** A non-tool script loads in the
editor as a PLACEHOLDER instance. Three consequences, all seen on 2026-07-28:

1. Calling anything on it fails — *"Attempt to call a method on a placeholder instance"* — so
   `FxStyle.apply()` never ran, no uniforms were pushed, and **every effect in the editor rendered
   pure white**.
2. `_apply_static()` aborts at that call, so `u_mode`, `u_body`, `u_ball_tones` and the rest never
   reach the material either — which is why the ball-fire quad appeared to draw nothing at all.
3. **Saving a `.tres` whose script is a placeholder writes back only the properties the editor could
   see and silently drops the rest.** `fire_card.tres` lost its `pixel` and `dither` that way, and
   picked up a corrupt `ramp_edges = null`, just from being opened. Recovered from git.

`FxStyle`, `FxRequest`, `FxFire`, `FxJuggle`, `ParticleSpec`, `ParticleEngine` and `FxAttachment` are
all `@tool` for this reason. Any new FX class an editor tool touches must be too. The array setters
also coerce null, as cheap insurance against a `.tres` corrupted this way reaching a shader.

Two more things it required, both worth not undoing:
- **`FxAttachment` is `@tool` now**, and reads settings through `FxAttachment.settings()` — the editor
  instantiates NO autoloads, so `SettingsManager` is absent there and the shipped `PlayerSettings`
  defaults stand in. `pacing()` already returned 1.0 with no Game.
- **Every node the tool builds is OWNERLESS and rebuilt from scratch** on any change. An owned child
  would be saved into `fx_editor.tscn` by the editor — the same trap that stops `CardVisual` from
  building FX in the editor at all.

It is a TOOL, not a test: nothing in it asserts. Assertions live in `Tests/Visual/test_pixels.gd`,
reviewable captures in `fx_snapshot.tscn`.

**Shader pixels need the SNAPSHOT harness, not the headless suite.** `--headless` uses the dummy
renderer and never compiles a shader program, so a GLSL error, an inverted sign, an upside-down
flame or an effect that draws nothing all pass it silently — the first snapshot run caught four
real bugs the green suite had not:

- `QuadMesh` is a 3-D primitive whose +Y is UP, so `(UV - 0.5) * extent` inverts y against Godot's
  2-D convention and **every effect rendered mirrored**. `fx_local()` owns that flip now; effects
  must go through it rather than quantizing UV themselves.
- Clamping the tendril's `u` to ±1 made `u_merge` a **silent no-op** (a neighbour is by definition
  sampled at |u| > 1, so it always evaluated to exactly zero).
- The comb spanned `u_body.x` — the UNROTATED width — leaving a third of a 90°-rotated card's edge
  bare. `emit_half_width()` handles it.
- The rotated-box contour used a fixed-point iteration that only converges for an unrotated
  rectangle, and returned a slanted base at 90°. `box_contour()` walks the convex hull instead.
  Note it must be UNROLLED: a dynamically indexed local array compiled without complaint on GLES3
  and returned garbage.

Run `Godot --path solatro res://Tests/Visual/fx_snapshot.tscn` (windowed, needs a GPU, self-quits)
after ANY shader edit; it writes PNGs to `user://fx_snapshots/`
(`%APPDATA%\Godot\app_userdata\Solatro\…`). It is deliberately not in `all_tests.tscn`. Shots:
`00_tendril_count` (geometry only, countable — and the onion shells), `00b_ogee_profile`,
`01_fire_ladder`, `02_fire_rotation`, `03_surfaces` (several surfaces under one comb, on the RING —
both arcs alight, the hole's middle empty), `04_shapes` (the real prop ART, masked from its own
alpha), `05_balls`,
`05b_ball_path`, `05c_ball_sphere`, `05d_ball_gravity` (the throw's easing — the balls bunch at the
apex as it rises), `05e_ball_arcs` (the arc ladder at one ball count), `06_ball_fire`,
`07_transition`, `08_focus_highlight` (ruling 10).
The ball shots carry an independent GDScript **oracle** — crosses drawn where the spec says each
ball should be — and the harness then MEASURES ITS OWN CAPTURE, printing per ball how far the
nearest rendered ball is from its expected position in ART UNITS (`PROBE` lines). Read those
numbers; do not measure the PNGs by hand, which is how two passes reached wrong conclusions.

Two GLSL/harness facts worth not rediscovering: **`return` is illegal in a Godot `fragment()`
processor** ("Using 'return' in the 'fragment' processor function is incorrect"), so a temporary debug
override has to be an `if` that assigns `COLOR` after the real body; and **snapshot layout must be in
CANVAS units** (`get_viewport_rect().size`), because `window/stretch/mode = canvas_items` means the
captured image is the canvas scaled to the window — convert by `img.get_width() / that` when reading
pixels back, or the last column lands off the right edge.

**Two harness traps, both of which masqueraded as shader bugs (2026-07-27):**

- `FxAttachment._push_live()` ENDS with `set_process(not _fx.is_empty())`. Parking the clock by
  calling `set_process(false)` BEFORE the push silently re-enables it, the frames awaited before the
  capture then advance `_phase`/`_time` by real deltas, and every ball renders ~0.15 of a cycle past
  the phase the oracle and the debug print were told about. **Disable the process LAST.** This, not
  `fx_nearest_ball`, was the "ball positions disagree at low counts" bug.
- Reference geometry is added to a slot BEFORE the effects so the effects draw on top. Inserting a
  node between them (the modulate host, when the focus-highlight shot was added) put the oracle
  crosses OVER the balls and read exactly like the balls had stopped rendering.
- Reference geometry drawn at sub-pixel widths is DROPPED by the rasterizer. At the zoom a ball quad
  forces (~1.0 art unit per pixel) the old 0.5-unit crosses and outlines lost half their lines, so
  "does the ball sit on its cross" could not be judged at all. Every width in `_Ghost` is now a
  multiple of the shot's art-units-per-pixel.

Every shot is byte-reproducible across runs **except `02_fire_rotation`** (measured: two consecutive
runs of identical code differ by ~11k pixels, all inside the ROTATED panels; the 0° panel is stable).
Review that one by eye — flames upright, pixels square — and do not read anything into a pixel diff
of it. Both harnesses share `Tests/Visual/snapshot_scene.gd` (`SnapshotScene`), which owns the
backdrop, the canvas-units rule, the captions and the capture.

Covered by `Tests/UI/test_fx_attachment.gd` ("FX ATTACHMENT"), the FX section of
`Tests/UI/test_visual_layers.gd`, and `Tests/Visual/fx_snapshot.gd`.

---

## 4h. PIXEL ART — one pixel size, and how each surface gets its colour (2026-07-27)

**Picking up prop/pip art work? Start at [VFX.md](VFX.md)**; this section is the contract it sends
you to.

**ONE PIXEL SIZE FOR ALL ART** (owner). A card draws its own art one texel per UNSCALED unit and is
then scaled by `card_scale`; a prop is scaled by `card_scale / PropVisual.AUTHORED_CARD_SCALE`. So a
prop texel matches a card texel on screen only when the prop draws its frame at
`frame_px * PropVisual.ART_PIXEL_SCALE` (= `AUTHORED_CARD_SCALE`, and derived from it rather than
retyped). **Every kind sizes `art_size` through that constant, never with raw pixel numbers** — that
is what keeps all of the game's art at one pixel size at every `card_scale`.

**Directional prop art MIRRORS, it never rotates.** Every directional sheet is authored pointing
LEFT; heading right draws the same frame flipped left↔right so its top stays its top (a 180° turn
would carry top and bottom around with it). `PropVisual.face_travel` opts a kind in, `flipped` is the
live state, and `_draw_art()` applies it as a DRAW transform — never a negative node scale, because
`FxAttachment` is a child of the prop and the FX pixel grid must not move.

**Where prop art comes from:**

| Kind | Sheet | Notes |
|---|---|---|
| Hoop | `Assets/hoop_prop.png` | 3×(32×72) frames — full, back half, front half. Only the FULL frame is sampled; the halves are source rects of it (owner preference), so the three cannot drift. |
| Knife | `Assets/knife_prop.png` | one 12×5 frame, tip toward −x; `face_travel` on. |
| Ball / Fire | `Assets/suit_pips.png` frames 2 / 3 | the props ARE their suits' pips — one drawing for the suit and the prop it launches. |
| Firework | none yet | still a placeholder polygon (`color`); no art authored. |

**The hoop's split axis is now VERTICAL** (it was the horizontal diameter): the art is a
foreshortened oval, so its LEFT arc is the ring's far side (it carries the shading) and renders
behind the occupied card, its RIGHT arc the near side, in front. That matches `fire.gdshader`'s
`u_half` split (BACK keeps `p.x <= 0`) exactly, so a burning hoop's back-arc flames stay behind the
card too. `SHAPE_RING` is an **ellipse** from `u_body`, not a circle of its half-width — a circle sat
the flames deep inside an 80×180 arc.

**Recolouring: only SUIT-AGNOSTIC art gets recoloured.** `Assets/color_picker.gdshader` replaces a
polygon's RGB with a palette entry while the polygon's texture supplies the alpha, so it flattens
whatever it touches to ONE colour. Therefore:

- The **suit pip** draws the sheet's own colours — `suit_pips.png` is authored in the palette, each
  frame already shaded with its suit's ramp. `PipSuit.set_texture()` CLEARS the material (these
  polygons are pooled and reused, so a stale material from a previous binding would survive).
- The **rank pip** and the **card art** are shared by every suit, so they are recoloured to that
  suit's `palette_role()` (§4i).
- The palette IMAGE and `num_colors` are both pushed from `PaletteDB` at bind time. Neither is
  stamped into `card_visual.tscn` and neither is a shader default any more (T21).
- **FX colour is on the palette too** since T21 — the fire ramp and the ball tones are generated from
  `PaletteRamp` resources. See §4i.

Visual checks: `Godot --path solatro res://Tests/Visual/prop_art_snapshot.tscn` (windowed, needs a
GPU) writes `user://prop_art_snapshots/` — every kind over a card outline, the pip-vs-prop pixel-size
comparison at three `card_scale`s, the mirror, the hoop halves reassembling the whole ring, the
recolour split per suit, the hoop/jumped-card centre alignment (`15_hoop_alignment`), and the
palette SWAP (`16_palette_swap`, §4i).

---

## 4i. THE UNIVERSAL PALETTE — every colour is a named pointer (T21, 2026-07-28)

**Every colour the game draws resolves to an entry of one N×1 image.** Reassigning a colour is
editing ONE named role; swapping the whole palette is repointing ONE resource. Owner's ask:
*"colors should come from universal palette … via some resource of pointers, and make it easy to
reassign to different colors especially if the palette changes."*

| Piece | File | What it is |
|---|---|---|
| `Palette` | `Scripts/palette.gd` | Wraps the N×1 texture. `width()` comes from the IMAGE — never hand-entered. |
| `PaletteRoles` | `Scripts/palette_roles.gd` | The resource of pointers: one named `@export` int per role. |
| `PaletteRamp` | `Scripts/palette_ramp.gd` | An ORDERED list of entries. The only way a gradient is expressed. |
| `PaletteDB` | `Scripts/palette_db.gd` | Statics that name the live palette, roles and ramps. |
| Data | `Assets/Palette/*.tres` | `circus_crayon`, `roles`, `ramp_fire`, `ramp_ball`, `ramp_ember`. |

**Rules that prevent regressions:**

- **STATICS, not an autoload** (owner 2026-07-28: *"autoload seems kind of overkill and has bad code
  smell"*). Nothing changes at runtime, the `@tool` FX hosts run with no autoloads (§4g's trap), and
  `preload` resolves at parse time — so no call site null-checks, and a null here is a bug to fix.
- **⚠ `PaletteDB.PALETTE` is a `static var`, NOT a `const` — do not "tidy" it back.** A `const`
  resource reference is resolved per reading script, so mutating the object through one reference is
  invisible through `PaletteDB.PALETTE` in another. That is not theory: the palette-swap snapshot came
  back pixel-identical until this changed, with the probe showing `pal == PaletteDB.PALETTE` true
  while their `.texture` differed.
- **RAMPS SAMPLE, THEY NEVER LERP** (owner: *"blending can create unpredictable and bad looking
  colors"*). A ramp's window is stepped, the ball bands index a tones texture, the ember gradient uses
  `GRADIENT_INTERPOLATE_CONSTANT`. The old fire ramp was baked by interpolating two band tables and
  had **64 colours, zero of them palette entries**; the 3-band ball `mix()` put its middle tone 49
  away from any entry even though both endpoints were hand-picked. Palette-valid ENDPOINTS are not
  enough — the in-between is where the drift lives.
- **A ramp is longer than any one effect needs and effects take a sliding WINDOW of it** (owner:
  *"ramp could have 10 colors, and fire ramp can focus on window of 3 and move through the ramp when
  intensity increases"*). The window slides toward the hot end as the stack level rises, so more
  stacks means hotter bands rather than the same bands brightened. `FxStyle.ramp_window` /
  `ramp_edges` / `ramp_cut`; built by `PaletteRamp.window_texture()` at load and cached on the style.
  There is no build step and no baked ramp PNG any more (`tools/make_fx_ramp.py` deleted).
- **The recolour shader is handed the palette; it does not own one.** `Assets/color_picker.gdshader`
  (a plain shader now — the old VisualShader had the palette texture baked INSIDE it, which is why a
  swap recoloured nothing). `PipSuit.set_material()` pushes `palette`, `color_x` and `num_colors`.
- **Roles are named for MEANING** (`status_flame`), never for colour (`orange`) — a role called
  `orange` is a literal in a costume and stops surviving the first palette change. `ROLE_NAMES` lists
  every role; a role missing from it is never range-checked again (a test pins the two together).
- **Pixel art stays as authored.** `suit_pips.png` and the prop sheets are already painted in the
  palette; recolouring them would flatten their shading (§4h). The swap shot asserts the pips do NOT
  move while the rank pip and card art do.
- **Colour is presentation: nothing here is saved.** `run.tres` stores no colour; never add a
  migration for a palette change.

**Editing roles in the inspector.** `PaletteRoles` is `@tool`: `_validate_property()` rebuilds each
role's dropdown from the live palette (`0 #1a0319`, `1 #700031`, …) and `_get_property_list()` adds a
read-only swatch per role. Both read the image, so they cannot go stale.

**Still hardcoded, deliberately** (owner 2026-07-28, *"Map and UI and background can be deferred to
some other day, I plan on adding custom art for those"*): the map screen, the in-game UI chrome, the
status-count text, and `FireworkVisual`'s placeholder. They are NOT allowlisted — the drift scan
reports each one every run as `[WARN][PLACEHOLDER]`, which is the standing reminder. When that art
lands, assign the colour in code at `_ready()`; never re-bake a literal into a `.tscn`.

**Enforcement.** `Tests/Engine/test_palette.gd` ("PALETTE") checks roles resolve in range, `width()`
matches the image, generated ramp/tone textures contain ONLY palette entries, a swapped palette moves
every role — and runs the drift scan through `TestSuite.warn()`, which counts separately and never
touches the exit code. Pixels: `16_palette_swap` (§4h) and `tools/palette_conformance.py`, which
reports off-palette pixels in the captured PNGs (a review instrument — FX quads alpha-blend, so
blended pixels legitimately are not entries; look for LARGE single-colour clusters far from any
entry).

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

Run: `Godot --path solatro res://Tests/all_tests.tscn` — **WINDOWED, no `--headless`**
(changed 2026-07-27: the PIXELS suite renders real effects and asserts on the image, and a
dummy renderer cannot compile a shader — headless it FAILS with an explanation rather than
skipping, per the owner's rule that tests must run properly rather than be skipped). Exit code
= failure count; the bar is ALL suites green (count the run's own banner; 27 as of 2026-07-27 —
PATIENCE, FX ATTACHMENT and PIXELS joined, and all run unordered like the other engine suites).
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

Visual-effects rulings (2026-07-26/27 — the spec §4g implements; do not redesign around them):

1. Fire tips always point generally UPWARDS, allowing some angle skew as spread. **Reaffirmed for
   CURVED hosts (2026-07-30)** after two rejected builds: the answer to a hoop's bare flanks is NOT
   to tilt the flames along the normal, and NOT to shear their bases along the contour. *"I want
   version that covers hoop top completely with tendrils always pointing up. This may require base of
   fire to be able to spread out/sticky against any surface, not just flat bottom."* Coverage is the
   BASE's job. **Satisfied 2026-07-30 by the MASK model** (§4g): the base is now whatever surface a
   column's down-march lands on, so it sticks to any surface by construction — and the march being
   WORLD-down is what makes "tips point up" structural rather than a per-shape branch.
2. Fire paints props and cards but, just like props, shows only BETWEEN cards — a card with FX
   does not show it where it is covered.
3. A burning card does not mean its balls are burning, except when it is spawning burning balls.
   **Each individual ball can be burning or not.**
4. No small tendril cap — either raise it to ~50 or abandon the cap and have fire increase in
   INTENSITY per stack. (Implemented as the latter.)
5. Balls ideally have NO stack limit; if one were forced, balls shrink as the count rises to fit
   the limited space.
6. Delete `PropVisual._draw_fire_tips()` once shader fire ships. (Done.)
7. FX is shared across all views — what it looks like on the board is what it looks like
   everywhere else.
8. One resource and shared location for all visual-effect tuning, rather than hunting shader by
   shader.
9. Embers must not follow a flaming object that leaves the area — so, particles.
10. Allow the focus highlight on effects.
11. Balls all pass IN FRONT of the card, one layer, no depth split.
12. The pattern speeds up as ball count rises.
13. The loop is centred on the card: the bottom arc rides the card's centre, the top arc peaks
    above the card.
14. Flame colour shifts with stack count.
15. "No burning object, just overlay" — fire never tints or chars its host.
16. Stack increases and decreases transition SMOOTHLY; no jump in visuals.
17. A burning ball does not transfer its status effect to the card — no hand-off flourish, and no
    `StatusBurning` is granted by a landing ball.
18. Any view that shows cards shows their status effects; a status should not be hidden behind
    selecting and reading a description.
19. `FX_LEVEL_REF` is "a high number like 100+", as long as it stays tunable.
20. Balls do NOT shift colour with count.
21. Ball fire and card fire are SEPARATE effects — a ball's flame level comes from the BALL, never
    from the card's Burning.
22. Transition speed metric: fast enough to finish before the next status effect can be applied.
23. A card flipped face-down hides its status effects — a hidden card reveals zero information.
24. Juggling keeps happening while the card is moving; no freezing ever, on any effect.
25. Balls spin, faster as stacks increase. No trails — too noisy.

- **Universal VFX rule (2026-07-27): no VFX pixel grid ever rotates** — fire, balls, particles, or
  anything added later. Mechanically: **quantize first, rotate after.** Snap the sample point to
  the grid in the quad's own world-aligned space and let every rotation act on the
  already-quantized coordinate. Rotating a frame BEFORE quantizing rotates the grid (diagonal
  pixels — never); rotating AFTER moves content through a fixed grid (chunky pixels that stay
  square while the thing they depict turns — always). This extends to `ParticleEngine`: the
  MultiMesh transform carries position and uniform scale only, never per-instance rotation.

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
