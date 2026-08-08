# TODO — open backlog (owner-endorsed unless marked otherwise)

Add new items here; **delete an item when it lands**, recording the regression-critical residue in
ARCHITECTURE_REVIEW.md rather than keeping a log here. Current-state facts live in
ARCHITECTURE_REVIEW.md; done-work history lives in git.

## Waiting on the owner

- ⬜ **Playtest the universal palette** (below) — the fire and ball colours changed.
- ⬜ **Playtest the shader FX** (FX_SHADER_PLAN §10, 17 steps).
- ⬜ **Delete FX_SHADER_PLAN.md + FX_HANDOFF.md** once that playtest passes. Their residue is
  already folded into ARCHITECTURE_REVIEW §4g/§4h.
- ⬜ **Spotlight: answer GAP-010 / GAP-011** (overrun banking; emptied-section hooks —
  `design/spotlight/gaps/`), **judge G2.2** (rank-glyph readability), **pick
  `spotlight_separation_mode`**. Status ledger: HANDOFF_spotlight.md.

Everything below is unscheduled backlog.

## Visual effects

**Anything fire, juggling, prop art or FX shaders starts at [VFX.md](VFX.md) §6/§7**, which carries
that whole backlog and its known bugs. Keeping the list here as well is exactly the two-places
drift this repo's doc hygiene forbids.

The current fire emitter is the **NOISE FIRE** (owner design): no tendrils, no comb, no ogee, no
onion shells. Fire is a cover field sampled from the art's own mask and carved by scrolling noise,
and every parameter ramps continuously with the stack count. Contract: ARCHITECTURE_REVIEW §4g;
the full record, including what only the owner can decide, is FX_HANDOFF §0.

- ⬜ **The two remaining FX tasks are FX_HANDOFF §0c/§0d** — the owner's words: *"our last tasks
  will be making fire vfx show behind the art and saving juggling performance"*. ⚠ Read §0c first:
  `inner_alpha` and `z_index` are NOT ruled out — the first attempt failed on a QUANTIZATION
  detail, and the one-line experiment to try before any layering change is named there. For the
  second, re-run the two levers whose blocker an unrelated fix removed. §0e explains `cover_taps`.
- **The three fire `.tres` were MIGRATED, not TUNED.** Only `noise_scale` was re-derived, because
  the retired build's value was ~6x too fine for a model where the noise IS the shape. **The art
  pass is the owner's and it is the biggest thing waiting.**
- **Fire still licks down a card's top corners.** The chamfer is in the RADII mask, not the flame
  model, so any correct model stands fire on it. FX_HANDOFF §8.

## Architecture / engine

- D6 command-log undo — the real fix for per-action deep-copy cost (E5); eliminates reference
  remapping entirely. Big.
- Board §5 step (5): delete the `move_data_to_coord` / `move_data_ontop_data` Vector3i adapters
  when convenient.
- D1 real mod-hook contract (single HOOKS list / signature checking) · D2 route ALL mod state
  mutation through Game/Board (some mods still write arrays directly) · D4 kill the
  `CardEnvironment.CURRENT` static reach-through (pass the environment/context instead).
- D8–D11 cosmetics: comparator speculative abstractions, editor-tool code out of `card_visual.gd`,
  unify the zone pair into one structure, Scoring section-banner rewrite.
- S3 same-column move edge cases (unit-test the remaining matrix), S4 `PlayArea.separation`
  int/float, S7 verify every ModsList consumer duplicates.

## Scoring / balance (playtest phase — the sim cannot answer these)

- Playtest per the SCORING_MATH_PLAN §10 protocol (git history): paired seeds, record sheets,
  acceptance bands. Open knobs: `difficulty` default, `combo_step` 0.1 vs 0.2,
  arrangement-capacity reality, mod-activation U generosity, Burning cascades as a combo source,
  δ fallback trigger, `score_additive` A/B (needs a goal_g0/alpha retune).
- Balance of the live `on_score` / `on_after_score` broadcasts — never balance-tested.
- Sim/doc fit drift: `--final --q 0.35` prints g0≈140/α≈2.03 while shipped constants are G0=130 /
  ALPHA=4.2. The owner is not worried (tunables cover it); arbitrate before recalibrating.
- Rarity tiers (luck currently only gates non-null stamp/skill/type rolls).

## Scoring engine test gaps

