# HANDOFF — spotlight

**Goal:** ship the Spotlight mechanic and its visual effects per
`solatro/design/spotlight/PLAN.md`. Done = phases 1–4 complete with every gate passed and the owner
satisfied by eye on the visual phases. (Phase 5, the film pipeline, is a separate deliverable and is
NOT part of this stream.)

**State: PHASE 1 DONE AND GREEN. PHASE 2 IS THROUGH S13 (2026-08-04).** S1–S10 passed every
phase-1 gate (G1.1–G1.7). S11 shipped `FxGlowStyle` and its three `.tres` — the glow's colour ramp
is an off-palette `Gradient` (GAP-003), which makes light the one thing in the game outside the
palette contract. S12 shipped `Shaders/glow.gdshader`, **rendered and looked at**: the halo, the
two-layer split and the `inverse_square` knob all read correctly on `09_glow_falloff`. S13 shipped
`Shaders/light.gdshader`, `UI/light_layer.gd`, the `LightLayer` node as `SceneRoot`'s LAST child,
and `LAYERING.md`'s entry for it — **rendered over a REAL board and looked at**: dim, crossing beams
that brighten without blowing out, beams that stop on their circles' far arcs, and cards under
circles that keep their rank, suit pip and art square.

⚠ **NOBODY CALLS `LightLayer.set_lights()` YET, so the dim never rises in the running game.** The
node, its shader, its placement and its tunables are all in and asserted; the wire from the
spotlight cue to the layer is **S14**, which is the next step. Gate **G2.4** cannot run until
something lights it, and gate **G2.2** (the readability call) is still unjudged — the circle blowout
the real board surfaced is fixed, but confirming it is the owner's eye against the wired game, not
mine against a snapshot.

⚠ **A SUITE-INTEGRITY DEFECT WAS FOUND AND FIXED ON RESUME (2026-08-04) — read this before trusting
any older evidence line in this file.** Five phase-1 tests had been **aborting mid-function** on a
call to `is_spotlit()` through a null `CardData.type`, and the runner counts only the checks that
actually ran, so **the banner said `CHECKS PASSED` while S3 emitted 1 check instead of 9 and S4
emitted 1 instead of 5**. The fixture was the fault, not the feature: `TestFactories.m_card` builds a
card with **no type modifier at all**, while every real card gets one (`Decks/deck.gd:36`), and
`is_spotlit()` lives on `CardModifier` — so `card.type.is_spotlit()` was a call on `Nil`.
`test_spotlight.gd`'s `play_card()` now attaches a `TypePaper`, matching the real deck. **SPOTLIGHT
went 64 → 76 checks, all green**, and gate **G1.5's assertion had never actually executed**.
⚠ **The lesson generalises past this stream: a GDScript runtime error inside a test function is
silent test LOSS that reads exactly like a pass.** Check a section's check COUNT against what the
file asserts, not the banner — and treat any `SCRIPT ERROR` on stderr as a failure even when the
summary line is green.

The design is confirmed (`DESIGN.md` **v9**, 255 answers, 0 open questions, no gap open); `PLAN.md`
is the specification and has not moved except for its §0 opening prompt, rewritten to be stateless,
and §1.8's one known-wrong row.

**Entry docs:** `solatro/START_HERE.md`, `solatro/VFX.md` (phases 2–4 only),
`solatro/design/spotlight/PLAN.md`, `solatro/design/spotlight/DESIGN.md`

## Why this is a separate file from `PLAN.md`

**One reason, and it is enough: the plan is IMMUTABLE and this is not.** The gap protocol marks plan
steps stale when a design node changes — *"S5 is stale"* is a claim about a specification, and it
stops meaning anything if the same file also churns with status flips. Keeping them apart is what
lets `git diff PLAN.md` answer "has the contract moved?" with a yes or a no.

(Two lesser reasons: a work stream can span more than one plan, or none; and this file is **deleted**
when the stream lands, while the plan belongs to the design record until that is folded away too.)

⚠ **THIS FILE HOLDS STATUS AND NOTHING ELSE.** Every step's description, files, dependencies,
verification command, done-when and design-node citations live in `PLAN.md` — §0b for the dependency
graph, §2–§5 for the steps, §2/§3/§4 for the gates. **Do not restate any of it here.** The repo's
doc-hygiene rule forbids the same text in two places, and the first draft of this file broke it: it
carried a full copy of all 18 step descriptions, which is exactly the kind of second copy that goes
quietly out of step with the first.

Standing alone with zero context does not require restating the plan — it requires naming it, and
`solatro/design/spotlight/PLAN.md` is a repo-relative path that resolves on any machine.

⚠ **Do not put checkboxes in `PLAN.md`.** Measured: a `- [ ]` prefix makes the step vanish from
`designloop`'s parser and silently re-attributes its `(implements …)` citations to the step above,
so the stale-step report then names the wrong steps.

