# HANDOFF — spotlight

**Goal:** ship the Spotlight mechanic and its visual effects per
`solatro/design/spotlight/PLAN.md`. Done = phases 1–4 complete with every gate passed and the owner
satisfied by eye on the visual phases. (Phase 5, the film pipeline, is a separate deliverable and is
NOT part of this stream.)

**State (2026-08-04, end of session): PHASE 1 DONE. PHASE 2 DONE EXCEPT S15. PHASE 4 (S18) DONE.**
Shipped this session: the v10–v12 doc fold-ins, **S18** the tuning tool (`@tool`, inspector-driven,
merged with the trace), **chart E's travel** completing S14, `FxSpotlightStyle` (the §16 knob resource
that had never existed), `Q85`'s art-square centring, GAP-008's fan-by-depth origin assignment, and
two new mechanical seam checks. **Remaining: S15, S16, S17, and gates G2.2 / G2.3 / G3.x.**
⚠ **The suite is green except three PIXELS checks caused by `Cards/card_visual.tscn`, which this
stream did not touch** — see the note below; `git checkout --` on that one file clears them.

**HISTORICAL STATE HEADER — PHASE 1 DONE AND GREEN, PHASE 2 THROUGH S14 EXCEPT CHART E:** S1–S10 passed
every phase-1 gate (G1.1–G1.7). S11–S13 shipped the glow style, `glow.gdshader`, `light.gdshader` and
the `LightLayer` node, each **rendered and looked at**. S14 shipped the origin allocator and the
wire; **the spotlight is now live in the running game and the owner has played it.**

## ⚠⚠ THE PATTERN BEHIND EVERY MISS ON THIS STREAM — READ THIS BEFORE WRITING ANY CODE

**Eight gaps and a dozen non-gap defects, and they are one shape: TWO REPRESENTATIONS OF ONE FACT,
WITH NOTHING THAT COMPARES THEM.** It is not "the agent did not read the design" — `Q85` and §16's
knob table were both read in-session and contradicted an hour later. **The failure is BINDING, not
reading**, and a 2400-line design re-read at session start binds nothing to the line of code written
later.

| Miss | A | B | compared by |
|---|---|---|---|
| GAP-001 | chart A8's polarity | `PLAN` §1.4's default | nothing |
| GAP-003 | chart O11's premise | `Q134`/`Q135`/`Q214` | nothing |
| GAP-004 | `Q73` dims the HUD | `Q74`–`Q76` exempt things above it | nothing |
| GAP-005 | `Q246` filters the CUE | `Q16`/chart E drive the BEAM | nothing |
| GAP-006 | `QR2`=(d) | `Q16`'s free text; `Q82` stranded by a gate | nothing |
| GAP-007 | `Q176` (form) | `Q174`/`Q175` (fidelity) | nothing |
| GAP-008 | `Q111`'s mechanism | `Q111`'s own stated rationale | nothing |
| GAP-008 again | the rule's worked EXAMPLE (one column) | the general rule | nothing |
| `Q85` | the answer | `SpotlightDirector`'s code | nothing |
| §16 knob table | the design table | the shipped properties | nothing |
| column reveal | chart D4, `Q46`, `Q52` | an invented `return -1` | nothing |
| blank PNG ×2 | exit code 0 | the pixels | nothing |
| dead cascade | a still frame | movement over time | nothing |
| tool disagreement | `--shoot-all` | `--verify` | nothing |

⚠ **A VARIANT THAT BIT TWICE: A RULE THAT ARRIVES WITH A WORKED EXAMPLE.** The example is one
representation and the general rule is another. GAP-008's fan was described for a single column; I
implemented "partition the bar by ROW", which reproduces that example exactly and is wrong for every
other shape. **The test missed it because I tested the two shapes the rule was DESCRIBED with — a
column and a row — and both readings agree on those.** Only an interleaved set separates them.
**When implementing a rule from an example, the test that matters is the case the example does not
cover**: name the readings you are choosing between, then test the input that tells them apart.

⚠ **THE PAIRS THAT SURVIVE ARE THE CROSS-KIND ONES** — a chart against an answer, a doc table against
a property list, a green banner against a frame. **Same-kind conflicts get caught** (two answers that
disagree are noticed, because one tool reads both); cross-kind ones survive indefinitely because no
single tool reads both representations, so the contradiction has nowhere to surface.

**THE RULE: when a fact gains a SECOND representation, write the comparison AT THAT MOMENT.** Better,
**delete the second one** — `circle_radius` as a `const` *and* a §16 row was two truths; one
`FxSpotlightStyle` property is one. `CardVisual.spotlight_center()` beats an offset copied into the
director.

**Seam checks that now exist, and what each caught on its FIRST run:**
- `npm --prefix designloop run check` → **`unclaimed`**: answered questions no plan step implements.
  **190 of 255 unclaimed**, `Q85` among them. Triage into `design/spotlight/implements-nothing.txt`.
- `test_the_design_16_knob_table_is_implemented()` — parses **`DESIGN.md` §16 itself** and asserts each
  row resolves to a property. **Found 13 more.** `PENDING_16` records each legitimate absence WITH the
  step that will retire it; delete an entry when that step lands and the check turns on.
- `test_light_shader_declares_every_spotlight_knob()` — the style's writes ↔ the shader's declarations.
  Godot ignores a write to an undeclared uniform in silence.
- **`Tools/spotlight_tool.tscn -- --verify`** — runs every scenario and reports what MOVED. **Found a
  thrown error on the retire beat that no still frame could show.**

⚠ **THE EVIDENCE HIERARCHY, and the last rung is new: green suite < printed counts < a rendered pixel
< movement measured over time.** `/fx-verify`'s "look at the PNG" is necessary and NOT sufficient — a
still of a working loop and a still of a dead one are identical, so a pulse, a travel, a fade or a
cascade needs an instrument that samples over time and reports what changed.

⚠ **THE LAST SESSION WAS MOSTLY BUG-FINDING, NOT STEP-SHIPPING, AND THAT IS THE HONEST SUMMARY.**
Six gaps were filed across this stream and `DESIGN.md` v9's changelog calls them one defect — *a
statement written before an answer and never revisited after it*. Three of them were found in the
last session alone, two of those by the owner playing the game. **Expect more of the same shape; do
not assume a green suite means the feature works.** The three tools that actually found things:
the **visual/event log** (`EventLog`, see below), the **engine-error check** now wired into the
suite, and the owner's eye.

✅ **TWO MECHANICAL CHECKS ADDED 2026-08-04, AND THEY EXIST BECAUSE READING THE DESIGN IS NOT A
MECHANISM.** The owner asked whether the repeated misses were a reading failure or a memory failure.
Neither: `Q85` and §16's knob table were both READ in-session and then not applied. What was missing
was anything that fails when a documented decision has no implementation.
- **`designloop check` now reports `unclaimed`** — answered questions **no plan step cites**. Every
  other check validated steps→nodes; nothing validated nodes→steps. Measured on this design:
  **255 answered, 65 claimed, 190 unclaimed**, `Q85` among them. Free-text overrides rank first.
  Triage into `design/spotlight/implements-nothing.txt` so the list converges. 152 designloop tests.
- **`test_the_design_16_knob_table_is_implemented()`** parses **`DESIGN.md` §16 itself** and asserts
  every knob resolves to a real property. It found **13 more** on its first run. `PENDING_16` carries
  each legitimate absence **with the step that will implement it** — delete the entry when that step
  lands and the check turns on for that knob. Currently `21 implemented, 13 pending`.
- Plus the reverse seam: every uniform `FxSpotlightStyle` writes must be DECLARED by
  `light.gdshader`, because Godot ignores a write to an undeclared uniform in silence.
**FX ATTACHMENT went 157 → 180 checks.**

