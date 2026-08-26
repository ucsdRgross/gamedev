---
name: charts-from-resolved-answers
description: "Never write a design chart node from the question line or from memory — render the chosen option's own words first, because reconstruction silently defaults to whatever you recommended"
metadata:
  node_type: memory
  type: feedback
---

**Write every flowchart node from a RENDERED answer sheet, never from the question text and never
from memory.** Start with the divergences:

```bash
node .claude/tools/answer_sheet.mjs <project>/<slug> --diverged
```

**Why:** `answers.json` stores an opaque LETTER. The letter's meaning lives back in the design
document, so writing a node means resolving it — and resolving it from memory silently defaults to
**the option you recommended**, not the one the owner chose.

Measured on `solatro/poker-patience`: **nine chart nodes across four charts stated my own
recommendation instead of the owner's answer. Every one was a question where the two differed; not
one node was wrong where they agreed.** The correlation was perfect — this is authoring bias, not
random error. The owner caught the first by eye and the audit it prompted found eight more.

**`run check`'s `stale` line cannot see this.** It flags a node posing an *answered question as an
open fork*; a node confidently asserting the *wrong answer* is ordinary prose to a parser. It is
self-consistent and it reads well. Only a side-by-side comparison against the resolved answers finds
it — see [[seam-checks-not-rereading]], of which this is an instance: two representations of one
fact (the answer, and the node) with nothing comparing them.

**Also treat a high divergence count as a fact about the questionnaire.** 57 of 314 answers overrode
the recommendation — more than one in six. So "the owner took the defaults" is never a safe
assumption when summarising what was decided, and any doc that leans on it is probably wrong
somewhere.

Full rule and the tool's own header: `/.claude/skills/flowchart-design/SKILL.md` §3b.
