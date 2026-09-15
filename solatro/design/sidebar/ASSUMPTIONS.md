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
  `PlayArea._publish_info()`, `GameView._on_description_dismissed()`,
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
  `HudContainer.return_to_lock()`, `showing_description()`, `_free_detached_visual()`,
  `PlayArea.highlight_cleared`, `PlayArea.description_dismiss_requested`,
  `PlayArea._publish_focus_left_cards()`,
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
  `PROCESSING_SCREEN` = `&"game"`, `_game_processing`, `_screen_is_processing()` and
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
- S8: `sidebar_scroll` is ONE action carrying BOTH directions of `JOY_AXIS_RIGHT_Y` (+1 and -1),
  because NAMES.md fixes exactly one name for it. Direction comes off the event's own `axis_value`
  and the rest position off `InputMap.action_get_deadzone()`, so neither is a literal. The LEFT
  stick is the navigation one: Godot's built-in `ui_up`/`ui_down` defaults bind the d-pad and the
  left stick, and nothing in `project.godot` overrides them (Q42=a).
- S8: `HudContainer` reads the scroll keys in `_input`, BEFORE the GUI pass, and marks the event
  handled. Measured against the code: `PlayArea._on_cell_gui_input` is the only place the board can
  hear an arrow, because the viewport's focus-neighbour search eats any arrow that finds a
  neighbour, and `Wall._unhandled_input` routes only what is left into the focused picture. Reading
  the arrows any later could not keep the board's own selection still while the sidebar scrolls.
- S8: a joypad reports an axis only when it MOVES, so the stick's deflection is held in
  `HudContainer._scroll_stick` and integrated by `_process`; a single event would scroll once and
  stop. `show_hud()` re-centres it, which is also what makes the stick inert behind the HUD.
- S8: new names NAMES.md does not list -- `PlayerSettings.sidebar_scroll_pages_per_second` (the
  scroll rate NAMES 5 has no knob for), `DescriptionPanel.scroll_by_pages()` and its
  `WHEEL_STEP_PAGES` const, `HudContainer._aim_scroll_stick()`,
  `_scroll_stick` and `_refresh_exit_focus()`. The unit everywhere is a PAGE of the description's
  own visible height: Godot's `ScrollContainer` steps an eighth of one per wheel notch, so an arrow
  moves `WHEEL_STEP_PAGES` and the stick's default 1.0 page a second is eight notches a second.
- S8: Q68=b is `%ExitX.focus_mode` -- `FOCUS_ALL` while the sidebar is locked, `FOCUS_NONE`
  otherwise, refreshed in `show_hud()` and `show_description()`. ⚠ Godot's focus navigation does
  not cross viewports: the board's cells live in the picture's own `SubViewport` and the X in the
  overlay's, so "navigation reaches the X" means the OVERLAY's own focus chain reaches it, never an
  arrow from a board cell. Accept on it is the engine's own `BaseButton` behaviour.
- S8: Q40=b needed no scene change -- `ScrollContainer.vertical_scroll_mode` already defaults to
  AUTO, which is exactly "shown when there is more content than fits". `TestSidebar` asserts both
  halves so a later edit cannot quietly change the mode.
- S8, measured: the root viewport stretches to a 1152x648 base, so `container_rect()` is computed in
  STRETCH pixels, not window pixels. At the shipped `container_size_fraction` NO card description
  can overflow the container at any window -- the top case leaves at least 169 px for 97 px of text
  and the side case at least 601 for at most 356. `Tests/Visual/sidebar_snapshot` therefore narrows
  the band to 0.1 through `WallPicture.editor_settings` for `description_scroll.png`. The real
  overflow arrives with S12's viewers; the rule itself is under test either way.
- S8 hygiene (bloat review on S6): three one-call-site helpers are inlined at their callers -- the
  lock in `GameView._on_data_selected()`, the locked-entry detach at the head of
  `HudContainer.show_description()`, and the pointer-left publish inside the card control's own
  `mouse_exited`. `HudContainer.clear_lock()` keeps its name: NAMES 3 lists it as a contract.
