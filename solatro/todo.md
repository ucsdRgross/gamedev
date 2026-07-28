# TODO — open backlog (owner-endorsed unless marked otherwise)

Last consolidated 2026-07-19. Done-work history lives in git; current-state facts live in
ARCHITECTURE_REVIEW.md. Add new items here; delete items when they land (record the
regression-critical residue in ARCHITECTURE_REVIEW.md instead of keeping a log here).

## Architecture / engine (unscheduled)

- D6 command-log undo — the real fix for per-action deep-copy cost (E5); eliminates
  reference remapping entirely. Big.
- Board §5 step (5): delete the `move_data_to_coord`/`move_data_ontop_data` Vector3i
  adapters when convenient.
- D1 real mod-hook contract (single HOOKS list / signature checking) · D2 route ALL mod
  state mutation through Game/Board (some mods still write arrays directly) · D4 kill the
  `CardEnvironment.CURRENT` static reach-through (pass the environment/context instead).
- D8–D11 cosmetics: comparator speculative abstractions, editor-tool code out of
  card_visual.gd, unify the zone pair into one structure, Scoring section-banner rewrite.
- S3 same-column move edge cases (unit-test the remaining matrix), S4 `PlayArea.separation`
  int/float, S7 verify every ModsList consumer duplicates.

## Scoring / balance (playtest phase — sim can't answer these)

- Playtest per SCORING_MATH_PLAN §10 protocol (git history): paired seeds, record sheets,
  acceptance bands. Open knobs: `difficulty` default, `combo_step` 0.1 vs 0.2,
  arrangement-capacity reality, mod-activation U generosity, Burning cascades as combo
  source, δ fallback trigger, `score_additive` A/B (needs goal_g0/alpha retune).
- Balance of the live `on_score`/`on_after_score` broadcasts — never balance-tested.
- Sim/doc fit drift: `--final --q 0.35` prints g0≈140/α≈2.03 while shipped constants are
  G0=130/ALPHA=4.2 — owner is not worried (tunables cover it); arbitrate if recalibrating.
- Rarity tiers (luck currently only gates non-null stamp/skill/type rolls).

## Scoring engine test gaps (from the retired SCORING_AUDIT)

- G3 direct ScoreModel table tests · G4 `get_loc_name` table test · G5 `_compare_results`
  full ordering chain · G1 end-to-end scoring under an active comparator mod.
- SD5 test-file section renumbering · SD6 exact-name leaderboard asserts · SE4 single-walk
  `_scan_wrap` (micro).

## Props / UI (owner has NOT yet re-verified)

- Description-panel scroll-lock, knife row behavior, hoop visibility, ballistic poof,
  undo-across-submit feel, held-loop spin, formation system + editor end-to-end (no
  formation .tres authored yet).
- Firework in-run acquisition beyond deck12 (owner decision). Per-pip tooltip granularity.
  Real `status_pips.png` asset (StatusLayer draws placeholders).
- Win/lose screen font (226px) clips long "Fame +N" text. game.tscn grabs no initial
  focus (keyboard/controller players must click first).

## Shader FX (landed 2026-07-27 — owner playtest pending; see ARCHITECTURE_REVIEW §4g)

- **Picking this up? Read [FX_HANDOFF.md](FX_HANDOFF.md) first** — state, open bugs, the exact
  commands, and the traps already paid for. New owner requirements (spherical balls, onion-layered
  fire, adjustable heights, and a universal palette system) are T17–T21 in FX_SHADER_PLAN.md §7.
- **⚠ OPEN BUG — ball positions disagree with the spec at LOW ball counts.** Run
  `Godot --path solatro res://Tests/Visual/fx_snapshot.tscn` and look at `05_balls.png` and
  `05b_ball_path.png`: the green crosses are an independent GDScript oracle transcribed from the
  spec, and at 50 balls the balls sit on them while at 1 ball the rendered ball is nowhere near
  its cross. The uniforms reaching the material are all correct (verified by the harness's own
  print: phase 0.13, count 1, span 30.4, arc 37.5, return 6, top_fraction 0.6), and the call sites
  of `fx_ball_at` pass their arguments in the declared order — so the fault is inside
  `fx_nearest_ball` / the `juggle.gdshader` fragment, most likely in the index recovery when
  `count` is 1 (every candidate wraps to the same index, so a wrong branch cannot be caught by
  disagreement between candidates). **Fire is unaffected**; this is balls only. Start from
  `05b_ball_path.png`, which traces one ball around the whole cycle phase by phase.
- Once that is fixed, re-check `06_ball_fire.png`: whether the plumes are welded to their balls
  cannot be judged while the balls themselves are misplaced.

- **Owner verification, in-game.** Shader pixels are not headless-testable — the dummy renderer
  never compiles a program — so nothing below has been seen running. Walk: 1/3/40 Burning stacks
  on a card (one full-width triangle → three tendrils → a fierce sheet, never 40 slivers);
  the same 1 stack on a knife (honestly small, still a triangle); a burning card partly behind
  another (flames cut exactly where it is covered, never painted over the card in front); the
  deck viewer (identical, scaled); a fast drag then stop (flames trail, whip past, settle — and no
  jitter when idle); 5 balls with 2 lit (exactly 2 plumes, welded, at every speed and under
  compression) while a burning card with unlit balls shows NO ball fire; balls spinning out of
  sync; the closed loop peaking above the card's top edge and returning across its centre; adding
  and removing stacks one at a time (nothing jumps, the last one fades); flipping face-down
  (everything disappears); 50 juggling stacks (balls shrink, arc grows, frame rate unchanged);
  dragging a burning card (embers stay where they were dropped); a burning hoop threading a card
  (flames upright, back-arc flames behind the card, card still passes through); focusing a burning
  card (card and flames brighten together); undo mid-act (everything clears, embers finish).
