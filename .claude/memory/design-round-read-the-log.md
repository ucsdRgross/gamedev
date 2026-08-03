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