## Tasks — status ledger. Read `PLAN.md` for what each step IS.

```yaml
- id: S1
  status: done
  evidence: 'Scripts/scoring_section.gd; SPOTLIGHT suite section "S1: THE SCORING SECTION", 5 checks green (row, ragged row, column, provenance, refresh)'
  notes: 'of_line / collect / refresh. refresh() is the Q252=b re-read the activation sweep runs after every hook.'

- id: S2
  status: done
  evidence: 'G1.2 green — grep -rn "is_active|skill_active_check|on_active|on_deactive" --include=*.gd solatro/ returns nothing outside addons/. Docs renamed too (ARCHITECTURE_REVIEW.md, DESIGN_DOC.md).'
  notes: 'active->spotlit, is_active->is_spotlit, skill_active_check->skill_spotlight_check, on_active->on_spotlight, on_deactive->on_unspotlight. addons/worldgen untouched, as the plan requires.'

- id: S3
  status: done
  evidence: 'CardModifier.blocks_spotlight() + _blocked_from_above() + _card_blocks(); SPOTLIGHT section "S3: THE BLOCK SEAM", 9 checks green (default blocks, headers follow their column, Kuroko unhides, Revealing survives being buried two deep, forced bypasses). ⚠ RE-VERIFIED 2026-08-04 on resume: only 1 of these 9 had ever run — see the suite-integrity note at the head of this file.'
  notes: 'GAP-001 answered by the owner 2026-08-04, implemented, and FOLDED IN (DESIGN.md v7 + PLAN.md §1.4 corrected): blocks_spotlight() defaults TRUE (a covering card hides the talent beneath), a Kuroko modifier overrides to false and unhides it, one opting-out modifier is enough for its card, Revealing is a property of the card itself. The seam REPLACES is_data_topmost, behaviour-neutral.'

- id: S4
  status: done
  evidence: 'GameData.forced_spotlight; SPOTLIGHT section "S4", 5 checks green. G1.5 asserted by test_forced_spotlight_never_bumps_revision(). ⚠ RE-VERIFIED 2026-08-04 on resume: only 1 of these 5 had ever run, and G1.5''s check was one of the four that did NOT — see the suite-integrity note at the head of this file.'
  notes: 'Not @export_storage, and explicitly cleared in duplicate_state(), so undo / act-cancel / resume all come back with no beam on the board (Q18=a).'

- id: S5
  status: done
  evidence: 'Game._spotlight_section(); score_line builds the section as its first act. SPOTLIGHT section "S5", 4 checks green. G1.4 asserted by test_buried_card_lit_during_its_phase().'
  notes: '⚠ forced_spotlight TRAVELS (Q16=c): never torn down between sections, membership always the section being scored. GAP-002 was filed on misreading "stays" and "moves" as a conflict and is WITHDRAWN — nothing about the code changed. Consequence, pinned in the G1.7 log: a card in both a row and a column section announces TWICE per act.'

- id: S6
  status: done
  evidence: 'the §1.5 loop; SPOTLIGHT test_hook_added_card_activates_in_the_same_phase() green.'
  notes: 'note_processing() per loop iteration — without it act_event_cap cannot see this loop at all. Logged in ASSUMPTIONS.md.'

- id: S7
  status: done
  evidence: 'SPOTLIGHT test_discard_compacts_and_the_replacement_activates() and test_self_feeding_chain_ends_at_act_cap(), both green. G1.6 satisfied.'
  notes: 'The slide is free (a column is a plain Array). The runaway test parks Game.act_calls just under the cap rather than editing the SHARED settings resource that concurrent suites read, and the spy carries a 40-generation brake so a failure to cap FAILS instead of hanging.'

- id: S8
  status: done
  evidence: 'score_line re-evaluates once over section.cards; SPOTLIGHT section "S8", 2 checks green (a broken meld banks the smaller hand, an emptied section banks zero).'
  notes: '⚠ CONTRACT CHANGE: a synthetic Result handed to score_line for a POPULATED zone is now discarded in favour of the re-derived hand. Tests/Engine/test_game_headless.gd was updated for it.'

- id: S9
  status: done
  evidence: 'Game._release_spotlight(), called from _perform_submit. SPOTLIGHT section "S9", 5 checks green. G1.7: the windowed and headless SPOTLIGHT log sections are identical (60 lines), mod-fire line "c0.bottom,c1.bottom,c0.top,c1.top,c0.bottom,c1.bottom" in both.'
  notes: 'Release RECOMPUTES rather than blanket-clearing, so a card that is still naturally spotlit fires no on_unspotlight (Q14=a).'

- id: S10
  status: done
  evidence: 'CardEnvironment.spotlight_cued(cards), emitted once per sweep that saw any transition. SPOTLIGHT section "S10", 3 checks green.'
  notes: 'Q246=a (the skill must implement on_spotlight) and Q247=a (one cue carrying every card) are both in the emit. NO suppression code for resume — Q248=b, the case cannot arise. Phase 2 draws what this emits.'

- id: S11
  status: done
  evidence: 'UI/Fx/fx_glow_style.gd + Shaders/Styles/glow_{card,circle,beam}.tres. FX ATTACHMENT suite (152 checks), new sections "THREE GLOW STYLES", "THE GLOW''S GRID IS THE KNOB", "LAYER ARRAYS REACH THE SHADER AT EXACTLY MAX_LAYERS", "THE GLOW''S DELETED KNOBS STAY ABSENT, AND ITS RAMP IS OFF-PALETTE". Full suite: ALL 29 SUITES: 1707 CHECKS PASSED, exit 0, WINDOWED, test_output_errors.log 0 bytes.'
  notes: 'Every knob of PLAN.md §1.8 shipped. GAP-003 answered by the owner 2026-08-04 (off-palette): glow_ramp is a Godot `Gradient` baked to a linear-filtered GradientTexture1D — ⚠ the ONE thing in the game not palette-bound, granted once and scoped to light. Two deliberate deviations, both pinned by tests: `grid` REPLACES the inherited `pixel` (ASSUMPTIONS.md, Q213=d — the base range stops at 0.25 and cannot reach screen resolution); no breathe_amp/breathe_speed (Q126=a steady). Array uniforms are padded to MAX_LAYERS=4 because Godot rejects a size mismatch whole, silently.'

- id: S12
  status: done
  evidence: 'Shaders/glow.gdshader. Uniform seam asserted by "EVERY GLOW UNIFORM THE STYLE WRITES EXISTS IN THE SHADER" (14 names + u_brightness + u_mask_kind/u_space) and "GLOW SHADER CONSTANTS AND ABSENCES". ⚠ RENDERED AND LOOKED AT: Tests/Visual/fx_snapshot.tscn shots 09_glow_falloff and 09b_glow_over_art — see "Verified vs assumed" for what the images actually show.'
  notes: '⚠ THE FIRST BUILD HAD THE FIELD BACKWARDS and only the render caught it: `d + sink` (fire''s erosion) spends part of the reach BEFORE the silhouette, so the light was a third decayed at the card''s edge and there was NO HALO AT ALL in any panel — while every headless check passed. The field now PEAKS ON THE SILHOUETTE and falls away both ways: outward over each layer''s radius, inward over `sink` (which is Q122=c''s inner lift, a rim rather than a wash). ⚠ The blend is `blend_premul_alpha`, which IS Q218=(c): alpha 0 outside is pure addition, alpha over the art is a tint that cannot blow out — both halves in one pass, no second material. ⚠ The over-art alpha is scaled by the light''s own coverage; a constant one dims every card in reach by 1-inner_alpha.'

- id: S13
  status: done
  evidence: 'Shaders/light.gdshader + UI/light_layer.gd + the LightLayer node as SceneRoot''s LAST child in Levels/game_view.tscn + LAYERING.md''s draw-order list + the four Spotlight tunables in Scripts/player_settings.gd. RENDERED OVER A REAL BOARD AND LOOKED AT: fx_snapshot shot 10_light_layer. Placement pinned by VISUAL LAYERS test_light_layer_is_over_everything() (4 checks: the node exists, it is the LAST child, it ignores the mouse, and an unlit board is not dimmed). Full suite ALL 29 SUITES: 1694 CHECKS PASSED [19 placeholder warnings — unchanged], exit 0, WINDOWED, errors log 0 bytes.'
  notes: '⚠ NO BOARD->SCREEN CONVERSION EXISTS AND NONE IS NEEDED: one canvas layer, no camera offset, so a card''s global_position IS the viewport pixel the shader''s SCREEN_UV resolves to, scroll already folded in. A second copy of the scroll here is the drift bug this avoids. ⚠ set_lights([]) is what RETIRES the dim — there is no stop() to disagree with the light set (QR2=d). ⚠ Q84/Q168 on dim_target: the light layer has NO style resource (FxGlowStyle''s three .tres are the GLOW''s), so Q84=(b) style-only has nowhere to live and it went into PlayerSettings as Q168 says. Flagged in the property''s own doc comment; if that reading is wrong, file a gap. ⚠ NOT YET DONE and NOT part of S13: nobody CALLS set_lights() — feeding it from the spotlight cue is S14/S15, and gate G2.4 needs that caller before it can run.'

- id: S14
  status: in_progress
  evidence: 'UI/spotlight_origins.gd (chart I) + UI/spotlight_director.gd (the wire) + GameView builds and binds it. SPOTLIGHT suite "S14: THE ORIGIN ALLOCATOR", 16 checks. VISUAL LAYERS test_the_spotlight_wire_lights_the_layer(): the REAL CardEnvironment cue on a REAL dealt board lights the layer, every live beam points DOWN at its target (Q117), the dim rises because something is lit (QR2=d), and retiring the set lowers it with no separate stop path. ⚠ GATE G2.4 PASSES in that test: fx_intensity 0 takes u_brightness to 0 and THE DIM STILL STANDS (Q83 "keeps beams glow and dim"). Full suite ALL 29 SUITES: 1724 CHECKS PASSED, exit 0, WINDOWED, errors log 0 bytes.'
  notes: '⚠ REMAINING: chart E (the light TRAVELLING between sections with its own easing). What is in is chart I plus the wire — the per-frame pass re-reads each lit card position, so a beam follows a card that moves (the S7 slide, a jump, a scroll), but there is no eased travel between one section and the next yet. ⚠ THE WIRE BUG WORTH KNOWING: bind() first used CardEnvironment.get_current_game(), which is null at GameView._ready because the view deliberately builds and binds its Game BEFORE adding it to the tree. Nothing connected, and every other phase-2 test stayed green while the feature did nothing — the environment is now PASSED IN. ⚠ _origins is APPEND-ONLY: indices are permanent handles, and the first build sorted the store on subdivision, which re-pointed live handles (measured: two beams sharing one origin). ⚠ Q117 lives in the allocator, not the shader — two copies could disagree invisibly.'

- id: S15
  status: pending
  evidence: ''
  notes: 'blocked by S13 and S10'

- id: S16
  status: pending
  evidence: ''
  notes: 'PHASE 3 — needs phase 1 green'

- id: S17
  status: pending
  evidence: ''
  notes: 'blocked by S16; carries gates G3.1, G3.2'

- id: S18
  status: pending
  evidence: ''
  notes: 'PHASE 4 — blocked by S13, S16'
```

