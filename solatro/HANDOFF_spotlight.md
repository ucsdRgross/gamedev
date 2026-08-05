# HANDOFF — spotlight

**Goal:** ship the Spotlight mechanic and its visual effects per
`solatro/design/spotlight/PLAN.md`. Done = phases 1–4 complete, every gate passed, and the owner
satisfied by eye on the visual phases. (Phase 5, the film pipeline, is a separate deliverable and is
NOT part of this stream.)

**State (2026-08-05):** phases **1, 2 (less S15) and 4 are shipped**. `DESIGN.md` is at **v12**; all
**eight** gaps are closed. **Remaining: S15, S16, S17, and gates G2.2 / G2.3 / G3.1–G3.3.**

**Entry docs:** `solatro/START_HERE.md`, `solatro/VFX.md`,
`solatro/design/spotlight/PLAN.md` (the spec — §1 is normative),
`solatro/design/spotlight/DESIGN.md` (the authority on behaviour; where it and the plan disagree, the
design wins), `solatro/HEADLESS_TESTING.md` **§0c** (the event log).

⚠ **THIS FILE IS STATUS AND NOTHING ELSE.** What each step IS lives in `PLAN.md` §2–§5; why a
decision went the way it did lives in `design/spotlight/gaps/GAP-00N.md`. Do not restate either here
— the first draft of this file grew to 1100 lines by accumulating history, which is the thing
`/handoff` forbids and which made every session start expensive.

---

## Before you write code

⚠ **Read `.claude/memory/seam-checks-not-rereading.md`.** Every defect on this stream — eight gaps and
a dozen others — is one shape: **two representations of one fact, with nothing comparing them.** It
is not a reading failure; `Q85` and §16's knob table were both read in-session and contradicted an
hour later. The full table is in that memory and in `DESIGN.md` v12's changelog.

**The three checks that exist because of it, and what each caught on its first run:**

```bash
npm --prefix designloop run check -- solatro/spotlight     # `unclaimed`: 190 of 255 answers had no step
"<godot>_console" --path solatro res://Tools/spotlight_tool.tscn -- --verify   # a thrown retire beat
```
plus `test_the_design_16_knob_table_is_implemented()` (parses `DESIGN.md` §16, found 13 missing knobs).

