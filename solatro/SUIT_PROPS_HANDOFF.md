# HANDOFF — Precious Mochi / Suit Props (through Phase 3, 2026-07-11)

Continuation doc for [SUIT_PROPS_PLAN.md](SUIT_PROPS_PLAN.md) +
[SUIT_PROPS_PLAN_CHECKLIST.md](SUIT_PROPS_PLAN_CHECKLIST.md). Execution order is
Phase 0 → 2 → 1 → 3 → 4 → 5 → 6.

## Status: Phases 0, 2, 1, 3 DONE and green. Next: Phase 4 (visual layer).

Full suite: `godot --headless --path . res://Tests/all_tests.tscn` (self-quits ~6s) →
**19 suites, 1062 checks, exit 0.** New suites: `test_statuses` (19), `test_prop_engine`
(26), `test_suit_props` (12). All data-layer work is headless-complete and unit-tested.

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