## Verified vs assumed

- **Verified 2026-08-04 ON RESUME — the tree is green, and green for real this time:**
  ```
  ======== ALL 29 SUITES: 1746 CHECKS PASSED [19 placeholder warnings] ========
  WINDOWED · test_output_errors.log 0 bytes · 0 `SCRIPT ERROR` lines on stderr
  ============ SPOTLIGHT: ALL 76 CHECKS PASSED ============   (was 64)
  ```
  Command: `"<godot>_console" --path solatro res://Tests/all_tests.tscn`, launched with
  `Start-Process -RedirectStandardOutput -RedirectStandardError` and waited on.
  ⚠ **The `+12` is the whole point** — the run BEFORE the fix also said `CHECKS PASSED`, at 1739.
  The stderr stream carried five `SCRIPT ERROR: Invalid call. Nonexistent function 'is_spotlit' in
  base 'Nil'` lines that the summary line knew nothing about. **`test_output_errors.log` was 0 bytes
  in BOTH runs, so it does not catch this class either.** Diffing a section's check count against
  the `check(` calls in its source is what caught it.
- **Verified 2026-08-04 — S11 and S12, the full suite after both:**
  ```
  ======== ALL 29 SUITES: 1707 CHECKS PASSED [19 placeholder warnings] ========
  exit 0 · WINDOWED · test_output_errors.log 0 bytes
  ```
  Command: `timeout 400 "<godot>" --path solatro res://Tests/all_tests.tscn`. The new checks are all
  in the FX ATTACHMENT suite (152 checks, all pass). **29 suites, equal to the phase-1 count and
  above the 28 baseline** — neither step added a suite, only sections.
  ⚠ **`--headless --path solatro --import` was needed first**, as it was in phase 1: `FxGlowStyle`
  is a new `class_name` and the three `.tres` name it in `script_class`, so without the reimport
  they load as bare `Resource`.
