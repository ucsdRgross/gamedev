---
name: implementer-routing
description: "Which model implements a step: Sonnet by default, Opus for input/focus/multi-viewport model work, Fable never as a subagent; escalate after two rejected verifications; the reviewer floor follows the author"
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
| `bloat-reviewer` per diff, adversarial review at the close | as `/plan-run` says | at or above the author | the floor rule |

**Escalation:** a Sonnet step whose report the overseer rejects twice (a wrong diagnosis, a
weakened row, a leak it cannot find) goes to Opus with the evidence so far — the tree, the logs,
the rejected report — not a fresh brief. Never escalate on the first miss; the gate and the
reviewers catch the same errors at either tier.

**Why:** Sonnet 5 is documented close to Opus 4.8 at $2/$10 per MTok against $5/$25
([Anthropic](https://www.anthropic.com/news/claude-sonnet-5)); the verification hierarchy in
`/plan-run` (red-then-green, the gate, the reviewers) is what makes the tier safe to lower, and
it does not change with the author. Rule 7 of CLAUDE.md is the known risk — assistants differ
~7x in unprompted defensive code — so the bloat review stays per diff.

**How to apply:** pass `model: "sonnet"` or `"opus"` on the `Agent` call; record every model that
wrote code in the handoff's `IMPLEMENTED-BY` line the moment it changes. The reviewer floor
([[plan-run]] "The reviewer's model floor") follows the AUTHOR: a Sonnet-authored diff may be
reviewed by Sonnet, Opus or Fable; an Opus-authored one by Opus or Fable. Related:
[[one-fix-at-a-time]], [[tests-that-prove-nothing]].
