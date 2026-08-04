# designloop — the branching-questionnaire design front end

A local web tool for the repo's design workflow (`.claude/skills/flowchart-design`). The agent
writes a design document in markdown; the owner answers its questions **one at a time** in a
browser, never seeing the count and never seeing a question their earlier answers made irrelevant;
the agent is woken when the round ends. Then the design graph is reviewed on a pan-and-zoom canvas
and **Confirmed** into a frozen version an implementation agent works from.

**Node, zero npm dependencies.** Nothing to install beyond Node itself.

## Start it

```
npm --prefix designloop start
```

→ `http://localhost:5273` — the index: every design in the repo, with its status and its gaps.
`designloop/start.cmd` is the double-click equivalent. A second launch reclaims the port from the
first, so there is never a stale server on 5273.

Three screens, all keyed by `<project>/<slug>`:

| URL | What |
|---|---|
| `/web/index.html` | every design, by project — status, last touched, gap and warning badges |
| `/web/question.html?key=solatro/spotlight` | the questionnaire, one question per screen |
| `/web/question.html?key=solatro/spotlight&scope=gaps` | a **scoped round**: only the open gaps |
| `/web/canvas.html?key=solatro/spotlight` | the review canvas (`&version=1` opens a frozen one) |
| `/web/gaps.html?key=solatro/spotlight` | gaps open and closed, and the plan steps they make stale |

## The other commands

```
npm --prefix designloop test                            the suite (~1.5 s)
npm --prefix designloop run check -- solatro/spotlight  does it parse — AND the four silent audits
npm --prefix designloop run check -- solatro/spotlight charts   …and do its charts ingest?
npm --prefix designloop run watch -- solatro/spotlight  park until the owner finishes a round
```

⚠ **Never pass a `--flag` through `npm run`** — npm eats it and exits 255 on a run that succeeded.
That is why the chart listing is the bare word `charts`.

## Where a design lives

Beside the code it describes, never inside this tool:

```
solatro/design/spotlight/
├─ DESIGN.md            agent   the document — questions AND mermaid charts. The source of truth.
├─ meta.json            agent   slug, title, projects touched, rounds, confirmed version
├─ graph.json           agent   generated from DESIGN.md's charts, rewritten when its hash moves
├─ status.agent.json    agent   whose turn it is — agent half
├─ ASSUMPTIONS.md       agent   what an executing agent decided that the design did not cover
├─ gaps/GAP-NNN.md      agent   what it would NOT decide — a draft question in the same grammar
├─ versions/NNN/        agent   frozen at Confirm: graph, layout, answers, annotations, renders
├─ answers.json         UI      the current answers
├─ answers.log          UI      append-only; answers.json is rebuildable from it
├─ annotations.json     UI      node and edge notes, flags
├─ ui_meta.json         UI      display title, archived flag, last opened
└─ status.owner.json    UI      whose turn it is — owner half
```

**Every file has exactly one writer.** That is the whole concurrency design: no locks, no merges,
no read-modify-write of a shared file. `status` is two files for exactly that reason.

A design is anything with a `meta.json` under `<project>/design/`. The index is a scan, so a design
that is added, renamed on disk or moved simply is what the next scan finds — there is no registry
to keep in step.

## Answering: the keyboard, and whether anyone is listening

Every control on the question screen has a key and **shows** it. Options are their own letters —
`(b)` is pressed by `b`; then `w` use what I wrote, `n` not relevant, `⌫` back, `h` the history
sidebar, `g` the review canvas, `i` is anyone watching. `↑` `↓` move, and **`⏎` presses whatever is
marked** — one control is always marked, so what Enter is about to do is never a surprise. The mark
starts on the recommended answer and moves to *use what I wrote* the moment you type something, so
Enter can never discard what you wrote.

Accepting the recommendation without moving the mark is still recorded as its own state
(`defaulted`, Q12) — being shown what Enter does did not turn it into a considered answer.

**BACK is a visit stack**, like a browser's: the question this screen showed before this one. It
survives a trip to the canvas and back, and where there is nowhere to go it is disabled and says
why rather than doing nothing.

