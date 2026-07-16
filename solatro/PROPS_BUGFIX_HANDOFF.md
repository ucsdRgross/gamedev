# PROP/STATUS SYSTEM — reference + bug-triage handoff (updated 2026-07-14)

THE authoritative doc for the **suit-props system** (built per SUIT_PROPS_PLAN.md, Phases 0–6
complete). The owner playtests, reports bugs, you fix. This doc gives you the map: design
rulings, architecture, landmines, tests, and the full PROP SYSTEM REFERENCE (file map →
recipes). Per-fix history was trimmed 2026-07-14 — git has it; only live implementation
details remain.
Architecture summary lives in `ARCHITECTURE_REVIEW.md` §1.6; locked design decisions in
`DESIGN_DOC.md` §10. (The interim docs SUIT_PROPS_HANDOFF / SUIT_PROPS_AUDIT_BRIEF /
SUIT_PROPS_PLAN_CHECKLIST / STATUS_EFFECTS_PLAN were retired 2026-07-13 — their live content
was folded in here and into ARCHITECTURE_REVIEW; git history has the originals.)

**Ground rules** (from memory + hard experience this session):
- The owner runs scenes AND tests from their editor. **Never run headless Godot while their
  editor has the project open — the two instances starve each other and your run hangs.**
  Check `Get-Process *odot*` + `MainWindowTitle` first; never kill a process with an editor
  window title (that's their session).
- No `git add`/commit. Type every array/for-iterator (warnings-as-errors). UI strings via
  `TRANSLATION.find` + `Locale/localization.csv`. Tuning knobs in `Scripts/player_settings.gd`.
- Full suite: `all_tests.tscn` — pin exit code / FAIL lines, never total check counts (fuzz
  suites vary per run). Run with NO `--quit-after` (it self-quits headless; `--quit-after`
  makes it idle the full duration and look hung). After adding a `class_name`: delete
  `.godot/`, run `--headless --path . --import` once (ignore the `yard` addon editor error +
  a cold-import `SettingsManager.settings` parse-error/segfault — clears on the next real
  run), then run tests. Reimport also regenerates `Locale/localization.en.translation`.
- Disk tests use `SolatroTest.backup_real_save()`/`restore_real_save()` to move a real
  `user://run_save/run.tres` aside — **never reintroduce a save-existence `[SKIP]` guard.**
- Warnings-as-errors gotchas: class-ref arrays in a func body must be `var … : Array[GDScript]`
  not `const`; duck-typed hook calls on a typed base go through `obj.call(&"hook", …)`.

## Standing design rulings + implementation notes (history trimmed 2026-07-14; git has it)

- **CardVisuals live on `%CardLayer`** (Node2D inside TopLevelVBox, sibling of PropLayer):
  scroll carries controls, cards, AND props together. Consequence: cards clip at the
  play-area rect (landmine 2) — the deck/discard fly-in is invisible outside it.
- **Suit-effect suppression is BY DESIGN**: a talented card suppresses its OWN suit effect
  (`PipSuit._spawn_origin`). Decks with talents on every card of a suit therefore never
  spawn that suit's props (deck9/deck10 show zero hoops by construction — documented on
  their builders). The default `get_deck()` is `deck11` (every suit has plain cards AND
  ExtraPoint talents); `deck12` is the only firework grant path; `deck13` = status stress.
- **Meld cards stay raised until all props finish** — `score_line` calls `view.reset_meld`
  AFTER `_run_score_effects`; move that call earlier if cards should drop first.
- **Only talents jump/spin**: both reaction hooks key on `card.skill` (`PropScoreTalents` ->
  JUMP, `PropScoreProps` -> SPIN). A plain card a knife scores gets no pose; add e.g.
  JUMP-for-plain in `PropScoreProps.reaction_for` if scored cards should react.
- **Card reactions are held group animations** (owner spec 2026-07-13/14): JUMP re-pulses
  per arrival AND holds while a jump-hinting prop OCCUPIES the card. SPIN STARTS on
  occupancy too (first spin prop ARRIVES over the card — never at spawn), then loops
  (`CardVisual.anim_spin_start`) while the card is still in any spin-hinting prop's
  remaining route (more coming: keep turning), winding down once via `anim_spin_stop`.
  `PropLayer._reacting` is `Dictionary[CardData, int]` bitflags (HOLD_JUMP|HOLD_SPIN);
  `abort_all` stops held poses explicitly. The spin loop is an INFINITE tween — never
  `custom_step(INF)` it (`anim_spin` guards on `_spin_holding`), and its revolution time
  floors get_delay() at 0.2s (a zero-duration looping tween trips Godot's
  infinite-loop guard, seen under manual prop stepping).
