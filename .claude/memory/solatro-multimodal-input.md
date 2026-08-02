---
name: solatro-multimodal-input
description: All solatro UI must support mouse + keyboard + controller; focus steal/restore on modals
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 1777a13a-9a84-4d8c-b5c0-c68f53f14cb2
---

Every interactive UI in solatro must work with mouse, keyboard, AND controller (user demanded this after playtest 2026-07-07 found keyboard-dead viewers and an untraversable-by-keyboard map).

**Why:** Enter on a still-focused button re-triggered it and stacked infinite DeckViewers; arrow keys were dead in card viewers; map nodes were mouse-only.

**How to apply:** modal opens steal focus and restore it to the opener on close; ui_cancel always closes (ui_accept too for read-only views); selectable elements get `FOCUS_ALL` + a visible focus state (ControlCard lights its CardVisual); non-Control interactions (map nodes) handle ui_* actions explicitly (see WorldMapController._kb_cycle). Since 2026-07-13 `ui_accept`/`ui_cancel` are OVERRIDDEN in project.godot to bind joypad A/B (defaults lacked them) — the overrides must re-list the keyboard defaults too, since overriding a built-in replaces them. New input paths get real synthesized-event coverage in Tests/Interaction/test_interaction.gd. Related: [[solatro-project-facts]], [[godot-key-events-no-bubble]].