The chip at the top says whether **an agent is parked on this design** — green while a
`run watch` is beating, amber if the session that was watching has stopped, grey if none ever was.
Click it (or press `i`) for a prompt to paste into a fresh session. Nothing about answering depends
on it: every answer is on disk before the next question appears, and any session reads them
afterwards. It only decides whether one wakes up on its own.

## Cross-chart links, derived

The chart language has no arrow between charts — every edge stays inside one chart. The references
exist anyway, written in prose inside labels: `A6["owner answers one question at a time — chart B"]`.
The tool reads them out and draws them, **dashed and node-to-chart**, so the whole-graph view shows
the loop the document actually describes. They go into `graph.json` as a `links` list beside
`edges`, kept separate on purpose: an edge was drawn by the author, a link was inferred, and a
reader who cannot tell them apart has been told something the design does not say.

A name is resolved the way a reader resolves it — **by the name the heading gives the chart, before
the chart's node prefix**, because the two can drift when one section holds two charts. A reference
to the node's own chart is not a link; a reference to nothing at all is reported by `run check` as
an authoring warning, never guessed. `l` toggles them on the canvas.

## The two rules worth knowing before changing anything

1. **The markdown IS the questionnaire.** There is never a second authored copy. `src/grammar.mjs`
   parses it and is imported unchanged by both the server and the browser — one parser, two
   callers. If a real design document does not parse, **the grammar is wrong, not the document**.
2. **An answer is on disk before the next question appears.** `answers.log` append → `fsync` →
   `answers.json` rewrite → `fsync` → *then* HTTP 200. The UI never advances on a failed write, and
   a crash between the two is recovered by replaying the log.

## The four silent defects `run check` reports

Three of these leave a document that **parses, validates and answers perfectly** while withholding
questions the owner was supposed to see; the fourth quietly misleads the reviewer. All four cost real
rounds on `solatro/spotlight` before they were automated, and none of them showed up in any other
check, test or round summary.

```
  dag audit   0 — defects that prune questions SILENTLY (listed below)
  stale       0 chart node(s) posing an ANSWERED question as open
```

| Reported as | The defect |
|---|---|
| `DAG … not marked ⚑gate` | A question whose answer appears in another question's gate, without the mark. A free-text answer has **no letter**, so no gate naming it can ever be true — on an unmarked question the whole subtree is amputated in silence. *Six of these hid 20 questions and the round still said `complete`.* |
| `DAG … DEFAULT (x) is not among them` | Some gate enumerates a multi-letter set — `[Q113=b|c]` — and the question's own recommended answer is not in it. A newly added option is by construction absent from every gate written earlier, so it orphans its subtree by default. |
| `DAG … its section … does not` | A **section heading** gate narrower than its own question lines. `reachability()` evaluates `effectiveGate`, which folds the heading in, so the heading wins and the whole section stays pruned no matter what the lines say. |
| `STALE …` | A chart node still posing an **answered** question as an open fork. Needs `answers.json`, so **re-run `check` after every answer round**, not only after authoring. |
| `PLAN …` | Once a `PLAN.md` exists beside the design: a step citing an ID that is **no design node or question**, or citing **nothing at all** — which means it can never be reported stale when the node it was built on changes. The gap protocol's whole blast-radius mechanism is those `(implements …)` clauses. |

