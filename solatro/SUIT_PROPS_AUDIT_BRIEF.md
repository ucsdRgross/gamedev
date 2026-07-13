# AUDIT BRIEF — Suit-Props + Status-Effects plan (Phases 0–6)

Hand-off package for an auditing agent. Covers the **Precious Mochi / Suit-Props** feature and
its embedded **Status-Effects** sub-plan. Everything below is scoped to this feature; the
Game/GameView split (commit `baa4b00`) is a *prerequisite* it builds on, not part of this audit.

Repo root for all paths: `solatro/`. Godot 4.7, GDScript, **warnings-as-errors**.

---

## 0. How the work is split across git

- **Phases 0–3 (data layer) are COMMITTED**: commits `2832d72`, `3a9d6cd`, `e06c990`, `027fe6b`
  (range `baa4b00..HEAD`). Feature-complete headless + unit-tested.
- **Phases 4–6 (visual layer, status visuals, localization, settings, docs) are UNCOMMITTED**
  in the working tree (`git status`).
- Diff the whole feature: `git diff baa4b00 HEAD` (committed) **plus** `git diff` / `git status`
  (uncommitted). A single combined view: `git diff baa4b00` (shows committed+unstaged vs the
  pre-feature base).

Full-suite run (self-quits ~6s headless): `godot --headless --path . res://Tests/all_tests.tscn`
→ expected **19 suites, 1062 checks, exit 0**. After any `class_name` change: delete `.godot/`,
run `--headless --path . --import` once (ignore the `yard` addon editor error + a cold-import
`SettingsManager.settings` parse-error/segfault — clears on the next real run), then run tests.
Reimport also regenerates `Locale/localization.en.translation` from the CSV.

---

## 1. Planning / spec docs (read in this order)

| Doc | Role |
|---|---|
| `SUIT_PROPS_PLAN.md` | **The spec.** §1 prop engine, §1.5 scoring seam, §1.6 path helpers, §3 suits, §4 visual layer (~L890), §5 status visuals, §6 docs, Scalability contract, execution order. |
| `SUIT_PROPS_PLAN_CHECKLIST.md` | Per-item checklist with `[x]`/notes; Phases 0–6 all ticked with as-built deviations. |
| `SUIT_PROPS_HANDOFF.md` | Chronological build log + **caveats/deviations per phase** (the single best "what to watch" source). |
| `STATUS_EFFECTS_PLAN.md` | The status sub-plan (Phase 2); top banner marks Steps 1–7 done + as-built notes. |
| `DESIGN_DOC.md` §10 "Suits" | Locked design decisions block (nominal subclasses, mancala, determinism, etc.). |
| `ARCHITECTURE_REVIEW.md` §1.6 | Architecture summary of the suit/prop/status subsystem + extension contract. |
| `UNIT_TESTS_PLAN.md` | Test conventions (behavior-vs-implementation audit standards). |

Memory/style rules the code follows (not in-repo): type every Array/Dictionary/for-iterator
(warnings-as-errors); UI strings via `TRANSLATION.find` + `Locale/localization.csv`; shared/speed
tuning knobs in `Scripts/player_settings.gd`; no git staging (owner uses GitHub Desktop).

---

## 2. Source files by layer

### 2.1 Suits (Phase 0 shells, Phase 3 bodies; Phase 5 localized)
- `Cards/Pips/pip_suit.gd` — `PipSuit` base (now a `CardModifier`); nominal `get_suit_index`,
  `spawn_props`, `from_index`/`random_standard`, `STANDARD` (Firework excluded), `fire_stacks`/
  `fire_mult`, `_spawn_origin`/`_spawn_count`/`_burning_mods`.
- `Cards/Pips/Suits/pip_suit_{hoop,knife,ball,fire,firework}.gd` — bodies + localized `get_str`/
  `get_description`.
