# Precious Mochi — Implementation Checklist

Low-level execution checklist for [SUIT_PROPS_PLAN.md](SUIT_PROPS_PLAN.md) (Plan v3.2 —
Suit Modifiers as Data-Layer Props). Check items off as they land. Execution order is
Phase 0 → 2 → 1 → 3 → 4 → 5 → 6 (per plan's "Execution order & risk notes").

Memory flags: [[godot-editor-disk-sync]] (re-read disk before diagnosing),
[[running-godot-scenes]] (add prints; the USER runs scenes/tests), [[no-git-staging]]
(edits only, no `git add`/commit), [[solatro-tres-cyclic-backrefs]] (four unlink/relink
sites), [[code-style-lean-documented]].

---

## Phase 0 — `PipSuit → CardModifier`, comparator, serialization, deck + test-factory

### 0.1 Base class `pip_suit.gd`
- [x] Change `extends Resource` → `extends CardModifier`; keep `@abstract class_name PipSuit`
- [x] Remove ordinal `value` property (and `with_value`)
- [x] Keep `signal data_changed` (card_data.gd:9-13 setter connects it)
- [x] Add consts: `SUIT_TEXTURE`, `ART_TEXTURE`, `COLOR_PICKER_SHADER`, `PALETTE := [8,11,14,2,6]`
- [x] `@abstract func get_suit_index() -> int` (0..4, art/palette slot only)
- [x] `@abstract func spawn_props() -> Array[PropSpawner]` (PURE; empty until Phase 3) — NOTE: PropSpawner type doesn't exist until Phase 1; use untyped `Array` return or forward-guard
- [x] `func get_frame() -> int: return get_suit_index()`
- [x] `set_texture(p)` — moved from Standard, palette-indexed via `get_suit_index()`
- [x] `set_material(p)` — moved up from Standard (ShaderMaterial + `PALETTE[get_suit_index()]`)
- [x] `set_art_texture(p, rank)` — moved up from Standard (`13*get_suit_index()+(rank.value-1)`)
- [x] Registry: `const STANDARD := [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]`
- [x] `static func from_index(i) -> PipSuit`, `static func random_standard() -> PipSuit`
- [x] `func fire_stacks() -> int` / `func fire_mult() -> int` (reads `data.statuses`; returns 0/1 until Phase 2 statuses array lands)
- [x] Implement `get_description()` abstract from CardModifier (per-subclass)

### 0.2 Five subclasses (thin shells; bodies in Phase 3)
- [x] `Cards/Pips/Suits/pip_suit_hoop.gd` — index 0, str "Hoop", desc, `spawn_props(): return []`
- [x] `pip_suit_knife.gd` — index 1, "Knife"
- [x] `pip_suit_ball.gd` — index 2, "Ball"
- [x] `pip_suit_fire.gd` — index 3, "Fire"
- [x] `pip_suit_firework.gd` — index 4, "Firework" (NOT in STANDARD registry)
- [x] Delete `Cards/Pips/pip_suit_standard.gd`

### 0.3 PipComparator — equality-only suits
- [x] `compare_suits`: keep null-check + mod hook; else `return NAN` (no ordinal arm)
- [x] `is_suit_same`: null-check, `==` short-circuit, mod hook, then `s1.get_script()==s2.get_script() and s1.get_str()==s2.get_str()`
- [x] `skill_grabber_og_lower.gd:17` — replace compare_suits/NAN trap with `not await is_suit_same(...)`
- [x] `skill_placer_og_lower.gd:16` — same fix
- [x] Rewrite `Tests/Engine/test_comparator.gd` ordinal asserts (:89, :124-132, :197)

### 0.4 CardData + serialization back-cycle
- [x] `with_suit`: `self.suit = suit.with_data(self) if suit else null`
- [x] `game_data.gd` `unlink_modifier_backrefs`/`relink_modifier_backrefs` (:195-203) — add `card.suit`
- [x] `run_manager.gd` `_to_saveable_cards`/`_relink_cards` (:123-133) — add `card.suit`
- [ ] Verify undo + add_deck: print `card.suit.data == card` true after both

### 0.5 Deck construction (mechanical)
- [x] `Decks/deck.gd` (40+ sites): `PipSuitStandard.new().with_value(i)` → `PipSuit.from_index(i-1)`; `.with_random()` → `PipSuit.random_standard()`
- [x] `UI/deck_builder.gd` — same

### 0.6 Test factories
- [x] `Tests/Support/pip_suit_test.gd` — `PipSuitTest extends PipSuit`, `id`, `get_suit_index(): id%4`, `get_str(): "TestSuit%d"%id`, `with_id`, inert `spawn_props`
- [x] `test_factories.gd` `m_card` builds `PipSuitTest.with_id(suit_id)` (keep signature)

### Verify Phase 0
- [x] Deck loads w/ correct pip art + colors (user playtested game_view — works as before)
- [x] Same-suit stack rejected; different-suit run grabbable (playtest; grabber/placer rewritten to is_suit_same)
- [x] Save/undo round-trip (test_run_manager 23/23 green — save cycle with from_index suits + backref)
- [x] `test_comparator` (47/47), `test_scoring` (198/198), `test_game_headless` (23/23) green

---

## Phase 2 — Status-effect foundation (data) — STATUS_EFFECTS_PLAN Steps 1–7
- [x] `Cards/card_modifier_status.gd` — `@abstract CardModifierStatus extends CardModifier`, `stacks` setter (removes at ≤0), `can_merge_with`, `is_active(): stacks>0`, `stacked(script, n)` + `with_stacks(n)` — NOTE: `stacked` takes the concrete `GDScript` (not a polymorphic `static stacked(n)`: GDScript static funcs have no `self`); Phase 3 calls `CardModifierStatus.stacked(StatusJuggling, 1)`
- [x] `card_data.gd`: replace `statuses: Dictionary[String,int]` → `Array[CardModifierStatus]`
- [x] `add_status` (merge-by-class; defensively duplicate foreign-`data` status — S7), `remove_status`, `with_status`
- [x] Extend `_to_string()` with status strs + stacks (`Namex<stacks>`)
- [x] Dispatch snapshot: statuses join `run_all_mods` (:37), `_compare_implementers` (:70-72), `return_first_data_array_result` (:85); `run_card_mods` is Phase 1 (4th site, TODO there); self-guard `if target != data: return`; NOT in `skill_active_check`
- [x] Backrefs: `for st: CardModifierStatus in card.statuses: st.data = ...` at both `game_data.gd` + both `run_manager.gd` sites
- [x] `Tests/Engine/test_statuses.gd` (registered in all_tests.tscn) — merge/coexist/override/expiry/S7-dup/self-scope/self-removal-mid-pass/backref-through-duplicate/save round-trip — 19/19 green. Test-only statuses live in `Tests/Support/status_test*.gd` (A/B/Seal/Scored); `test_persistence_fuzz` updated to build `Array[CardModifierStatus]`

---

## Phase 1 — Prop engine + tick loop + dispatch + scoring seam + compression

### 1.1 `Cards/Props/prop_data.gd`
- [x] `PropData extends RefCounted`; `enum Reaction {NONE,JUMP,SPIN,JUGGLE,BURN}`
- [x] Movement: `at:=Vector3i.MIN`, `route:Array[Vector3i]`, `countdown:int`, `ticks_per_slot:=1`, `done`, `pass_negated`
- [x] `mods:Array[PropModifier]`, `kind`, `fire_stacks`, `source:CardData` (+ `reloc_sink` for teleport records)
- [x] API: `negate_pass()`, `teleport(coord,new_route)`, `set_route(new_route)`, `run_mods(fn,...)`, `reactions_for(card)` — NOTE: `reactions_for` dispatches `reaction_for` via `m.call(...)` (static-typed `PropModifier` has no such method → warning-as-error otherwise)

### 1.1b `Cards/Props/prop_modifier.gd`
- [x] `PropModifier extends RefCounted`; hook doc block (on_spawned/on_pass_card/on_finish/reaction_for)

### 1.2 `Cards/Props/prop_spawner.gd`
- [x] `PropSpawner extends RefCounted`: origin, remaining, batch_size, interval, max_live, live, factory (+ `emitted` = emit_index counter)
- [x] `func due(tick): remaining>0 and tick%interval==0`
- [x] Emission staging: i-th prop `countdown = ticks_per_slot + i` (set by the loop). Refill-behind-hindmost is emergent from countdown staging; not separately special-cased.

### 1.3 Tick loop (Game) `run_props(spawners)`
- [x] `const MAX_TICKS := 2048`
- [x] SPAWN (per due spawner, cap by max_live, `on_spawned`)
- [x] MOVE (instant; exclude spawn-tick props; countdown--; pop route[0]→at or done)
- [x] START `if view: tick_done = view.begin_prop_tick(...)` (NOT awaited) — Phase 1 stub `begin_prop_tick` added to game_view.gd
- [x] EVENTS (movers only, emission order; `note_processing()` per entry; 3-phase pass)
- [x] FINISH (done props: `on_finish`, release spawner slot via `owner_of` map)
- [x] `await skill_active_check()` once/tick
- [x] SYNC `if view: await tick_done`; filter done; `tick += 1`
- [x] Break on `act_overrun or tick >= MAX_TICKS`

### 1.4 `run_card_mods` (CardEnvironment)
- [x] Iterate `[card.type, card.stamp, card.suit]` + statuses snapshot + active skill; targeted dispatch (this is the statuses 4th dispatch site from Phase 2)

### 1.5 Scoring seam (Game)
- [x] `add_line_score(is_row, score_zone, index, amount)` — single write path
- [x] `row_gutter(v)` helper
- [x] Refactor `score_line` onto `add_line_score` (behavior preserved; row_total now banked after animate_meld — irrelevant, consumed only at apply_act_score)
- [x] `_run_score_effects(result)` in score_line: gather spawners → `run_props` → `on_score` broadcast per meld card → `on_after_score`. NOTE: this ACTIVATES previously-dormant `on_score`/`on_after_score` (all call sites were commented out) — SkillExtraPoint/StampDoubleTrigger/SkillEchoingTrigger now fire. All test suites still green (1074 checks), but USER should playtest for balance.

### 1.6 Path helpers, sides, compression
- [x] `entity_side_for_row(v)` — `hash([submits_used, save_history.size(), v.x, v.z]) & 1 == 0`
- [x] `row_slot_path(v, l2r)`, `row_slot_path_from(coord, l2r)`, `column_rise_path(v)`, `mancala_targets(v, count, eligible)`
- [x] `note_processing(weight)` base no-op in CardEnvironment; one per mod invoked in run_all_mods + run_card_mods
- [x] Game compression: consts (COMPRESS_RATIO/STEP_MS/MIN_FACTOR/SOFT_MS/HARD_CAP), `_begin_act`, `note_processing` override, `get_delay()` override (delegates to `super.get_delay()` to avoid a SettingsManager compile-order typing error)
- [x] `_begin_act()` at top of `_perform_submit`/`_perform_next`

### 1.7 `Tests/Engine/test_prop_engine.gd` (registered in all_tests.tscn) — 26/26 green
- [x] Probe classes + cases: traversal, ballistic, 3-phase-targeted, dodge, redirect, teleport, batch-vs-sequential schedules, max_live-cap-delivers-all, spawner-card-removal, concurrent, empty-route-runaway-terminates, determinism, add_line_score/row_gutter seam. NOTE: absolute per-tick timing cases (train/speed, mixed speeds, same-slot silence, spawn-tick exclusion, one-frame headless) are asserted indirectly via order/counts/live-cap — prop mods can't see the tick number headless; exact timing is validated visually in Phase 4.

---

## Phase 3 — Five suits: spawner configs + prop mods — DONE (test_suit_props 12/12 green)
- [x] Shared `spawn_props` shape via base helpers `_spawn_origin()` / `_spawn_count()` / `_burning_mods()` (skill/game/vec3 guards; count = rank×fire_mult). NOTE: base `spawn_props()` + all subclasses now typed `-> Array[PropSpawner]` (was untyped `Array`; run_props rejected the untyped array) — PipSuitTest updated too.
- [x] 3.1 Hoop — `PropScoreTalents` mod; batch burst; `row_slot_path(entity_side)`; HOOP_TICKS_PER_SLOT=2
- [x] 3.2 Knife — `PropScoreProps` mod; opposite side (`not entity_side_for_row`); scores no-skill cards incl. self (self-pass)
- [x] 3.3 Ball — ballistic; `PropDropStatus(StatusJuggling, JUGGLE)`; mancala targets (eligible = has skill); `StatusJuggling` pays column on_score
- [x] 3.4 Fire — ballistic; `PropDropStatus(StatusBurning, BURN)`; eligibility skips talents AND Fire suits; `StatusBurning` read by fire_stacks/fire_mult (count buff)
- [x] 3.5 Firework — column rise; `PropBankColScore` on_finish (empty route → banks immediately)
- [x] `PropBurning` mod (sets prop.fire_stacks) folded on via `_burning_mods()` when the source card is Burning
- [x] `Tests/Engine/test_suit_props.gd` (registered) — hoop/knife row scoring, suppression, Ball worked example `t,,b5,t,t`→`t1,,b5,t2,t2`, fire skip talents+Fire, fire count-buff, firework column bank, Juggling on_score. `fire_stacks()` in pip_suit.gd now reads StatusBurning.

---

## Phase 4 — Visual layer
- [ ] `UI/prop_layer.gd` (node under SmoothScrollContainer/TopLevelVBox, unique name)
- [ ] `PropLayer`: `_process` interpolation vs LIVE tick seconds, `begin_prop_tick`, reactions state machine, `slot_point`/`staged_point`/`void_point`
- [ ] `Cards/Props/prop_visual.gd` + hoop/knife/ball/fire/firework visuals (placeholder `_draw`, `art_size`)
- [ ] `UI/play_area.gd` expose `prop_layer`; `game_view.gd` `begin_prop_tick` seam
- [ ] `card_visual.gd` `anim_spin()`
- [ ] Verify (USER runs)

---

## Phase 5 — Status visuals + tooltips
- [ ] Status Polygon2D slot + count Label in `update_visual()`
- [ ] `ControlCard.describe_card` append suit + status descriptions
- [ ] Pip/status hover tooltips + keyboard/controller focus path [[solatro-multimodal-input]]

---

## Phase 6 — Docs
- [ ] DESIGN_DOC.md §10
- [ ] ARCHITECTURE_REVIEW.md
- [ ] STATUS_EFFECTS_PLAN.md (mark Steps 1–7 done)
