# ASSUMPTIONS.md — reversible decisions taken while executing PLAN.md

- `HudContainer`'s children are authored in `hud_container.tscn`, so `HudContainer.new()` yields a
  bare `PanelContainer` with no children. `TestSidebar` instantiates `hud_container.tscn` instead,
  still with no `Main` and no wall in the tree (C1, Q150).
- `Main.enter_game()` hands its wall's own `HudContainer` to `GameView.hud_container` before
  attaching the view, so `_bind_hud_container()` binds to exactly that wall's container. A
  standalone fixture with no `Main` leaves it null and gets a private `HudContainer` as its own
  child instead -- same scene, same accessors, freed with the view like everything else it owns.
- TEST_PLAN 3.4 expected the board's centre to MOVE when `%MultScore`/`%Preview` were deleted. It
  cannot: the inset was `_hud_authored_width() * hud_scale()`, which is `0.25 * 1576` = 394 whatever
  the widest control. Measured pre-deletion centre 733.808; 3.4 asserts it is unchanged (C4, L9).
- `HudContainer.set_active_screen(screen: StringName)` is a new method NAMES.md does not list: it
  takes `Main`'s own focus id (`&"game"`, `&"map"`, `&"start_menu"`, `&""`) rather than inventing a
  second enum, since that id is already the one thing every call site has in hand (C13, Q83).
- GAP-003 corrects D11/`Q247`=a: the map DOES sit in a picture, so `Map._publish_map_inset()`
  converts the container's window px through `WallPicture.local_rect_beside()`, the same conversion
  `Menu` uses, into the shift from screen centre to the space left over beside the container.
  `Camera2D.offset` is a world offset the engine multiplies by `zoom` before it reaches the screen
  (`Camera2D::get_camera_transform()`), so `WorldMapController` divides the shift by its own zoom
  and re-applies it on every zoom change, not only when the container moves.
- The menu's own inset (Q22=b, Q27) scales and centres the WHOLE menu (title and buttons alike) in
  the space beside `container_rect()`, uniformly (one factor on both axes, never distorting a
  glyph) and only once its own authored content bounds -- title, buttons and the run row union'd,
  not the window's empty margin around them -- would not otherwise fit there.
- `Menu.hud_container` falls back to a private instance when null, the same shape `GameView`/`Map`
  already use -- `Tools/wall_editor.gd`'s preview hosts a real `menu.tscn` with no `Main` in the tree.