⚠ **None of them blocks, deliberately** — each shape has a legitimate form (a "decline this
sub-feature" option is *supposed* to reach nothing; a section gate is *supposed* to narrow). The
judgement is the author's; being told is not. A non-zero count is a defect until someone has looked
at it and said why not.

⚠ **Precision was the hard part, not detection.** Reporting every orphaned option produced 24
warnings on Spotlight, all of them correct behaviour, and a check at that signal-to-noise gets muted.
The filters are narrow on purpose: `auditGates` in `src/grammar.mjs` documents each one.

## The plan, and where progress lives

`PLAN.md` sits beside `DESIGN.md` in the design directory and is read by `readPlanSteps` for one
purpose: the `(implements …)` clause on each step, which is what makes a design change able to name
the plan steps it invalidates.

A step is recognised as **`**Sn — title**`** at the start of a line — optionally behind a list or
checkbox marker — or as a bare **`id: Sn`** inside YAML, which is the shape `/handoff` writes.

⚠ **The plan is a specification and should not carry status.** Progress belongs in the work stream's
`<project>/HANDOFF_<topic>.md`, which is a ledger of `id` / `status` / `evidence` / `notes` and
nothing else — the step's description, files, dependencies and citations stay in `PLAN.md`, because
the same text in two places is the drift this whole tool exists to prevent. The reason they are
separate files at all is that **the plan is immutable and the handoff is not**: "S5 is stale" is a
claim about a specification, and it stops meaning anything if that file also churns with ticks.

⚠ **The leading `- [ ]` is TOLERATED, not recommended.** It used to be rejected, and rejection was
not benign — the unmatched line fell through to the citation branch and attributed its nodes to the
*previous* step, so a checklist silently made the stale report name the wrong steps. Guidance about
where status belongs is guidance; it must not be enforced by silent data loss.

## The ask list — how an agent gets a question RE-asked

`status.agent.json` may carry an **`ask`**: the questions the agent needs answered this round.

```json
{ "state": "ready", "mode": "questions", "round": 3, "ask": ["Q24", "Q113", "QR2"] }
```

An entry counts as **unanswered until it is answered in that round**, which does two things at once:

- **it comes back into the queue, and it is asked first** — an agent that has rewritten a question
  (new option, corrected premise) no longer has to tell the owner to go hunting through their own
  history for it. The previous answer arrives with it, already selected, so confirming is one
  keystroke;
- **the round cannot end while any of them is outstanding.** Everything an ask unlocks is gated on
  it, so the subtree is withheld until it is answered and then holds the round open in turn. The
  owner is declared finished when the agent's whole ask is satisfied — not the instant the reachable
  set happens to empty.

⚠ **Both halves came from one owner report (2026-08-03):** *"This workflow of going into history to
find the question you are talking about then changing previous choice to unlock questions is pretty
bad UX. If you need me to answer new questions, every question that needs to be answered needs to be
given in one go, and you only pick up its finished when I finish answering all new questions you want
me to, instead of me changing one answer, answering its subquestions, then you immediately pick it up
before I have chance to look at next question."* Before this, the only routes were to make the owner
navigate their own history, or to ask in chat and leave `answers.json` permanently out of step with
the design. Both had happened.

`ask_total`, `ask_remaining` and `ask_revisit` come back from `/next` so the screen can say how much
of the agent's ask is left instead of leaving the owner to guess.

## Gaps — the way back from execution

An agent implementing a plan that meets a decision the design does not cover does not invent it. It
files `gaps/GAP-NNN.md` **in the questionnaire grammar**, parks that thread only, and keeps working
everything else. The tool then:

- badges the design's card on the index — open gaps loudly, closed ones quietly;
- offers a **scoped round** built from the gap's own options — only the gaps, never the whole
  questionnaire again;
- lists the execution-plan steps that cite what an open gap puts in question as **stale**, read out
  of the plan's own `(implements …)` citations;
- keeps closed gaps with their resolutions. A gap is closed by a new design version, never deleted.

The review canvas' assumptions panel carries the other direction: **"I want a say in this"** files
an open gap against an assumption that was already made, and every step that relied on it goes
stale from that moment.

## The tool is optional

The markdown document is answerable by ID in chat with no tool at all, exactly as before this
existed. Nothing in the design workflow depends on the server being up — what it needs is only that
the question grammar is obeyed. If the tool is down, mid-change, or unwanted, the workflow degrades
to what it was and nothing is lost.

## The documents behind it

| File | What |
|---|---|
| `design/designloop/DESIGN.md` | the design, and the authority on behaviour |
| `design/designloop/PLAN.md` | the execution plan — §4 file formats, §5 the grammar, §6 the mermaid subset, §7 module APIs, all normative |
| `design/designloop/ASSUMPTIONS.md` | every decision taken that the design did not cover, with why each is reversible |
| `design/designloop/gaps/` | where the design was thin, kept |
| `HANDOFF_designloop.md` | the build's live state, written to stand alone |
| `.claude/skills/flowchart-design/SKILL.md` | how a design is authored, and the handover procedure |