- **Formations are per-kind resources** — see the FORMATIONS section below. play_area.tscn
  contains NO formation node.
- **Undo can cancel a resolving act**: `act_cancelled` -> `get_delay()` 0, `run_props`
  breaks, manual-step hold releases, `_restore_pre_act_board` -> `PropLayer.abort_all`.
  Full contract: ARCHITECTURE_REVIEW §1.7. Fame banks at Continue (`exit_show`).
- **Tests never ride `Decks/deck.gd`** — it is the owner's freely-changing playtest deck.
  Seeded/crafted tests build FROZEN compositions from `Tests/Support/test_decks.gd`
  (`TestDecks`: `seeded_deck()` = deck9 freeze the 424242/31337 observations replay against,
  `standard_rules()`, `minimal_deck()`). Existing TestDecks functions are replay contracts —
  add new ones, never edit. `game.gd:218` SHOULD follow the live `get_deck()`.
- **Suits are referenced by exact class** (`PipSuitHoop`, ... via `PipSuit.ALL_SUITS` /
  `STANDARD`), never by index — `PipSuit.from_index` was deleted deliberately.

## FORMATIONS — condensed spawn patterns (owner spec 2026-07-13)

- **Data**: `Cards/Props/formation_data.gd` (`PropFormationData`: ONE pattern of UNSCALED
  card-space points, all inside one card footprint, plus its `mode`) +
  `Cards/Props/formation_set.gd` (`PropFormationSet`: all of a kind's formations). Loaded
  from `Cards/Props/Formations/<kind>.tres`; a MISSING file = no formation = exact
  slot-line flight — the DEFAULT for every kind until the owner authors one.
- **Runtime** (`PropLayer._assign_formation_offsets`): each spawn tick batches spawns by
  (kind, origin); each batch draws ONE formation (seeded — replay-identical, varies across
  batches via `_spawn_index`) and maps props onto its points per the formation's `mode`:
  DETERMINISTIC = exact point-list order (prop i -> point i), RANDOM = seeded shuffle of
  the list (points only — no repeats until all are used, never random free positions).
  Either way extras wrap (overflow separates in TIME via countdown stagger, never widens
  past the card) and a full batch fills every point. Offsets are view-only
  (`PropVisual.lane_offset` = point * card_scale; the prop ART is never scaled);
  data/replay never see them.
- **Authoring**: open `Cards/Props/Tools/formation_editor.tscn`, select the root node —
  inspector only: kind dropdown (auto-loads its set), formation index + mode dropdown
  (DETERMINISTIC/RANDOM, saved per formation), add/delete formation, generators
  (grid/ring/scatter/line + count/spacing/jitter/seed), hand-editable points (out-of-card
  points draw RED), SAVE writes the kind's .tres. Preview spawns REAL PropVisuals over the
  assigned points (`PropVisual` + subclasses are @tool for this) at their true in-game
  size — `preview_scale` scales the card footprint and point offsets ONLY, mirroring
  card_scale; set it to the live card_scale for exact parity. Counts beyond one formation
  spill into extra columns, each with its own seeded formation — adjacent in-game slots.
  Card footprint/stack drawings are debug scenery only (scale/stack/pitch knobs).

## Architecture in 6 lines

- `Game.run_props` (game.gd ~:528) — the DATA simulation: integer ticks, one step AHEAD of the
  view. Per tick: SPAWN → MOVE → `view.begin_prop_tick(live, spawned, movers, relocated)`
  (NOT awaited) → EVENTS (3-phase pass) → FINISH → `if view and view.prop_tick_pending():
  await tick_done`.
- `GameView.begin_prop_tick` delegates to `PlayArea.prop_layer` (**UI/prop_layer.gd**,
  `PropLayer`, Node2D inside the scroll content so props ride the scroll).
- `PropLayer._process` drives interpolation per frame against the LIVE tick seconds
  (`game.get_delay() * SettingsManager.settings.prop_tick_fraction`, re-read every frame).
  Each visual has `from/target/t` + `span_ticks` (= prop's `ticks_per_slot`; a leg spreads
  continuously over that many ticks) + `t_goal` (per-tick ratchet; `tick_done` fires when all
  visuals reach their goal — never waits a whole leg).
- Coords: `PlayArea.slot_center_global(v)` = **card anchor**, PURE MATH since 2026-07-15 (zone
  hbox origin + column/row pitch + half `card_size_play`; NO control reads, one formula for
  occupied/empty/off-board slots). `PropLayer._slot_point` = `to_local` of that.
- `Cards/Props/prop_visual.gd` + `Cards/Props/Visuals/*` = per-kind placeholder draw
  (kind: 0 hoop 1 knife 2 ball 3 fire 4 firework) + `travel_curve` shape (ball/fire arc).
- Statuses draw via `StatusLayer` (runtime child of CardVisual, `CARD_SIZE`-anchored);
  card text via `ControlCard.describe_card` shown in the **focus inspector panel**
  (play_area.gd) — the native tooltip is deliberately gone.

## Landmines that already bit us (check these FIRST for any new bug)

1. **SmoothScrollContainer rewrites every Control entering its subtree to
   `MOUSE_FILTER_PASS`** (`addons/SmoothScroll/smooth_scroll_container.gd _on_node_added`).
   Any display-only Control under the scroll content MUST
   `set_meta("_smooth_scroll_default_mouse_filter_set", true)` BEFORE `add_child` or it
   becomes a click-blocking hit-target. This was the "descriptions block clicks" bug.
2. **The ScrollContainer clips at the play-area rect** (`clip_contents` default). Anything
   staged/exiting past the rect is INVISIBLE — deep off-board staging made whole hoop bursts
   never render. Staging is therefore compressed to ≤ ~1.5 slot pitches behind the route
   entry (`PropLayer._staged_point`). If props "disappear", suspect clipping before code.
3. **Slot y-geometry**: row controls are thin strips, each column's LAST control is full card
   height, headers resize with focus. Anything reading control rects for slot positions will
   zig-zag — which is why `slot_center_global` is now pure math (2026-07-15) and prop geometry
   must NEVER go back to control reads. Related trap: a fanned card is a full card TALL behind
   its visible strip, so "which card is under this point" tests pick cards from the wrong row
   (short-column hoop bracket bug, 2026-07-16) — use the prop's anchor slot + `body_size`
   overlap instead (`PropLayer._apply_split`/`_body_over_any_card`).
4. **`tick_done` is a persistent signal**: the Game awaits it only while
   `view.prop_tick_pending()`. Don't emit or await it any other way.
5. **`submits_used` lives ON `GameData`** (`@export_storage`) so undo/history snapshots rewind
   it; `Game.submits_used` is a forwarding property. Any new per-show counter that undo must
   rewind belongs on GameData, not Game.
6. **Despawn is kind-dependent** (`PropLayer._despawn_visual`): route travelers (captured at
   spawn as `vis.exits_into_void = route.size() >= 2`) exit one slot pitch along their travel
   line — as a leg in `_drive_exiting`, re-pinned to their last slot, NEVER a fixed-pixel
   tween; ballistic props poof (scale+fade) IN PLACE — continuing their diagonal read as
   "flying off in a random direction".
7. **Props with `ticks_per_slot > 1`** must move CONTINUOUSLY (span_ticks/t_goal). If motion
   stutters, someone forgot to pass `float(prop.ticks_per_slot)` to `retarget` or broke the
   ratchet at the top of `begin_prop_tick`.
8. **The focus inspector panel is a PERMANENT `prop_layer` child** re-pinned beside its
   anchor control every frame (`PlayArea._process`); it hides itself when the anchor is freed
   (rebuilds also hide it up front in `set_card_zones`). It must stay
   `MOUSE_FILTER_IGNORE`/`FOCUS_NONE` + the addon meta (landmine 1). Do NOT reparent it under
   controls again — that was a workaround for cards lagging the scroll, fixed via CardLayer.

## Tests that guard all this

`Tests/UI/test_ui_props.gd` (suite "UI PROPS", runs second-to-last; E2E waits on it — never
make it wait on E2E or they deadlock). Suite ordering chain (each owns CURRENT/save/settings
while it runs): everything else → INTERACTION (`Tests/Interaction/test_interaction.gd`,
multimodal input incl. mid-submit undo-cancel + game-over overlay) → UI PROPS → E2E.
Notables:
- `test_row_prop_never_leaves_its_row` — one CONTINUOUS per-frame sampler (`_sample_flight`,
  spawn to node-free, no per-tick gaps) against a LIVE row band + x-span envelope, with a
  mid-flight focus-resize relayout poke. **Extend this pattern for any new "prop moved
  weirdly" report**: reproduce the route, sample raw positions, assert the envelope and
  `_direction_changes` (which prints every turn with its position).
- `test_each_kind_moves_as_expected` — hoop/knife/ball/fire through the ONE shared
  travel_curve, asserted from raw sampled positions (no x reversals; ballistic = exactly one
  vertical turn, lands at target).
- `test_ballistic_despawn_poofs_in_place` — ball stays within half a card of its target
  through despawn.
- `test_slow_props_move_continuously` — tps=2 legs spread over both ticks (uses a locally
  slowed base_delay: at FAST_DELAY one frame can overshoot a leg and false-fail).
- Inspector tests — IGNORE/FOCUS_NONE, no tooltip_text, reparenting, hide paths.
- `test_game_view_submit_with_props` — REAL `game_view.tscn` submit under a watchdog (a
  prop-tick sync bug FAILS instead of hanging), now with per-frame LIVE-SEAM guards: every
  hoop/knife must hold its anchor row's y through the whole submit (catches the live
  diagonal that synthetic fixtures missed) and every kind that spawned must enter the
  visible viewport at least once (catches invisible hoops). The suite backs up
  `settings.tres` (Settings writes to disk on every change) and `run.tres`.