- `Cards/Pips/pip_suit_standard.gd` — **DELETED** (was ordinal).
- `Scripts/pip_comparator.gd` — ordinal suit compare removed; equality-only `is_suit_same`.
- `Cards/Skills/Rules/skill_grabber_og_lower.gd`, `skill_placer_og_lower.gd` — use `is_suit_same`.
- `Decks/deck.gd`, `UI/deck_builder.gd` — `from_index`/`random_standard` migration (mechanical).

### 2.2 Prop engine (Phase 1)
- `Cards/Props/prop_data.gd` — transient prop; movement API (`teleport`/`set_route`/`negate_pass`),
  `run_mods`, `reactions_for`, `reloc_sink`.
- `Cards/Props/prop_modifier.gd`, `prop_spawner.gd`.
- `Cards/Props/Mods/prop_{score_talents,score_props,drop_status,bank_col_score,burning}.gd`.
- `Levels/game.gd` — `run_props` tick loop, `_run_score_effects`, `add_line_score`/`row_gutter`,
  path helpers (`entity_side_for_row`/`row_slot_path[_from]`/`column_rise_path`/`mancala_targets`),
  compression (`_begin_act`/`note_processing`/`get_delay`), `MAX_TICKS`/`act_overrun`.
- `Scripts/card_environment.gd` — `run_card_mods` (the only suit-seeing dispatch).

### 2.3 Statuses (Phase 2; Phase 5 visuals/localization)
- `Cards/card_modifier_status.gd` — `CardModifierStatus` base; merge/expiry/self-scope;
  `draw_icon` placeholder hook (Phase 5).
- `Cards/Statuses/status_{juggling,burning}.gd` — shipped statuses; localized; `draw_icon`.
- `Cards/Statuses/status_layer.gd` — **NEW** `StatusLayer` (runtime-drawn icons + `×N`).
- `Cards/card_data.gd` — `statuses: Array[CardModifierStatus]`, `add/remove/with_status`.
- Back-ref unlink/relink (suit + status cycles): `Scripts/game_data.gd`, `Scripts/run_manager.gd`.

### 2.4 Visual layer (Phase 4) + view seam
- `UI/prop_layer.gd` — **NEW** `PropLayer`; per-frame interpolation, `begin_prop_tick`, spawn/
  teleport/void anims, reaction state machine, `_slot_point`/`_staged_point`/`_void_point_of`.
- `Cards/Props/prop_visual.gd` — **NEW** `PropVisual` base (`art_size`, `travel_curve`,
  `face_travel`, `retarget`/`relocate_to`, placeholder `_draw`).
- `Cards/Props/Visuals/{hoop,knife,ball,fire,firework}_visual.gd` — **NEW** per-kind draw/arc.
- `UI/play_area.gd` — `prop_layer` accessor, `control_for_coord`/`slot_center_global`, tooltip wiring.
- `UI/play_area.tscn` — added `%PropLayer` Node2D under `SmoothScrollContainer/TopLevelVBox`.
- `Levels/game_view.gd` — `begin_prop_tick` delegate (replaced the Phase-1 stub).
- `Cards/card_visual.gd` — `anim_spin()`, `StatusLayer` creation + refresh.

### 2.5 Localization + settings + inspector text (Phase 5)
- `Locale/localization.csv` — new SUITS + STATUSES key sections.
- `Scripts/player_settings.gd` — `prop_tick_fraction` knob.
- `UI/control_card.gd` — `describe_card` appends suit effect + per-status lines.

### 2.6 Docs (Phase 6)
- `DESIGN_DOC.md` §10, `ARCHITECTURE_REVIEW.md` §1.6, `STATUS_EFFECTS_PLAN.md` banner,
  `SUIT_PROPS_PLAN_CHECKLIST.md`, `SUIT_PROPS_HANDOFF.md`.

### 2.7 Tests (committed)
Suites: `Tests/Engine/test_{prop_engine,statuses,suit_props,game_headless,game_data,mods}.gd`,
`Tests/E2E/test_e2e_run.gd`, plus updates to `test_{comparator,scoring,board,dispatch,iterator,
act_score,fuzz}.gd`, `Tests/Map/test_*`, `Tests/UI/test_ui_viewers.gd`. Support:
`Tests/Support/{pip_suit_test,status_test,status_test_b,status_test_scored,status_test_seal,
test_base,test_factories}.gd`, `Tests/all_tests.gd`.

