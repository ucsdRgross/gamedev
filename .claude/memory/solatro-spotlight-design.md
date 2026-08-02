---
name: solatro-spotlight-design
description: solatro/design/spotlight/DESIGN.md (started 2026-08-01) is a DESIGN-ONLY flowchart plan for the Spotlight mechanic + its VFX — nothing is implemented until every node and question is approved
metadata: 
  node_type: memory
  type: project
  originSessionId: c2e12eb4-4da5-425b-b1c7-49fb8ac3a906
  modified: 2026-08-01T12:18:13.757Z
---

`solatro/design/spotlight/DESIGN.md`, written 2026-08-01 via [[repo-claude-tooling]]'s
`/flowchart-design` skill. **PAUSED and not approved — nothing may be implemented yet.** The
owner reviews it by answering 188 questions and pointing at flowchart node IDs (A1…N7). The
implementation plan is a SEPARATE doc written only after that.

⚠ **§17 is a branching DAG, not a list** (converted 2026-08-01): eight root gates QR1–QR8 come
first and prune whole sections; every question carries a gate in backticks (`[Q4=b|c]`), lettered
options, and a recommended default so *default* is a complete answer. Longest path ~150 of 188.
Q140 is retired in place (superseded by QR5) — IDs are never renumbered. §19 is the conversion
contract for [[designloop-tool]]; the owner is doing that mini project first.

Why it exists: the previous cycle (the FX editor) shipped from a plan that was not thorough
enough, so design decisions got made silently during implementation. Owner's bar: *"what I
describe in review of plan will have functionally no difference once implemented."*

Load-bearing facts the plan is built on, worth keeping even if the doc is deleted:

- **Spotlight already exists as `active`.** `CardModifier.is_active()` — rules card / StampGlobal /
  stage PLAY or ZONE / StampRevealing / else `game.is_data_topmost`. Only SKILLS are gated on it
  (`run_all_mods` fires type/stamp/status hooks with no activation check at all).
- **Board geometry:** a column is a VBox, a row is a child index across VBoxes; higher `z` draws
  later, sits lower and covers. A covered card shows only its top ~45 px of 125, and the card's
  32×32 art square is CENTRED, so a spotlight circle on a covered card is ~75% hidden — which is
  why the row must expand first.
- **Reveal precedent already ships:** held-stack expansion sets the control above the grabbed card
  to the full card size. Same operation.
- **`PlayArea.slot_center_global` is pure uniform-pitch math** and every prop anchors to it — any
  per-row expansion breaks it. Row score gutters must expand with their rows too.
- The two questions that restructure everything: **Q31** (is the spotlight set the whole line or
  just `result.meld`?) and **Q113** (beam origins screen-anchored vs content-anchored — the
  braindump contains both readings).

See also [[solatro-game-view-split]], [[solatro-structural-layering]],
[[solatro-pooled-board-controls]], [[solatro-tuning-knobs-in-settings]].
