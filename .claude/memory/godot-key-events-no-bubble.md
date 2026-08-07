---
name: godot-key-events-no-bubble
description: Godot 4 key/joypad events go ONLY to the focused control — no ancestor bubbling (mouse bubbles); container-root gui_input handlers for ui_accept/ui_cancel are dead code
metadata: 
  node_type: memory
  type: reference
  originSessionId: 7ebd1646-45bb-4f64-aa75-15d99765dbde
---

Godot 4 delivers keyboard/joypad events ONLY to the focus-owner Control; unlike mouse
events they do NOT bubble to ancestor Controls. A `gui_input` handler on a container root
silently never sees `ui_accept`/`ui_cancel` from a focused child. Unconsumed key events
fall through the Viewport's focus-navigation pass into `_unhandled_input` — put area-wide
keyboard/controller handling there (guard on `get_viewport().gui_get_focus_owner()` and
`set_input_as_handled()` when acting).

**Why:** it made Solatro's keyboard/controller card selection dead code for its whole life;
only the interaction test suite (synthesized events via `Input.parse_input_event`) exposed
it. The working handler is `UI/play_area.gd _unhandled_input`.

**How to apply:** never handle focus-driven key actions in a parent's `gui_input`; test
input paths with real synthesized events (see `Tests/Interaction/test_interaction.gd`),
not direct handler calls. Related: [[architecture-map]].
