---
name: code-style-lean-documented
description: "User wants low line count (delete unused code) but doc comments on every method's purpose; plans need references/sources for handoff"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d1c50448-488f-47c2-b749-5658dd6afef7
  modified: 2026-07-30T22:11:48.554Z
---

Keep lines of code low by REMOVING old unused code outright (no dormant paths), while ADDING `##` doc comments that explain each method's intended purpose. Plans should include a references/sources section for easy handoff.

**Why:** Requested during the worldgen addon restructure (2026-07-03); the codebase already follows a heavy-doc-comment style (see graph_placement.gd), and handoff-ready plans matter to them.

**How to apply:** When editing gamedev code, prune dead code in the same pass; give every new/rewritten method a `##` purpose comment; end plans with a references section. **Before deleting any doc, run `git ls-files <path>` first** — a plan file was once deleted while untracked, so git did not have it and the owner had to catch it. The doc-hygiene policy (fold residue into ARCHITECTURE_REVIEW/todo, then delete the plan) assumes the file is tracked. Use `/handoff` for handoff docs ([[repo-claude-tooling]]). Commented-out code rule in Solatro (owner ruling 2026-07-16, see [[solatro-project-facts]]): replace with a TODO comment if it describes unimplemented logic, delete outright if the implementation exists elsewhere.