- The menu's inset conversion (review finding 2) reuses `GameView`'s own UNMARGINED `picture_scale`
  shape rather than the live camera transform: `Menu._apply_container_inset()` runs mid-`WallPicture.
  build()`, before `Main` positions the focused camera, so a transform read off the screen sprite at
  that point is still the unfocused identity. `WallPicture.local_rect_beside()` is the one owned
  conversion (window px beside `container_rect()` -> this picture's own space), called by `Menu` and
  by the SIDEBAR suite's own menu geometry tests.
- Hygiene pass: `HudContainer.ensure(existing, parent)` is a new static factory NAMES.md does not
  list -- it replaces the `if hud_container == null: instantiate a private container` fallback that
  `GameView`, `Map` and `Menu` each repeated. `connect_for_screen()`/`disconnect_for_screen()` are new
  instance methods on `HudContainer` that replace each screen's own `_connect_container()` /
  `_container_connections` teardown pair, since the container (not any one screen) is what outlives
  the connection and should own dropping it.
- Hygiene pass: deleting the tautological entrance-offset test (item 8) also removed the only
  `state.grids` text in `test_sidebar.gd`, tripping `test_game_headless.gd`'s zone-only-test ratchet
  (the file still names `upper_zone` in a real, grid-backed test). Restored the sanity check "a fresh
  show deals at least one grid" into `test_a_top_case_resize_fits_the_board_under_the_band`, which
  already exercises a real grid via `pa.grid_container` -- the ratchet's marker list just did not
  recognise that spelling, so the smaller fix is real grid-marker text, not a marker-list change.
- Hygiene pass: `game_view.gd`, `map.gd` and `menu.gd` decided `container_is_top()` off
  `SettingsManager.settings` while `HudContainer.container_rect()` (and `PlayArea.game_picture_design_size()`
  in `game_view.gd`) already read `PlayArea.settings()`, which honours `WallPicture.editor_settings`
  -- so `Tools/wall_editor.gd`'s override reached the container's size but not which band it sat on.
  All three now pass `PlayArea.settings()`, matching the source `container_rect()` already uses.
- `board_inset_left`/`board_inset_top` divide by the UNMARGINED `picture_scale` (`max(window/1576,
  window/887)`), not `WallPicture.focused_scale()` (which adds `wall_overfill_margin` when the two
  axis ratios differ). Measured at 1280x720 (side case, container 320 window px wide):
  `picture_scale` 0.812183 gives `board_inset_left` 394.0 picture px (the gate); the live camera's
  `focused_scale` 0.828427 puts the rendered board edge 6.4 window px right of the container's own
  edge -- a gap, never an overlap, so the 394/262.7 gates stay on `picture_scale`.
- S5: `DescriptionPanel.show_entry(entry, panel_size)` and `detach_entry()` are new methods NAMES.md
  does not list. The panel is HANDED the container's own `container_rect()` size rather than reading
  a width knob, because `InfoCard`'s `wall_info_card_*` knobs are S9's to delete (C5, B2).
- S5 ownership, one rule: the PANEL owns the visual while it is mounted and frees it when another
  entry replaces it; `HudContainer` owns each screen's remembered entry -- detached (not freed) on
  leaving that screen, re-mounted on return, and the detached ones freed in `_exit_tree()` (Q19=c).
- S5: per-screen memory lives on `HudContainer` as `_entry_by_screen`, with `_stash_description()`
  and `_restore_description()` hanging off the existing `set_active_screen()` -- that focus id is
  already the only key every call site has in hand (B15, B16, Q20=b).
- S5: the description's card visual is built in `CardVisual.DisplayContext.PREVIEW` and drawn at
  `PlayArea.board_card_window_px()` -- `card_size_play` times the live `board_zoom` times
  `picture_to_window_scale` -- because Q34=b's "the board's own card size" is the size a board card
  is DRAWN at on screen, and the container lives in window px outside the picture (measured at
  1280x720: 40 px flat against a board card's 57.6 px). New names NAMES.md does not list:
  `PlayArea.picture_to_window_scale` (pushed by `GameView._publish_board_inset()`, the same seam
  `board_inset_*` crosses the other way), `PlayArea.board_card_window_px()`, the `card_px` parameter
  on `PlayArea.card_info()`, and `CardVisual.preview_size`.
- S5: `picture_to_window_scale` is `WallPicture.focused_scale()`, NOT the unmargined ratio
  `board_inset_*` divides by. Measured at 1280x720: the picture's live screen sprite draws at
  0.828426 and `focused_scale` returns 0.828427, while the unmargined 0.812183 would miss a board
  card's drawn width by 1.1 px. The inset reserves board SPACE; the preview matches drawn PIXELS.
- S5: the preview's size is carried by `CardVisual.preview_size`, applied inside
  `recalculate_size()`. Measured, by eye, after both shortcuts failed: a `Container` resets its
  children's `scale` on every layout pass, and `CardVisual._ready()` re-runs `recalculate_size()`,
  so a card scaled or sized from outside is back to its context's size the frame it is mounted.
- S5: the 1.2 test's `card_size == card_size_play` check was RETIRED, not moved: it asserted the
  size this fix corrects. `test_the_preview_is_drawn_at_the_boards_own_card_size` replaces it with
  a stronger claim -- the preview's DRAWN width against a real board `CardVisual`'s, both measured
  through the engine's own transforms, plus the name sitting to its right (Q33=c).
- S5: "frozen" is `CardVisual.floating = false`, which stops the idle and snaps the card face-on --
  the one flag the rig's own animation runs off (Q35=b).
- S5: the top row is the visual LEFT, the name right -- the notecard's own arrangement rotated for a
  tall panel, which is what `Q33`=c names. The body sits below, at the panel's full width.
- S5: `PlayArea._publish_focus_description(control)` is a new private method: every highlight
  publishes from `on_control_focus_entered`, so hover and key/pad share one site (B1). The click
  emits and their Info-mode gate are untouched.
- S5 corrects the step brief: while `wall_info_mode` is on the legacy `InfoCard` takes the entry
  INSTEAD of the container, not as well. Both surfaces reparent `entry.visual` and a node has one
  parent, so exactly one may own it; Info mode is off by default and S9 deletes the branch.
- S5: `test_wall_focus.gd`'s dropped-entry test asserted the pre-S5 rule (Info mode off => the
  visual is freed). Re-aimed at the rule that replaces it: whatever SHOWS the entry owns its visual.
- S6: the click route is `PlayArea.data_selected` -> `GameView._on_data_selected`, which calls
  `hud_container.lock_to(PlayArea.card_info(data, board_card_window_px()), data)` BEFORE the game
  action and pushes `play_area.locked_data = data`; the container's `description_dismissed` comes
  back through `GameView._on_description_dismissed()` to clear it. The board never decides what is
  shown -- it publishes, and the view relays in both directions (B5, Q56=a, PLAN 2).
- S6: new names NAMES.md does not list -- `PlayArea.locked_data`, `PlayArea._refresh_card_marking()`,
  `PlayArea._publish_info()`, `GameView._lock_description_to()`, `GameView._on_description_dismissed()`,
  `HudContainer._description_size()`, `HudContainer._place_exit_button()`, the `ExitLayer`/`%ExitX`
  nodes, and `DescriptionPanel.resize_to()` (S5's `_resize_to`, now also called on a resize).
- S6: Q58=c's marking is `CardVisual.focused`, applied by ONE rule -- a card is marked while it holds
  the board focus OR while the sidebar is locked to it -- and re-applied at the end of
  `set_card_zones_visuals()`, so a rebuild marks whichever visual now represents that card (B13).
- S6: the exit X's FACE is the glyph `X`, not a localised word: the same shape the overlay's
  magnifier button already uses, with the localised `SIDEBAR_CLOSE` as its tooltip (Q47=a, C16).
- S6: the exit X hangs off a full-rect `ExitLayer` `Control` inside `hud_container.tscn`, because a
  `PanelContainer` fits EVERY direct child to its whole rect. It is anchored to the container's own
  right edge and offset down by `_band_top`, so the engine's layout keeps it in the corner on resize.
- S6: `show_hud()` emits `description_dismissed` on every revert to the HUD, a screen change
  included -- PLAN 1.2 makes it the one place the swap and the lock clear, so it is the one
  announcement too.
- S6, measured: `_size_stack_slot()` leaves an OCCUPIED slot's own zone control `FOCUS_NONE` and
  zero-height while it stays in `ui_data`, so neither a click nor a key can land on it. The suite
  filters its click/focus candidates on `focus_mode` rather than trusting `ui_data`.
- S6, measured: the description panel's WIDTH already followed a resize through the engine's own
  layout pass; what did not follow is the content height `resize_to()` computes, so
  `_apply_container_rect()` re-runs it for the entry already up.
- S6 hygiene: the no-listener guard stays in `PlayArea` as `_publish_info()`, the ONE publish site
  for the highlight and for both Info-mode click emits -- smaller than teaching four bare
  `play_area.tscn` fixtures to connect a freeing sink, and it keeps the ownership rule in one place.
- S6b: "the pointer left every card" is a new `PlayArea` signal, `highlight_cleared`, NAMES.md does
  not list it. Two triggers, one signal: the per-control `mouse_exited` publishes only when
  `_card_control_at()` finds no card under the pointer (card to card is silent -- the card being
  entered publishes its own description), and `focus_exited` publishes through a DEFERRED connection
  because at `focus_exited` the viewport has dropped the old focus and not yet taken the new one, so
  the owner reads null however the focus is moving. Focus onto an overlay HUD control counts: Godot
  clears focus across every viewport sharing one base window.
- S6b: the container answers it with `return_to_lock()` and keeps `_locked_entry_by_screen`. A hover
  that displaces the locked entry DETACHES its visual instead of freeing it (the same handoff the
  per-screen memory uses), so returning re-mounts the very node the lock was shown with; `clear_lock()`
  and `_exit_tree()` free it when it is still detached. New names NAMES.md does not list:
  `HudContainer.return_to_lock()`, `showing_description()`, `_detach_locked_entry()`,
  `_free_detached_visual()`, `PlayArea.highlight_cleared`, `PlayArea.description_dismiss_requested`,
  `PlayArea._publish_pointer_left_cards()`, `PlayArea._publish_focus_left_cards()`,
  `GameView._on_description_dismiss_requested()`.
- S6b: cancel and a bare-board press both publish `description_dismiss_requested`; the VIEW decides
  whether the event is spent, because only it sees both the board's ask and the container's
  `showing_description()`. A cancel with nothing showing is left alone, so `Wall.back_requested`
  still fires -- `Wall._unhandled_input` gives the focused picture first refusal by reading that
  viewport's own `is_input_handled()`, so consuming inside the board is what suppresses Back.
- S6b: `Tests/Visual/sidebar_snapshot` gained `description_follow.png`. Its hover walks Entrance
  candidates until `moused_hovered_control` reports the landing -- a control's own centre is not
  always hit-testable, and the first version silently re-shot the locked card instead.
- S7: new names NAMES.md does not list, all on `HudContainer`: `set_processing(busy)` (the method
  `GameView._on_processing_changed()` relays `Game.processing` through), the const
  `PROCESSING_SCREEN` = `&"game"`, `_processing_screen`, `_screen_is_processing()` and
  `_drops_publication()`. The rule is scoped by that const rather than by whichever screen happened
  to be active at the flip: `Main` sets the active screen at the END of `enter_game()`'s transition,
  after `GameView._ready()` has already run, so a latched screen id would be wrong for a show that
  starts processing during its own boot (C10, Q260b=b).
- S7: `return_to_lock()` needs no processing guard of its own -- `show_hud()` clears the lock and
  `lock_to()` is dropped while processing, so `is_locked()` is false throughout a cascade and the
  method is already a no-op (B18, B19).
- S7: a publication dropped mid-cascade is FREED, not orphaned: the entry carries a live preview the
  board built for it, and the container is the listener that took delivery of it. Returning to a
  screen that is mid-cascade therefore lands on the HUD rather than re-showing that screen's
  remembered entry -- re-showing it would free a visual the memory still points at, and the HUD is
  what the cascade is watched in anyway (B17, C8).
- S7: the rule reaches a screen, not a container, so a standalone `GameView` fixture with the
  private container `HudContainer.ensure()` builds (`_active_screen` is `&""`, the wall-view value)
  is untouched by it. Every product path has `Main` setting `&"game"` first.
- S7, measured: a placement that completes no line resolves inside ONE frame -- `_broadcast_board_mutation`
  only holds `processing` across `run_all_mods(&"on_board_mutated")`, which animates nothing when
  nothing scores. So `TestSidebar`'s real-cascade row asserts the HUD at the FLIP (via
  `processing_changed`) as well as per frame, and `Tests/Visual/sidebar_snapshot` keeps placing
  until a cascade lasts long enough to photograph -- the 5th card into one cell, which is where
  `LineGeometry.height_line_scores` first fires.
- S7: `sidebar_snapshot` gained `description_processing.png`. Its placements are issued through
  `PlayArea.data_selected` (the board's own selection signal, which `GameView._on_data_selected`
  answers) rather than a synthesised click on the cell -- the click path is already photographed by
  the locked and follow stills -- and its targets are filtered to GRID cells, because stacking
  inside the Entrance is a legal move that runs no mutation pass and so cascades nothing.
  `_click_an_entrance_card()` now walks the Entrance until the board reports the grab, since only
  some of those controls are grabbable once the board has been played into.