⚠⚠ **RED SUITE RIGHT NOW, AND THE CAUSE IS `Cards/card_visual.tscn`, WHICH THIS STREAM DID NOT
TOUCH.** `PIXELS` fails 3 checks (`t=0.15/0.30/0.45: the mask and the drawn face agree in EVERY FX
cell`), reproduced on three consecutive runs. `git diff Cards/card_visual.tscn` shows the scene was
saved with **a mid-animation pose baked into `Offset/Visual`** (`position.y` −0.052 → 0.628, a new
`rotation`, `scale` 0.9999/0.9857 → 0.9947/0.9911, `skew` 0.0007 → 0.0139) and with **`Suit`, `Art`
and `Skeleton2D` set `visible = false`**.
⚠ **Both halves matter.** The baked transform offsets the DRAWN face against the rig the mask is
built from, which is exactly what PIXELS measures. The hidden nodes mean **shipped cards render with
no art square and no suit pip** — which is a gameplay-visible regression, not a test artefact.
⚠ **NOT DIAGNOSED AS INTENTIONAL AND NOT REVERTED** — it is the owner's file and the revert is theirs
to make (`git checkout -- solatro/Cards/card_visual.tscn` restores it). Everything else in the tree
is green; this is the only failure.
⚠ **THE LESSON FOR ANY AGENT RUNNING AN `@tool` SCENE: a `@tool` script that instantiates a shipped
scene can leave the editor holding it dirty.** Whether that is what happened here is unproven, but
`Tools/spotlight_tool.tscn` does instantiate `CardVisual` in the editor, so **check
`git status Cards/` after working in it.**

⚠ **A SHIPPED BUG THE TOOL FOUND IN ITS FIRST HOUR — `Q85` HAD NEVER BEEN IMPLEMENTED.** The circle
is specified *"centred on the card's ART-SQUARE centre"*; `SpotlightDirector` centred it on the card's
ORIGIN. Owner, looking at the tool: *"circles should be centered on the skill art, not on card
center"*, *"hard to tell which card circle it is on currently"*. Fixed —
**`CardVisual.spotlight_center()`** now owns the offset (`Art` sits at `(0,5)`, polygon ±16, so the
square is 32 units across, exactly `Q85`'s diameter) and both the director and the tool ask the card.
⚠ **It shipped through S13, S14, every phase-2 gate and two by-eye reviews**, because a circle on a
card's origin looks fine **until there is a second card under it**. That is the seventh instance of
the v9 pattern and the first found by LOOKING.
⚠ **The guard is stated NEGATIVELY on purpose: "no light sits on a card ORIGIN".** The natural
positive form (*every light sits on an art square*) is flaky — `PlayArea` controls are pooled, so a
`CardVisual` can be re-bound between the emit and the check, and it failed 2-of-3 against correct
code. Under the bug every centre was an origin, so the negative form is the one that fails loudly.

✅ **THE TREE IS GREEN, OBSERVED 2026-08-04 — BUT SAY HOW MANY RUNS IT TOOK.** Four full-suite runs
this session: **three green** (`1759`, `1771`, `1756` checks, `[engine-errors] clean`, SPOTLIGHT 86,
0 `SCRIPT ERROR`, errors log 0 bytes) and **one FAILED the LEAK CANARY** — see Open bugs, where the
flake is now reproduced rather than seen once. The owner has committed through `6766518 add logging`;
the v10 documentation edits and S18 are uncommitted.

**WHAT IS LEFT, IN ORDER — this is the whole remaining stream:**

0. ~~**Fold GAP-005 and GAP-006 into `DESIGN.md`/`PLAN.md`**~~ ✅ **DONE 2026-08-04.**
   ~~**S18, the tuning tool**~~ ✅ **DONE 2026-08-04, G4.1 green** — `Tools/spotlight_tool.tscn`.
   ⚠ **GAP-007 is open on its `@tool` half and needs the owner**, but the tool is usable now.

1. ⚠ **THE OWNER'S FIRST JOB IN THE TOOL** — open `Tools/spotlight_tool.tscn` in the editor and pick
   presets from the **Scenario** dropdown:
   - **S17 with `play` on** — the GAP-006 per-section pulse at un-compressed pacing. Shipped,
     mechanically correct, **untuned**: in a real act the beat is 1–3 frames. If it reads as a flash,
     the knobs are `spotlight_hold_fraction` and the two dim fractions, and
     **`spotlight_dim_target = 0` is the off switch**, which keeps every beam, circle and glow.
   - **S15** — gate **G2.2**, now judgeable for the first time because the glow is in.
   - **S2 vs S2b** — the buried row with row separation off and on; the case for S16, visible.
   - **S5 with `play` on** — the whole act's shape, and **where chart E's missing travel shows**.
2. ~~**Chart E, the travel**~~ ✅ **DONE 2026-08-04 — S14 is complete.** See Open bugs.
3. **S15 — the momentary cue's visuals.** The next step to build. `spotlight_cued` is this step's
   signal ALONE since GAP-005, so it is genuinely independent; draw it at `Q245`=(c)'s shallower dim,
   which `LightLayer.set_lights(lights, scoring=false)` already selects.
4. **S16 — derived row expansion**, then **S17** (gutters, `slot_center_global`, prop anchors).
   ⚠ **The tuning tool already SIMULATES the reveal** (`row_separation`, eased over
   `spotlight_reveal_fraction`), so the shape is decided and visible — S16 is making `PlayArea` do it
   for real. ⚠ `slot_center_global` is pure uniform-pitch math and every prop anchors to it; that is
   what S17 exists to fix, and it is the known hard part.
5. **Gate G2.2** (readability — now judgeable, the glow is in the tool), **G2.3** (the cost number,
   never measured — `Q254`=a says measure THEN cut, so report it and trim nothing pre-emptively),
   **G3.1–G3.3** (phase 3).
6. **The log-parsing subagent** — deferred by the owner until logging was final; it now is.

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

The design is confirmed (`DESIGN.md` **v10**, 255 answers, 0 open questions); `PLAN.md` is the
specification and has moved only by correction-in-place: its §0 opening prompt, §1.8's one
known-wrong row, §0b's S18 path, and the v10 fold-in below.

✅ **GAP-005 AND GAP-006 ARE NOW FOLDED IN — `DESIGN.md` v10 + `PLAN.md`'s new §1.12, 2026-08-04.**
Verified with `npm --prefix designloop run check -- solatro/spotlight`: **0 errors, 0 warnings,
0 unresolved links, dag audit 0, stale 0, 18 plan steps / 0 bad citations**, question count unchanged
at 272 live. What moved: `DESIGN.md`'s v10 changelog, chart C (C5/C16), chart D (D10, D13, the new
**D13a** fade-out, D20, the forks list), chart E's entry note, chart T (T5 + its consequences list),
`Q16`, `Q82`, `Q246`, §17.6b and §16; `PLAN.md`'s new **§1.12 the show axis**, §1.10's `u_dim` row,
§1.11's `dim_target` correction, and S10 / S13 / S14 / S15.

⚠ **THE FOLD-IN FOUND SOMETHING THAT CHANGES HOW THE GAP COUNT SHOULD BE READ: GAP-006's answer HAD
ALREADY BEEN GIVEN, IN ROUND 1, AND A GATE HID IT.** `Q82` asks exactly *"does the dim raise once per
act or per line"* and the owner answered it 2026-08-03 with an override — *"per anytime spotlight
effect is happening"*. `answers.log` **seq 269** stranded it (`active: false`) along with 19 others
when `QR2` moved to (d); §17.6's heading was later widened to `[QR2=a|c|d]` but `Q82`'s own gate stayed
`[QR2=a & QR8=a]`, so it dropped out of every later reading of the document. **The act-long dim that
shipped was chosen by nobody.** `Q82` is now gated `[QR2=a|d & QR8=a]` with an option (c) authoring the
branch. I audited the other 19: only `Q78` and `Q81` are still inactive, both genuinely moot under a
per-section pulse and neither an override — **`Q82` was the only stranded answer in the batch.**
⚠ **So this is NOT the sixth instance of the "statement written before an answer" defect, and filing
it as one is what would let it recur.** That defect is caught by re-reading; this one is invisible in
the rendered document. **The check is mechanical and nobody has run it as a habit: after any `strand`
event in `answers.log`, diff the stranded IDs against the gates that were later widened.** Both are
recorded in the log, so it is a script, not a discipline.

⚠ **`spotlight_dim_target = 0` IS THE DIM'S OFF SWITCH** (owner, 2026-08-04, anticipating that the
per-section pulse *"might flash if speed is high"*). It keeps every beam, circle and glow and drops
only the dim — the opposite split from `fx_intensity = 0`, which `Q83`/G2.4 forbid from removing the
dim. Pinned by a check in the VISUAL LAYERS wire test.

**Entry docs:** `solatro/START_HERE.md`, `solatro/VFX.md` (phases 2–4 only),
`solatro/design/spotlight/PLAN.md`, `solatro/design/spotlight/DESIGN.md`,
**`solatro/HEADLESS_TESTING.md` §0c** (the event log — read this before debugging any behaviour).