- ✅ G3/G4/G5 **CLOSED** 2026-08-07 — `test_scoring.gd`: `run_score_model_table` (ScoreModel branch
  table, direct), `run_loc_name_table` (`get_loc_name` branch/distinctness + the size-suffix rule),
  `run_compare_results_chain` (every `_compare_results` tier in isolation, plus irreflexivity).
  All three were mutation-tested — each section was made to fail on purpose and did.
- ✅ G1 **CLOSED** 2026-08-07 — `test_comparator.gd::run_end_to_end_scoring_under_mod`, and it
  **found a real seam, which is now PINNED and needs an owner ruling** (below).
- SD5 test-file section renumbering · SD6 exact-name leaderboard asserts · SE4 single-walk
  `_scan_wrap` (micro).

### ⬜ OWNER DECISION — comparator mods do not reach hand building

Writing G1 turned up two representations of *"are these the same?"*, with only one of them
overridable, and nothing comparing them:

- **Pairwise** — `compare_ranks` / `is_rank_same` / `is_suit_same`. The `on_compare_ranks` /
  `on_compare_suits` hooks DO override these, and `Scoring.is_flush` plus the placement legality
  query both use them, so the hooks are live in the game today.
- **Profile** — `get_rank_profile` / `get_suit_profile` in `Scoring._get_hand_profiles_async`, which
  derive per-card bucket keys and never consult a hook. **All grouping — sets, straights, houses —
  is built from these buckets.**

Measured: a mod returning `0.0` from `on_compare_ranks` ("every rank is the same") leaves
`PokerHands.score` returning **High Card** on five distinct ranks. With a suit mod, `is_flush(hand)`
returns **true** while the hand scored from those same cards carries **no FLUSH type** — the two
disagree under one mod.

⚠ **Entirely latent: no shipped card implements either hook** (`grep "func on_compare_ranks" Cards/`
is empty). The first rules card that rewrites rank equality will land on this, and it will present
as the card doing nothing.

The question is whether a comparator mod SHOULD restructure hands. `test_comparator.gd` SECTION 5
pins today's answer (mods do not regroup) so the split is visible and any change to it is loud —
those checks are written to FAIL if grouping is ever wired through the hooks, which is the point.

## Props / UI (owner has NOT re-verified)

- Description-panel scroll-lock, knife row behavior, hoop visibility, ballistic poof,
  undo-across-submit feel, held-loop spin, formation system + editor end-to-end (no formation
  `.tres` authored yet).
- Firework in-run acquisition beyond deck12 (owner decision). Per-pip tooltip granularity.
- Win/lose screen font (226px) clips long "Fame +N" text. `game.tscn` grabs no initial focus, so
  keyboard/controller players must click first.

## Universal palette (owner playtest pending)

Contract: ARCHITECTURE_REVIEW §4i. Open follow-ups, all deferred by the owner rather than missed:

- **Map screen and in-game UI chrome are still hardcoded**, pending the owner's custom art
  (`world_map_controller.gd`, `map_player_token.gd`, `game_view.tscn`, `choice_viewer`,
  `deck_picker`, `deck_viewer`, `deck_builder`, `text_popup`). The PALETTE suite lists each as
  `[WARN][PLACEHOLDER]` every run — that list IS this task. When the art lands: add a role per surface, assign it in code at `_ready()`, never
  re-bake a literal into a `.tscn`.
- **`FireworkVisual` has no art** — its placeholder magenta polygon is the last non-deferred
  literal. The `suit_firework` role already exists for whenever that art is drawn.
- **The fire ramp's ENDS are an art call the owner has not made.** `ramp_fire` runs
  `[0, 20, 1, 2, 16, 30, 6, 3, 31, 19]`; entry 0 makes a 1-stack flame nearly black and entry 19
  puts a neutral grey at the white-hot end. Both are honest nearest-palette choices and both are
  one-line edits to `Assets/Palette/ramp_fire.tres`.
- **`suit_pips.png` has a few off-palette pixels** (e.g. `#ec0037`, 27 from entry 2). Authored art,
  not a plumbing bug; `tools/palette_conformance.py` finds them.

## Patience & rerolls (owner playtest pending)

Full behavior and the settings list: ARCHITECTURE_REVIEW §4e.

