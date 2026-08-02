---
name: flowchart-design
description: Turn a braindump into a reviewable flowchart design plan — numbered flowcharts covering 100% of a feature's behaviour, plus a BRANCHING questionnaire (a decision DAG, not a flat list) where each answer prunes the questions that just became irrelevant. Use when asked to "make this a flowchart design plan" or to run the flowchart questionnaire workflow, and before any feature large enough that a vague plan would leak decisions into implementation.
---

# Flowchart design plan

The owner braindumps a feature. This skill turns that into a document they can review **by
answering questions**, not by writing the design themselves. The bar:

> The owner should be able to review the whole plan without ever having to write "you forgot to
> ask about X". Every decision the implementation will face is either already made in the
> structure, or is a numbered question with a recommended default.

**This is a DESIGN artefact. No code, no file lists, no method signatures, no step ordering, no
test plan.** Those belong to a separate implementation plan written after every node is approved.
Mixing them is what makes a design doc unreviewable.

## Why this exists

A previous cycle (the Solatro FX editor) shipped from a plan that was not thorough enough, and the
gaps became decisions made silently during implementation. A design decision made by the
implementer is a design decision the owner never got to make.

---

## THE QUESTIONNAIRE IS ITSELF A FLOWCHART

**This is the load-bearing rule of the skill.** A flat list of 180 questions asks the owner to
answer questions that their own earlier answers already made meaningless. The questionnaire is a
**decision DAG**: every question carries a *gate* — the condition under which it is asked at all —
and answering one question prunes whole subtrees.

Two consequences:

1. **Order by gate weight, not by topic.** The first questions asked must be the ones that gate the
   most downstream questions. This is the binary-search property: a handful of root answers should
   eliminate a large fraction of the tree. Group headings still follow topic, but the ROOT section
   comes first and is explicitly labelled as such.
2. **It is a DAG, not a tree.** Branches converge: a question can be gated on `Q4=b OR Q9=c`, so the
   same question is reachable down several paths and is only written once.

### The four universal rules (they apply to every question, so they are never written on the line)

1. **Every option is prefilled and clickable.** The owner should be able to answer by clicking, not
   by composing prose. Prose is the escape hatch, never the expected path.
2. **Every option carries a short consequence** — what choosing it *does*, not a restatement of the
   label. `(a) yes` is useless; `(a) yes — the beam is literally on it, so blockers are ignored` is
   an answer someone can give without thinking about it for a minute.
3. **Every question offers free text** ("none of these — here is what I actually want"), and
   **every question offers *not relevant / not worth answering***, which records the default and
   marks it unreviewed. Neither is ever written on the line; both are always present.
4. **Every question is self-contained.** It is read alone, one per screen, with no document around
   it. If understanding it requires a section reference, a chart, or "the brief", **the question is
   broken** — inline whatever it needs, even if that repeats a paragraph from §1. Verbosity in a
   question is much cheaper than the owner having to go and look something up.

### Question grammar (one line per question, strict)

```
- **Q57** `[gate]` — self-contained question text? · **(a)** option — consequence · **(b)** option — consequence · *default* (b) · notes
```

| Part | Rule |
|---|---|
| **ID** | `Q1`, `Q2`, … stable forever. Root-level gates use `QR1`, `QR2`, … Never renumber; retire an obsolete question in place. |
| **gate** | Backticked. `[root]` = always asked. `[Q4=b]` = only if Q4 was answered b. `[Q4=b\|c]` = b or c. `[Q4=b & Q9=a]` = both. `[Q4≠a]` = anything but a. Omitting the gate is an error — write `[root]`. |
| **text** | One decision, self-contained per rule 4. If it contains "and", split it into two questions. |
| **options** | Lettered `(a) (b) (c)…`, even for yes/no. Each carries its consequence per rule 2. Multiple choice beats binary wherever a third answer is genuinely possible — a forced binary is how a real option gets lost. |
| **default** | Exactly one letter. Every question has one, so *default* is a complete answer. |
| **notes** | Marks a fork where the options are especially likely to be insufficient. Free text is available everywhere regardless; this is a hint to the owner that it is expected here. |
| **⇒** | Forward hint: `⇒ skips Q40–Q52`. The gates are the truth; this is a convenience. |

### Gating questions carry a preview of what comes next

A **gating question** is one whose answer prunes other questions. Mark it `⚑gate` and give every
option a short **→ next:** preview of the kind of questions that follow it.

