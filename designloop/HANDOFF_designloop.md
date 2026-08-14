# HANDOFF — the Design Loop tool

**What it is:** the tool described by `designloop/design/designloop/PLAN.md` — the owner answers a
branching design questionnaire one question at a time in a local browser UI, every answer is on
disk before the next question appears, and the agent is woken when the round ends.

**State: FINISHED.** Every step is complete and verified, `npm --prefix designloop test` is green,
and both filed gaps are closed with nothing parked. All three halves work end to end: the
questionnaire, the review canvas, and the gap surface — gap files read as draft questions, a badge
per design, a **scoped round** built from a gap's own options, stale plan steps computed from the
plan's own citations, closed gaps kept with their resolutions, and "I want a say in this" promoting
an assumption to a gap from the canvas.

`designloop/README.md` is the tool's entry point; new work on it starts there.

**Entry docs:** `designloop/design/designloop/PLAN.md` (the build document; §4–§7 are normative),
`designloop/design/designloop/DESIGN.md` (the authority on behaviour — where they disagree, the
design wins), `designloop/design/designloop/ASSUMPTIONS.md`,
`designloop/design/designloop/gaps/`.

---

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from `designloop/design/designloop/DESIGN.md`. Every step cites the design node IDs it
implements.

If you are executing this and you reach a decision the design does not cover:

1. Reversible and clearly within intent → do it, and append one line to
   `designloop/design/designloop/ASSUMPTIONS.md` citing the node you were working on. Never
   silently.
2. Otherwise — two defensible choices differ in what the user sees, or the choice is expensive to
   reverse (file format, a public seam, the question grammar), or it is an owner call (scope, look)
   → **park that thread, file a gap, keep working on unaffected threads, and tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.

File gaps at `designloop/design/designloop/gaps/GAP-NNN.md` using the template in
`.claude/skills/flowchart-design/SKILL.md`. Write the options in the questionnaire grammar; they
become the next round's questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## How to run it

```
npm --prefix designloop test                                  the whole suite, ~1.5 s
npm --prefix designloop start                                 the server, http://localhost:5273
npm --prefix designloop run check -- solatro/spotlight        does a design document parse?
npm --prefix designloop run check -- solatro/spotlight charts …and do its charts ingest?
npm --prefix designloop run watch -- solatro/spotlight        park until the owner finishes a round
```

Four screens, all keyed `<project>/<slug>`: `/web/index.html` lists every design,
`/web/question.html?key=…` answers the questions (`&scope=gaps` makes it a scoped gap round),
`/web/canvas.html?key=…` reviews the graph (`&version=1` opens a frozen one), and
`/web/gaps.html?key=…` is the gap surface — open, closed, and what is stale.

Never pass a `--flag` through `npm run` — npm eats it and exits 255 on a run that succeeded; that
is why the chart listing is the bare word `charts`.

**The Node server has no hot reload.** After editing anything in `designloop/src/`, `preview_stop`
then `preview_start`, or the browser will be talking to the old routes. Editing `web/` only needs a
page reload. ⚠ **When the owner is running their own server from `start.cmd`, it keeps the code it
started with. Never restart or kill their server to make a change land — say so and let them.**

### Verifying the UI

The Browser pane drives it through the `designloop` entry in `.claude/launch.json`. **The pane in
this environment is not displayed**, so `computer {action:"screenshot"}` fails and OS-level key
events do not reach the page. Verify with `read_page` / `get_page_text`, and exercise keyboard paths
by dispatching real `KeyboardEvent`s through `javascript_tool` — that runs the actual handler in the
actual page.

**To actually LOOK at something** (project rule 4 — visuals are verified by eye or not at all):
`node designloop/tools/shot.mjs <url> <out.png> [w] [h] ["js first"]` — headless Edge over CDP,
driven with Node's built-in `WebSocket`, runs a JS snippet before the shot (so the shot can be of
the *collapsed* canvas, or of the picker) and writes a real PNG. No dependencies. `msedge
--screenshot` on its own only ever captures the initial state, which is useless for a canvas whose
interesting states are behind a click.

⚠ **Verify against a throwaway design, never against `solatro/spotlight`.** Answering anything in
the UI writes `answers.json`, `answers.log` and `status.owner.json` into that design's directory,
and on the owner's paused document those are answers they did not give. Make a design directory with
a two-question `DESIGN.md`, exercise that, delete it. Check `git status solatro/design/spotlight`
before you finish.

## Standing invariants

