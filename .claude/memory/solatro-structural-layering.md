---
name: solatro-structural-layering
description: Board draw order is 100% structural (no z_index); hoop passes through cards via bracket nodes; test suite deadlock rule
metadata: 
  node_type: memory
  type: project
  originSessionId: fcc8ebf5-ee2e-47a4-ae9c-f2f415a0ada4
---

The solatro board (`Levels/game_view.tscn` → `UI/play_area.tscn`) draws on ONE canvas (no
`CanvasLayer`). As of 2026-07-15 every board `CanvasItem` stays at **`z_index == 0`** and draw
order is purely tree/sibling structure. Full reference: `solatro/LAYERING.md` (linked from
ARCHITECTURE_REVIEW §1.6).

- `TopLevelVBox` children: `CardLayer → PropLayer → OverlayLayer` (later sibling = on top).
- Cards ordered by guarded `move_child` in CardLayer (`play_area.gd _order_board_cards`), NOT z —
  ROW-MAJOR ACROSS COLUMNS per zone since 2026-07-16 (headers, then row 0 of every column, …):
  visually identical for cards (they only overlap within a column) but rows are CONTIGUOUS so a
  split prop can bracket a whole row. Targets 0,1,2,… assigned only to verified deduped current
  children → move_child index-safe by construction (an absolute ordinal once overran the child
  count → crash). CRITICAL: fresh visuals add_child via call_deferred in COLUMN-major creation
  order, so `_order_board_cards` queues ONE deferred re-order when it skipped pending visuals —
  without it a fresh board silently kept the wrong order (11 test failures + wrong hoop brackets).
- **Hoop pass-through:** a split prop (`PropVisual.has_back_half()`) renders as TWO `_PropHalf`
  nodes in CardLayer that bracket the card's WHOLE ROW (2026-07-16, needs row-major order): back
  in the inter-row gap before the row = behind every card in the row / above earlier rows; front
  after the row = in front of the whole row / below later rows (`_apply_split`+`_row_bounds`;
  OK positions are RANGES so multiple hoops per row don't churn). `_update_back_halves` mirrors
  the prop's transform+modulate onto both halves each frame (single fade source). `_draw_back(into)`/
  `_draw_front(into)` must draw onto the passed node, NOT self (drawing outside a node's own
  `_draw()` is illegal in Godot). Editor preview draws the full body via `_draw_body()`.
  Bracket ROW = the prop's ANCHOR SLOT row (`vis.anchor_coord`), NEVER guessed from geometry —
  fanned cards are a full card tall behind their visible strip, so "which card is under the
  ring" picks a short column's top card at an empty-row crossing (wrong row, 2026-07-16).
  Geometry only gates WHETHER to split: `PropVisual.body_size` (hardcoded per kind like
  CARD_SIZE; props have WIDTH — never center-point tests) must overlap a card footprint
  (`_body_over_any_card`); nothing under → unsplit whole ring.
  Hoops take NO formation offset (kind 0 skipped in `_assign_formation_points`) — ring threads
  the card center. Formation offsets + prop art scale are LIVE settings reads every frame
  (`_refresh_lane_offset`, `vis.scale = card_scale / PropVisual.AUTHORED_CARD_SCALE`); NEVER
  capture settings at spawn — the owner changes sliders mid-run and expects card-like response.
  `order_card_visual` clamps its move_child target (halves/deferred removals share CardLayer).
- **Slot geometry is PURE MATH** (2026-07-15): `play_area.gd slot_center_global` = zone hbox
  origin + column·(card width+separation) + separation + row·(strip+separation) + half-card
  anchor. NO control reads — never returns Vector2.ZERO, empty/short/off-board slots share the
  one formula. `control_for_coord` remains for focus/input only.
- **Formation points** (spread_by_separation) are STORED in full-card normalized space
  (`PropFormationSet.norm_to_strip`/`strip_to_norm`; ratio 1 = separation==card height); the
  formation editor edits the CURRENT strip's projection and converts on push/pull.

**Test infra (`Tests/`):** base class is `TestSuite` (`test_base.gd`). Suites that need exclusive
global state wait via `await_siblings_except([names])`. ⚠️ DEADLOCK RULE: if A waits for B, B must
NOT wait for A — a new suite once deadlocked the whole run. Order: engine/map → INTERACTION →
UI PROPS → VISUAL LAYERS → E2E. Output routes through `TestLog` (tees to
`user://test_output_all.log` + `test_output_errors.log`, overwritten each run; `all_tests.gd` has
a `terminal_output` ALL/ERRORS_ONLY dropdown AND an `@export speed_base_delay` (default 0.01,
near-instant) published to `TestLog.speed_base_delay` — animated suites read that instead of
per-suite FAST_DELAY consts; mid-flight-sampling tests keep their own absolute 0.3/0.4 delays —
both configured in `_enter_tree` so they beat child `_ready`). See [[running-godot-scenes]] — the two prop-landing checks in `test_ui_props`
(`test_prop_visual_lifecycle`, `test_slow_props`) are timing-flaky and were failing independent of
this migration.