```
- **QR3** `[root]` ⚑gate — Beams, or circles only? · **(a)** beams and circles — → next: beam shape, origin placement, overlap behaviour · **(b)** circles only — → next: nothing about beams; straight to the card glow · *default* (a)
```

Why: at a gating question the owner is choosing a *path*, not just an answer, and choosing a path
blind is how a questionnaire produces a design nobody wanted. The preview is what makes the choice
informed.

**Free text at a gating question cannot be routed** — there is no path for an answer the DAG does
not know about. So a free-text answer at a `⚑gate` question **ends the round immediately** and
returns to the agent to author the new branch, rather than being queued until the rest of the
questions are answered. Design for that: keep `⚑gate` questions few, put them early, and make their
option sets genuinely exhaustive.

### Root questions

Open the question section with a short **§ Root forks** group: the 4–8 `⚑gate` questions that gate
whole sections. Typical shapes:

- "Does this mechanic have gameplay effect at all, or is it purely presentation?"
- "Does sub-feature X exist in v1, or is it deferred?"
- "Which of these two incompatible readings of the braindump is the real one?"

Each must state **what it prunes** (`⇒`) and **what follows each option** (`→ next:`).

### Terminal groups

End with an **out-of-scope confirmation** group — adjacent things the owner might have assumed were
included. Confirming an exclusion is cheap; discovering one late is not.

---

## The procedure

### 1. Research first — the plan is built on code, not on docs

Before writing a single node:

