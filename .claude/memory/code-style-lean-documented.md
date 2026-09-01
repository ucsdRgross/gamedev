---
name: code-style-lean-documented
description: "User wants low line count (delete unused code) but doc comments on every method's purpose, kept SHORT — state the rule, not the story; plans need references/sources for handoff"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d1c50448-488f-47c2-b749-5658dd6afef7
  modified: 2026-07-30T22:11:48.554Z
---

Keep lines of code low by REMOVING old unused code outright (no dormant paths), while ADDING `##` doc comments that explain each method's intended purpose. Plans should include a references/sources section for easy handoff.

⚠⚠ **NO COMMENT GOES INSIDE A METHOD BODY.** Owner rule, verbatim: *"comments dont exist inline of
methods, and only explains why the methods exists and nothing else. no historical stuff or what
method does since that can be read through the code."*

So a comment sits **above** the method, as a `##` doc comment, and says **why the method exists** —
not what it does, and not how it came to be. If an inline comment feels necessary, that is a signal
the code needs a name (extract the step into a well-named helper), not a signal it needs prose.
`py .claude/tools/doc_check.py` reports these as `inside a method`; the repo carries a large
standing backlog of them, so judge a regression by whether YOUR diff added any.

⚠ **A doc comment is a rule, not a story. Go straight to the point.** Same content, fewer words — every time. Cut in particular:
- **The narrative of how a bug was found** ("the first build did X, and that was wrong twice over"). Keep the rule it produced and the number it measured; drop the plot.
- **Facts that change nothing for the reader** — who reported it, what the old behaviour was, which session it landed in. Git has that.
- **The same fact restated at a second site.** State it once where it is enforced; elsewhere point at that name.
- **Line-number references** (`scoring.gd:811`) — they are dead references waiting to happen.
- **Design-process ids** (`Q183=a`, `GAP-017=c`, `S34`, `PLAN.md §1.8`) — they name a document the
  reader cannot see. State the rule the answer produced. Full rule, and why the traceability
  instinct produces this: [[design-ids-stay-out-of-code]].

⚠ **REUSE BEFORE YOU WRITE. Owner, verbatim:** *"reducing duplicate code as much as possible
and no reinventing existing setups, or using existing engine methods when available."*

Search for an existing helper before adding one, and prefer an engine method over a hand-rolled
one. Measured cost of not doing it: a bucket-growing helper was added to `GameData` that
duplicated `Game.resize_score_zone`, and `mantissa = 0` ended up stated in two files — the
existing one was also stricter, so collapsing them fixed a latent weakness as well.

⚠ **This rule was reaching nobody.** It lives here and in `/simplify`, but the `/plan-run` brief
template carries lines about tunable literals, design ids and registry names and NOT this one —
so implementer briefs never said it. **Put it in the brief.** The same shape of failure produced
26 card files reaching past a documented-but-unenforced boundary; where a rule matters, enforce
it with a gate rather than restating it.

**Why:** the codebase already follows a heavy-doc-comment style (see `graph_placement.gd`), and handoff-ready plans matter to the owner.

**How to apply:** When editing gamedev code, prune dead code in the same pass; give every new/rewritten method a `##` purpose comment; end plans with a references section. **Before deleting any doc, run `git ls-files <path>` first** — the doc-hygiene policy (fold residue into the living doc, then delete the plan) assumes the file is tracked, and an untracked file deleted that way is gone for good. Use the `/handoff` skill for handoff docs. Commented-out code rule (owner ruling, `solatro/START_HERE.md`): replace with a TODO comment if it describes unimplemented logic, delete outright if the implementation exists elsewhere.