- **Verified 2026-08-04 BY EYE — `09_glow_falloff`, rendered and looked at.** Command:
  `"<godot>" --path solatro res://Tests/Visual/fx_snapshot.tscn`; the PNGs land in
  `user://fx_snapshots/`. What the image actually shows, panel by panel:
  - a **white-hot rim sitting exactly on the card's outline** with a warm amber halo bleeding
    outward, and no seam, notch or discontinuity anywhere along it — including the corners;
  - `inverse_square` **0.0 → 0.6 → 1.0 tightens the halo monotonically**, from a broad soft bloom to
    a crisp outline with a narrow fringe. The knob reaches the shader and points the right way
    (`Q208`: a lamp, not a smudge);
  - **1 layer shows the rim and no outer halo; 2 layers shows both** — which is `Q207`=(b)'s
    *"a tight bright core plus a wide soft halo... where almost all of the effect is"*, visible;
  - **no rectangle at the quad's edge**, which is what `falloff()`'s normalization exists to prevent
    (an un-normalized inverse-square is still ~4 % at its limit, and 4 % with a hard edge is a box
    around every glowing card).
- **Verified 2026-08-04 BY EYE — the beam's grain, retuned.** The first defaults put `fx_fbm`'s
  base cell at ~50 screen pixels, so the "volumetric noise" read as flat blocks the size of a card's
  art square. ⚠ **Isolated, not guessed**: rendering with `u_beam_noise = 0` made the patches vanish,
  which ruled out the dim's Bayer dither. Now grain rather than blocks, and every knob involved
  (`u_beam_noise`, `_scale`, `_scroll`) is a uniform.
