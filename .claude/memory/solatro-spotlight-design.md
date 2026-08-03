---
name: solatro-spotlight-design
description: solatro/design/spotlight/DESIGN.md (started 2026-08-01, version 2 on 2026-08-03) is a DESIGN-ONLY flowchart plan for the Spotlight mechanic + its VFX — nothing is implemented until every node and question is approved
metadata: 
  node_type: memory
  type: project
  originSessionId: c2e12eb4-4da5-425b-b1c7-49fb8ac3a906
  modified: 2026-08-01T12:18:13.757Z
---

`solatro/design/spotlight/DESIGN.md`, written 2026-08-01 via [[repo-claude-tooling]]'s
`/flowchart-design` skill. **NOT approved — nothing may be implemented yet.** Round 1 is IN
PROGRESS in [[designloop-tool]] (`question.html?key=solatro/spotlight`); the implementation plan is
a SEPARATE doc written only after the flowcharts are CONFIRMED, not after the last answer
([[design-review-ends-with-handoff]]).

⚠ **§17 is a branching DAG, not a list.** Measured by the parser, **version 2 (2026-08-03): 248 live
questions, 10 `⚑gate` roots QR1–QR10, longest path 236, 18 charts, 0 errors/warnings.** (v1 was 195
live / path 194 / 8 roots.) Every question carries a gate in backticks (`[Q4=b|c]`), lettered
options, and a recommended default so *default* is a complete answer. Q140 is retired in place —
**IDs are never renumbered.**

**Version 2 exists because two round-1 answers were written in the owner's own words**, one of them
at a `⚑gate` (which is what ends a round). Both became real options rather than replacing anything,
and the §17.6 gates were widened to `[QR2=a|c]` so answers already given survive the switch:

- **QR2 (c) — the TRANSIENT dim.** The dark lasts only the opening beat (lights spawn, first meld
  jumps and scores), then back to a normally lit board for the rest of the act. Chart S, §17.6b.
- **Q24 (c) — COMPACT AND FOLLOW.** A meld card discarded mid-line: the column closes up (free — a
  column is a plain array, `game.gd:613`), the covering card slides into the slot, and the light
  follows the SLOT and force-spotlights the new occupant. Chart R, §17.2b. Q160 said the opposite
  and is re-gated.
- Plus a glow-shader braindump → **QR9** (is the spotlight circle drawn by the glow shader, and does
  it move onto the card?) and **QR10** (the halation/bloom/LUT/grain film pipeline — in scope?).

⚠ **Chart naming drifted and is now pinned.** Charts A–L were named by heading while their node
prefixes ran one letter ahead from §7 on (heading *Flowchart G* holds nodes `H1…`). v2 charts are
named by their own prefix (O, P, R, S). The prefix is the truth.

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
- **The glow needs almost no new machinery, and §1.6 has the audit.** `FxAttachment` IS a `Node2D`
  any host parents, so "a glow for cards and props" is one `.gdshader` + an `FxGlowStyle` SUBCLASS
  (never knobs on the `FxStyle` base) + a request. `FxRequest.reach` already lets an effect hang off
  the card's edge. **"Can overlap object pixels unlike the fire shader" is literally
  `u_inner_alpha < 1`** — an existing uniform no shipped style uses, because the owner ruled seeing
  art through flame *"looks very bad"*.
- ⚠ **There is NO screen read anywhere in this project** (grepped 2026-08-03: zero
  `SCREEN_TEXTURE` / `hint_screen_texture` / `BackBufferCopy` / viewport-texture hits outside
  `addons/`). So halation, bloom, film LUT, chromatic aberration, gate weave, dust and HDR
  tonemapping are a full-screen subsystem that does not exist and would change the WHOLE game's
  look — that is why they are QR10 and not a shader detail. Multi-layer glow, inverse-square
  falloff and the core→mid→edge colour shift need none of it (the shift is one `PaletteRamp`
  sample, which is what the palette contract wants anyway).

See also [[solatro-game-view-split]], [[solatro-structural-layering]],
[[solatro-pooled-board-controls]], [[solatro-tuning-knobs-in-settings]].