- Tune `patience_max` (ships 3) and the per-stage `patience_influence_*` flags (ships PLAY only);
  decide whether the legality query `on_can_place_stack` should count at all — if not, add it to
  `patience_disabled_hooks` and re-tune what "interesting move" means.
- ⚠ `patience_max` ships **3**, but the original spec asked for **1** — confirm which is intended
  before drawing playtest conclusions (3 = three idle moves per round).
- Rule cards that raise `patience_max` / grant patience: the grant path exists
  (`patience_max_increased`), no content uses it yet.
- Booster rerolls (§4f): pool ships at 5 (`booster_reroll_pool`); reroll-count modifiers (the
  `luck()`-style content hook) not written yet.
- Watch existing suites for auto-Next fallout: any test that makes 3+ boring moves in one round now
  advances the round mid-test.
- Comparator hooks reach patience: `on_compare_ranks/suits` fire through
  `return_first_compare_mod_result` during the placement legality query, so ANY board card with a
  comparator modifier holds the counter (once per round under uniques). Decide whether that is the
  intended "interesting move" bar or belongs in `patience_disabled_hooks`.
- `Game._on_patience_max_increased` edits `state.patience` with no commit — a mid-round grant is
  lost on quit and reverted by undo. Fine for a settings knob; revisit when a rule CARD grants
  patience (that grant should ride a committed action).
- `Game._ready` connects to `SettingsManager.settings.patience_max_increased` without the N9
  reconnect idiom, so the connection binds the settings resource that exists at show start. Only
  matters if `SettingsManager.settings` is ever reassigned at runtime (its setter supports it).
- Two gaps documented in ARCHITECTURE_REVIEW: the auto-Next pending-action replay caveat (§1.5) and
  the seen-set-only commit gap in `_perform_next` (§4e).
- ✅ Test hygiene **DONE 2026-08-07**: settings isolation lives on `TestSuite`
  (`backup_real_settings` / `restore_real_settings` + `snapshot_settings(prefix)`) and **every suite
  now uses it** — UI PROPS, VISUAL LAYERS and LEAK CANARY had their copy-pasted
  `REAL_SETTINGS_PATH` / `REAL_SETTINGS_BAK` pairs removed, which freed the base const back to the
  obvious name (`TestSuite.REAL_SETTINGS_PATH`; the awkward `SETTINGS_FILE` is gone).
  ⚠ **Do not reintroduce a local pair:** each copy hardcoded ONE backup path (`.testbak`,
  `.testbak2`, `.testbak3`), so two suites running concurrently could park and restore across each
  other. `_settings_bak_path()` derives the name from `suite_name()`, which is why it is a function.

## Card size + outline — landed, one thing open

Card is **40x54**; every element wears `Shaders/outline.gdshader`'s rim. Rules and landmines:
**ARCHITECTURE_REVIEW §4j**. Design record: `design/card_size_outline/`. Tuning:
`Shaders/Styles/outline_default.tres`, edited live on `tools/outline_atlas.tscn`.

- ⚠ **OPEN — `design/card_size_outline/gaps/GAP-001.md`: a 7-column board is now WIDER THAN THE
  WINDOW.** A fire prop spawns at x=1187 against a 1152-px viewport; the card gained 5 px per
  column and the board was already exactly on the edge. `test_ui_props`'s *"every spawned fire
  entered the visible viewport"* is **left FAILING on purpose** — it reports a true fact, and the
  three ways out (narrow the test board, drop `card_scale`, tighten `PlayArea.separation`) are a
  game-feel call. ⚠ The real finding is the zero margin: **nothing asserts a full-width board fits
  the window.**
- ⚠ **ART, owner's call — the rim MERGES the dense `suit_art` frames.** The highest-rank frames
  pack nine+ pips into 32x32 and invert into a dark lattice. The fix is art-side (space by 3) or
  scope-side (exempt the 32x32 art). Nothing in code is wrong.
- **Q6a / the alert's LOOK is unjudged.** GLARE and THROB are tunable live on the atlas; whether a
  card-space glare reads on an 8x8 pip (lit ~25 % of the sweep) is the owner's eye. The escape
  hatch is a per-host thickness scale.
- **FX numbers are stale by ~12 % of fill.** FX_HANDOFF.md carries a banner; re-run `fx_cost.gd`
  before spending that budget.

## Design work not started (DESIGN_DOC pointers)

