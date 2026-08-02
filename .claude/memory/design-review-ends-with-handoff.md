---
name: design-review-ends-with-handoff
description: "A design review ends with the implementation plan AND a copy-paste handoff prompt in the same message — never stop at the plan and wait to be asked if it's ready"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: c2e12eb4-4da5-425b-b1c7-49fb8ac3a906
  modified: 2026-08-02T02:45:09.977Z
---

**The trigger is the owner CONFIRMING the flowcharts, not their answering the last question.**
Sequence: last question answered → agent finalises the flowcharts → **owner reviews them** →
owner confirms → *then* the handoff. Answering the questionnaire settles decisions; reviewing the
charts settles sequence and completeness ("between D6 and D7 there must be…"), and that feedback
only arrives when someone looks at the chart. Until the Design Loop tool ships, the review stage is
the markdown doc's own mermaid charts — present them, say what the answers changed, and **ask for
confirmation rather than assuming it**.

Once confirmed, the next message must contain **the implementation plan, a scope recommendation,
and a copy-paste prompt for the implementing agent** — all three, together. Stopping at the plan and
waiting for "is this ready to hand off?" is friction the owner called out by name (2026-08-01).

**Why:** the point of the questionnaire is that answering it is the owner's whole job. Making them
then chase readiness, discover the plan is under-specified, and ask again for a prompt re-imports
exactly the back-and-forth the workflow exists to remove.

**How to apply:**
- The no-code rule belongs to the DESIGN doc only. The IMPLEMENTATION plan must carry every
  normative contract — file schemas field by field with who writes each, formal grammars, module
  API signatures, the wire protocol, per-step done-when, and hard self-checking acceptance gates.
  *"The plan deliberately contains no implementation detail"* is an unfinished plan with an excuse
  attached; that exact phrasing was the failure.
- Run the readiness checklist before presenting: grep that every path the plan references exists or
  is created by a step; every step cites design node IDs; the plan's own docs live in the layout its
  design mandates; nothing is still phrased as a question.
- Fix loose ends yourself rather than handing back another decision the owner already made
  implicitly by answering the questionnaire.
- End with the fenced prompt, scoped to specific phases, naming the effort level and the hard gates.

The full procedure is Step 8 of `.claude/skills/flowchart-design/SKILL.md`.