- **Verified 2026-08-04 BY EYE — the circle edge, settled at 0.4** after 0.25 (arc) and 0.75 (too
  soft). ⚠ The lesson is worth more than the number: **blurring a boundary is not how you remove a
  discontinuity across it.** 0.75 hid the arc; converging the beam's coverage on the circle's
  removed it, which is what let the edge be crisp again.
- **Verified 2026-08-04 BY EYE — the beam/circle join SCALES.** The owner asked whether the shape
  stays consistent if the circle is enlarged later. It does, and it is structural rather than
  tuned: **the beam's mouth AND its end cap are both derived from `radius`**, so there is no second
  number to fall out of step. Pinned by looking rather than by claiming — `10_light_layer` now
  carries **three different radii (46 / 70 / 100)** and all three show the same shape at different
  sizes, checked at 3x magnification on the largest, where a chord would be most visible. ⚠ Keep the
  three radii in that shot: a single-size panel cannot show this and the question will come back.
- **Verified 2026-08-04 BY EYE — the circle READS as its own pool inside the beam** (chart H5), at
  all three radii, with the card under it keeping its rank and pips. That needed
  `u_circle_intensity` — see `ASSUMPTIONS.md` for why it is 0.3 and why it should fall further once
  the glow draws the disc.
- **Verified 2026-08-04 BY EYE — `10_light_layer`, rendered and looked at.** What the image shows:
  - **the dim is real and it is a dark blue-grey, not black** (`Q79`=a), uniform rather than a
    vignette, with the stand-in board reading as dark rectangles outside the light and at full
    brightness inside it — H7 and H8 as one equation, the beam punching its own hole;
  - **the two crossing beams ARE brighter where they cross** — a clearly brighter diamond at the
    overlap — **and it does not blow out to white**. `Q100`=(a) and `Q101`=(a), both visible in one
    region;
  - each **circle is markedly brighter than its beam** with a hot white core (chart H5);
  - the beams carry **visible chunky grain that scrolls along them**, not screen static (`Q98`=b,
    `Q99`=a).
- ⚠ **AN OWNER CALL THE SHOT RAISED, NOT ANSWERED: the beam does not stop at its target.** Past the
  circle it continues at constant width to the edge of the screen. That is what a real followspot in
  haze does and it is what the code deliberately does (`beam_cover` does not clamp `t` in the edge
  term) — but nothing in the design asks for it either way, and on the shot it reads as the beam
  sailing past the card it is lighting. **Worth a look before S14 pins the origins.** It is one
  line to change.