## How to verify anything here — read this before running a thing

```bash
# The suite. WINDOWED, never --headless. ~60 s, self-quits, exits with the failure count.
"<godot>_console" --path <abs path to solatro> res://Tests/all_tests.tscn
# The spotlight scenario trace. Writes logs + a PNG per transition to user://logs/events/.
"<godot>_console" --path <abs path to solatro> res://Tools/spotlight_trace.tscn
```

⚠ **ALWAYS launch with `WaitForExit(<ms>)` AND KILL ON TIMEOUT.** A parse error leaves a blank window
open forever and no in-scene watchdog can save it — the script never loads. This cost the owner real
time; they had to close windows by hand.
⚠ **`--headless --path <solatro> --import` FIRST after adding any `class_name`**, or it resolves as a
bare `Resource`/unknown identifier.
⚠ **The suite now FAILS on unexpected engine errors**, deduplicated with counts, read from
`user://logs/godot.log`. `ENGINE_ERROR_ALLOW` in `Tests/all_tests.gd` is the allowlist — **keep it
narrow**; too broad and it restores the blindness it exists to remove. It has already caught a real
parse error during this session's own work.
⚠ **The check TOTAL varies run to run** (fuzz suites). **The SUITE COUNT is the stable number: 29.**
A drop means a suite failed to LOAD while the banner still says PASSED.
⚠ **Read `summary.log` FIRST** in any `user://logs/events/<run>/` folder — a few dozen lines however
long the capture ran, and its per-event tally is often the whole diagnosis.

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
  status: done
  evidence: 'UI/spotlight_origins.gd (chart I) + UI/spotlight_director.gd (the wire) + GameView builds and binds it. SPOTLIGHT suite "S14: THE ORIGIN ALLOCATOR", 16 checks. VISUAL LAYERS test_the_spotlight_wire_lights_the_layer(): the REAL CardEnvironment cue on a REAL dealt board lights the layer, every live beam points DOWN at its target (Q117), the dim rises because something is lit (QR2=d), and retiring the set lowers it with no separate stop path. ⚠ GATE G2.4 PASSES in that test: fx_intensity 0 takes u_brightness to 0 and THE DIM STILL STANDS (Q83 "keeps beams glow and dim"). Full suite ALL 29 SUITES: 1724 CHECKS PASSED, exit 0, WINDOWED, errors log 0 bytes.'
  notes: '✅ GAP-005 RESOLVED 2026-08-04 — the wire now reads CardEnvironment.spotlight_section_changed (the scored section, unfiltered) instead of spotlight_cued. Guarded by test_the_section_signal_carries_plain_cards(). ⚠ NOT YET SEEN IN THE RUNNING GAME BY EYE — that is what S18 (the tuning tool) is being built for, at the owner''s direction. ⚠ HISTORY, KEPT BECAUSE THE FAILURE MODE RECURS: THE WIRE WAS INERT IN THE REAL GAME. The director draws CardEnvironment.spotlight_cued, which Q246=a filters to skills implementing on_spotlight, and the shipped game has exactly ONE such skill (Cards/Skills/Rules/zone_adder.gd, a rules card with no CardVisual). Ordinary board cards have no skill at all, so set_lights() never gets a non-empty set and NO beam, circle or dim has ever appeared in the running game. Every test passes because the fixture skill implements the hook. Owner report: "see zero spotlight effects". Chart E travel is parked behind it — easing between two always-empty sets is nothing. ⚠ ORIGINAL REMAINING WORK, still true: chart E (the light TRAVELLING between sections with its own easing). What is in is chart I plus the wire — the per-frame pass re-reads each lit card position, so a beam follows a card that moves (the S7 slide, a jump, a scroll), but there is no eased travel between one section and the next yet. ⚠ THE WIRE BUG WORTH KNOWING: bind() first used CardEnvironment.get_current_game(), which is null at GameView._ready because the view deliberately builds and binds its Game BEFORE adding it to the tree. Nothing connected, and every other phase-2 test stayed green while the feature did nothing — the environment is now PASSED IN. ⚠ _origins is APPEND-ONLY: indices are permanent handles, and the first build sorted the store on subdivision, which re-pointed live handles (measured: two beams sharing one origin). ⚠ Q117 lives in the allocator, not the shader — two copies could disagree invisibly.'

- id: S15
  status: pending
  evidence: ''
  notes: 'blocked by S13 and S10. GAP-005 made it genuinely independent — `spotlight_cued` is this step''s signal alone and nothing else reads it. Draw it at Q245=(c)''s shallower casual dim, which LightLayer.set_lights(lights, scoring=false) already selects.'

- id: S16
  status: pending
  evidence: ''
  notes: 'PHASE 3 — needs phase 1 green'

- id: S17
  status: pending
  evidence: ''
  notes: 'blocked by S16; carries gates G3.1, G3.2'

- id: S18
  status: done
  evidence: 'Tools/spotlight_tool.{gd,tscn} + Tools/spotlight_scenarios.json, an @tool EDITOR scene (GAP-007 resolved). GATE G4.1: "<godot> --path solatro res://Tools/spotlight_tool.tscn -- --shoot-all" -> "SPOTLIGHT TOOL: 13 preset(s) shot", 0 SCRIPT ERROR, and a per-preset "cards=N lit=M sections=K" line. RENDERED AND LOOKED AT, several: S2 vs S2b is the stacked row with the S16 reveal off and on; S15 shows the circle ON THE ART SQUARE with the card glow rimming only the active card; S12 shows Q245=(c) casual dim visibly shallower than S1. Suite after every change: ALL 29 SUITES green, VISUAL LAYERS 141 -> 144, engine stream clean, errors log 0 bytes, PALETTE warnings unchanged at 19 (res://Tools IS in SCAN_DIRS).'
  notes: '✅ GAP-007 IS RESOLVED — the owner chose a FOURTH shape none of my options offered: @tool + the inspector, with the FIDELITY answers giving way instead of the form. "Just play area simulating effects is enough, dont need full game_view with hud" / "trigger different preset scenarios using editor tool options". So Q174=(a) and Q175=(a) ARE SUPERSEDED: no Game, no GameView, no PlayArea, no HUD. Real CardVisuals on the REAL board pitch (PlayArea.slot_center_global''s own two constants), the real LightLayer, the real shader, the real SpotlightOrigins, and now the real glow. ⚠ THE STANDING LIMIT: THE CASCADE IS POSED, NOT RUN — section membership, the activation sweep and the hold beat are Game''s. A BEHAVIOUR question ("did the light travel when it should have") goes to Tools/spotlight_trace.tscn or the suite; THIS TOOL ANSWERS "DOES IT LOOK RIGHT" AND NOTHING ELSE. ⚠ Everything renders into a SubViewport, and that is not a detail: light.gdshader is screen-space, and the editor 2D view has its own pan and zoom, so a layer parented into an edited scene would slide against its cards the moment anyone scrolled. The SubViewport also IS Q177''s "dummy screen size", for free. ⚠ LightLayer GAINED @tool but its _ready() still does nothing in the editor — otherwise merely OPENING game_view.tscn would attach a ShaderMaterial to a node that scene OWNS and saving would write it in; the build moved to a public ensure_built(). ⚠ SIMULATED, AND NAMED AS SUCH: the cascade order, the mocked solo activation cue (casual: true, Q245=c), and ROW SEPARATION (the S16 reveal — PlayArea cannot do it yet, and slot_center_global is pure uniform-pitch math that a per-row expansion breaks, which is what plan step S17 has to solve). row_separation DEFAULTS ON at the owner''s direction: judging the light on a stack the reveal has not opened is judging the wrong picture. ⚠ HISTORY, kept because the failure recurs: GAP-007 WAS OPEN AND WAS THE ONE THING S18 DID NOT BUILD. Q176=(a) wants the tool @tool; Q174/Q175=(a) want a real PlayArea/CardVisual/Game. THEY CANNOT BOTH HOLD — measured: game.gd, game_view.gd, play_area.gd, light_layer.gd and spotlight_director.gd are all non-@tool (placeholder instances in the editor, every method call on one fails) and the editor instantiates no autoloads, while the director reads SettingsManager.settings.card_scale per light. Built RUNNABLE-ONLY with an IN-SCENE control panel, which serves both of Q176''s stated purposes and is strictly better here: inspector edits never reach a RUNNING scene, and tuning the GAP-006 pulse means moving a knob mid-cascade. Recommendation is option (a); if the owner picks otherwise the panel is what changes and nothing else. ⚠ THE SCENARIO LIST IS DATA (Q182) in spotlight_scenarios.json with a documented step grammar — adding a scenario needs no GDScript. ⚠ TWO TOOL DEFECTS FOUND ONLY BY LOOKING AT THE PNG, BOTH INVISIBLE TO A GREEN RUN: a Control parented straight to a CanvasLayer has no parent RECT, so PRESET_TOP_RIGHT put the whole panel off-screen; and a ScrollContainer has ZERO minimum height, so adding the scroll collapsed the panel to nothing. BOTH TIMES THE SCENARIO PLAYED GREEN AND REPORTED SUCCESS WITH NO PANEL ON SCREEN. ⚠ Capture fires 3 frames AFTER dim_rising, never on it — the event marks the START of the ease, so a shot on that frame catches the dim at 0 and reads exactly like the dim being broken. ⚠ HISTORY: PROMOTED TO THE NEXT STEP by the owner 2026-08-04: "I would rather do all testing via the planned editor so dont ask me to check until it exists." THIS IS THE PLANNED EDITOR — PLAN.md §5, the scenario player, chart N (N1-N7) and Q173-Q182, scenario list S1-S17 from DESIGN.md §14. Everything visual is gated behind it now: G2.2 (readability), the S14 travel judgement, and the first by-eye look at the beam in a real act. ⚠ PLAN.md lists it as blocked by S16 (phase 3, not started) — only scenarios that need row expansion depend on that, so build it now and mark those scenarios unavailable rather than waiting. ⚠ ITS HOME IS solatro/Tools/, NOT PLAN.md §0b''s UI/Fx/Tools/ — see the tooling note below.'
