---
name: design-round-read-the-log
description: Picking up a /flowchart-design round — read answers.log for override:true, not just answers.json, and widen gates rather than replacing options
metadata:
  type: feedback
---

When resuming a questionnaire round in [[designloop-tool]], **`answers.json` is the current state and
`answers.log` is what happened.** Read the log.

**Why:** on 2026-08-03 the Spotlight round (see [[solatro-spotlight-design]]) held a free-text answer
at the `⚑gate` `QR2` — a genuine new branch, the kind that ends a round — and then, four minutes
later, the owner going back and picking `(a)` so they could keep answering instead of sitting
blocked. `answers.json` showed a clean `QR2=a` with no trace of it. **A reverted override is not a
withdrawn opinion; it is someone working around a missing option.**

⚠ **The severe version of the same bug: an unmarked gating question amputates its subtree in
silence.** A free-text answer has no letter, so a gate reading `[Q24=c]` can never be true. On a
`⚑gate` question that is handled — free text ends the round. On an unmarked one nothing happens at
all: the round rolls on and the whole subtree is skipped with no warning. Measured on Spotlight
2026-08-03: six unmarked gating questions, **20 questions never asked**, including nine written the
round before *for the branch the owner had explicitly asked for* — and the round still reported
`done (complete)`.

**✅ ALL OF THIS IS NOW AUTOMATED (2026-08-03).** `npm --prefix designloop run check -- <proj>/<slug>`
grew two report lines that did not exist when any of these defects shipped:

- **`dag audit`** — a question that gates others without the `⚑gate` mark; a `default` orphaned from
  a multi-letter gate it should be in; and a **section heading narrower than its own question
  lines** (the heading wins via `effectiveGate` — this is what stranded 20 answers).
- **`stale`** — chart nodes still posing an ANSWERED question as an open fork. Needs `answers.json`,
  so **re-run `check` after every answer round, not only after authoring** — that is exactly when
  nobody thinks to.

Neither blocks; each shape has a legitimate form. **A non-zero count is a defect until you have
looked and said why not.** `grammar.auditGates()` is the implementation, with three tests pinning the
exact shapes.

**How to apply:**

1. `grep '"override":true' answers.log` on every pick-up, including IDs whose current answer is an
   ordinary lettered option. Each hit is a branch to author.
2. The owner's words become a **new option** on that question, usually its `*default*` — never a
   replacement for an existing one, and never a rewrite of the question.
3. **Widen the gates below a gate that gained an option.** Children reading `[QR2=a]` strand every
   answer already given the moment the owner switches; the ones the new branch still needs become
   `[QR2=a|c]`. Say so at the section head *and* in the changelog — "did my work just get thrown
   away" is the owner's first question.
4. Name the exact re-ask list in the changelog and in `status.agent.json`'s summary. "Two questions
   have a new option to click" is a very different message from "the round restarts".
5. `npm --prefix designloop run check -- <project>/<slug>` must come back **0 errors, 0 warnings,
   0 unresolved links** before handing the turn back, and it re-measures the counts so the
   document's own "measured, not estimated" line can be updated instead of guessed.

⚠ **CHARTS ARE WRITTEN AFTER THE FIRST ANSWER ROUND, NOT BEFORE** (owner, 2026-08-03: *"no way will
chart ever be accurate before first question round"*). Sketching the flow is still how you FIND the
questions — a step you cannot draw is a decision you have not noticed — but the sketch is scratch,
not an artefact, and publishing it is what makes you patch instead of re-derive. **And never draw a
question's option set as a chart fork**: before the answer it repeats the question, after it it is a
lie. That one instruction (since deleted from the skill) produced Spotlight's worst charts — a whole
chart offering three origin models, a node branching on three answers to a root gate. On a later
round, RE-DERIVE the charts from the answers rather than patching the nodes you happen to remember;
patching is how 20 stale nodes accumulated across 11 charts.