- `test_batch_props_stagger` — batch mates map onto an injected PropFormationSet's points
  (cache-injected; no .tres on disk is read or required).
`Tests/Engine/test_game_headless.gd`: `test_undo_rewinds_act_count`, suit-backref checks.

# PROP SYSTEM REFERENCE — full lifecycle, files, variables, knobs

The authoritative "where do I edit X" map. Sections: file map -> data types -> spawn ->
the tick loop -> the view pipeline -> timing -> structures -> recipes.

## R1. File map

| File | Role |
|---|---|
| `Cards/Props/prop_data.gd` (`PropData`, RefCounted) | ONE live prop's data: position, route, speed, mods. Transient — never serialized (quit mid-act replays the act). |
| `Cards/Props/prop_spawner.gd` (`PropSpawner`, RefCounted) | One scored card's emission plan (how many, how fast, factory). |
| `Cards/Props/prop_modifier.gd` (`PropModifier`, RefCounted) | Behavior unit; all prop behavior composes as a list of these. Duck-typed hooks. |
| `Cards/Props/prop_visual.gd` (`PropVisual`, Node2D) | View twin: draw + trajectory params. NO PropData retention. |
| `Cards/Props/Visuals/*.gd` | Per-kind subclasses: placeholder `_draw_body` + `art_size`/`color`/`face_travel`/`arc_height`. NO movement code of their own. |
| `Cards/Props/formation_data.gd` (`PropFormationData`) + `formation_set.gd` (`PropFormationSet`) | Per-KIND condensed spawn patterns (card-space points -> per-prop `lane_offset`), loaded from `Cards/Props/Formations/<kind>.tres`; missing file = slot-line flight. Authored via `Cards/Props/Tools/formation_editor.tscn` (standalone @tool scene, inspector buttons only). |
| `Levels/game.gd` -> `run_props`, `_run_score_effects`, path helpers (§1.6) | THE simulation: the tick loop, spawn/move/events/finish, sync with the view. |
| `Levels/game_view.gd` -> `begin_prop_tick`, `prop_tick_pending` | The seam: forwards to PlayArea's PropLayer. Headless = no view = no visuals, whole run resolves in one frame. |
| `UI/prop_layer.gd` (`PropLayer`, Node2D in the scroll content) | ALL prop animation: visuals lifecycle, per-frame interpolation, repin, exits, card reactions. |
| `UI/play_area.gd` -> `slot_center_global`, `control_for_coord` | Slot coord -> pixel geometry (the ONLY coordinate authority). |
| `Cards/Pips/Suits/pip_suit_*.gd` -> `spawn_props()` | Per-suit emission definitions (what a scored card actually launches). |
| `Tests/UI/test_ui_props.gd` | The view-side guard suite (see "Tests that guard all this"). |
| `Tests/Engine/test_prop_engine.gd` | Data-side simulation tests (headless). |