- S8 hygiene, measured: `PlayArea._publish_focus_left_cards()`'s `is_inside_tree()` guard is an
  `assert` now. Every production teardown frees the screen root and a deferred call on a freed
  object is dropped, so no production caller can reach it out of the tree; the full suite (the test
  helper that leaves a view in the tree's memory included) never fires the assert.
- S9, on Q21=(b): the wall-view picture hover goes with Info mode, so `WallPicture.get_info()` lost
  its last caller and is deleted with `_INFO_PREVIEW_SIZE`. `MapHoverPanel.get_info()` is a
  different method and survives.
- S9: the wall editor grows no sidebar preview toggle. It hosts the real `wall.tscn`, which already
  carries `HudContainer`, so `_listen_for_info()` publishes a hosted screen's entry straight to that
  container instead of to a tool-owned card.
- S10: `WallOverlay`'s `WALL_INFO` localisation row is deleted from `Locale/localization.csv` --
  Info mode was its only reader.
- S9: `_pose_tween`/`_kill_pose_tween()` in the wall editor go with the info animation, which was
  their only writer; the tool's camera poses are snaps again, as they were before Info mode.
- S9: `PlayArea._info_mode()` is deleted (no callers left). `_popups_allowed()` survives for S10
  and now reads `wall_screen_popups` alone.
- S9: `TestGameHeadless._gd_scripts_under()` is hoisted to `TestBase.gd_scripts_under()` so the 8.1
  check reuses it rather than duplicating the walker.
- S9: `TestWallFocus.test_the_four_wall_actions_...` is renamed
  `test_the_wall_actions_drive_a_real_navigate_back_forward_wall_cycle` -- there are three now.
- S9: `TestWallTransition.test_a_requested_move_keeps_the_settings_it_started_with` survives by
  flipping `wall_reduced_motion`, the only branch `sample_at()` still has.
- P2 review: a screen's container state belongs to the CONTENT that published it, not to the screen
  id `Main` reuses show after show. New names NAMES.md does not list: `HudContainer.release_screen(
  screen)` (called from `GameView._exit_tree()` right after `disconnect_for_screen()`, so the revert
  to the HUD it performs reaches no dying listener), `_release_shown_entry()`, `_swap_to_hud()`,
  `_release_remembered_entry()`, and the `screen` parameter on `_release_locked_entry()`.
  `PROCESSING_SCREEN` is renamed `GAME_SCREEN`: one const for the game screen's own focus id, read
  both by the cascade rule and by the view that releases that screen's state.
- P2 review corrects the S6 line "`show_hud()` emits `description_dismissed` on every revert, a
  screen change included": a SCREEN CHANGE IS NOT A DISMISSAL. `set_active_screen()` swaps to the
  HUD through `_swap_to_hud()`, which neither clears the lock nor announces one, so the screen being
  left keeps its lock AND its board keeps the locked card's marking -- which is what makes B15/B16's
  "exactly as you left it" true of the marking too, with no restore channel to invent. `show_hud()`
  is still the one place a real dismissal clears and announces.
- P2 review, measured: `release_screen()` frees the entry the panel is SHOWING itself rather than
  leaving it to the dictionaries. On a whole-tree teardown `HudContainer._exit_tree()` runs before
  `GameView._exit_tree()` and clears both dictionaries, so a visual detached after that point is in
  no dictionary and no tree -- 24 orphaned previews across the suite, 1057 leaked ObjectDB instances.
- P2 review: the description's preview follows the window. `GameView._publish_board_inset()` ends by
  pushing `play_area.board_card_window_px()` through `HudContainer.resize_preview()` ->
  `DescriptionPanel.resize_preview()`, which re-draws the mounted card and re-lays the content its
  height feeds. The MOUNTED entry only: a screen's stashed entry is re-drawn when the board next
  publishes into it. New names: `HudContainer.resize_preview()`, `DescriptionPanel.resize_preview()`,
  `ControlCard.size_preview_to()` (the three lines `PlayArea.card_info()` used to spell out).
- P2 review, measured: `card_info()` builds its preview in an `HBoxContainer`, never a
  `FlowContainer`. A flow reports the minimum size its last `_resort()` cached, so a re-sized card
  left `resize_to()` computing the content height from the size the card used to be (123 px carried
  against 162 px fresh). A box computes its minimum on demand.
- P2 review: Q68=b's "navigation reaches the X directly" is `ui_up` at the top of a LOCKED
  description, which moves the focus onto `%ExitX` instead of scrolling (`DescriptionPanel.at_top()`,
  `HudContainer._navigates_to_exit()`). It is the press that has nothing left to scroll and leaves
  the content upward, it reaches the X on pad and keyboard alike, and accept on it is the engine's
  own `BaseButton` behaviour. The S8 line "`Q68=b` is `%ExitX.focus_mode`" was the flag only.
- P2 review, measured: `DescriptionPanel.scroll_by_pages()` carries the sub-pixel remainder between
  calls. `roundi()` on each frame alone threw away every frame of a gentle stick on a short panel --
  0.25 deflection on a 40 px panel is 0.17 px a frame, and the scroll never moved at all.
- S10: `TestUIProps.test_focus_inspector_all_input_modes` is deleted whole with its subject. Its one
  unrelated assertion -- board controls carry no `tooltip_text`, the native tooltip window having
  blocked clicks -- goes with it; no surviving test owns that claim.
- S10: `TestVisualLayers.test_overlay_above_everything` keeps its claim and changes vehicle. The
  deleted panel was its occupant of `OverlayLayer`; the score-name `TextPopup` is the other
  production occupant and needs no scoring pass to exist.
- S10: `_process()` is stopped by `_ease_row_openings()`'s own return, which already reports the row
  openings AND the depth-layer growth. The measured rule (a row stuck at 54 against a container at
  74) moves onto `_process` with it.

- S11: `Q151`'s "opacity" is exposed as NOTHING. The design gives the container a flat opaque panel
  (`Q27`=d, C1) and no opacity knob exists; `HudContainer._ready()` takes its `StyleBoxFlat.bg_color`
  from the palette role `hud_background`, so the hosted wall already shows that colour live and that
  is the whole affordance the word was asking for.
- S11: `Q151`'s WIDTH is driven through `preview_settings.container_size_fraction` /
  `container_size_max_px` -- the panel the tool already has -- with no duplicate export beside them.
  What was missing was liveness, so `HudContainer._ready()` now connects
  `PlayArea.settings().settings_changed` to `_apply_container_rect()`: both knobs move the container
  with no window resize, in the settings screen as well as in the tool. A `preview_settings` resource
  REPLACED wholesale leaves that connection on the resource it was made against.
- S11: `Q151`'s SIDE is a read-only `WallEditor.container_side` readout (`"side  320 x 720 px"`),
  computed through `HudContainer.container_is_top()` and `rect_for_window()` rather than restated.
  No override, per §1.1 -- the soak reaches the top case by narrowing the WINDOW, the squeeze
  `sidebar_snapshot` already uses.
- S11: the wall editor does NOT hand its wall's container to the hosted screens. `Levels/menu.gd`
  records the private fallback container as that tool's deliberate arrangement, so
  `WallEditor.preview_locked_description` locks the WALL's container itself, off the hosted board's
  first card through `PlayArea.card_info()` -- a real entry, never a stand-in.
- S11: `WallEditor._apply_focus()` now makes the `HudContainer.set_active_screen()` hand-over `Main`
  makes on every focus change. Without it the tool's container showed the GAME hud over the start
  menu and stayed up in wall view, neither of which the game does.
- S11 new names NAMES.md does not list, tool-local and following that file's own `preview_*`
  convention: `WallEditor.preview_locked_description`, `WallEditor.container_side`.

- S12: a viewer's description preview is drawn at the size THAT VIEWER draws a card at, in window
  px -- `CardsViewer.card_window_px()` is `controls[0].child.card_size * picture_to_window_scale`.
  Q34=b's "the board's own card size, so it reads as the same object" is about the object the
  player is POINTING at, and inside a viewer that is the viewer's own card (L11, Q34).
- S12: viewers publish HIGHLIGHTS only. Hover and key/pad focus call into the sidebar; a click in a
  viewer is that viewer's own action (take, close) and never locks -- the lock is a board
  transition (L11, B5).
- S12: closing a viewer announces the lost highlight through the same channel the board uses --
  `DeckViewer.highlight_cleared` / `ChoiceViewer.highlight_cleared` -> `HudContainer.return_to_lock()`,
  so a description locked before the viewer opened comes back (B7) and an unlocked container keeps
  the last card read inside it (B4).
- P3 review: `DeckViewer.show_deck(parent, deck, opener)` takes the opening Control instead of
  reading `parent.get_viewport().gui_get_focus_owner()`: the pile buttons live in the wall overlay
  while the viewer lives inside a picture's SubViewport, and Godot clears focus across every
  viewport of one window, so the read always found nothing to restore. Every caller passes the
  button it was pressed from; `BoosterTemplate.view_choices()` had no caller at all and is deleted.
- P3 review: OPENING a deck/discard/rules viewer PUBLISHES its first card, because that opening
  focus is a highlight (B1) -- `DeckViewer.update_viewer()` defers the grab so it lands after the
  opener has connected the relay and fitted the viewer. `ChoiceViewer` opens on its Confirm button
  instead, so it publishes nothing until the player moves onto a card.
- S12 new names NAMES.md does not list: `InfoEntry.relay_to(out)` (the "emit it, or free the live
  preview nothing will take delivery of" shape `GameView._relay_info_requested` spelled out, now
  shared with `Map._relay_info_hovered` and both viewers); `HudContainer.rect_beside(picture)` and
  `HudContainer.window_scale(picture)`; `WallPicture.window_scale(window)`;
  `CardsViewer.picture_to_window_scale` / `card_window_px()`; `DeckViewer.info_requested` /
  `highlight_cleared` / `fit_beside()` and the same three on `ChoiceViewer`;
  `GameView.wall_picture` (set by `Main.enter_game()` beside `hud_container`) and
  `GameView._open_deck_viewer()`.
- S12: `HudContainer.rect_beside()` REPLACES the "convert the container's window px into this
  picture's space, or fall back to the plain window rect" expression `Menu._apply_container_inset()`
  and `Map._publish_map_inset()` each carried; the viewers are its third and fourth callers.
- S12: `Q141`=b's "inside" is a left (or top) inset, per PLAN 1.9. `DeckViewer.fit_beside()` insets
  its `MarginContainer`'s own authored margins, so the full-screen click-to-close catcher still
  spans the picture while the cards and their tint start beside the container;
  `ChoiceViewer.fit_beside()` offsets its `FlexContainer` the same way. Measured at 1280x720: the
  grid starts at 494 picture px against the container's inner edge at 394.
- P3 review: `fit_beside()` sets ALL FOUR edges from the remaining rect, on BOTH viewers, not only
  the near ones -- the far offsets otherwise stay at the picture's own edge, which is outside what a
  cropped window SHOWS. Measured at 600x1000: 3 of 5 pack cards and 22 of 47 listed cards were drawn
  past the visible right edge at 1054 picture px. `DeckViewer` needed it too, though the finding
  scoped the defect to `ChoiceViewer`.
- P3 review: `DeckViewer._inset_margin()` + `_authored_margins` -- the scene's own margins are read
  once and every fit SETS from them, since a fit now runs again on each window change and adding
  would double the inset (measured: 47 of 47 listed cards outside the space beside the container
  after one re-fit).
- P3 review: A VIEWER IS A SCREEN OCCUPANT LIKE THE BOARD. `GameView._fit_open_viewer()` and
  `Map._fit_open_viewers()` re-fit whatever viewer is open on `container_rect_changed`, the signal
  the board re-fits on, connected AFTER `_publish_board_inset` / `_publish_map_inset` so the
  viewer's own re-publish is what the description ends on. Each screen holds the viewer it opened
  (`_deck_viewer`, plus `_choice_viewer` on the map, which can have both up at once).
- P3 review: `CardsViewer.republish_highlight()` -- a re-fit publishes the list's current highlight
  again, so the description's preview is re-drawn at the size THAT viewer now draws its cards at
  rather than at the board's, which `GameView._publish_board_inset()` has just applied to the
  mounted entry. Measured at 1920x1080: preview 86.4 px (the board's) against the viewer's 99.4.
- P3 review: the highlight is REMEMBERED as it is published (`CardsViewer._publish_highlight()`,
  `_highlighted`) rather than re-derived on demand: `Control.is_hovered()` does not exist in Godot
  4.7 (`BaseButton` only). `CardsViewer.inspect_on_highlight(control, data)` is the one place a
  listed control's hover and focus are wired, so `ChoiceViewer._swap_card_control()`'s rerolled slot
  is remembered too.
- P3 review: THE SAME CLASS FOLLOWS THE SAME RULE. The deck picker's own Inspect viewer
  (`UI/deck_picker.gd`, inside the start menu) is inset and relayed exactly as the game screen's is:
  `Q22`=b keeps the container on the menu, so it is visible (empty) there and would otherwise cover
  the viewer's first columns -- measured at 1280x720, 3 of 8 listed cards were drawn at picture
  x 104 against the container's inner edge at 288. New names: `DeckPicker.viewer_opened(viewer)`
  (the picker announces what an Inspect opened; the screen hosting it owns the wiring),
  `Menu.info_requested` (the relay `Main` connects, the same one `GameView` exposes),
  `Menu._on_viewer_opened()` / `Menu._fit_open_viewer()` (re-fitted on `container_rect_changed`
  like the others). The viewer stays parented to the PICKER, so picking a deck frees it with the
  picker.
- P3 review: `ChoiceViewer`'s pack, confirm button and reroll counter share one `Layout` Control
  (`mouse_filter` IGNORE, the dimmed backdrop stays outside it) and `fit_beside()` insets THAT, so
  the chrome anchors to the space beside the container rather than to the picture: the confirm
  button centres under the pack (measured 576 vs the pack's 720 at 1280x720) and the counter keeps
  to the visible right edge (measured outside it at 600x1000). `Q141`=b's "the viewer owns its own
  layout" is about the whole layout, not only the cards.
- S12: `UI/deck_builder.tscn` lost its broken `Cards/card.tscn` `ext_resource`, the `Card` node it
  instanced and the dead "Skill Text" `Label` beside it. The tool's preview is now a real
  `ControlCard` built in `_ready()` over a `preview_data : CardData` the option buttons mutate --
  `CardVisual` redraws itself off `CardData.data_changed`, so nothing rebuilds it (Q166=c, L13).
- P3 review: `CardsViewer.rehighlight(replaced, data)` -- a slot swapped out UNDER the highlight (a
  pack Reroll) publishes the card that took the slot. The pointer never moved, so `B1`'s "a
  highlight is what the sidebar reads" would otherwise leave it reading a card that is gone
  (measured: the title still read the rerolled-away card until the pointer moved).
- P3 review: the Deck Maker's `TypeOption` node and its skill "Random" item are DELETED, not wired:
  nothing ever read `TypeOption`, and the skill randomiser was already commented out in the
  pre-repair script, so there is no behaviour to restore -- only dead code `Q166`=c asks to remove.
  `skills` is now index-aligned with the option's own items (item 0 is the scene's "None" -> null).
- P3 review: three methods with no caller anywhere are deleted -- `HudContainer._key_scroll_pages()`
  (its body was inlined into `_input()`), `PlayArea._grid_panel_height()` and
  `PlayArea.get_data_from_control()` (with the commented-out siblings around it).
- P3 review: `CardEnvironment.get_current_game()`'s `is_instance_valid(CURRENT)` guard KEEPS its
  place, now with the caller named: `FxAttachment.transition_secs()` reaches it from a card visual
  still finishing a transition after its game was freed. Replacing the guard with an assert proved
  it: the assert never fired (a freed instance compares EQUAL to null in Godot 4.7) while
  `CURRENT is Game` errored 6 times in one suite run.
- S13: `PlayArea.board_card_picture_px()` -- the board's card at the live zoom in the PICTURE's own
  pixels, which is the space a swipe's `travel` is measured in. `board_card_window_px()` now
  derives from it, and it is what the bare-board swipe passes to `GestureMetrics` (M5, `Q296`=a).
- P3 re-review: `HudContainer.connect_for_screen(screen, sig, callable)` /
  `disconnect_for_screen(screen)` key their remembered pairs by the SCREEN that made them
  (`Dictionary[Node, Array]`). One flat list made a finished show's `GameView._exit_tree()` drop the
  map's Deck button and the map's and menu's insets as well (measured: the map's camera offset stayed
  (-144, 0) where a live inset reads (0, -81), and the Deck button opened nothing).
- P3 re-review: `DeckViewer.republish_highlight()` / `ChoiceViewer.republish_highlight()` are public,
  and the RE-FIT no longer republishes on its own: each opener (`GameView._fit_open_viewer`,
  `Map._fit_open_viewers`, `Menu._fit_open_viewer`) asks for it only while
  `hud_container.showing_description()`. A dismissal is the player's act, so a window change must not
  undo one.
- P3 re-review (overseer, reversible): the exit X is focusable WHENEVER a description shows, not only
  while locked -- `HudContainer._refresh_exit_focus()` reads the X's own visibility, and the new
  `focus_exit()` is what `DeckViewer._hand_the_focus_back()` uses when the opener it would return the
  focus to is not `is_visible_in_tree()` (a viewer's opening highlight hides the pile buttons that
  opened it, stranding a pad player). The opener's own `owner` IS its `HudContainer`, since the pile
  buttons and the map's Deck button live in `hud_container.tscn`. `Q68`=b's `ui_up`-off-the-top rule
  is unchanged.
- P3 re-review: `DeckPicker._inspect()` opens its viewer at `layer + 1`, above the picker's own Dim.
  The Dim is `MOUSE_FILTER_STOP` and covers the screen, so a viewer left at the default layer got no
  hover and no click at all on the menu -- only the keyboard reached it. Raising the viewer (rather
  than making the Dim ignore the mouse) keeps the picker's modal guard over the menu behind it and
  makes the viewer's own click-to-close work everywhere; the picker's buttons are behind the open
  viewer until it is closed, which is how the same viewer behaves on every other screen.
- S14: new names `CardVisual.held_lift_px()` and `CardVisual.cursor_ride_offset()`,
  `PlayArea.follow_cards()`, `PlayArea._on_pointer_moved()` / `_origin_cell_rect()` and
  `PlayArea._next_grab_follows`.
- S14: no lift quantity existed for a held card -- a grab never called `anim_jump`, so a following
  card rode the cursor with no raise at all. `Q265`=a wants the two states at the SAME lift, so the
  lift is applied in BOTH: `CARD_JUMP_RISE` (through `card_jump_rise_play`, scaled by the anchor's
  own global scale, which is what `get_card_control_center` already does) above whatever the card
  aims at -- its slot centre until it follows, the cursor once it does. Measured 18.8 px at
  1280x720. No new knob and no literal.
- S14: `Q267`=a's "a clicked card follows immediately" cannot be written at the click, because the
  pickup lands behind `Game.try_grab`'s own await, after the click handler has returned. The click
  sets `_next_grab_follows` and `grab_cards` consumes it; `ungrab_cards` drops it, so a click that
  placed instead of grabbing cannot make a later arm follow.
- S14: `Q268`=a's cell-leave dismissal is read BEFORE the same motion latches `following`, so the
  very motion that arms an untouched card never also closes a description (`1.8`). The cell is the
  card control's PARENT (`_fit_children(slot, ...)` makes every card control a child of its cell
  slot), so no new geometry is published.
