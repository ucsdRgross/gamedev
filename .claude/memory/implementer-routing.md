---
name: implementer-routing
description: "Which model implements a step: Opus 5.5 medium or low, or Sonnet 5 low for mechanical work, effort set in each agent's frontmatter; Fable only as the read-only reviewer"
metadata:
  type: feedback
---

**Owner, verbatim: "implementers will be opus 5.5 medium or low or sonnet 5 low."** Three
definitions, effort set in each one's frontmatter (the docs' only per-subagent effort control;
the `Agent` call cannot pass it): `plan-implementer` (`opus`, medium),
`plan-implementer-low` (`opus`, low), `plan-implementer-sonnet` (`sonnet`, low -
mechanical steps only). ⚠ A definition naming a model the app cannot run is SUBSTITUTED by the
session's model, and the owner saw that run at the session's effort (high) rather than the
frontmatter's low. The presets use the `opus` and `sonnet` aliases so they follow each new version (owner).
Name only a model the app supports, and have the owner confirm model and
effort on the subagent's `/tasks` row after an edit. **A session caches an agent definition when it
first loads it**: an edit takes effect in the NEXT session; a refused dispatch leaves
`.claude/.subagent.lock` held - clear it by hand when nothing runs.

**Implementers run the latest Opus (`model: opus`; on an older app the alias resolved to Opus 5
from a Fable session - confirm on `/tasks`), and the lever is EFFORT, not the model family:
`plan-implementer-low` (effort low) for a step whose writer and row the brief names,
`plan-implementer` (effort medium) for the rest.** The overseer (Fable) writes no source.
Owner ruling: costs were too high with every implementer on Opus 5. A Sonnet tier failed one
non-mechanical step (below); it is back, low effort, for mechanical steps only.

**The arithmetic (Anthropic's published prices, Sept 2026):** Sonnet 5 $2/$10 per MTok;
Opus 5.5 $4/$20, cache reads $0.20; Opus 5 $5/$25, cache reads $0.50. Opus 5.5 is 2x Sonnet
per token and "40% less than Opus 5 on typical workloads", i.e. it also spends fewer tokens per
task. A subagent's spend is mostly cache reads of its own growing context, where 5.5 matches
Sonnet's rate. Measured here: the one Sonnet step spent 288k tokens and failed where Opus steps
spent 116k-238k and landed - at that token ratio Sonnet's 2x price edge is gone before the
escalation rework is counted. Effort is the cheaper lever: low effort on a named-writer step
cuts the tokens without changing the model's judgement when the step turns out to need it.

Route a purely mechanical step (a sweep, a knob, a re-point, a re-shot) to **`plan-implementer-sonnet`**;
route a step to **`plan-implementer-low`** when its brief already names the writer and the row (a
knob, a one-site fix with a cited `file:line`, a comment sweep, a probe re-shot, a re-point of
named tests, a recon-backed bug). Route to **`plan-implementer`** (medium) when the step designs
a model the brief cannot fully specify: input routing across viewports, focus ownership, a modal/lock state machine, a
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
| a knob, a re-point of named rows, a comment sweep, a probe re-shot, a test-only repair, a one-site fix with its `file:line` in the brief | ~55% | Opus 5.5 LOW | mechanical once the writer is named; the gate and sweep_check catch the miss |
| a bug whose CAUSE the recon left open (measure-first diagnoses: the P24 render-target frame, the P36 floor identity), a deletion that must prove every caller gone | ~30% | Opus 5.5 MEDIUM | the value is in the measurement design; the recon candidates were wrong twice on this stream |
| a new input or focus model across viewports, a modal/lock state machine, anything with three or more interacting rulings | ~15% | Opus 5.5 MEDIUM, and split the brief before dispatch | even Opus took 3-4 rounds; a smaller brief is the lever, not a bigger model |
| read-only recon (`Explore`) ahead of a step | every non-trivial row | `sonnet` (grep-and-cite, no judgement) | grep-and-cite; the implementer measures anyway - and it is what turns an Opus row into a Sonnet one |
| `bloat-reviewer` per diff, adversarial review at the close | as `/plan-run` says | `fable`, read-only | owner ruling; a finding is a brief for an implementer |

**Escalation - by the KIND of miss, not a count.** A low-effort report that names an unknown cause
as a flake, or leaves a failure unexplained, goes to medium effort on the FIRST such report, with the tree,
the logs and the rejected report - not a fresh brief. A mechanical miss (a comment over the line
limit, a shot taken mid-travel, a row not added to the dispatch list) is sent back once; it is
cheap to fix and more effort would not have avoided it. Measured on the first Sonnet step
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

**The overseer stays Fable for a stream in flight; the next stream may try Opus 5.5 at high effort
and compare.** The arithmetic: an overseer's turns are almost all cache reads of a long context,
priced $0.25/MTok on Fable 5.1 against $0.20 on Opus 5.5 - near parity - while its output and
fresh input are small; so switching the overseer saves far less than the sticker prices (2.5x)
suggest, and mid-stream it costs a full context re-read. What the overseer buys is judgement
over a very long context: rejecting a report whose exit profile moved, whose shot was taken
mid-travel, whose "flake" had passed four gates, whose tolerance was calibrated to a bug. Judge
a 5.5 overseer on that record, not on benchmarks.

**Reviewers are Fable, always, and never edit.** With the implementer on Opus 5.5 that is also a
DIFFERENT model reading the author's code - decorrelated blind spots, which `/plan-run` values at
or above the floor - and a review is a short read (24k-58k tokens each on this stream), so its
Fable price is small. Owner ruling, verbatim: "reviewer ideally fable
always, but it never touches the code itself, just finds issues." So `bloat-reviewer`,
`plan-auditor`, `adversarial-review`, the test-surface pass and the `/code-review` and `/simplify`
angles all run on `fable` and REPORT; every fix they name is a brief for an implementer (routed by
the table above), verified and gated like any step. `/simplify`'s apply phase and
`/code-review --fix` are not used here.

**How to apply:** dispatch `plan-implementer-low` or `plan-implementer` by `subagent_type` (effort
lives only in the frontmatter - the `Agent` call cannot override it, and its `model` enum offers
aliases only, so the full id lives there too); record every model that
wrote code in the handoff's `IMPLEMENTED-BY` line the moment it changes. The reviewer is Fable
regardless of the author, so the floor ([[plan-run]] "The reviewer's model floor") is always
cleared. Related:
[[one-fix-at-a-time]], [[tests-that-prove-nothing]].