⚠ **Name the competing READINGS before implementing a rule, and test the input that separates them**
(`PLAN.md`'s gap-protocol block). This stream lost two days to rules that arrived with a worked
example: both readings reproduce the example, and only the case it does NOT cover tells them apart.

⚠ **Evidence hierarchy: green suite < printed counts < a rendered pixel < movement over time.** A
still frame cannot show a pulse, a travel, a fade or a dead cascade — a still of a working loop and a
still of a broken one are identical.

---

## How to verify

```bash
# The suite. WINDOWED, never --headless. ~60 s, self-quits, exits with the failure count.
"<godot>_console" --path <abs path to solatro> res://Tests/all_tests.tscn
# The tuning tool: inspector preview, a real act (--trace), or every scenario checked (--verify).
"<godot>_console" --path <abs path to solatro> res://Tools/spotlight_tool.tscn [-- --trace|--verify|--shoot-all]
```

- ⚠ **ALWAYS launch with `WaitForExit(<ms>)` AND KILL ON TIMEOUT.** A parse error leaves a blank
  window open forever and no in-scene watchdog can save it — the script never loads.
- ⚠ **`--headless --path <solatro> --import` FIRST after adding any `class_name`**, or it resolves as
  a bare `Resource`.
- ⚠ **The SUITE COUNT is the stable number: 29.** The check total drifts run to run (fuzz suites). A
  drop means a suite failed to LOAD while the banner still says PASSED.
- ⚠ **The suite FAILS on unexpected engine errors**, read from `user://logs/godot.log`.
  `ENGINE_ERROR_ALLOW` in `Tests/all_tests.gd` is the allowlist — keep it narrow.
- ⚠ **Never run Godot while the owner's editor is open.** ⚠ **No `git add`, no commits.**

---

## Tasks — status ledger. Read `PLAN.md` for what each step IS.

```yaml
- id: S1
  status: done
  evidence: 'Scripts/scoring_section.gd; SPOTLIGHT "S1", 5 checks green'
  notes: 'of_line / collect / refresh. refresh() is Q252=b, re-read after every hook.'

- id: S2
  status: done
  evidence: 'G1.2 green — the rename grep returns nothing outside addons/'
  notes: 'active->spotlit, is_active->is_spotlit, on_active->on_spotlight, on_deactive->on_unspotlight.'

- id: S3
  status: done
  evidence: 'CardModifier.blocks_spotlight(); SPOTLIGHT "S3: THE BLOCK SEAM", 9 checks green'
  notes: 'GAP-001: blocks_spotlight() defaults TRUE; Kuroko overrides to false; Revealing is a property of the card itself. REPLACES is_data_topmost, behaviour-neutral.'

- id: S4
  status: done
  evidence: 'GameData.forced_spotlight; SPOTLIGHT "S4", 5 checks green; G1.5 asserted'
  notes: 'Not @export_storage, cleared in duplicate_state() — undo/cancel/resume come back with no beam (Q18=a).'

- id: S5
  status: done
  evidence: 'Game._spotlight_section(); SPOTLIGHT "S5", 4 checks green; G1.4 asserted'
  notes: '⚠ forced_spotlight TRAVELS (Q16=c): never torn down between sections; membership is always the section being scored. A card in both a row and a column section announces TWICE per act.'

- id: S6
  status: done
  evidence: 'the §1.5 loop; test_hook_added_card_activates_in_the_same_phase() green'
  notes: 'note_processing() per loop iteration — without it act_event_cap cannot see the loop.'

- id: S7
  status: done
  evidence: 'test_discard_compacts_and_the_replacement_activates() + test_self_feeding_chain_ends_at_act_cap(); G1.6 satisfied'
  notes: 'The runaway test parks Game.act_calls under the cap rather than editing the SHARED settings resource; the spy carries a 40-generation brake so a failure to cap FAILS instead of hanging.'

- id: S8
  status: done
  evidence: 'SPOTLIGHT "S8", 2 checks green'
  notes: '⚠ CONTRACT CHANGE: a synthetic Result handed to score_line for a POPULATED zone is discarded in favour of the re-derived hand.'

- id: S9
  status: done
  evidence: 'Game._release_spotlight(); SPOTLIGHT "S9", 5 checks green; G1.7 log parity 60 lines identical'
  notes: 'Release RECOMPUTES rather than blanket-clearing, so a still-naturally-spotlit card fires no on_unspotlight (Q14=a).'

- id: S10
  status: done
  evidence: 'CardEnvironment.spotlight_cued(cards); SPOTLIGHT "S10", 3 checks green'
  notes: '⚠ Q246=a filters this to skills implementing on_spotlight. It is the MOMENTARY CUE only and S15 draws it — wiring the scoring beam to it was GAP-005 and made the feature invisible for a whole phase.'

- id: S11
  status: done
  evidence: 'UI/Fx/fx_glow_style.gd + Shaders/Styles/glow_{card,circle,beam}.tres; FX ATTACHMENT green'
  notes: 'GAP-003: glow_ramp is an off-palette Gradient. ⚠ Light is the ONLY thing outside the palette contract — granted once, scoped, does not travel. grid REPLACES the inherited pixel; no breathe_amp (Q126=a). Array uniforms padded to MAX_LAYERS=4 — Godot rejects a size mismatch whole, silently.'

- id: S12
  status: done
  evidence: 'Shaders/glow.gdshader; uniform seam asserted; RENDERED AND LOOKED AT (09_glow_falloff, 09b_glow_over_art)'
  notes: '⚠ The field PEAKS ON THE SILHOUETTE and falls away both ways. The first build had it backwards and only the render caught it — every headless check passed with no halo at all. blend_premul_alpha is Q218=(c): addition outside, a tint that cannot blow out over art, one pass.'

- id: S13
  status: done
  evidence: 'Shaders/light.gdshader + UI/light_layer.gd + LightLayer as SceneRoot LAST child; RENDERED AND LOOKED AT (10_light_layer)'
  notes: '⚠ NO BOARD->SCREEN CONVERSION EXISTS AND NONE IS NEEDED: one canvas layer, no camera offset, so a card global_position IS the viewport pixel. ⚠ set_lights([]) is what retires the dim — there is no stop() to disagree with the light set (QR2=d).'

- id: S14
  status: done
  evidence: 'UI/spotlight_origins.gd + UI/spotlight_director.gd; SPOTLIGHT "S14" 16 checks + the origin/travel tests (96 total); VISUAL LAYERS test_the_spotlight_wire_lights_the_layer() and test_the_light_travels_between_sections() (151 total). G2.4 PASSES. RENDERED AND LOOKED AT: 04_S4 (column fan), 07_S6 (interleaved), 10_S15.'
  notes: '⚠ Reads spotlight_section_changed, NEVER spotlight_cued (GAP-005). ⚠ Chart E travel is IN: lights outlive their section — Q61=a a card in both keeps its light, E3 surplus fades in place, Q65=a a new light fades in ALREADY AIMED, Q64=a all travel one frame, Q63=a FULL SIZE in transit, E10 the origin stays fixed. ⚠ _origins.begin() MAY ONLY RUN WHEN NOTHING IS LIT — it clears the taken-set and would re-point live beams. ⚠ Origin assignment is GAP-008: sections of the bar BY COLUMN left to right, fan by DEPTH inside each, ordered by distance. Partitioning by ROW is wrong for anything but one column. ⚠ Circles sit on the ART SQUARE via CardVisual.spotlight_center() (Q85), not the card origin.'

- id: S15
  status: pending
  evidence: ''
  notes: 'THE NEXT STEP. Draw what S10 emits. GAP-005 made it genuinely independent — spotlight_cued is this step''s signal alone and nothing else reads it. Q245=(c) shallower casual dim, which LightLayer.set_lights(lights, scoring=false) already selects.'

- id: S16
  status: pending
  evidence: ''
  notes: 'Derived row expansion. ⚠ The tuning tool already SIMULATES it (row_separation, eased over spotlight_reveal_fraction), so the shape is decided and visible — this is making PlayArea do it for real. A COLUMN expands every row it passes through (Q46, Q52, chart D4).'

- id: S17
  status: pending
  evidence: ''
  notes: 'Gutters, slot_center_global, prop anchors — blocked by S16, carries G3.1/G3.2. ⚠ slot_center_global is pure uniform-pitch math and every prop anchors to it; that is the known hard part.'

- id: S18
  status: done
  evidence: 'Tools/spotlight_tool.{gd,tscn} + spotlight_scenarios.json. G4.1: `-- --shoot-all` builds 13 presets with per-preset "cards=N lit=M sections=K"; `-- --verify` reports 13 scenario(s), 0 SUSPECT.'
  notes: '⚠ GAP-007: @tool + inspector, and Q174/Q175 (a real PlayArea and Game) are SUPERSEDED — no Game, no GameView, no HUD. Real CardVisuals on the REAL board pitch, real LightLayer, real shader, real glow. ⚠ THE CASCADE IS POSED, NOT RUN: a BEHAVIOUR question goes to `-- --trace` or the suite. ⚠ Everything renders in a SubViewport — light.gdshader is screen-space and the editor 2D view has its own pan/zoom. Its canvas_item_default_texture_filter must be NEAREST or every card is bilinear-smeared. ⚠ Pose a card only AFTER add_child: CardVisual._ready re-enables its own _process and delta_self_moving_logic then frees it, leaving a blank frame at exit 0.'
```

---

## Verified vs assumed

- **Verified 2026-08-05 — the tree:**
  ```
  ALL 29 SUITES: ~1814 passed, 3 FAILED  [19 placeholder warnings]
  [engine-errors] clean · 0 SCRIPT ERROR on stderr
  SPOTLIGHT 96 · VISUAL LAYERS 151 · FX ATTACHMENT 180 · [§16] 25 implemented, 9 pending
  designloop: 152 tests green
  ```
  **The 3 failures are PIXELS and are NOT this stream's** — see Open bugs.
- **Verified 2026-08-05 BY EYE** — `04_S4` (a column: the fan, near-vertical onto the topmost card,
  each deeper one from further out, no crossings), `07_S6` (interleaved: six beams left-to-right,
  cleanly separated), `02_S2b` (a buried row with the reveal simulated, glow rims on the lit cards),
  `10_S15` (the circle on the art square with the glow's warm rim), `09_S12` (the casual dim visibly
  shallower). Shots land in `user://logs/events/spotlight_tool/`.
- ⚠ **ASSUMED, NOT CHECKED — gate G2.2, the readability call.** Now judgeable for the first time (the
  glow is in the tool), and it is the owner's alone. Scenario **S15** holds one light on a card face.
- ⚠ **ASSUMED, NOT CHECKED — G2.3, the cost number.** `fx_cost.tscn` has never been run against the
  glow. `Q254`=(a): measure it, THEN decide what gets cut — report the number, trim nothing
  pre-emptively. The glow's outline branch is an unconditional 24-segment loop per lit fragment.
- ⚠ **UNTUNED — the GAP-006 per-section pulse.** Mechanically correct; at shipped pacing the whole
  cycle is 1–3 frames. Judge it in the tool's **S17** preset with `play` on. If it reads as a flash,
  the knobs are `spotlight_hold_fraction` and the two dim fractions — and **`spotlight_dim_target = 0`
  is the off switch**, which keeps every beam, circle and glow.

---

## Open bugs

⚠ **PIXELS fails 3 checks, and the cause is `Cards/card_visual.tscn`, which this stream never
touched.** The scene carries a **mid-animation pose baked into `Offset/Visual`** (`skew` 0.0007 →
0.0139, plus a rotation), which offsets the drawn face against the rig the fire mask is built from.
The owner also hid `Suit`/`Art`/`Skeleton2D` **deliberately** (the bones showed up in editor tools);
that half is harmless at runtime because `art.show()`/`suit.show()` are called in code.
**`git checkout -- solatro/Cards/card_visual.tscn` clears it. Do not "fix" it in the FX code.**

⚠ **The LEAK CANARY flake — reproduced, ~1 run in 4, and the signature MOVES.** Seen with growth 3
(`game.gd` strays), growth 2 (`/Fx` from `fx_attachment.gd` plus anonymous nodes) and growth 1. Two
different sources is weaker evidence for a flaky test than for a real intermittent leak. **Do not
report a green suite without saying how many runs it took.**

⚠ **A leaked GLES3 texture at exit**, printed AFTER the banner:
`ERROR: 1 RID allocations of type 'N5GLES37TextureE' were leaked at exit.`
⚠ **`_scan_engine_errors` reads `godot.log` DURING the run, so every exit-time error is invisible to
the gate by construction** — that blind spot matters more than the one texture. Cause unattributed;
the suspect is the glow's baked `GradientTexture1D`.

⚠ **LOWER PRIORITY — the light set is re-pushed every frame.** `SpotlightDirector._process` rebuilds
and re-pushes the whole array to follow moving cards. Correct, but 2 `PackedVector4Array` uploads per
frame for a set that usually has not changed. Worth a dirty check before **G2.3**.

**No gap is open.** GAP-001, 003, 004, 005, 006, 007, 008 answered and folded in; GAP-002 withdrawn.

---

## Files touched

**New:** `Scripts/scoring_section.gd`, `Scripts/event_log.gd`, `UI/Fx/fx_glow_style.gd`,
`UI/Fx/fx_spotlight_style.gd`, `UI/light_layer.gd`, `UI/spotlight_origins.gd`,
`UI/spotlight_director.gd`, `Shaders/glow.gdshader`, `Shaders/light.gdshader`,
`Shaders/Styles/glow_{card,circle,beam}.tres`, `Shaders/Styles/spotlight_default.tres`,
`Tools/spotlight_tool.{gd,tscn}`, `Tools/spotlight_scenarios.json`,
`Tests/Engine/test_spotlight.gd`, `Tests/Support/spotlight_test_{skill,kuroko}.gd`,
`design/spotlight/{ASSUMPTIONS.md,gaps/GAP-001..008.md}`.
**Deleted:** `Tools/spotlight_trace.{gd,tscn,gd.uid}` — merged into the tool as `-- --trace`.
**Edited (the ones that matter):** `Cards/card_visual.gd` (`spotlight_center()`),
`Scripts/card_environment.gd` (the two signals), `Scripts/player_settings.gd` (the Spotlight group),
`Levels/game.gd`, `Levels/game_view.{gd,tscn}`, `Tests/all_tests.gd` (the engine-error scan),
`Tests/UI/test_{visual_layers,fx_attachment}.gd`, `Tests/Engine/test_palette.gd`.
**Outside solatro:** `designloop/src/{gaps,check}.mjs` + `test/gaps.test.mjs` (the `unclaimed` report).

⚠ **Nothing is committed** — the owner commits through GitHub Desktop.
⚠ **Two tracked `~`-prefixed DLLs show as deleted** (`addons/*/bin/~*.dll`). Godot lock-rename
artefacts, committed by accident, almost certainly belong in `.gitignore`. Owner's call; not this
stream's.

---

## Still owed

**The log-parsing subagent** — deferred by the owner until logging was final; it now is. Scoped:
*"should only be used for massive logs such as recording an entire playthrough from start to
lose/win."* `EventLog.summary()` already handles ordinary captures.

---

## Next up

1. **S15 — the momentary cue's visuals.**
2. **S16 — derived row expansion**, then **S17** (gutters, `slot_center_global`, prop anchors).
3. **G2.2** (readability — the owner's call, in the tool), **G2.3** (the cost number),
   **G3.1–G3.3**.

### Opening prompt for the next agent

> Read `solatro/HANDOFF_spotlight.md`, then `solatro/design/spotlight/PLAN.md` §0's opening prompt.
> Confirm the tree before trusting any status: run the suite WINDOWED with a kill-on-timeout, check
> the SUITE count is **29** (not the check total, which varies) and `[engine-errors] clean`. Three
> PIXELS failures are expected and are `Cards/card_visual.tscn`'s, not the code's.
>
> **Work S15**, then S16 and S17. Before implementing any rule, name the competing readings and test
> the input that separates them — `PLAN.md`'s gap-protocol block says why. Run
> `npm --prefix designloop run check -- solatro/spotlight` and read `unclaimed` before starting a
> step; run `Tools/spotlight_tool.tscn -- --verify` for anything with a duration.
>
> ⚠ Do not `git add` or commit. ⚠ Do not run Godot while the owner's editor is open. ⚠ When a
> decision the design does not cover appears, file a gap — eight have been filed on this stream and
> every one was two representations of a fact with nothing comparing them.

---

## References

- `solatro/design/spotlight/PLAN.md` — the specification. §1 is normative.
- `solatro/design/spotlight/DESIGN.md` **v12** — the authority on behaviour. Where the two disagree,
  the design wins. Its v7–v12 changelogs carry every gap's reasoning.
- `solatro/design/spotlight/gaps/` — none open; each file carries its own forensics.
- `solatro/design/spotlight/ASSUMPTIONS.md` — decisions taken under gap-protocol rule 1.
- `solatro/HEADLESS_TESTING.md` §0c (the event log), `solatro/VFX.md` (the instrument table),
  `solatro/LAYERING.md`, `solatro/ARCHITECTURE_REVIEW.md` §4g/§4h/§4i.
- `.claude/memory/seam-checks-not-rereading.md` — the pattern behind every miss on this stream.
