# HANDOFF — spotlight

**Goal:** ship the Spotlight mechanic and its visual effects per
`solatro/design/spotlight/PLAN.md`. Done = phases 1–4 complete with every gate passed and the owner
satisfied by eye on the visual phases. (Phase 5, the film pipeline, is a separate deliverable and is
NOT part of this stream.)

**State: PHASE 1 IS DONE AND GREEN (2026-08-04).** S1–S10 all landed and every phase-1 gate
(G1.1–G1.7) passes. Phase 2 (S11–S15, the shader and the light layer) is next and needs the owner's
eye at every step — it must not be attempted blind. The design is confirmed (`DESIGN.md` version 6,
2026-08-03, 255 answers, 0 open questions); `PLAN.md` is the specification and has not moved.

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
  evidence: 'CardModifier.blocks_spotlight() + _blocked_from_above() + _card_blocks(); SPOTLIGHT section "S3: THE BLOCK SEAM", 8 checks green (default blocks, headers follow their column, Kuroko unhides, Revealing survives being buried two deep, forced bypasses).'
  notes: 'GAP-001 answered by the owner 2026-08-04, implemented, and FOLDED IN (DESIGN.md v7 + PLAN.md §1.4 corrected): blocks_spotlight() defaults TRUE (a covering card hides the talent beneath), a Kuroko modifier overrides to false and unhides it, one opting-out modifier is enough for its card, Revealing is a property of the card itself. The seam REPLACES is_data_topmost, behaviour-neutral.'

- id: S4
  status: done
  evidence: 'GameData.forced_spotlight; SPOTLIGHT section "S4", 5 checks green. G1.5 asserted by test_forced_spotlight_never_bumps_revision().'
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
  status: pending
  evidence: ''
  notes: 'PHASE 2 — needs phase 1 green'

- id: S12
  status: pending
  evidence: ''
  notes: 'blocked by S11 — declare u_brightness or fx_intensity misses it'

- id: S13
  status: pending
  evidence: ''
  notes: 'blocked by S12; carries gate G2.4'

- id: S14
  status: pending
  evidence: ''
  notes: 'blocked by S13'

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

None, and no gap is open. Two were raised during phase 1 and **both are closed and folded in**
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
Also edited in the v7 fold-in: `design/spotlight/DESIGN.md`, `design/spotlight/PLAN.md`.

**Edited:** `Cards/card_modifier.gd`, `Cards/card_modifier_skill.gd`, `Cards/card_modifier_status.gd`,
`Cards/Skills/Rules/zone_adder.gd`, `Cards/Skills/skill_echoing_trigger.gd`,
`Cards/Skills/skill_extra_point.gd`, `Cards/Stamps/stamp_double_trigger.gd`,
`Scripts/card_environment.gd`, `Scripts/game_data.gd`, `Levels/game.gd`, `Tests/all_tests.tscn`,
`Tests/Engine/test_{dispatch,mods,comparator,game_headless,leak_canary,patience}.gd`,
`ARCHITECTURE_REVIEW.md`, `DESIGN_DOC.md`.

⚠ **Nothing is committed** — the owner commits through GitHub Desktop.

## Next up

**Phase 1 is closed**, and both gaps are folded in. Next:

1. **S11** — `FxGlowStyle` + three `.tres`. Phase 2 needs the owner's eye at every step
   (`PLAN.md` §3, gates G2.1–G2.4).
2. **S16** — derived row expansion (phase 3) is independent of phase 2 and is also unblocked.

⚠ **Before writing any more of `PLAN.md`'s normative contracts, have the owner review them.** Both
of phase 1's gaps were contracts invented in §1 that no answer covered — a default value, and a
four-word compression of a free-text answer. Neither was in the confirmed design.

⚠ **`.godot/global_script_class_cache.cfg` had to be regenerated** before the new `class_name`
scripts resolved — `<godot> --headless --path solatro --import`. The owner's editor does this by
itself; a fresh clone, or another machine that runs the suite before opening the editor, will not.

Opening prompt for the next agent: the fenced block in `PLAN.md` §0, *The opening prompt for a
fresh session*. Or, to resume mid-stream:

```
Resume solatro/HANDOFF_spotlight.md. Read it and solatro/design/spotlight/PLAN.md first;
they are self-contained. Continue from the first pending task. Phase 2 (S11-S15) needs the
owner's eye — verify by rendering and LOOKING, never from metrics. Follow the gap protocol
at the head of PLAN.md. No git add, no commits. Never run Godot while the owner's editor
is open.
```

## References

- `solatro/design/spotlight/PLAN.md` — the specification. §1 is normative.
- `solatro/design/spotlight/DESIGN.md` v6 — the authority on behaviour. Where the two disagree, the
  design wins and the plan is wrong.
- `solatro/design/spotlight/ASSUMPTIONS.md` — decisions taken under gap-protocol rule 1.
- `solatro/design/spotlight/gaps/` — GAP-001 is open.
- `solatro/design/spotlight/answers.json` — 255 answers, 0 open.
- `solatro/START_HERE.md`, `solatro/VFX.md`, `solatro/LAYERING.md`,
  `solatro/ARCHITECTURE_REVIEW.md` §4g/§4h/§4i.
