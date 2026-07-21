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