- **A design document is never edited by this tool.** `solatro/design/spotlight/DESIGN.md` is
  byte-identical to the file it was moved from — a requirement, not an accident. `graph.json` is
  generated from the document and rewritten whenever its hash moves, so the document is the one
  authored copy and everything else is derived.
- **Nothing is ever written back to a gap file or to a plan.**

## What is NOT verified

- **Physical keypresses.** Handlers are exercised with dispatched `KeyboardEvent`s in the real page,
  which runs the real code, but OS-level input has never been tried.
- ~~The gaps page and the scoped round have never been looked at~~ — **both have now been, and
  looking found a defect no test would have.** The page said **"11 open"** for `solatro/spotlight`, a
  stream with two: those eleven files write their status in prose instead of the template's
  `status:` key, and `parseGap`'s missing-key fallback produced an object byte-identical to a real
  `status: open` — so `staleFor` marked plan steps stale on nine answered gaps. Fixed by making the
  fallback SAY so (`unstated`, `gap.statusStated`, a badge, a `gaps` line in `run check`); it stays
  OPEN, because an unreadable status is not evidence of closure. ⚠ **The gap FILES were not edited**
  — "the tool never edits a gap" is absolute; recording their real statuses is the owner's call.
- **A second author's charts.** Only the two real documents have been ingested, and both are written
  by the same hand — so the mermaid subset is proven against this repo's dialect, not against
  mermaid.

## Open bugs

None known.

## Open gaps

**None.** Both filed gaps are closed, in place, with their resolutions. What each turned into, so
nobody re-derives it:

**GAP-002 — the owner chose (b): derive the cross-chart links.**

- **`src/graph.mjs` derives them at ingestion.** A node label naming another chart becomes a link
  from that node to that **chart** — not to a node inside it, because the label named a chart and
  picking an endpoint would invent structure the document does not have.
- **`graph.json` grows a `links` list beside `edges`** (PLAN §4.6), deliberately separate: an edge
  was drawn by the author, a link was inferred from a label, and a consumer that cannot tell them
  apart asserts a connection the document never made. Key is `FROM~>TOCHART`, so it can never
  collide with an edge key.
- **The rule is PLAN §6.1**, and it resolves a name **the way a reader does — by the name the
  document uses, before the chart ID.** This is the one that bites: Spotlight's §7 holds two charts,
  so from there on every chart ID is one letter ahead of the heading naming it, and
  `K14 "see chart H"` means the chart with `I`-prefixed nodes. ID-first gives a wrong link.
- **Nothing is guessed.** Unresolved → a warning naming the line (GAP-001's rule, same class of
  defect); same-chart → dropped silently (chart E says "chart E2" about its own node, which is
  correct authoring); repeated in one label → deduped.
- **The canvas draws them dashed, purple, node-to-chart**, under the nodes, hidden in the
  single-chart picker view, with a `links: shown (N)` toggle (`l`). A collapsed chart keeps its
  links.
- **Measured and pinned as a fixture** in PLAN §6.1 and `test/graph.test.mjs`: 10 links here, 5 in
  Spotlight, 0 unresolved in either, and neither document was edited to make it so.

**GAP-001 — the owner chose (b): a `⚑gate` option with no `→ next:` is a warning, not a parse
error.**

- `parseQuestionLine` warns by default; `strict: true` still throws, which is what PLAN §5.6's
  must-throw case exercises.
- The warning reaches the authoring agent through `run check` **and** through a badge on the
  design's card in the index (`registry.docHealth` → `GET /api/designs` → `web/index.mjs`).
- The question screen renders **`→ next: not described`** on an option with no preview. Rendering
  nothing would be indistinguishable from "no questions follow this branch".
- `.claude/skills/flowchart-design/SKILL.md` states the rule for future authoring.

Both gap files are kept with their resolutions rather than deleted, and
`web/gaps.html?key=designloop/designloop` shows them closed with the options they offered.

## Next up

**Nothing in this stream.** The owner is already *using* it — Spotlight's phase 1 shipped against
it — so the next job is that design, not this tool.

1. **`solatro/design/spotlight/` is IN PROGRESS.** Do not reset it, do not answer it, and do not
   delete its `answers.*`. Park on `npm --prefix designloop run watch -- solatro/spotlight` —
   parking is visible to the owner: the screen's chip goes green while a watch is beating.
2. ~~Fix QR8~~ and ~~look at the gaps page~~ — **both done.** `run check` reports `warnings 0` on all
   three real designs.