```

## Verified vs assumed

- **Verified 2026-08-04 — S18's gate G4.1, and it is the tool's own exit code:**
  ```
  <godot>_console --path solatro res://Tools/spotlight_tool.tscn -- --autoplay all
  ======== SPOTLIGHT TOOL: 11 scenario(s) played, 0 failed ========
    skipped: S2 (unavailable), S4 (unavailable), S10 (unavailable), S13 (unavailable),
             S15 (freezes by design), S16 (unavailable)
  0 `SCRIPT ERROR` on stderr
  ```
  ⚠ **`--autoplay` EXITS WITH THE FAILURE COUNT**, and `_fail()` is the single place that both reports
  and counts — an interpreter that pushed an error and still exited 0 would be the same false green
  this stream has already paid for twice.
  ⚠ **Scenarios that FREEZE are skipped and NAMED, never reported green.** S15 holds the act on one
  frame on purpose; "plays to completion" is a category error for it, and an agent must neither pass
  it nor hang on it.
- **Verified 2026-08-04 BY EYE — `01_S17_dim_rising.png`, rendered and looked at.** What the image
  actually shows, and it is the first sight of this feature at normal pacing:
  - **the dim is up and clearly readable** as a darkening of the whole board, with cards outside the
    light visibly darker than the ones inside it;
  - **three soft-edged beams descend onto the scored row**, each with visible falloff along its
    length — not flat cones;
  - **the two cards mid-jump carry bright pools** and are the brightest thing on screen;
  - **the control panel renders in full** — scenario list with S2/S4/S10 greyed, Play/Freeze/Step/
    Shoot, the viewport selector, and the live knob sliders reading their real values.
- ⚠ **STILL NOT JUDGED, AND NOT MINE TO JUDGE — whether the pulse READS as a spotlight.** I can say
  the dim rises, the beams land and the pools are bright. Whether the beat is too fast at shipped
  pacing is the owner's call in scenario S17, and it is the reason the tool exists. **Gate G2.2 is
  likewise still unjudged** — scenario S15 freezes on the pool for exactly that call.
- **Verified 2026-08-04 — the v10 fold-in parses and cites real nodes.**
  ```
  npm --prefix designloop run check -- solatro/spotlight
  questions 272 live, 1 retired · errors 0 · warnings 0 · links 0 unresolved
  dag audit 0 · stale 0 · plan 18 step(s), 0 bad citation(s), 0 uncited
  ```
  ⚠ **The first run of this after my edits had 3 ERRORS and they are worth knowing about**: a
  `⚠ **note**` appended as a trailing ` · ` segment on a question line is an **unrecognised segment**,
  and an unparsed question line does not merely lose its note — **the question vanishes from the DAG**,
  which then reported `PLAN S10 cites Q246 — no such question`. A note about a question belongs in its
  PROSE (before the first option), never after `notes`.
- **Verified 2026-08-04 AFTER the v10 fold-in — the tree is green:**
  ```
  [engine-errors] clean — 0 unexpected lines in the engine stream
  ======== ALL 29 SUITES: 1759 CHECKS PASSED [19 placeholder warnings] ========
  ============ SPOTLIGHT: ALL 86 CHECKS PASSED ============
  WINDOWED · test_output_errors.log 0 bytes · 0 `SCRIPT ERROR` lines on stderr
  ```
  Command: `"<godot>_console" --path solatro res://Tests/all_tests.tscn`, launched with
  `Start-Process -RedirectStandardOutput -RedirectStandardError` and `WaitForExit(400000)` +
  kill-on-timeout. **29 suites — the stable number.** SPOTLIGHT is 86 (76 → 83 at GAP-005 → 86 at
  GAP-006), which is the count to diff against `test_spotlight.gd`'s `check(` calls if it ever drops.
- ⚠ **ASSUMED, NOT CHECKED — `Q82`'s `active` flag in `answers.json` is still `false`.** I widened the
  gate in `DESIGN.md`; the flag is recomputed by `designloop`'s server, not by `check`, so it will
  flip the next time the questionnaire is served. The ANSWER itself is untouched and intact in
  `answers.log` seq 164 — **do not hand-edit `answers.json` to force it.**

- **Verified 2026-08-04, THE HANDOVER STATE — this is the run the next agent should reproduce:**
  ```
  [engine-errors] clean — 0 unexpected lines in the engine stream
  ======== ALL 29 SUITES: 1753 CHECKS PASSED [19 placeholder warnings] ========
  ```
  Command: `"<godot>_console" --path <abs solatro> res://Tests/all_tests.tscn`, WINDOWED, launched
  with `WaitForExit` + kill-on-timeout. ⚠ **29 SUITES is the number to check**, not 1753 — the fuzz
  suites make the check total drift run to run (1740 / 1753 / 1775 / 1779 all seen green this
  session). A suite count below 29 means one failed to LOAD while the banner still said PASSED.

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

✅ **FIXED 2026-08-04 — GAP-006: the show now PULSES PER SECTION.** Owner's spec: *"spotlight + dim
occurs as cards of section get revealed, with both spotlight and dim effect fading away as scoring
starts to happen. When next section is revealed, spotlight and dim effect are visible again, moving
to new location, then fade away again."* Visibility is now an axis SEPARATE from the light set:
`CardEnvironment.spotlight_reveal_ended` + `LightLayer._show`, which eases 0↔1 and multiplies both
the dim target and every light's intensity.
⚠ **The lights are not freed by the fade** — they survive at their positions so chart E can travel
FROM them. Freeing them would make the travel unbuildable.
⚠ **THE HOLD BEAT HAD NEVER BEEN BUILT, AND ONLY THE TRACE FOUND IT.** With the fade in, the log
showed `revealed` and `reveal_faded` on the SAME FRAME at `show=0.000` — nothing waited between them,
so the dim eased toward a target it was already leaving. Added `spotlight_hold_fraction` (chart D's
**D13**, `Q68`=a, `PLAN.md` §1.11, default 0.5), gated `if view:` so headless still waits on nothing
(`Q19`=a) and G1.7 parity holds.
⚠ **UNTUNED.** In the trace the whole cycle takes 1–3 frames (`dim_rising span=0.005s`) because
`get_delay()` is already compressed. Whether it reads as a spotlight or a flicker is a tuning
question over `spotlight_hold_fraction`, the dim fractions and `base_delay` — **which is what S18 is
for**, and the first thing to look at there.
⚠ **The origin of the miss, worth keeping:** GAP-002's v7 resolution kept *"the light travels"* and
dropped *"dims after initially showing"*, recording *"the implementation was already correct."* It
never had been. Fifth instance of the same pattern.