- Entrance drop-down between acts (DESIGN_DOC §2) — decide and implement.
- Tips / hype-wagering / fog of war / tour planning (§15); circus renames (§9); shop & economy
  (§16); meta progression (§19); leaders/acts (§11); deterministic per-subsystem RNG streams
  (§6/§23 — required before any seed-sharing feature).

## Testing / infrastructure

- **Snapshot nondeterminism — RE-MEASURED 2026-08-07, and it is not the "rotated host" story**
  (FX_HANDOFF §12; full evidence in the `NOISY` comment in `Tools/snapshot_diff.py`). Three
  consecutive runs of an unchanged build, every pair diffed: **18 of 21 panels byte-identical in all
  three pairs.** The exceptions: `02_fire_rotation` (8248 px, and A^C was **0** — bistable),
  `09_embers` (142–1015 px, randomised by design), and **`10_light_layer` (up to 78834 px = 8.1% of
  the frame), which was never on the noisy list at all.** `05f_ball_rotation` was stable in all three.
  **`10_light_layer` is now FIXED (below); `02_fire_rotation` remains the open one.**
  - ⚠ **This unblocks the diagnosis rather than closing it.** Newly RULED OUT: `_push_live`'s
    `rotation = -parent.global_rotation` — every CPU-side value the harness prints (rotations,
    every shader uniform, every probe reading) was IDENTICAL across all three runs, so the
    divergence is not in game logic, even though `fx_snapshot.gd` names that line as "the only place
    that can happen". Also ruled out earlier: screen-space `fx_bayer`, pinning `_seed`.
  - ✅ **`10_light_layer` FIXED — 78834 px → 0, byte-identical over three runs, and it is back in
    the diff instead of on the noisy list.** Cause: UNPARKED CARD CLOCKS. That shot's shader side is
    fully pinned (fixed centres and radii, `u_time = SHOT_TIME`), so the light could never vary —
    what varied were the 18 real `ControlCard`s staged under it, which is also why it was the only
    panel affected (it is the one shot using real cards rather than ghost stand-ins). TWO clocks
    were live: `CardVisual.delta_floating_anim` drifts/bobs on **`Time.get_ticks_msec()`** (absolute
    WALL CLOCK, and `floating` defaults to true), and `card_visual.tscn`'s **AnimationPlayer is on
    autoplay**, so `set_process(false)` never reached the skinned bone pose — that was the whole
    residual after the first fix (78834 → ~6-31 → 0). Fix is `fx_snapshot.gd::_park_cards`.
    Re-read by eye afterwards: crossing beams, three radii, dim not black, glyphs still legible.
    - ⚠ **This makes G3.3's `10_light_layer` claim testable again** — re-run it and the panel either
      matches its baseline or it does not.
  - ⚠ **`02_fire_rotation` is still unexplained** and is a different shape: `_shot` DOES park it, and
    its A^C diff was exactly **0** while A^B and B^C were both exactly 8248 — two discrete outcomes,
    not drift. Run B was the outlier for this and `10_light_layer` alike, so a per-run condition is
    still in play for it.
  - ⚠ **It also invalidates a closed gate:** HANDOFF_spotlight's G3.3 attributed `10_light_layer`'s
    difference to the 38x52 art refactor, "verified by eye". That panel moves by 78k px between two
    runs of one unchanged build, so **G3.3 for `10_light_layer` is UNPROVEN, not closed.**
- **LEAK CANARY's object-count check is intermittent** (growth 0–2 across runs). Judge it across
  runs. **2026-08-07 tally, and the shape of it is worth more than the count: 3 failures (growth 2
  each time) in the session's first ~8 runs, then 0 in the following ~30 consecutive runs**
  (including one deliberate 14-run hunt that never tripped).
  - ⚠ **A CORRELATION, EXPLICITLY NOT A CLAIM OF CAUSE:** every failure predates that session's
    settings-isolation migration, which moved this suite off its own hardcoded `settings.tres.testbak3`
    onto `TestSuite`'s per-suite, self-healing backup. A stale backup left by an aborted run used to
    be able to make the "real" settings file for the next run be a previous run's throwaway, and the
    session cycles read settings. That is a plausible mechanism and nothing more — the flake was
    always intermittent (the handoff records 6 consecutive passes then a failure), so ~30 clean runs
    is suggestive, not proof. **Do not mark this fixed on that basis; let the census report the next
    real failure.**
  - ⚠ **`print_orphan_nodes()` IS A DEAD END — do not spend another session on it.** It was the
    standing "next thing to try". Run on a genuinely FAILING run it printed exactly four strays, and
    all four are the ones `test_leak_canary` abandons ON PURPOSE before the baseline to prove the
    canary works. **The real growth is not a Node**, so an orphan-node dump cannot ever contain it.
  - ✅ Replaced with `_object_census()` / `_report_growth()`, which split the growth across
    NODE / RESOURCE / other (plain RefCounted) using the engine's own performance monitors and say
    which class it landed in. Verified by forcing the branch — it prints and the monitors resolve.
    It has not yet caught a live failure, so **the class of the leaked objects is still unknown**;
    the next failing run will name it without any extra work.
