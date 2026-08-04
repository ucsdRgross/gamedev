# PLAN.md — Design Loop implementation plan

The execution plan for the Design Loop tool. Derived from `DESIGN.md` (beside this file) with
round 1 and round 2 fully answered (2026-08-01). **This is the build document; the design document
is the authority on behaviour.** Where they disagree, the design wins and this file is wrong.

**Start here. You need no other document to build this tool.** §4–§7 are normative: the file
formats, the question grammar, the mermaid subset and the module APIs are specified, not suggested.

---

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `designloop/design/designloop/DESIGN.md`, **version 3** — rounds 1–2 answered
2026-08-01, the GAP-001/GAP-002 round answered 2026-08-02 (design §14). Every step below cites the
design node IDs it implements.

If you are executing this and you reach a decision the design does not cover:

1. Reversible and clearly within intent → do it, and append one line to
   `designloop/design/designloop/ASSUMPTIONS.md` citing the node you were working on. Never
   silently.
2. Otherwise — two defensible choices differ in what the user sees, or the choice is expensive to
   reverse (file format, a public seam, the question grammar), or it is an owner call (scope, look)
   → **park that thread, file a gap, keep working on unaffected threads, and tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.

File gaps at `designloop/design/designloop/gaps/GAP-NNN.md` using the template in
the gap template in `.claude/skills/flowchart-design/SKILL.md`.
Write the options in the questionnaire grammar; they become the next round's questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## 1. The decisions this plan is built on

Everything here is settled. It is restated so a fresh agent needs one file to start.

| Decision | Source |
|---|---|
| **Node, zero npm dependencies**, modelled on `palette/tools/serve.mjs` (a 435-line dependency-free local server already doing this job). `node --test` for tests. | Q100=a |
| **Markdown is the source of truth.** The design doc IS the questionnaire; the tool parses it. Never a second authored copy. | QR7=a |
| **Design artefacts live beside the code they describe**: `<project>/design/<slug>/`. `designloop/` holds only the tool. | Q101=b, Q102=a |
| A design's `gaps/` and `ASSUMPTIONS.md` live **inside its own directory**, so a design moves or archives whole. | Q105=a |
| **No file is written by both the agent and the UI.** `questions` (from markdown) is agent-side; `answers.json`, `annotations.json` are UI-side; `status.json` has one field each. No locks. | §3 |
| **Durability:** append to a log, atomically rewrite the materialised file, `fsync` both, *then* return 200. The UI never advances on a failed write. | Q80=a, Q82=a |
| **One question per screen. No progress indicator of any kind.** | Q10=a, Q26=a |
| Options are **prefilled, clickable, each with its consequence**; free text and *not relevant* always available; every question **self-contained**. | §1 rules 1–4 |
| **Three answer states:** `chosen`, `not_relevant`, `defaulted`. | Q108=a |
| **Enter repeatedly accepts defaults, but stops at ⚑gate and `notes` questions**, then shows what was accepted. | Q109=a, Q110=a, Q111=a |
| **Full mouse + keyboard parity** everywhere, canvas included: arrow keys move a focus ring, Enter picks, letter keys jump, everything is also a click target. | Q112=a, Q113=a |
| **Free text at a gate ends the round immediately** and hands back to the agent. | chart B2 |
| **Back navigation + history list**; changing an answer warns before stranding later ones; stranded answers are marked inactive, never deleted, and restored on return. | Q33=a, Q34=a, Q35=a |
| **Canvas is in v1:** whole graph at once, collapsible subgraphs, auto layout, pan/zoom, node **and** edge annotations, side panel, per-node approval, versions + diff, SVG/PNG export, colour by chart **or** status. | QR3=a, Q52=c, Q66=c |
| **Confirm freezes layout AND collapse state**, so a version reopens exactly as left. | Q115=b |
| **The agent watches `status.json`**, and telling it in chat always works too. | QR1=c |
| **The tool never touches git.** | Q83=a |

---

## 2. Directory shape

```
designloop/                          THE TOOL
├─ design/designloop/                its OWN design, in the standard layout (Q104: no exceptions)
│   ├─ DESIGN.md                     the design (authority)
│   ├─ PLAN.md                       this file
│   ├─ meta.json  ASSUMPTIONS.md  gaps/
├─ package.json                      type: module, no dependencies, node --test
├─ start.cmd                         double-clickable launcher
├─ src/
│   ├─ grammar.mjs                   question-grammar parser + gate evaluator + reachability
│   ├─ graph.mjs                     mermaid subset -> graph model
│   ├─ store.mjs                     durable answer/annotation store
│   ├─ registry.mjs                  discover <project>/design/<slug>/ across the repo
│   └─ server.mjs                    static hosting + JSON API (serve.mjs is the model)
├─ web/                              the browser app, plain ES modules, no build step
│   ├─ index.html  question.html  canvas.html
│   └─ *.mjs  *.css                  imports src/grammar.mjs directly — ONE parser
└─ test/                             node --test

solatro/design/spotlight/            A DESIGN (beside the code it describes)
├─ DESIGN.md              agent   the questionnaire + flowcharts (moved from SPOTLIGHT_DESIGN.md)
├─ meta.json              agent   slug, title, projects touched, versions
├─ graph.json             agent   generated from DESIGN.md's mermaid blocks
├─ status.agent.json      agent   whose turn it is — agent half
├─ ASSUMPTIONS.md         agent   execution-time assumptions
├─ gaps/GAP-NNN.md        agent   filed by executing agents
├─ versions/NNN/          agent   frozen at Confirm
├─ answers.json           UI      materialised current answers
├─ answers.log            UI      append-only event log; answers.json is rebuildable from it
├─ annotations.json       UI      node/edge notes + per-node approval
├─ ui_meta.json           UI      archived flag, last opened
└─ status.owner.json      UI      whose turn it is — owner half
```

