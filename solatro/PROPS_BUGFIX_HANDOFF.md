# PROP/STATUS SYSTEM — reference + bug-triage handoff (2026-07-12/13)

THE authoritative doc for the **suit-props system** (built per SUIT_PROPS_PLAN.md, Phases 0–6
complete). The owner playtests, reports bugs, you fix. This doc gives you the map: fix log,
architecture, landmines, tests, and the full PROP SYSTEM REFERENCE (file map → recipes).
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

## Fixed this round (2026-07-12, unverified by owner)

1. **Cards lagged scrolling** — CardVisuals were children of the PlayArea ROOT, outside the
   scroll content, so they chased their anchors' scrolled globals through the `_process` ease.
   Now they live on `%CardLayer` (a Node2D inside TopLevelVBox, sibling of PropLayer): the
   scroll transform carries controls, cards, AND props together, and the ease only ever
   animates genuine anchor-relative travel. NOTE: cards now clip at the scroll rect like props
   (landmine 2) — the deck/discard fly-in is invisible outside the play-area rect.
2. **Focus inspector un-reparented** — with cards riding the scroll, the child-of-control
   workaround is gone: the panel is a PERMANENT prop_layer child, re-pinned beside its anchor
   control every frame (`PlayArea._process` -> `_position_focus_info`; hides itself if the
   anchor was freed by a rebuild).
3. **Diagonal prop drift** — legs locked in PIXEL geometry; any container relayout mid-flight
   (score labels growing as lines bank, focus resizing headers/rows) moved slot centers from
   under them and the leg walked a diagonal to a stale point — worst OFF-BOARD, where staged
   trains and void exits had no live slot at all. EVERY visual now carries
   `PropVisual.anchor_coord` (its slot target, the route entry while staged, the last slot
   during a void exit) and `PropLayer._repin` shifts from/target/position by the anchor's
   live delta EVERY frame — staged trains, mid-leg waits, and exits included. Void exits are
   now normal legs through `_drive_exiting` (same travel_curve/timing, tick-independent,
   fade+free on arrival), NOT fixed-pixel tweens.
4. **One shared movement function** — Ball/Fire's duplicated `travel_curve` overrides are
   gone; base `PropVisual.travel_curve` = line + optional parabolic hump via `arc_height`
   (ball 28, fire 24, everything else 0). Kinds differ ONLY by that knob.
5. **Tests now read RAW visual output** — `_sample_flight` captures a visual's position EVERY
   frame from spawn to node-free in one continuous loop (the old per-tick polling had gaps
   and only checked y on despawn); `_direction_changes` derives direction flips from the
   samples and PRINTS each with its position. Movement samples are taken RELATIVE to a live
   board anchor (`origin` callable): the whole board moves as one under smooth-scroll settle
   and relayouts, and global-space sampling flagged that shared wobble as prop turns (the
   first ball/fire failures). `settle()` also waits for slot geometry to hold still 3 frames.
   The row test pokes a mid-flight focus-resize relayout and holds the prop to the LIVE row
   y; `test_each_kind_moves_as_expected` covers hoop/knife (straight one-way sweep) and
   ball/fire (monotonic x, exactly one vertical turn, lands at target).
6. **Ballistic hop at spawn (2026-07-13)** — the stationary staged pose is a retarget to
   itself, and `travel_curve` applied the arc hump to that zero-length "leg": balls/fires
   visibly hopped in place at their card before the real flight (the extra y direction-flips
   the movement tests caught). `travel_curve` now skips the hump when `from == target`.
7. **THE live diagonal: empty-column header inflation (2026-07-13)** — `update_card_zone_
   visuals` gives every column's LAST control full card height; in a COMPLETELY EMPTY column
   the header IS the last control, so `slot_center_global`'s fallback (header BOTTOM + ...)
   put that column's slots a whole card below the row. Row paths span every column, so props
   entering or crossing empty columns (the usual live board shape — empty edge columns!)
   staged and swept diagonally. The fallback now anchors to the header TOP (vbox tops align
   across columns; occupied headers are 0-high), which IS the row line. Guarded by a
   `test_slot_geometry` pin, the row test's now-empty entry column, and the live-seam tests.