✅ **FIXED 2026-08-04 — CHART E, THE TRAVEL, IS BUILT. S14 IS COMPLETE.** `SpotlightDirector` now
holds `_Beam` records that OUTLIVE the section that created them, instead of rebuilding the set every
time. Per chart E and its answers: **E2/`Q61`=(a)** a card in both sections keeps its light and does
not move; leftover lights are paired to leftover targets **sorted by x** (chart E2 option A — see
GAP-008); **E3** surplus lights fade in place over `spotlight_retire_fraction`; **E4/`Q65`=(a)** a new
light fades in **already aimed**, not travelling in along its beam; **E9/`Q64`=(a)** every travelling
light moves on the same frame, smoothstepped over `spotlight_travel_fraction`; **`Q63`=(a)** full size
the whole way — the fade is the spawn/retire envelope only, never transit; **E10** the ORIGIN stays
put while the wide end tracks the circle.
⚠ **`_origins.begin()` MAY ONLY RUN WHEN NOTHING IS LIT** (`_band_ready`). It rebuilds the origin
array and clears the taken-set, so calling it per section — which the pre-travel build did — would
re-point every live beam's index at somebody else's lamp. That was harmless only because that build
also threw every light away each section.
⚠ **`retire()` now FADES rather than vanishing**, so its test asserts two things: still lit one frame
after, dark shortly after. The old one-line assertion would have passed against a snap.
Guarded by `test_the_light_travels_between_sections()` — two DISJOINT sections, then: the light COUNT
is unchanged, **no circle has snapped to its new card one frame in**, the origins have not moved, and
the lights do arrive. VISUAL LAYERS 144 → 151.

⚠ **HISTORICAL — chart E was unimplemented and the code actively contradicted it.**
`SpotlightDirector._on_section_changed()` calls `_release_all()` and rebuilds the whole set from
scratch every section, so every light dies and respawns. The brief forbids exactly that — *"no
instant movements or spawning in and out"* — and **E3** requires that a card in BOTH the old and new
set keeps its existing light without moving. This is the long-flagged remaining half of **S14**, not
a regression; it was never built. Chart E is fully specified (E1–E11 plus the E2 assignment rule,
`Q111`=a / option A: sort both by target x, which provably minimises beam crossings), so it needs no
new design — just implementation.

✅ **DIAGNOSED 2026-08-04 FROM THE VISUAL LOG — the beams are behaving correctly; the SECTIONS shrink.**
`Tools/spotlight_trace.tscn`, 3 scenarios (empty board / one shallow row / deep columns), read from
`user://logs/spotlight_trace/`. **Every section places ALL of its lights on ONE frame** — f=4 three
lights, f=29 four, f=48 two, f=51 three, all same-frame. **The light is never sequential within a
section.** What changes is section SIZE as the board empties: 3,1,1,1 then 4,2,1,3,2,1,1. A one-card
section is one beam, which is what read as *"sequential and never parallel again"*. Sections are
separated by ~19 frames of `prop_tick`, so section-to-section IS sequential — that is `Q16`=(c)'s
travelling light working as designed.
✅ **The owner's own hypothesis about the overlapping beams was RIGHT.** Column cards sit ~44 px apart
in y (measured: centres 260 / 304 / 349 at x=520) while each circle is **r=40**, so two stacked cards
in one section put two pools almost exactly on top of each other. **It resolves itself when S16 (row
expansion) lands** and stops being reproducible then — do not "fix" it in the light layer.

⚠ **STILL OPEN, LOWER PRIORITY — the light set is re-pushed EVERY FRAME.** `set_lights` appears on
essentially every frame between sections (f=30..f=47 unbroken), because `SpotlightDirector._process`
rebuilds and re-pushes the whole array to follow moving cards. Correct, but it is 2 `PackedVector4Array`
uploads per frame for a set that usually has not changed. Worth a dirty check before **G2.3**, the
cost gate.

⚠ **HISTORICAL — the owner's original report, kept because it shows how it was answered:**
Owner, watching a real act: *"at very start its parallel on all cards, but afterwards its sequential
and never parallel again, also saw case where multiple spotlights on what looks like same card, but
might be column scoring since expansion not working yet."*
**Do not guess at this.** The instrument to answer it is `Tools/spotlight_trace.tscn` + the by-frame
log — a section whose lights all land on one frame is parallel, one frame per light is sequential,
and `lights_set`'s `requested=N placed=M` says whether cards are being dropped by `_visual_of`. The
harness must place cards first (see above) before it can show any of this.
⚠ The owner's own hypothesis about the overlapping beams is plausible and cheap to confirm from the
log: a COLUMN section lights every card in that column, and with S16 (row expansion) not built those
cards are still stacked, so several beams legitimately converge on nearly one screen point.
`light_placed` records each card's `centre=(x,y)`, which settles it without anyone squinting.

✅ **FIXED 2026-08-04 — GAP-005: THE SPOTLIGHT HAD NEVER BEEN VISIBLE IN THE RUNNING GAME.**
`SpotlightDirector` listened to `spotlight_cued`, which the activation sweep filters to skills
implementing `on_spotlight` (`Q246`=a). Exactly one non-test skill does
(`Cards/Skills/Rules/zone_adder.gd`), it is a rules card, and it has no `CardVisual` — so the light
set was always empty. Ordinary numeral cards, which is what a scored row *is*, have no skill at all.
**The scoring beam had been wired to the announcement cue, and those are two different questions**
(chart T vs `Q16`=c / chart E). Owner chose option (a): `CardEnvironment.spotlight_section_changed`
now carries the scored section unfiltered, emitted from `Game._spotlight_section()` and empty from
`_release_spotlight()`; `spotlight_cued` is untouched and becomes S15's alone. See `gaps/GAP-005.md`.
⚠ **The regression guard is the point, not the fix:** `test_the_section_signal_carries_plain_cards()`
scores a column of cards carrying NO skill. **Every pre-existing spotlight test supplies a fixture
skill that implements `on_spotlight`, which is exactly why none of them could see this** — the same
shape as S14's `bind()` bug. A test whose cards all have skills cannot detect a filter on skills.

✅ **FIXED 2026-08-04 — `game_view.tscn` was completely white in the editor.** `LightLayer` is a
`ColorRect`, whose `color` defaults to **opaque white**, and `light_layer.gd` is deliberately not
`@tool` (`PLAN.md` §1.8 — `@tool` silently drops properties). So in the editor `_ready()` never runs,
no shader material is assigned, and a full-rect white quad covers the scene. The scene now carries
`color = Color(0, 0, 0, 0)`; `test_palette.gd`'s `ALLOW_LINES` carries that exact fragment, because a
fully transparent colour is not a colour choice — placeholder warnings stay at 19.
⚠ **The old comment in `light_layer.gd` argued FOR leaving `color` unset** (the shader writes `COLOR`
outright, so at runtime it is inert). That reasoning was correct about runtime and blind to every
context where the shader is not running. It is corrected in place.

