---
name: no-mocks-in-tools
description: "Owner standing preference — tools and harnesses must host the real scene/art, never a hand-built stand-in"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 3f18e406-f632-412e-9098-25e0edea0130
  modified: 2026-07-30T03:59:06.519Z
---

Tools, editors and test harnesses must stand up the **real scene with real data**, not a hand-built
model of it. Owner (about the FX editor drawing a flat polygon where a card goes): *"no
placeholder art that isnt ever seen in game, and no useless mocks when you can just use actual original
scene, just like how hoop knife use actual art."*

**Why:** a stand-in cannot disagree with the thing it stands in for, so any tool built on one is
structurally unable to show the bug you are looking at it for. Measured twice on this project: the FX
editor drew the card's face from *the same array* the fire's mask was built from (so a face-vs-mask error
was invisible by construction), and the harnesses' `star_outline` card was 2.3–3.3 art units from any
pose the real rig makes — which made a 26.9-art-unit mask error look like a 2-unit one for weeks.

**How to apply:** prefer instantiating the shipped scene even when it costs guards. Cost paid once for
`CardVisual` in the editor: `Engine.is_editor_hint()`-safe settings access, and `@tool` down the whole
data class chain (a non-`@tool` BASE makes every subclass a placeholder — the type name survives and no
member does). If a stand-in is genuinely unavoidable, MEASURE how far it is from the real thing and say
so where it is used. See [[running-godot-scenes]] for verifying editor-only behaviour.