- E2E first-card fly-in in the pack preview: confirm fixed on a real run.
- Background-save robustness at scale unverified (large history serialize on a worker thread) —
  watch the console; the history cap bounds it.
- **PIXELS `test_the_card_mask_is_the_card_the_player_sees` is GREEN but PINNED, not fixed.** The
  check no longer demands exact cell agreement — that bar was unachievable and passed at rest by
  alignment. It asserts a band around the outline: **edges ≤ 1.7 FX cells** (the fraction is the
  32-slot wedge index, whose quantization is angular; measured worst 1.50) and **corner bite ≤ 2.6
  cells** (measured worst 2.45 at t=0.30). Both bounds are in CELL units so one `pixel` knob moves
  them together. The **COUNT** is asserted too — rest pose exact (0/0), deformed poses ≤ 130
  disagreeing cells (measured worst 104) — because the distance bars alone cannot see a shallow
  uniform boundary shift. ⚠ **All numbers are measured and deliberately tight so any worsening
  fails — do not raise them to go green.**

  Underneath it are **two independent model approximations**, diagnosed and NOT fixed; the fix is a
  model choice, so it is the owner's. The `[mask vs face WHERE]` line in `test_pixels.gd` buckets
  every disagreeing cell: corner cells 22/62/60 and edge cells 36/42/0 at the three deformed poses.
  - **CORNER class — `CardVisual.corner_points()`.** It puts the bite's middle point at
    `corner + along_prev + along_next`, assuming the corner cell stays a **parallelogram**. It is
    really a bilinear patch whose fourth point (the internal vertex, e.g. `(-14.25,-18.75)`) is
    skinned independently. Exact while the cell is a rectangle — which is why t=0.00 passes — and
    drifting as it shears. ⚠ **The function's own comment claims it is "exact under deformation";
    that claim is false**, and this is the measurement that shows it.
  - **EDGE class — the radial wedge mask.** `WEDGES = 32` (11.25° per slot) indexes which polygon
    segment a fragment is tested against, with only `WEDGE_CANDIDATES` consecutive slots tried.
    Deformation spreads the 24 vertices unevenly in angle, so a slot can span more segments than
    the window covers and points near a slot boundary test against the wrong segment.
  - **Options.** (1) Exact corner: re-do the skinning in GDScript from `Polygon2D.bones` weights
    for the 4 corner diagonals only — per-frame per-card code the comments already guard for cost.
    (2) Widen the candidate window, or drop the radial mask for a non-radial one. (3) Give the
    check a stated tolerance instead of demanding exactly 0.
  - **Already ruled out, do not re-open:** the baked `Offset/Visual` pose; the animation driving it
    (it does not — only bone `:position` tracks exist); bilinear filtering (a real harness bug,
    fixed, but t=0.30's 887 undecidable cells did not move); "tips vs skinning blend" (bone rests
    equal their vertices exactly and each vertex is ~0.99997 weighted to its own arm).
- **G2.3 / spotlight cost** (`fx_cost.gd::_spotlight_rows`). Over a 1.947 ms empty-scene floor:
  0 lights +0.478, 1 +0.607, 8 +1.537, 24 +4.666, 64 (MAX_LIGHTS) +12.237 ms. **≈0.19 ms per light,
  near-linear**, swept over LIGHT COUNT because `light.gdshader` shades the whole viewport
  regardless of host count. A realistic section (5–12 lights) is ~1–2.5 ms; 64 would blow a
  16.67 ms frame alone. `Q254`=(a): reported, nothing trimmed — the cut is the owner's call.
  ⚠ The GLOW is still unpriced: there is no `FxGlow` effect class, only the shader.