3. **This tool's OWN DESIGN.md has four defects its check reports and nobody has acted on** — the
   dogfood failing: `Q10` and `QR6` gate questions (1 and 7) without being marked `⚑gate`, so a
   free-text answer to either prunes them silently; `S15` cites `Q95`/`Q96`/`Q97`, which do not
   exist; `S17` cites nothing and can never be reported stale.

### S20 — PROVENANCE

`src/provenance.mjs` + `⚑contract` in the grammar + `GET /provenance` + two `check` subcommands.
**The incident that motivated it is written at the head of the module and is worth reading before
touching any of it:** one free-text answer, two documents paraphrasing it, both dropping the clause
that settled it, and an executing agent filing a gap on the difference between the paraphrases.

The reports are `in prose`, `unquoted` and `contracts`; like every other audit here, none of them
blocks. The ID scanner matches GAP ids as well as question ids — gap answers are free-text by
construction and were invisible to every report, silently. `quoteAudit` hoists its per-document work
(it was O(answers × doc bytes), ~700 ms on Spotlight per request).

⚠ **What is NOT built: the canvas has no contracts panel.** The owner reviews flowcharts; `PLAN.md`
§1 — which is what an executor actually obeys — is still reviewed only by being read in chat.
`GET /provenance` serves the data a panel would need. `.claude/skills/flowchart-design/` §8b item 9
carries the process half in the meantime.

### Copy-paste opening prompt for the next agent

```
The Design Loop tool (designloop/) is FINISHED — every step of
designloop/design/designloop/PLAN.md, npm --prefix designloop test green, both gaps closed.
Read designloop/README.md first; designloop/HANDOFF_designloop.md is the build's live state and
stands alone.

If you are here to WORK ON THE TOOL: PLAN.md §4-§7 are NORMATIVE — the file formats, the question
grammar, the mermaid subset and the module APIs are specified, not suggested. DESIGN.md beside it
is the authority on behaviour; where the two disagree the design wins and the plan is wrong (read
the owner's written answers in DESIGN.md §9, not the plan's summary of them). Follow the gap
protocol at the head of the plan: a decision the plan does not cover is a gap file, not an
invention. The tool shows those gaps itself.

If you are here to USE it, that is the more likely job: solatro/design/spotlight/ is the owner's
paused Spotlight design, never edited. Start the server, hand over
http://localhost:5273/web/question.html?key=solatro/spotlight, and park on
npm --prefix designloop run watch -- solatro/spotlight. .claude/skills/flowchart-design/SKILL.md
is the procedure end to end.

Environment facts that cost time twice: the Browser pane is not displayed, so screenshots fail
there and OS key events do not reach the page — verify with read_page/get_page_text and dispatch
KeyboardEvents through javascript_tool. To actually LOOK at something, run
`node designloop/tools/shot.mjs <url> <out.png> [w] [h] ["js first"]` and Read the PNG. The Node
server has no hot reload, so preview_stop + preview_start after any src/ edit; editing web/ only
needs a page reload.

Keep this handoff updated after every task. Do not git add or commit.
```

## References

- `designloop/README.md` — what the tool is, how to start it, every screen and every file, and the
  gap loop. The entry point for anyone who is not resuming this build.
- `designloop/design/designloop/PLAN.md` — the build document; §3 the steps, §4 the interchange
  contracts, §5 the grammar, §6 the mermaid subset, §7 the module APIs.
- `designloop/src/graph.mjs` — the mermaid subset, with the reason for every refusal in the header.
- `designloop/src/gaps.mjs` — the gap file format, read as a draft question, and the stale-step
  computation, with why nothing is ever written back to a gap or to a plan.
- `designloop/src/layout.mjs` — the layout engine and its metrics; `ENGINE` is what a frozen version
  records so a later change cannot silently re-flow it.
- `designloop/src/versions.mjs` — Confirm, the freeze, the diff, and the generated renders.
- `designloop/design/designloop/DESIGN.md` — the authority on behaviour; charts A–J, §9/§12 the
  questionnaire and its answers of record.
- `designloop/design/designloop/ASSUMPTIONS.md` — every decision taken that the design did not
  cover, with why each is reversible.
- `.claude/skills/flowchart-design/SKILL.md` — the authoring rules, the gap protocol and its
  template, the handover procedure and the gap surface it drives.
- `solatro/design/spotlight/DESIGN.md` — the acceptance corpus, and the first real client. Paused,
  unapproved, and never edited by this build.
- `palette/tools/serve.mjs` — the dependency-free local server this one is modelled on.