- **The numbers to settle by eye**, all single tunables: `FxFire.FX_MAX_TENDRILS` (12),
  `FxStyle.level_ref` (120 card / 60 prop / 40 ball), `settings.fx_transition_fraction` (0.6),
  `ParticleEngine.MAX_PARTICLES` (1024), `FxStyle.ember_rate_max` (24/s), ball spin base and
  its per-count coefficient, and the ~35 art levers in the `Shaders/Styles/*.tres` presets.
- **Fill rate is the one unmeasured risk** and it needs a real GPU to measure: 20 burning cards on
  the board, then 50 in the deck viewer, read the frame time. If it measures badly, spend the
  levers in this order — raise `FxStyle.pixel` (chunkier FX pixels is a LOOK change, not a
  capability loss) → drop `fx_fbm` to one octave → cap `FxStyle.height` to shrink the quads → and
  only then reconsider one-quad-per-effect. Do not start by cutting features.
- **Motion lag is tier 1** (one spring). The 8-sample position history that gives a real S-curve
  is only worth building if a single arc reads flat — show the owner tier 1 first.
- `Shaders/Styles/` now holds FxStyle presets AND `ember.tres` (a ParticleSpec), which makes the
  folder name wrong. Everything lives in ONE place, which is what the ruling asked for; renaming
  the tree to `res://Fx/` is a separate mechanical change.
- `FxAttachment.measure_silhouette` samples the card's authored/baked outline once. Live per-frame
  BONE deformation from the star rig is not tracked — re-call it if anything ever re-bakes a card
  shape at runtime.

## Patience & rerolls (landed 2026-07-20 — owner playtest pending)

- Tune `patience_max` (ships 3) and the per-stage `patience_influence_*` flags (ships PLAY
  only); decide whether the legality query `on_can_place_stack` should count at all — if not,
  add it to `patience_disabled_hooks` and re-tune what "interesting move" means. Full
  behavior + the settings list: ARCHITECTURE_REVIEW §4e.
- Rule cards that raise `patience_max` / grant patience: the grant path exists
  (`patience_max_increased`), no content uses it yet.
- Booster rerolls (§4f): pool ships at 5 (`booster_reroll_pool`); reroll-count modifiers
  (the `luck()`-style content hook) not written yet.
- Watch existing suites for auto-Next fallout: any test that makes 3+ boring moves in one
  round now advances the round mid-test.
- `patience_max` ships **3**, but the original spec asked for a default of **1** — confirm
  which is intended before playtest conclusions (3 = three idle moves per round).
- Comparator hooks now reach patience: `on_compare_ranks/suits` fire through
  `return_first_compare_mod_result` during the placement legality query, so ANY board card
  with a comparator modifier holds the counter (once per round under uniques). Decide whether
  that is the intended "interesting move" bar or belongs in `patience_disabled_hooks`.
- `Game._on_patience_max_increased` edits `state.patience` with no commit — a mid-round grant
  is lost on quit and reverted by undo. Fine for a settings knob; revisit when a rule CARD
  grants patience (that grant should ride a committed action).
- `Game._ready` connects to `SettingsManager.settings.patience_max_increased` without the N9
  reconnect idiom — the connection binds the settings resource that exists at show start. Only
  matters if `SettingsManager.settings` is ever reassigned at runtime (its setter supports it).
- Two known gaps documented in ARCHITECTURE_REVIEW: the auto-Next pending-action replay
  caveat (§1.5) and the seen-set-only commit gap in `_perform_next` (§4e).
- Test hygiene (partly done 2026-07-20): settings isolation now lives on `TestSuite`
  (`backup_real_settings`/`restore_real_settings` + `snapshot_settings(prefix)`), used by
  PATIENCE, UI VIEWERS and INTERACTION. UI PROPS, VISUAL LAYERS and LEAK CANARY still carry
  their own copy-pasted `REAL_SETTINGS_PATH`/`REAL_SETTINGS_BAK` pair — migrate them onto the
  shared helpers (that also frees the base const back to the obvious name; see the note on
  `TestSuite.SETTINGS_FILE`).

## Design work not started (DESIGN_DOC pointers)

- Entrance drop-down between acts (DESIGN_DOC §2) — decide + implement.
- Tips / hype-wagering / fog of war / tour planning (§15); circus renames (§9); shop &
  economy (§16); meta progression (§19); leaders/acts (§11); deterministic per-subsystem
  RNG streams (§6/§23 — required before seed-sharing features).

## Testing / infrastructure

- Headless "hangs after final banner": did not reproduce 2026-07-17 (6 clean runs) — if
  it recurs, capture with `--verbose`; workarounds in HEADLESS_TESTING.md.
- E2E first-card fly-in in the pack preview: confirm fixed on a real run.
- Background-save robustness at scale unverified (large history serialize on worker
  thread) — watch console; history cap bounds it.
