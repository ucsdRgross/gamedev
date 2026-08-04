# HANDOFF — spotlight

**Goal:** ship the Spotlight mechanic and its visual effects per
`solatro/design/spotlight/PLAN.md`. Done = phases 1–4 complete with every gate passed and the owner
satisfied by eye on the visual phases. (Phase 5, the film pipeline, is a separate deliverable and is
NOT part of this stream.)

**State:** nothing implemented yet. The design is confirmed (`DESIGN.md` version 6, 2026-08-03, 255
answers, 0 open questions) and `PLAN.md` is written and verified — 18 steps, every one citing the
design nodes it implements. **Start at S2, the rename**: it is mechanical only while nothing new
depends on the old names.

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
  status: pending
  evidence: ''
  notes: 'no dependency; can go either side of S2'

- id: S2
  status: pending
  evidence: ''
  notes: 'DO THIS FIRST — mechanical only while nothing new depends on the old names. Carries gate G1.3, the save migration.'

- id: S3
  status: pending
  evidence: ''
  notes: 'blocked by S2'

- id: S4
  status: pending
  evidence: ''
  notes: 'blocked by S2; carries gate G1.5'

- id: S5
  status: pending
  evidence: ''
  notes: 'blocked by S1, S2, S4; carries gate G1.4'

- id: S6
  status: pending
  evidence: ''
  notes: 'blocked by S5'

- id: S7
  status: pending
  evidence: ''
  notes: 'blocked by S6. THE ONLY STEP THAT CAN HANG — gate G1.6 needs a bounded watchdog.'

- id: S8
  status: pending
  evidence: ''
  notes: 'blocked by S5'

- id: S9
  status: pending
  evidence: ''
  notes: 'blocked by S5; carries gate G1.7'

- id: S10
  status: pending
  evidence: ''
  notes: 'blocked by S2. Q248=b — loading a save must emit ZERO cues; add no suppression code.'

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

- **Assumed, not checked:** every step above. Nothing is implemented yet.
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

None from this stream yet.

⚠ **Known design conflict, already flagged in the plan:** `Q84`=(b) puts `dim_target` on the style
resource; `Q168`=(a) calls it a player setting. The plan resolves to `Q84` as the later and more
specific answer. **If that reading is wrong, file a gap — do not split the difference.**

⚠ **Unrelated, noticed 2026-08-03:** `solatro/Cards/card_visual.tscn` shows as modified in
`git status` and this stream has not touched it. Probably the owner's editor.

## Files touched

Nothing yet.

## Next up

1. **S2** — the rename. First, always: mechanical only while nothing new depends on the old names.
2. **S1** — `ScoringSection`. Independent of S2; can be done either side of it.
3. **S4** — forced spotlight state, once S2 lands.

Opening prompt for the next agent: the fenced block in `PLAN.md` §0, *The opening prompt for a
fresh session*. Or, to resume mid-stream:

```
Resume solatro/HANDOFF_spotlight.md. Read it and solatro/design/spotlight/PLAN.md first;
they are self-contained. Continue from the first pending task. Phase 1 (S1-S10) only.
Follow the gap protocol at the head of PLAN.md. No git add, no commits. Never run Godot
while the owner's editor is open.
```

## References

- `solatro/design/spotlight/PLAN.md` — the specification. §1 is normative.
- `solatro/design/spotlight/DESIGN.md` v6 — the authority on behaviour. Where the two disagree, the
  design wins and the plan is wrong.
- `solatro/design/spotlight/answers.json` — 255 answers, 0 open.
- `solatro/START_HERE.md`, `solatro/VFX.md`, `solatro/LAYERING.md`,
  `solatro/ARCHITECTURE_REVIEW.md` §4g/§4h/§4i.
