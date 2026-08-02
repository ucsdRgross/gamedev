---
name: designloop-tool
description: designloop/ — local web tool presenting the flowchart-design questionnaire one question at a time; design CLOSED, design/designloop/PLAN.md is the 17-step build plan, and steps S1–S10 (Phases 0–2) are BUILT and green — resume from designloop/HANDOFF_designloop.md
metadata: 
  node_type: memory
  type: project
  originSessionId: c2e12eb4-4da5-425b-b1c7-49fb8ac3a906
  modified: 2026-08-02T03:28:28.641Z
---

`designloop/design/designloop/DESIGN.md` — the design (charts A–J) for the owner's "mini project":
the front end for [[repo-claude-tooling]]'s `/flowchart-design` workflow. **Both rounds answered
2026-08-01; the questionnaire is CLOSED.** `designloop/design/designloop/PLAN.md` beside it is the
build plan — 17 steps in 5 phases, each citing design node IDs, ordered so stopping after Phase 1
still leaves a working tool (Phase 3, the review canvas, is roughly half the work).

**BUILD STATE (2026-08-01): S1–S10, Phases 0–2, are done and verified — the questionnaire half
works end to end.** Resume from `designloop/HANDOFF_designloop.md`, which stands alone; next is
Phase 3, the canvas, at S11 (mermaid ingestion, the riskiest step). `npm --prefix designloop test`
is the gate. Both hard gates passed: SPOTLIGHT_DESIGN.md parses UNEDITED (195 live + 1 retired
questions, 0 errors), and a crash between the log append and the materialise is recovered by
replay. One gap is open and not blocking — GAP-001, a contradiction between "a ⚑gate option with no
`→ next:` is a parse error" and "the acceptance document must parse unchanged" (QR8 breaks it);
both behaviours exist behind a `strict` flag until the owner answers.

**Windows landmine, design-guaranteed not bad luck:** a replacing `rename` fails with **EPERM** while
the S9 watch holds the design directory open, so `writeJsonAtomic` retries. Atomic-write + directory
watch on the same folder is the collision; any new writer in that directory needs the same retry.

**Measured, replacing two wrong hand estimates:** `SPOTLIGHT_DESIGN.md` is **196 question lines**
(188 `Q` + 8 `QR`; 195 live, Q140 retired in place), 8 `⚑gate`, 39 `notes`, and its **longest path is
194 of 195** — only one pair in the DAG is mutually exclusive. ⚠ **Gate weight only prunes when a
root's DEFAULT is the pruning branch**; Spotlight's roots all default to "include this sub-feature",
so all-defaults answers nearly everything. The DAG's value is amputating a sub-feature in one click,
not a short common path.

**Structure settled:** the tool lives in `designloop/`; design ARTEFACTS live beside the code they
describe, `<project>/design/<slug>/` (so `solatro/SPOTLIGHT_DESIGN.md` moves to
`solatro/design/spotlight/DESIGN.md`), each design self-contained with its own `gaps/`,
`ASSUMPTIONS.md` and `versions/`. Markdown stays the source of truth — the tool parses it, so the
workflow still works with no tool at all. Phase 0's acceptance test is that
SPOTLIGHT_DESIGN.md parses UNCHANGED; if it needs edits, the grammar is wrong.

The loop it specifies: braindump in chat → agent researches and authors a question DAG + draft
design graph → agent hands over a **local URL** → owner answers **one question at a time**, never
sees the count, never sees a question their earlier answers pruned, free-text note at every fork,
**every answer fsynced to disk before the next question appears** → agent notices the round ended
by itself → follow-up round or finalise → owner reviews the design graph on a pan/zoom canvas with
node and edge annotations and a side panel of assumptions / out-of-scope / notes → Confirm freezes
a version, or Review again runs another cycle → a confirmed version is what an implementation agent
turns into an execution plan.

**The five rules of a question** (owner requirements, fixed): prefilled clickable options; each
option states its CONSEQUENCE, not just a label; free text AND a "not relevant / not worth
answering" button (which records the recommended default, flagged unreviewed) on every question;
every question self-contained — answerable alone on a screen with nothing to look up; and gating
questions preview what follows each option (`→ next:`). Consequence: **free text at a gating
question ends the round immediately** and hands back to the agent to author the new branch, since
every later question sits on a path the owner just declined. Back navigation is required, including
re-answering a gate to take a different path; stranded answers are marked inactive, never deleted.

Design decisions already made (structure, not up for question): **no file is written by both the
agent and the UI** — that is the entire concurrency design (questions.json is agent-only,
answers.json is UI-only, status.json has one field each; no locks, nothing can be lost). Plain
JSON per project, append-only answer log beside the materialised file, atomic writes, never
touches git.

**The gap protocol (chart J) closes the loop back from execution.** An implementing agent that hits
a decision the design does not cover triages it: reversible + clearly within intent → do it and log
an assumption; otherwise (two defensible choices differ in what the player sees / expensive to
reverse / an owner call) → **park that thread only, file `gaps/GAP-NNN.md`, keep working the rest,
tell the owner**; design contradicts itself or the code → always a gap. A gap is written IN THE
QUESTIONNAIRE GRAMMAR so its options become the next round's questions unchanged. It may never be
resolved by the agent picking an answer, and is closed only by a new design version. This requires
**every execution-plan step to cite the design node IDs it implements** — without that there is no
blast radius. The protocol travels via a self-propagating block copied verbatim into every derived
document (design → execution plan → handoff → …); the master copy is in the skill, the first live
copy is `solatro/SPOTLIGHT_DESIGN.md` §20.

**Round 1 answered 2026-08-01** (§11 of the doc). Notable: the review canvas IS in v1 (QR3=a);
questions are ordered document-order-within-section, sections by gate weight (Q11=c); no progress
indicator of any kind (Q26=a — "progress is impossible to determine with branching paths"); Enter
repeatedly accepts defaults but those must be logged as a distinct state since they were not
actually considered (Q12); full mouse + arrow-key parity everywhere (Q13).

**Runtime decided: Node, zero dependencies.** The owner asked Python-vs-Node; the evidence flipped
the default. Node v26.4.0 installed; `palette/tools/serve.mjs` is a 435-line **dependency-free Node
local server already doing this job** (static hosting + JSON file API + ping/shutdown port
reclaim); `palette` has no npm dependencies and uses built-in `node --test`. Decisive factor: the
question-grammar parser and graph schema are needed in BOTH browser and server — Node makes that
one module, Python makes it two implementations, and "two copies drift" is this repo's most
repeated scar. (`py` is Python 3.9.7, `python` is 3.14.6 — two disagreeing Pythons.)

The two questions that restructure everything: **QR1** (how the agent learns a round ended — a
watch loop vs the owner saying so; no precedent for this in the repo) and **QR3** (is the review
canvas in v1, or questionnaire-first — roughly half the work).

**Ordering:** this ships before [[solatro-spotlight-design]] resumes, and Spotlight is its first
real client — 188 questions, 8 root gates, ~200 graph nodes, converted from its existing markdown
without editing it.