8. **Live seam now exercises ALL kinds** — the seeded submit spawns only knives, so
   hoops/balls/fires never touched the real view in tests ("hoops invisible in game view"
   slipped through). `test_all_kinds_live_in_game_view` crafts a board (incl. an empty edge
   column) where one `_run_score_effects` pass fans all four kinds through a REAL GameView,
   with per-frame guards: each kind spawned + visible in the viewport at least once, and
   hoops/knives hold their row (stray reports include anchor + leg endpoints).
9. **Reactions fire per ARRIVAL (2026-07-13)** — `_update_reactions` was edge-triggered on a
   boolean, so a TRAIN of props crossing the same card animated it only once ("cards don't
   reliably spin"), and it tracked cards with NO reaction, anim_reset-ing them when a prop
   merely passed over — stomping the meld-score jump pose it didn't own. Now: every MOVER
   arrival replays its reactions (one spin per knife), the JUMP pose holds while any
   jump-hinting prop occupies the card, and ONLY prop-raised cards are ever reset. NOTE: meld
   cards staying raised until the knives finish is BY DESIGN — `score_line` calls
   `view.reset_meld` after `_run_score_effects`; move that call earlier if the owner wants
   cards to drop before the props fly.
10. **WHY HOOPS NEVER APPEAR IN REAL PLAY (2026-07-13)** — not a rendering bug: the active
   starter deck (`Decks/deck.gd` `deck9`, also deck10) gives EVERY hoop-suited card
   (`from_index(0)`) a `SkillExtraPoint` — and a talented card suppresses its own suit effect
   (`PipSuit._spawn_origin`, by design). Hoops literally cannot spawn with these decks. Fire
   is half-suppressed the same way (rank-4 fires carry skills). OWNER DECISION: change the
   deck lists or the suppression rule. `test_all_kinds_live_in_game_view` proves the whole
   hoop pipeline works when a skill-less hoop card scores.
11. **Manual prop stepping (owner tool)** — `PropLayer.manual_step` + `step()`: when ON, each
   finished visual tick HOLDS (motion frozen at the boundary, `tick_done` withheld, so
   run_props pauses at its SYNC await) until stepped. GameView builds two debug buttons in
   `_add_prop_debug_controls` (bottom-right: "Prop Step" toggle + "Tick +1", FOCUS_NONE,
   localized keys DEBUG_PROP_STEP_MODE / DEBUG_PROP_STEP_TICK).
12. **Staggered volleys (owner request)** — `Cards/Props/prop_formation.gd` (`PropFormation`,
   @tool Node2D child of PropLayer in play_area.tscn): a plotted set of UNSCALED card-space
   points, drawn over a card footprint in the editor. Each spawned prop takes one as its
   `lane_offset` (DETERMINISTIC walks spawn order, RANDOM draws uniformly), applied to every
   slot point it travels through. KEEP POINT 0 AT ZERO — lone props (and single-prop tests)
   fly the exact slot line. `test_batch_props_stagger` guards it.

## Fixed this round (2026-07-13, session 2)

13. **"Cards not jumping or spinning for hoops or knives" — NOT an animation bug** — the
   owner had flipped `get_deck()` to `deck4` (the full 52, every card PLAIN). Both reaction
   hooks key on `card.skill` (`PropScoreTalents.reaction_for` -> JUMP a talent,
   `PropScoreProps.reaction_for` -> SPIN a talent): with zero skill cards on the board there
   is NOTHING that can ever jump or spin, by design. The anim chain itself is proven live by
   `test_all_kinds_live_in_game_view` (crafted talents; asserts raised + rotated poses on the
   real seam). FIX: `get_deck()` now returns the new `deck11` — every suit has BOTH plain
   cards (so no suit is skill-suppressed; hoops spawn) AND ExtraPoint talents (so hoops JUMP
   and knives SPIN something). This also closes the "hoops can't spawn with deck9/deck10"
   owner decision from #10 — via deck choice, not a suppression-rule change (rule intact).
14. **deck.gd rewritten with loop builders** — every deck is now a `_build_deckN()` loop
   with a comment stating its testing + balance niche; decks 1-10 keep their EXACT original
   compositions (incl. the hand-written quirk where deck7/deck8's 3rd back-half repeat closes
   on a fully plain card — preserved verbatim and commented). Suits are referenced by EXACT
   class (`PipSuitHoop`, ...) via the `ALL_SUITS` const, never by index. NEW decks:
   `deck11` prop+reaction showcase (all suits x ranks 1-4 plain + 2 ExtraPoint talents per
   suit — the default), `deck12` firework access (the ONLY grant path for kind-4 fireworks,
   which are outside `PipSuit.STANDARD`), `deck13` status stress (max-pip fires/balls +
   plain hoop/knife targets for Burning/Juggling stacking).
15. **`PipSuit.from_index` DELETED** — an index hid which suit a call site produced. Every
   caller now names the exact class (tests, `type_booster_basic`) or indexes
   `PipSuit.STANDARD[...]` where the index is genuinely data (deck_builder's option ids,
   persistence fuzz's rng draw). `random_standard()` stays.
16a. **Undo can now cancel a resolving act (2026-07-13, owner feature)** — `Game.undo()`
   mid-Submit/Next sets `act_cancelled`: `get_delay()` -> 0 (props/animations snap, read
   live), `run_props` breaks like `act_overrun`, `PropLayer` releases a manual-step hold,
   and the act restores the pre-act board (`_restore_pre_act_board` -> `PropLayer.abort_all`
   frees every prop visual — no later tick would prune them). Undo at the win/lose screen
   rewinds the final Submit; fame now banks at Continue (`exit_show`), not at resolve.
   See ARCHITECTURE_REVIEW §1.7 for the full contract.
16. **Tests no longer ride `Decks/deck.gd` AT ALL (final form 2026-07-13)** — `get_deck()`
   is the owner's freely-changing playtest deck; seeded tests that used it silently changed
   behavior on every flip (that's how #13 slipped in), and even pinning `deck.deck9` left
   them exposed to future deck.gd edits. Tests now build their own FROZEN compositions from
   `Tests/Support/test_decks.gd` (`TestDecks`): `seeded_deck()` (verbatim freeze of deck9
   as of 2026-07-13 — the composition the 424242/31337 observations replay against, hoop
   suppression quirk included), `standard_rules()` (rules1 freeze with fixed cosmetic pips),
   `minimal_deck()` (save bootstrap for crafted-board tests). Existing TestDecks functions
   are replay contracts — add new ones, never edit. `game.gd:218` still uses `get_deck()` —
   that one is the real game entry and SHOULD follow the active deck.

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
- Coords: `PlayArea.slot_center_global(v)` = **card anchor** (control top + half
  `card_size_play`), NOT rect center; empty slots in short columns extrapolate from the
  column header with the same formula. `PropLayer._slot_point` = `to_local` of that.
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
   height, headers resize with focus. Anything reading `control.size * 0.5` for a position
   will zig-zag. Always anchor `control top + card_size_play.y * 0.5`, and keep the
   empty-slot fallback in `slot_center_global` EXACTLY mirroring the occupied formula —
   anchored to the header TOP, never its bottom: an EMPTY column's header is its LAST control
   and gets inflated to full card height, which bent every route crossing empty columns.
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
- `test_batch_props_stagger` — batch mates take different PropFormation offsets.
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
| `Cards/Props/prop_formation.gd` (`PropFormation`, @tool Node2D) | Plotted card-space spread points -> per-prop `lane_offset`. Child of PropLayer in play_area.tscn. |
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
- `_spawn_index : int` — running count indexing `PropFormation.points` (DETERMINISTIC mode).
- `formation : PropFormation` — child node lookup in `_ready`.

**`begin_prop_tick(live, spawned, movers, relocated)`** — one data tick's animation orders:
1. `play_area.flush_rebuild()` (geometry must match current revision).
2. Ratchet every visual's `t_goal += 1/span_ticks` (slow props keep moving through
   no-new-slot ticks — landmine 7).
3. SPAWNED: `_make_visual` (kind -> subclass), assign `lane_offset =
   formation.offset_for(_spawn_index++)`, position at `_staged_point(prop, origin) +
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
   rebuilds). Skips MIN anchors and vanished slots (slot_center_global == ZERO).
2. `_drive_exiting`: same repin + same interpolation for void exits, INDEPENDENT of
   `_tick_active` (a run-final exit must complete); on arrival: fade 0.15s + free.
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

**Geometry** (play_area.gd): `slot_center_global(v)` = control top + half
`card_size_play` (NEVER rect center — landmine 3), empty-slot fallback extrapolates from
the column header's TOP with the SAME formula (never its bottom — empty columns' headers
are inflated to full card height by the last-control rule); `control_for_coord` walks
upper/lower_zone_right -> vbox children (child 0 = header, z == -1).

## R6. Timing + tuning knobs

| Knob | Where | Effect |
|---|---|---|
| `base_delay` | `Scripts/player_settings.gd` (`SettingsManager.settings`) | Global animation delay; everything scales off it. |
| `prop_tick_fraction` (0.45) | player_settings.gd | Seconds per prop tick = `game.get_delay() * this`. Bigger = slower props. Read LIVE every frame. |
| `get_delay()` compression | game.gd (COMPRESS_RATIO/STEP_MS/SOFT_MS/MIN_FACTOR) | Long acts shrink the delay; props retime mid-flight automatically (nothing locks in durations). |
| `ticks_per_slot` | per prop (suit constants) | Data speed: slot residency in ticks. |
| `countdown` at emission | run_props SPAWN (`+ i`) | Train stagger spacing in ticks. |
| Staging compression (1 + 0.15/pitch, cap 0.5) | prop_layer `_staged_point` | How far behind the entry a burst queues. |
| Exit distance (last leg length, min card width) | prop_layer `_void_point_of` | How far past the edge exits travel. |
| `arc_height` | each Visuals subclass `_init` | Ballistic hump height. |
| Formation points / mode | PropFormation node in play_area.tscn | Batch spread offsets (card-space; POINT 0 STAYS ZERO). |
| `max_live`, `batch_size`, `interval` | each suit's `spawn_props()` | Emission shape/concurrency. |
| `MAX_TICKS` (2048) + `note_processing` runaway cap | game.gd | Hard stops for infinite props. |
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
- **Spread pattern**: select PropFormation under PropLayer in play_area.tscn; edit `points`
  (card-space, drawn in-editor) / `mode`.
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
  `_update_reactions` in prop_layer.gd; one-shot statuses (JUGGLE/BURN) are status visuals,
  not poses.

## Known-open / unverified (as of this handoff)

- ~~Hoops can't spawn with deck9/deck10~~ RESOLVED via deck choice (#13): `get_deck()` is now
  `deck11`, which keeps skill-less cards of every suit. The suppression rule itself is
  unchanged (talented cards still skip their own suit effect) — deck9/deck10 still show zero
  hoops by construction, now documented on their builders in deck.gd.
- **Reaction design note (#13)**: ONLY talents ever jump/spin (both `reaction_for` hooks key
  on `card.skill`). A plain card a knife SCORES gets no pose. If the owner wants scored cards
  to visibly react, add e.g. JUMP-for-plain in `PropScoreProps.reaction_for` — one line, the
  hold/reset plumbing already handles it.
- **Meld cards stay raised until all props finish** — by design (`score_line` resets AFTER
  `_run_score_effects`); owner to confirm the feel or move the `reset_meld` call.

- Owner has NOT yet re-verified after this round: description panel scroll-lock, knife row
  behavior, hoop visibility (clipping/staging fix), ballistic poof, undo-across-submit.
- Hoop vs knife visual symmetry: they cross the same row in OPPOSITE directions
  (`entity_side_for_row`); if one side still misbehaves, suspect the staged/void points near
  the clipped board edges (landmine 2).
- ~~Firework grant path~~ RESOLVED: `deck12` is the deliberate grant path (#14) — though a
  general in-run acquisition mechanism (booster/shop) is still an owner decision.
  ~~Reactions at tick-start vs arrival~~ RESOLVED: reactions fire per ARRIVAL (#9).
- Still open owner decisions: per-pip tooltip granularity (focus inspector shows whole-card
  text only), real `status_pips.png` asset (StatusLayer + `draw_icon` are placeholders),
  moving the game.gd compression consts (COMPRESS_RATIO/STEP_MS/SOFT_MS/MIN_FACTOR) into
  PlayerSettings if they should be player-tunable.
- Balance of the now-live `on_score`/`on_after_score` broadcasts — never balance-tested.
