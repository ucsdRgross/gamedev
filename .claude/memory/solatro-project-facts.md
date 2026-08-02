---
name: solatro-project-facts
description: "Solatro doc map (START_HERE.md is the entry point since 2026-07-19), core contracts, owner rulings, and engine gotchas"
metadata: 
  node_type: memory
  type: project
  originSessionId: dd5ea729-646a-4df9-bb88-96554d303e7d
  modified: 2026-07-28T11:28:54.672Z
---

Solatro runs on Godot 4.7. **Start any new Solatro session by reading
`solatro/START_HERE.md`** — the agent rules + planning playbook. **For visual-effects work
(fire, juggling, prop art, FX shaders) the entry point is `solatro/VFX.md`** (added
2026-07-28): map, runbook, backlog, known bugs; the contracts it points at live in
ARCHITECTURE_REVIEW §4g/§4h. The suite runs WINDOWED now (the PIXELS suite asserts on real
pixels and fails rather than skips under a dummy renderer). Doc structure since the
2026-07-19 consolidation: START_HERE.md (rules/workflow), ARCHITECTURE_REVIEW.md
(current-state architecture + all regression rules: scoring §3, props §4, undo §5,
memory §6, testing §7, owner rulings §8), LAYERING.md, HEADLESS_TESTING.md, todo.md
(backlog), DESIGN_DOC/DESIGN_RECOMMENDATIONS/DESIGN_REFERENCES (design). All old
plan/handoff/audit docs are deleted — git history keeps them; START_HERE.md has the
retired-doc → live-home map (code comments still cite old §numbers like
"SCORING_MATH_PLAN §15a"). **Doc hygiene policy (owner-endorsed): plan docs are
temporary — fold residue into ARCHITECTURE_REVIEW/todo and delete them once landed;
no dated history logs in living docs.**

Core contracts (authoritative copy: "MUTATION GUIDELINES" in `Scripts/board.gd`):
- All board mutations via Board/Game methods; each bumps `GameData.revision` AFTER the
  state is consistent. A missed bump = stuck UI (visible) + stale comparator cache +
  STALE POSITION INDEX (`GameData.position_of` is a lazy revision-keyed cache).
- PlayArea code reading ui_data/data_ui/data_card must call `flush_rebuild()` first.
- Per-act/per-show state that undo must rewind lives on GameData, never on Game.

Owner rulings (do NOT re-fix): B10 live iteration by design; S6 same-value
`stage_changed` re-emits relied upon; N8 score-array desync allowed;
skill_active_check stays per-mod-call (not batched); commented-out code rule (changed
2026-07-16): TODO if unimplemented, DELETE if implemented elsewhere; player drops move
with trigger_mods=false (drop hooks fire only from automated moves); Deck Maker kept
though orphaned.

Gotchas that caused real bugs: GDScript declaration-default values BYPASS property
setters; re-setting an equal `stage` clobbers `previous_stage` and kills animations;
`BigNumber` is the owner's RefCounted class — no `duplicate()`, invisible to
`duplicate_deep`, manual array copy required. My engine-behavior claims were wrong
twice — have the owner compile/run-verify them. See [[running-godot-scenes]],
[[solatro-tres-cyclic-backrefs]].