- ⚠ **ASSUMED, NOT VERIFIED — gate G2.2, the readability call, and it is the important one.**
  `09b_glow_over_art` steps `inner_alpha` 0 / 0.35 / 0.6 / 0.9 and the four panels **look nearly
  alike**: with the field peaking on the silhouette, a card glow barely covers art at all, so the
  knob only moves a thin inner rim. **The design predicted exactly this** (§14b.3: *"A halo around a
  silhouette barely covers art at all; the spotlight circle is the worst case"*). The panels are
  also staged over an OUTLINE-ONLY ghost, so there is no card face in them to judge legibility
  against. **G2.2 needs the circle at full intensity over a real busy card face — scenario S15 —
  which needs the light layer (S13). It has not been judged and must not be reported as passed.**
- ⚠ **ASSUMED, NOT CHECKED: G2.3 and G2.4.** `fx_cost.tscn` has not been run before or after
  (`Q254`=a says build it, measure it, THEN decide what gets cut — so the number is owed, and
  nothing has been trimmed pre-emptively). `fx_intensity = 0` has not been exercised against the
  glow. The shipped `inner_alpha = 0.35`, `grid = 0.5`, `reach = 4` and the two-layer split remain
  **starting points for the owner's eye** (`Q216`=d, `Q213`=d, `Q210`), not tuned values.
- **Verified 2026-08-04 — every phase-1 gate, all green:**
  - **G1.1** `ALL 29 SUITES: 1667 CHECKS PASSED [19 placeholder warnings]`, exit 0,
    `test_output_errors.log` EMPTY, **WINDOWED**. Suite count **29 ≥ the 28 baseline** below; the
    new suite is `Tests/Engine/test_spotlight.gd` (37 checks). ⚠ The CHECK total varies run to
    run (two green runs read 1649 and 1667) — the fuzz and leak suites emit a variable number. **The
    SUITE count is the stable number and the one G1.1 is about.**
  - **G1.2** the grep returns nothing outside `addons/`.
  - **G1.3** `test_migration_pre_rename_save()` — a real `ResourceSaver` round trip with the
    written `spotlit = ` rewritten back to `active = `, then `_resume_show`'s resync line: the
    same spotlit set a fresh derive gives, and **zero** `on_spotlight`.
  - **G1.4** `test_buried_card_lit_during_its_phase()`.
  - **G1.5** `test_forced_spotlight_never_bumps_revision()`. ⚠ Scoped to the forced-spotlight
    write / read / clear, **not** to a whole submit: `discard_lower_board()` and `draw_card()`
    bump `revision` and always did, so G1.5's literal wording in `PLAN.md` is unachievable and
    the assertion is the actual content of `Q17`=(a).
  - **G1.6** `test_self_feeding_chain_ends_at_act_cap()`, with the spy's own 40-generation brake
    as the bounded watchdog the gate asks for.
  - **G1.7** windowed vs `--headless`: the whole SPOTLIGHT log section is identical, 60 lines.
    The only failure anywhere in the headless run is the PIXELS suite, which refuses a dummy
    renderer by design.
- ⚠ **BASELINE for gate G1.1, measured 2026-08-04 on an unmodified tree** — G1.1 says the suite
  count must not drop, which is unverifiable without this number:
  ```
  ======== ALL 28 SUITES: 1616 CHECKS PASSED [19 placeholder warnings] ========
  exit 0 · 0 Parse Errors · test_output_errors.log empty
  ```
  Command: `timeout 400 "<godot>" --path solatro res://Tests/all_tests.tscn`
  **28 suites / 1616 checks is the floor.** A lower SUITE count means a suite failed to load and the
  banner still says PASSED — check the number, not the word.
- **Verified 2026-08-03:** the plan's 18 steps all parse and all cite real design nodes — 0 unknown
  citations, 0 steps without a chart-node citation. Command:
  `node --input-type=module -e "import {readPlanSteps} …"` against `designloop/src/gaps.mjs`.
  ⚠ **`readPlanSteps(design.dir)` reads `PLAN.md` ONLY** (`designloop/src/server.mjs:424`). This
  file is never parsed by the tool, so its shape is for humans and agents, not for the stale report.
- **Verified 2026-08-03:** every path `PLAN.md` names exists, or is created by a step in it.
- **Verified 2026-08-03:** `solatro/design/spotlight/DESIGN.md` — 0 errors, 0 warnings, 0 unresolved
  links, `dag audit` 0, `stale` 0. Command:
  `npm --prefix designloop run check -- solatro/spotlight`.

## Open bugs

⚠ **FLAKE SEEN ONCE, 2026-08-04, NOT REPRODUCED — record rather than lose it.** One run of the full
suite failed `LEAK CANARY: OBJECT_COUNT returns to baseline after 3 full simulated play sessions —
baseline 2701, after 2704 (growth 3)`, with three `Stray Node (Type: Node) (Source:
res://Levels/game.gd)`. The immediately preceding and following runs both passed, and **nothing in
this stream touches `game.gd`**. It is logged because "it passed the second time" is how a real leak
gets missed; if it recurs, `game.gd`'s bare `Node` children are where to look.

No other bugs, and **no gap is open** — all four raised so far are closed.

✅ **FIXED 2026-08-04 — the circle no longer blows the card out.** It was a DOUBLE COUNT, not a
tuning value: chart H8 had the layer adding `coverage * light colour` while `QR9`=(c) has the glow
shader drawing the same circle as `MASK_DISC`. The layer's circle now contributes **coverage only**
(it punches the dim; the glow draws the light, where `circle_inner_alpha` lives). Re-rendered and
looked at: cards under circles read rank, suit pip and art square clearly. Reversible in one line —
see `ASSUMPTIONS.md`. ⚠ Still the owner's call at **G2.2**, which is unchanged.

✅ **FIXED 2026-08-04 — no visible arc where beam and circle meet** (owner: *"there is clear
semicircle where beam and circle overlap"*). It was a step between two VALUES at one boundary, not a
geometry defect: the disc punched the dim to zero while the beam beside it only reached 0.45. The
beam's COVERAGE now ramps to 1.0 at its target so the two match exactly there, its ADDED light
deliberately does not ramp (that is what washed the card out before), and `u_circle_softness` went
to 0.75 — a real pool has a penumbra, and without one the un-lit half of the circle read as a grey
disc on the background. Re-rendered and looked at: the pool melts into the beam with no edge.

✅ **FIXED 2026-08-04 — beams cut off ON the circle's far arc, covering the whole pool** (owner:
*"they reach max width at the circle then keep going for some reason. beam edges should match
circle"*, then *"Beam hard cuts into a straight line when it reaches halfway into circle instead of
covering entire circle"*). ⚠ **Two attempts ended it at `t = 1`, and `t = 1` is the circle's
CENTRE** — a straight chord through the middle of the pool. Past the centre plane the cone's
cross-section is now measured from the centre, so the circle's own far half finishes the shape;
the two are equal at `t = 1`, so the join is seamless by construction. Its mouth is DERIVED from the
circle's radius, so the two cannot disagree. Verified by cropping and magnifying the beam ends 3x,
not by eyeballing the full shot. §16's
`beam_width_at_target` is retired as a free number — its stated requirement was *"must cover the
circle"*, which makes it derived — and what survives is `flare`, extra half-width beyond the circle,
shipped at 0.

**GAP-004 is closed and folded in** (`DESIGN.md` **v9**): ONE surface, **above everything, no
exemptions**. `Q74`, `Q75` and `Q76` are withdrawn — owner: *"dim doesnt last long enough to matter
for readability, dim everything without worrying about certain visuals being exempt"*. ⚠ The reason
retires the whole question class: every exemption argued from legibility, and every duration in this
feature is a fraction of `Game.get_delay()`. **A future "should X be exempt from the dim" is already
answered: no.**

**GAP-003 is closed and folded in** (`DESIGN.md` **v8**, 2026-08-04): the glow's colour ramp is an
off-palette `Gradient`, not a `PaletteRamp`. Chart **O11** argued the opposite from a premise
`Q134`=(b), `Q135`=(b) and `Q214` had already overturned; O11, §16's knob row, §1.6 fact 3 and chart
P's `P5` are all corrected, and `PLAN.md` §1.8's row is marked known-wrong in place.
⚠ **Light is now the only thing in the game outside the palette contract.** Granted once, scoped to
the light layer, does not travel.

Two more gaps were raised during phase 1 and **both are closed and folded in**
(`DESIGN.md` **v7**, 2026-08-04):

- **GAP-001 — answered.** `blocks_spotlight()` defaults **`true`** (a covering card hides the talent
  beneath), Kuroko overrides to `false`, one opting-out modifier is enough for its whole card, and
  the seam **replaces** `is_data_topmost`. `PLAN.md` §1.4 had specified the opposite default and is
  corrected; chart A8 was right all along.
- **GAP-002 — WITHDRAWN, it was never a gap.** "Stays up for the whole act" and "moves from section
  to section" are one behaviour. The conflict existed only between two lossy restatements of
  `Q16`, whose free-text answer says both halves plainly. No code changed. `Q16` gained option
  **(c)** and now carries its note verbatim; D20 is reworded.

⚠ **The pattern behind both is worth more than either:** both were in `PLAN.md` §1, which the owner
never reviewed — the design was confirmed, the code-level contracts were written afterwards. §1 now
opens by saying the design wins outright when they disagree.

⚠ **Known design conflict, already flagged in the plan:** `Q84`=(b) puts `dim_target` on the style
resource; `Q168`=(a) calls it a player setting. The plan resolves to `Q84` as the later and more
specific answer. **If that reading is wrong, file a gap — do not split the difference.** Not reached
in phase 1 (it is a phase-2 knob).

✅ **Closed:** the stray `solatro/Cards/card_visual.tscn` modification noted on 2026-08-03 is gone —
`git status` is clean on it as of 2026-08-04. It was never this stream's.

## Files touched

**New:** `Scripts/scoring_section.gd`, `Tests/Engine/test_spotlight.gd` + `.tscn`,
`Tests/Support/spotlight_test_skill.gd`, `Tests/Support/spotlight_test_kuroko.gd`,
`design/spotlight/ASSUMPTIONS.md`, `design/spotlight/gaps/GAP-001.md` + `GAP-002.md`.
**New in S11/S12/S13:** `UI/Fx/fx_glow_style.gd`, `Shaders/glow.gdshader`,
`Shaders/light.gdshader`, `Shaders/Styles/glow_card.tres`, `glow_circle.tres`, `glow_beam.tres`,
`design/spotlight/gaps/GAP-003.md`, `GAP-004.md`.
Also edited in the v7 fold-in: `design/spotlight/DESIGN.md`, `design/spotlight/PLAN.md` (and
`PLAN.md` §0's opening prompt again on 2026-08-04, to make it stateless).

**Edited on resume 2026-08-04:** `Tests/Engine/test_spotlight.gd` (`play_card()` now attaches a
`TypePaper` — the suite-integrity fix at the head of this file).

**Edited in S11/S12/S13:** `Tests/UI/test_fx_attachment.gd`, `Tests/Visual/fx_snapshot.gd` (shots
`09_glow_falloff`, `09b_glow_over_art`, `10_light_layer`), `design/spotlight/ASSUMPTIONS.md`,
`design/spotlight/DESIGN.md` (v8) and `PLAN.md` (§0's prompt, §1.8's row).

**Edited:** `Cards/card_modifier.gd`, `Cards/card_modifier_skill.gd`, `Cards/card_modifier_status.gd`,
`Cards/Skills/Rules/zone_adder.gd`, `Cards/Skills/skill_echoing_trigger.gd`,
`Cards/Skills/skill_extra_point.gd`, `Cards/Stamps/stamp_double_trigger.gd`,
`Scripts/card_environment.gd`, `Scripts/game_data.gd`, `Levels/game.gd`, `Tests/all_tests.tscn`,
`Tests/Engine/test_{dispatch,mods,comparator,game_headless,leak_canary,patience}.gd`,
`ARCHITECTURE_REVIEW.md`, `DESIGN_DOC.md`.

⚠ **Nothing is committed** — the owner commits through GitHub Desktop.

## Next up

**Phases 1 and 2 through S13 are closed.** Next, in order:

1. **Finish S14 — chart E, the TRAVEL.** Chart I (origins) and the wire are in and asserted; what
   remains is the light EASING from one section to the next rather than cutting. `Q16`=(c)'s
   travelling light is already correct in the game state (S5) and in the light SET (the director
   replaces rather than accumulates) — this is the animation between the two positions, on
   `spotlight_travel_fraction` (§1.11, a fraction of `Game.get_delay()`, never wall-clock).
   ⚠ **SEE IT FIRST.** The wire is live now, so the honest next move is to run the game, watch a
   submit, and judge what travel is actually missing before writing an ease for it.
2. **S15 — the momentary cue's visuals.** S10 already emits `CardEnvironment.spotlight_cued(cards)`;
   this draws it, at `Q245`=(c)'s shallower dim outside scoring (`spotlight_dim_casual_scale`, which
   `LightLayer.set_lights(lights, scoring=false)` already selects).
3. ~~**Gate G2.4**~~ ✅ **PASSED 2026-08-04**, inside the wire test: `fx_intensity = 0` takes
   `u_brightness` to 0 and the dim still stands (`Q83`: *"keeps beams glow and dim"*).
4. **Gate G2.2**, the readability call — the circle at full intensity over the busiest card face the
   game can build, scenario S15 of the design's §14 list. ⚠ Expect `u_circle_intensity` (0.3) to
   come DOWN when the glow draws the disc, not up.
5. **S16** — derived row expansion (phase 3). Independent of phase 2 and unblocked throughout.
6. **G2.3, the cost number.** `fx_cost.tscn` has not been run since the glow existed. `Q254`=(a) and
   `Q255`=(d) say the number comes first and the cut is chosen after it, so **report it, do not
   pre-emptively trim** — and the glow's outline branch is an unconditional 24-segment loop per lit
   fragment, a different cost shape from fire's.

⚠ **The glow shader still has no effect class.** `FxGlowStyle.GLOW_SHADER` holds the preload as a
stopgap, the way `FxFire` holds `FIRE_SHADER`. When one is written, **MOVE** that const rather than
copying it — two preloads of one shader are two `Shader` resources, and a style applied through the
wrong one silently misses every uniform the other declares.

⚠ **Before writing any more of `PLAN.md`'s normative contracts, have the owner review them.** Both
of phase 1's gaps were contracts invented in §1 that no answer covered. All four gaps so far were
one defect — a statement written before an answer and never revisited after it (`DESIGN.md` v9's
changelog).

⚠ **`.godot/global_script_class_cache.cfg` has to be regenerated** before a new `class_name` script
resolves — `<godot> --headless --path solatro --import`. The owner's editor does this by itself; a
fresh clone, or another machine that runs the suite before opening the editor, will not.

**Opening prompt for the next agent: the fenced block in `PLAN.md` §0**, *The opening prompt for a
fresh session*. ⚠ **There is exactly one, and it is stateless** — it names no phase and no step,
because status lives here and a prompt that repeats it is wrong the moment a step lands.

## References

- `solatro/design/spotlight/PLAN.md` — the specification. §1 is normative.
- `solatro/design/spotlight/DESIGN.md` v9 — the authority on behaviour. Where the two disagree, the
  design wins and the plan is wrong.
- `solatro/design/spotlight/ASSUMPTIONS.md` — decisions taken under gap-protocol rule 1.
- `solatro/design/spotlight/gaps/` — **none open.** GAP-001, GAP-003 and GAP-004 answered and folded
  in; GAP-002 withdrawn. ⚠ All four were the SAME defect — a statement written before an answer and
  never revisited after it. See `DESIGN.md` v9's changelog.
- `solatro/design/spotlight/answers.json` — 255 answers, 0 open.
- `solatro/START_HERE.md`, `solatro/VFX.md`, `solatro/LAYERING.md`,
  `solatro/ARCHITECTURE_REVIEW.md` §4g/§4h/§4i.
