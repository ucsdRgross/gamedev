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

A **contract question** is one whose answer has to be written down as a code-level contract in the
implementation plan's normative section — a signature, a default, a schema, a uniform name. Mark it
`⚑contract`. A question can be both; the two tags are independent and may appear in either order.

```
- **Q9** `[QR1=a]` ⚑contract — Ship the general `blocks_spotlight` seam now, or keep `is_data_topmost`? · …
```

⚠ **The tag exists because `Q9` above was NOT one, and that cost a round.** It asked *whether* to
ship a seam and never what the seam's default was or what it replaced, so the plan's §1 invented
both — and inverted the default, which would have lit up every covered card on the board. A
scheduling question is not a contract question, and `npm run check` now reports every normative
block in the plan that no `⚑contract` question authorises. **If the plan will have to write a
literal — a default, a bound, a name — the question that fixes it is `⚑contract`.**

⚠⚠ **IF A QUESTION'S ANSWER APPEARS IN ANY OTHER QUESTION'S GATE, IT IS A `⚑gate`. NO EXCEPTIONS.**
Breaking this fails SILENTLY. A free-text answer has **no letter**, so a gate reading `[Q24=c]` can
never be true. On a `⚑gate` question that is handled — free text ends the round and you author the
branch. On an *unmarked* one it is not handled at all: the answer is recorded, the round rolls on,
and **the entire subtree below it is amputated with no warning and nothing on screen.** Measured on
Spotlight: six unmarked gating questions, **20 questions never asked**, and the round
still reported `done (complete)`.

⚠⚠ **AND THE OBVIOUS RECOVERY DOES NOT WORK.** The question screen presents only *UNANSWERED*
reachable questions, so **adding an option to an already-answered question is invisible to the
tool**. Use the **ask list** (`status.agent.json` → `"ask": [...]`, README §"The ask list"): those
questions are re-asked FIRST with the previous answer prefilled, and the round cannot end until the
whole ask is satisfied. If you need an answer *now*, ask in chat and write it back through the store
API so `answers.json` does not drift from the design.

### `run check` now catches all of this — read its bottom four lines

These were manual greps; they are automated, and none of them existed when the defects above shipped:

```bash
npm --prefix designloop run check -- <project>/<slug>
```

| Line | What it means |
|---|---|
| `errors` | the document is wrong; fix the line |
| `warnings` | a `⚑gate` option with no `→ next:` |
| **`dag audit`** | **the silent-pruning defects**: a question that gates others without the mark; a `default` orphaned from a multi-letter gate it should be in; a **section heading narrower than its own question lines** (the heading wins — this one stranded 20 answers) |
| **`stale`** | **chart nodes still posing an ANSWERED question as an open fork.** Needs `answers.json`, so it only runs on a design key, not a bare path |
| **`plan`** | once `PLAN.md` exists: a step citing an ID that is no design node or question, or **citing nothing at all** — which silently removes it from every future stale report |

⚠ **`dag audit` and `stale` do not block, and that is deliberate** — each shape has a legitimate
form, so the judgement is yours. Being *told* is not optional: every one of them is invisible from
the owner's side of the screen. **A non-zero count in either is a defect until you have looked at it
and said why not.**

⚠ **Re-run `check` after ANY answer round, not just after authoring.** `stale` compares charts
against answers, so it only turns red once answers exist — which is exactly when nobody thinks to
run it. Spotlight accumulated **20 stale nodes across 11 charts** over four rounds and the owner
found them by eye.

**A `⚑gate` option with no `→ next:` is a warning, not a parse error** (`GAP-001`, resolved).
The document still parses and the owner can still answer it — blocking the person who
cannot fix it helps nobody — but the shortfall is *yours* to fix: `run check` names the question and
its line, and the design's card in the index carries a warning badge until it is gone. The owner
sees the option marked **→ next: not described**, which is exactly the blind choice rule 5 exists to
prevent. Treat any warning on that badge as an authoring defect.

**Free text at a gating question cannot be routed** — there is no path for an answer the DAG does
not know about. So a free-text answer at a `⚑gate` question **ends the round immediately** and
returns to the agent to author the new branch, rather than being queued until the rest of the
questions are answered. Design for that: keep `⚑gate` questions few, put them early, and make their
option sets genuinely exhaustive.

⚠ **READ `answers.log`, NOT ONLY `answers.json`.** `answers.json` is the CURRENT state;
the log is what actually happened. Spotlight's log held a free-text answer at `QR2` — a real new
branch — and then, four minutes later, the owner going back and picking `(a)` so they could keep
answering instead of sitting blocked. `answers.json` therefore showed a clean `QR2=a` and **the
branch would have been missed entirely**. Grep the log for `"override":true` every time you pick a
round up, including on IDs whose current answer is an ordinary option. A reverted override is not a
withdrawn opinion; it is someone working around you.

