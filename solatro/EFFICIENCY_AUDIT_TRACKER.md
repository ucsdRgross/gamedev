# Efficiency Audit Tracker

Living tracker for the `efficiency_audit.txt` optimization plan. **Purpose: progress
checking + handoffs — future audits should consult this first and NOT re-audit files
marked done.** Update the status tables and findings as work lands.

- Plan: [efficiency_audit.txt](efficiency_audit.txt) (§1 complexity, §2 typing, §3 engine
  integration, §4 composition, §5 doc leanification, §6 health/tests, §7 C#/C++ notes,
  §8 agent directives)
- Companion: [ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md) — B/S/D/E/N item numbering
  referenced below. Doc updates land there; THIS doc records audit coverage.
- Rules of engagement: low-hanging fruit first; **new files / architectural changes need
  owner approval + a design doc first**; strict logic preservation; all tests stay green.
- Tests: `C:\richard\Godot_v4.7-stable_win64_console.exe --headless --path
  C:\richard\gamedev\solatro res://Tests/all_tests.tscn`. NOTE: the headless process can
  HANG after printing the final banner — read the result from the newest
  `%APPDATA%\Godot\app_userdata\Solatro\logs\godot*.log` (look for the
  `======== ALL N SUITES ========` line), then kill the process.

**Phase 2:** every remaining item is written up as a yes/no proposal in
[AUDIT_PROPOSALS_HANDOFF.md](AUDIT_PROPOSALS_HANDOFF.md) (P1-P15) — approved items get
implemented from there; this doc stays the coverage record.

## Owner rulings — do NOT "fix" (ARCHITECTURE_REVIEW §8)

- B10 live iteration in `run_all_mods` (no snapshot), S6 same-value `stage_changed`
  re-emits, N8 score-array desync, D7 commented-out code kept as reference.
- `addons/worldgen/` is **vendored** — canonical home is the separate worldgen project;
  never edit the copy here (§1.5). Worldgen findings are documented below for upstreaming.

## Audit status by area