- S14: three landed S6 tests (1.4, 1.5, 1.6's second lock, and the `Q58`=c marking test) locked
  with `_click_card`, which also GRABS. With `Q62`=b/B11 landing, the pointer then carries the held
  card out of its cell and dismisses what was locked. Those fixtures now lock through the suite's
  existing `_lock_without_holding()`; the rows they implement (1.4/1.5/1.6) never asked for a held
  card.
- S15: new names `PlayArea.rest_focus_on_armed()`, `PlayArea._focus_is_resting`,
  `PlayArea._pointer_was_in_the_origin_cell`, `GameView._arm_the_entrance()` and
  `GameView._rested_the_focus`. `armed_slot()` / `arm_leftmost()` are NAMES.md's.
- S15: the show-start rest focus (`Q251`=b, G10) is placed by the VIEW after the first arm and is
  SILENT -- `PlayArea._focus_is_resting` brackets that one `grab_focus`, and
  `on_control_focus_entered` skips both `_publish_info` and `follow_cards` while it is set. Without
  it the very first focus would open a description (`Q240`=a says a fresh show is the HUD) and start
  the card following (`Q254`=d says it must not). The latch is on the REST FOCUS, never on the grab
  path, which is what `Q252`=b forbids.
- S15: `arm_leftmost()` leaves the board alone while `Game.processing` is true or something is
  already held. Both callers are real: `Game._restore_pre_act_board()` rebuilds the view with
  `processing` still true, and a second arm must not re-grab a card the player has already started
  moving (it would reset `following`).
- S15: `Q62`=b's cell-leave dismissal is now a CROSSING, not a position test. With a card armed at
  all times, "the pointer is outside the held card's cell" is true on every motion, so a hover
  opened a description and the next motion closed it -- B1/B4 were unreachable on the game screen.
  The answer's own words are "the cursor LEAVING the bounds of the cell", and a card armed with the
  cursor elsewhere was never inside it to leave. `grab_cards` seeds the flag from the live cursor,
  so a CLICKED card (cursor on it) still dismisses when the pointer carries it out (1.7's fourth).
- S15: `GameView._on_undo_pressed`'s held-cards guard is deleted. With the Entrance always armed it
  was always true, so Undo could never fire; what is held is the arm, and the arm is view-only, so
  undo drops it and re-derives it from the restored board (`Q117`=a).
- S15: a REFUSED placement falls through to picking the clicked card up, which is how `Q114`=a's
  "clicking a different Entrance card re-arms and locks that card's description -- one click, both"
  happens: the Entrance header refuses a card as a drop target, so the click's remaining action is
  the pickup. A card nothing can grab leaves the arm alone rather than emptying the hand.
  `Q122`=a's board-card half belongs to S16 (PLAN lists Q122/Q123 there) and is unreachable today:
  the only `on_can_grab_stack` implementations are `TypeInput` (the Entrance) and
  `SkillGrabberOgLower` (the retired LOWER zone), so no board card can be picked up at all.
- S15: `PlayArea._publish_focus_left_cards`'s `assert(is_inside_tree())` became an early return.
  Its premise ("every teardown frees the screen root, so a deferred call never reaches a live
  board") stopped holding the moment a show ALWAYS leaves a card focused: tearing a view down while
  a card holds the focus queues that deferred call against a node already out of the tree.
- S15: `TestSidebar._hoverable_card_controls()` now also drops a HELD card's control and a buried
  FOCUS_NONE zone control. Both are the product's own answer to "can the pointer land here and
  publish": `grab_cards` makes a held control `MOUSE_FILTER_IGNORE`, and a covered zone control
  cannot take the focus a publish rides on. Three landed assertions moved with the feature: the
  placement test now asserts the PLACED card is no longer held (something always is), and 6.10
  compares the restored card by NAME, since `Game.undo()` rebuilds `GameData` and hands back new
  `CardData` objects.
- S15: `rest_focus_on_armed()` returns whether the focus actually landed, and the view only spends
  its one-shot flag when it did. `Game.try_grab` is awaited inside `arm_leftmost`, so a board that
  rebuilt across that await can hand back an armed card the control map no longer has; the show
  then rests on the next arm instead of crashing on a missing key.
- S15: G12 / `Q24`=a / `Q124`=a's legal-cell highlight does not exist in the code at all and was
  never built -- a CLICK pickup shows none either -- so nothing in S15 could preserve it. Filed as
  GAP-005 (owner call: what the mark IS), with `TEST_PLAN.md` §11's claim that every chart node is
  covered noted as wrong for G12.
- S16: new names `PlayArea.card_dragged` / `card_dropped` (signals), `PlayArea.stop_following()`,
  and the private `_arm_card_gesture()`, `_gesture_threshold_px()`, `_take_up_the_dragged_card()`,
  `_consume_as_card_release()`, `_release_places()`, `_press_origin` / `_press_data` /
  `_press_card_px` / `_drag_began`; `GameView._on_card_dropped()`, `_place_held_onto()`,
  `_pick_up()`; and `Tests/Support/test_main_host.gd` (`TestMainHost`).
- S16: THE CLICK IS DECIDED AT THE RELEASE, not the press. `_on_gui_input`'s left-button branch
  now fires on the release, and `_input` consumes any release that travelled past the threshold
  before the GUI pass sees it -- so one gesture is either a click or a placement, never both.
  `Tests/UI/test_grid_view.gd`'s `_click()` helper moved with it (it drove a press).
- S16: the press/release reader lives in `_input`, beside the swipe, NOT in `_on_gui_input`: the
  swipe reader's own note applies (only `_input` runs before the viewport's GUI pass), and event
  positions there are the picture's own pixels, the space every control rect is measured in.
- S16: a finger is read through the mouse form `emulate_mouse_from_touch` synthesises (device -1)
  and the raw `InputEventScreenTouch` forms are left to the swipe reader, which is why that one
  filters device -1 OUT. One gesture model, one reader.
- S16: `Q288`=a needed NO new forwarding. A press on the board sets no `gui.mouse_focus` in the
  ROOT viewport (the board lives in a picture's SubViewport, not a root Control), so the root GUI
  pass does not consume the later release even over the container, and `Wall._unhandled_input` ->
  `WallInput.route` carries it into the picture like every other board event. Measured: 5.4 goes
  red the moment that routing stops forwarding mouse buttons, and nothing else in the suite does.
- S16: the release forgets its press (`_press_data = null`) whichever branch it takes. Without
  that, pointer motion long after the button came up counted as a drag and re-grabbed a card
  (it failed `TestSidebar`'s 1.8 check, where a hover re-armed onto a different card).
- S16: `GameView._on_data_selected`'s toggle -- a click on the held card, or on the card directly
  beneath it, UNGRABBED -- is deleted. `Q114`=a makes a click on the held card a click like any
  other (it locks and stays held) and putting a card back is Cancel's job, S18.
- S16: a HELD card's own control is `MOUSE_FILTER_IGNORE`, so no tap can reach the card in hand at
  all. The check that the toggle is gone drives the KEY accept on the focused card control, which
  is the path a player actually has to it; a tap-based version of that check was vacuous.
- S16: 5.1's discriminator is the LOCK, not the grab. With the threshold removed a short drag
  still ends with the card held (the drag takes up the card it started on), so what separates a
  click from a drag is that only the click route locks the card's description.
- S16: the gesture's threshold reference is the PRESSED card's own drawn size, falling back to
  `board_card_picture_px()` when the press found no card (`Q296`=a). The swipe keeps its own
  `_swipe_threshold_px()`, which is that same fallback by definition -- two readers, one model.
- S16: `Tests/Support/test_main_host.gd` is a NEW support file rather than a reuse, because no
  shared fixture hosted a real `Main`: `TestGameViewHost` hosts a bare `GameView` in a SubViewport
  with no wall and no root-level container, which cannot answer 5.4 at all. The boot itself was
  already written inside `TestSidebar` (`_boot_main_at`), so it moved there and `TestSidebar`'s two
  helpers now delegate -- one boot, two suites, rather than a second copy.
- S16: the board card 5.6/5.7 need rides as a STAMP. `return_first_data_array_result` dispatches
  `type`, `stamp` and `statuses` always but a `skill` only while `spotlit`, and a stamp leaves the
  card's own type -- what it is drawn from -- alone. No shipped rule grabs a board card.
- S16: `TestDragPlace` sits directly after `SIDEBAR` in `TestSuite`'s ordering chain (it hosts a
  real `Main` and writes `CardEnvironment.CURRENT` / `Main.save_info` / the real save); the six
  suites before it name "DRAG PLACE" in their excludes.
- S17: the tap's refusal reads the BOARD's own committed depth (`save_history.size()`) at the
  press that opened the pair against the depth at the tap. `Q93a`=a asks "did the first press
  place?" and that is the board's own answer, so no new call from the view into the board and one
  rule for every input. The bound `card_tap` action is exempt: it has no first press to undo, so
  there is nothing a placement could make it rewind.
- S17: A TAP EATS THE RELEASE THAT CLOSES ITS GESTURE (`_tapped_this_gesture`, consumed in
  `_consume_as_card_release` beside the travelled release). Measured: without it the pair's second
  release falls through to the GUI pass as an ordinary click and re-grabs the card the tap just
  let go.
- S17: the finger's pair is SELF-DETECTED and the engine's own synthesis never taps -- the mouse
  reader ignores `double_click` on device -1. Godot copies a touch's `double_tap` onto the mouse
  form it emulates, so on a platform that sets it both readers would otherwise fire for one pair.
- S17: the tap pair's distance window is `_gesture_threshold_px()`, i.e. the drag threshold the
  pair's FIRST press armed from the card it landed on. One distance model for the drag and the
  tap, no second knob and no millimetres (`Q291`=a).
- S17: undoing the grab and re-deriving the arm live in `GameView._on_card_tapped` --
  `ungrab_cards()` + `_arm_the_entrance()`, the same two calls `_on_undo_pressed` makes, which is
  what makes the arm STAND on a tap of the armed card (`Q94`=a). `PlayArea` only detects and emits.
  With nothing held there is no grab to undo, so a tap on a bare card re-arms nothing.
- S17: the hook reaches cards as `game.run_all_mods(&"on_card_tapped", data)` from that same
  handler. `Scripts/card_effect_api.gd` is UNCHANGED: it has no subscription surface, and
  `run_all_mods` already forwards any hook name.
- S17: `card_tap` binds key T and joypad button 2 (X) -- the first pad face button neither accept
  (button 0) nor cancel (button 1) uses, and clear of the wall's Back and shoulder bindings.
- S17: the dummy tap effect is a `CardModifierStamp`, not a `CardModifierType`: `run_all_mods`
  dispatches `type`, `stamp` and `statuses`, and a stamp leaves the Entrance card it rides the type
  it was drawn from (S16's finding). It is test-local; nothing under `Cards/` listens.
- S18: new names `PlayArea._cancel_one_step()` (the second mouse button: one thing per press) and
  `PlayArea._cancel_everything()` (`ui_cancel`: both at once), plus the test names
  `TestSidebar._second_button_press()` and `sidebar_snapshot._cancel_the_held_card_once()` with its
  `CANCEL_FIRST_PRESS_OUT_PATH`.
- S18: `ungrab_cards()` never hid the description -- the collapse the audit warned about is in
  `GameView._place_held_onto`, which belongs to a landed PLACEMENT, not to a cancel. Only the
  ordering and the consumption changed.
- S18: `Q100`=c is implemented by NOT consuming: `GameView._on_description_dismiss_requested` no
  longer marks the event handled, so the wall's own Back hears the same Escape. The second mouse
  button is consumed by the board instead, which is what keeps it cancel-only.
- S18: the 1.7 cancel test lost its second-press half. Once the first Escape both dismisses and
  goes back, the wall sets `input_locked` for the transition it started, so a second press in the
  same test window is inert by design -- the case it asserted is now the first press's own.
- Phase 5 fix 1: the touch reader owns its own opening-press depth, `PlayArea._touch_press_depth`,
  and `_pair_taps` takes that depth as a parameter. Godot dispatches the mouse form it emulates
  from a touch BEFORE the touch itself (source: `Input::_parse_input_event_impl` nests the
  emulated dispatch; measured the same order here), so the closing press re-armed the gesture and
  reset `_depth_when_pressed` before the touch could compare it -- the refusal after a placement
  could never fire on a real touchscreen. New test row
  `TestDragPlace.test_a_touch_tap_after_a_placement_is_refused`, sharing
  `_cell_the_arm_can_be_placed_on()` and `_check_the_placement_stands_untapped()` with the mouse
  row; `_touch_tap` now pushes the two forms in the engine's order.
- Phase 5 fix 2: a cancel ends the PRESS as well as the hold. `PlayArea._end_the_gesture()` is
  now the one place `_press_data` is cleared -- the release calls it, and so do `_cancel_one_step`
  and `_cancel_everything`; without it the release closing a cancelled drag ran `_release_places`
  and emitted `card_dropped` for a hand nobody was holding. New test rows
  `TestDragPlace.test_a_cancel_mid_drag_leaves_nothing_for_the_release` and its
  `..._an_escape_mid_drag_...` twin, sharing `_check_a_cancelled_drag_places_nothing()` with the
  new `_escape_press()` (root-viewport `ui_cancel`). Only the second-button row reproduced: the
  wall's transition lock already swallowed the release after an Escape, so the twin is a guard.
- Phase 5 fix 3: no new name. `PlayArea.stop_following()` now also clears `_next_grab_follows`, so
  it means "nothing tracks the cursor, including a click still waiting on its grab", and
  `GameView._on_data_selected`'s `processing` early return -- the path that DROPS the selection --
  calls it. Without that the flag survived the dropped click and the next `arm_leftmost()` armed a
  card that was `following` from birth, which `Q267`=a/`Q262`=a reserve for a card the player
  touched. The drag refusal already called `stop_following`, so it gets the same clear.
- Phase 5 fix 6: no new name. `GameView._pick_up` calls `play_area.stop_following()` when
  `try_grab` REFUSES, so a refused pickup drops the click's promise of following exactly as the
  refused drop does. Without it the flag survived (nothing on the board is grabbable today) and the
  next auto-arm reached through the processing edge -- `_on_processing_changed(false)` ->
  `_arm_the_entrance` -> `arm_leftmost`, which never ungrabs first -- was born `following`,
  measured 550.4 px off its slot centre against an 18.8 px lift. New test row
  `TestSidebar.test_a_refused_pickup_does_not_make_the_next_arm_follow`.
- Phase 5 fix 4: no new name. `PlayArea._tapped_this_gesture` now means "this gesture's release
  closes a PAIR", tapped or refused, and `_press_closes_a_pair()` sets it either way -- so
  `_consume_as_card_release` eats the closing release of a REFUSED pair as it already ate a tap's.
  Without it that release fell through the GUI pass as an ordinary click (measured: one
  `data_selected` emission), which places again whenever the cell under it accepts the card the
  first click's placement armed. New test row
  `TestDragPlace.test_a_refused_pairs_release_places_nothing`, which pushes the one mouse motion a
  real mouse makes between two clicks -- the hover refresh `_on_gui_input` reads.
- Phase 5 fix 5: `PlayArea._close_a_pair()` is the one place a pair closes for either input -- it
  taps if the pair may tap and marks the gesture's release as a pair's either way, so the MOUSE
  reader and the TOUCH reader share one rule. Without it a refused FINGER pair's emulated release
  (device -1, dispatched after the touch) fell through to `_on_gui_input` and placed again
  (measured: one `data_selected`). The touch refusal row now spies selections through the new
  `TestDragPlace._spy_on_selections()`, and `_check_the_placement_stands_untapped()` takes them, so
  both refusal rows assert it at one site. `TestSidebar`'s arrow-focus row now asserts the focus
  owner is a board card (`ui_data.has(owner)`), which a null owner no longer satisfies.
- S19: the stock rides the Entrance zone's own per-cell data: `GridData.stocks`, one
  `ArrayCardData` per cell, reached through `GameData.entrance_stocks()` (grows to match
  `cells`), `GameData.all_stock_cards()` (the flat union every walker and the deck viewer read)
  and `GameData.stocks_are_empty()` (the "deck is empty" predicate S22 reads). So the set of
  slots and the set of stocks cannot disagree.
- S19: `Board.remove_column` carries the removed Entrance slot's stock out with it, returning
  those cards among the orphans the ZoneAdder already discards (`Board._stock_orphans`).
  `add_column` needs no counterpart -- `entrance_stocks()` grows.
- S19: a board with NO Entrance slots still holds one stock. `add_deck` runs before the zone
  adders build the row, so the shuffled deck lands in stock 0 and `Game.deal_stocks()` -- called
  again by the bootstrap once the slots exist -- spreads it. `deal_stocks()` is also the seam
  S20's `rebalance_stocks()` calls.
- S19: `Game.draw_card(slot)` and `CardEffectApi.draw_card(slot)` take the slot whose stock they
  pop; `TypeInput.on_refill` passes its own column. `CardEffectApi.draw_deck()` KEEPS its name as
  the flat read-only view of the union (its one caller counts cards), and
  `return_to_draw_deck(card)` puts the card on the shortest stock, earliest slot winning ties.
- S19: old in-flight saves are discarded, not migrated, through a save version:
  `RunState.stock_format` (`STOCK_FORMAT` = 1, written by `RunManager._build_payload`). A run
  written before stocks loads as 0, and `RunManager._drop_unrebuildable_show()` clears its
  `game_history` and pending markers on load -- the run survives, the show does not.
- S19: `TestGridFixtures.draw_any(game)` draws the top of the first slot that still has one, for
  the fixtures that want a card from what is left of the deck and do not care which slot owns it.
- S19: `TestUIProps`' frozen-deck seed moved 424242 -> 424243. The per-slot deal changes which
  cards reach the scored row, and the fixture's whole point is a seeded deal whose line spawns
  props; the new seed restores that, the deck composition is unchanged.
- S20: the rebalance is ONE parameterless state-derived rule, `Game.rebalance_stocks()`, in two
  named halves: `_pour_out_slotless_stocks()` empties any stock beyond the slot count from ITS
  bottom, round-robin into the survivors' bottoms left to right; `_pull_bottoms_to_even_shares()`
  then moves bottoms from slots above their even share (`_first_stock_below_target()` picks the
  taker) until every slot holds what `deal_stocks()` would give it. Tops never move.
- S20: `Board.remove_column` no longer orphans the removed Entrance slot's stock (S19's contract):
  `Board._park_removed_stock()` moves that stock to the END of `GridData.stocks`, where it has no
  slot, and the rebalance pours it back. A caller that removes a column without the rebalance
  leaves the cards parked, not lost.
- S20: the production seam is `CardEffectApi.add_column`/`remove_column` (the only path
  `ZoneAdder` has), guarded by `_rebalance_if_entrance()` because only the Entrance owns stocks.
  `Board` is static and holds no `Game`, so the call cannot sit inside it.
- S20: `TestUIProps`' frozen-deck seed moved 424243 -> 424245. The bootstrap's zone adders now
  rebalance as each slot appears, so the final `deal_stocks()` deals a different permutation and
  the fixture's scored line stopped spawning props; the new seed restores that (424244 and 424246
  also fail, 424247 also passes). The deck composition is unchanged.
- S20: `TestEntranceStocks` drives the real seam through the adders themselves --
  `_add_slot(g)` spotlights one more `SkillAdderInputUpper`, `_remove_slot(g, slot)` unspotlights
  the adder that owns that slot -- so no test calls `rebalance_stocks()` directly.
- S21: face-down-ness is a BOARD fact, not the card's: `CardVisual.face_down` (with
  `showing_back()`, which ORs it with the data's own `flipped`, and `resting_basis()`, the face a
  card arrives on) is what the Entrance sets, so the deck viewer and every save are untouched.
  `CardVisual.flip_up_after(delay)` owns the wait through one engine tween (`flip_tween`) and is
  idempotent, so a rebuild mid-flip cannot restart it; the flip ITSELF is the floating slerp that
  was already there.
- S21: `entrance_stock_face_down_cap` is DELETED per the owner's mid-step ruling. A slot draws
  exactly ONE face-down card while its stock is non-empty (`PlayArea._face_down_depth()`), and no
  other stock card is an entity at all. `_entrance_drawn_columns()` is what each slot draws
  (that face-down card, then the cards it holds), and it is the array `set_card_zone`,
  `update_card_zone_visuals` and the Entrance's draw order all run on -- so the face-down card is
  bound, sized, ordered and positioned by the SAME code as every other board card.
- S21: a slot's height 0 is one control up from the bottom while it has a face-down card, so
  `PlayArea._control_height()` (the reveal's control pass) and `control_for_coord()` both subtract
  it, and `_entrance_slot_center_global` adds it to `coord.h`. The revealed card therefore does not
  move when the face-down card appears: measured card0_y 699.16 and grid cell0_y 147.83, identical
  with the face-down card and with the stocks emptied -- the strip's own fixed reservation
  (140.88 px) already covers the deeper row (100.87 px), so the board is not pushed up at all.
- S21: `PlayArea.entrance_flip_delay(slot)` is the stagger, `slot * entrance_flip_stagger *
  get_delay()`; `_turn_the_entrance_over()` is the per-rebuild pass that puts every DRAW-stage
  card's visual face down and asks every revealed one to flip up. It reads STAGES, not the control
  map, because a rebuild's dictionaries and the state can disagree mid-grab (measured: a missing
  `data_card` key through `arm_leftmost` -> `grab_cards`).
- S21: the face-down card's control is `FOCUS_CLICK`, not `FOCUS_ALL` -- reachable by pointer and
  click, which is what publishes the slot's description. ⚠ The focus mode alone does NOT keep the
  arrows off it: Godot honours an explicit `focus_neighbor` at every mode but `FOCUS_NONE`, so what
  makes it never an arrow stop is `_link_arrow_stops()` leaving it out of the chain, tested by
  S21.7. `PlayArea.is_stock_control()` is the public predicate, used by the publish path, by the
  link builder and by the fixtures that mean "a card a player can grab".
- S21: `PlayArea._publish_stock_info()` sends the SLOT's own entry -- title the zone card's name,
  body `SIDEBAR_STOCK_REMAINING` with the count, no preview visual -- through the same
  `info_requested` route a card uses. ⚠ The localisation CSV's third column is a CONTEXT, not a
  comment (see the two `INPUT_ZONE_CARD_DESCRIPTION` rows): text put there files the message under
  that context and `TranslationServer` hands back the raw key.
- S21: `GameView.sorted_stock_union(state)` is the Deck button's content -- one flat union sorted
  by `suit.get_suit_index()` then `rank.value`. `DeckViewer`'s dead `SORTING_TYPE`/`SORTING_ORDER`
  enums and `randomized`/`sorting_*` vars are deleted with it; the sort lives at the caller.
- S21: `CardVisual.on_stage_changed`'s DRAW branch (fly to the Deck control and free) is deleted
  with the fly-in. A card newly dealt into a stock hit it on its first stage change and deleted its
  own visual; the Deck control is not a place on the board, and `GameView.deck_ui` is not even
  assigned until after the deal.
- S22: the goal check sits in `Game.place_card_in_grid` between `run_all_mods(&"on_card_placed")`
  and `refill_entrance_if_due()`, guarded on `not processing`, and RETURNS -- so an ended show runs
  the placement's own commit (Phase 7 fix 9) but never the Entrance refill. This is the reading of
  "after the WHOLE placement resolves" that excludes the refill.
- S22: `Game._end_show_on_goal()` is the pause plus the existing `end_show()`. The pause is
  `get_delay() * SettingsManager.settings.spotlight_hold_fraction` through `Pacing.wait`, guarded
  `if view:` so headless stays byte-identical. No new knob: the design named none, and the hold
  fraction IS the project's "let it read" beat.
- S22: `GameData.grids_are_full()` is the second half of the End reveal -- "no more possible action
  on board (no empty tiles)". The first half is S19's `stocks_are_empty()`. The OR is taken in the
  view, so no third predicate exists.
- S22: `GameView._refresh_end_reveal()` is the ONLY writer of `submit_button.visible`, called from
  `_refresh_hud()` (score-driven) and `_on_board_changed()` (board-driven). `GameView._mark_goal_met()`
  is the Goal label's met state.
- S22: `PaletteRoles.goal_met = 9` (the palette's bright green) is the Goal label's met colour --
  a role like `hud_background`, never a literal.
- S22: 7.1-7.4 live in `TestGameHeadless`, 7.5 in `TestSidebar` (it needs a real `GameView` and
  `HudContainer`). No suite was added; the count stays 48.
- S22: four existing tests now pin their goal out of reach because reaching it ends a show by
  itself (`TestGameHeadless.GOAL_OUT_OF_REACH`, `TestSidebar.GOAL_OUT_OF_REACH`,
  `TestE2E.GOAL_OUT_OF_REACH`); E2E scenario 1 lowers its goal to 1 immediately before its explicit
  `end_show()` so the win still banks. `TestInteraction`'s game-over test empties every stock first,
  because a hidden End cannot be clicked.
- S22: `sidebar_snapshot.gd` gains `goal_met.png` via `_show_the_goal_met()`, which drops the goal
  TO the settled board's total -- the real transition lasts one hold beat and cannot be photographed.
- Phase 6 fix 7: `PlayArea._consume_as_stock_press()` is the click/accept half of the face-down
  rule, in the same `_consume_as_*` shape as `_consume_as_focus_click` -- a press on a stock
  control publishes the slot's own entry and is consumed, so `data_selected` never carries a
  hidden card and the sidebar cannot lock to one.
- Phase 6 fix 8: `PlayArea._link_arrow_stops()` is the Entrance's neighbour chain -- each slot's
  topmost control, minus the slots showing only a face-down card, so the arrows walk from one
  revealed card to the next. Clearing both links every rebuild is part of it: the controls are
  pooled, so a stale path would outlive the slot that earned it.
- Phase 7 fix 9: `Game._commit_placement()` is a placement's commit -- the grid commitment lift plus
  the `save_state()` a PLAYER's placement owes. The winning placement runs it BEFORE the hold, so
  undo after an automatic end rewinds only the end and the winning row survives.
- Phase 7 fix 9: `Game._end_show_on_goal()` takes the board lock (`processing = true`) before the
  hold, so no undo, re-arm or second placement fits inside it. The hold length is read from
  `get_delay()` FIRST, because the lock is what compresses it.
- Phase 7 fix 9: `Game._end_show_if_goal_met()` re-fires the goal check on resume (after a replay,
  and on the no-marker branch). A board loaded with the goal met and no outcome saved therefore
  ends the show -- including a board saved after an undo of an automatic end, which is
  indistinguishable on disk and which the goal-ends-a-show rule wins.
- Phase 7 fix 9: `TestGameHeadless.RefillSpy` is a test-only skill whose `on_refill` records the
  hook; it is how 7.2 proves the end fired BEFORE the refill (`committed_grid` no longer says so,
  because the commitment lift now runs with the placement's commit).
- Phase 7 fix 9: `TestGridCards.GOAL_OUT_OF_REACH` and `TestLeakCanary.GOAL_OUT_OF_REACH` join the
  three S22 ones: TP-122's placement scores thousands, and the leak canary's phase 4 quits
  mid-show, so neither may reach the goal. The canary drops its goal to 1 on the RESUMED board and
  lets the automatic end resolve the win (its `end_show()` call was a no-op after it).
- Card back: the owner's ruling *"cardback should be frame 3"* is `CardVisual.CARD_BACK_FRAME`
  = 3 of `card_types.png`, drawn by `update_visual()`'s non-front branch whenever
  `showing_back()`; the branch's old bare literal 1, which a face-down card used to draw, is
  named `BLANK_CARD_FRAME` and still serves a card with no type. A card's frame is a UV window
  (`CardOutline.frame_polygon`), not a Sprite2D `frame`, so S21.4 asserts it through the
  `u_frame_uv` clamp the card pushes to its own shader.
- Phase 7 fix 10: `%Submit` is authored HIDDEN in `UI/hud_container.tscn`. The container lives on
  the wall from boot, so Button's default true left End flagged visible for every frame before a
  GameView existed to write it; `GameView._refresh_end_reveal()` is still the only writer.
  `TestSidebar.test_every_hud_member_is_visible_and_reachable` forces it visible to measure
  geometry, the way that test already forces the Combo label.
- Phase 7 fix 11: the resolved show leaves nothing armed. `GameView._on_show_resolved` calls the
  existing `PlayArea.ungrab_cards()` BEFORE `disable_board_focus()` -- ungrab runs a rebuild whose
  fresh controls are born FOCUS_ALL, so the disable must come last. New test name
  `TestSidebar.test_the_outcome_screen_leaves_no_card_armed`, under the behavior section
  "THE RESOLVED SHOW LEAVES NOTHING ARMED".
- S23: `MapNamePopup.show_above(node_name: String, node: WorldGraphNode)` is the popup's whole API
  besides `hide_name()` -- the map hands it the title of the entry it just published and the node
  itself, and the popup holds that node as the only thing it remembers.
- S23: `WorldMapController.node_screen_rect(node)` is the one conversion from a graph node to the
  map viewport's own coordinates (`get_global_transform_with_canvas()` + `marker_radius`), shared
  by the popup's placement and by the tests that check it. It is `static`: the popup re-asks it
  every frame and holds no controller.
- S23: the FIRST TAP RULE lives in `WorldMapController._consumed_as_touch()`, which also swallows
  the mouse press the engine emulates from that finger (`device == -1`, the same discrimination
  `UI/play_area.gd` uses) because the emulated press arrives BEFORE the touch event. The tapped
  node is remembered in `_tapped_node`; `_try_click()` became `_travel_to(node)`, and the mouse's
  own path calls it with `_node_at_mouse()`.
- S23: a `FlowContainer` visual is mounted BELOW the body, in `DescriptionPanel`'s new `%GridSlot`,
  and given the panel's own width to wrap at; every other visual still sits beside the name in the
  top row. `_slot_for(visual)` is the one place that choice is made -- a grid of many needs the
  whole width, which the name's row does not have. No flag on `InfoEntry`.
- S23: the popup keeps the last node's name after the pointer leaves -- `Map` still connects no
  `node_unhovered` -- but it is ANCHORED to that node, not to a place: it re-places itself against
  the node's current screen rect every frame it is up, so travel, a pan, a zoom and a resize all
  carry it. Fix 13: the sidebar's keep-the-last-entry rule governs the sidebar only; the popup's
  own lifetime ends when there is no dot to name.
- Fix 13: `MapNamePopup.hide_name()` is called from three places in `Map` -- the run starting, a
  node being entered, and `HudContainer.active_screen_changed` (the new no-argument signal the
  container emits when a different screen becomes the active one, the same swap the HUD makes).
- Fix 13: the tests drive a real pan through `TestSidebar._pan_map_by()` (a motion without its own
  `relative` pans nothing), and `_enter_game_fixture()` is the tail of `_start_game_fixture()`
  split out so a test can act on the map first and still reach the board by the product's route.
- S23: `TestSidebar._start_game_fixture()` was split: `_start_map_fixture()` is the real `Main`
  resting on its generated map, and the game fixture carries it on into a dealt board. The shared
  teardown is `_end_main_fixture()` (renamed from `_end_game_fixture`), and the map picture's
  viewport is `_map_viewport`.
- Phase 7 fix 12: `Game._replay_pending_placement()` releases the resume's board lock before the
  placement, so the replay runs the SAME route a live placement does -- its commit (which clears
  the marker), its goal check before the refill, and the unlock it leaves behind. No new flag.
- Phase 7 fix 12: `_end_show_if_goal_met()` also requires the show not already ended, so a replay
  that ended the show itself is not held a second time.
- Phase 7 fix 12: `TestEntranceStocks` gains `GOAL_OUT_OF_REACH` (the same 1000000 the other
  suites use) plus `_last_card_entrance_game()`, `_arm_interrupted_placement()`, `_cell_is_filled()`
  and `_restore_run()` -- the fixture for a quit mid-cascade and the teardown its tests share.
- Fix 14: `WorldMapController._consumed_as_touch()` takes ONLY the emulated mouse RELEASE that
  closes a press which never crossed `DRAG_THRESHOLD` -- the map's one distance model, the same
  `_dragging` the mouse path uses. The emulated press and motion take that path untouched, so a
  finger pans exactly as a mouse drag does; the first-tap rule fires on the lift, not the down.
- Fix 14: `TestSidebar._push_touch(at, pressed)` is the bare finger form, `_push_finger()` the
  whole tap and `_drag_finger_by(from, by)` the whole drag, both in the engine's dispatch order
  (the emulated mouse form of a touch before the touch, at the press and again at the release).
- Fix 15: `DescriptionPanel._mount_visual()` takes the old visual OUT of its slot before freeing
  it -- a queue-freed child is still a child until the frame ends, and `resize_to()` measures the
  slots in the same call. New test names in `TestSidebar`:
  `test_a_replaced_preview_grid_takes_its_height_with_it`, the helpers
  `_hover_map_node_and_settle()`, `_content_height()`, `_scroll_overflow()`, and
  `_a_map_node_with_role(role)` which replaces `_a_booster_node()` so a show node is reachable too.
- Fix 15: the sidebar's scroll EXTENT settles a frame or more after a visual is re-mounted (a pack
  replacing a pack reads 0 overflow while its grid is 1004 px tall), so a height assertion uses the
  content's own laid-out height and the extent is only asked whether a short entry scrolls at all.
- Close fix 1: `Game.undo()` releases `processing` as its LAST statement, after the history
  pop, so the view's re-arm edge derives the armed card from the RESTORED Entrance instead of
  the state being discarded. New test helper name `TestInteraction.an_empty_cell_control()`,
  the control an armed card is aimed at (a free cell presents its own zone card).
- Close fix 2: a screen's remembered description dies with its CONTENT on every screen, not only
  the game's. `HudContainer.connect_for_screen()` connects the screen's `tree_exiting` once
  (one-shot) to `disconnect_for_screen()`, replacing the `_exit_tree()` pairs in `GameView`,
  `Map` and `Menu`; `GameView` connects its own `tree_exiting` to `release_screen(GAME_SCREEN)`,
  `Map.start_run()` releases `MAP_SCREEN` (the map persists across runs, its content is the run)
  and `Menu` releases `MENU_SCREEN` when the deck picker leaves the tree. New names:
  `HudContainer.MAP_SCREEN`, `HudContainer.MENU_SCREEN`, and the `TestSidebar` tests
  `test_a_new_run_does_not_inherit_the_maps_last_description`,
  `test_closing_the_picker_drops_the_menus_description`.
- Close fix 3: a release places only when the dragged card IS the held one (`dragged in selected_cards` in `PlayArea._consume_as_card_release`); a drag whose pickup the board refused ends with nothing to drop, so the armed card no longer lands where a grid card or an empty cell's zone card was dragged. No new production name. New test names in `TestDragPlace`: `test_a_refused_drag_from_an_empty_cell_places_nothing`, `test_a_refused_drag_from_a_grid_card_places_nothing`, `_check_a_refused_drag_places_nothing()`, `_an_empty_cell_other_than()`, `_is_in_the_entrance()`, and `_is_reachable()`, which `_legal_cell_control()` now shares: it skips a zero-area cell control, which `Rect2.encloses` accepts and a release aimed at lands on nothing (it made the grid-card row pass vacuously).
- Close fix 4: a DISMISSAL forgets the screen's remembered description; a swap that is not one keeps
  it. `HudContainer.dismiss_description()` frees the shown entry, erases the screen's memory and
  then calls `show_hud()`; the exit X, cancel and a bare-board press (via
  `GameView._on_description_dismiss_requested`), a landed placement (`GameView._place_held_onto`)
  and the wall editor's lock toggle call it. `show_hud()` stays for the cascade hold (S7: a screen
  returned to mid-cascade keeps its memory) and the container's own `_ready`. New `TestSidebar` rows
  `test_a_description_dismissed_with_the_x_stays_dismissed_on_return`,
  `test_a_description_a_placement_took_down_stays_down_on_return`, helper
  `_leave_the_game_and_return_by_the_wall()`.
- Close fix 5: `GameView.pile_center(pile)` is where a card leaving the board aims -- the pile's
  window centre carried once through `WallPicture.local_rect_beside(window, Rect2(), false)` (the
  unmargined resting map, within ~6 px of the drawn point at `wall_overfill_margin` 1.02). With no
  `wall_picture` (a GameView hosted without `Main`) it returns the window point, as
  `HudContainer.rect_beside` does. `CardVisual.get_control_center` is deleted. New `TestSidebar` row
  `test_a_card_leaving_the_board_flies_to_its_pile`, helper `_check_flight_lands_on()`.
- Close fix 7: a grid placement arms the Entrance ONCE, after its refill and commit, whichever route
  drove it: `Game.place_card_in_grid` ends a player's non-winning placement with the new
  `GameView.arm_after_placement()` (drop the hand, re-derive the arm), which `_place_held_onto` used
  to do after `try_place` returned -- so a resume's replay arms the card its refill drew. New
  `TestSidebar` row `test_a_resumed_placement_arms_the_card_its_refill_drew`.
- Close fix 8: accept on the exit X from the keyboard or pad hands the focus back to the board.
  `HudContainer._on_exit_gui_input()` takes `ui_accept` in the X's `gui_input` signal, which the
  engine emits before `BaseButton` handles the event, dismisses, and emits the new
  `HudContainer.exit_accepted`. A mouse click stays the button's own `pressed` ->
  `dismiss_description()`: a mouse press also focuses the X (measured), so `has_focus()` cannot tell
  the two apart, and a mouse dismissal must not move the focus. `GameView` connects the signal to the
  new `PlayArea.return_focus_to_board()`, which RESTS the focus (no publish, no following) on
  `focused_control`, or on the armed card through `rest_focus_on_armed()` once that control is freed
  or out of `ui_data`; both rest through the new `_rest_focus_on(control)`. The map connects nothing,
  so its X is unchanged. New `TestSidebar` row
  `test_accepting_the_exit_x_hands_the_focus_back_to_the_board` (helper `_tap_key()`), and a mouse
  check added to `test_the_exit_x_reverts_to_the_hud`. Undo at the outcome screen stays out of a
  pad's reach -> GAP-009, not fixed.