- **Find every existing name for the thing.** The braindump uses the design word; the code often
  uses an older one (Solatro's "spotlight" is `active`/`is_active` in the source). Grep for both.
- **Read the actual call chain end to end** and pin `file.gd:line` for every claim. Docs go stale;
  code wins.
- **Measure the geometry / numbers the design depends on** and write them down with their
  derivation. A design that says "reveal the card" is unreviewable; one that says "the card is
  125 px tall and only its top 45 px shows" is reviewable.
- **Find the precedents.** Whatever the feature needs, something adjacent probably already does a
  version of it. Name it — it makes the design concrete and it is the honest baseline.
- **Read the project's contracts** (rulings, layering, palette, persistence, testing) and note every
  one the feature touches. Rulings the design must obey are facts, not questions.

Put all of this in a §1 "Audit facts" section with line references. Everything downstream cites it.

### 2. Build the state model before the flowcharts

Name the independent facts the feature introduces and where each lives (derived / persisted /
view-only). Most feature confusion is two facts that were never separated. Do this in a table.

**Fill in the structure yourself.** The owner answers behaviour and appearance questions, not
architecture ones. If a structural choice has a behavioural consequence, ask about the
*consequence*, not the structure.

### 3. Write the design flowcharts

- **Mermaid, in fenced ```mermaid blocks.**
- **Every node gets an ID** (`D4`, `G12`). The owner reviews by ID. Without IDs the review has no
  addresses.
- **Mark new nodes `NEW`**, and name existing nodes with their **real function**
  (`Game.score_line`). The chart should read as a diff against reality.
- **One chart per concern**, not one giant chart.
- **Over-decompose.** A step that "obviously" has no decision in it is a step the owner cannot point
  at when it turns out to have one.
- **Draw unresolved forks as explicit option branches**, recommendation marked, cross-referenced to
  the question ID that decides them.

### 4. Enumerate every usage

One row per situation the feature can be in — including the boring ones (headless, empty case,
single-element case, every screen it can appear on, undo, resume, settings changed mid-flight).
Each row points at the chart or question that covers it. State plainly: *if a usage is missing,
that is the most valuable thing you can report.*

### 5. Write the branching questionnaire

Per the grammar above. Additional rules:

- **Assign every question a gate before writing its text.** If you cannot state the gate, the
  question is either a root or it is really two questions.
- **Sanity-check the DAG**: no question gated on an answer that no option produces; no cycles; every
  question reachable from at least one root path; every option of every question leads somewhere
  (even if only to the end).
- **Re-read every question alone** — cover the rest of the document and ask whether it is still
  answerable. That is rule 4, and it is the one that quietly fails: a question written while the
  audit facts are fresh in your head reads fine to you and is unanswerable in isolation.
- **Audit the option sets at `⚑gate` questions hardest.** A missing option there costs a whole
  round-trip, because free text at a gate ends the round.
- **Answers must be revisitable.** The owner can go back to any earlier question and change it,
  which may send them down a different path; answers stranded on the abandoned path are marked
  inactive, never deleted, and are restored if they come back. Say so where the questionnaire is
  presented.
- **Count the worst path, not the total** — and **measure it, never estimate it.** Report "196
  lines, longest path 194". ⚠ A hand estimate of Spotlight's was wrong by 44 (2026-08-01: guessed
  ~150, measured 194), because path length is a property of the whole DAG and intuition is bad at it.
- ⚠ **Gate weight only pays off when a root's DEFAULT is the pruning branch.** Spotlight's eight
  roots all default to "include this sub-feature", so the all-defaults path answers nearly
  everything and the DAG saves the owner nothing on the common route. That is not a defect — the
  value is amputating a whole sub-feature in one click — but **say so plainly** where the
  questionnaire is introduced, rather than advertising a short path the owner will not get. If you
  want the common path genuinely shorter, the roots have to be framed so that the *expected* answer
  prunes, which usually means asking "is X in v1?" rather than "do you want X?".

### 6. Ship a tunables section

Every number the feature introduces, in the project's canonical tuning home, with a suggested
starting value and what it means.

### 7. Header, footer, and the gap protocol

- Open with **"How to review this document"**: IDs, the *default* convention, how gates prune, what
  "a step is missing" feedback looks like, and that nothing is implemented until every reachable
  node is approved.
- Close with **"What this document deliberately does not contain"**.
- **Include the gap-protocol block below, verbatim.** It is what lets execution get back here.

---

## The gap protocol — how execution reports design space the plan does not cover

A design plan is a claim about completeness, and every such claim is eventually wrong. Without a
route back, an implementing agent that hits uncovered ground does the worst available thing: it
decides, quietly, and the owner finds out from the diff. This protocol is the route back.

### Two requirements on the documents

1. **Every execution-plan step cites the design node IDs it implements** (`Step 4 — implements D6,
   D7, I10`). Without that citation there is no blast radius: nothing can say which steps a changed
   design node invalidates. Enforce it when the execution plan is written, not later.
2. **The propagation block travels.** It goes in the design doc, is copied verbatim into the
   execution plan, and into the handoff doc, and into anything derived from those in turn — the
   block says so itself. A fresh agent with no memory of this skill gets the protocol in the only
   document it is guaranteed to read.

### The triage an executing agent runs

Not everything uncovered is a blocker; stopping for each one is as bad as deciding for each one.

| Verdict | Test | Action |
|---|---|---|
| **COVERED** | the design answers it | do it |
| **ASSUME** | uncovered, but reversible and clearly within the design's intent | do it, append one line to the assumptions log citing the node — never silently |
| **GAP** | uncovered **and** any of: two defensible choices differ in observable behaviour; the choice is expensive to reverse (data/save format, a public seam, art direction); it is a class the project reserves for the owner (balance, look, scope) | park that thread, file a gap, keep working on unaffected threads, tell the owner |
| **CONTRADICTION** | the design says two incompatible things, or says something the code makes impossible | always a gap, highest priority — the design is wrong, not merely incomplete |

### The gap report is a draft question

This is what makes escalation cheap: a gap is filed **in the questionnaire grammar**, so its options
drop into the next round unchanged. One file per gap:

```markdown
# GAP-007 — <one-line title>
status: open | questioned | resolved | withdrawn
raised: <date>, during <execution plan step>
design: <doc> version <N>, nodes <D6, I10>
severity: GAP | CONTRADICTION

**What the design says** — <quote it, cited>
**What it does not say** — <the decision that has to be made, stated as a decision>
**Why it blocks** — <which triage test it meets, concretely>
**Options I can see** — **(a)** … — consequence · **(b)** … — consequence · *my recommendation* (a)
**Blast radius** — plan steps <4, 9>; design nodes <D6, D7>
**Meanwhile** — parked <thread>; continued on <threads>
```

Rules for the executing agent, and they are absolute: **do not resolve a gap by picking an answer.
Do not proceed on the parked thread. Do not delete or edit a gap** — a gap is closed by a new
design version, not by a change of mind.

### Closing the loop

The owner is offered a scoped questionnaire round covering only the open gaps and whatever their
answers open — never the whole questionnaire again. That round produces **design version N+1** with
a changelog: nodes added or changed, questions added, gaps closed. Every execution-plan step citing
a changed node is marked **stale** and re-derived before it is worked on again. Work on untouched
steps was never blocked and does not get thrown away.

### The propagation block (copy verbatim into every derived document)

```markdown
## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: <design doc>, version <N>, confirmed <date>. Every step below cites the design node
IDs it implements.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent → do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise — two defensible choices differ in observable behaviour, or the choice is expensive to
   reverse, or it is an owner call (balance, look, scope) → **park that thread, file a gap, keep
   working on unaffected threads, and tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.

File gaps at `<gaps dir>/GAP-NNN.md` using the template in `<design doc>` §gap-protocol. Write the
options in the questionnaire grammar; they become the next round's questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.
```

---

## Output and the conversion contract

One markdown file in the repo. Note its doc-hygiene obligation if the project has one.

**Write it so a tool can ingest it.** The strict question grammar above is not decoration — it is
the interchange format. A parser must be able to recover, from the prose alone: id, gate expression,
text, options, default, and whether notes are offered. Never duplicate the questions into a second
machine-readable block; two copies drift, and the prose is the one humans read.

Offer to render the design flowcharts as an Artifact for visual review.

### Where the design goes, and how the owner answers it

**The Design Loop tool** (`designloop/`) is the front end for this document: it parses the markdown
you write — there is no second authored copy — and presents it one question at a time in a local
web UI that never shows the question count and prunes as it goes. Answers stream to disk, and the
agent is woken when the round ends.

**The tool is optional and must stay optional.** If it is not running, is broken, or the owner
would rather not use it, the markdown document IS the questionnaire and they answer by ID in chat
exactly as before. Nothing in this procedure depends on it. What the tool needs is only that the
grammar above is obeyed.

1. **Write the design beside the code it describes**, in its own directory:

   ```
   <project>/design/<slug>/DESIGN.md      the document — this skill's whole output
   <project>/design/<slug>/meta.json      slug, title, projects touched
   <project>/design/<slug>/gaps/          filed by executing agents, later
   ```

   `<project>` is a top-level repo directory (`solatro`, `palette`, `worldgen`). `<slug>` is short
   and typeable; the readable name lives in `meta.json`:

   ```json
   { "slug": "spotlight", "title": "The Spotlight mechanic and its visual effects",
     "projects": ["solatro"], "doc": "DESIGN.md",
     "created": "2026-08-01T00:00:00Z", "rounds": 1, "confirmed_version": null }
   ```

   `projects` is a list because a design may touch several; it appears under each in the index.

2. **Check that it parses before handing anything over.** A question the parser cannot read is a
   question the owner never sees:

   ```
   npm --prefix designloop run check -- <project>/<slug>
   ```

   It reports the question count, which question the round opens at, and every error and warning
   with its line. Errors mean the document is wrong, not the parser — fix the line.

3. **Start the server and hand over the URL.** Not a file path, not "open the doc":

   ```
   npm --prefix designloop start
   ```

   → `http://localhost:5273/web/question.html?key=<project>/<slug>`

   (`designloop/start.cmd` is the double-click equivalent, and a second launch reclaims the port.)

4. **Park on the watch** in the same session, so the owner is never waiting on you:

   ```
   npm --prefix designloop run watch -- <project>/<slug>
   ```

   It blocks and returns the moment the round ends, printing what was answered, what was waved
   through as *not relevant* or Enter-defaulted, and whether the owner wrote their own answer.
   **Telling you in chat always works too** — never make the watch the only route.

5. **When it wakes**, read `<project>/design/<slug>/answers.json`, revise the document, and hand the
   turn back by writing `status.agent.json` (yours; the owner's half is never yours to write):

   ```json
   { "state": "ready", "mode": "questions", "round": 2, "at": "…",
     "summary": "Your answer to QR3 opened these: …" }
   ```

   The owner's screen switches itself over and opens the round with that summary. `mode: "review"`
   is for when the questions are finished and the design graph is ready to review instead.

   One ending is special: `status.owner.json` with `reason: "new_branch_needed"` means the owner
   answered a `⚑gate` in their own words and the round stopped there, with questions still
   unanswered. Author the branch they described — **their answer becomes a real option on that
   question** — and they resume at that same question with it there to click.

---

## Step 8 — THE HANDOFF. Confirmation ends with a plan AND a prompt, in the same message.

### 8.0 The trigger is CONFIRM, not the last answer

⚠ **Answering the last question does not end the design.** The sequence, matching chart A of the
Design Loop design (A13 → A14 → A15 → A18):

```
last reachable question answered
  → agent revises and FINALISES the design flowcharts
  → owner REVIEWS the flowcharts            ← a real stage, not a formality
  → owner CONFIRMS  (or "review again" → another cycle)
  → THEN: implementation plan + scope + copy-paste prompt, in one message
```

The review stage exists because the questionnaire settles *decisions* while the flowcharts settle
*sequence and completeness* — "between D6 and D7 there must be…" is feedback that only arrives when
someone looks at the chart. Producing the plan before that is building on an unreviewed design.

**Until the Design Loop tool ships**, the review stage is the markdown document's own mermaid
charts: after the last question, present the updated flowcharts, say what changed as a result of the
answers, and **ask for confirmation**. Do not assume it. Confirmation is the owner saying the
flowcharts are right — not their having answered the questions.

**Once confirmed, the owner must never have to ask "is this ready to hand off?"** If they do, this
step failed. Confirmation is followed immediately by the implementation plan, a scope
recommendation, and a copy-paste prompt. Do not stop at the plan and wait to be asked.

### 8a. The implementation plan is NOT bound by the design doc's no-code rule

⚠ **This is the mistake that produced this section (2026-08-01).** The no-code rule belongs to the
*design* document only. The *implementation plan* is the last document anyone should need to build
the thing, and it must carry every normative contract:

- **File formats / schemas** — every file, field by field, with who writes it. Anything read by two
  components is a contract, and a plan that names a file without specifying it is guaranteeing two
  incompatible inventions of the same thing.
- **Grammars and parsers** — formally, not by example. Prose plus a sample is not a spec.
- **Module APIs** — function signatures, so two callers cannot grow two versions of one behaviour.
- **Wire protocol** — every endpoint, its payload, its ordering guarantees.
- **Per-step done-when**, and at least one or two **hard self-checking acceptance gates** — a test
  that cannot be talked past. Those are what make a lower-effort autonomous run safe.

Writing "the plan deliberately contains no implementation detail" is not restraint. It is an
unfinished plan with a justification attached.

### 8b. Readiness checklist — run it before presenting anything

1. Every file the plan names is either specified in it or created by a step in it.
2. Every path the plan references exists, or a step creates it. **Grep for the paths.**
3. Every step cites design node IDs (the gap protocol's traceability requirement).
4. At least one acceptance gate per phase is objective and self-checking.
5. The propagation block is at the head, with real paths filled in.
6. The plan's own directory layout matches the layout the design chose — including for the plan's
   own documents. (The tool's own design living outside the structure its design mandates is exactly
   the kind of thing that greets an implementing agent as a broken path.)
7. Nothing in the plan is phrased as a question to the owner. The questionnaire is over.

### 8c. Scope the run

Say which phases go in one handoff and why, and name the effort level. The split is usually:
**pure-logic phases with hard gates** run together and tolerate lower effort; **visual or
judgment-heavy phases** get their own run at higher effort, because they need iteration against a
preview rather than one blind pass.

### 8d. The copy-paste prompt — always the last thing in the message

Fenced, self-contained, ready to paste into a fresh session with no editing. Template:

```
Implement <plan path>, Phases <n>-<m> only (steps S1-S10). Stop at S10.

Read <plan path> first; it is self-contained. <design path> is the authority on behaviour -
where they disagree the design wins and the plan is wrong.

Sections <n>-<m> of the plan are normative: <the contracts> are specified, not suggestions.
Do not invent them.

Hard gates, self-checking:
- <gate 1: an objective acceptance test>
- <gate 2>

Follow the gap protocol at the head of the plan: if you hit a decision the plan does not
cover, do not invent it - file a gap and keep working the unaffected steps.

Use /handoff to keep resumable state.
```

Include `/handoff` whenever the run spans more than one session's work. Repo-level rules (git
policy, code style) propagate through directory-keyed memory and do not need restating.

## Keep this skill improving

Every time this skill is used and the owner's review turns up something the questionnaire should
have caught, **fix this file in the same session**:

- A missing question category → add it to the §5 checklist.
- A chart that could not be reviewed → tighten the §3 rules.
- A default that was wrong in a predictable way → note the class of default to avoid.
- A gate that was wrong, or a question the owner had to answer that their earlier answers had
  already made irrelevant → that is a DAG bug, and it is the most important kind to fix here.

Then save the lesson to memory as a `feedback` note so it survives the session. Ask the owner after
each review pass whether the format itself needs changing; the questionnaire's own shape is
reviewable too.