⚠ **When a `⚑gate` gains an option, WIDEN THE GATES BELOW IT — that is how answers survive.** Adding
`(c)` to a gate whose children all read `[QR2=a]` strands every answer already given the moment the
owner switches.

⚠⚠ **AND THE SECTION HEADING CARRIES A GATE TOO.** `reachability()` evaluates
`q.effectiveGate || q.gate`, and `effectiveGate` folds in the `### 17.6 The dim [QR2=a|c]` heading.
Measured on Spotlight: 17 question lines were widened to `a|c|d`, the heading was not,
and **all 12 of §17.6 stayed pruned anyway** — the owner clicked the option I told them to click and
watched 20 answers go inactive. Widen the heading in the same edit, always.

**Then prove it, twice, rather than assuming:**

```bash
# 1. does every option of every gating question actually reach something?
#    an option that appears in NO downstream gate prunes its whole subtree.
# 2. re-run reachability against the real answers.json and confirm the count.
node --input-type=module -e "…parseDocument + reachability…"   # designloop/src/grammar.mjs
```

The first catch is the one that matters: a newly added option is *by construction* absent from every
gate you wrote earlier, so it orphans its subtree by default. On Spotlight this caught `Q113=(d)`
orphaning `Q114` — `origin_rise`, the number that sets every beam's length. Note that a legitimate
"decline this whole sub-feature" option shows up in the same list and is fine; read the list, do not
just count it. Go through each child and ask which of them the new branch still needs: those become
`[QR2=a|c]`, and only the ones that are genuinely about the old branch stay `[QR2=a]`. Then say so in
the document, at the section head and in the changelog, because from the owner's side "did my work
just get thrown away" is the first question and the answer must not be "read the gates".

⚠ **Add options, never replace them, and say which questions will be re-asked.** The owner's own
words become an option on the question they wrote them on, and normally become its `*default*` — they
already told you what they want. Everything else stays untouched, so the re-ask list is exactly the
questions whose option sets changed. Name that list in the changelog and in `status.agent.json`'s
summary; two IDs is a very different message from "the round restarts".

⚠⚠ **THE CASE `check` CANNOT SEE: a stranded answer that widening never restored.** `dag audit`
reads 0 as soon as the *heading* is widened — but a child's OWN gate may still be narrow, and
**an inactive question holding an answer is indistinguishable from an inactive question holding
none.** Measured on Spotlight: widening `QR2` stranded 20 questions; §17.6's heading was widened to
`[QR2=a|c|d]` so the audit went clean, while `Q82`'s own gate stayed `[QR2=a & QR8=a]`. `Q82` held a
free-text override — *"per anytime spotlight effect is happening"*, the per-section dim — which went
inactive, vanished from every later reading, and the act-long dim shipped **chosen by nobody**. It
cost a playtest, `GAP-006`, and a round trip to recover an answer the owner had already given.

**So run this on every pick-up — it is two greps, not a discipline:** for each
`{"event":"strand"}` in `answers.log`, take its IDs and report any still `active:false` in
`answers.json` **while holding an answer**, `override:true` first. Each hit is either a gate that
needs widening or a dead question you should be able to say why is dead. On Spotlight the batch of
20 yielded exactly one live hit (`Q82`) and two genuinely moot ones — the signal is sharp, not noisy.

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
- ⚠ **READ THE ENGINE'S OWN DOCS FOR EVERY ENGINE FEATURE THE DESIGN LEANS ON, AND SEARCH FOR THE
  KNOWN PROBLEM.** This repo's absence of a feature is not evidence the engine lacks it. See below.

Put all of this in a §1 "Audit facts" section with line references. Everything downstream cites it.

#### ⚠ Search the web before you turn ignorance into a question

