---
name: implementer-routing
description: "Which model implements a step: Sonnet by default, Opus for input/focus/multi-viewport model work, Fable only as the read-only reviewer; escalate after two rejected verifications"
metadata:
  type: feedback
---

**Implementers default to `sonnet`; `opus` is the exception, chosen per step; the overseer (Fable)
writes no source.** Owner ruling: costs were too high with every implementer on Opus.

Route a step to **`sonnet`** when its brief already names the writer and the row (a knob, a
one-site fix with a cited `file:line`, a comment sweep, a probe re-shot, a re-point of named
tests, a recon-backed bug). Route to **`opus`** when the step designs a model the brief cannot
fully specify: input routing across viewports, focus ownership, a modal/lock state machine, a
deletion that must prove every caller gone, anything the recon left open. Never dispatch Fable as
an implementer; a step that needs it needs a smaller brief.

**The distribution, measured on one 20-step playtest stream** (all steps on Opus, 40k-480k
tokens each): cost concentrated in two places - the steps that DESIGNED a state machine
(a modal viewer, a lock suspension: 3-4 rejection rounds even on Opus) and the REWORK rounds
(a first pass that games a rule, a leak found only by the full gate, a shot taken mid-travel).
Neither is lowered by a stronger implementer; both are lowered by a sharper brief and a
read-only recon that names the writer first. So by step kind, from what actually happened:

| Kind of step | Share | Model | Why |
|---|---|---|---|
| a knob, a re-point of named rows, a comment sweep, a probe re-shot, a test-only repair, a one-site fix with its `file:line` in the brief | ~55% | `sonnet` | mechanical once the writer is named; the gate and sweep_check catch the miss |
| a bug whose CAUSE the recon left open (measure-first diagnoses: the P24 render-target frame, the P36 floor identity), a deletion that must prove every caller gone | ~30% | `opus` | the value is in the measurement design; the recon candidates were wrong twice on this stream |
| a new input or focus model across viewports, a modal/lock state machine, anything with three or more interacting rulings | ~15% | `opus`, and split the brief before dispatch | even Opus took 3-4 rounds; a smaller brief is the lever, not a bigger model |
| read-only recon (`Explore`) ahead of a step | every non-trivial row | `sonnet` | grep-and-cite; the implementer measures anyway - and it is what turns an Opus row into a Sonnet one |
| `bloat-reviewer` per diff, adversarial review at the close | as `/plan-run` says | `fable`, read-only | owner ruling; a finding is a brief for an implementer |

**Escalation - by the KIND of miss, not a count.** A Sonnet report that names an unknown cause
as a flake, or leaves a failure unexplained, goes to Opus on the FIRST such report, with the tree,
the logs and the rejected report - not a fresh brief. A mechanical miss (a comment over the line
limit, a shot taken mid-travel, a row not added to the dispatch list) is sent back once; it is
cheap to fix and a stronger model would not have avoided it. Measured on the first Sonnet step
(P38, playtest stream): the Sonnet pass spent 288k tokens over 185 tool calls (seven suite runs,
five "waiting" rounds) before the two-rejection escalation, MORE tokens than a comparable Opus
step (116k-238k) - so at a ~2.5x price ratio the handoff cost about what Opus-first would have,
and the Opus takeover still had to re-read the tree. Escalation saves only when the step
FINISHES on Sonnet (a knob, a sweep, a re-point); the moment a Sonnet report says "flake" or
"unexplained", every further Sonnet run is spent. Also cap it: ONE filtered run per report; the
overseer decides the next run.

**Why:** Sonnet 5 is documented close to Opus 4.8 at $2/$10 per MTok against $5/$25
([Anthropic](https://www.anthropic.com/news/claude-sonnet-5)); the verification hierarchy in
`/plan-run` (red-then-green, the gate, the reviewers) is what makes the tier safe to lower, and
it does not change with the author. Rule 7 of CLAUDE.md is the known risk — assistants differ
~7x in unprompted defensive code — so the bloat review stays per diff.

**Reviewers are Fable, always, and never edit.** Owner ruling, verbatim: "reviewer ideally fable
always, but it never touches the code itself, just finds issues." So `bloat-reviewer`,
`plan-auditor`, `adversarial-review`, the test-surface pass and the `/code-review` and `/simplify`
angles all run on `fable` and REPORT; every fix they name is a brief for an implementer (routed by
the table above), verified and gated like any step. `/simplify`'s apply phase and
`/code-review --fix` are not used here.

**How to apply:** pass `model: "sonnet"` or `"opus"` on the `Agent` call; record every model that
wrote code in the handoff's `IMPLEMENTED-BY` line the moment it changes. The reviewer is Fable
regardless of the author, so the floor ([[plan-run]] "The reviewer's model floor") is always
cleared. Related:
[[one-fix-at-a-time]], [[tests-that-prove-nothing]].
