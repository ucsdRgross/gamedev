---
name: designloop-tool
description: designloop/ — local web tool presenting the flowchart-design questionnaire one question at a time, plus a review canvas and a gap surface; design CLOSED and ALL 17 build steps are DONE and green (2026-08-02) — read designloop/README.md, then HANDOFF_designloop.md
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

**BUILD STATE (2026-08-02): ALL 17 STEPS DONE — the tool is finished and green at 118 tests**
(`npm --prefix designloop test` is the gate). `designloop/README.md` is the entry point;
`designloop/HANDOFF_designloop.md` is the build's live state and stands alone. Every hard gate
passed: the Spotlight document parses and ingests **UNEDITED** (195 live + 1 retired questions,
0 errors; 14 charts, 176 nodes, 182 edges) — verified again after S16 moved it, byte-identical
(sha1 `68c348db`); a crash between the log append and the materialise is recovered by replay; the
hand-rolled layered layout does those 176 nodes in **1.8 ms**, deterministically, so **no layout
dependency was needed** and no gap was filed for one.
**GAP-002 is RESOLVED (b), 2026-08-02 → design version 3** (`DESIGN.md` §14), answered in the tool's
own scoped gap round — the first time the gap loop ran on real work. The whole-graph view had no
connections to show, because **neither real document has a single cross-chart edge** (of 133 and
182) while node labels name other charts in prose. They are now **derived**: `src/graph.mjs` reads
`chart X` out of a node label into a `links` list beside `edges` in `graph.json` (PLAN §4.6, §6.1),
and the canvas draws them dashed, node-to-chart, hidden in the single-chart picker, toggled with
`l`. **10 links here, 5 in Spotlight, 0 unresolved — pinned as a fixture**, and neither document
was edited. ⚠ **Resolution is by the name the DOCUMENT uses before the chart ID**: Spotlight's §7
holds two charts, so from there every chart ID runs a letter ahead of its heading and
`K14 "see chart H"` means the chart with `I`-prefixed nodes — ID-first gives a confidently wrong
link. Unresolved → warning; same-chart → dropped; repeated → deduped. Six other review defects were
fixed (see the handoff's S18); the
biggest reusable one: **`web/md.mjs` is now the ONE inline-markdown renderer** — it was copied into
three screens and the canvas panel had never had it, so `**bold**` reached the owner as asterisks.

GAP-001 was resolved (b) on 2026-08-01: a ⚑gate option with no `→ next:` is a
**warning**, surfaced by `run check`, by a badge on the index card, and on the question screen as
`→ next: not described`; `strict: true` still throws for the grammar test.

**S16 moved the owner's paused document, 2026-08-02:** the file that was `solatro/SPOTLIGHT_DESIGN.md`
is now `solatro/design/spotlight/DESIGN.md` (Q104=a, one layout, no exceptions), with `meta.json`'s `doc`
changed from `../../SPOTLIGHT_DESIGN.md` to `DESIGN.md`. **Not one byte of the document changed.**
Anything pointing at the old top-level path is stale.

**The gap surface (S15) is where execution gets back into the design.** `src/gaps.mjs` reads
`gaps/*.md` as *draft questions* — the `**Options I can see**` line goes through the same grammar
as every other question (`parseQuestionBody`), with `*my recommendation*` normalised to `*default*`
— so `question.html?key=…&scope=gaps` is a **scoped round** asking only the open gaps. Answers land
in the ordinary `answers.json` keyed by the gap's own ID; the last one ends the owner's turn with
`reason: "gaps_answered"`, which wakes the watch WITHOUT ending the main questionnaire (Q88b=a).
Stale plan steps are **computed and reported, never written into `PLAN.md`** — read out of the
plan's `(implements …)` citations against a gap's `**Blast radius**` line. The canvas' assumptions
panel files a gap from an assumption ("I want a say in this", Q95b=a) with **no options**, because
the tool never authors a question (Q94=a).

**Two places the DESIGN beat the PLAN in Phase 3, both worth remembering as a pattern:** Q52's
written answer asked for a chart picker *and* the whole graph with collapsible charts (the plan
recorded only the latter), and Q59's asked for **disapproval flagging** with soft-approval defaults
(the plan's summary said per-node approval). Read the owner's own words in `DESIGN.md` §9, not the
plan's one-line summary of them.

**The mermaid subset is deliberately tiny** (`PLAN.md` §6, `src/graph.mjs`): `ID["label"]`,
`ID{"decision"}`, `-->`, `-- label -->`, one `flowchart TD` header, one shared ID prefix per chart.
Everything else throws with the file and line. It is parsed by a left-to-right cursor, never by
splitting on `-->`, because real labels contain `->`, `--` and `·`.

**S19 — the owner's review of the ANSWERING screen, 2026-08-03 → design version 4** (`DESIGN.md`
§15, nodes B18–B20, D10–D14, E12–E16). Seven findings, **none of them a re-answered question**:
history is a scrollable sidebar carrying question *and* answer; **BACK is a browser-style visit
stack** in `sessionStorage` (it used to mean "the newest answer", so standing on that answer it
pointed at itself and did nothing); every control shows its key (`w n ⌫ h g i`, options are their
own letters); **Enter's target is marked before it is pressed** and moves to "use what I wrote" as
soon as you type — which killed a bug where Enter discarded a typed answer with no undo; and
`session.json` (§4.9) is the watch's **heartbeat**, so the screen says whether an agent is actually
parked, with a prompt to paste when none is. Q108's states survived being shown: the mark where the
screen *put* it answers `defaulted`, the mark the owner *moved* answers `chosen`.

⚠ **The general lesson, now in the skill:** every one of those seven was a decision the design had
already settled (Q12 Enter, Q33 BACK, QR1 the watch) that the SCREEN never said out loud. A
questionnaire settles what a thing does; it does not settle whether the person using it can tell.
Plan for two reviews — one on the charts, one by driving the built thing — and when a design settles
a hidden behaviour, write the node saying how the user will KNOW.

**To LOOK at a screen** (CLAUDE.md rule 4, and the Browser pane's screenshot fails here because the
pane is not displayed): `node designloop/tools/shot.mjs <url> <out.png> [w] [h] ["js first"]` —
headless Edge over CDP with Node's built-in WebSocket, running a JS snippet before the capture, so
the shot can be of a state behind a click. `msedge --screenshot` alone only ever gets the initial
state. It paid for itself immediately: the links passed every count and every test, and the
screenshot of the COLLAPSED canvas is what showed them lying flat through the boxes (collapsed
charts shelf-pack into one row, so a bow proportional to the vertical drop is zero).

**Windows landmine, design-guaranteed not bad luck:** a replacing `rename` fails with **EPERM** while
the S9 watch holds the design directory open, so `writeJsonAtomic` retries. Atomic-write + directory
watch on the same folder is the collision; any new writer in that directory needs the same retry.

**Measured, replacing two wrong hand estimates:** the Spotlight `DESIGN.md` is **196 question lines**
(188 `Q` + 8 `QR`; 195 live, Q140 retired in place), 8 `⚑gate`, 39 `notes`, and its **longest path is
194 of 195** — only one pair in the DAG is mutually exclusive. ⚠ **Gate weight only prunes when a
root's DEFAULT is the pruning branch**; Spotlight's roots all default to "include this sub-feature",
so all-defaults answers nearly everything. The DAG's value is amputating a sub-feature in one click,
not a short common path.

**Structure settled:** the tool lives in `designloop/`; design ARTEFACTS live beside the code they
describe, `<project>/design/<slug>/` (which is where Spotlight now lives, at
`solatro/design/spotlight/DESIGN.md`), each design self-contained with its own `gaps/`,
`ASSUMPTIONS.md` and `versions/`. Markdown stays the source of truth — the tool parses it, so the
workflow still works with no tool at all. Phase 0's acceptance test is that that document parses
UNCHANGED; if it needs edits, the grammar is wrong.

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
copy is `solatro/design/spotlight/DESIGN.md` §20.

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

⚠ **The ASK LIST landed 2026-08-03** (`status.agent.json` → `"ask": ["Q24", …]`, README §"The ask
list"). An entry counts as **unanswered until answered in that round**, which both re-opens it — asked
FIRST, previous answer prefilled — and **holds the round open until the whole ask is satisfied**.
Owner report that caused it: *"going into history to find the question you are talking about then
changing previous choice to unlock questions is pretty bad UX… every question that needs to be
answered needs to be given in one go, and you only pick up its finished when I finish."* Before it,
the only routes were making the owner navigate their own history or asking in chat and leaving
`answers.json` out of step.

⚠ **Its test suite used to PIN the live Spotlight document's counts** (188 questions, longest path
194, 176 nodes) — five tests broke on every ordinary design edit and none ever found a defect. They
assert properties now (parses clean, DAG sound, every originally-ingesting chart still ingests,
every derived link still resolves), plus the two checks that HAVE caught bugs: every gating question
is `⚑gate`, and no option orphans its subtree. **132 tests.**

⚠ **`run check` gained two audit lines on 2026-08-03** — `dag audit` (a gating question not marked
`⚑gate`; a `default` orphaned from a multi-letter gate; a section heading narrower than its own
question lines) and `stale` (chart nodes posing an ANSWERED question as an open fork). They catch the
class of defect that leaves a document parsing, validating and reporting `done (complete)` while
**silently withholding questions from the owner**. Neither blocks. **135 tests.**

⚠ **`run check` also reports `plan`** once a `PLAN.md` exists beside the design: steps whose
`(implements …)` cites a non-existent node, and steps citing nothing (which can never be reported
stale). `planSteps` now tolerates a leading `- [ ]` — it used to reject it and silently reattribute
that step's citations to the step ABOVE. **The plan is the immutable spec; progress lives in
`<project>/HANDOFF_<topic>.md` as an `id`/`status`/`evidence`/`notes` ledger, never restating the
plan.** 136 tests.
