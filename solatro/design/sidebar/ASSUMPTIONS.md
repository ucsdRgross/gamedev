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
  `WHEEL_STEP_PAGES` const, `HudContainer._key_scroll_pages()`, `_aim_scroll_stick()`,
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
- S12: the deck picker's own Inspect viewer (`UI/deck_picker.gd`, inside the start menu) is
  deliberately NOT wired to a relay. `Q143`=a makes an empty sidebar the right answer where nothing
  publishes, and PLAN 3a's touch list does not name `menu.gd`/`deck_picker.gd`; the viewer's
  `info_requested` simply has no listener there and `relay_to()` frees each entry it builds.
- S12: `UI/deck_builder.tscn` lost its broken `Cards/card.tscn` `ext_resource`, the `Card` node it
  instanced and the dead "Skill Text" `Label` beside it. The tool's preview is now a real
  `ControlCard` built in `_ready()` over a `preview_data : CardData` the option buttons mutate --
  `CardVisual` redraws itself off `CardData.data_changed`, so nothing rebuilds it (Q166=c, L13).