✅ **FIXED 2026-08-04 — the `_on_screen()` error flood during act submit** (owner: *"a ton of
duplicate errors ... `Condition "!is_inside_tree()" is true`"*). `PropVisual._ready()` builds its half
attachments onto the `_PropHalf` nodes from `ensure_back()` / `ensure_front()`, and those are
**deliberately orphans at that moment** — `PropLayer` parents them to `CardLayer`, not to the prop.
The first `sync()` therefore reached `_on_screen()` outside the tree and `get_viewport_rect()` raised,
once per split-capable prop per act. `fx_attachment.gd:981` now answers `false` for a node outside the
tree, which is the true answer rather than a workaround, and it is self-healing: uploads resume on the
frame the half is parented, by the same mechanism that handles a host scrolling back into view.
⚠ Verified: `SCRIPT ERROR` count on stderr is **0** across a full suite run, `is_inside_tree` hits 0.

⚠ **OPEN, LOW PRIORITY, AND THE GATE STRUCTURALLY CANNOT SEE IT — a leaked GLES3 texture at exit.**
The 2026-08-04 fold-in run ends with, AFTER the green banner:
```
ERROR: 1 RID allocations of type 'N5GLES37TextureE' were leaked at exit.
```
⚠ **`_scan_engine_errors` reads `user://logs/godot.log` DURING the run, and this line is printed by the
engine at SHUTDOWN — so every exit-time error is invisible to the gate by construction**, and
`[engine-errors] clean` on the same run is not a contradiction. That blind spot is worth more
attention than the one texture: **anything the engine reports at exit passes the suite silently.**
⚠ **Cause unknown and I did not establish whether it is new.** Do not assume it is this stream's —
but the obvious suspect is the glow's baked `GradientTexture1D` (GAP-003), which is the one texture
this stream created and which `FxGlowStyle` holds through a preload. **The honest state is: seen once,
observed, unattributed.** Cheapest next step is to diff a run of the tree before S11 against one after.

⚠ **OPEN — THE LEAK CANARY FLAKE IS NOW REPRODUCED. ~1 RUN IN 4, AND THE SIGNATURE MOVES.**
- **2026-08-04, run A:** `baseline 2701, after 2704 (growth 3)`, three `Stray Node (Type: Node)
  (Source: res://Levels/game.gd)`.
- **2026-08-04, run B (after S18):** `baseline 2560, after 2562 (growth 2)`, and the strays are
  **different** — `/Fx (Type: Node2D) (Source: res://UI/Fx/fx_attachment.gd)` plus three anonymous
  `Node`s with no source at all.
- **Three further runs the same day passed** (`1771`, `1756`, and the earlier `1759`).
⚠ **NOT ATTRIBUTABLE TO S18** — the tool is not loaded by the suite; `test_palette.gd` reads
`res://Tools` as TEXT and instantiates nothing. But **"it passed the second time" is exactly how a
real leak gets missed**, and this has now failed twice with two different sources, which is weaker
evidence for a flaky test and stronger evidence for a real intermittent leak.
⚠ **The next agent should not spend the session on it, and should not report a green suite without
saying how many runs it took.** If it is picked up: the two signatures share nothing except that both
are nodes whose parent died first, and `fx_attachment.gd`'s `/Fx` child is the half-attachment
orphan that the `_on_screen` tree guard was about — that is where I would look first.

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

**New on 2026-08-04 (the logging + tooling session):** `Scripts/event_log.gd` (`EventLog`),
`Tools/spotlight_trace.{gd,tscn}`, `design/spotlight/gaps/GAP-005.md`, `GAP-006.md`.
**Moved:** `tools/*.py` → `Tools/*.py` (case rename, STAGED — see the tooling section),
`Cards/Props/Tools/formation_editor.*` and `UI/Fx/Tools/fx_editor.*` → `Tools/`.
**Edited on 2026-08-04:** `Tests/Engine/test_spotlight.gd` (the `TypePaper` suite-integrity fix, the
GAP-005 guard, the GAP-006 guard), `Tests/all_tests.gd` (the engine-error scan),
`Tests/Support/test_log.gd` (`logs/test/`), `Tests/Engine/test_game_headless.gd` (the debug-history
test), `Tests/Engine/test_palette.gd` (ALLOW_LINES + `res://Tools` in SCAN_DIRS),
`Tests/UI/test_visual_layers.gd` (the section-signal wire + the dim off switch),
`Scripts/card_environment.gd` (two new signals), `Scripts/player_settings.gd`
(`spotlight_hold_fraction`), `Levels/game.gd` (the signals, the hold beat, the debug history, the
data-channel instrumentation), `Levels/game_view.gd` (the debug bar), `Levels/game_view.tscn`
(`LightLayer` transparent), `UI/light_layer.gd` (`_show`), `UI/spotlight_director.gd`,
`UI/play_area.gd`, `UI/prop_layer.gd`, `UI/Fx/fx_attachment.gd` (`_on_screen` tree guard),
`Cards/card_data.gd` (`log_str()`), `Locale/localization.csv`, `HEADLESS_TESTING.md`, `VFX.md`.

**Edited in S11/S12/S13:** `Tests/UI/test_fx_attachment.gd`, `Tests/Visual/fx_snapshot.gd` (shots
`09_glow_falloff`, `09b_glow_over_art`, `10_light_layer`), `design/spotlight/ASSUMPTIONS.md`,
`design/spotlight/DESIGN.md` (v8) and `PLAN.md` (§0's prompt, §1.8's row).

**Edited:** `Cards/card_modifier.gd`, `Cards/card_modifier_skill.gd`, `Cards/card_modifier_status.gd`,
`Cards/Skills/Rules/zone_adder.gd`, `Cards/Skills/skill_echoing_trigger.gd`,
`Cards/Skills/skill_extra_point.gd`, `Cards/Stamps/stamp_double_trigger.gd`,
`Scripts/card_environment.gd`, `Scripts/game_data.gd`, `Levels/game.gd`, `Tests/all_tests.tscn`,
`Tests/Engine/test_{dispatch,mods,comparator,game_headless,leak_canary,patience}.gd`,
`ARCHITECTURE_REVIEW.md`, `DESIGN_DOC.md`.

**New 2026-08-04 (S18, the style resource, chart E):** `Tools/spotlight_tool.{gd,tscn}`,
`Tools/spotlight_scenarios.json`, `UI/Fx/fx_spotlight_style.gd`,
`Shaders/Styles/spotlight_default.tres`, `design/spotlight/gaps/GAP-007.md`, `GAP-008.md`.
**Deleted:** `Tools/spotlight_trace.{gd,tscn,gd.uid}` — merged into the tool as `-- --trace`.
**Also edited outside solatro:** `designloop/src/gaps.mjs` + `src/check.mjs` (the `unclaimed`
inverse-citation report) and `designloop/test/gaps.test.mjs` (152 tests green).
**Shipped code edited by S18 — NOT just tool files, read this before assuming the tool is isolated:**
`Cards/card_visual.gd` (new `spotlight_center()`, the `Q85` fix), `UI/spotlight_director.gd` (calls
it, twice — the initial place and the per-frame re-read), `UI/light_layer.gd` (`@tool`, `_ready()`
inert in the editor, the build split into `ensure_built()`, public static `editor_settings`),
`Tests/UI/test_visual_layers.gd` (the `Q85` guard, +3 checks).
**Still owed on the glow:** `FxGlowStyle.GLOW_SHADER` is a stopgap preload and there is no `FxGlow`
effect class. The tool builds the request directly. ⚠ **When a class is written, MOVE the tool's call
site to it rather than copying** — two preloads of one shader are two `Shader` resources, and a style
applied through the wrong one silently misses every uniform the other declares.

**Edited 2026-08-04 (the v10 fold-in session — DOCUMENTATION ONLY, no code touched):**
`design/spotlight/DESIGN.md` (v10), `design/spotlight/PLAN.md` (new §1.12 + corrections in place),
`design/spotlight/gaps/GAP-005.md`, `GAP-006.md`, and this file.

⚠ **NOT THIS STREAM'S, AND AN OWNER DECISION: two tracked `~`-prefixed DLLs show as DELETED** —
`addons/big_number/bin/windows/~big_number.windows.template_debug.x86_64.single.dll` and
`addons/worldgen/bin/~worldgen_native.windows.template_debug.x86_64.dll`. These are Godot's
lock-rename artefacts: when a GDExtension `.dll` is replaced while the editor holds it open, the old
one is renamed with a `~` prefix. **They were committed by accident and the deletion is almost
certainly the right end state — they probably belong in `.gitignore`, not in the tree.** No agent
should restore or stage either without the owner saying so. Untouched by any spotlight work.

⚠ **Everything up to `6766518 add logging` IS committed** — `git status` was clean at the start of
the 2026-08-04 fold-in session, so the "nothing is committed" note above is historical. The doc edits
listed immediately above are uncommitted. The owner commits through GitHub Desktop; do not `git add`.

## The visual-layer log — started 2026-08-04, PARTLY DONE

Owner: *"emit some sort of logs for you to read of literally every single thing that happens on
visual layer and their timestamp ... The logging system sounds very valuable for testing purposes."*

⚠ **SCOPE, owner 2026-08-04: *"visual log should track literally everything visible on visual layer,
not just spotlight."*** Started — `board`, `prop` and `score` channels are wired at their main seams
(`PlayArea.flush_rebuild` / `popup_score`, `PropLayer.begin_prop_tick` / `_free_visual`). **Not yet
complete**: card visual moves/flips/pose, status layer, focus inspector, hover, gutter labels, the
end-screen overlays. Each is a one-line `VisualLog.event(...)` at the seam; the pattern is set.

**Size discipline is BUILT IN, because the owner asked for it** (*"Make sure log size is not massive
before you read it"*): `max_events = 20000` stops recording with a `push_warning` rather than growing
without bound (it does NOT ring-buffer — the start of a capture is the part that explains what
happened), and **`VisualLog.summary()` is a few dozen lines however long the run was**. Read the
summary FIRST, every time. Its per-event tally is frequently the whole diagnosis: `score_line 12`
against `lights_set 4` says eight sections lit nothing, found without opening the event list.

**Docs updated** so this is discoverable rather than folklore: `HEADLESS_TESTING.md` **§0c** (the full
how-to, and why `f=` beats `t=`) and `VFX.md`'s instrument table.

**Shipped and green:**
- `Scripts/visual_log.gd` (`VisualLog`) — static, off by default, free when off. Channels
  (`spotlight`/`light`/`board`/`prop`/`score`/`act`), `dump()`, `dump_by_frame()`, `filter()`,
  `save()`. Typed `VisualLog.Event`, **not** a `Dictionary` — warnings-as-errors rejects every
  `Variant` read out of one, so `int(e["f"])` does not compile.
- Instrumented: `SpotlightDirector` (`section_changed`, `light_placed` per card with its origin
  index, `lights_set` with **requested vs placed**, `retire`), `LightLayer` (`set_lights` as a
  `was -> now` TRANSITION, `dim_rising`, `dim_settled`), `Game.score_line` (`score_line` with
  row/col + index + card count, the spine everything else is read against).
- `Tools/spotlight_trace.{gd,tscn}` — real `GameView`, real seeded deck, no mocks; writes
  `visual_log.log`, `visual_log_by_frame.log` and a PNG per transition to **`user://logs/`**.

⚠ **FRAME NUMBER IS THE ORDERING TRUTH, NOT THE TIMESTAMP** — and this corrects the assumption the
feature was requested under. A wall-clock delta is ambiguous (0.3 ms apart is either one frame's work
or two frames at 3000 fps), and under the act speed-up that ambiguity is the normal case.
`Engine.get_process_frames()` is exact, is what the player perceives (same frame = one moment on
screen), **and is frame-accurate headless**, where wall-clock means nothing. So the worry that this
would not survive headless resolves the opposite way: the frame column always works, the microsecond
column is the one to distrust. Read `f=` first. `dump_by_frame()` exists for exactly this question.

✅ **FIXED — `spotlight_trace` places cards.** `_place_hand(count, per_col)` moves real hand cards to
real column ends through `Game.move_data_to_coord`, and scenario 1 remaining an EMPTY board is
deliberate (submit fires regardless of what is on the board, so "an act that scores nothing must
light nothing" is a case to prove, not a blocker). This note previously said the harness was unable
to place cards; that stopped being true in the same session and the note went stale.
⚠ **`spotlight_trace` IS NOW THE LESSER OF TWO HARNESSES.** `Tools/spotlight_tool.tscn` (S18) does
everything it does plus a scenario selector, freeze/step, viewport control, live knobs and an
`--autoplay` gate. **The trace is kept because it is the ZERO-UI instrument** — nothing on screen but
the board, so a capture from it has no panel in the way. Reach for the tool first.

## Logging work — what is DONE

✅ **`VisualLog` → `EventLog`, one timeline, two channel GROUPS.** `GROUP_VISUAL`
(`spotlight`/`light`/`board`/`prop`/`score`) and `GROUP_DATA` (`act`/`move`/`mod`/`state`/`input`),
the latter firing headless. New data instrumentation: `Game.move_stack` (**logged for rejections
too** — a refused move leaves no other trace, so "the card didn't go where I dragged it" is otherwise
invisible), `Game._note_mod_fired` (**every** dispatch path funnels through it, so it is the one
place that sees the whole firing order), and `try_place`/`submit`/`next`/`undo` on `input`.
⚠ **The `input` channel is what makes a playtest log reproducible** — everything else is consequence;
those are cause. ⚠ Logs moved to **`logs/events/`**, not `logs/visual/`: the log covers the data layer
too, and naming the folder after one of its two groups would mislead exactly the way
`logs/spotlight_trace/` did. Verified: a trace run populates both groups (`mod_fired` 96,
`move_stack` 10, `submit` 3 alongside the visual channels).

✅ **The record switch + 3 debug buttons** (`GameView._build_debug_bar`, debug builds only):
`Rec` toggles a capture and writes it on stop with the folder printed, `<< Undo` is an **uncapped**
rewind, `Redo >>` steps forward. Serves the owner's loop verbatim — *undo past the bug, record,
repeat the action, send the log*.
⚠ **`Game._debug_history` is a SECOND history, not a bigger `undo_cap`.** The production cap is a
design decision about how far a PLAYER may rewind; raising it to serve debugging would change the
game to serve the tool. The two histories can disagree, and that is correct.
⚠ **It cannot recover snapshots the production cap already trimmed before the run resumed** — it is
seeded from `save_history` and uncapped *from there on*, which is the honest promise.
**Guarded by `test_debug_history_is_uncapped_and_redoable()`**, which commits 8 actions against a cap
of 3 — *a test committing fewer actions than the cap would pass identically with the feature
deleted*. 5 checks green, including that a fresh commit invalidates the redo future.

✅ **The suite FAILS on unexpected engine errors** (`Tests/all_tests.gd::_scan_engine_errors`).
GDScript cannot hook the error stream, so it reads **`user://logs/godot.log`** — the engine mirrors
stderr there and `godot.log` is the current run, older sessions rotated to timestamped siblings.
Unexpected lines are printed **deduplicated with counts** (the flood that prompted this was one bug
repeated thousands of times) and added to the failure count. A clean run prints one line and nothing
else, per *"include stream in output basically only if error"*.
⚠ **`ENGINE_ERROR_ALLOW` is the whole design risk** — too broad and it restores the blindness it
exists to remove. Verified 2026-08-04 that it is not vacuous: the run carried **3** engine ERROR
lines and all 3 matched the allowlist (2 deliberate `Palette index` clamps, 1 `LeakSentinel`), so the
scanner is demonstrably reading the stream rather than always saying "clean".
✅ **`CardData.log_str()`** — `Hoop NumeralRank1.0 Extra Point  PLAY PLAY` → `Ho1*+`.
⚠ **A SECOND METHOD, NOT AN EDIT TO `_to_string()`** — the verbose form feeds test assertions and the
**G1.7 headless-parity diff**, which compares whole log sections between runs; shortening it would
change what that gate compares without anyone noticing.
✅ **Two log roots** — `logs/test/` (`TestLog`) and `logs/visual/<run>/` (`VisualLog`, which now owns
its own path so a harness cannot claim it). Each run writes `summary.log` first.
✅ **`spotlight_trace` self-closes** — on-screen status label, plus a `_Watchdog` node that quits even
if a scenario wedges. ⚠ **Neither saves a PARSE ERROR**, which is what the owner actually hit: the
script never loads, so nothing runs to quit it. **Always launch with `WaitForExit(<timeout>)` and
kill the process if it outlives it** — a harness cannot rescue itself from failing to compile.

## Still owed to the owner (asked 2026-08-04, NOT yet built)

1. **The log-parsing subagent — EXPLICITLY DEFERRED by the owner until logging is finalized**, and
   scoped: *"should only be used for massive logs such as recording an entire playthrough from start
   to lose/win."* Not for ordinary captures, which `summary.log` already handles. **This is now the
   only outstanding item**, and logging IS finalized, so it is unblocked.
2. ~~`VisualLog` → `EventLog` with channel groups~~ ✅ **DONE.**
3. ~~The playtest RECORD switch + 3 debug buttons~~ ✅ **DONE.**
4. ~~**The suite must FAIL on unexpected engine errors.**~~ ✅ **DONE.**
   Reasoning kept: **this was the root cause of two false greens this session.** *"suite should fail on unexpected errors in
   error stream so visible to an agent testing to immediately fix, instead of current behavior where
   I have to copy paste it to agent. suite tests should include stream in output basically only if
   error."* ⚠ **This is the root cause of two false greens already this session** — the aborted
   `is_spotlit` tests and the `_on_screen` flood. `test_output_errors.log` is the harness's OWN
   channel (`TestLog` writes only `check()` FAIL lines); nothing reads stderr and no check asserts on
   it. Needs an ALLOWLIST: `test_palette.gd` and `test_leak_canary.gd` push errors deliberately.
2. **Compact log lines.** *"Logs should be as compact as possible, current card data to_str may need
   changes."* `CardData._to_string()` currently yields e.g. `Input Zone ZONE PLAY` — verbose and it
   repeats the stage twice. A short stable card id is wanted.
3. **Owner-driven playtests hand logs to the agent.** *"I want to be able to playtest myself, then
   hand off logs as evidence to agent to parse along with any issues I found."* ⚠ Implication:
   `VisualLog` must be switchable ON IN THE REAL GAME (a setting or a launch flag), not only inside
   `spotlight_trace`. Not wired yet.
4. **A subagent that parses the logs.** *"likely need subagent to parse logs every time to find the
   issues."* Suggests a `.claude/agents/log-parser.md` reading `user://logs/`.

## Tooling consolidation — done 2026-08-04, owner's direction

**Every parameter-tuning tool now lives in `solatro/Tools/`**, flat, one folder (owner: *"have every
single editor/tool for modifying parameters scene in one easy to find folder"*).

| Was | Now |
|---|---|
| `Cards/Props/Tools/formation_editor.{gd,tscn}` | `Tools/formation_editor.{gd,tscn}` |
| `UI/Fx/Tools/fx_editor.{gd,tscn}` | `Tools/fx_editor.{gd,tscn}` |
| `tools/*.py` (lowercase) | `Tools/*.py` |

⚠ **The Python scripts are FLAT in `Tools/`, not in a `Tools/Scripts/` subfolder, and that is not a
style choice** — `make_fx_noise.py` and `palette_conformance.py` resolve their assets with
`Path(__file__).resolve().parent.parent / "Assets"`, so one extra directory level silently points
them at `solatro/Tools/Assets`, which does not exist. Nesting them broke both; flattening fixed it.
⚠ **`res://Tools` was added to `test_palette.gd`'s `SCAN_DIRS`.** The editors used to be scanned only
as a side effect of sitting under `res://Cards` and `res://UI`; moving them out would have dropped
them from the palette drift scan with no visible sign. Placeholder warnings stayed at 19 after the
move, which is the evidence that `fx_editor` carries no drift of its own.
⚠ **`tools` → `Tools` is a CASE-ONLY rename, and on Windows git cannot record it from the working
tree alone** — it required `git mv`, which stages. That is the one staged change in the tree and the
one deliberate exception to the no-staging rule; everything else is unstaged as usual. If it is
unstaged, the rename silently reverts to a no-op and the folder stays lowercase on any case-sensitive
machine.
⚠ **`PLAN.md` §0b's S18 row said `UI/Fx/Tools/`** and now says `Tools/`. That is the owner's
direction overriding the plan's path — recorded here rather than treated as plan drift.

## Opening prompt for the next agent

Copy-paste this. It stands alone.

> Read `solatro/HANDOFF_spotlight.md` top to bottom, then `solatro/design/spotlight/PLAN.md` §0's
> opening prompt, then `solatro/HEADLESS_TESTING.md` §0c. Confirm the tree is green before trusting
> any status in the handoff: run the suite WINDOWED with a kill-on-timeout, check the SUITE count is
> 29 (not the check total, which varies), and check `[engine-errors] clean`.
>
> **DONE, DO NOT REDO:** the v10–v12 doc fold-ins; **S18** the tuning tool
> (`Tools/spotlight_tool.tscn`, `@tool` + inspector, with the old `spotlight_trace` merged in as
> `-- --trace`); **S14 including chart E's travel**; `FxSpotlightStyle`; `Q85`'s art-square centring;
> GAP-008's fan-by-depth origins. **GAP-007 and GAP-008 are both RESOLVED.**
>
> ⚠ **Read the handoff's "THE PATTERN BEHIND EVERY MISS" table before writing code.** Every defect on
> this stream is two representations of one fact with nothing comparing them. Run
> `npm --prefix designloop run check -- solatro/spotlight` and look at `unclaimed` before
> implementing a step; run `Tools/spotlight_tool.tscn -- --verify` for anything with a duration.
>
> ⚠ **The next step is S15** (the momentary cue's visuals), then S16 and S17. Ask the owner to run
> the tool's S17 preset with `play` on before any further tuning — the GAP-006 pulse is shipped,
> mechanically correct and UNTUNED, and their judgement of it is the input the look depends on.
> ⚠ **The suite has three PIXELS failures caused by `Cards/card_visual.tscn`, which this stream never
> touched** — a mid-animation pose baked into `Offset/Visual`. `git checkout --` on that one file
> clears them. Do not "fix" it in the FX code.
>
> ~~Build **S18, the scenario player**~~ (`PLAN.md` §5, chart N, `Q173`–`Q182`, scenario list S1–S17
> from `DESIGN.md` §14). Everything visual is gated behind it — the owner will not judge visuals any
> other way. Its first job is tuning the GAP-006 per-section pulse, which is shipped but untuned and
> may read as a flash at speed; `spotlight_dim_target = 0` is the off switch if it does.
>
> ⚠ Do not `git add` or commit. ⚠ Do not run Godot while the owner's editor is open. ⚠ When a
> decision the design does not cover appears, file a gap — six have been filed on this stream and
> every one was the same defect, a statement written before an answer and never revisited after it.

## Next up

⚠ **THE ORDER CHANGED 2026-08-04.** The owner will not judge anything by eye until the tuning tool
exists — *"I would rather do all testing via the planned editor so dont ask me to check until it
exists"* — so **S18 comes before every remaining visual step**, and asking them to run the game or
look at a snapshot is not an available move until it ships.

0. **S18 — the scenario player** (`PLAN.md` §5, chart N, `Q173`–`Q182`). Real `PlayArea`, real
   `CardVisual`s, real headless `Game` on a fixed deck — no mocks (`Q174`=a, `Q175`=a). `@tool` AND
   runnable (`Q176`=a), viewport-size control (`Q177`=a), step (`Q178`=a), freeze (`Q179`=a), every
   §16 tunable live and POLLED (a custom resource does not announce its own edits — `fx_editor`
   already does this and is the model to copy). ⚠ **Scenario list is DATA, not code** (`Q182`: the
   list is itself still reviewable). Lands in `solatro/Tools/`. Gate **G4.1**.
   ⚠ Scenarios needing S16 (row expansion) cannot play yet — mark them unavailable, do not wait.

Then, in order:

1. **Finish S14 — chart E, the TRAVEL.** Chart I (origins) and the wire are in and asserted; what
   remains is the light EASING from one section to the next rather than cutting. `Q16`=(c)'s
   travelling light is already correct in the game state (S5) and in the light SET (the director
   replaces rather than accumulates) — this is the animation between the two positions, on
   `spotlight_travel_fraction` (§1.11, a fraction of `Game.get_delay()`, never wall-clock).
   ⚠ **SEE IT FIRST — IN S18**, now that the wire genuinely lights the layer (GAP-005). Judge what
   travel is actually missing before writing an ease for it.
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
- `solatro/design/spotlight/DESIGN.md` **v10** — the authority on behaviour. Where the two disagree,
  the design wins and the plan is wrong.
- `solatro/design/spotlight/ASSUMPTIONS.md` — decisions taken under gap-protocol rule 1.
- `solatro/design/spotlight/gaps/` — ⚠ **GAP-007 IS OPEN** (S18's `@tool` half: `Q176`=(a) against
  `Q174`/`Q175`=(a), a measured contradiction — recommendation option (a), runnable-only with the
  in-scene panel that is already built). GAP-001, GAP-003, GAP-004, GAP-005 and GAP-006
  answered, implemented and folded in; GAP-002 withdrawn. ⚠ **Five of them were one defect** — a
  statement written before an answer and never revisited after it (`DESIGN.md` v9's changelog).
  **GAP-006 is a second, different defect and the v10 changelog separates them**: an answer
  *deactivated by a gate* and never re-activated when the gate's premise widened. Re-reading catches
  the first; only a diff of `answers.log`'s `strand` events against later gate widenings catches the
  second.
- `solatro/design/spotlight/answers.json` — 255 answers, 0 open.
- `solatro/START_HERE.md`, `solatro/VFX.md`, `solatro/LAYERING.md`,
  `solatro/ARCHITECTURE_REVIEW.md` §4g/§4h/§4i.
