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
