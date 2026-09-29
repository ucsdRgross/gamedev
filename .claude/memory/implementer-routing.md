---
name: implementer-routing
description: "Which model implements a step: Opus 5.5 medium, then Opus 5.5 low, then Sonnet 5.5 high for deterministic grunt work, effort set in each agent's frontmatter; Fable only as the read-only reviewer"
metadata:
  type: feedback
---

**Owner, verbatim: "opus 5.5 is still more trustable for general work. sonnet 5.5 should still do
deterministic grunt work, looking at the stats though, sonnet 5.5 is much better to be run at high
effort instead of low. cheaper and less likely to make mistakes. sonnet 5.5 high is tier below opus
5.5 medium."** Then, placing it: **"lets put sonnet 5.5 high below opus 5.5 low."** (Supersedes
"implementers will be opus 5.5 medium or low or sonnet 5 low.") Three definitions, highest tier
first, effort in each one's frontmatter (the only per-subagent effort control; the `Agent` call
cannot pass effort): `plan-implementer` (`model: opus`, medium), `plan-implementer-low` (`opus`,
low), `plan-implementer-sonnet` (`sonnet`, high - deterministic grunt work only). The presets use
the aliases so they follow each new version (owner); `sonnet` is Sonnet 5.5 on the Anthropic API
from Claude Code v2.1.284 (code.claude.com/docs/en/model-config). The overseer writes no source.

**The deciding question (Opus 5.5 low and Sonnet 5.5 high are close in capability, so the TASK
decides): can this step end with "the premise was wrong, stop and ask"?** No -> Sonnet. Yes, the
writer named -> Opus low. Yes, the cause open -> Opus medium. The implementers answer it again from
what they measure and stop below the tier that owns the call; every report ends with a `ROUTING:`
line (right tier / needs a higher tier / could go lower) - route the NEXT similar step by it.
Cost check at the boundary: cache reads cost the same on both models ($0.20/MTok) and are most of a
subagent's spend, so Sonnet is cheaper only while it needs no more turns than Opus low would; a
"deterministic" step that runs long on Sonnet was not deterministic - route its kind one tier up.

**Route by what the brief already knows, not by how big the step looks:**

| The step | Dispatch | Measured on the playtest stream |
|---|---|---|
| mechanical: a comment sweep, a one-line inline, a doc correction, a re-point of named rows | `plan-implementer-sonnet` | Sonnet 5 at low: 5 of 5 landed first round, 29k-54k tokens each; Sonnet 5.5 at high not yet measured here |
| the writer and row are named: a one-site fix with its `file:line`, a recon-backed bug | `plan-implementer-low` | 34k-69k tokens each; each one either landed or stopped with a measured owner question |
| the cause is open, a focus/input model across viewports, a modal or lock state machine, a deletion that must prove every caller gone | `plan-implementer` (medium) | 100k-680k tokens per round; split the brief before dispatch - a smaller brief, not a bigger model, is the lever |
| read-only recon ahead of a step | `Explore` on `sonnet` | grep-and-cite; the implementer measures anyway |
| every review | `bloat-reviewer` / `plan-auditor` / `adversarial-review` / `pair-reviewer` on `fable` | read-only, see below |

**Escalation - by the KIND of miss, not a count.** A low or Sonnet report that calls an unknown
cause a flake, or leaves a failure unexplained, goes to medium effort on the FIRST such report, with
the tree, the logs and the rejected report - not a fresh brief. A mechanical miss (a comment over
the line limit, a shot taken mid-travel) is sent back once. ONE filtered run per report; the
overseer decides the next run. The one Sonnet step ever given an open-cause bug spent 288k tokens
over 185 tool calls and failed where Opus steps spent 116k-238k and landed - so Sonnet only for
work that cannot turn into a diagnosis.

**Cost arithmetic (Anthropic's published prices, Sept 2026):** Sonnet 5 and 5.5 $2/$10 per MTok, Sonnet 5.5 cache reads $0.20; Opus 5.5
$4/$20, cache reads $0.20; Opus 5 $5/$25, cache reads $0.50. A subagent's spend is mostly cache
reads of its own growing context, so continuing a finished implementer with `SendMessage` for its
next round is cheaper than a fresh one re-reading the tree - until its context is very large
(a 600k-token round is the sign to start fresh with a sharp brief).

Every finding becomes an implementer step. When and how to spend a review (per step, per group, a
mechanism-shaping owner question, the close): `/plan-run` § "Spending the reviewer".

**The main agent is Opus 5.5 at high effort, for design and implementation alike, and the
`/plan-run` overseer with it; Fable 5.1 is its pair reviewer.** Owner, as recorded in the todo: "the
main agent is Opus 5.5; as it goes it asks a Fable 5.1 subagent to review its work at reasonable
checkpoints and suggest changes, like pair programming"; the overseer half was a proposal the owner
answered "go". Design checkpoints: `/flowchart-design` § Pair review.

**Operational gotchas, all measured:**
- A definition naming a model the app cannot run is SUBSTITUTED by the session's model, and ran at
  the session's effort (high), not the frontmatter's. Have the owner confirm model and effort on the
  subagent's `/tasks` row after any edit to a definition.
- A NEW agent file is offered in the same session; whether an EDIT to an already-loaded definition
  applies before the next session is unmeasured - treat it as next-session.
- A subagent cut off by its turn cap, a usage limit or an app restart: `/plan-run` "Interruptions".

Related: [[one-fix-at-a-time]], [[tests-that-prove-nothing]], [[brief-premise-is-a-hypothesis]].