---

## 3. MISSES, DEVIATIONS & SPECS TO AUDIT

Ordered by risk. Each names the spec it should match and how the build diverges.

### 3.1 Gameplay-facing behavior changes (headless-passing, NOT playtested for balance)
1. **`on_score` / `on_after_score` are now LIVE** (`game.gd _run_score_effects`). Previously every
   call site was commented out, so `SkillExtraPoint`, `StampDoubleTrigger`, `SkillEchoingTrigger`
   were dormant and **now fire**. Audit: intended per plan, but never balance-tested; verify no
   double-counting vs the outer scorer.
2. **Suits go live in ALL decks at Phase 3.** Any Hoop/Knife/Ball/Fire scored in a meld spawns
   props and mutates gutters/statuses. Fireworks are NOT in `STANDARD` (never random) — and there
   is **no path yet to grant Firework to a deck** (MISS: needs a deliberate grant mechanism).
3. **Per-meld double fire** (row + col membership → two spawns) is intended; confirm it isn't
   accidentally single/triple anywhere.
4. **Resume mid-submit alignment** (`game_view.gd load_board_visuals`): score-buffer gutters built
   BEFORE cards so a resumed scoring jump aligns. Audit by quitting mid-submission and resuming.

### 3.2 Prop-engine determinism & timing (Phase 1)
5. **Determinism rule**: no RNG in the sim; `entity_side_for_row` hashes only resume-persisted
   inputs (`submits_used`, `save_history.size()`, coord). Audit that nothing added later reads
   `randi()`/frame state inside a spawn/hook.
6. **Timing cases asserted INDIRECTLY**: prop mods can't see the absolute tick number headless, so
   train/speed, mixed speeds, same-slot silence, spawn-tick exclusion, and one-frame-headless are
   asserted via order/counts/live-cap only. **Exact timing is a Phase-4 VISUAL check** — audit the
   real animation, not just the tests.
7. **Runaway caps**: `MAX_TICKS` (2048) + `act_overrun` via `note_processing`/`HARD_CAP`. Confirm a
   pathological empty-route or million-prop spawner terminates and doesn't strand the await.

### 3.3 Phase-4 view-layer risks (the largest audit surface)
8. **`tick_done` is a PERSISTENT signal**, awaited by `game.gd` each tick. Correctness relies on
   the EVENTS phase (current prop mods are pure data, no view awaits) resolving in-frame so
   `await tick_done` registers before `PropLayer._process` next emits. **A future prop mod that
   awaits a multi-frame tween in `on_pass_card`/`on_finish` could race → the await misses the
   emission → HANG.** Recommended hardening: hand a fresh one-shot signal per tick. (Documented in
   handoff.)
9. **Reactions fire at TICK START (occupancy of `p.at`), NOT at visual arrival.** Data is one tick
   ahead, so a card jumps/spins as the prop *starts* approaching (anticipation). **Deviates from
   plan §4.2** which wants arrival-synced (fire when interpolation `t` crosses 1). Audit whether the
   anticipation reads acceptably or should be moved to arrival.
10. **Coordinate mapping** is content-local via `PlayArea.slot_center_global` (global center) +
    `PropLayer.to_local` (rides the scroll). **Empty slots past built rows fall back to column
    header + row offset** — audit that fallback for correctness. **Edge clipping of staged trains
    is UNVERIFIED** (plan §4.1 says widen margins / disable clip if trains pop).
11. **Despawn**: props that reach the void self-despawn via an independent tween
    (`PropLayer._despawn_visual`) — this fixed a bug where props `done` on the run's LAST tick were
    stranded (no next tick to prune). Audit: does every prop path free its visual exactly once
    (no leak, no double-free)? `_void_point_of` extrapolates along last travel dir.