## R2. Data types, field by field

**`PropData`** (all mutable from ANY hook mid-flight — the tick loop re-reads next tick):
- `at : Vector3i` — slot currently over; `Vector3i.MIN` until first entry / after unresolved
  teleport. Drives events (which card's hooks fire) and reactions.
- `route : Array[Vector3i]` — slots AHEAD, `[0]` = next to enter, popped on entry. Rewriting
  it (`set_route`, `teleport`) IS how effects re-route props.
- `countdown : int` — ticks until it pops `route[0]`. Staging/train stagger lives HERE
  (spawner sets `ticks_per_slot + i` for the i-th of a batch), never in the route.
- `ticks_per_slot : int` — per-prop speed; countdown resets to this on each slot entry.
  1 = one slot per tick. Knife/hoop use 2 (`KNIFE_TICKS_PER_SLOT`/`HOOP_TICKS_PER_SLOT`).
- `done : bool` — set by the MOVE stage when the route is exhausted; FINISH + despawn follow.
- `pass_negated : bool` — phase-1 dodge flag for the CURRENT pass only; auto-cleared.
- `mods : Array[PropModifier]` — ALL behavior. `kind : int` — pure visual selector
  (0 hoop 1 knife 2 ball 3 fire 4 firework). `fire_stacks : int` — flame-tip visual count.
- `source : CardData` — origin card; must tolerate that card leaving the board.
- `reloc_sink : Array` — injected per tick by the loop; `teleport()` records
  `[prop, from, to]` here so the view blinks instead of tweening.

**`PropSpawner`**: `origin` (captured coord, survives card removal), `remaining`,
`batch_size` (emitted per due tick), `interval` (ticks between emissions), `max_live`
(concurrency cap; emission resumes as props finish), `live`/`emitted` (engine-maintained),
`factory : Callable(emit_index) -> PropData` (PURE — routes/targets precomputed at
spawn-plan time). Emission modes: hoops/knives = `batch_size == remaining` burst (train);
ball/fire = `batch_size 1, interval 1` sequential drops.

**`PropModifier` hooks** (duck-typed via `has_method`, awaited):
- `on_spawned(prop, game)` — once at emission, before first move.
- `on_pass_card(prop, game, card)` — PHASE 2 of a pass: THE effect. Skipped when negated.
- `on_finish(prop, game)` — route exhausted / ballistic arrival, before despawn.
- `reaction_for(prop, card) -> PropData.Reaction` — pure view hint (JUMP/SPIN/JUGGLE/BURN).
Card-side counterparts (on `CardModifier`s, via `game.run_card_mods`):
- `on_prop_passing(prop)` — PHASE 1: may call `prop.negate_pass()` (dodge/intercept).
- `on_prop_passed(prop)` — PHASE 3: notification, fires even when negated.

## R3. Spawn definitions (who launches what)

`Game._run_score_effects(result)` (game.gd, called by `score_line` per scored row/col meld):
1. For each meld card with a suit: `card.suit.spawn_props()` -> `Array[PropSpawner]`.
   Shared helpers on `PipSuit`: `_spawn_origin()` (the card's coord or MIN), `_spawn_count()`
   (pip count + Burning bonus), `_burning_mods()` (extra mods when the card burns).
2. ALL spawners feed ONE `run_props(spawners)` call — suits interleave deterministically.
3. Afterwards: `run_all_mods("on_score", card)` per meld card, then `on_after_score`.

Per suit (each ~30 lines, the template to copy for a new suit):
- `pip_suit_hoop.gd` — kind 0, `row_slot_path(v, entity_side_for_row(v))`, burst train,
  tps 2, `PropScoreTalents` (+`HOOP_POINTS` per talent passed).
- `pip_suit_knife.gd` — kind 1, SAME row but `not entity_side_for_row(v)` (opposite edge),
  burst train, tps 2, `PropScoreProps` (+`KNIFE_POINTS` per plain card; self-scored by design).
- `pip_suit_ball.gd` — kind 2, ballistic: `mancala_targets(v, count, has-skill)` picked at
  spawn, one per tick, `PropDropStatus(StatusJuggling, JUGGLE)`.
- `pip_suit_fire.gd` — kind 3, ballistic like ball but eligibility = plain non-Fire cards,
  drops `StatusBurning` (BURN).
- Firework (kind 4) — `column_rise_path`; currently NO grant path (not in PipSuit.STANDARD).

Path helpers + determinism (game.gd §1.6): `entity_side_for_row` (replay-stable hash of
`submits_used`/history/coords — data, not RNG), `row_slot_path`, `row_slot_path_from`
(re-routes), `column_rise_path`, `mancala_targets` (pure, computed once).

## R4. The tick loop — `Game.run_props(spawners)` (game.gd ~:539)

State: `live_props : Array[PropData]` (ARRAY: emission order IS hook order — the determinism
guarantee), `owner_of : Dictionary` prop->spawner (identity lookup to release `live` slots),
`tick : int`. Loop runs while any prop lives or any spawner has `remaining`; cut short by
`act_overrun` (runaway cap via `note_processing`) or `MAX_TICKS` (2048).

Per tick, in order:
1. **SPAWN** — each `due(tick)` spawner emits up to `min(batch_size, remaining,
   max_live - live)` props via `factory.call(emitted)`. Each gets
   `countdown = ticks_per_slot + i` (train stagger). Hook: `on_spawned`. Appended to
   `spawned` (this tick's report) and `live_props`.
2. **MOVE** (instant, data only; spawn-tick props skipped — no pop-and-teleport) — per prop:
   inject `reloc_sink`; `countdown -= 1`; still > 0 -> nothing fires this tick; at 0: empty
   route -> `done = true`, else `at = route.pop_front()` (re-read HERE so hook rewrites
   count), `countdown = ticks_per_slot`, append to `movers`.
3. **START the visual tick** — `view.begin_prop_tick(live_props, spawned, movers, relocated)`
   — NOT awaited; animation runs in parallel with step 4. `relocated` = teleport records.
4. **EVENTS** — for each MOVER in emission order, if its slot has a card
   (`find_vec3_data(p.at)`; may have emptied mid-flight): `note_processing()`, then the
   3-phase pass: `on_prop_passing` (card, may negate) -> `on_pass_card` (prop, the effect,
   skipped if negated) -> `on_prop_passed` (card, notification). `pass_negated` cleared.
5. **FINISH** — for each `done` prop: `on_finish`, release `owner_of` spawner `live` slot.
6. `skill_active_check()` — once per tick; hooks may flip skill active states.
7. **SYNC** — `if view and view.prop_tick_pending(): await tick_done`. The pending check is
   MANDATORY (landmine 4): `tick_done` is persistent; a blind await after the emission hangs.
8. `live_props = live_props.filter(not done)`; `tick += 1`.

Data is one tick AHEAD of the view (physics-interpolation style): the view animates tick N
while the data already computed it. Score writes from prop effects go through
`add_line_score` (THE single line-score write path; feeds row/col totals + gutters + label
anim when a view exists).

## R5. The view pipeline — `PropLayer` (UI/prop_layer.gd)

A Node2D INSIDE the scroll content (SmoothScrollContainer/TopLevelVBox), so the scroll
transform carries props, cards (CardLayer), and controls together.

State:
- `_visuals : Dictionary[PropData, PropVisual]` — data->node map (identity; order-free).
- `_exiting : Array[PropVisual]` — void-exit legs, still driven+repinned after their prop
  left `_visuals` (their PropData is done/gone).
- `_reacting : Dictionary[CardData, Dictionary]` — held jump/spin poses (rising-edge fires).
- `_tick_active : bool` — the `prop_tick_pending()` truth; `tick_done` emits when every
  visual reached its `t_goal`.
- `_spawn_index : int` — running spawn count folded into each batch's formation seed.
- `_formation_sets/_formation_checked` — lazy per-kind PropFormationSet cache (null = none);
  tests pre-seed the cache instead of touching the shipped .tres files.

**`begin_prop_tick(live, spawned, movers, relocated)`** — one data tick's animation orders:
1. `play_area.flush_rebuild()` (geometry must match current revision).
2. Ratchet every visual's `t_goal += 1/span_ticks` (slow props keep moving through
   no-new-slot ticks — landmine 7).
3. SPAWNED: `_make_visual` (kind -> subclass), assign the STORED formation point + spread flag
   from `_assign_formation_points` (per-(kind,origin) batch onto the kind's PropFormationSet
   points, seeded; none when no set; hoops always skip — card center); the pixel `lane_offset`
   is derived LIVE per frame from settings (`_refresh_lane_offset` — card scale / separation
   changes re-project mid-flight). Position at `_staged_point(prop, origin) +
   lane_offset` (route travelers: <= ~1.5 slot pitches behind the route entry, compressed —
   landmine 2; ballistic: at the source card, lifted 6px per countdown step), capture
   `exits_into_void = route.size() >= 2`, stationary `retarget`, set `anchor_coord` =
   route entry (or origin) + `anchor_point`, rotate `face_travel` art down the route.
4. RELOCATED: `relocate_to(_slot_point(at) + lane_offset)` — instant + flash, never lerp —
   re-anchor.
5. MOVERS: `retarget(_slot_point(prop.at) + lane_offset, float(ticks_per_slot))` — new leg
   from current position — re-anchor to `prop.at`.
6. DONE props (still in `live` this tick): `_despawn_visual` — route travelers: leg to
   `_void_point_of` (one last-leg-length pitch along the travel line) pushed onto
   `_exiting`; ballistic: scale+fade poof tween IN PLACE (landmine 6).
7. `_update_reactions(live, movers)` — every MOVER arrival replays its reactions on the card
   it entered (one anim per prop — trains re-trigger); the JUMP pose holds while any
   jump-hinting prop occupies the card and resets when the last leaves. Only prop-raised
   cards are tracked/reset — never the meld-score jump pose.
8. `_prune_done(live)` — fade+free any visual whose prop silently left `live`.
9. `_tick_active = true`; return the `tick_done` signal.

**`_process(delta)`** — every frame:
1. `_repin` EVERY visual in `_visuals`: shift `from`/`target`/`position` by however much
   `anchor_coord`'s live point moved (relayouts: score labels growing, focus resizes,
   rebuilds); also `_refresh_lane_offset` (live formation offset) and the live art scale
   (`card_scale / PropVisual.AUTHORED_CARD_SCALE`). Skips MIN anchors.
2. `_drive_exiting`: same repin + same interpolation for void exits, INDEPENDENT of
   `_tick_active` (a run-final exit must complete); on arrival: fade
   (`prop_fade_fraction` of get_delay) + free.
3. If `_tick_active`: advance each leg — `t += delta / (current_tick_seconds() *
   span_ticks)` (secs re-read LIVE every frame; 0 -> snap), `position =
   travel_curve(from, target, min(t, 1))`. When all visuals reach `t_goal`:
   `_tick_active = false`, emit `tick_done`.

**`PropVisual` interpolation state** (owned by PropLayer): `from`/`target` (content-local
pixels), `t` (0..1 along the leg), `span_ticks` (data ticks the leg spans = ticks_per_slot),
`t_goal` (per-tick ratchet), `anchor_coord`/`anchor_point` (live-board repin),
`lane_offset` (formation spread), `exits_into_void`, `arc_height`, `face_travel`.
`travel_curve(a, b, u)` = THE one movement function: `a.lerp(b, u)` minus
`arc_height * 4u(1-u)` — kinds differ ONLY by `arc_height` (ball 28, fire 24, rest 0).

**Geometry** (play_area.gd): `slot_center_global(v)` = PURE MATH (zone hbox origin +
column/row pitch + half `card_size_play`; no control reads, one formula for every slot —
2026-07-15); `control_for_coord` (focus/input only) walks upper/lower_zone_right -> vbox
children (child 0 = header, z == -1); `row_card_visuals(v)` = the row's visuals across all
columns (PropLayer's row-bracket source).

## R6. Timing + tuning knobs

| Knob | Where | Effect |
|---|---|---|
| `base_delay` | `Scripts/player_settings.gd` (`SettingsManager.settings`) | Global animation delay; everything scales off it. |
| `prop_tick_fraction` (0.45) | player_settings.gd | Seconds per prop tick = `game.get_delay() * this`. Bigger = slower props. Read LIVE every frame. |
| `get_delay()` compression | PlayerSettings `compress_ratio`/`compress_step_calls`/`compress_min_factor`/`compress_soft_calls` — per-ACTIVATION via `act_calls`, no wall clock (2026-07-16) | Long acts shrink the delay; props retime mid-flight automatically (nothing locks in durations). |
| `ticks_per_slot` | per prop (suit constants) | Data speed: slot residency in ticks. |
| `countdown` at emission | run_props SPAWN (`+ i`) | Train stagger spacing in ticks. |
| Staging compression (1 + 0.15/pitch, cap 0.5) | prop_layer `_staged_point` | How far behind the entry a burst queues. |
| Exit distance (last leg length, min card width) | prop_layer `_void_point_of` | How far past the edge exits travel. |
| `arc_height` | each Visuals subclass `_init` | Ballistic hump height. |
| Formation points / sets | `Cards/Props/Formations/<kind>.tres` via the formation editor tool | Per-kind batch spread patterns (card-space, fit one card; no file = slot-line flight). |
| `max_live`, `batch_size`, `interval` | each suit's `spawn_props()` | Emission shape/concurrency. |
| `MAX_TICKS` (2048, game.gd) + `act_event_cap` (PlayerSettings) | game.gd `note_processing` | Hard stops for infinite props. |
| `manual_step` / `step()` | prop_layer.gd (GameView debug buttons, bottom-right) | Hold each finished visual tick until stepped — watch a run tick by tick. |

## R7. Why each container is what it is

- `spawners`, `live_props`, `spawned`, `movers`, `relocated`, `_exiting`, `mods`, `route` —
  Arrays because ORDER is semantics (hook order, emission order, travel order).
- `owner_of`, `_visuals`, `_reacting`, `data_ui`/`ui_data`/`data_card` (play_area) —
  Dictionaries because they're identity lookups with no meaningful order.
- `reloc_sink` is injected per tick (not a signal) so teleports are captured exactly in the
  tick report the view is about to animate.

## R8. Recipes — "to change X, edit Y"

- **Prop speed (visual)**: `prop_tick_fraction` in player_settings.gd. **(data)**: the
  suit's `ticks_per_slot`.
- **Spread pattern (formations)**: open `Cards/Props/Tools/formation_editor.tscn`, select
  the root node — kind dropdown, generate/hand-edit points, SAVE writes the kind's
  `Formations/<kind>.tres`, preview spawns real prop visuals (overflow = extra columns).
  Delete the .tres to return a kind to slot-line flight.
- **New prop kind**: add `Visuals/<kind>_visual.gd` (set `art_size`/`color`/`face_travel`/
  `arc_height`, override `_draw_body`), extend the match in `PropLayer._make_visual`,
  pick the next `kind` int, launch it from a suit's `spawn_props()`.
- **New prop effect**: new `PropModifier` subclass implementing the R2 hooks; append it in
  the suit factory. Score through `game.add_line_score` (+ `row_gutter(v)` for rows).
- **New card counter-effect**: `on_prop_passing` / `on_prop_passed` on a CardModifier.
- **Re-route mid-flight**: from any hook, `prop.set_route(game.row_slot_path_from(...))` or
  `prop.teleport(coord, new_route)` — never touch `at`/`route` from the view.
- **Movement shape**: `PropVisual.travel_curve` — the ONLY movement function; add a knob
  like `arc_height` rather than overriding per kind.
- **Staging/exit look**: `_staged_point` / `_void_point_of` / `_despawn_visual` in
  prop_layer.gd — keep everything anchored (`anchor_coord`) or it will drift on relayout.
- **Reactions (card poses under props)**: `reaction_for` on the prop mod +
  `_update_reactions` in prop_layer.gd. JUMP = re-pulse per arrival + hold by occupancy;
  SPIN = continuous loop while inbound (`anim_spin_start`/`anim_spin_stop`, see the
  standing rulings section); one-shot statuses (JUGGLE/BURN) are status visuals, not poses.

## Known-open / unverified (as of this handoff)

- Owner has NOT yet re-verified: description panel scroll-lock, knife row behavior, hoop
  visibility (clipping/staging fix), ballistic poof, undo-across-submit, held-loop spin,
  the formation system + editor tool end-to-end (no formation .tres authored yet).
- Hoop vs knife visual symmetry: they cross the same row in OPPOSITE directions
  (`entity_side_for_row`); if one side still misbehaves, suspect the staged/void points near
  the clipped board edges (landmine 2).
- A general in-run firework acquisition mechanism (booster/shop) beyond deck12 is still an
  owner decision.
- Still open owner decisions: per-pip tooltip granularity (focus inspector shows whole-card
  text only), real `status_pips.png` asset (StatusLayer + `draw_icon` are placeholders),
  ~~moving the game.gd compression consts into PlayerSettings~~ — DONE 2026-07-16, and
  reworked to per-activation compression (see FORMATION_LAYERING_HANDOFF.md rounds 2-4).
- Balance of the now-live `on_score`/`on_after_score` broadcasts — never balance-tested.
