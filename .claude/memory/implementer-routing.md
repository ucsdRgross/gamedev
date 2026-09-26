---
name: implementer-routing
description: "Which model implements a step: Opus medium or low, or Sonnet low for mechanical work, effort set in each agent's frontmatter; Fable only as the read-only reviewer"
metadata:
  type: feedback
---

**Owner, verbatim: "implementers will be opus 5.5 medium or low or sonnet 5 low."** Three
definitions, effort in each one's frontmatter (the only per-subagent effort control; the `Agent`
call cannot pass effort): `plan-implementer` (`model: opus`, medium), `plan-implementer-low`
(`opus`, low), `plan-implementer-sonnet` (`sonnet`, low - mechanical steps only). The presets use
the aliases so they follow each new version (owner). The overseer writes no source.

**Route by what the brief already knows, not by how big the step looks:**

| The step | Dispatch | Measured on the playtest stream |
|---|---|---|
| mechanical: a comment sweep, a one-line inline, a doc correction, a re-point of named rows | `plan-implementer-sonnet` | 5 of 5 landed first round, 29k-54k tokens each |
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

**Cost arithmetic (Anthropic's published prices, Sept 2026):** Sonnet 5 $2/$10 per MTok; Opus 5.5
$4/$20, cache reads $0.20; Opus 5 $5/$25, cache reads $0.50. A subagent's spend is mostly cache
reads of its own growing context, so continuing a finished implementer with `SendMessage` for its
next round is cheaper than a fresh one re-reading the tree - until its context is very large
(a 600k-token round is the sign to start fresh with a sharp brief).

**Reviewers are Fable, always, and never edit.** Owner, verbatim: "reviewer ideally fable always,
but it never touches the code itself, just finds issues." Every finding is an implementer step,
verified and gated like any other; `/simplify`'s apply phase and `/code-review --fix` are not used.
⚠ **Ask each per-diff review two to four questions about THIS diff's riskiest interactions**, beyond
rules 7 and 8 (which inputs reach the new path, what state it inherits, whether a re-pointed test got
looser, which docs now contradict it). About two in three such reviews on the playtest stream
returned an actionable finding - a hang route, a stale flag across a teardown, a coordinate-space
mix, a test that could pass vacuously - that the implementer's own green run had not caught.

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
- A 150-turn cap stop (a broad medium step: a layout rebuild plus a lock-out retired plus six
  re-pointed rows) leaves the edits in the tree and is resumable: `SendMessage` to the same agent
  continues with its context intact. A step that big is the sign to split the next brief.
- An app restart or a usage limit kills a running subagent mid-step and leaves its last edits in
  the tree and `.claude/.subagent.lock` held. Read the diff and its scratch evidence before
  redispatching, and clear the lock by hand when nothing runs.

**How to apply:** dispatch by `subagent_type`; record every model that wrote code in the handoff's
`IMPLEMENTED-BY` line the moment it changes. Related: [[one-fix-at-a-time]],
[[tests-that-prove-nothing]], [[brief-premise-is-a-hypothesis]].
