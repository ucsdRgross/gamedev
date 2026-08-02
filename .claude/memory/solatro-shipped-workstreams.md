---
name: solatro-shipped-workstreams
description: "Solatro workstreams that are DONE and owner-accepted (suit-props 2026-07-13, scoring/goal rework 2026-07-17) — live spec is ARCHITECTURE_REVIEW, plan docs deleted, do not relitigate"
metadata: 
  node_type: memory
  type: project
  originSessionId: 75157de2-6326-43ea-b7df-1a25b81a7de6
  modified: 2026-07-30T21:59:29.022Z
---

Two big Solatro workstreams are finished and owner-accepted. Their plan/handoff docs were
deleted 2026-07-19 (git history keeps them; `START_HERE.md` maps old §citations that code
comments still use). **Read the live section in `solatro/ARCHITECTURE_REVIEW.md` first for
any bug in these areas — not this memory, and not the git-history plans.** Do not reopen the
settled designs.

**Suit-props — COMPLETE 2026-07-13. Live reference: ARCHITECTURE_REVIEW §4.**
Suits as prop-spawners (hoop/knife/ball/fire/firework), statuses, PropModifier hooks,
integer-tick simulation; §4 holds the architecture, landmines, formations, knobs and recipes.
Durable rulings: props are NOT CardModifiers (parallel PropModifier system, transient data,
never serialized); data runs one tick AHEAD of the view; travelers pass their own origin card
(knives self-score by design); reactions play at visual arrival from pure hints; a same-act
fire cascade is intended; tick math is all-integer so [[solatro-persistence-gotchas]] replay
stays deterministic. Retired plan doc: SUIT_PROPS_PLAN.md v3.2. Draw-order / hoop bracket
rules live in [[solatro-structural-layering]].

**Scoring + goal curve — COMPLETE 2026-07-17. Live spec: ARCHITECTURE_REVIEW §3.**
Act payout = R×C×(1+0.1·U) with meld-class combo; goal = G0·(N̂/N0)^ALPHA·difficulty·BOSS^b·LAP^lap
from boosters_on_path. **Overscore was retired deliberately — never punish overperformance, it
breeds sandbagging.** All knobs sit in `player_settings.gd` "Balance —" groups
([[solatro-tuning-knobs-in-settings]]). Sim oracle: `py solatro/tools/scoring_sim.py --final
--q 0.35`; known drift — it fits g0≈140/α≈2.03 against shipped G0=130/ALPHA=4.2, and the owner
is not worried, so arbitrate with them before any recalibration. Remaining work is owner-side
parameter tuning plus the playtest questions in `solatro/todo.md`; the playtest protocol and
acceptance bands are in git-history SCORING_MATH_PLAN §10/§11 if a playtest phase starts.
Retired plan docs: SCORING_MATH_PLAN.md, SCORING_IMPL_PLAN.md, SCORING_AUDIT.md.

See [[solatro-project-facts]] for the doc map and the doc-hygiene policy that deleted these plans.
