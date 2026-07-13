# HANDOFF — Precious Mochi / Suit Props (through Phase 3, 2026-07-11)

Continuation doc for [SUIT_PROPS_PLAN.md](SUIT_PROPS_PLAN.md) +
[SUIT_PROPS_PLAN_CHECKLIST.md](SUIT_PROPS_PLAN_CHECKLIST.md). Execution order is
Phase 0 → 2 → 1 → 3 → 4 → 5 → 6.

## Status: Phases 0, 2, 1, 3 DONE and green. Phase 4 (visual layer) IMPLEMENTED + first
## playtest-fix pass applied. Phase 5 PARTIAL: status visuals + describe_card text DONE; the
## interactive board pip/status hover+focus tooltip is the remaining Phase 5 item (best done with
## the user's runtime iteration). No Godot binary on this machine; headless is unreliable here.

### Playtest round 4 fixes (2026-07-12) — NEXT AGENT: read [PROPS_BUGFIX_HANDOFF.md](PROPS_BUGFIX_HANDOFF.md) FIRST
- **Hoops invisible / props off-screen:** the ScrollContainer CLIPS at the play-area rect and
  staged trains sat up to (countdown/tps) slot-pitches off-board — whole bursts rendered
  outside the clip. Staging now compresses to ≤ ~1.5 pitches behind the route entry (front
  waits 1 pitch out, the rest queue 0.15 pitch apart).
- **Ballistic "random direction" despawns:** ball/fire continued along their card→target
  diagonal into the void. Travelers (route ≥ 2, captured at spawn as `exits_into_void`) still
  exit along their line; ballistic props now POOF in place (scale+fade) at their target.
- **Inspector panel scroll lag:** now reparented UNDER the focused control while shown
  (pixel-locked to the card through scroll + relayout), parked back on the prop layer on hide
  (which runs before rebuilds free controls).
- **NEW geometry-envelope tests (owner request):** `test_row_prop_never_leaves_its_row` polls
  global positions EVERY FRAME across a full flight (staging/sweep/despawn) against a row-band
  + x-span envelope; `test_ballistic_despawn_poofs_in_place` pins the poof. Use
  `run_tick_polled` to build more of these for future motion reports.

### Playtest round 3 fixes (2026-07-12, owner's report + 3 UI PROPS test failures)
- **THE actual click blocker found:** `SmoothScrollContainer` force-rewrites EVERY Control that
  enters its subtree to `MOUSE_FILTER_PASS` (`smooth_scroll_container.gd _on_node_added`,
  `override_mouse_filters` on). It clobbered the focus inspector's `IGNORE`, turning the panel
  into a mouse hit-target hovering over cards. Fix: the panel + label claim the addon's
  `_smooth_scroll_default_mouse_filter_set` meta BEFORE `add_child`, so the addon skips them.
  **Any future display-only Control under the scroll content must do the same.** (This was
  also the failing "inspector ignores the mouse" check — a real catch, not a test bug.)
- **`submits_used` now lives ON `GameData`** (`@export_storage`): every undo/history snapshot
  carries the act count, so undoing across a Submit rewinds it with the board (it was a
  Game-level counter undo never touched — acts were permanently eaten). `Game.submits_used`
  is a forwarding property (old API intact); `_resume_show` assigns it AFTER the state swap
  (run-save `game_submits` stays authoritative — rescues pre-field snapshots); `undo()` also
  persists `game_submits` + refreshes the Submit label. Test: `test_undo_rewinds_act_count`.