Status: `done` = audited 2026-07-16 (fixes applied or findings logged — don't re-audit),
`todo` = not yet audited.

| Area | Status | Notes |
|---|---|---|
| Scripts/ (all 14 files) | done | fixes below; scoring.gd already carried SE1-SE3/SD/SC optimizations |
| Scripts/Map/ (3 files) | done | traveled-set fix; token/roles clean |
| Levels/ (game, game_view, main, map, menu) | done | find_data_vec3 dedup; rest clean |
| UI/ (all 12 files) | done | play_area/prop_layer already signal-driven (E3/D5); fixes below |
| Cards/ (all files incl. Props/Skills/Types/Statuses/Pips) | done | card_visual fixes; prop stack clean and deliberate |
| Decks/ | done | audited 2026-07-16 (late pass): N-E1's copy-paste is ALREADY loop-built (doc was stale); only N6 eager construction remains — proposal P4 in AUDIT_PROPOSALS_HANDOFF.md |
| Tests/ | deferred | leanification is LAST per plan §6; suite is green and fast enough |
| addons/worldgen/ | done | document-only (vendored) — findings below, upstream to the worldgen project |
| Other addons (big_number, flex_container, script-ide, SmoothScroll, yard) | out of scope | third-party |

## Fixes applied 2026-07-16 (this audit)

All logic-preserving; verified by the full 22-suite run (identical failure set before and
after the changes — see "Test runs" at the bottom).

| Fix | File(s) | Plan § / review item |
|---|---|---|
| Iterator recursion → flat `while` loop | Scripts/card_data_iterator.gd | §1 recursion ban / E9 |
| `print_board` upper/lower dup → `_zone_to_csv` | Scripts/game_data.gd | E7 (remaining half) |
| Same-value guards on 5 scalar setters | Scripts/game_data.gd | E10 |
| Typed dicts in `validate()` (`seen`, `expected_stage`) | Scripts/game_data.gd | §2 typing |
| Typed `_compare_implementers` impl array | Scripts/card_environment.gd | §2 typing |
| Typed `ModsList.stamps/types` | Scripts/mods_list.gd | §2 typing |
| Typed 4 local dicts (val_map ×2, cnt, used) | Scripts/scoring.gd | §2 typing |
| `find_data_vec3` → delegate to `Board.locate` (removes duplicate walk) | Levels/game.gd | §6 AI-bloat dedup |
| `settings` setter disconnect-old/connect-new | Scripts/settings_manager.gd | N9 |
| `CardVisual.data` setter owns signal wiring (disconnect on swap) | Cards/card_visual.gd | N9 |
| `refresh_visuals` traveled lookup: linear per edge → prebuilt set; dead `_is_traveled` removed | Scripts/Map/world_map_controller.gd | §1 single-pass |
| Typed `_reverse_adj`, `_booster_ranks` dict | Scripts/Map/world_map_controller.gd, map_node_roles.gd | §2 typing |
| `set_card_zone` duplicated map-block → `_bind_slot` | UI/play_area.gd | E6 (mapping half) |
| Focus-inspector `_process` gated by panel visibility (`set_process`) | UI/play_area.gd | §3 idle-cycle removal |
| Autosize font fit: linear scan (~90 measures) → binary search (~7) | UI/autosize_label.gd | §1 complexity |
| `assert(ResourceSaver.save(...))` → checked save (assert strips side effects in release!) | UI/deck_builder.gd | §6 silent failures |
| `_game_view()` called twice per frame → once | Cards/card_visual.gd | N-E2 (partial) |
| Bake tool `get_v_idx` O(V²) → Dictionary lookup (editor-only) | Cards/card_visual.gd | E11 |

## Findings log

### Already-done items discovered (docs were stale — ARCHITECTURE_REVIEW now updated)

- **E2 comparator dispatch cache** — implemented as `SE1` (`_compare_implementers` keyed
  on `[state id, revision]`). §4 now shows [x].
- **E3/D5** rebuild churn — signal-driven coalesced rebuilds confirmed in play_area.gd.
- **Threaded async save I/O (plan §3)**: `RunManager` background saver thread, coalesced
  payloads, atomic temp-file rename.
- **Asset preloading (plan §3)**: no runtime `load()` in hot paths; `ResourceLoader.load`
  only at run/settings load boundaries. Scene refs are `preload`/uid consts.
- **N5** default-active topmost rule — implemented in `CardModifier.is_active()`.

### Log-only observations (acceptable now; revisit only if profiling says so)

- `Scoring.HandProfile.remove_card` walks every rank/suit key per removal → extraction
  loops are O(cards × keys). Bounded by board size; a card→keys reverse map would fix it.
- `PropLayer._body_over_any_card` is O(split-props × cards) per frame; reaction pass is
  O(live × route) `find_vec3_data` (linear) calls per TICK. Both bounded small; the real
  fix is the §5.4 position index (E4).
- `WorldMapController._pulse_next_markers` re-derives + sorts `next_nodes_of` per frame
  while idle on the map (2-4 nodes — trivial; cache on move if it ever grows).
- `MapHoverPanel._process` polls its rect every frame while visible (documented: its
  mouse_entered never fires under covering children). Early-returns when hidden.
- `AutosizeLabel` binary-search fix above; `_update_font_size` still runs per resize (event-driven, fine).
- `run_all_mods` varargs + `Callable.callv` allocate per dispatch — inherent to the
  duck-typed hook design; do not micro-optimize without an E1 ruling.

### Suspicious / latent bugs flagged (NOT fixed — behavior changes need owner sign-off)

- `Cards/Skills/skill_extra_point.gd:11` — `if data == self.data` is always-true
  (member compared to itself); almost certainly meant `target == self.data`. As written,
  EVERY active ExtraPoint card triggers on every scored card. Covered by tests as-is.
- `Cards/Skills/skill_hungry_hippo.gd:32` — `game.state.draw_deck.append(card)` bypasses
  Board/revision-bump (MUTATION GUIDELINES). Path is currently dead (its dropped-on hook
  is fully commented out).
- `Scripts/game_data.gd validate()` I1 message prints `seen[card]` which is just `true` —
  message never shows the "other place". Cosmetic.
- `UI/deck_builder.gd` + `UI/deck_builder.tscn` are ORPHANED: preload
  `res://Cards/card.tscn` / `res://UI/card_control.tscn` which no longer exist, and type
  against the deleted `Card` class. Nothing references the scene. Candidate for deletion
  (owner call — D7-adjacent).

### Deferred — needs owner approval (behavior or architecture)

- **E1** (`run_all_mods` full `on_anything` pass after every event + per-mod
  `skill_active_check`): the fix changes `on_active`/`on_deactive` firing ORDER
  mid-dispatch — not logic-preserving, and adjacent to the B10 owner ruling. Needs a
  ruling. This is the single biggest remaining dispatch cost.
- **E4 / §5.4 position index** (`Board.locate` / `find_data_vec3` linear scans, also felt
  in the prop tick loop): the architected fix is the `Dictionary[CardData, Vector3i]`
  index — §5 step (2), still open.
- **E5/D6 undo snapshot cost** (`save_state` deep-duplicates the whole state per action).
- **E8 BoosterTemplate** gather-and-broadcast ×10 + un-awaited `run_all_mods`: the await
  half is a behavior change; the dedup-only half would un-type the pools. Do together,
  with a ruling on the async semantics.
- **N6 + N-E1** `Decks/deck.gd`: all nine test decks built per `Game` (hundreds of
  resources; DeckPicker builds them again). Factory-function rework ≈ new design.

### §7 C# / GDExtension migration candidates (log only — no conversion)

- `Scripts/scoring.gd` poker evaluation (cluster/straight/flush extraction over big
  hands; the wrap-walk `_scan_wrap` is O(ranks²) worst case) — prime C# candidate.
- `addons/worldgen/core/steps/rivers.gd` — the whole CPU hydrology pass (priority-flood
  depression fill, MFD flow accumulation, per-cell dilate/box-blur/stamp loops). Already
  mitigated by the downscaled grid + WorkerThreadPool; the per-cell GDScript loops are
  the project's #1 GDExtension candidate if generation time ever matters.
- `addons/worldgen/core/graph/graph_placement.gd` MapField (landmass labeling, signed
  distance transform, blue-noise sampling) + `biomes/biome_regions.gd` flood/voting.
- `addons/worldgen/painting/map_painter.gd` + `core/world_generator.gd` readback loops.

### Worldgen addon findings (2026-07-16, document-only — vendored; upstream these)

> **UPSTREAMED + RE-COPIED 2026-07-17.** All four micro-items below are implemented in
> the canonical worldgen project and the vendored copy here is current. Details (incl.
> where the ~10x readback claim was corrected by measurement) live in
> `../worldgen/UPSTREAM_EFFICIENCY_TODO.md`.

- **§8 cross-folder coupling: PASS** — zero references to base-project scripts/classes
  anywhere in the addon.
- **Already excellent**: GPU shader steps, WorkerThreadPool for CPU steps + parallel
  noise baking, COW PackedArray buffers/masks, texelFetch data textures (working around
  the vec4[] uniform bug), downscaled hydrology + distance-transform grids, thread-safe
  pure-data graph placement. No recursion found. No runtime `load()` in per-frame paths.
- Upstream-worthy micro-items:
  - `world_generator.gd` `read_height_from_image` / `read_plate_ids_from_image` /
    `height_texture`: per-pixel `get_pixel`/`set_pixel` over the full map — Image raw
    `data` buffer math is ~10x faster for readback at scale.
  - `rivers.gd` builds `river_nodes/lake_nodes` as `Array[Vector2i]` per pixel
    (Variant-boxed, can be huge) — `PackedInt32Array` of indices (or PackedVector2Array)
    is denser; consumers already have the byte masks.
  - Untyped local `{}` dicts throughout (graph_spec, world_randomizer, biome steps, …) —
    typed dictionaries where the K/V are stable.
  - `world_map_2d.gd` `_process` spinner ticks even with no overlay (early-return,
    trivial) — could `set_process` gate on overlay visibility.


## Phase 2 fixes applied 2026-07-16 (owner-approved proposals, AUDIT_PROPOSALS_HANDOFF.md)

Implemented in handoff order; the FULL 22-suite run was green (exit 0) after every step.
Per-item implementation notes live in the handoff doc's STATUS lines.

| Item | Fix | File(s) |
|---|---|---|
| P10 | I1 duplicate-card message names both containers | Scripts/game_data.gd |
| P12 | Static per-card backref link/unlink helpers, shared by RunManager | Scripts/game_data.gd, Scripts/run_manager.gd |
| P8 | HungryHippo eat/return routed through consistent state + revision bumps | Cards/Skills/skill_hungry_hippo.gd |
| P4 | 13 decks + rules1 lazily built (Deck.new() allocates nothing; ~146k -> ~18k leaked instances at test exit) | Decks/deck.gd |
| P6 | Undo history caps: MAX_UNDO_HISTORY=100 hard, undo_cap=25 mod-adjustable; trimmed count persisted so entity_side_for_row is unchanged | Levels/game.gd, Scripts/run_state.gd, Scripts/run_manager.gd |
| P15 | HandProfile reverse maps: remove_card touches only its own buckets | Scripts/scoring.gd |
| P1 | Hook-implementer gating in run_all_mods + owner rule (skip on_anything when nothing fired) + on_append gate in shuffle_deck; 1 deliberate test_dispatch assertion update | Scripts/card_environment.gd, Levels/game.gd, Tests/Engine/test_dispatch.gd |
| P5 | BoosterTemplate _gather helper (10 pairs -> 1) + awaited pool broadcasts; await ripple through ChoiceViewer/map/hover panel | Cards/Types/booster_template.gd, UI/choice_viewer.gd, Levels/map.gd, UI/map_hover_panel.gd |
| P7 | SkillExtraPoint self-check fixed (target == self.data) | Cards/Skills/skill_extra_point.gd |
| P3 | SS5.4 position index: lazy revision-keyed GameData.position_of; I4 in validate(); locate/find_data_vec3/is_data_topmost O(1); remove_column bump ordering fixed; fuzz suite now cross-checks every position vs an independent scan + duplicate_state hops | Scripts/game_data.gd, Scripts/board.gd, Levels/game.gd, Tests/Engine/test_fuzz.gd, Tests/Engine/test_board.gd |
| P11 | Commented-code purge per owner TODO rule (D7 overridden for these blocks) | Scripts/pip_comparator.gd, Cards/Skills/Rules/skill_scorer_cascade_lower.gd, Cards/card_modifier.gd, Cards/card_visual.gd, Cards/Types/type_stone.gd, Scripts/card_data_array.gd, UI/play_area.gd |
| P14 | Worldgen findings opened as upstream work; IMPLEMENTED upstream + re-copied here 2026-07-17 (see that file's inline notes — incl. the measured correction: per-byte GDScript writes are ~3x slower than set_pixel, so wins were taken as whole-image C++ passes, all verified bit-identical) | ../worldgen/UPSTREAM_EFFICIENCY_TODO.md, addons/worldgen/ (10 .gd files re-copied) |

Skipped per owner NO: P2 (skill_active_check batching), P9 (Deck Maker deletion), P13
(tests leanification).

## Test runs + environment gotchas (READ BEFORE TRUSTING A RUN ON THIS MACHINE)

> The headless/environment findings now live in **HEADLESS_TESTING.md** (project root)
> — canonical, kept current. The entries below are the historical log.

- **Stale global class cache trap (found + fixed 2026-07-16):**
  `.godot/global_script_class_cache.cfg` was stale (2026-07-11) and did NOT contain the
  suit-props-era classes (PropSpawner/PropData/CardModifierStatus/...). Under it, six
  newer test suites (INTERACTION, UI PROPS, VISUAL LAYERS, PROP ENGINE, STATUSES,
  SUIT PROPS) silently failed to load — "16 suites / 849 checks" runs were INCOMPLETE.
  Mid-session it degraded into hard parse-error cascades ("Could not find type
  CardModifierStatus"). Fix: `Godot --headless --path <project> --import` rebuilds the
  cache. If class-resolution cascades ever appear again, re-import BEFORE debugging code.
- 2026-07-16 "baseline" (pre-change, stale cache): 16 suites, 849 checks passed —
  incomplete, see above.
- 2026-07-16 post-change (cache fixed, ALL 22 suites): **1269 passed, 10 FAILED — all 10
  in INTERACTION, all position-based synthetic input** (mouse click/touch tap/button
  click; keyboard + joypad paths pass). **Verified PRE-EXISTING, not audit regressions**:
  reverting every runtime-relevant audit edit and re-running the suite in isolation
  reproduced the identical 10 failures. These tests had NEVER successfully run on this
  machine (suite added 2026-07-13, cache stale since 07-11). Likely headless/environment
  mouse-emulation behavior on this box or a genuine bug that shipped with the suite —
  needs an owner look on the machine where the suite was developed.
  - **ROOT-CAUSED + FIXED 2026-07-16 (later session):** a suite bug that only bites
    headless. `Input.parse_input_event` takes WINDOW coordinates; the suite fed it
    CANVAS coordinates from `get_global_rect()`. In a desktop window the two coincide,
    so the suite passed where it was developed. Headless, `DisplayServer.window_get_size()`
    is (0,0) (Godot clamps the root window to 100x100) while `canvas_items` stretch keeps
    the canvas at 1152 wide — the window->canvas inverse transform blew every synthetic
    click ~11x past the controls, so no positioned press ever landed (keyboard/joypad
    checks don't carry positions, hence they passed; right-click cancel passed because
    ungrab lives in `_unhandled_input`, no hit-test). Fix in `test_interaction.gd`: a
    `to_window()` helper (`get_viewport().get_final_transform() * pos`) applied in
    `mouse_move_to` / `mouse_click` / `touch_tap`. Identity in a normal window, so the
    suite still passes windowed. Verified: INTERACTION 34/34 headless in isolation and
    in the full 22-suite run.
- Final post-change full run (all audit fixes applied): **22 suites, 1251 passed,
  the SAME 10 pre-existing INTERACTION failures, 0 implementation failures** — the
  audit introduced zero regressions. (Check totals vary a little run-to-run from
  data-dependent suites; the failure set is what's compared.)
- 2026-07-16 Phase 2 implementation runs: 9 full 22-suite runs, one after each landed
  step (batch P10/P12/P8, P4, P6, P15, P1, P5, P7, P3, P3-testfix, P11). All exit 0.
  Check totals ranged 1219-1327 (data-dependent suites vary run-to-run); the only
  mid-stream failure was the B4 locate check in BOARD, caused by that test's raw column
  append not bumping revision - fixed in the test per the MUTATION GUIDELINES, green on
  re-run. INTERACTION stayed 34/34 throughout.
- 2026-07-17 P14 re-copy run (upstream worldgen batch copied into addons/worldgen/,
  after `--import`): **ALL 22 SUITES, 1252 CHECKS PASSED, exit 0.** ~19.5k leaked
  instances at exit (consistent with the known ~18k baseline, canary work still open).
- 2026-07-17 LEAK CANARY landed (owner-approved): new 23rd suite
  Tests/Engine/test_leak_canary.gd, runs last+alone in the ordering chain. Full run
  after wiring: **ALL 23 SUITES, 1221 CHECKS PASSED, exit 0** (totals vary run-to-run).
- 2026-07-17 P14 A/B generation timing (worldgen addon_node_test, seed 12356, 2 runs
  each): enabled-steps avg **5663 ms (baseline) -> 5287 ms (new), ~6.5% faster**;
  readback steps consistently down (PeaksAndValleys 50-67 -> 34 ms, Erosion ~109 -> ~86 ms),
  Rivers unchanged (hydrology-bound — the GDExtension candidate). Painting/merge savings
  (~30 ms/repaint at 512²) and the packed river/lake memory win are not in step timings.
- **Headless-hang lead (2026-07-17, from validating P14 upstream):** Godot 4.7
  `--headless` never fires `RenderingServer.frame_post_draw`; any await on it stalls
  forever (this is what freezes the worldgen pipeline test scenes headless — they must
  run windowed). Candidate root cause for the "hangs after the final banner" quirk.
- **2026-07-17 (later session) headless-hang + leak-attribution work:**
  - Headless hang: DOES NOT REPRODUCE — 6 consecutive full headless runs self-terminated
    cleanly (~20 s, exit 0). Nothing in Scripts/Tests awaits frame_post_draw (only the
    vendored worldgen flush(), untouched by tests); RunManager's saver thread joins in
    _exit_tree. Documented in HEADLESS_TESTING.md §1 with a recurrence workaround.
  - Residual exit leak ATTRIBUTED per suite via new Tests/Support/leak_probe.tscn (runs
    one suite scene, quits; exit leak count = that suite's leak). All test-owned; sums
    matched the full-run ~19.3k. Teardown fixes (test_base.gd unlink_cards helper +
    unlink at every fixture drop site) landed in persistence_fuzz, board fuzz, board,
    game_headless, e2e, ui_props, visual_layers, interaction; plus ONE production fix:
    Game.undo() unlinks the outgoing live state (quiescent; _restore_pre_act_board
    deliberately left linked — mods still run against the doomed state there).
  - Full-run exit leak: **19,335 -> 1,847 instances (-90%)**. Validation runs mid-work
    and final: ALL 23 SUITES green (1246 / 1228 checks, exit 0).
  - Worldgen C++ port note: BLOCKED — no C++ toolchain on this box (no MSVC/MinGW/scons);
    owner call needed to install Build Tools.
- **2026-07-17 (same later session) leak-tail sweep:** teardown unlinks added to
  test_mods (done() helper), test_run_manager, test_prop_engine (done()), test_iterator
  (_made tracking), test_game_data, test_suit_props (done()), test_statuses.
  Per-suite: MODS 382->98, RUN MANAGER 278->0, PROP ENGINE 238->11, ITERATOR 161->0,
  GAME DATA 109->0, SUIT PROPS 104->0, STATUSES 54->0. Full-run exit leak now **699**
  (19,335 originally, -96%). Accepted floor: UI VIEWERS/DISPATCH/COMPARATOR (~100,
  scattered inline card builds), LEAK CANARY 57 (deliberate), small mid-test residues.
  Validation: ALL 23 SUITES, 1240 CHECKS PASSED, exit 0.
- **2026-07-17 C++ port handoff written:** worldgen/GDEXTENSION_PORT_HANDOFF.md
  (implementation) + worldgen/CPP_SETUP_FOR_OWNER.md (owner's toolchain install steps).
  Port remains blocked until the owner installs VS Build Tools + scons.
- **2026-07-17 worldgen C++ port, Phase 1 (Rivers) LANDED:** toolchain installed
  (MSVC 19.51 + SCons 4.10); new `worldgen/worldgen_native/` GDExtension (godot-cpp
  master pinned to the 4.7 API dump — upstream has no 4.7 branch). Native
  `fill_depressions` / `flow_accumulate_mfd` / `box_blur` / `dilate_lake` with the
  GDScript paths kept as automatic fallback (`GenerationStep._native` null check;
  verified with dlls renamed away). Bit-identical A/B gate:
  `worldgen/tests/native_ab_test.tscn` (seeds 12356/777/424242, zero byte diffs).
  Timing seed 12356: enabled steps **5287 -> 1829 ms**, Rivers_Only ~3.4 s -> 256 ms.
  Vendored here: `addons/worldgen/bin/` (gdextension + win64 debug/release dlls) plus
  updated `core/world_gen_step.gd`, `core/steps/rivers.gd`. Validation: worldgen scenes
  green (generate_up_to, graph_placement, biome_regions, biome_assign, graph_spec full
  1500-fuzz 1860/1860, bake/node), Solatro **ALL 23 SUITES: 1254 CHECKS PASSED, exit 0**.
- **2026-07-17 worldgen C++ port, Phase 2 (Graph/MapField) LANDED:** native
  `label_landmasses` / `map_distance_transform` / `poisson_land_samples` +
  `jittered_land_samples` / `measure_land` in `worldgen_native` (GDScript fallbacks
  kept, `GenerationStep._native` null check). Poisson RNG determinism: the C++ side
  instantiates the ENGINE's own RandomNumberGenerator (godot-cpp), so the random
  sequence matches GDScript by construction. `_build_masks` left in GDScript
  (profiled 15 ms); the Graph solver untouched (out of scope per Phase 2 handoff).
  A/B gate extended to 30 checks x 3 seeds (labels/sizes/seeds/main_label,
  measure_land, dt, poisson, poisson-confine_main, jittered) — all bit-identical.
  Timing seed 12356 (addon_node_test): Graph **933 -> 383 ms**, enabled steps
  **1829 -> 1212 ms**. Per-fn native-vs-gd: labels 1/182, dt 2/150, poisson 6/139,
  measure 0/107 ms. Vendored here: `addons/worldgen/bin/` dlls +
  `core/graph/graph_placement.gd`. Validation: worldgen scenes green
  (generate_up_to, graph_placement, biome_regions, biome_assign, graph_spec full
  1500-fuzz 1860/1860, bake/node), no-dll fallback PASS, Solatro
  **ALL 23 SUITES: 1240 CHECKS PASSED, exit 0**. Next: Phase 3 (Biomes ~300 ms, 25%).
- **2026-07-18 worldgen C++ port, Phase 3 (Biomes) + Rivers residual LANDED:** native
  `biome_build_cells` (the whole warped Dial flood + orphan labeling + per-cell
  stats/adjacency of BiomeRegions.build_cells; adj Dictionaries built with the exact
  GDScript insertion order so downstream key iteration matches; paint_cells stays
  GDScript at a measured 3 ms). Rivers: execute()'s five inline loops extracted into
  StepRivers methods with native twins (`river_downsample`, `river_seed_field` —
  humidity via the engine's own Image.get_pixel from C++ —, `river_depth_stamp`,
  `river_lake_surfaces`, `river_apply_water`), GDScript fallbacks kept. A/B gate now
  48 checks x 3 seeds, all bit-identical. Timing seed 12356 (addon_node_test):
  Biomes **300 -> 33 ms**, Rivers_Only **263 -> 63 ms**, enabled-steps total
  **879 ms** (was 5287 pre-port, 1212 after Phase 2). Vendored here: bin/ dlls +
  `core/steps/rivers.gd` + `core/biomes/biome_regions.gd`. Validation: worldgen
  scenes green (generate_up_to, graph_placement, biome_regions, biome_assign,
  graph_spec full 1500-fuzz 1860/1860, bake/node), no-dll fallback PASS, Solatro
  **ALL 23 SUITES: 1225 CHECKS PASSED, exit 0**.
- **2026-07-18 PRODUCTION leak canary LANDED (owner-endorsed 2026-07-17,
  PRODUCTION_LEAK_CANARY_HANDOFF.md):** test_leak_canary.gd grew SECTION 2, the
  "PRODUCTION SESSION CANARY" (same suite, still last+alone - suite count stays 24, no
  exclude-list changes). Each cycle simulates a full play session through the real
  production objects: DeckPicker open (builds all starter lists) + DeckViewer inspect +
  Pick; RunManager.new_run (frozen TestDecks); synthetic-map traversal (MAP TRAVERSAL
  rig, no worldgen) + MapHoverPanel booster preview + take-all ChoiceViewer confirm
  (deck grows); a real show WITH a GameView (2 Nexts, grab/place via try_grab/try_place,
  discard_data, a Submit with real scoring + props, UNDO across the Submit - proves the
  2026-07-17 Game.undo() unlink - then redo); quit-mid-show -> resume (save/load relink,
  app-exit stand-in unlinks like E2E); win exit_show (return_to_map) AND a loss show +
  exit_show; clear_save. Warm-up cycle first, _drain (0.25s + 2 settle frames) before
  every count, print_orphan_nodes on failure; asserts OBJECT_COUNT returns to the
  post-warm-up baseline over 3 cycles.
  Writing it surfaced FIVE real production leaks, all FIXED (PRODUCTION FILES TOUCHED):
  * Levels/game.gd return_to_map: the run doc's replaced deck copies + the dying
    rules_deck / zone-header cards now unlink (every completed show leaked them);
  * Levels/game.gd exit_show loss branch: unlinks the whole doomed board after
    run_lost.emit();
  * Scripts/run_manager.gd clear_save: unlinks the dropped run doc's card/rule decks
    (idempotent - test paths that already unlinked are unaffected);
  * UI/deck_picker.gd _exit_tree: unlinks every lazily-built starter list (+ rules when
    a pick built them) - each picker open+close leaked ~250 cards' cycles;
  * UI/map_hover_panel.gd: retains + unlinks its booster preview cards on clear/exit -
    every booster-node hover leaked the preview graph.
  _restore_pre_act_board stays linked BY DESIGN (untouched). Numbers: full-run exit leak
  699 -> **547**; isolated canary via leak_probe still exactly **57** (its own deliberate
  fixture - the session section attributes 0). Validation: two full headless runs,
  **ALL 24 SUITES: 1291 CHECKS PASSED, exit 0** (second run exit 0, errors log empty).
- **2026-07-18 worldgen NoiseBake (setup) LANDED:** native `bake_multifractal` for
  `noise_baker.gd _multi` (the hand-rolled multifractal loop behind peaks_ridge /
  peaks_billow; the other 6 maps already used FastNoiseLite.get_image natively).
  GDScript configures the FastNoiseLite and passes it in; C++ calls the engine's own
  get_noise_2d per octave — identical values by construction, verified bit-identical
  on output image bytes (both variants x 3 seeds in the A/B gate). Per-map ~2.4x
  (floor = the ~5M engine noise calls), but the threaded bake totals to the slowest
  single map: setup NoiseBake **~2200 -> ~380 ms** (dev box). Scene gates + no-dll
  fallback green; vendored here (`bin/` dlls + `core/noise_baker.gd`); full suite
  **ALL 24 SUITES: 1243 CHECKS PASSED, exit 0** (24th = the new COMBO suite, added
  outside this work). Worldgen native totals now: setup ~380 ms + enabled steps
  ~645-880 ms (was ~5287 + ~1150 pre-port); remaining time is the Graph solver
  (owner-gated) and map_painter _paint (Phase 4, owner-gated).
- **2026-07-18 (later session) WEAKREF BACKREFS + PLAYTEST LEAK SENTINEL LANDED**
  (LEAK_PREVENTION_HANDOFF.md, both workstreams; the handoff is now historical):
  `CardModifier.data` is a WeakRef-backed property (same name, ~every call site
  untouched) — the CardData<->modifier RefCounted cycle can no longer exist, so the
  ENTIRE per-drop-site unlink discipline was deleted (production and tests).
  BENCHMARK GATE (required before landing): micro-bench 10M `mod.data` reads
  2.03s -> 6.47s (~0.45 us/read of property+WeakRef overhead), but suite wall-time —
  the actual gate — is unchanged-to-better: full all_tests 75.1s baseline -> 72.3-72.9s
  after; SCORING/ACT SCORE/BOARD FUZZ/E2E/PROP ENGINE per-suite times all within noise
  (several faster). PASSED.
  PRODUCTION FILES TOUCHED:
  * Cards/card_modifier.gd: `data` -> `_data_ref : WeakRef` + property (covers
    skills/types/stamps + PipSuit + CardModifierStatus by inheritance);
  * Cards/card_data.gd: debug-only `sentinel_registry` (weakref per card in `_init`);
  * Scripts/game_data.gd: duplicate_state() now relinks its copy (duplicate_deep does
    NOT remap a WeakRef — every deep-copy site must relink); unlink/relink helpers KEPT
    (relink after copies/loads; unlink so saves carry no backref), comments rewritten;
  * Levels/game.gd: add_deck relinks both copied decks; deleted the undo() /
    exit_show-loss / return_to_map unlink blocks (_restore_pre_act_board comment kept);
  * Scripts/run_manager.gd: new_run relinks the copied decks; clear_save unlink deleted;
    _to_saveable_cards still nulls backrefs (saves stay backref-free);
  * UI/deck_builder.gd: relinks its duplicated preview card;
  * UI/deck_picker.gd: _exit_tree unlink deleted; UI/map_hover_panel.gd: unlink helper
    deleted (plain list clear remains);
  * Levels/main.gd + project.godot + Scripts/leak_sentinel.gd + player_settings.gd:
    workstream B (below).
  TEST SIDE: TestSuite.unlink_cards deleted + every per-suite teardown unlink swept
  (15 files). test_leak_canary rewritten: clean cycles now free WITHOUT unlinking (the
  tripwire proving the leak class is dead); the deliberate-leak proof abandons stray
  Nodes instead of cards; new LEAK SENTINEL section drives LeakSentinel.tick() directly
  (its one push_error in the log is deliberate). Canary counts prune the sentinel
  registry via LeakSentinel.prune() (benign WeakRef growth).
  WORKSTREAM B — Scripts/leak_sentinel.gd autoload (debug builds only): at quiescent
  moments (map entry / show exit via Main hooks + a slow timer, never while
  Game.processing) compares CardData alive (registry) vs reachable from legitimate
  roots (run doc + RunManager save caches/payload + live Game state/history/fallback
  deck + open DeckViewer/DeckPicker/MapHoverPanel/ChoiceViewer); sustained excess
  (slack 8, 3 strikes) push_errors counts + a stage/modifier histogram naming the
  source. Knobs in player_settings.gd (leak_sentinel_enabled/slack/strikes/interval);
  quiet under the test runner (TestLog.begin sets LeakSentinel.test_mode).
  NUMBERS: full-run exit leak 547 -> **4** (the canary's own deliberate stray-Node
  fixture); isolated leak_probe runs now report NO leak warning at all for STATUSES,
  BOARD, E2E RUN, UI PROPS, INTERACTION (LEAK CANARY's 57 fixture figure is gone with
  the rewrite). Validation: two full headless runs, **ALL 24 SUITES green, exit 0**
  (1312 / 1285 checks — totals vary, fuzz suites).