**The failure this prevents, measured on `solatro/picture-wall`:** the design needed to pause one
screen while another ran. Grepping found no `get_tree().paused` and no `process_mode` in the whole
project, so the root fork was authored as *"engine pause (`PROCESS_MODE_DISABLED` on the subtree)
**or** a `pause()` contract each screen implements"* — a false dichotomy built entirely out of not
having read [the pause tutorial](https://docs.godotengine.org/en/latest/tutorials/scripting/pausing_games.html).
Godot's actual model is a **global** `SceneTree.paused` plus a per-node `process_mode`
(INHERIT / PAUSABLE / WHEN_PAUSED / ALWAYS / DISABLED); the docs say outright that pausing "only
affects the entire game". The owner answered the question by pasting the doc URL and writing *"the
possible answers you gave me dont seem to reflect this knowledge"*. One search, before authoring,
and that root fork would have been a real question about which subtrees are ALWAYS.

So, before any question that depends on how the engine, library or platform behaves:

- **Read the official doc page for that feature.** Not a memory of it, not an inference from the
  repo. If the design rests on it, fetch it and quote it into §1.
- **Search for the known bug or the known gap.** The interesting facts are the ones the tutorial
  does not mention: `SceneTree.create_timer()` defaults `process_always = true` and so runs straight
  through a pause ([godot-proposals#9924](https://github.com/godotengine/godot-proposals/issues/9924)),
  and shader `TIME` keeps advancing while paused
  ([godot#27127](https://github.com/godotengine/godot/issues/27127)). Those two are the entire
  reason "pause the screen" is not one line — and neither is on the tutorial page.
- **Look for the existing solution before designing one.** Someone has usually solved this shape
  before; an addon, an engine feature, or a documented pattern beats an invention, and finding none
  is itself worth writing down.
- **Cite the URL in §1 next to the fact**, so the next reader can check it and so a stale fact has
  an address. Mark anything the sources disagree on as needing verification in-project rather than
  asserting it.

**The test for whether a question needed a search:** if the owner could answer it by pasting a doc
link, it was never a design question. A design question asks what the owner WANTS. A question that
asks what the ENGINE DOES is a research failure wearing a question's clothes — and it is worse than
useless, because a plausible wrong option set steers the answer.

### 2. Build the state model before the flowcharts

Name the independent facts the feature introduces and where each lives (derived / persisted /
view-only). Most feature confusion is two facts that were never separated. Do this in a table.

**Fill in the structure yourself.** The owner answers behaviour and appearance questions, not
architecture ones. If a structural choice has a behavioural consequence, ask about the
*consequence*, not the structure.

### 3. SKETCH the flow to find the questions — do NOT ship it yet

⚠⚠ **CHARTS GO IN AFTER THE FIRST ANSWER ROUND, NOT BEFORE IT** (owner: *"no way will
chart ever be accurate before first question round"*). This reverses what this step used to say, and
the reversal was earned: Spotlight's charts were authored up front, patched across four rounds, and
ended with **20 stale nodes across 11 charts** that the owner found by eye. A chart of behaviour
nobody has chosen yet is a guess with an ID on it.

**Sketching still comes first, because drawing the flow is HOW you find the questions.** A step you
cannot draw is a decision you have not noticed. So:

- **Sketch the flow however you like — scratch file, scratchpad, prose.** Over-decompose: a step that
  "obviously" has no decision in it is a step the owner cannot point at when it turns out to have one.
- **Every fork you cannot resolve becomes a QUESTION**, not a drawn branch.
- **Then throw the sketch away.** It has done its job. It is not an artefact, it is not reviewed, and
  it must not be published — a published sketch is something you will feel obliged to patch instead
  of re-derive, which is exactly how drift accumulates.

⚠⚠ **AND THE RULE THAT WOULD HAVE PREVENTED MOST OF IT: NEVER DRAW A QUESTION'S OPTION SET AS A
CHART FORK.** This step used to say the opposite — *"draw unresolved forks as explicit option
branches, cross-referenced to the question ID that decides them"* — and that single instruction
produced Spotlight's worst charts: a whole chart offering three origin models (`Q113`), a node
branching on the three answers to `QR10`, forks reading *"does it have anything to announce? — Q246"*.
Every one of them was **the questionnaire, redrawn**. Before the answer it tells the owner nothing
the question did not; after the answer it is a lie. If a fork's branches are a question's options, it
belongs in the questionnaire and nowhere else.

**What may be charted before a round, because it is fact rather than proposal:** the EXISTING call
chain, read out of the code with `file.gd:line` pinned. That is the §1 audit and it cannot go stale
from an answer. Anything marked `NEW` is a proposal and waits.

### 3b. Write the charts AFTER the round — derived, and re-derived

Once the round ends, the answers decide the behaviour, so the charts can finally be written as
statements instead of guesses.

- **Mermaid, in fenced ```mermaid blocks.**
- **Every node gets an ID** (`D4`, `G12`). The owner reviews by ID. Without IDs the review has no
  addresses.
- **Mark new nodes `NEW`**, and name existing nodes with their **real function**
  (`Game.score_line`). The chart should read as a diff against reality.
- **One chart per concern**, not one giant chart.
- **A node states its answer, never its question.** `"Q141=b — headers glow, no special case"`, not
  `"do they glow? Q141"`. `run check`'s `stale` line reports the second form; a node that ends on a
  bare question ID is the shape it catches.
- ⚠ **One heading, one chart, and the heading's letter IS the chart's node prefix.** Put a second
  chart under `## 7. Flowchart E — …` and its nodes are prefixed `F`, so from there on every chart
  ID runs a letter ahead of the heading that names it — Spotlight's *Flowchart H* is the chart whose
  nodes are `I1`, `I2`…. The tool copes (it resolves a reference by the heading name first, which is
  how a reader reads it), but it is a trap for everyone: **name every chart by its own node prefix.**
- **A label that names another chart becomes a drawn link.** Write the reference the way the
  documents already do — `A6["owner answers one question at a time — chart B"]` — and the canvas
  draws it dashed, node to chart, and puts it in `graph.json` as a `links` entry (GAP-002, design
  version 3). There is no cross-chart arrow in the mermaid subset, so this prose form IS the way to
  connect charts. A name that resolves to nothing is reported as an authoring warning.

⚠ **On a LATER round, RE-DERIVE the charts from the answers; do not patch them.** Patching is what
accumulated the 20 stale nodes: each round I fixed the nodes I remembered and left the rest. The
answers are the source; the charts are output. `run check`'s `stale` line is the check, and it only
turns red once answers exist — **so re-run it after every round, not only after authoring.**

### 4. Enumerate every usage

One row per situation the feature can be in — including the boring ones (headless, empty case,
single-element case, every screen it can appear on, undo, resume, settings changed mid-flight).
Each row points at the **question** that covers it — and, after §3b, at the chart too. ⚠ Before the
first round there are no charts to point at, which is the point: if a usage has no question, you have
found a hole. State plainly: *if a usage is missing, that is the most valuable thing you can report.*

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
  lines, longest path 194". ⚠ A hand estimate of Spotlight's was wrong by 44 (guessed
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
| **RESTATEMENT** | two documents disagree, but both are *summarising the same answer* | ⚠ **NOT a gap — go read the answer.** Resolve it against `answers.json`, fix the losing summary, and log it. Escalating this costs the owner a round to be told what they already said. `npm run check -- <slug> answer <ID>` prints the source note and every restatement of it, side by side. |

### The gap report is a draft question

This is what makes escalation cheap: a gap is filed **in the questionnaire grammar**, so its options
drop into the next round unchanged. One file per gap:

```markdown
# GAP-007 — <one-line title>
status: open | questioned | resolved | withdrawn
outcome: answered | withdrawn | superseded      (added when it closes; withdrawn = it was never a gap)
raised: <date>, during <execution plan step>
design: <doc> version <N>, nodes <D6, I10>
severity: GAP | CONTRADICTION

**What the design says** — <quote it, cited>
**What the ANSWER says** — <the verbatim note from `answers.json` for every question involved, and
  why it does not settle this>
**What it does not say** — <the decision that has to be made, stated as a decision>
**Why it blocks** — <which triage test it meets, concretely>
**Options I can see** — **(a)** … — consequence · **(b)** … — consequence · *my recommendation* (a)
**Blast radius** — plan steps <4, 9>; design nodes <D6, D7>
**Meanwhile** — parked <thread>; continued on <threads>
```

⚠ **`What the ANSWER says` is mandatory and it is the field that stops wasted rounds.** Filing a gap
without reading the source note is how `solatro/spotlight` GAP-002 happened: two documents
paraphrased one free-text answer, both dropped the clause that settles it, and the executor
escalated the gap between the two summaries. Quoting the note and having to write *why it does not
settle this* is what makes that impossible to do accidentally.

Rules for the executing agent, and they are absolute: **do not resolve a gap by picking an answer.
Do not proceed on the parked thread. Do not delete or edit a gap** — a gap is closed by a new
design version, not by a change of mind.

### Closing the loop

The owner is offered a scoped questionnaire round covering only the open gaps and whatever their
answers open — never the whole questionnaire again. That round produces **design version N+1** with
a changelog: nodes added or changed, questions added, gaps closed. Every execution-plan step citing
a changed node is marked **stale** and re-derived before it is worked on again. Work on untouched
steps was never blocked and does not get thrown away.

**The Design Loop tool does all of that from the gap file itself** (`designloop/web/gaps.html`), so
write the file properly and there is nothing else to build:

- the design's index card badges the open gaps, and quietly badges the closed ones;
- `→ Answer N gaps now` opens a **scoped round** on the ordinary question screen —
  `question.html?key=<project>/<slug>&scope=gaps` — built from the gap's `**Options I can see**`
  line, parsed by the same grammar as every other question, with the report's own
  *what the design says / does not say / why it blocks* carried onto the screen beside it;
- the plan steps that cite what an open gap puts in question are listed as **stale**, read out of
  `PLAN.md`'s own `(implements …)` citations against the gap's `**Blast radius**` line. It is
  reported, never written into the plan;
- when the last open gap is answered the owner's turn ends with `reason: "gaps_answered"`, which is
  what wakes an agent parked on the watch. Only that thread parks — the main questionnaire carries
  on where it was;
- the review canvas' assumptions panel has **"I want a say in this"**, which files an open gap
  against an assumption already made and makes every step that relied on it stale. It is filed with
  **no options** — the owner asked for the decision, not for a question — and drafting the real
  options in the grammar is yours.

Three things to get right in the file, all of them from the template above: `status:` on its own
line (`open` and `questioned` are open, `resolved` and `withdrawn` are kept but never re-asked);
`resolution:` as a `|` block when you close it, because a closed gap is only a record if what it
became is beside it; and a `**Blast radius**` line naming plan steps first and design nodes after
`design nodes`, because that is where the stale list comes from.

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
4. ⚠ **Two documents disagreeing is NOT automatically (3).** If both are restating the same answer,
   go read that answer — the conflict is a documentation bug to fix against the source, not a
   decision to escalate. Quote the note in the gap and say why it does not settle the question; if
   you cannot, it was never a gap.

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

Offer to render the design flowcharts as an Artifact for visual review — **after the round, once
they exist** (§3/§3b). There is nothing to render before it.

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
   <project>/design/<slug>/PLAN.md        after confirmation — the steps and contracts (§8a)
   <project>/design/<slug>/TEST_PLAN.md   after confirmation — every test, planned (§8a′)
   <project>/design/<slug>/NAMES.md       after confirmation — the identifier registry (§8a′)
   ```

   `<project>` is a top-level repo directory (`solatro`, `palette`, `worldgen`). `<slug>` is short
   and typeable; the readable name lives in `meta.json`:

   ```json
   { "slug": "spotlight", "title": "The Spotlight mechanic and its visual effects",
     "projects": ["solatro"], "doc": "DESIGN.md",
     "created": "2026-08-01T00:00:00Z", "rounds": 1, "confirmed_version": null }
   ```

   `projects` is a list because a design may touch several; it appears under each in the index.

2. ⚠ **THE ENGINE-CAPABILITY GATE — run this BEFORE the first round, not after.** The design must
   carry a **§1m Engine capability audit** table before any URL is handed over. One row per
   engine/library/platform capability the design leans on, each marked ✅ *confirmed*,
   ⚠ *already exists — do not build it*, or ⚠ *contradicted*, **each citing the doc URL**. Nothing
   in it may come from memory or from grepping the repo.

   Build it by walking your own draft and asking, for every `NEW` thing and every question:

   | Ask | Because |
   |---|---|
   | Does the engine already ship this? | a question about a feature that exists is a question that should never be asked |
   | Is there a standard node, resource or pattern for this shape? | inventing past `NinePatchRect` is how a "frame system" gets designed |
   | Does this capability exist on the platform we actually build on? | it may exist on one OS and silently never fire on ours |
   | What does the doc page NOT say? | the load-bearing facts are usually in an issue, not the tutorial |
   | Is the thing I called impossible actually available now? | version drift cuts both ways |

   **Measured on `solatro/picture-wall`, running this gate LATE — after 203 answers and 13 charts:**
   three features had been designed that the engine already ships (`NinePatchRect`/`StyleBoxTexture`
   for the expandable frame, `stretch_shrink` for render resolution, per-node
   `CanvasItem.texture_filter` for the filter swap), one recommended node type was documented as not
   supporting the only thing the design does with it, one input event never fires on the development
   platform, one API was called unavailable that had shipped two versions earlier, and one reliability
   caveat invalidated a `⚑contract` number. **Five gaps and a re-derivation, all of which the gate
   would have caught before a single question was asked.**

   ⚠ **A capability audit is not the same as a code audit.** §1 is what the *repo* does; §1m is what
   the *engine* offers. The picture-wall design had a thorough §1 and every one of those defects
   still shipped into the questionnaire, because grepping the repo can only ever tell you what this
   project already uses.

3. **Check that it parses before handing anything over.** A question the parser cannot read is a
   question the owner never sees:

   ```
   npm --prefix designloop run check -- <project>/<slug>
   ```

   It reports the question count, which question the round opens at, how many mermaid charts were
   ingested, and every error and warning with its line. Errors mean the document is wrong, not the
   parser — fix the line. Add `charts` for one line per chart:

   ```
   npm --prefix designloop run check -- <project>/<slug> charts
   ```

   **Your charts must be inside the subset the canvas reads** — `ID["label"]`, `ID{"decision"}`,
   `-->`, `-- label -->`, one `flowchart TD` header, one shared ID prefix per chart. Anything else
   (`subgraph`, `classDef`, `-.->`, an unquoted label) is refused by name and line rather than
   guessed at. `run check` also reports `links N derived, M unresolved` — the cross-chart links read
   out of your labels (§6.1). **M must be 0**: an unresolved `chart X` is a reference you wrote to
   something that does not exist. The subset is `designloop/design/designloop/PLAN.md` §6; widening it is a plan
   change, not a parser change.

4. **Start the server and hand over the URL.** Not a file path, not "open the doc":

   ```
   npm --prefix designloop start
   ```

   → `http://localhost:5273/web/question.html?key=<project>/<slug>`  the questions
   → `http://localhost:5273/web/canvas.html?key=<project>/<slug>`    the review canvas
   → `http://localhost:5273/web/gaps.html?key=<project>/<slug>`      the gaps, once there are any

   (`designloop/start.cmd` is the double-click equivalent, and a second launch reclaims the port.)

5. **Park on the watch** in the same session, so the owner is never waiting on you:

   ```
   npm --prefix designloop run watch -- <project>/<slug>
   ```

   It blocks and returns the moment the round ends, printing what was answered, what was waved
   through as *not relevant* or Enter-defaulted, and whether the owner wrote their own answer.
   **Telling you in chat always works too** — never make the watch the only route.

6. **When it wakes**, read `<project>/design/<slug>/answers.json`, revise the document, and hand the
   turn back by writing `status.agent.json` (yours; the owner's half is never yours to write):

   ```json
   { "state": "ready", "mode": "questions", "round": 2, "at": "…",
     "summary": "Your answer to QR3 opened these: …" }
   ```

   The owner's screen switches itself over and opens the round with that summary. `mode: "review"`
   is for when the questions are finished and the design graph is ready to review instead.

   Two endings are special. `reason: "new_branch_needed"` means the owner answered a `⚑gate` in
   their own words and the round stopped there, with questions still unanswered: author the branch
   they described — **their answer becomes a real option on that question** — and they resume at
   that same question with it there to click. `reason: "gaps_answered"` means they answered a
   scoped gap round instead: read the answers against `gaps/`, write design version N+1 with its
   changelog, close those gaps in place *with their resolution*, and re-derive the steps the gap
   page lists as stale.

**The live example is `solatro/design/spotlight/`** — 195 questions, 14 charts, written by hand to
this grammar before the tool existed and answerable in it without a single edit. That is the bar:
if a real document needs editing to be read, the parser is wrong. `designloop/README.md` is the
tool's own entry point.

---

## Step 8 — THE HANDOFF. Confirmation ends with a plan AND a prompt, in the same message.

### 8.0 The trigger is CONFIRM, not the last answer

⚠ **Answering the last question does not end the design.** The sequence, matching chart A of the
Design Loop design (A13 → A14 → A15 → A18):

```
last reachable question answered
  → agent WRITES the flowcharts from the answers   ← §3b; on a later round, RE-DERIVES them
  → owner REVIEWS the flowcharts            ← a real stage, not a formality
  → owner CONFIRMS  (or "review again" → another cycle)
  → THEN: implementation plan + test plan + names + scope + prompt, in ONE message
  → the TOOL audits §1 (`contracts … unauthorised`)  ← §8b item 13. Clean = nothing to review.
```

⚠ **The owner's review gate is the flowcharts, and only the flowcharts.** §1 is audited
mechanically; escalate a block only when the audit says nothing authorises it.

⚠ **This is the FIRST time the charts exist**, and that is deliberate (§3): a chart drawn before the
answers is a guess with an ID on it. The owner's verdict that put it here — *"no way will chart ever
be accurate before first question round"* — was earned by 20 stale nodes across 11 charts on
Spotlight.

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

⚠ **This is the mistake that produced this section.** The no-code rule belongs to the
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

⚠ **QUOTE A FREE-TEXT ANSWER; NEVER SUMMARISE IT.** An answer with no lettered option is prose, and
the plan's habit of compressing everything into a contract line destroys it: Spotlight's `Q16` became
*"Q16 whole act"* in the plan and *"stays set for the whole act"* in the design, and **both dropped
the clause that settled it**. An executor then read two lossy summaries, saw a contradiction that
does not exist in `answers.json`, and filed a gap on it. Paste the note. `run check -- <slug>
answers` lists every answer this applies to, and `answer <ID>` prints the note beside every place
the documents speak for it.

### 8a′. THE HANDOFF IS THREE DOCUMENTS, NOT ONE

⚠ **The goal that decides everything in this section, in the owner's words:**

> *"the implementer therefore can spend zero time thinking or inventing any design details, and will
> spend all of its time purely implementing and testing."*

Every minute an implementer spends deciding is a minute spent making a decision the designer was
better placed to make, with more context, under review. So the handoff ships **three** files:

| File | What it fixes | Why the implementer must not author it |
|---|---|---|
| `PLAN.md` | the steps, the normative contracts, the done-whens | it is the specification |
| `TEST_PLAN.md` | **every test that must exist, planned in advance** | see below |
| `NAMES.md` | the exact identifiers everything will be called | two agents invent two names for one thing |

#### `TEST_PLAN.md` — plan the tests, do not delegate inventing them

**The designer writes the test plan, because the designer knows what the feature is for.** An
implementer deriving its own test list re-derives the design badly and *silently misses cases* —
the ones it misses are exactly the ones it did not understand, and a missing test looks identical to
a passing one.

- **One row per test**, each citing the **design node** it proves and the **plan step** it gates.
- **The important tests are named in advance and are not optional.** The implementer **may add**
  low-level tests for details the plan could not foresee — that is expected and welcome — but it may
  **not** decide that a planned test is unnecessary. Removing one is a gap, not a judgement call.
- **Specify the FIXTURES too.** "Test that the packer clusters" is not a test; "given 7 pictures of
  size class M and one L, ring capacity 6, assert ring 0 holds exactly 6 and ring 1 holds 2 at the
  authored angles" is. If the plan does not fix the data, the implementer invents the data, and
  invented data tests whatever it happened to make true.
- **Say which are self-checking gates** — the ones that cannot be talked past — and which are
  by-eye verifications a human must sign off (this repo's rule 4: no green test is evidence about
  pixels).
- **Say what is deliberately NOT tested**, and why. An untested area that nobody chose is a hole; one
  the designer chose is a decision.
- **Map every design node to at least one test.** A node no test proves is a behaviour that can
  regress silently. This is the same claimant logic `run check`'s `unclaimed` line already applies to
  steps, pointed at tests instead — see [[design-answers-need-a-claimant]].

#### `NAMES.md` — the identifier registry

Every name the feature introduces, fixed before anyone types it: class names, file paths, scene
paths, signal names, method signatures on any shared seam, `InputMap` action names, settings keys,
localisation keys, test suite names, node names that a `%unique` lookup depends on. It is a table,
it is boring, and it removes an entire category of "I called it something else" divergence — which
is the most common way two sessions on one plan produce work that does not compose.

#### ⚠ AN ARGUABLE NUMBER IS A KNOB, NOT A CONTRACT

**If you catch yourself presenting a literal to the owner as "worth arguing with", it should not be
in the plan at all — it should be a tunable the tuning tool exposes.** A number the owner might
disagree with is a number they should be able to *turn*, by eye, against the running thing. Asking
them to adjudicate it on paper is the worst of both: they cannot see its effect, and they have to do
it before anything exists.

The test: **could the owner tell whether this value is right by looking at a screenshot?** If yes it
is a knob — a `PlayerSettings` field or a resource field the tool edits live — and the plan's job is
only to say where it lives and what it starts at. If no (a schema, a file path, an ordering rule, a
signature) it is a genuine contract and belongs in §1.

Measured on `picture-wall`: I ended a handoff by listing six literals as "worth arguing with" —
gap widths, texture floors, target sizes. Every one was a knob, five already were, and the sixth
became one. **The list should have been empty**, and the tool step should have said *every* knob is
exposed live, which it did not.

#### And three more things that buy back implementer thinking-time

1. **Resolve every `UNVERIFIED` fact before handoff, or make it a Phase 0 spike with a decision rule
   written down.** An implementer that meets "sources disagree, check by eye" is doing design. If a
   fact cannot be settled on paper, the plan opens with a spike whose *outcome is pre-bound*: "if X,
   do A; if not X, do B" — so the experiment resolves it and no judgement is needed.
2. **Ship an anti-scope list.** Name what the implementer must NOT do — the adjacent improvements,
   the refactors it will be tempted by, the polish. Without it, "obviously this should also…" is a
   decision it makes alone.
3. **Order the steps into a dependency graph and say which are parallel.** Sequencing is a design
   judgement with real cost; leaving it implicit means every session re-derives it and two sessions
   derive it differently.

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
8. **`npm --prefix designloop run check -- <slug>` is clean on the four provenance lines**, not just
   on errors: `in prose` (answers with no letter), `unquoted` (a document paraphrasing a free-text
   answer instead of quoting it), `contracts … unauthorised` (a normative block no `⚑contract`
   question covers), `uncontracted`, and **`unclaimed`** (an answered question no step cites — the
   nodes → steps direction, see [[design-answers-need-a-claimant]]).
9. **`TEST_PLAN.md` and `NAMES.md` exist** (§8a′), every design node is claimed by at least one
   planned test, and every planned test cites a node and a step.
10. **No `UNVERIFIED` fact reaches the implementer undecided** — each is either settled before
    handoff or is a Phase 0 spike whose outcome is pre-bound to an action.
11. **The anti-scope list is present**, and the step order names what is parallel.
12. ⚠ **Read the plan back asking one question only: "where would I have to THINK?"** Every place an
    implementer would have to choose a name, a number, a file, a test, an order, or a shape is a
    place the plan is unfinished. That is the whole bar of §8a′ and it is easy to satisfy on paper
    and fail in practice.
13. ⚠ **§1 IS AUDITED, AND ONLY ESCALATED WHEN THE AUDIT IS DIRTY.** Both of Spotlight's phase-1
    gaps were in the plan's normative section, which is written *after* confirmation and goes
    straight to an executor — the design was reviewed and was right both times. So §1 does need a
    gate. **But the gate is `run check`'s `contracts … unauthorised` line, not the owner's
    eyes.** Every normative block must cite a `⚑contract` question the owner already answered:
    - **`unauthorised` is 0** → §1 contains no decision they have not already made. **Say that, and
      do not ask them to read it.**
    - **`unauthorised` is non-zero** → each one is a decision that entered the plan without ever
      being asked. Do not present it as "please review §1"; present the specific block, say what it
      decides and what authorises nothing, and treat it as a gap.

    ⚠ **Run the audit BEFORE composing the handoff message.** Measured on `picture-wall`: I asked the
    owner to review §1 with `unauthorised` already at 0, and their reply was *"not sure why I would
    need to check plan.md, I thought I only need to review the charts"* — a fair objection to a
    question the tool had already answered. **The owner reviews the charts. The tool reviews §1.**

    ⚠⚠ **AND CHECK THE BLOCK COUNT, NOT ONLY THE UNAUTHORISED COUNT.** `normativeBlocks` scans a
    section headed exactly `## 1. ` — write `## §1.` and it scans **nothing**, finds zero blocks, and
    reports `0 unauthorised`, which is byte-identical to a clean result. Measured on `picture-wall`:
    that is precisely what happened, I quoted the 0 as proof, and the real audit found **3
    unauthorised blocks** the moment the heading was fixed. **`blocks` must be greater than 0 or the
    audit proved nothing** — a vacuous pass and a real pass look the same from the outside.

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

<test plan path> lists every test that must exist, with its fixtures. Write those tests -
you may ADD lower-level ones, you may not decide a planned one is unnecessary. Dropping one
is a gap, not a judgement call.

<names path> fixes every identifier. Use those names exactly. Do not rename, do not
"improve", do not shorten.

Hard gates, self-checking:
- <gate 1: an objective acceptance test>
- <gate 2>

You should not have to design anything. If you find yourself choosing a name, a number, a
file, a test, an order or a shape that no document fixes, that is a plan defect: file a gap
and keep working the unaffected steps. Do not invent it, and do not "just pick something
sensible" - the whole point of these documents is that the decision was already made with
more context than you have.

Do not do the things in the plan's anti-scope list, however tempting.

Use /handoff to keep resumable state.
```

Include `/handoff` whenever the run spans more than one session's work. Repo-level rules (git
policy, code style) propagate through directory-keyed memory and do not need restating.

## ⚠ A questionnaire settles what a thing DOES, not whether anyone can tell

Learned twice, on the tool this skill drives (and), and it is the most
reliable class of miss in the whole procedure. Both owner reviews of built screens produced findings
that were **already decided in the design and simply never shown**:

- Enter accepts the recommendation (Q12, answered) — and nothing on the screen said so, so the only
  way to learn it was to have it happen, on a question where it destroyed what had been typed.
- BACK exists (Q33, answered) — and it meant "the newest answer", so on the newest answer it
  pointed at itself and the click did nothing.
- An agent is woken by a watch (QR1, answered) — and the owner had no way to see whether one was
  parked, so a whole round could be answered into a directory nothing was listening to.

None of these is a question the questionnaire failed to ask. Each is a decision it settled and the
*surface* never surfaced. So:

- **Plan for two reviews, and say so.** One settles behaviour, from the charts. The other happens
  only by **driving the built thing**, and it cannot be done early or on paper.
- **When a design settles a hidden behaviour — a key, a default, a background process, an implicit
  navigation — write the node that says how the person using it will KNOW.** "Enter takes the
  default" is half a decision; "and the control it will press is marked" is the other half.
- Findings from the second review are usually **a new design version, not re-answered questions**:
  the owner is not changing their mind, they are covering ground the questions never reached.

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