- **Knife "fly to one end then reverse" removed:** spawned travelers (route ≥ 2) no longer
  fly card→staging; they MATERIALIZE at the staged spot — off-board behind their row entry,
  `countdown/ticks_per_slot` slot-pitches back along the travel axis (plan §4.2's train),
  pre-rotated (`face_travel`) down the travel direction — then sweep ONE way. Ballistic props
  still appear at their source card. (Deviation from plan's pop-out-of-the-card: owner ruling.)
- **The REAL "up and down the row" bug:** a row crossing traverses EVERY column, and short
  columns have no control at that z → the empty-slot fallback y was ~one pitch LOWER than
  real slots, so knives dipped at every short column. `slot_center_global`'s fallback now
  mirrors the occupied formula exactly (header bottom + separation + z·pitch + half-card).
- Test fixes: the slow-prop mid-flight assert ran on a zero-length staged→entry leg (now
  asserts on a full slot 0→1 leg, under a locally slowed base_delay so one frame can't
  overshoot the leg); the real-view focus check grabbed a `FOCUS_NONE` zone header (now picks
  a `FOCUS_ALL` card control).
- NOTE: don't run headless tests while the editor has the project open — two instances starve
  each other (this is why the agent-run suite hung; the OWNER runs tests this round).

### Playtest round 2 fixes (2026-07-12, owner's report)
- **Descriptions must NEVER touch input:** the native `Control.tooltip_text` tooltips (Phase 5)
  are a popup **Window** — the big multi-line card text sat under the cursor and BLOCKED board
  clicks. Removed entirely. The focus inspector panel is now THE card-text surface for every
  input mode (mouse hover grabs focus, so focus covers mouse+keyboard+controller); it is pure
  display (`MOUSE_FILTER_IGNORE`, `FOCUS_NONE` — asserted in test_ui_props) and hides on
  mouse-exit / ui_cancel / rebuild. Don't reintroduce tooltip_text on board controls.
- **Row travel zig-zag ("up and down 1 row"):** `slot_center_global` used control RECT centers;
  stacked row controls are thin strips while each column's LAST control is full card height, so
  centers jumped ~half a card across a row. Now anchors control top + half a card
  (= `CardVisual.get_card_control_center`) — straight lines, and props align with the cards.
- **Knives spawning at one edge point:** `PropLayer._spawn_origin_of` preferred `route[0]` (the
  far-edge row entry) over the source card. Now pops out of the SOURCE CARD (plan §4.2),
  falling back to the route head only for off-board sources.
- **Sprint-and-freeze motion ("pause and stop"):** `ticks_per_slot = 2` props (hoop/knife)
  crossed a slot in ONE tick then froze for the rest of their residency. `PropVisual` gained
  `span_ticks` + a per-tick ratcheted `t_goal`: a leg now spreads continuously over all its
  ticks (arriving as the residency ends — arrival-synced, closer to plan §4.2's intent), and
  `tick_done` still fires per data tick (at the tick's share, never waiting a whole leg).
- **"Despawning early":** the void extrapolation was one `card_separation` (~35px) so props
  looked like they vanished ON the last card; now one full slot pitch (the last leg's own
  length), and the despawn tween runs at the prop's own `span_ticks` speed instead of 2× it.
- test_ui_props updated: `test_slow_props_move_continuously` pins the smooth-motion contract;
  inspector tests assert the no-input-interaction properties and the absence of tooltip_text.

### Audit pass (2026-07-11, per SUIT_PROPS_AUDIT_BRIEF.md) — fixes + new UI suite
- **FIXED — StatusLayer misposition (was brief §3.4 #15, worse than noted):** the corner offset
  used `card_size` (already × `card_scale`, default 2.5) inside the root-scaled tree, so icons
  drew ~2.5× off the card at default settings. Now the constant `CARD_SIZE` in unscaled local
  coords (the root `scale` applies card_scale like the polygons) — correct at every scale and
  settings-change-proof.
- **FIXED — `tick_done` persistent-signal race (brief §3.3 #8):** `PropLayer.tick_pending()` +
  `GameView.prop_tick_pending()` seam; `run_props` SYNC is now
  `if view and view.prop_tick_pending(): await tick_done` — if the events phase outlasts the
  animation the emission already fired and the await is skipped instead of hanging forever.
  Check-then-await is atomic (single-threaded), so no emission can slip between.
- **FIXED — empty-slot fallback pitch** (`PlayArea.slot_center_global`) now adds the VBox theme
  separation to the per-row offset (was ~4px×scale short per row).
- **DONE — keyboard/controller card inspector** ([[solatro-multimodal-input]], was the open
  Phase 5 item): focus gained WITHOUT the mouse pops a `describe_card` PanelContainer beside the
  card (parented to the PropLayer so it rides the scroll; flips left at the play-area edge);
  mouse-held focus keeps the native tooltip (never both); `ui_cancel`/ungrab/rebuild dismisses.
  Per-PIP tooltip granularity is still TODO (runtime iteration).
- **DONE — checklist 0.4 verify** as tests, not prints: `test_game_headless` now checks
  `suit.data == card` after undo (restore_runtime relink) and after `add_deck`'s deep duplicate.
- **NEW SUITE — `Tests/UI/test_ui_props.gd` (36 checks):** PlayArea slot geometry + fallback,
  PropLayer spawn/travel/teleport-blink/despawn (none stranded, `_visuals` map emptied), JUMP
  reaction raises + resets the card visual, StatusLayer + tooltip surfaces, the focus inspector,
  and one FULL Submit through a real instantiated `game_view.tscn` (real seam) under a watchdog —
  a prop-tick sync regression FAILS instead of hanging. It backs up `settings.tres` (the suite
  speeds `base_delay` up and SettingsManager writes on every change) and `run.tres`, and runs
  second-to-last: it waits for every sibling EXCEPT E2E (which waits for ALL siblings, so waiting
  on it would deadlock); E2E stays last.
- **Verified clean:** typing conventions in all Phase 4/5 files; no tscn `unique_id` collision;
  localization keys resolve after reimport (raw keys + a `% stacks` format error appear if the
  `.translation` is stale — reimport clears it); every despawn path frees exactly once;
  `run_card_mods` remains the only suit dispatch.
- Full suite after all this: **20 suites, exit 0** (checks ~1016–1053 — the fuzz suites' check
  COUNT varies run-to-run, so don't pin a total; pin exit code + zero FAILs).

### Phase 4 playtest fixes (2026-07-11, after owner's first run)
- **Despawn bug (knives stranded at the edge):** a prop that became `done` on the run's LAST tick
  had no following tick to prune it. Done props now self-despawn via an independent tween
  (`PropLayer._despawn_visual` → travel into void, fade, free) that survives the run_props loop
  ending. `_void_point` → `_void_point_of(vis)`.
- **Speed too fast to see:** `PropLayer.PROP_TICK_FRACTION` bumped 0.12 → **0.45** and re-documented
  as THE speed knob (tick seconds = `game.get_delay() * this`, read live). Ramp-up scaling lives in
  game.gd `get_delay` + `COMPRESS_RATIO`/`STEP_MS`/`SOFT_MS`/`MIN_FACTOR` (:59-62); global base is
  `SettingsManager.settings.base_delay`.
- **Directional art:** `PropVisual.face_travel` (rotates the visual to its travel angle in
  `retarget`); Knife sets it (blade tip drawn toward +x flips when travelling left). Hoop/Ball
  stay radially symmetric (off).

### Phase 5 progress (2026-07-11)
- **describe_card** (control_card.gd) now appends `suit.get_description()` and one `"%s ×%d — %s"`
  line per status → flows into every inspector (choice_viewer, map_hover_panel). `test_ui_viewers`
  nameless-type case switched to a suitless card (the suit line now legitimately carries "—").
- **Status visual v1:** `CardModifierStatus.draw_icon(canvas, at, size)` placeholder hook (Juggling
  = ball, Burning = flame tip); `Cards/Statuses/status_layer.gd` (`StatusLayer` Node2D) draws all a
  card's statuses + `×N` counts. `CardVisual` creates one in the card's top-left corner (runtime,
  no .tscn slot, no asset) and refreshes it in `update_visual()`. Placeholder art — swap for real
  once `status_pips.png` exists (see below).
- **Tooltip v1:** each board card control gets `tooltip_text = ControlCard.describe_card(data)`
  (play_area.gd set_card_zone, both header + row controls) — full mouse-hover surfacing.
- **STILL TODO (Phase 5 polish):** per-PIP / per-status tooltip granularity. The
  keyboard/controller focus popup is DONE in the audit pass (see top) — a focus-driven
  `describe_card` panel in play_area.gd covers non-mouse input.
- ~~Known-minor: StatusLayer corner position~~ — was actually a real misposition bug at the
  default card_scale 2.5; FIXED in the audit pass (constant `CARD_SIZE` offset, scale-proof).

### Localization + settings pass (2026-07-11, per owner)
- **All suit/status UI text localized:** `Locale/localization.csv` gained a SUITS + STATUSES
  section (`SUIT_HOOP` / `SUIT_HOOP_DESCRIPTION` … `STATUS_BURNING_DESCRIPTION`); the 5 suits +
  2 statuses now `return TRANSLATION.find('KEY')` (status descriptions keep `% stacks`). Rule
  captured in memory [[solatro-localize-ui-strings]] — any user-facing string is a CSV key, never
  a literal. Reimport regenerates the `.translation`.
- **Prop-speed knob moved to settings:** `PlayerSettings.prop_tick_fraction` (0.45) replaces the
  `PROP_TICK_FRACTION` const; PropLayer reads `SettingsManager.settings.prop_tick_fraction` live.
  Memory [[solatro-tuning-knobs-in-settings]] — shared/speed knobs live in player_settings.gd.
  (The game.gd compression consts COMPRESS_RATIO/STEP_MS/SOFT_MS/MIN_FACTOR are candidates to move
  there too if they need to become player-tunable.)

### Phase 6 — docs DONE (2026-07-11)
- **DESIGN_DOC.md §10:** added a "Locked & implemented" block (nominal subclasses, factory
  switching, per-meld firing, Firework special, Knife kept, fire count-buff, mancala, prop
  architecture, determinism, view layer).
- **ARCHITECTURE_REVIEW.md §1.6:** new subsection (PipSuit dispatched only via run_card_mods +
  spawn_props; ordinal compare_suits removed; on_score/on_after_score broadcast; status/suit
  back-cycles in the four save sites; run_props sim + PropLayer view + compression/cap; extension
  contract).
- **STATUS_EFFECTS_PLAN.md:** top banner marks Steps 1–7 implemented; corrected `on_prop_passed`
  hook name, script-based `stacked`, and Step 6 placeholder-visual reality.

## PLAN COMPLETE (Phases 0–6). Remaining optional polish only:
- Phase 5 tooltip: per-pip granularity (the keyboard/controller focus popup is DONE — audit pass).
- Real `status_pips.png` asset (StatusLayer + CardModifierStatus.draw_icon are placeholders).
- Consider moving game.gd compression consts into PlayerSettings if they should be player-tunable.
- Firework not in STANDARD (never random) — needs a deliberate way to be granted to decks.

### Phase 4 — what was added (2026-07-11)
- **`Cards/Props/prop_visual.gd`** (`PropVisual`) — base draw+trajectory twin, owns `from/target/t`
  (PropLayer drives them), `retarget`/`relocate_to`(flash)/`travel_curve`, placeholder `_draw`
  to `art_size` + shared `_draw_fire_tips`. Subclasses in **`Cards/Props/Visuals/`**:
  `hoop/knife/ball/fire/firework_visual.gd` (ring / blade / arcing ball / arcing flame / rising
  rocket; Ball & Fire override `travel_curve` for a parabolic hump).
- **`UI/prop_layer.gd`** (`PropLayer`, Node2D under `SmoothScrollContainer/TopLevelVBox`,
  `%PropLayer`, z_index 100) — per-frame interpolation against the LIVE `game.get_delay() *
  PROP_TICK_FRACTION` (0.12); `begin_prop_tick(live,spawned,movers,relocated) -> tick_done`;
  spawn pop-out (staged, staggered by countdown), teleport blink, void despawn (fade+free),
  reaction diff (`anim_jump`/`anim_spin`/`anim_reset`). Node added to `play_area.tscn`.
- **`UI/play_area.gd`** — `prop_layer` accessor + `control_for_coord`/`slot_center_global`
  (direction-agnostic slot→global point, header+row-offset fallback for empty slots).
- **`Levels/game_view.gd`** — `begin_prop_tick` stub replaced with the PropLayer delegate.
- **`Cards/card_visual.gd`** — `anim_spin()` (rotation tween on `offset`, composes with jump).

### Phase 4 caveats / deviations (verify + possibly revisit)
- **Reactions fire at TICK START (occupancy of `p.at`), not at visual arrival.** Data is one tick
  ahead, so a card jumps as the prop STARTS approaching (anticipation) rather than on landing.
  Plan §4.2 wants arrival-synced (fire when `t` crosses 1) — acceptable v1, flagged.
- **`tick_done` is a persistent signal** — HARDENED in the audit pass: `run_props` only awaits
  while `view.prop_tick_pending()` holds, so an events phase that outlasts the animation (mods
  awaiting multi-frame tweens) skips the already-fired emission instead of hanging.
- **Coords are content-local via `to_local`** (PropLayer rides the scroll). Verify edge clipping
  of staged trains; widen margins / disable clip on the ScrollContainer if trains pop.
- `unique_id=2038411771` on the new tscn node is an arbitrary value matching the project's
  node-header convention.

Full suite: `godot --headless --path . res://Tests/all_tests.tscn` (self-quits) →
**20 suites, exit 0** (check totals vary — fuzz suites; pin the exit code, not the count).
Suit-props suites: `test_statuses` (19), `test_prop_engine` (26), `test_suit_props` (12),
`test_ui_props` (36, view layer). All layers are headless-tested end to end.

### How to run tests (learned the hard way — see also memory `running-godot-scenes`)
- Run `all_tests.tscn` with **NO `--quit-after`** — it self-quits headless. `--quit-after <ms>`
  forces the process to idle the FULL duration (looks hung); never use it to "force quit".
- One `godot --headless` at a time (concurrent instances starve each other).
- After adding a `class_name`: delete `.godot/`, run `--headless --path . --import` once
  (ignore the `yard` addon editor error + a cold-import `SettingsManager.settings`
  parse-error/segfault — those clear on the next real run once the class cache is built),
  then run tests.
- Warnings are errors: type every `for x: T in …`; class-ref arrays in a func body must be
  `var … : Array[GDScript]` not `const`; duck-typed hook calls on a typed base must go
  through `obj.call(&"hook", …)` (e.g. `PropData.reactions_for`).

## What exists now (data layer)

- **Statuses (Phase 2):** `Cards/card_modifier_status.gd` (`CardModifierStatus`), `CardData.statuses`
  is `Array[CardModifierStatus]` with `add_status`/`remove_status`/`with_status` (merge-by-class,
  S7 defensive-dup). Dispatch snapshot in `run_all_mods` / `_compare_implementers` /
  `return_first_data_array_result` / `run_card_mods`. Backrefs in all four unlink/relink sites
  (game_data.gd + run_manager.gd). Statuses self-scope targeted hooks with `if target != data: return`.
- **Prop engine (Phase 1):** `Cards/Props/prop_data.gd`, `prop_modifier.gd`, `prop_spawner.gd`.
  `Game.run_props(spawners)` is the tick loop (SPAWN→MOVE→START→EVENTS 3-phase→FINISH→SYNC;
  `MAX_TICKS`/`act_overrun` cutoffs). `CardEnvironment.run_card_mods` = targeted per-card dispatch
  (the ONLY dispatch that sees suits). Scoring seam `Game.add_line_score`/`row_gutter`, `score_line`
  refactored onto it, `_run_score_effects`. Path helpers `entity_side_for_row`/`row_slot_path`/
  `row_slot_path_from`/`column_rise_path`/`mancala_targets`. Compression `_begin_act`/`note_processing`/
  `get_delay` override.
- **Suits (Phase 3):** `Cards/Pips/Suits/pip_suit_{hoop,knife,ball,fire,firework}.gd` bodies,
  `Cards/Props/Mods/prop_{score_talents,score_props,drop_status,bank_col_score,burning}.gd`,
  `Cards/Statuses/status_{juggling,burning}.gd`. Base helpers `PipSuit._spawn_origin/_spawn_count/_burning_mods`;
  `fire_stacks()` reads `StatusBurning`. `spawn_props()` is typed `-> Array[PropSpawner]` everywhere.

## Behavior changes to VALIDATE by playing (headless tests pass, but these are gameplay-facing)

1. **`on_score` / `on_after_score` are now LIVE.** `_run_score_effects` (game.gd) broadcasts them
   per scored meld — every call site was previously commented out, so `SkillExtraPoint`,
   `StampDoubleTrigger`, `SkillEchoingTrigger` were dormant and now FIRE. Watch balance if your
   decks contain those. This is intended per the plan, but never before exercised in real play.
2. **Suits go live in all decks at Phase 3** (owner ruling). Any Hoop/Knife/Ball/Fire card scored
   in a meld now spawns props and mutates gutters/statuses. Fireworks are NOT in
   `PipSuit.STANDARD` (never rolled randomly).
3. **Resume mid-submit alignment fix** (game_view.gd `load_board_visuals`): score-buffer gutters are
   now created BEFORE the cards build, so a resumed scoring jump aligns with the board. VERIFY by
   quitting mid-submission and resuming — the first-row cards should jump from the correct spot.
   (`[resume]` console prints show the order.)

## Phase 4 — Visual layer (NEXT). Seams already stubbed for you:

- `GameView.begin_prop_tick(live, spawned, movers, relocated) -> Signal` — **Phase 1 stub** returns
  an immediately-completing signal (game_view.gd). Replace with the real PropLayer-driven tick that
  animates props and completes the signal when BOTH animation and the (parallel) mods are done. The
  Game already calls `if view: tick_done = view.begin_prop_tick(...)` then `await tick_done`.
- `PropData` carries everything the view needs: `at`, `route`, `kind` (0=hoop 1=knife 2=ball 3=fire
  4=firework), `fire_stacks`, `source`, `reactions_for(card) -> Array[Reaction]`
  (NONE/JUMP/SPIN/JUGGLE/BURN), and `reloc_sink` (teleport records land here as `[prop, from, to]`
  so the view can blink instead of tween).
- Plan §4 (SUIT_PROPS_PLAN.md, read from line ~890) specifies: `PropLayer` (Node2D under
  `SmoothScrollContainer/TopLevelVBox` so props ride the scroll), per-frame interpolation against the
  LIVE tick duration (`get_delay() * PROP_TICK_FRACTION`, re-read every frame), reaction state machine
  (raise while any JUMP over a card, spin while SPIN, compose; `anim_reset` when clear), into-the-void
  despawn. `PropVisual` (+ per-kind visuals) with placeholder `_draw` at an exported `art_size`.
  Also add `CardVisual.anim_spin()` (only `anim_jump()` exists).
- Reactions play AT visual arrival from pure hints (`reactions_for`), independent of the parallel
  data mods (dodge/negation changes the data effect, never the animation).

## Phase 5 (status visuals + tooltips) and Phase 6 (docs) — not started.

- Phase 5: status Polygon2D slot + count Label in `card_visual.gd update_visual()`;
  `ControlCard.describe_card` append suit + status descriptions; pip/status hover tooltips with
  keyboard/controller focus (memory `solatro-multimodal-input`). No `status_pips.png` asset yet —
  `CardModifierStatus.set_texture` is currently a no-op placeholder; needs the asset + real framing.
- Phase 6: DESIGN_DOC §10, ARCHITECTURE_REVIEW, mark STATUS_EFFECTS_PLAN Steps 1–7 done.

## Test-infra change (this session, per owner): disk tests never skip on a real save

`SolatroTest.backup_real_save()` / `restore_real_save()` (test_base.gd) move any real
`user://run_save/run.tres` to a `.testbak` sibling before the disk section and restore after.
`test_run_manager`, `test_persistence_fuzz`, `test_e2e_run` use them → they always run full and
preserve the player's save. **Never reintroduce a save-existence `[SKIP]` guard.**

## Deviations from the plan text (all intentional, noted in the checklist)

- `CardModifierStatus.stacked(script: GDScript, n)` is script-based, not a polymorphic
  `static stacked(n)` (GDScript static funcs have no `self`). Call sites:
  `CardModifierStatus.stacked(StatusJuggling, 1)`.
- `spawn_props()` is typed `-> Array[PropSpawner]` (base + all subclasses + PipSuitTest); the plan
  left it untyped `Array` for Phase 0.
- `Game.get_delay()` delegates to `super.get_delay()` (avoids a `SettingsManager` compile-order
  typing error from duplicating the base expression).
- Prop-engine timing cases that need the absolute tick number (train/speed, mixed speeds, same-slot
  silence, spawn-tick exclusion, one-frame-headless) are asserted indirectly via order/counts/live-cap
  — prop mods can't see the tick number headless; exact timing is a Phase 4 visual check.