12. **`face_travel`** rotates directional art (knife) to its travel angle in `retarget`; symmetric
    kinds (hoop/ball) leave it off. Audit orientation for diagonal/vertical (Firework rise,
    post-teleport) travel.
13. **`unique_id=2038411771`** on the new `%PropLayer` tscn node is an arbitrary value matching the
    project's node-header convention — confirm no collision.

### 3.4 Phase-5 status visuals & tooltips
14. **Status visual v1 is a PLACEHOLDER**: no `status_pips.png` asset; `CardModifierStatus.set_texture`
    is a no-op; `StatusLayer` draws primitives + `×N`. **MISS vs plan §5** which specified a
    Polygon2D slot + Label. Swap when the asset lands.
15. **StatusLayer position is set ONCE at `_ready`** (card top-left corner); a card-scale settings
    change won't reposition it. Minor.
16. **Tooltip is MOUSE-HOVER only** (`Control.tooltip_text = describe_card`). **MISS vs plan §5**:
    per-pip / per-status granularity and the keyboard/controller **focus** popup are NOT done
    (Godot only auto-shows tooltips on mouse hover; there's no play-area info panel). Left for
    runtime iteration. Multi-modal input is a project requirement (mouse+keyboard+controller).

### 3.5 Localization & settings (Phase 5)
17. **All suit/status UI strings** now `TRANSLATION.find('KEY')` with keys in `localization.csv`
    (SUITS/STATUSES sections). Audit: keys resolve after reimport; the pseudo-localization /
    "revealed" cycler still works; status descriptions keep `% stacks` post-`find`.
18. **`prop_tick_fraction`** moved to `PlayerSettings` (default 0.45). Existing settings `.tres`
    won't carry the field → loads the default (fine). game.gd compression consts
    (`COMPRESS_RATIO`/`STEP_MS`/`SOFT_MS`/`MIN_FACTOR`) remain consts — candidates to move if they
    should be player-tunable (not done).

### 3.6 Serialization / persistence (Phases 0/2)
19. **Suit self-cycle (`CardModifier.data`) + status back-refs** unlinked/relinked in **four** sites
    (`game_data.gd` ×2, `run_manager.gd` ×2). Audit all four round-trip. Props are never serialized
    (a quit mid-act replays from the pre-act board via `pending_action`).
20. **UNCHECKED verify item** (checklist 0.4, line 51): "print `card.suit.data == card` true after
    undo + add_deck". Never explicitly confirmed — audit this.
21. **Test infra**: `SolatroTest.backup_real_save()`/`restore_real_save()` move a real
    `user://run_save/run.tres` aside during disk tests. **Never reintroduce a save-existence
    `[SKIP]` guard.**

### 3.7 Intentional deviations from plan text (all noted in checklist, confirm still true)
- `CardModifierStatus.stacked(script, n)` is **script-based**, not polymorphic `static stacked(n)`
  (GDScript static funcs have no `self`).
- `spawn_props()` typed `-> Array[PropSpawner]` everywhere (plan left it untyped for Phase 0).
- `Game.get_delay()` delegates to `super.get_delay()` (avoids a compile-order typing error).
- The per-card prop hook is named **`on_prop_passed`** (STATUS_EFFECTS_PLAN text said
  `on_entity_passed`).

---

## 4. Suggested audit procedure

1. Reimport + run `all_tests.tscn`; confirm 19 suites / 1062 checks / exit 0.
2. Read `SUIT_PROPS_HANDOFF.md` end-to-end (it front-loads the caveats).
3. Data layer: verify `run_props` determinism & caps (§3.2), the four back-ref sites (§3.6), and
   that `run_card_mods` is the ONLY suit dispatch.
4. View layer: the `tick_done` race (§3.3 #8), reaction timing (#9), despawn accounting (#11),
   coord fallback + clipping (#10) — these need a **running game**, not just tests.
5. Balance: exercise a suit-laden board and watch the now-live `on_score` broadcasts (§3.1).
6. Confirm the open MISSES: Firework grant path (#2), status asset (#14), keyboard/controller
   tooltip focus (#16), unchecked serialization verify (#20).
