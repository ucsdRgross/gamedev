---
name: charts-from-resolved-answers
description: "Never write a design chart node from the question line or from memory — render the chosen option's own words first, because reconstruction silently defaults to whatever you recommended"
metadata:
  node_type: memory
  type: feedback
---

**Write every flowchart node from a RENDERED answer sheet, never from the question text and never
from memory** — `node .claude/tools/answer_sheet.mjs <project>/<slug> --diverged` first.

`answers.json` stores an opaque letter; resolving it from memory defaults to the option you
recommended. Measured: nine wrong chart nodes, every one on a question where the owner overrode the
recommendation, none where they agreed. `run check`'s `stale` line cannot see it — it is an instance
of [[seam-checks-not-rereading]].

Full rule, the measurement and the divergence count: `.claude/skills/flowchart-design/SKILL.md` §3b.