**Every file has exactly one writer.** That is the concurrency design in full: no locks, no merges,
no read-modify-write of a shared file. Note `status` is **two files, not one** — a single
`status.json` with a field per side would still be a shared read-modify-write, which is the thing
being avoided.

`web/` importing `src/grammar.mjs` directly is the whole reason the runtime is Node — one parser,
two callers, no drift.

---

## 3. Phases

Ordered so that **stopping after any phase leaves something that works.** Phase 1 alone already
replaces the chat questionnaire.

### Phase 0 — foundations

**S1 — project skeleton and server.** *(implements A4, I2, I3)*
`package.json` (`type: module`, no dependencies, `"test": "node --test test/*.test.mjs"`),
`src/server.mjs` doing static hosting + JSON API + `/api/ping` + `/api/shutdown`, loopback-only, and
`start.cmd`. Copy the port-reclaim pattern from `palette/tools/serve.mjs` rather than reinventing
it. Add a `designloop` entry to `.claude/launch.json` (`runtimeExecutable: "npm"`,
`runtimeArgs: ["--prefix","designloop","start"]`, `autoPort: true`) so the Browser pane can drive it.
**Done when:** the server starts, serves a placeholder page, `/api/ping` answers, a second launch
reclaims the port.

**S2 — the grammar module.** *(implements C1–C11, and §0's grammar)*
`src/grammar.mjs`: parse one question line into `{id, gate, text, options[{letter,label,consequence}],
default, notes, isGate, nextPreviews}`; parse section headings and their gates; evaluate gate
expressions (`[root]`, `=`, `≠`, `|`, `&`); compute `REACHABLE` / `PENDING` / `PRUNED` per C7/C10.
Pure, no I/O, no DOM — so it runs identically in `node --test` and in the browser.
⚠ **The acceptance test is `solatro/SPOTLIGHT_DESIGN.md` parsing unchanged** (Q89=a): 188 questions,
8 gates, every section gate, zero parse errors, and a reachability run that reproduces the
documented "longest path ~150". If it does not parse, the grammar is wrong, not the document.
**Done when:** that file parses clean and the DAG validator reports no unreachable question, no
cycle, and no gate referencing an option letter that does not exist.

**S3 — registry and index.** *(implements H1–H4, Q102, Q103, Q106, Q107)*
`src/registry.mjs` scans sibling project directories for `design/*/meta.json`; a design lists the
projects it touches and appears under each; slug + human title; rename and archive, never delete.
**Done when:** the index page lists every design with project, title, status, last touched.

### Phase 1 — the questionnaire (the usable milestone)

**S4 — the store.** *(implements B12, Q80, Q81, Q82, Q108, Q35)*
Append to `answers.log`, rewrite `answers.json` via temp+rename, `fsync` both, then respond. Answer
records carry `state: chosen | not_relevant | defaulted`, the chosen letter, free text, and an
`active` flag for stranding. `answers.json` is always reconstructible from the log.
**Done when:** a kill -9 between log append and materialise leaves a state the loader recovers from,
proven by a test that simulates it.

**S5 — the question screen.** *(implements B6, B7, B7a, B7b, Q11, Q12, Q14, Q17, Q17b, Q17c, Q17d, Q26)*
One question, options prefilled with consequences, recommendation marked but **not** pre-selected,
free-text box, NOT RELEVANT button, expandable "asked because…", `→ next` previews on gates only,
**nothing indicating progress**. Ordering: document order within a section, sections by gate weight.
**Done when:** driving it in the Browser pane shows Spotlight's QR1 with all its options, its
consequences and its branch previews, and answering it prunes §17.2 from the reachable set.

**S6 — input parity and Enter-to-default.** *(implements Q13, Q108–Q113)*
Arrow keys move a visible focus ring, Enter picks the focused option, letter keys jump, everything
is a click target. Enter on an unfocused question accepts the default and advances, recording
`defaulted` — but **stops at ⚑gate and `notes` questions**, and on stopping shows "you accepted N
defaults" with a click-back list.
**Done when:** hammering Enter from QR1 halts at the next gate, and the accepted list is accurate.

**S7 — back, history, re-answering.** *(implements D1–D9, Q33, Q34, Q35, Q36b)*
BACK plus a clickable history list. Changing an answer previews the blast radius ("this makes 14
answers irrelevant — continue?") before applying; stranded answers go inactive, not deleted, and
restore intact on return.
**Done when:** answering QR3=(a), then several canvas questions, then re-answering QR3=(b), strands
them with a warning — and re-answering (a) brings them all back.

**S8 — round handshake and gate override.** *(implements B15, B17, P1–P8, E2, E9, E10, Q28, Q29)*
`status.json` with `owner_state` (UI-owned) and `agent_state` (agent-owned). Last reachable question
answered → `owner_state = done`. Free text at a gate → `owner_state = done, reason =
new_branch_needed`, immediately. DONE screen waits and switches itself over when `agent_state`
flips. Round 2+ opens with a short summary of what opened the new questions.
**Done when:** both endings write the right status and the DONE screen self-transitions.

> **Stopping here yields a working tool.** Everything after this is the review half.

### Phase 2 — the agent loop

**S9 — the watch.** *(implements E4, E5, E7, E9, Q20, Q21, Q23)*
A documented procedure plus a small `npm run watch -- <design>` that blocks until `owner_state`
changes and prints what happened, so an agent session can park on it. The chat fallback ("I'm done")
needs no code and must stay documented as always-valid.
⚠ This is the one mechanism with **no precedent in this repo** — build it last in the phase, test it
by hand, and if the blocking watch proves flaky the fallback already covers it.
**Done when:** an agent parked on the watch wakes within a second of the last answer.

**S10 — skill wiring.** *(implements A2–A4, Q91)*
`.claude/skills/flowchart-design/SKILL.md` gains the concrete handover: where to write the design,
how to start the server, what URL to hand over. The skill must keep working with the tool absent —
markdown remains answerable in chat.
**Done when:** a dry run of the skill produces a design directory the index picks up.

### Phase 3 — the canvas

**S11 — graph ingestion.** *(implements G2, F12, F14, Q64)* — **re-derived, design v3 (GAP-002)**
`src/graph.mjs` reads the design doc's ```mermaid blocks into `{nodes, edges, chart}` with IDs
preserved. **Restrict to a documented subset** (`ID["text"]`, `-->`, `-- label -->`, `{decision}`)
and **fail loudly** on anything outside it rather than guessing.
⚠ Riskiest step in the plan: mermaid is loose and the existing docs use several node shapes.
Validate against all 14 Spotlight charts and all 11 of this document's before declaring it done.

Ingestion also **derives the cross-chart links** exactly as §6.1 specifies, and carries each chart's
`name` (§4.6) because resolution needs it. Warnings — unresolved references — are **returned beside
the graph, never thrown**: an unresolved `chart Z` is an authoring defect in a document that is
otherwise fine, and the GAP-001 rule already decided that class of thing warns rather than blocks.
**Done when:** every chart in both design docs ingests with zero unknown constructs, **and** the
link counts of §6.1's fixture table reproduce exactly — 10 here, 4 in Spotlight, 0 unresolved in
both — with neither document edited to make it so.

**S12 — canvas render.** *(implements F2, F8, F13, Q52, Q53, Q63, Q66)* — **re-derived, design v3 (GAP-002)**
Whole graph at once, collapsible subgraphs (one per chart), auto layout, pan/zoom, desktop-only,
colour by chart or by status (switchable). Layout must be deterministic for a given input so a
frozen version reproduces.
⚠ Layout is the one place a dependency is defensible (Q100 allowed vetted ones). Try a hand-rolled
layered layout first — these graphs are small and mostly a DAG of ~20 nodes per chart; reach for a
library only if it visibly fails, and record the measurement either way.

**Cross-chart links are drawn in the whole-graph view** (F13). They are what that view is *for* —
without them it was, in the owner's words on review, worse than the picker. Requirements:

- **Dashed, and visibly not an edge.** A reader must never have to work out which of the two they
  are looking at.
- **Node to chart**, terminating on the target chart's frame or title, not on a node inside it. The
  document named a chart; picking an endpoint would invent structure.
- **A collapsed chart keeps its links** (F8), re-anchored to the collapsed box at both ends — that
  is the case where the links are most useful, because a collapsed whole-graph view is exactly the
  "how do these fit together" picture.
- **Not in the single-chart picker view**, or shown there only as a stub, since the other end is
  off-screen by construction.
- **Never routed through the layout's ranking.** Links do not create layers, do not affect
  positions, and must not be able to change a frozen layout. Layout runs on `edges`; links are drawn
  over the result.
**Done when:** Spotlight's ~200 nodes render legibly and pan/zoom smoothly, and this document's 10
links are visible, dashed, and still correct with every chart collapsed. **Verify by eye** — render
it and look at it (repo rule 4); a link count in the console is not evidence about the picture.

**S13 — annotations and side panel.** *(implements F5, F6, F7, Q55, Q56, Q57, Q58, Q116)*
Click a node or an edge, annotate it, saved with the same durability rule as answers. Side panel has
three sections: assumptions, out-of-scope, open notes. Assumptions list all three sources —
agent-declared, `defaulted`, `not_relevant` — visually distinguished.
**Done when:** an annotation survives a restart and appears in the panel.

**S14 — approval, Confirm, versions.** *(implements F10, F11, F14, G1–G3, Q59, Q60, Q61, Q62, Q65, Q71, Q72, Q115)* — **re-derived, design v3 (GAP-002)**
Per-node approve (a convenience, not a gate on Confirm). Confirm freezes `versions/NNN/` including
**layout and collapse state**, renders a generated `DESIGN.md` beside it, and leaves the working copy
editable. Node-level diff between versions. SVG and PNG export.

A frozen `graph.json` carries its `links` like any other part of the graph — that is the whole point
of putting them in the file rather than in the canvas (F14, Q64=a). Two consequences:

- **The diff reports links**, added and removed, in their own group and labelled as derived. A link
  that appears because a label was reworded is a real change to what the design claims, and it is
  also not an edge the author drew; both facts have to survive into the diff.
- **The generated `DESIGN.md` render (G3) does not draw links as mermaid edges.** The subset has no
  cross-chart arrow, and emitting one would produce a document this tool refuses to read. They
  belong in the render as prose beneath each chart — "chart D links to: E, C" — which is what the
  original labels said anyway.
**Done when:** two Confirms produce two frozen versions, the diff names exactly what changed
including link changes in their own group, reopening version 1 restores its collapse state, and the
generated `DESIGN.md` of any frozen version **re-ingests through S11 with zero errors**.

### Phase 4 — gaps, handoff, migration

**S15 — the gap surface.** *(implements J8–J17, Q86–Q97b)*
Read `gaps/*.md`, badge the index (Q89b=c), offer a **scoped** round built from a gap's own options,
mark plan steps citing changed nodes as stale, keep closed gaps with their resolutions. Promoting an
assumption to a gap marks dependent steps stale (Q95b=a).
**Done when:** a hand-written gap file appears as a badge and generates a one-question scoped round.

**S16 — migrate Spotlight.** *(implements Q104, and it is the real load test)*
Move `solatro/SPOTLIGHT_DESIGN.md` → `solatro/design/spotlight/DESIGN.md`, write its `meta.json`,
ingest its charts, and open it in the tool. **Do not edit the document to make it parse** — if it
does not, S2 or S11 is wrong.
**Done when:** Spotlight's 188 questions are answerable in the tool end to end.

**S17 — docs pass.** *(project rule)*
`designloop/README.md` (what it is, how to start it), the skill updated, `ARCHITECTURE.md` if the
tool grows contracts worth pinning, and memory updated. Fold nothing from the design doc — it stays
as the authority.

### Phase 5 — what the owner found by using it

**S18 — the canvas review.** *(implements F2–F11, and design version 3)*
The owner drove the built canvas on 2026-08-02. Six defects fixed inline as look decisions (§10
gives the implementer that latitude), and one filed as **GAP-002**, because whether a prose
reference becomes a drawn link changes `graph.json` and is not an implementer's call. Its answer is
design version 3 and the re-derivation of S11, S12 and S14.
**Done when:** every finding is either fixed or filed. Both, done.

**S19 — the answering-screen review.** *(implements B18, B19, B20, D10–D14, E12–E16 — design version 4)*
The owner drove the question screen on 2026-08-03. Seven findings, none of them reversing a settled
answer, all of them decisions this design had made and the screen had never shown:

1. **History is a sidebar** (D14) — scrollable, always on screen, carrying the question **and** the
   answer. It replaces the button and the screen it opened.
2. **BACK is a visit stack** (D10–D13) — the questions this screen has shown, in order, in
   `sessionStorage` so that leaving for the canvas and coming back does not reset it. Fallback with
   nothing above the current question: the question answered **immediately before** it, never the
   newest answer, or BACK would run forwards at the start of a round. Nowhere to go → **disabled,
   with the reason in its tooltip**. It never navigates to the index.
3. **Every control carries its key, and shows it** (B20). Option letters own their own keys; an
   action whose mnemonic an option has claimed has **no** key on that question rather than a
   silently rebound one. A legend is rendered from the same map the handler reads, so it cannot
   drift from what the keys do.
4. **Enter's target is marked before it is pressed** (B18). Exactly one control at a time. Q12 and
   Q108 survive: the mark where it was **put** answers `defaulted`, the mark the owner **moved**
   answers `chosen`.
5. **Typing moves the mark to "use what I wrote"** (B19), and the note rides along with every
   answer including a defaulted one. Drafts are kept per question until committed.
6. **`session.json`** (E12–E16, §4.9) — the watch's heartbeat, three readings, a copy-paste prompt
   when nothing is listening, and the standing truth that no answer depends on it.

**Done when:** all six behave as described, driven in a real browser, **and** the four that a test
can hold are held by one: the heartbeat reads live, a killed watch reads as *stopped*, a clean exit
reads as *none*, and a design nobody ever watched is never reported as a session that died.
⚠ **Verify by eye** (repo rule 4): every one of these findings is about what the screen shows, and
not one of them would have been caught by a passing test.

---

## 4. Interchange contracts

These are the file formats. **Do not invent them at implementation time** — every one of them is
read by at least two of {parser, store, UI, watch loop, version freeze}, and a divergence here is
silent (each side round-trips its own writes fine) and expensive to unpick later.

All JSON is written **temp-file + `fsync` + `rename`**, UTF-8, 2-space indent, keys in the order
given. ISO-8601 UTC timestamps.

### 4.1 `meta.json` — agent-owned

```json
{
  "slug": "spotlight",
  "title": "The Spotlight mechanic and its visual effects",
  "projects": ["solatro"],
  "doc": "DESIGN.md",
  "created": "2026-08-01T00:00:00Z",
  "rounds": 2,
  "confirmed_version": null
}
```

`projects` is an array because a design may span several (Q103=a); it appears under each in the
index. The design's **key** everywhere in the API is `<first project>/<slug>`.

### 4.2 `status.owner.json` / `status.agent.json`

```json
{ "state": "answering" | "done", "reason": null | "complete" | "new_branch_needed",
  "round": 1, "at": "2026-08-01T00:00:00Z" }
```

```json
{ "state": "idle" | "working" | "ready", "mode": "questions" | "review",
  "round": 1, "at": "2026-08-01T00:00:00Z" }
```

The handshake in full: UI sets owner `done` (with `reason`) → agent sees it, sets `working` → agent
finishes, sets `ready` + `mode` + incremented `round` → UI sees it, switches screen, sets owner
`answering`. `reason: "new_branch_needed"` is the free-text-at-a-gate case (chart B2) and is the
only one that can arrive with reachable questions still unanswered.

### 4.3 `answers.json` — UI-owned

```json
{
  "slug": "spotlight",
  "doc_hash": "sha256:…",
  "updated": "2026-08-01T00:00:00Z",
  "answers": {
    "QR1": { "state": "chosen", "option": "a", "note": "", "override": false,
             "active": true, "round": 1, "at": "2026-08-01T00:00:00Z" }
  }
}
```

| Field | Meaning |
|---|---|
| `state` | `chosen` (deliberate), `not_relevant` (button — records the default, Q17b=a), `defaulted` (Enter-hammered, Q12) |
| `option` | the letter, or `null` when `override` is true |
| `note` | free text, may accompany any state |
| `override` | true = free text **instead of** choosing. On a `⚑gate` question this ends the round |
| `active` | false = stranded by a changed upstream answer. **Never deleted** (Q35=a) |
| `round` | which round it was answered in |

`doc_hash` is the SHA-256 of `DESIGN.md` at the last successful parse. If it differs on load, the
questionnaire changed under the answers and the agent must reconcile before asking anything else.

### 4.4 `answers.log` — UI-owned, append-only JSONL

One event per line, `seq` strictly increasing. Replaying in `seq` order reproduces `answers.json`
exactly — that is the recovery contract, and the test for S4.

```json
{"seq":1,"at":"…","event":"answer","id":"QR1","state":"chosen","option":"a","note":"","override":false}
{"seq":2,"at":"…","event":"strand","ids":["Q73","Q74"],"cause":"QR2","active":false}
{"seq":3,"at":"…","event":"restore","ids":["Q73"],"cause":"QR2","active":true}
```

Order of operations per answer: append to log → `fsync` → rewrite `answers.json` → `fsync` → **then**
respond 200. A crash between the two leaves the log ahead of the materialised file, which the
replay-on-load resolves.

### 4.5 `annotations.json` — UI-owned

```json
{
  "nodes":    { "D6":       [ { "at": "…", "text": "…" } ] },
  "edges":    { "D6->D7":   [ { "at": "…", "text": "…" } ] },
  "approved": { "D6":       { "at": "…", "version": 0 } }
}
```

Edge key is `FROM->TO`, suffixed `#1`, `#2`… when a pair has several edges, in the order they appear
in the source chart.

### 4.6 `graph.json` — agent-owned, generated from `DESIGN.md`

```json
{
  "doc_hash": "sha256:…",
  "charts": [ { "id": "D", "name": "D", "title": "ONE LINE'S SPOTLIGHT PHASE", "nodes": ["D1","D2"] } ],
  "nodes":  { "D1": { "chart": "D", "label": "…", "shape": "box", "new": true, "decidedBy": ["Q31"] } },
  "edges":  [ { "key": "D1->D2", "from": "D1", "to": "D2", "label": "" } ],
  "links":  [ { "key": "D8~>E", "from": "D8", "fromChart": "D", "toChart": "E", "ref": "E", "line": 376 } ]
}
```

`shape` is `box` or `decision`. `new` is true when the label carries the `NEW:` marker.
`decidedBy` lists question IDs mentioned in the node's label or in the prose immediately following
its chart — best-effort, and the source of the "which question decided this" panel (Q55=a).

`name` is what the document **calls** the chart — the `X` in a `Flowchart X — …` heading — which is
not always its ID: the chart headed *Flowchart B2* has `P`-prefixed nodes, so `{ "id": "P", "name":
"B2" }`, and in Spotlight the chart headed *Flowchart H* is the one with `I`-prefixed nodes. A
heading names the **first** chart under it and no other; every later chart under that heading has
`name: null`, which is also what a chart with no heading above it gets. It never falls back to the
ID — see §6.1 for why a fabricated name is worse than none. `name` exists so §6.1 can resolve a
reference the way a reader does.

`links` is the derived cross-chart links (§6.1, design F12–F14, GAP-002). It is a **separate list
from `edges` and must stay separate**: an edge was drawn by the author, a link was inferred from a
label, and a consumer that cannot tell them apart will assert a connection the document never made.
`key` is `FROM~>TOCHART` — `~>` rather than `->` so a link key can never collide with an edge key in
`annotations.json` — and it is **unique**: one node naming the same chart twice in one label (chart
D's `D8` does exactly that) is one link, the first occurrence, not two. Repetition in prose is not a
second connection. `ref` is the text as written (`E`, `B2`), kept so an error message can quote the
document. Links are **not** annotatable and **not** approvable in v1: they are derived, so there is
nothing on them the owner could be reviewing that is not already in the label.

### 4.7 `versions/NNN/` — agent-owned, immutable once written

```
versions/003/
├─ graph.json          copy, frozen
├─ layout.json         positions + collapse state + viewport (Q115=b)
├─ answers.json        copy, frozen
├─ annotations.json    copy, frozen
├─ DESIGN.md           generated human-readable render (Q71=a)
└─ changelog.md        nodes added/changed/removed, questions added, gaps closed
```

```json
{ "engine": "layered-v1", "positions": { "D1": { "x": 0, "y": 0 } },
  "collapsed": ["E","F"], "viewport": { "x": 0, "y": 0, "zoom": 1 } }
```

`engine` is recorded so a later layout change cannot silently re-flow a frozen version.

### 4.9 `session.json` — agent-owned, written by the watch (design E12–E16)

```json
{ "watching": true, "key": "solatro/spotlight", "pid": 12345,
  "since": "2026-08-03T00:31:57Z", "at": "2026-08-03T00:34:18Z", "every_ms": 5000 }
```

A **heartbeat**, not a state. `watch.mjs` rewrites it every `every_ms` while it is parked, and once
more with `watching: false` if it gets to exit cleanly. One writer, like every other file here.

**Staleness is the signal.** A reader treats the session as live only while
`now - at <= max(every_ms × 4, 3000 ms)`. The 3-second floor is not a fudge: `now()` writes
timestamps to the **second**, so any window shorter than that is measuring rounding and would report
a healthy watch as a dead one. Three situations, and they are three different sentences to the
owner:

| File | Reading | What the screen says |
|---|---|---|
| absent | nobody has ever watched | "no agent is watching" — and what that does not cost |
| `watching: true`, fresh | parked | "an agent is watching", since when |
| `watching: true`, stale | **it died without tidying up** | "the session stopped" — plus a prompt to paste |
| `watching: false` | it exited cleanly | "no agent is watching" |

The stale row is the one this file exists for. A killed process, a crashed one, or a chat session
that simply ended never gets to write anything; only the absence of a further beat reports it.

⚠ **Nothing about answering depends on it.** Every answer is fsynced before the next question
appears, and any session reads them all afterwards (Q22=a). This file decides what the screen
*says*, never what is *safe* — and the screen has to say so, or a missing session reads as lost work.

### 4.8 HTTP API

`:key` is `<project>/<slug>`. Everything is JSON except static assets. Loopback callers only.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/designs` | the index (H3): key, title, projects, status, counts, gap badge |
| GET | `/api/designs/:key` | meta + both status halves + `session` (§4.9). `?poll=1` for the answering screen's "is anyone watching yet?" — same body, but it does **not** count as the owner opening the design, so a poll every few seconds cannot rewrite `ui_meta.json` or keep waking the watch's directory watcher |
| GET | `/api/designs/:key/next` | the next reachable question, or `{done:true}` |
| GET | `/api/designs/:key/history` | answered questions in answer order (Q33=a) |
| POST | `/api/designs/:key/answer` | `{id,state,option,note,override}` — 200 **only after fsync** |
| POST | `/api/designs/:key/reanswer?preview=1` | blast radius without applying (Q34=a) |
| POST | `/api/designs/:key/reanswer` | apply, stranding/restoring as needed |
| GET | `/api/designs/:key/graph` | `graph.json` |
| POST | `/api/designs/:key/annotate` | `{target:"node"\|"edge", key, text}` |
| POST | `/api/designs/:key/approve` | `{node}` |
| POST | `/api/designs/:key/confirm` | freeze the next version |
| GET | `/api/designs/:key/versions` · `/versions/:n` · `/diff?a=1&b=2` | history (Q62=a) |
| GET | `/api/designs/:key/gaps` | open + closed gaps |
| GET | `/api/ping` · POST `/api/shutdown` | port reclaim, as `palette/tools/serve.mjs` does |

---

## 5. The question grammar, formally

`src/grammar.mjs` implements exactly this. The prose version lives in
`.claude/skills/flowchart-design/SKILL.md`; **this is the normative one** and the two must agree.

### 5.1 Question line

```
- **<ID>** `<gate>` [⚑gate] — <text> · <option> [· <option>…] · *default* (<letter>) [· notes] [⇒ <hint>]
```

| Token | Pattern / rule |
|---|---|
| `ID` | `QR\d+` or `Q\d+[a-z]?` (the `b` suffix exists to avoid renumbering — `Q88` and `Q88b` are different questions) |
| `gate` | backticked; `[root]` or an expression (§5.2) |
| `⚑gate` | optional marker; when present every option **must** contain a `→ next:` clause, and the parser errors if one does not |
| `text` | everything up to the first ` · `; may contain inline markdown (Q19=a) |
| `option` | `**(<letter>)** <label>` where `<label>` may contain ` — <consequence>` and ` — **→ next:** <preview>` |
| `default` | `*default* (<letter>)`; the letter must be one of the options |
| `notes` | optional literal `notes` |
| `⇒ hint` | optional human hint; never parsed for meaning |

Separator is ` · ` (space, U+00B7, space). Retired questions take one of two forms and are recorded
as `retired` with no options:

```
- **Q140** — *superseded by QR5. Not asked.*
- **Q15** — *settled: a free-text box is on every question, always. Not asked.*
```

### 5.2 Gate expressions

```
gate    := "root" | conj
conj    := atom ( " & " atom )*
atom    := ID ( "=" | "≠" ) letters
letters := letter ( "|" letter )*
```

`|` binds **inside one atom's letter list only** — `[Q4=b|c]` means "Q4 is b or c". There is no
cross-question `or`; every gate written in either design doc obeys this. A gate naming a letter that
the referenced question does not offer is a **hard parse error**, not a warning.

### 5.3 Section gates

`### 17.4 The reveal \`[QR4=a]\`` — a backticked gate at the end of a heading applies to every
question under it, ANDed with each question's own gate.

### 5.4 Reachability

Per chart C. Three states, and the middle one is the reason this is a DAG rather than a tree:

- **REACHABLE** — unanswered, gate is `root`, or every referenced ID is answered and the gate is true.
- **PENDING** — unanswered, and some referenced ID is not yet answered. Not askable, not pruned.
- **PRUNED** — unanswered or answered, every referenced ID answered, gate false. An existing answer
  is marked `active: false`, never deleted.

### 5.5 Ordering

Q11=c: document order within a section; sections ordered by **gate weight** — the number of
questions a section's gate-referenced questions transitively prune, descending. Ties keep document
order.

### 5.6 Test corpus

`test/grammar.test.mjs` covers, one case each: `[root]`; `[Q4=b]`; `[Q4=b|c]`; `[Q4=b & Q9=a]`;
`[Q7≠c]`; a `⚑gate` with `→ next:` on every option; a `⚑gate` missing one (must throw); a gate
naming a nonexistent letter (must throw); both retired forms; a section gate; an option whose
consequence contains a ` — ` of its own; an option list of four.

**And the acceptance test** — ⚠ **the numbers below are MEASURED (2026-08-01), replacing a hand
estimate that was wrong in two places.** `solatro/SPOTLIGHT_DESIGN.md` parses **unedited** to:

```
196 question lines   = 188 Q-numbered + 8 QR root gates
195 live, 1 retired  (Q140, retired in place)
8 ⚑gate, 39 notes
opens at QR1 · 0 errors · 1 warning (QR8, GAP-001)
```

and the DAG validator reports no cycle, no gate naming an undefined ID or letter, and nothing
unsatisfiable. The original wording — *"188 questions, 8 of them `QR*`"* — cannot be true of that
document: it is 188 **plus** 8. The **longest path is 194 of 195**, not the ~150 originally
estimated, because exactly one pair in the DAG is mutually exclusive (Q118 `[Q113=a]` against
Q114 `[Q113=b|c]`).

⚠ **The general lesson, worth carrying into every future questionnaire:** gate weight only pays off
when a root's *default* is the pruning branch. Spotlight's eight roots all default to "include this
sub-feature", so the all-defaults path answers nearly everything. The DAG's value is amputating a
sub-feature in one click, not shortening the common path.

---

## 6. The mermaid subset

`src/graph.mjs` accepts exactly this and **throws on anything else, naming the file and line**.
Guessing is what turns a diagram change into a silently wrong graph.

```
flowchart TD
  A1["label text"]                      box node
  A2{"label text"}                      decision node
  A1 --> A2                             plain edge
  A1 -- "edge label" --> A2             labelled edge (quoted)
  A1 -- edge label --> A2               labelled edge (bare, no · or " in it)
  A1["label"] --> A2["label"]           inline declaration on an edge line
```

- Node IDs match `[A-Z]{1,2}\d+[a-z]?` (`A1`, `QR3`, `D10`, `B7a`).
- A quoted label may span source lines; the parser joins them with a single space.
- First declaration of an ID wins; a later bare reference reuses it; a **conflicting** re-declaration
  is an error.
- `flowchart TD` is the only accepted header. Subgraphs, styling, class defs, and other arrow kinds
  (`-.->`, `==>`) are errors — if a chart needs one, that is a plan change, not a parser change.
- Every chart's node IDs must share a prefix letter, which becomes the chart ID.

**Validation gate for S11:** all 14 charts in the Spotlight design and all 11 in this tool's design
ingest with zero unknown constructs. That is 25 real charts; if the subset cannot express them, the
subset is wrong.

### 6.1 Cross-chart links, derived (design F12–F14; GAP-002 = b)

Charts in this subset cannot point at each other — every edge is within one chart, and `validate()`
errors if one is not. The references exist anyway, written in prose inside labels
(`A6 "owner answers one question at a time — chart B"`). §6.1 reads them out. It is **derivation,
never authoring**: the document is not edited to gain links, and nothing is guessed.

**Extraction.** Over each node's label, every match of

```
/\bchart\s+([A-Z]{1,2}\d*)\b/g
```

The `\b` before `chart` is load-bearing: it is what stops `flowchart TD` matching. Case-sensitive.
Only node labels are scanned — not edge labels, not prose, not headings.

**Resolution**, in order, first hit wins:

1. `ref` equals some chart's `name` (§4.6) → that chart. *(`chart B2` → the chart with `P` nodes.)*
2. `ref` equals some chart's `id` → that chart.
3. `ref` is a node ID the graph declares → the chart that node belongs to. *(`chart E3` → chart E.)*
4. Nothing → **warning**, naming file, line, node and `ref`. Never a link.

Warnings are **reported, never stored**: they reach the author through `run check` and the index
badge (the surface GAP-001 built), and `graph.json` on disk stays exactly the §4.6 shape. A report
about a document is not part of the graph an implementation agent is promised.

⚠ **Name before ID is not a preference, it is the only correct order**, and the reason is worth
stating because it is invisible until it bites. Spotlight's §7 holds *two* charts, so from there on
every chart ID runs one letter ahead of the heading that names it: the chart headed *Flowchart H* is
the chart whose nodes are `I1`, `I2`… A reader writing `K14 "see chart H"` means the heading. ID-first
resolution would have linked it to chart `H` — a different chart, a wrong link, drawn as confidently
as a right one. Wrong links are worse than no links; that is the whole reason this gap was filed.

**Naming, therefore, is per heading, not per chart.** A heading names the **first** chart under it and
no other. The second chart in Spotlight's §7 has `name: null` and is reachable only by its ID. `name`
never falls back to the ID for the same reason — a fabricated name would land in the resolution
table and shadow a real one.

Then: **a link whose `toChart` is the source node's own chart is dropped, silently.** It is a
same-chart reference — Spotlight's chart E says `chart E2`, `chart E3`, `chart E4` about its own
nodes — and drawing it would be noise, not information. Dropping is silent because it is correct
authoring, not a defect.

Finally, **duplicates collapse**: one link per `(from, toChart)` pair, the first occurrence, per
§4.6.

**Ordering.** Source order: by chart as ingested, then by the node's declaration line, then by
position within the label. Deterministic, because a frozen version records this list (S14).

**Known result, measured 2026-08-02** — a regression fixture, not an estimate:

| Document | links | keys |
|---|---|---|
| `designloop/design/designloop/DESIGN.md` | **10** | `A6~>B` `A9~>E` `A14~>F` `A18~>G` `B3~>C` `B10~>D` `B17~>P` `B14~>D` `P5~>E` `F14~>G` |
| `solatro/design/spotlight/DESIGN.md` | **5** | `D8~>E` `D21~>E` `D25~>C` `K14~>I` `L11~>E` |

Unresolved: **0** in both. The three interesting rows, each of which is a rule earning its keep:
`B17~>P` came from `chart B2` (resolved by name); `K14~>I` came from `chart H` (the drift — ID
resolution would have said `H`); `L11~>E` came from `chart E3` (resolved through a node). Dropped as
same-chart: **3** in Spotlight, where chart E says `chart E2`, `chart E3` and `chart E4` about its
own nodes. Deduped: **1**, `D8`'s label naming chart E twice.

If a change to §6.1 moves any of these numbers, that is the change announcing itself. `run check`
prints `links N derived, M unresolved` and every unresolved reference by line.

---

## 7. Module APIs

Small enough to state, and stating them is what stops the browser and the server growing two
versions of the same logic.

**`src/grammar.mjs`** — pure, no I/O, imported by both server and browser:
`parseDocument(markdown) -> {questions, sections, errors}` ·
`parseQuestionLine(line) -> Question` · `parseGate(str) -> Gate` ·
`evaluateGate(gate, answers) -> "true"|"false"|"pending"` ·
`reachability(questions, answers) -> {reachable[], pending[], pruned[]}` ·
`nextQuestion(questions, answers) -> Question|null` (applies §5.5) ·
`blastRadius(questions, answers, id, newOption) -> {strand[], restore[]}` ·
`validate(questions) -> Error[]`

**`src/graph.mjs`** — `parseCharts(markdown) -> Graph` · `validate(graph) -> Error[]`

**`src/store.mjs`** — `load(dir) -> State` (replays the log) · `append(dir, event)` ·
`materialise(dir, state)` · `writeJsonAtomic(path, obj)` (temp + fsync + rename) ·
`answer(dir, record)` (the whole 4.4 sequence) · `annotate(dir, target, key, text)`

**`src/registry.mjs`** — `discover(repoRoot) -> Design[]` (scan `*/design/*/meta.json`) ·
`key(design)` · `rename(dir, title)` · `archive(dir, bool)`

**`src/server.mjs`** — routes of §4.8; loopback guard; static hosting of `web/`; ping/shutdown.

**`web/`** — plain ES modules, **no build step**, importing `../src/grammar.mjs` directly.

---

## 8. Verification

- **`npm --prefix designloop test`** after every step — `node --test`, no runner to install.
- **The Browser pane** for anything visible: `preview_start` the `designloop` launch config, drive it
  with `read_page` / `computer`, read `read_console_messages` for errors. Never ask the owner to
  check something the pane can show.
- **The parse acceptance test is the honest gate for Phase 0**: if `SPOTLIGHT_DESIGN.md` needs edits
  to parse, the grammar is wrong.
- **No git operations at any point** — the owner commits through GitHub Desktop.

## 9. Risks, named

| Risk | Mitigation |
|---|---|
| **Mermaid ingestion (S11)** — loose format, several node shapes in the existing docs | strict documented subset, fail loudly, validated against all 24 existing charts before it counts as done |
| **The watch loop (S9)** — no precedent in this repo | built last in its phase; the chat fallback is always valid and needs no code |
| **Grammar drift** — the tool and the doc disagreeing about what a question is | one parser module, imported by both server and browser; the Spotlight parse is the regression test |
| **Canvas layout at 200 nodes** | hand-rolled first, measured; a vetted dependency is permitted (Q100=a allows it under (c) semantics only — **treat adding one as a gap**, not a free choice) |
| **Scope: the canvas is roughly half the work** | phases are ordered so Phase 1 ships a usable tool; the canvas can slip without wasting anything |

## 10. What this plan does not cover

Multi-user, any host but localhost, and the tool authoring its own questions (all confirmed out of
scope, Q92–Q94).

**The visual design of the screens** — typography, spacing, colour, the look of the focus ring — is
not specified anywhere in this plan or in the design. Behaviour is fully specified; appearance is
not. That is a deliberate hole and it is the one place an implementer should expect to be inventing:
make it plain and legible, and if a look decision turns out to change behaviour (legibility of the
option list at 6 options, say), **file a gap** rather than deciding it.

Everything else an implementer needs is in §4–§7. If something is missing there, that is a defect in
this document, not a licence to invent — file a gap.
