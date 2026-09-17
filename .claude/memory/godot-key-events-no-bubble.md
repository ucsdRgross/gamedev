---
name: godot-key-events-no-bubble
description: Godot 4 key/joypad events go ONLY to the focused control — no ancestor bubbling (mouse bubbles); focus never crosses a viewport, and grab_focus() clears every other viewport's owner in the window
metadata:
  node_type: memory
  type: reference
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

**Focus and viewports, measured on the same code:** the focus-neighbour search never crosses a
viewport, so a HUD in the root viewport and a board in a SubViewport are two separate focus
worlds and a pad reaches the other only through a handler that grabs on its behalf. And
`Control.grab_focus()` clears the focus owner of EVERY viewport in the window — a grab in the
root viewport nulled a SubViewport's pad cursor. A control that leaves the tree (a detached
grid) releases its focus, leaving no owner at all. So: read the owner BEFORE a detach to know
whether a pick came by focus, grab on the pad's behalf only then, and rest the focus back inside
the viewport the pad was in.

**How to apply:** never handle focus-driven key actions in a parent's `gui_input`; test
input paths with real synthesized events (see `Tests/Interaction/test_interaction.gd`),
not direct handler calls — and assert the FOCUS OWNER after any pad route, in the viewport the
pad must move on next; a row that asserts only the state change is green while the pad is
stranded. Related: [[architecture-map]], [[tests-that-prove-nothing]].
