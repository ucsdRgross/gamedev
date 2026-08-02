---
name: solatro-pooled-board-controls
description: "PlayArea board Controls are pooled per slot — per-card control state must be re-derived in _bind_slot, not set-and-unset"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6521753d-01e7-41c5-96cb-36b929410efb
  modified: 2026-07-21T04:43:27.351Z
---

Solatro's `UI/play_area.gd` reuses board Controls **per column/row SLOT**: `set_card_zone` only creates/frees controls when a column's size changes, and `_bind_slot` rebinds the surviving control to whatever CardData now sits in that slot. So any per-card property written onto a control (mouse_filter, focus_mode, minimum size, metadata) is state that OUTLIVES the card it was meant for.

**Why:** the 2026-07-20 auto-Next bug. `grab_cards` set `MOUSE_FILTER_IGNORE` on the held card's control and only `ungrab_cards` cleared it — looked up by the held card's NEW position. Patience-0 folds a Next into `try_place`, so the board rebuilt while the grab was live; the IGNORE stayed on the old slot's control, which got rebound to a different card. Symptom: exactly one card per auto-Next totally uninteractable (no hover, focus, highlight, description, grab), surviving undo, healed only by restarting the game.

**How to apply:** write per-card control state as a pure function of current state inside `_bind_slot` (`c.mouse_filter = IGNORE if data in selected_cards else PASS`), so every rebuild self-heals. Also avoid mutating the board under a live grab — `Game` calls `view.release_grab()` before the auto-Next. Regression pin: `Tests/Interaction/test_interaction.gd::test_auto_next_leaves_no_dead_controls` (scans `pa.ui_data` for any control left at `MOUSE_FILTER_IGNORE` with nothing held). See [[solatro-structural-layering]], [[solatro-game-view-split]].
