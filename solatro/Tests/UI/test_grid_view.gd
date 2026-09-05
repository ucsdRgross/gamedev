extends TestSuite
# res://Tests/UI/test_grid_view.gd
# ==============================================================================
# S26 — THE TWO VIEW MODES. The board is either showing every grid (orientation) or focused on
# one grid (where placement happens). Nothing sits between them.
#
# CATEGORY MAP: BEHAVIOR — what the player sees when a show opens, and what a click on a grid
# does before they have chosen one. There is no IMPLEMENTATION pin here: the mode is only worth
# anything through the input path, so every check drives the REAL handler on a REAL control.
#
# ⚠ NONE OF THIS IS EVIDENCE ABOUT PIXELS (repo rule 4).
# ==============================================================================

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
## The real wall picture, for the render-target checks: the game screen is a picture on the wall,
## so its render target is only meaningful through the node that owns one.
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
## The real app root, for the camera-dependent checks (`GAP-026`=(a)) — see `_stand_up_main_grids`.
const MAIN_SCENE := preload("res://Levels/main.tscn")
const KEY_COMMA := 44
const KEY_PERIOD := 46

var _prev_run : RunState
var _prev_save_info : RunState

func suite_name() -> String:
	return "GRID VIEW"

func _ready() -> void:
	# This suite hosts a real GameView and writes the shared `CardEnvironment.CURRENT`, so it waits
	# for every sibling that hosts one too. See TestSuite's DEADLOCK RULE and its ordering chain.
	await await_siblings_except(["SETTINGS RANGE", "E2E RUN", "LEAK CANARY", "WALL PAUSE"])
	TestLog.line("============ GRID VIEW TEST PASS ============")
	check_all_tests_registered()
	await run_the_show_opens_zoomed_out_test()
	await run_one_grid_opens_focused_test()
	await run_clicking_a_grid_zooms_in_on_it_test()
	await run_back_zooms_out_and_forward_returns_test()
	await run_panning_has_its_own_actions_test()
	await run_every_pan_lands_a_grid_centred_test()
	await run_the_board_rests_positioned_test()
	await run_the_focused_grid_is_as_tall_as_its_window_test()
	await run_focusing_takes_the_other_grids_out_of_view_test()
	await run_a_non_focused_grid_paints_nothing_outside_the_window_test()
	await run_the_board_edge_bounces_test()
	await run_the_clamp_collapses_to_centre_when_it_fits_test()
	await run_one_scroll_container_on_the_board_test()
	await run_panning_shifts_which_three_are_in_frame_test()
	await run_arrows_cross_a_grid_boundary_test()
	await run_overview_arrows_select_a_grid_test()
	await run_removing_the_focused_grid_refocuses_left_test()
	await run_the_board_recentres_after_any_removal_test()
	await run_the_overview_view_and_cursor_agree_after_a_removal_test()
	# ⚠ THE TOUCH TESTS GO LAST: a touch leaves no hover behind, and the mouse paths above need one.
	await run_a_swipe_fires_once_test()
	await run_a_drag_on_a_card_places_and_on_the_board_pans_test()
	await run_the_game_picture_fits_exactly_three_grids_test()
	await run_the_render_target_never_exceeds_the_clamp_test()
	await run_the_camera_steps_between_grid_positions_test()
	await run_the_focused_view_frames_the_block_and_the_entrance_test()
	await run_a_card_between_grids_is_never_clipped_away_test()
	await run_the_camera_rests_at_the_saved_pan_test()
	await run_leaving_and_re_entering_restores_the_pan_test()
	await run_a_resize_re_derives_the_pose_from_the_saved_pan_test()
	finish()

## FIX-GRID-3 standing in a real GameView: the show's own board grown to three empty 5x5 grids.
## Mirrors `test_grid_layout._stand_up` — same goal-out-of-reach and same CardEnvironment
## re-assertion, for the same reasons its comments give.
func _stand_up() -> GameView:
	return await _stand_up_grids(3)

## The same stand-up at any grid count: FIX-GRID-3 at 3, FIX-GRID-1 at 1.
## `host` is where the view is mounted; the suite itself by default. TP-141 passes a SubViewport of
## the picture's own size, because a rendered pixel is only the product's pixel inside one.
func _stand_up_grids(n: int, host: Node = null) -> GameView:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260829)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	var mount : Node = host if host else self
	mount.add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	while view.game.state.grids.size() < n:
		Board.add_grid(view.game.state, GridData.new())
	while view.game.state.grids.size() > n:
		Board.remove_grid(view.game.state, view.game.state.grids.size() - 1)
	view.play_area.flush_rebuild()
	# ⚠ THIS FIXTURE GROWS THE BOARD AFTER THE SHOW HAS ALREADY OPENED, which production never
	# does — the rules deck builds every grid in one deal, so `PlayArea` settles its opening view
	# once and latches. Re-opening it here puts the fixture back in the state the same grid count
	# would have reached on its own, and it is the product's own entry point deciding, not the test.
	view.play_area.open_show_view()
	await get_tree().process_frame
	return view

func _tear_down(view: GameView) -> void:
	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = _prev_run
	Main.save_info = _prev_save_info

## THE `Main`-HOSTED FIXTURE (`GAP-026`=(a)): OVERVIEW stepping now lives on the wall camera, so any
## check that reads it needs a REAL `Main`/`Wall`/`%Camera2D`, not the bare `GameView` above — a
## hand-wired stand-in is exactly what hard rule 6 forbids. Modelled on
## `Tests/Visual/overview_pan_route_probe.gd`, proven to produce a camera that really steps: same
## `Levels/main.tscn` instantiation, same `enter_game()` entry, same real-save park/restore.
func _stand_up_main_grids(n: int) -> Main:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260829)
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false   # Wall._ready() sets this globally; undone same as the probe.
	await get_tree().process_frame
	await get_tree().process_frame
	await main.enter_game()
	await get_tree().process_frame
	var view := _main_game_view(main)
	CardEnvironment.CURRENT = view.game
	while view.game.state.grids.size() < n:
		Board.add_grid(view.game.state, GridData.new())
	while view.game.state.grids.size() > n:
		Board.remove_grid(view.game.state, view.game.state.grids.size() - 1)
	view.play_area.flush_rebuild()
	view.play_area.open_show_view()   # same reason as `_stand_up_grids` above
	await get_tree().process_frame
	return main

## The live `GameView` `Main.enter_game()` mounted, reached through the wall picture it is a screen
## of — the same lookup the route probe uses.
func _main_game_view(main: Main) -> GameView:
	var game_wp : WallPicture = main._pictures[&"game"]
	return game_wp.screen_root as GameView

## The one `%Camera2D` the whole app shares, owned by `Main`'s `Wall`.
func _main_camera(main: Main) -> Camera2D:
	return main.wall.get_node(^"%Camera2D") as Camera2D

func _tear_down_main(main: Main) -> void:
	_main_game_view(main).queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = _prev_run
	Main.save_info = _prev_save_info
	main.queue_free()
	await get_tree().process_frame

## Fires the `pressed` half of a real `InputEventKey` through the engine's own pipeline — the same
## route a physical key press takes, never a direct call to the handler it drives.
func _fire_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)

## The matching release — a real key press is press-then-release, and leaving it held could confuse
## the next simulated key.
func _fire_key_release(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = false
	Input.parse_input_event(ev)

## Wait for the CAMERA to stop moving, mirroring `_settle_scroll` for the fixture whose horizontal
## authority is the camera rather than the scroll container (`GAP-024`=(b)). The step is tweened
## over ~18 frames, so a frame count is the wrong instrument here too.
func _settle_camera(camera: Camera2D) -> void:
	var last := INF
	var waited := 0.0
	while waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if is_equal_approx(camera.position.x, last): return
		last = camera.position.x

## Grid `gi`'s cut-off, in px, against the CAMERA's OWN `visible_rect()` — never reconstructed from
## `resting_state()`/`grid_state()` (`GAP-026`). 0 when the grid's cell block sits wholly inside it.
## Reuses `_grid_world_rect` (`TP-105`), the world-space rect through the real `WallPicture.rect`.
func _camera_cut_off_px(main: Main, pa: PlayArea, camera: Camera2D, gi: int) -> float:
	var visible := _board_view_rect(main, camera)
	var r := _grid_world_rect(main, pa, gi)
	return maxf(maxf(visible.position.x - r.position.x, 0.0), maxf(r.end.x - visible.end.x, 0.0))

## Does grid `gi`'s cell block put any pixel inside the CAMERA's OWN `visible_rect()`?
func _camera_overlaps(main: Main, pa: PlayArea, camera: Camera2D, gi: int) -> bool:
	var visible := _board_view_rect(main, camera)
	var r := _grid_world_rect(main, pa, gi)
	return r.end.x > visible.position.x and r.position.x < visible.end.x

## What the camera shows OF THE BOARD'S OWN AREA -- its visible rect with the HUD's share taken off
## the left.
##
## ⚠ **ISOLATION IS MEASURED IN THE BOARD'S AREA, NOT THE CAMERA'S WHOLE RECT** (owner: *"the center
## should be on halfway through the 0.75 section... pretend 0.75 area is the entire camera view, so
## its truly centered"*). The board centres in its own area, so measuring "out of view" against the
## whole picture asked the LEFT neighbour to clear a boundary the right one did not -- the two
## become symmetric the moment the board's area is the frame of reference.
func _board_view_rect(main: Main, camera: Camera2D) -> Rect2:
	var window_size := main.get_viewport().get_visible_rect().size
	var visible := WallTransition.visible_rect(camera.position, camera.zoom.x, window_size)
	var wp : WallPicture = main._pictures[&"game"]
	var left := wp.rect.centre.x - wp.rect.size.x * 0.5 			+ wp.rect.size.x * SettingsManager.settings.hud_width_fraction
	return visible.intersection(Rect2(Vector2(left, visible.position.y),
			Vector2(maxf(visible.end.x - left, 1.0), visible.size.y)))

## Does the board's real span, first grid to last, exceed the CAMERA's OWN `visible_rect()`? The
## OVERVIEW pan is the camera (`GAP-024`=(b)), so this is the overview's version of
## `_board_overflows()`, which measures the scroller instead.
func _camera_board_overflows(main: Main, pa: PlayArea, camera: Camera2D) -> bool:
	var window_size := main.get_viewport().get_visible_rect().size
	var visible := WallTransition.visible_rect(camera.position, camera.zoom.x, window_size)
	var first := _grid_world_rect(main, pa, 0)
	var last := _grid_world_rect(main, pa, pa.grid_container.get_child_count() - 1)
	return last.end.x - first.position.x > visible.size.x

## Wait for the geometry to STOP MOVING, never for a fixed frame count — a container sorts its
## children a frame after the rebuild that changed them. Same shape as the Phase 5 suite's helper,
## including its re-assertion of the shared `CardEnvironment.CURRENT` on every frame it waits.
func _settle_layout(view: GameView) -> void:
	var pa := view.play_area
	CardEnvironment.CURRENT = view.game
	pa.flush_rebuild()
	var last := INF
	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		CardEnvironment.CURRENT = view.game
		var now := pa.slot_center_global(BoardCoord.new(0, 0, 0, 0)).y
		if is_equal_approx(now, last): return
		last = now

## The zone-card control of cell (0,0) in grid `gi` — a real board control the player can click.
func _cell_control(pa: PlayArea, gi: int) -> Control:
	var panel : Control = pa.grid_container.get_child(gi)
	var row : Control = pa._cells_root(panel).get_child(0) as Control
	var slot : Control = row.get_child(0) as Control
	return slot.get_child(0) as Control

## A left press delivered to the board's OWN gui handler, with the hover and focus state a real
## click carries. ⚠ Not a call to the focus method — a click that stops reaching the board must
## fail this.
func _click(pa: PlayArea, control: Control) -> void:
	pa.focused_control = control
	pa.moused_hovered_control = control
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	pa._on_gui_input(press)

# ==============================================================================
# TP-97 — FIX-GRID-3: the show opens zoomed out.
# ==============================================================================
func run_the_show_opens_zoomed_out_test() -> void:
	behavior_section("THE SHOW OPENS ZOOMED OUT")
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)
	check(pa.grid_container.get_child_count() == 3,
			"precondition: three grids are on the board (TP-97 fixture FIX-GRID-3)",
			"%d panels" % pa.grid_container.get_child_count())
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"a show opens on the all-grids view, not focused on a grid",
			"mode %d" % pa.view_mode)
	check(pa.focused_grid == PlayArea.NO_GRID,
			"nothing is focused until the player chooses a grid",
			"focused_grid %d" % pa.focused_grid)
	await _tear_down(view)

# ==============================================================================
# FIX-GRID-1: with exactly one grid the show opens FOCUSED, so no click is needed to zoom in
# (owner ruling: "clicking to zoom in when there is only 1 grid should not be necessary").
#
# ⚠ NOT AN EDGE CASE. Q4=(d) and Q5 make one grid the answer for any deck of 52 or fewer, so this
# is the DEFAULT starting configuration.
#
# ⚠ THE BOARD ZOOM IS ASSERTED, NOT ONLY THE MODE. A mode flag that never reached the zoom is
# exactly the defect TP-139 exists for; a view that claims to be focused at OVERVIEW_BOARD_ZOOM
# shows the player the overview.
# ==============================================================================
func run_one_grid_opens_focused_test() -> void:
	behavior_section("ONE GRID OPENS FOCUSED")
	var view := await _stand_up_grids(1)
	var pa := view.play_area
	await _settle_layout(view)
	check(pa.grid_container.get_child_count() == 1,
			"precondition: exactly one grid is on the board (FIX-GRID-1)",
			"%d panels" % pa.grid_container.get_child_count())
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"a one-grid show opens FOCUSED -- no click is needed to zoom in",
			"mode %d" % pa.view_mode)
	check(pa.focused_grid == 0,
			"...on the only grid there is",
			"focused_grid %d" % pa.focused_grid)
	check(pa.board_zoom > PlayArea.OVERVIEW_BOARD_ZOOM,
			"...and the ZOOM went with the mode, not just the flag",
			"board_zoom %.4f vs overview %.4f" % [pa.board_zoom, PlayArea.OVERVIEW_BOARD_ZOOM])
	# The Back level stack is untouched: the overview is still reachable from a focused one-grid
	# board, so nothing the player could do before is gone.
	pa.open_zoomed_out()
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"the all-grids view is still reachable with one grid -- Back loses nothing",
			"mode %d" % pa.view_mode)
	await _settle_scroll(view)
	await _tear_down(view)

# ==============================================================================
# TP-98 — FIX-GRID-3: clicking a grid zooms in on it, and that click places NOTHING. The same
# click, once focused, is a placement again — that is the pair that separates the two modes.
# ==============================================================================
func run_clicking_a_grid_zooms_in_on_it_test() -> void:
	behavior_section("CLICKING A GRID ZOOMS IN ON IT")
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)
	var selected : Array[CardData] = []
	pa.data_selected.connect(func(d: CardData) -> void: selected.append(d))
	var control := _cell_control(pa, 1)
	check(control in pa.ui_data,
			"precondition: the clicked cell is a real bound board control")
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"precondition: the board is still in the overview")

	_click(pa, control)
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"a click on a grid in the overview zooms in",
			"mode %d" % pa.view_mode)
	check(pa.focused_grid == 1,
			"it zooms in on the grid that was clicked, not on some other one",
			"focused_grid %d" % pa.focused_grid)
	check(selected.is_empty(),
			"the overview is orientation only: that click acted on no card",
			"%d selections" % selected.size())

	_click(pa, control)
	check(selected.size() == 1,
			"the SAME click, once focused, acts on the card again",
			"%d selections" % selected.size())
	check(pa.focused_grid == 1,
			"a click inside the focused grid does not re-focus anything")
	await _tear_down(view)

# ==============================================================================
# The rest of Phase 6's view: the level stack, the pan actions, the snap, the bounce.
# ==============================================================================

## An action press as the real input path sees it. Built as an action rather than a key so these
## checks assert the READER; the bindings get their own check in TP-100.
func _action(name: StringName) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e

## Clear the viewport's "input handled" flag, so the next drive can be read honestly. A dispatch
## resets the flag on entry, so pushing an event nothing is bound to is what clears it.
func _reset_input_handled() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_F13
	e.pressed = true
	get_viewport().push_input(e)

## The scroll container the board actually pans in.
func _scroller(pa: PlayArea) -> SmoothScrollContainer:
	return pa.scroll_container as SmoothScrollContainer

## Wait for the BOARD to stop moving horizontally. A pan and a bounce both have a DURATION, so a
## still frame taken right after the press is the wrong instrument for either.
## Returns how long that took, in seconds: a move with a DURATION is the only thing that can take
## longer than one frame to come to rest.
func _settle_scroll(view: GameView) -> float:
	var smooth := _scroller(view.play_area)
	var last := INF
	var waited := 0.0
	while waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		CardEnvironment.CURRENT = view.game
		var now := smooth.pos.x
		if is_equal_approx(now, last): return waited
		last = now
	return waited

## The board's VISIBLE window in global x: the scroll container's own rect less whatever a visible
## vertical scrollbar takes off its right edge. ⚠ Not the rect itself — a shown v-scrollbar narrows
## the content area, and the board is laid out inside what is left, so the rect's own centre is off
## by half the bar (measured: 4 px).
func _window_x(pa: PlayArea) -> Vector2:
	var bar := pa.scroll_container.get_v_scroll_bar()
	var taken : float = bar.size.x if bar and bar.visible else 0.0
	var win := _screen_rect(pa.scroll_container)
	return Vector2(win.position.x, win.end.x - taken * win.size.x / maxf(pa.scroll_container.size.x, 1.0))

## A control's rect AS DRAWN, in the picture's own pixels.
##
## ⚠ **`global_position` CARRIES EVERY SCALE ABOVE IT AND `size` CARRIES NONE**, so the two cannot
## be added together on a board that zooms. Read through the engine's own transform instead of a
## named scale: that keeps this instrument true of ANY implementation that makes a grid bigger on
## screen, rather than only of the one the product happens to use.
func _screen_rect(c: Control) -> Rect2:
	var t := c.get_global_transform()
	return Rect2(t.origin, t.get_scale() * c.size)

## How far grid `gi`'s CELL BLOCK hangs outside that window, in pixels; 0 when it is wholly on
## screen. The instrument for "no cut-off grid at rest" — a rule scoped to the grid the view is ON:
## ⚠ ask it about that grid, never about every grid on the board (owner ruling).
func _cut_off_px(pa: PlayArea, gi: int) -> float:
	var cells := pa._cells_root(pa.grid_container.get_child(gi) as Control)
	var r := _screen_rect(cells)
	var win := _window_x(pa)
	return maxf(maxf(win.x - r.position.x, 0.0), maxf(r.end.x - win.y, 0.0))

## Does the board actually overflow its window? Every pan claim below is vacuous if it does not.
func _board_overflows(pa: PlayArea) -> bool:
	return _scroller(pa).should_scroll_horizontal()

# ==============================================================================
# TP-99 - FIX-GRID-3: Back zooms out a level, Forward returns to the view it left.
# ==============================================================================
func run_back_zooms_out_and_forward_returns_test() -> void:
	behavior_section("BACK ZOOMS OUT AND FORWARD RETURNS")
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)
	pa.focus_grid(2)
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED and pa.focused_grid == 2,
			"precondition: the board is focused on grid 2 (TP-99)",
			"mode %d grid %d" % [pa.view_mode, pa.focused_grid])

	pa._unhandled_input(_action(&"wall_back"))
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"Back zooms OUT a level: focused grid -> all grids (TP-99)",
			"mode %d" % pa.view_mode)
	check(pa.focused_grid == PlayArea.NO_GRID,
			"...and nothing is focused in the all-grids view",
			"focused_grid %d" % pa.focused_grid)

	pa._unhandled_input(_action(&"wall_forward"))
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"Forward returns to the previous view (TP-99)",
			"mode %d" % pa.view_mode)
	check(pa.focused_grid == 2,
			"...to the SAME grid it zoomed out of, not to grid 0",
			"focused_grid %d" % pa.focused_grid)
	await _settle_scroll(view)
	await _tear_down(view)

	# A GRID CAN GO WHILE THE VIEW IS ZOOMED OUT, and Forward's memory is an INDEX: every index
	# right of the hole names a different grid afterwards. Checked on IDENTITY, never on the index.
	view = await _stand_up_grids(5)
	pa = view.play_area
	await _settle_layout(view)
	var remembered : GridData = view.game.state.grids[3]
	pa.focus_grid(3)
	pa._unhandled_input(_action(&"wall_back"))
	Board.remove_grid(view.game.state, 1)
	pa.flush_rebuild()
	await _settle_layout(view)
	pa._unhandled_input(_action(&"wall_forward"))
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"Forward still returns after a grid elsewhere on the board went (TP-99)",
			"mode %d" % pa.view_mode)
	check(view.game.state.grids[pa.focused_grid] == remembered,
			"...to the SAME GRID Back left, which has shifted one index left (TP-99)",
			"focused_grid %d" % pa.focused_grid)
	await _settle_scroll(view)
	await _tear_down(view)

	# AND WHEN THE REMEMBERED GRID ITSELF GOES there is no view to return to, so Forward has
	# nothing left to give and FALLS THROUGH to the wall — it must not be swallowed and do nothing,
	# and it must not land on whichever grid slid into that index.
	view = await _stand_up_grids(5)
	pa = view.play_area
	await _settle_layout(view)
	pa.focus_grid(3)
	pa._unhandled_input(_action(&"wall_back"))
	Board.remove_grid(view.game.state, 3)
	pa.flush_rebuild()
	await _settle_layout(view)
	_reset_input_handled()
	check(not get_viewport().is_input_handled(),
			"instrument check: the handled flag starts clear (TP-99)")
	pa._unhandled_input(_action(&"wall_forward"))
	check(not get_viewport().is_input_handled(),
			"Forward with the remembered grid gone is NOT swallowed -- it reaches the wall (TP-99)")
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"...and the board stayed in the overview rather than focusing another grid (TP-99)",
			"mode %d grid %d" % [pa.view_mode, pa.focused_grid])
	await _settle_scroll(view)
	await _tear_down(view)

# ==============================================================================
# TP-100 - FIX-GRID-3: panning uses the NEW actions, and the wall's shoulder buttons still reach
# the wall.
#
# THE DISCRIMINATING CASE IS BACK WHILE ALREADY IN THE ALL-GRIDS VIEW. Zoom intercepting Back and
# the wall keeping Back are only compatible because the board hands the event back once it has no
# level left to step out of. Delete that fall-through and the wall is unreachable from inside a
# show while every other check in this suite still passes - so it is checked on the REAL handler,
# through the REAL "was this consumed" flag.
# ==============================================================================
func run_panning_has_its_own_actions_test() -> void:
	behavior_section("PANNING HAS ITS OWN ACTIONS AND THE WALL KEEPS ITS SHOULDERS")
	for action : StringName in [&"grid_pan_left", &"grid_pan_right"]:
		check(InputMap.has_action(action),
				"%s exists as an action (TP-100)" % action)
		var has_key := false
		var has_pad := false
		for e : InputEvent in InputMap.action_get_events(action):
			if e is InputEventKey: has_key = true
			if e is InputEventJoypadButton or e is InputEventJoypadMotion: has_pad = true
		check(has_key and has_pad,
				"%s is bound on keyboard AND joypad" % action,
				"key %s pad %s" % [has_key, has_pad])

	# The pan bindings and the wall's shoulder bindings are disjoint: that is what "new actions on
	# different bindings" means, and a shared event would make the two fight.
	var wall_codes : Array[int] = []
	for a : StringName in [&"wall_back", &"wall_forward"]:
		for e : InputEvent in InputMap.action_get_events(a):
			var k := e as InputEventKey
			if k: wall_codes.append(int(k.keycode))
	var overlap := false
	for a : StringName in [&"grid_pan_left", &"grid_pan_right"]:
		for e : InputEvent in InputMap.action_get_events(a):
			var k := e as InputEventKey
			if k and wall_codes.has(int(k.keycode)): overlap = true
	check(not overlap,
			"the pan keys are not the wall's Back/Forward keys (TP-100)")
	check(wall_codes.has(int(KEY_BRACKETLEFT)) and wall_codes.has(int(KEY_BRACKETRIGHT)),
			"wall_back / wall_forward keep their own bindings",
			"%s" % [wall_codes])

	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)

	# THE FALL-THROUGH. In the all-grids view there is no level left, so Back must NOT be consumed.
	pa.open_zoomed_out()
	_reset_input_handled()
	check(not get_viewport().is_input_handled(),
			"instrument check: the handled flag starts clear")
	pa._unhandled_input(_action(&"wall_back"))
	check(not get_viewport().is_input_handled(),
			"Back in the all-grids view is NOT swallowed -- it reaches the wall (TP-100)")
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"...and the board stayed where it was",
			"mode %d" % pa.view_mode)

	# The same press one level deeper IS the board's, which is what makes the check above a
	# distinction rather than a dead handler.
	pa.focus_grid(1)
	_reset_input_handled()
	pa._unhandled_input(_action(&"wall_back"))
	check(get_viewport().is_input_handled(),
			"Back on a focused grid IS intercepted by the board (TP-100)")

	# Forward with nothing to return to falls through for the same reason.
	pa._zoom_out_grid = PlayArea.NO_GRID
	_reset_input_handled()
	pa._unhandled_input(_action(&"wall_forward"))
	check(not get_viewport().is_input_handled(),
			"Forward with no view to return to reaches the wall too (TP-100)")
	await _settle_scroll(view)
	await _tear_down(view)

# ==============================================================================
# TP-101 - FIX-GRID-3: every pan lands the grid the view is on centred, and that grid is never cut
# off.
#
# ⚠ THE CUT-OFF RULE IS ABOUT THE GRID THE VIEW IS ON, NOT ITS NEIGHBOURS (owner ruling): a
# neighbouring grid sliced by the window edge is not a defect, so nothing here asserts over every
# grid on the board.
# ⚠ NOTHING IS PANNED BEFORE THE FIRST MEASUREMENT. This test used to call `pan_to_grid(0)` first —
# the very call a resting board never makes — and so could not see a board that rests unpositioned.
# ==============================================================================
func run_every_pan_lands_a_grid_centred_test() -> void:
	behavior_section("EVERY PAN LANDS A GRID CENTRED")
	var main := await _stand_up_main_grids(3)
	var view := _main_game_view(main)
	var pa := view.play_area
	var camera := _main_camera(main)
	await _settle_layout(view)
	await _settle_scroll(view)
	await _settle_camera(camera)
	# Re-pointed to FOCUSED (owner ruling): the picture now fits whole in the OVERVIEW, so
	# nothing there overflows the camera frame any more -- H9's pan-lands-centred claim moves to
	# the FOCUSED scroll-stepping mechanism, which still has a board wider than its window.
	pa.focus_grid(1)
	await _settle_scroll(view)
	await _settle_camera(camera)
	check(_camera_board_overflows(main, pa, camera),
			"precondition: three grids are wider than the camera frame, so a pan can move (TP-101)",
			"content %f window %f" % [
					_grid_world_rect(main, pa, pa.grid_container.get_child_count() - 1).end.x
							- _grid_world_rect(main, pa, 0).position.x,
					WallTransition.visible_rect(camera.position, camera.zoom.x,
							main.get_viewport().get_visible_rect().size).size.x])
	var rest_grid := pa.pan_grid
	check(rest_grid == 1,
			"precondition: the view is focused on the middle of three grids (TP-101)",
			"pan_grid %d" % rest_grid)
	check(_camera_cut_off_px(main, pa, camera, rest_grid) <= 1.0,
			"the grid the view rests on is wholly on screen, with no pan asked for (TP-101)",
			"%f px off screen" % _camera_cut_off_px(main, pa, camera, rest_grid))

	pa._unhandled_input(_action(&"grid_pan_right"))
	await _settle_scroll(view)
	await _settle_camera(camera)
	check(pa.pan_grid == rest_grid + 1,
			"a pan-right press steps ONE grid, to grid %d (TP-101)" % (rest_grid + 1),
			"pan_grid %d" % pa.pan_grid)
	check(_camera_cut_off_px(main, pa, camera, pa.pan_grid) <= 1.0,
			"the grid it stepped onto rests wholly on screen -- no cut-off grid UNDER THE VIEW",
			"%f px off screen" % _camera_cut_off_px(main, pa, camera, pa.pan_grid))

	for _i : int in [0, 1]:
		pa._unhandled_input(_action(&"grid_pan_left"))
		await _settle_scroll(view)
		await _settle_camera(camera)
	check(pa.pan_grid == rest_grid - 1,
			"two pan-left presses step back two grids, to grid %d" % (rest_grid - 1),
			"pan_grid %d" % pa.pan_grid)
	check(_camera_cut_off_px(main, pa, camera, pa.pan_grid) <= 1.0,
			"and that grid rests wholly on screen too",
			"%f px off screen" % _camera_cut_off_px(main, pa, camera, pa.pan_grid))
	await _tear_down_main(main)

# ==============================================================================
# TP-138 — THE BOARD RESTS POSITIONED: at rest, with nothing panned, the board sits where an
# explicit pan to the grid the view is on puts it.
#
# ⚠ OVERVIEW-FIXTURE SECTION: THREE GRIDS, MATCHING THE CANVAS BUDGET, CHECKED FOCUSED. At
# <=3 grids the picture fits whole in the OVERVIEW by design, so nothing overflows there any more --
# the resting-position claim is exercised through a focus onto this same three-grid fixture instead
# (the same repoint TP-101 took). `game_picture_design_size()` is authored for `grid_max_count`
# grids (currently 3, unlocked in production), so the fixture needs to be the canvas budget itself --
# more grids than the budget shift the middle grid's cell-block position off a canvas that was never
# resized to match.
#
# ⚠ FOCUSED SECTION: FIVE GRIDS, NOT THREE. With the view on grid 0 the scroll container's own
# clamp parks the board hard left anyway, so an unpositioned board and a correctly positioned one
# are the SAME number and the check passes with the wiring cut. The resting grid has to be one the
# clamp cannot supply.
#
# ⚠ THE CLAIM IS AN IDENTITY, NOT A TOLERANCE: where a grid comes to rest is the layout's business,
# so the reference is the player's own pan to that same grid — the same reference TP-112 uses.
# ==============================================================================
func run_the_board_rests_positioned_test() -> void:
	behavior_section("THE BOARD RESTS POSITIONED ON THE GRID THE VIEW IS ON")
	var overview_main := await _stand_up_main_grids(3)
	var overview_view := _main_game_view(overview_main)
	var overview_pa := overview_view.play_area
	var overview_camera := _main_camera(overview_main)
	var overview_smooth := _scroller(overview_pa)
	await _settle_layout(overview_view)
	await _settle_scroll(overview_view)
	await _settle_camera(overview_camera)
	# Re-pointed to FOCUSED (owner ruling): the picture now fits whole in the OVERVIEW, so nothing
	# there overflows the camera frame any more -- the "resting position is the camera's job"
	# precondition moves to the FOCUSED scroll-stepping mechanism, the same repoint TP-101 took.
	overview_pa.focus_grid(1)
	await _settle_scroll(overview_view)
	await _settle_camera(overview_camera)
	check(_camera_board_overflows(overview_main, overview_pa, overview_camera),
			"precondition (_board_overflows): three grids overflow the camera frame, so resting "
			+ "position is the camera's job (TP-138)")
	check(overview_pa.pan_grid == 1,
			"the overview rests on the MIDDLE grid, so the whole board is centred (TP-138)",
			"pan_grid %d" % overview_pa.pan_grid)
	check(_camera_cut_off_px(overview_main, overview_pa, overview_camera, overview_pa.pan_grid) <= 1.0,
			"...and the grid it rests on is wholly in frame (TP-138)",
			"%f px off screen"
			% _camera_cut_off_px(overview_main, overview_pa, overview_camera, overview_pa.pan_grid))
	var overview_rest := overview_smooth.pos.x
	overview_pa.pan_to_grid(overview_pa.pan_grid)
	await _settle_scroll(overview_view)
	check(absf(overview_smooth.pos.x - overview_rest) <= 1.0,
			"the board at rest is already where an explicit pan to that grid puts it -- it was "
			+ "POSITIONED, not left at scroll zero (TP-138)",
			"rest %.1f vs explicit pan %.1f" % [overview_rest, overview_smooth.pos.x])
	await _tear_down_main(overview_main)

	# FOCUSED: the scroller is still the view (`GAP-024`=(b)), so the resting-grid cut-off stays the
	# scroller-based instrument — its neighbours may be sliced by the window edge and that is not a
	# defect.
	var main := await _stand_up_main_grids(5)
	var view := _main_game_view(main)
	var pa := view.play_area
	await _settle_layout(view)
	await _settle_scroll(view)
	await _settle_camera(_main_camera(main))
	var smooth := _scroller(pa)
	pa.focus_grid(3)
	await _settle_scroll(view)
	var focused_rest := smooth.pos.x
	check(pa.focused_grid == 3 and pa.pan_grid == 3,
			"focusing a grid puts the view on it (TP-138)",
			"focused %d pan %d" % [pa.focused_grid, pa.pan_grid])
	check(_cut_off_px(pa, 3) <= 1.0,
			"the FOCUSED grid rests wholly in frame (TP-138)",
			"%f px off screen" % _cut_off_px(pa, 3))
	pa.pan_to_grid(3)
	await _settle_scroll(view)
	check(absf(smooth.pos.x - focused_rest) <= 1.0,
			"...at exactly the position an explicit pan to it lands (TP-138)",
			"rest %.1f vs explicit pan %.1f" % [focused_rest, smooth.pos.x])
	await _tear_down_main(main)

# ==============================================================================
# TP-139 — THE FOCUSED GRID IS AS TALL AS ITS WINDOW. The two view modes differ ON SCREEN and not
# only in a bookkeeping int: focusing a grid makes that grid's CELL BLOCK exactly as tall as the
# board's window, and zooming back out gives it its overview size back.
#
# ⚠ THIS IS THE WIRING CHECK. `view_mode` and `focused_grid` are values the code assigns itself and
# assert nothing about pixels; a click that reached the mode but not the zoom passes every check on
# them and fails this one. Cut `focus_grid`'s call to the zoom and the block stays at its overview
# height against a window twice that (measured: 286 against 555).
#
# ⚠ THE CLAIM IS AN IDENTITY, NOT A TOLERANCE — "as tall as the window" is a number the layout owes
# exactly, so it is asserted against the window and never against a remembered constant.
# ==============================================================================
func run_the_focused_grid_is_as_tall_as_its_window_test() -> void:
	behavior_section("THE FOCUSED GRID IS AS TALL AS ITS WINDOW")
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)
	pa.open_zoomed_out()
	await _settle_layout(view)
	await _settle_scroll(view)
	var window_h := _screen_rect(pa.scroll_container).size.y
	var overview_h := _screen_rect(pa._cells_root(pa.grid_container.get_child(1) as Control)).size.y
	check(window_h > 1.0 and overview_h > 1.0,
			"precondition: the board and its window are both on screen (TP-139)",
			"window %.1f grid %.1f" % [window_h, overview_h])
	check(overview_h < window_h - 1.0,
			"precondition: in the OVERVIEW a grid is SHORTER than the window, so the focused view "
			+ "has somewhere to grow to (TP-139)",
			"grid %.1f vs window %.1f" % [overview_h, window_h])

	pa.focus_grid(1)
	await _settle_layout(view)
	await _settle_scroll(view)
	var focused_h := _screen_rect(pa._cells_root(pa.grid_container.get_child(1) as Control)).size.y
	# ⚠ **THE BLOCK FILLS WHAT THE FIT LEAVES IT, NOT THE WHOLE WINDOW.** `focused_board_zoom()`
	# divides the window by the block PLUS everything else the board must hold -- the Entrance
	# strip, the two edge pads, and the panel/scroller furniture. Asserting the block equals the
	# whole window was true only while those terms were missing from the fit, and closing them
	# (`GAP-039`) is what finally made a focused grid isolate its neighbours. The block is now
	# exactly the window's share of the fit that belongs to it.
	# ⚠ **THE BLOCK FILLS ITS WINDOW LESS THE PANEL FURNITURE.** The window already carries the
	# Entrance strip and the edge pads; what it does NOT carry is the column-label row and the
	# scroller's reserved band, which `focused_content_height_px()` reserves out of the same fit
	# (`GAP-039`). Asserting the block equals the WHOLE window was true only while those terms were
	# missing from the fit -- and closing them is what finally made a focused grid isolate its
	# neighbours. MEASURED: window 407.9, block 363.4, and the 44.5 between them is exactly the
	# 35 board units of furniture at the live zoom of 1.27.
	var window_h2 := _screen_rect(pa.scroll_container).size.y
	var furniture_screen : float = PlayArea.board_furniture_height_px(PlayArea.settings()) 			* pa.board_zoom
	check(absf(focused_h - (window_h2 - furniture_screen)) <= 2.0,
			"the FOCUSED grid's cell block fills its window less the panel furniture the same fit "
			+ "reserves (TP-139)",
			"grid %.1f vs window %.1f" % [focused_h, _screen_rect(pa.scroll_container).size.y])
	check(focused_h > overview_h + 1.0,
			"...which is BIGGER than it was in the overview -- the mode change is a visible one "
			+ "and not a state flag (TP-139)",
			"focused %.1f vs overview %.1f" % [focused_h, overview_h])

	# ⚠ FOCUS A SECOND GRID WITHOUT ZOOMING OUT FIRST. The zoom is derived from the window, and a
	# window read while already zoomed answers in the zoomed board's own units -- which reads as
	# "already the right size" and drops the board back to overview scale on the step.
	pa.focus_grid(2)
	await _settle_layout(view)
	await _settle_scroll(view)
	var stepped_h := _screen_rect(pa._cells_root(pa.grid_container.get_child(2) as Control)).size.y
	check(absf(stepped_h - focused_h) <= 1.0,
			"stepping from one focused grid to the next KEEPS the focused size (TP-139)",
			"stepped %.1f vs first focus %.1f" % [stepped_h, focused_h])

	pa.open_zoomed_out()
	await _settle_layout(view)
	await _settle_scroll(view)
	var back_h := _screen_rect(pa._cells_root(pa.grid_container.get_child(1) as Control)).size.y
	check(absf(back_h - overview_h) <= 1.0,
			"zooming back out gives the grid its overview size back -- the zoom is not one-way "
			+ "(TP-139)",
			"back %.1f vs overview %.1f" % [back_h, overview_h])
	await _tear_down(view)

# ==============================================================================
# TP-140 — FOCUSING TAKES THE OTHER GRIDS OUT OF VIEW (owner ruling). In the overview a neighbour
# overlaps the board's window; focused, every grid but the focused one is wholly outside it.
#
# ⚠ THE FIXTURE IS WHAT GIVES THIS TEETH: focusing the MIDDLE of three grids asks the pan for
# nothing -- the board is already centred there -- so an unzoomed board does not move at all and
# both neighbours stay in frame (measured with the zoom cut: grid 0 at 238.5 against a window
# starting at 423). Focus an OUTER grid instead and the pan alone carries the neighbours out, and
# this check passes while the zoom is missing.
# ==============================================================================
func run_focusing_takes_the_other_grids_out_of_view_test() -> void:
	behavior_section("FOCUSING TAKES THE OTHER GRIDS OUT OF VIEW")
	# `Main`-hosted (`GAP-026`=(a)): "out of view" here means outside the CAMERA's `visible_rect()`
	# (`GAP-024`=(b), confirmed by that gap's own measurement for this exact check), which only a
	# real `%Camera2D` under a real `Main`/`Wall` can answer.
	var main := await _stand_up_main_grids(3)
	var view := _main_game_view(main)
	var pa := view.play_area
	var camera := _main_camera(main)
	await _settle_layout(view)
	pa.open_zoomed_out()
	await _settle_layout(view)
	await _settle_scroll(view)
	await _settle_camera(camera)
	check(_camera_overlaps(main, pa, camera, 0) or _camera_overlaps(main, pa, camera, 2),
			"precondition: in the OVERVIEW a neighbouring grid is in frame beside the middle one "
			+ "(TP-140)",
			"grid 0 %s grid 2 %s"
			% [str(_camera_overlaps(main, pa, camera, 0)), str(_camera_overlaps(main, pa, camera, 2))])

	pa.focus_grid(1)
	await _settle_layout(view)
	await _settle_scroll(view)
	await _settle_camera(camera)
	check(_camera_cut_off_px(main, pa, camera, 1) <= 1.0,
			"the FOCUSED grid is wholly in frame (TP-140)",
			"%.1f px off screen" % _camera_cut_off_px(main, pa, camera, 1))
	var window_size := main.get_viewport().get_visible_rect().size
	for gi : int in [0, 2]:
		check(not _camera_overlaps(main, pa, camera, gi),
				"grid %d is OUT OF VIEW while another grid is focused (TP-140)" % gi,
				"cells %s vs window %s"
				% [str(_grid_world_rect(main, pa, gi)),
				str(WallTransition.visible_rect(camera.position, camera.zoom.x, window_size))])
	await _tear_down_main(main)

## Does grid `gi`'s cell block put any pixel inside the board's window? The instrument for "out of
## view" — an off-screen DISTANCE cannot tell "just outside" from "half in".
func _overlaps_window(pa: PlayArea, gi: int) -> bool:
	var r := _screen_rect(pa._cells_root(pa.grid_container.get_child(gi) as Control))
	var win := _window_x(pa)
	return r.end.x > win.x and r.position.x < win.y

# ==============================================================================
# TP-141 — A NON-FOCUSED GRID PAINTS NOTHING OUTSIDE THE BOARD WINDOW (owner ruling: while focused,
# the other grids are OUT OF VIEW).
#
# ⚠ **THIS ASKS WHAT WAS PAINTED, NOT WHERE ANYTHING SITS, AND THAT IS THE WHOLE POINT.** TP-140
# already proves the neighbours are positioned outside the window, and that was TRUE while a whole
# grid still drew across the side panels — the board's scroll container did not clip, so a grid
# outside its window was painted over the Deck button and the score column all the same. A check
# built on `_screen_rect` alone passes either way and proves nothing.
#
# So this one RENDERS the board and asks whether HIDING a non-focused grid changes any pixel
# outside the window. A grid whose paint is contained changes none; a grid that paints there
# changes many.
#
# ⚠ IT NEEDS THE PICTURE'S OWN VIEWPORT. The board's geometry is only the product's inside a
# viewport of `game_picture_design_size` (grid_zoom_shot records why), and the suite's own root
# viewport holds every other suite's nodes at once.
# ==============================================================================

## The renderer guard. A dummy renderer rasterizes nothing, so every claim below would be vacuous —
## reported as a FAILURE with the fix in the message, never as a skip.
func _check_renderer() -> bool:
	var display := DisplayServer.get_name()
	var live := display != "headless"
	check(live, "the run has a real renderer, so what is PAINTED can be checked at all (TP-141)",
			"DisplayServer is '%s' — re-run all_tests.tscn WITHOUT --headless" % display)
	return live

func run_a_non_focused_grid_paints_nothing_outside_the_window_test() -> void:
	behavior_section("A NON-FOCUSED GRID PAINTS NOTHING OUTSIDE THE WINDOW")
	if not _check_renderer(): return
	var vp := SubViewport.new()
	vp.size = PlayArea.game_picture_design_size(SettingsManager.settings)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var view := await _stand_up_grids(3, vp)
	var pa := view.play_area
	await _settle_layout(view)

	# THE INSTRUMENT CHECK, taken where a grid is SUPPOSED to paint: in the overview, hiding a grid
	# has to change the picture. An assertion that counts zero changed pixels passes trivially on a
	# probe that can see nothing at all.
	pa.open_zoomed_out()
	await _settle_layout(view)
	await _settle_scroll(view)
	var whole := Rect2i(Vector2i.ZERO, vp.size)
	var seen := await _paint_delta(view, vp, 0, whole)
	check(seen > 0,
			"instrument check: the probe SEES paint — hiding a grid changes the rendered picture "
			+ "(TP-141)",
			"%d px changed" % seen)

	pa.focus_grid(1)
	await _settle_layout(view)
	await _settle_scroll(view)
	check(_cut_off_px(pa, 1) <= 1.0,
			"precondition: the focused grid is wholly in frame, so the window is where it belongs",
			"%.1f px off screen" % _cut_off_px(pa, 1))
	# ⚠ **TP-141's ORIGINAL CLAIM IS RETIRED BY OWNER RULING (`GAP-040`=(a)).** It asserted that a
	# non-focused grid paints NOTHING outside the board's window, which was true only because the
	# scroller clipped -- and that clip also cut props and animations authored to leave the board's
	# edges. Isolation is now wholly the CAMERA's, which is what `TP-140` asserts. What is checked
	# here instead is the ruling itself: the board DOES paint through its own window now.
	var painted_outside := 0
	for gi : int in [0, 2]:
		painted_outside += await _paint_delta(view, vp, gi, _outside_window_band(pa, vp, gi == 0))
	check(painted_outside > 0,
			"the board paints THROUGH its window -- nothing on the card layer is clipped away, "
			+ "which is what lets a prop or an animation leave the board's edge (TP-141, "
			+ "GAP-040=(a))",
			"%d px changed outside the window" % painted_outside)
	await _tear_down(view)
	vp.queue_free()

## The strip of the picture on one side of the board's window: everything the clip must keep the
## board out of. ⚠ Measured off the scroll container's OWN rect, not `_window_x` — the clip is to
## that rect, and `_window_x` steps in off the right edge by the scrollbar, which is inside it.
func _outside_window_band(pa: PlayArea, vp: SubViewport, left: bool) -> Rect2i:
	var r := _screen_rect(pa.scroll_container)
	if left: return Rect2i(0, 0, maxi(int(floorf(r.position.x)), 0), vp.size.y)
	var from := mini(int(ceilf(r.end.x)), vp.size.x)
	return Rect2i(from, 0, vp.size.x - from, vp.size.y)

## How many pixels of `area` CHANGE when grid `gi`'s panel is hidden — the render's own answer to
## "does this grid paint here". Outside the window nothing else moves when a grid goes: the side
## panels are laid out beside the scroll container, not inside it.
func _paint_delta(view: GameView, vp: SubViewport, gi: int, area: Rect2i) -> int:
	var panel := view.play_area.grid_container.get_child(gi) as Control
	panel.visible = false
	await _settle_layout(view)
	var without := await _shot(view, vp)
	panel.visible = true
	await _settle_layout(view)
	var shown := await _shot(view, vp)
	return _differing_px(shown, without, area)

## One rendered frame of `vp`, read back. Two waits: the first carries the layout change into a
## drawn frame, the second is the frame that is read.
func _shot(view: GameView, vp: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	CardEnvironment.CURRENT = view.game
	await RenderingServer.frame_post_draw
	CardEnvironment.CURRENT = view.game
	return vp.get_texture().get_image()

## A small tolerance, not an equality: the render target is 8 bit and a channel can land a step
## either side. Same reasoning as `PixelProbe.COLOUR_EPS`, which is where it is written down.
const PAINT_EPS := 2.5 / 255.0

## How many pixels of `area` differ between two frames.
func _differing_px(a: Image, b: Image, area: Rect2i) -> int:
	var clipped := area.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var n := 0
	for y : int in range(clipped.position.y, clipped.end.y):
		for x : int in range(clipped.position.x, clipped.end.x):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > PAINT_EPS or absf(p.g - q.g) > PAINT_EPS \
					or absf(p.b - q.b) > PAINT_EPS or absf(p.a - q.a) > PAINT_EPS:
				n += 1
	return n

# ==============================================================================
# TP-102 - FIX-GRID-3: the board edge bounces.
#
# A BOUNCE IS A MOTION, NOT A POSE. Sampled over frames: the board must MOVE past its resting edge
# and then come back to it. A still frame either side proves nothing.
# ==============================================================================
## THE OVERVIEW's HALF (`GAP-025`=(a)): a show opens on the all-grids view (`PlayArea._ready()` calls
## `open_zoomed_out()`), so this is where `H10`'s edge lives by default -- and OVERVIEW's pan is the
## wall camera (`GAP-024`=(b)), so the bounce needs the real `Main`/`Wall`/`%Camera2D`, same reason
## `GAP-026` moved the other camera-dependent checks onto `_stand_up_main_grids`.
func run_the_board_edge_bounces_test() -> void:
	behavior_section("THE BOARD EDGE BOUNCES")
	var main := await _stand_up_main_grids(3)
	var view := _main_game_view(main)
	var pa := view.play_area
	var camera := _main_camera(main)
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"precondition: a show opens on the all-grids view, where the edge is (TP-102)",
			"mode %d" % pa.view_mode)
	pa.pan_to_grid(2)
	await _settle_camera(camera)
	check(pa.pan_grid == 2,
			"precondition: the view is on the LAST grid, with nowhere further right to go")
	var rest := camera.position.x

	pa._unhandled_input(_action(&"grid_pan_right"))
	# ⚠ **SIGNED, NOT ABSOLUTE.** An `absf()` here is satisfied by a swing in EITHER direction, and
	# a bounce that threw the camera a whole grid INWARD before springing back passed it for as
	# long as it existed. What a bounce means is that the board is pushed FURTHER OUT and comes
	# back, so both extremes are tracked and each is asserted on its own side of rest.
	var farthest := 0.0
	var deepest_inward := 0.0
	var waited := 0.0
	while waited < 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		CardEnvironment.CURRENT = view.game
		farthest = maxf(farthest, camera.position.x - rest)
		deepest_inward = minf(deepest_inward, camera.position.x - rest)
	check(farthest > 1.0,
			"pressing right at the last grid PUSHES the camera past its edge, to the RIGHT "
			+ "(TP-102)",
			"%f px past rest" % farthest)
	check(deepest_inward >= -1.0,
			"...and it never swings the other way first -- an overshoot measured from the "
			+ "picture's centre rather than the pan the camera is actually on drags it a whole "
			+ "grid inward before springing back",
			"%f px inward of rest" % deepest_inward)
	check(pa.pan_grid == 2,
			"...without stepping onto a grid that is not there",
			"pan_grid %d" % pa.pan_grid)
	await _settle_camera(camera)
	check(absf(camera.position.x - rest) <= 1.0,
			"...and the board comes back to its edge: a bounce, not a scroll",
			"rest %f -> %f" % [rest, camera.position.x])
	check(_camera_cut_off_px(main, pa, camera, 2) <= 1.0,
			"the last grid is wholly on screen again once the bounce settles",
			"%f px off screen" % _camera_cut_off_px(main, pa, camera, 2))
	await _tear_down_main(main)

# ==============================================================================
# TP-103 - FIX-GRID-1: the clamp collapses to centre on an axis that already fits.
# ==============================================================================
func run_the_clamp_collapses_to_centre_when_it_fits_test() -> void:
	behavior_section("THE CLAMP COLLAPSES TO CENTRE WHEN EVERYTHING FITS")
	var view := await _stand_up_grids(1)
	var pa := view.play_area
	await _settle_layout(view)
	check(pa.grid_container.get_child_count() == 1,
			"precondition: one grid on the board (TP-103 fixture FIX-GRID-1)",
			"%d panels" % pa.grid_container.get_child_count())
	check(not _board_overflows(pa),
			"precondition: one grid already fits the window, so the pan range is nothing",
			"content %f window %f" % [pa.grid_container.size.x, pa.scroll_container.size.x])

	# ⚠ Measured on the PANEL, not on its cell block: the panel is the whole grid, score gutters
	# included, and it is the panel's edges that "no bare background beside the board" is about.
	# The cell block sits a few px off the panel's own centre because the row-label gutter on the
	# left and the column-label gutter below are not the same width -- that is S24's layout, not a
	# centring error.
	# ⚠ A GLOBAL ORIGIN PLUS A LOCAL SIZE IS NOT A GLOBAL CENTRE once the board is zoomed:
	# `global_position` carries the zoom and `size` never does. Harmless while a one-grid board
	# opened at OVERVIEW_BOARD_ZOOM; it reads 157 px off now that one grid opens focused.
	var panel := pa.grid_container.get_child(0) as Control
	var win := _window_x(pa)
	var window_centre := (win.x + win.y) * 0.5
	var grid_centre := panel.global_position.x + panel.size.x * 0.5 * pa.board_zoom
	check(absf(grid_centre - window_centre) <= 2.0,
			"the board that already fits sits CENTRED, not parked at an edge (TP-103)",
			"grid %f vs window %f" % [grid_centre, window_centre])

	for a : StringName in [&"grid_pan_right", &"grid_pan_left"]:
		pa._unhandled_input(_action(a))
	await _settle_scroll(view)
	var after := pa.grid_container.get_child(0) as Control
	var after_centre := after.global_position.x + after.size.x * 0.5 * pa.board_zoom
	check(absf(after_centre - window_centre) <= 2.0,
			"panning either way leaves it centred: the clamp collapsed the whole range",
			"grid %f vs window %f" % [after_centre, window_centre])
	check(pa.pan_grid == 0,
			"and there was never another grid to step onto",
			"pan_grid %d" % pa.pan_grid)
	await _tear_down(view)

# ==============================================================================
# TP-104 - FIX-FULL-15: ONE scroll container inside the picture. The board pans between grids and
# the SAME container reveals more of a tall stack or an oversized grid; a second scroller nested in
# the board would make two things that scroll the same content.
#
# ⚠ THIS IS A RATCHET, and its whole value is failing the day someone nests another scroller in the
# board. So it PROVES IT CAN SEE scrollers first -- an assertion that counts zero things passes
# trivially. Same shape as TP-93, which proves it can see labels before asserting none is a
# subtotal.
# ==============================================================================

## Every ScrollContainer at or under `root`, in tree order. The instrument TP-104 is built on.
func _scrollers_under(root: Node) -> Array[ScrollContainer]:
	var found : Array[ScrollContainer] = []
	var sc := root as ScrollContainer
	if sc: found.append(sc)
	for child : Node in root.get_children():
		found.append_array(_scrollers_under(child))
	return found

func run_one_scroll_container_on_the_board_test() -> void:
	behavior_section("ONE SCROLL CONTAINER ON THE BOARD")
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)

	# THE INSTRUMENT CHECK. The play area as a whole holds more than one scroller (the board's, and
	# the pinned Entrance's own vertical one, which is NOT on the board), so a finder that returned
	# nothing would be caught here rather than passing the count below by default.
	var everywhere := _scrollers_under(pa)
	check(everywhere.size() >= 2,
			"instrument check: the finder SEES scrollers -- the play area holds more than one (TP-104)",
			"%d found" % everywhere.size())
	check(everywhere.has(pa.scroll_container) and everywhere.has(pa.entrance_v_scroll),
			"...and it finds both the board's scroller and the Entrance's own")

	var on_board := _scrollers_under(pa.scroll_container)
	var names := PackedStringArray()
	for s : ScrollContainer in on_board: names.append(s.name)
	check(on_board.size() == 1,
			"the board has exactly ONE scroll container -- nothing scrolls inside it (TP-104)",
			"%s" % [names])
	check(on_board.size() == 1 and on_board[0] == pa.scroll_container,
			"...and it is the board's own container, the one the pan drives",
			"%s" % [names])
	await _tear_down(view)

# ==============================================================================
# TP-106 - with MORE THAN 3 grids, panning shifts WHICH grids are in frame.
#
# ⚠ `grid_max_count` caps a real run at 3, so this case cannot arise in a show -- which is exactly
# why it is the untested region and why the fixture builds past the cap DIRECTLY (the cap governs
# unlocking, not `Board.add_grid`). At three grids every claim below is vacuous: nothing is ever
# out of frame to shift into it. So the fixture is five, and the test asserts the framing MOVED --
# direction and ordering, never an exact delta, because the scroll content's own origin shifts as
# the region around it resizes.
#
# It drives the REAL input path, so deleting the pan wiring out of `_consume_as_view_action` fails
# it even though every part still exists.
# ==============================================================================

## The grids wholly on screen right now, by index, ascending. "In frame" is `_cut_off_px` at zero.
func _grids_in_frame(pa: PlayArea) -> Array[int]:
	var seen : Array[int] = []
	for gi : int in range(pa.grid_container.get_child_count()):
		if _cut_off_px(pa, gi) <= 1.0: seen.append(gi)
	return seen

## The grids wholly on screen right now against the CAMERA's OWN `visible_rect()`, by index,
## ascending -- the OVERVIEW instrument (`GAP-024`=(b), `GAP-026`=(a)).
func _camera_grids_in_frame(main: Main, pa: PlayArea, camera: Camera2D) -> Array[int]:
	var seen : Array[int] = []
	for gi : int in range(pa.grid_container.get_child_count()):
		if _camera_cut_off_px(main, pa, camera, gi) <= 1.0: seen.append(gi)
	return seen

## The lowest index in frame, or -1 when nothing is. Written out because `Array.min()` is a Variant.
func _lowest(seen: Array[int]) -> int:
	var best := -1
	for gi : int in seen:
		if best < 0 or gi < best: best = gi
	return best

## The highest index in frame, or -1 when nothing is.
func _highest(seen: Array[int]) -> int:
	var best := -1
	for gi : int in seen:
		if gi > best: best = gi
	return best

func run_panning_shifts_which_three_are_in_frame_test() -> void:
	behavior_section("PANNING SHIFTS WHICH GRIDS ARE IN FRAME")
	# `Main`-hosted (`GAP-026`=(a)): this is the OVERVIEW instrument, where "in frame" means inside
	# the CAMERA's own `visible_rect()` (`GAP-024`=(b)).
	var main := await _stand_up_main_grids(5)
	var view := _main_game_view(main)
	var pa := view.play_area
	var camera := _main_camera(main)
	await _settle_layout(view)
	check(pa.grid_container.get_child_count() == 5,
			"precondition: five grids on the board (TP-106)",
			"%d panels" % pa.grid_container.get_child_count())
	check(pa.grid_container.get_child_count() > SettingsManager.settings.grid_max_count,
			"precondition: that is MORE than the cap, which is the case TP-106 is about",
			"cap %d" % SettingsManager.settings.grid_max_count)

	pa.pan_to_grid(1)
	await _settle_scroll(view)
	await _settle_camera(camera)
	var before := _camera_grids_in_frame(main, pa, camera)
	check(not before.is_empty(),
			"instrument check: some grid is in frame at rest, so 'in frame' means something",
			"%s" % [before])
	check(before.size() < 5,
			"precondition: five grids do NOT all fit -- there is something to shift into frame",
			"%s in frame" % [before])
	# ⚠ **THE GRID THE VIEW IS ON, NOT ITS NEIGHBOUR.** This asked for grid 0 while the view sat on
	# grid 1, which held only while grids were spaced 4 px apart and two of them fitted the window
	# at once. The DERIVED isolating buffer puts a real gap between cell blocks, so at this window size the
	# grid in the middle is the only one WHOLLY in frame -- and a neighbour sliced by the window
	# edge is explicitly not a defect (the no-cut-off rule is scoped to the focused grid). What the
	# layout owes, and what the "near edge moves along" check below rests on, is that the grid at
	# rest is itself uncut.
	check(before.has(pa.pan_grid),
			"the grid the view rests on is wholly in frame before panning",
			"%s in frame, resting on %d" % [before, pa.pan_grid])

	for _i : int in [0, 1]:
		pa._unhandled_input(_action(&"grid_pan_right"))
		await _settle_scroll(view)
		await _settle_camera(camera)
	check(pa.pan_grid == 3,
			"two pan-right presses step the view onto grid 3 (TP-106)",
			"pan_grid %d" % pa.pan_grid)
	var after := _camera_grids_in_frame(main, pa, camera)
	check(not after.is_empty(),
			"grids are still in frame after the pan",
			"%s" % [after])
	check(_lowest(after) > _lowest(before),
			"panning right shifts WHICH grids are in frame -- the near edge moves along (TP-106)",
			"%s -> %s" % [before, after])
	check(_highest(after) > _highest(before),
			"...and a grid that was off the far edge is now in frame",
			"%s -> %s" % [before, after])
	check(not after.has(0),
			"...while the grid it started on has left the frame",
			"%s" % [after])

	for _i : int in [0, 1]:
		pa._unhandled_input(_action(&"grid_pan_left"))
		await _settle_scroll(view)
		await _settle_camera(camera)
	var back := _camera_grids_in_frame(main, pa, camera)
	check(pa.pan_grid == 1,
			"panning back left returns to the grid it started on",
			"pan_grid %d" % pa.pan_grid)
	# ⚠ Direction and ordering, never set identity: whether the grid at the far edge counts as
	# wholly on screen turns on a pixel or two of settle, so the near edge is the honest instrument.
	check(_lowest(back) == _lowest(before),
			"...and the frame is back where it started: the window shifted, it did not resize",
			"%s vs %s" % [back, before])
	check(_highest(back) < _highest(after),
			"...having given up the far grid it had panned onto",
			"%s vs %s" % [back, after])
	await _tear_down_main(main)

# ==============================================================================
# S29 — MOVING THE SELECTION. Arrows across grids, the overview's grid cursor, and the one-finger
# swipe.
#
# ⚠ THE TOUCH TESTS RUN LAST, AFTER EVERY MOUSE TEST ABOVE: a touch leaves no HOVER behind, and
# the mouse selection path those tests drive needs one.
# ==============================================================================

## A real key press, so these checks assert the `ui_*` BINDINGS as well as the reader.
func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

## The board coordinate a control names, printed. Written out because `BoardCoord` has no
## `_to_string` and a failure message that says "moved to the wrong cell" must say WHICH.
func _where(pa: PlayArea, c: Control) -> String:
	if not is_instance_valid(c): return "<none>"
	var coord := pa._coord_of_control(c)
	return "grid %d (%d,%d)" % [coord.grid, coord.x, coord.y]

## True when `c` names exactly this cell.
func _is_cell(pa: PlayArea, c: Control, gi: int, x: int, y: int) -> bool:
	if not is_instance_valid(c): return false
	return pa._coord_of_control(c).equals(BoardCoord.new(gi, x, y, 0))

# ==============================================================================
# TP-107 — FIX-GRID-3: arrow keys cross a grid boundary, and the view follows.
#
# ⚠ DRIVEN THROUGH THE CELL CONTROL'S OWN `gui_input`, which is where the board can first hear an
# arrow — the viewport's focus-neighbour search consumes arrows in the GUI pass, so a reader in
# `_unhandled_input` would never run. Cutting the connect in `create_card_control` therefore fails
# this test even though every part still exists.
#
# ⚠ "THE CAMERA FOLLOWS" IS NOT A CAMERA: there is none in this phase. What follows is the board's
# own scroll, so the observable asserted here is which grid the view is centred on and which grids
# are in frame — never a camera transform.
# ==============================================================================
func run_arrows_cross_a_grid_boundary_test() -> void:
	behavior_section("ARROW KEYS CROSS A GRID BOUNDARY AND THE VIEW FOLLOWS")
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)
	pa.focus_grid(0)
	await _settle_scroll(view)
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED and pa.pan_grid == 0,
			"precondition: focused on grid 0 (TP-107 fixture FIX-GRID-3)",
			"mode %d pan %d" % [pa.view_mode, pa.pan_grid])

	# WITHIN a grid first: the same key, one column along, nothing about the view changes.
	var start := pa._cell_focus_control(BoardCoord.new(0, 0, 2, 0))
	check(start != null and _is_cell(pa, start, 0, 0, 2),
			"instrument check: the selection starts on a real cell of grid 0 (TP-107)",
			_where(pa, start))
	start.grab_focus()
	start.gui_input.emit(_key(KEY_RIGHT))
	check(_is_cell(pa, pa.focused_control, 0, 1, 2),
			"a right press inside a grid moves ONE column along it",
			_where(pa, pa.focused_control))
	check(pa.pan_grid == 0,
			"...and the view has no reason to move", "pan_grid %d" % pa.pan_grid)

	# THE BOUNDARY. Grid 0's rightmost column: one more press has to land in grid 1.
	var edge := pa._cell_focus_control(BoardCoord.new(0, 4, 2, 0))
	check(edge != null and _is_cell(pa, edge, 0, 4, 2),
			"precondition: the selection is on grid 0's RIGHTMOST column",
			_where(pa, edge))
	edge.grab_focus()
	edge.gui_input.emit(_key(KEY_RIGHT))
	check(_is_cell(pa, pa.focused_control, 1, 0, 2),
			"stepping off a grid's edge CROSSES into the next grid's first column (TP-107)",
			_where(pa, pa.focused_control))
	check(pa.focused_grid == 1 and pa.pan_grid == 1,
			"...and the view follows the selection onto that grid",
			"focused %d pan %d" % [pa.focused_grid, pa.pan_grid])
	await _settle_scroll(view)
	check(_grids_in_frame(pa).has(1),
			"...so the grid the selection crossed into is actually in frame (TP-107)",
			"%s in frame" % [_grids_in_frame(pa)])

	# Back the other way, to prove the crossing is not a one-directional accident.
	pa.focused_control.gui_input.emit(_key(KEY_LEFT))
	check(_is_cell(pa, pa.focused_control, 0, 4, 2),
			"a left press at grid 1's first column crosses back into grid 0's last",
			_where(pa, pa.focused_control))
	check(pa.pan_grid == 0,
			"...and the view comes back with it", "pan_grid %d" % pa.pan_grid)
	await _settle_scroll(view)

	# THE OUTER EDGE OF THE BOARD. There is no grid past the last one, so nothing moves.
	var far := pa._cell_focus_control(BoardCoord.new(2, 4, 2, 0))
	far.grab_focus()
	far.gui_input.emit(_key(KEY_RIGHT))
	check(_is_cell(pa, pa.focused_control, 2, 4, 2),
			"at the board's outer edge the selection stays put — it does not wrap (TP-107)",
			_where(pa, pa.focused_control))

	# The vertical axis is the same lattice: row 0 is the TOP row, so Down increases y.
	var mid := pa._cell_focus_control(BoardCoord.new(1, 2, 2, 0))
	mid.grab_focus()
	mid.gui_input.emit(_key(KEY_DOWN))
	check(_is_cell(pa, pa.focused_control, 1, 2, 3),
			"a down press moves one row down the same grid",
			_where(pa, pa.focused_control))
	await _settle_scroll(view)
	await _tear_down(view)

# ==============================================================================
# TP-108 — FIX-GRID-3: in the overview the arrows select a GRID, and Enter focuses it.
#
# ⚠ THE DISCRIMINATING CASE IS THAT THE SAME KEY DOES TWO DIFFERENT THINGS. A selection model that
# was simply "the same cells at a smaller scale" would pass a test that only checked the overview,
# so both modes are driven here with the same press.
# ==============================================================================
func run_overview_arrows_select_a_grid_test() -> void:
	behavior_section("IN THE OVERVIEW THE ARROWS SELECT A GRID")
	# ⚠ FIVE GRIDS, NOT THREE: three fit the window, so the layout centres them and the centring
	# claim below is true whatever the arrows do.
	var view := await _stand_up_grids(5)
	var pa := view.play_area
	await _settle_layout(view)
	pa.open_zoomed_out()
	pa.selected_grid = 0
	pa.pan_to_grid(0)
	await _settle_scroll(view)
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"precondition: the board is in the all-grids view (TP-108)", "mode %d" % pa.view_mode)

	pa._unhandled_input(_key(KEY_RIGHT))
	check(pa.selected_grid == 1,
			"a right press in the overview selects the NEXT GRID, not the next cell (TP-108)",
			"selected_grid %d" % pa.selected_grid)
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"...selecting is not focusing: the board is still in the overview",
			"mode %d" % pa.view_mode)
	check(pa.pan_grid == 1,
			"...and the view moves onto the selected grid",
			"pan_grid %d" % pa.pan_grid)
	await _settle_scroll(view)
	check(_grids_in_frame(pa).has(1),
			"...so the selected grid is in frame", "%s" % [_grids_in_frame(pa)])

	pa._unhandled_input(_action(&"ui_accept"))
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"Enter focuses the selected grid (TP-108)", "mode %d" % pa.view_mode)
	check(pa.focused_grid == 1,
			"...the grid the arrows selected, not the one it started on",
			"focused_grid %d" % pa.focused_grid)
	await _settle_scroll(view)

	# THE OTHER GRANULARITY, from the same key. Now that a grid is focused, right moves a CELL.
	var cell := pa._cell_focus_control(BoardCoord.new(1, 0, 2, 0))
	cell.grab_focus()
	var was_focused_grid := pa.focused_grid
	cell.gui_input.emit(_key(KEY_RIGHT))
	check(_is_cell(pa, pa.focused_control, 1, 1, 2),
			"the SAME press, once focused, moves a CELL instead of a grid (TP-108)",
			_where(pa, pa.focused_control))
	check(pa.focused_grid == was_focused_grid,
			"...and it selects no new grid", "focused_grid %d" % pa.focused_grid)

	# Back in the overview, the leftmost grid has nothing to its left.
	pa.open_zoomed_out()
	pa.selected_grid = 0
	pa._unhandled_input(_key(KEY_LEFT))
	check(pa.selected_grid == 0,
			"at the first grid, left selects nothing that is not there",
			"selected_grid %d" % pa.selected_grid)
	await _settle_scroll(view)

	# ⚠ IN FRAME IS NOT CENTRED, AND THE ARROW ALSO MOVES THE BOARD FOCUS. The scroll container's
	# `follow_focus` answers a focus change by KILLING the in-flight pan and parking the control
	# `follow_focus_margin` inside the window edge — still "in frame", not centred. So the pan has
	# to be the last writer, and the claim is that the arrow lands the board exactly where an
	# explicit pan to that grid does.
	# ⚠ THE STEP MUST LAND ON A CELL THAT IS CURRENTLY OUTSIDE THAT MARGIN BAND, or follow-focus
	# has nothing to correct and leaves the pan alone whichever order they run in — measured: a
	# rightward step onto an already-visible column passes with the orders swapped. Stepping LEFT
	# from the middle grid of five lands on a column off the left edge.
	# ⚠ MIDDLE GRID, never an outer one: centring an edge grid hits the scroll container's own
	# clamp, which puts a stolen pan and an honest one in the same place.
	pa.selected_grid = 3
	pa.pan_to_grid(3)
	await _settle_scroll(view)
	check(_board_overflows(pa),
			"precondition: the board overflows, so centring is the scroll's job (TP-108)")
	pa._unhandled_input(_key(KEY_LEFT))
	await _settle_scroll(view)
	check(pa._grid_index_of(pa.get_viewport().gui_get_focus_owner() as Control) == 2,
			"instrument check: the arrow moved the board FOCUS onto the selected grid, so the "
			+ "scroll container's follow-focus really did run (TP-108)",
			"focus on grid %d" % pa._grid_index_of(pa.get_viewport().gui_get_focus_owner() as Control))
	var arrowed := _centre_offset(pa, 2)
	pa.pan_to_grid(2)
	await _settle_scroll(view)
	check(absf(arrowed - _centre_offset(pa, 2)) <= 1.0,
			"the arrow leaves the grid it selected CENTRED, exactly where an explicit pan lands — "
			+ "follow-focus did not steal the pan (TP-108)",
			"arrow %.1f px off centre vs pan %.1f" % [arrowed, _centre_offset(pa, 2)])
	await _tear_down(view)

# ==============================================================================
# TP-109 — A SWIPE FIRES ONCE.
#
# ⚠ WITH `emulate_mouse_from_touch` AT ITS DEFAULT, ONE FINGER ARRIVES TWICE: as an
# `InputEventScreenDrag` and as a synthesised `InputEventMouseMotion`. A test that delivered only
# the screen drag would pass on a reader that doubles, because the partner never arrives. So this
# delivers BOTH FORMS, interleaved, the way the engine does.
#
# ⚠ AND IT DRIVES THEM THROUGH `Viewport.push_input`, NEVER THE HANDLER DIRECTLY. Calling the
# reader proves the reader and says nothing about whether a finger can REACH it: measured, it could
# not — touch goes through the GUI pass and the board's scroll container marked it handled long
# before unhandled input ran, so the whole swipe was dead in the product while these were green.
#
# ⚠ AND IT NEEDS FIVE GRIDS. Starting on grid 1 of three, a doubling reader's second step runs off
# the end and bounces, leaving `pan_grid` at the same value a correct reader produces — the fixture
# would hide the very defect the test exists for. From grid 0 of five, one step is 1 and two is 2.
# ==============================================================================

## A finger going down or coming up. `device` 0: a REAL touch, not the engine's own synthesis.
func _touch(at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.position = at
	e.pressed = pressed
	e.device = 0
	return e

## A finger moving. `device` -1 is the engine's marker for an emulated event.
func _drag(at: Vector2, device: int) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.position = at
	e.device = device
	return e

## The mouse motion the engine synthesises alongside every one of those drags.
func _emulated_motion(at: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.relative = relative
	return e

## A point on BARE BOARD — inside the scrolling window, over no card control. The board is
## bottom-aligned, so its top strip is empty; the caller checks this is really bare.
func _bare_point(pa: PlayArea) -> Vector2:
	return pa.scroll_container.global_position + Vector2(6.0, 6.0)

## One finger swiping `by` pixels horizontally from `from`, delivered in `steps` moves — each of
## them in BOTH the forms the engine produces. What it proves is read off the board afterwards.
func _swipe(pa: PlayArea, from: Vector2, by: float, steps: int) -> void:
	var vp := pa.get_viewport()
	vp.push_input(_touch(from, true))
	var at := from
	for i : int in steps:
		var next := from + Vector2(by * float(i + 1) / float(steps), 0.0)
		vp.push_input(_drag(next, 0))
		vp.push_input(_emulated_motion(next, next - at))
		at = next
	vp.push_input(_touch(at, false))

func run_a_swipe_fires_once_test() -> void:
	behavior_section("A SWIPE FIRES ONCE")
	# ⚠ MOUNTED INSIDE THE PICTURE'S OWN SUBVIEWPORT, sized `game_picture_design_size` -- same reason
	# TP-140/TP-141 need it: "in frame" is measured against the board's real scroll window, which the
	# suite's own default 1152x648 root window is narrower than.
	var picture_vp := SubViewport.new()
	picture_vp.size = PlayArea.game_picture_design_size(SettingsManager.settings)
	add_child(picture_vp)
	var view := await _stand_up_grids(5, picture_vp)
	var pa := view.play_area
	await _settle_layout(view)
	pa.pan_to_grid(0)
	await _settle_scroll(view)
	var threshold := pa._swipe_threshold_px()
	check(threshold > 0.0,
			"instrument check: the swipe threshold is a real distance in px (TP-109)",
			"%f px" % threshold)
	# ⚠ A LIVE KNOB, NOT A CONSTANT: a threshold that ignores the setting entirely would still be
	# "a real distance in px". Doubled and halved about the default, the px must follow.
	var knob := SettingsManager.settings.grid_swipe_threshold_mm
	SettingsManager.settings.grid_swipe_threshold_mm = knob * 2.0
	var wider := pa._swipe_threshold_px()
	SettingsManager.settings.grid_swipe_threshold_mm = knob
	check(wider > threshold,
			"the millimetre knob really drives the threshold — it is not a hard-coded px (TP-109)",
			"%f mm -> %f px, %f mm -> %f px" % [knob, threshold, knob * 2.0, wider])
	var from := _bare_point(pa)
	check(pa._card_control_at(from) == null,
			"instrument check: the swipe starts on BARE BOARD, over no card",
			"%s" % [from])

	# A leftward swipe drags the board's content left, which brings the NEXT grid into view.
	_swipe(pa, from, -threshold * 4.0, 6)
	await _settle_scroll(view)
	check(pa.pan_grid == 1,
			"one swipe pans exactly ONE grid — the emulated mouse partner did not double it (TP-109)",
			"pan_grid %d" % pa.pan_grid)
	check(_grids_in_frame(pa).has(1),
			"...and that grid is in frame", "%s" % [_grids_in_frame(pa)])

	# The mouse form ALONE must move nothing: it is the partner, never the signal.
	# ⚠ RE-ANCHORED AT GRID 0 FIRST, and before every negative check below. Left where the swipe
	# above put it, a board that has run out of grids to step onto cannot move whatever the reader
	# does — so these checks would pass on a reader that reads every form, proving nothing.
	pa.pan_to_grid(0)
	await _settle_scroll(view)
	var before := pa.pan_grid
	check(before == 0 and pa.grid_container.get_child_count() > 1,
			"instrument check: the board is re-anchored with somewhere left to pan (TP-109)",
			"pan_grid %d of %d" % [before, pa.grid_container.get_child_count()])
	var vp := pa.get_viewport()
	vp.push_input(_touch(from, true))
	for i : int in 6:
		vp.push_input(_emulated_motion(from + Vector2(-threshold * float(i + 1), 0.0),
				Vector2(-threshold, 0.0)))
	vp.push_input(_touch(from, false))
	await _settle_scroll(view)
	check(pa.pan_grid == before,
			"the emulated mouse motion on its own pans NOTHING (TP-109)",
			"pan_grid %d -> %d" % [before, pa.pan_grid])

	# An emulated SCREEN DRAG — the form a real mouse produces — is filtered by device -1, so a
	# mouse drag across the board never pans it.
	pa.pan_to_grid(0)
	await _settle_scroll(view)
	vp.push_input(_touch(from, true))
	for i : int in 6:
		vp.push_input(_drag(from + Vector2(-threshold * float(i + 1), 0.0), -1))
	vp.push_input(_touch(from, false))
	await _settle_scroll(view)
	check(pa.pan_grid == before,
			"a drag marked device -1 is the engine's own synthesis and is ignored (TP-109)",
			"pan_grid %d" % pa.pan_grid)

	# A finger that never travels far enough is a tap, not a swipe.
	pa.pan_to_grid(0)
	await _settle_scroll(view)
	_swipe(pa, from, -threshold * 0.4, 4)
	await _settle_scroll(view)
	check(pa.pan_grid == before,
			"a drag shorter than the threshold is a tap and pans nothing",
			"pan_grid %d" % pa.pan_grid)

	# And the other way, one grid back.
	pa.pan_to_grid(1)
	await _settle_scroll(view)
	_swipe(pa, from, threshold * 4.0, 6)
	await _settle_scroll(view)
	check(pa.pan_grid == 0,
			"swiping the other way pans one grid back, once",
			"pan_grid %d" % pa.pan_grid)
	await _tear_down(view)
	picture_vp.queue_free()

# ==============================================================================
# TP-110 — FIX-GRID-1: a drag that STARTS ON A CARD places; one starting on empty board pans.
#
# The two are the same one-finger drag, so the discrimination is the whole behaviour: it is read
# from where the finger WENT DOWN, exactly as the wall reads a press on a picture as "enter" and a
# press on bare wall as "arm the pan".
# ==============================================================================
func run_a_drag_on_a_card_places_and_on_the_board_pans_test() -> void:
	behavior_section("A DRAG ON A CARD PLACES, ON EMPTY BOARD IT PANS")
	var view := await _stand_up_grids(1)
	var pa := view.play_area
	await _settle_layout(view)
	pa.focus_grid(0)
	await _settle_scroll(view)
	var threshold := pa._swipe_threshold_px()
	var control := _cell_control(pa, 0)
	check(control in pa.ui_data,
			"precondition: a bound board control to start the drag on (TP-110 fixture FIX-GRID-1)")
	var on_card := control.get_global_rect().get_center()
	check(pa._card_control_at(on_card) == control,
			"instrument check: that point really is on the card control",
			"%s" % [on_card])

	# STARTING ON A CARD: never a pan, and the event is left for the placement path.
	var vp := pa.get_viewport()
	vp.push_input(_touch(on_card, true))
	check(not pa._swipe_armed,
			"a finger going down on a card does NOT arm a pan (TP-110)")
	vp.push_input(_drag(on_card + Vector2(-threshold * 4.0, 0.0), 0))
	check(not pa._swipe_fired,
			"...so dragging from it is not swallowed as a swipe — it stays a placement, and no pan "
			+ "fired (TP-110)")
	vp.push_input(_touch(on_card, false))

	# ...and the placement itself still works, through the real press path.
	var selected : Array[CardData] = []
	pa.data_selected.connect(func(d: CardData) -> void: selected.append(d))
	_click(pa, control)
	check(selected.size() == 1,
			"a press on that same card still reaches the placement path (TP-110)",
			"%d selections" % selected.size())

	# STARTING ON EMPTY BOARD: armed, and the swipe is the board's.
	var bare := _bare_point(pa)
	check(pa._card_control_at(bare) == null,
			"instrument check: the second start point is bare board",
			"%s" % [bare])
	vp.push_input(_touch(bare, true))
	check(pa._swipe_armed,
			"a finger going down on empty board ARMS the pan (TP-110)")
	vp.push_input(_drag(bare + Vector2(-threshold * 4.0, 0.0), 0))
	check(pa._swipe_fired,
			"...and dragging from it IS read as a swipe by the REAL route, not offered to "
			+ "placement (TP-110)")
	vp.push_input(_touch(bare, false))
	check(not pa._swipe_armed,
			"lifting the finger disarms, so the next press decides again")
	await _settle_scroll(view)
	await _tear_down(view)

# ==============================================================================
# TP-111 — FIX-GRID-3: removing the grid the view is focused on refocuses the NEAREST survivor,
# and the LEFT one when two are equally near.
#
# The middle grid of three is removed, so both its neighbours survive and both are exactly one
# grid away: the tie the left-preference exists to break. ⚠ The check is on the surviving grid's
# IDENTITY, not its index — after the removal the RIGHT neighbour occupies the index a clamp would
# leave the focus on, so an index-only claim cannot tell the preference from a clamp.
#
# It removes the grid through `Board.remove_grid`, the real removal the grid creator's
# `on_unspotlight` calls, and never touches the refocus itself.
# ==============================================================================
func run_removing_the_focused_grid_refocuses_left_test() -> void:
	behavior_section("REMOVING THE FOCUSED GRID REFOCUSES THE NEAREST SURVIVOR")
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)
	var left : GridData = view.game.state.grids[0]
	var right : GridData = view.game.state.grids[2]
	pa.focus_grid(1)
	await _settle_scroll(view)
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED and pa.focused_grid == 1,
			"precondition: focused on the MIDDLE of three grids (TP-111 fixture FIX-GRID-3)",
			"mode %d grid %d" % [pa.view_mode, pa.focused_grid])
	var banked := view.game.state.live_total()

	Board.remove_grid(view.game.state, 1)
	pa.flush_rebuild()
	await _settle_layout(view)
	await _settle_scroll(view)

	check(view.game.state.grids.size() == 2,
			"precondition: the focused grid is gone and both neighbours survive (TP-111)",
			"%d grids" % view.game.state.grids.size())
	check(view.game.state.grids[0] == left and view.game.state.grids[1] == right,
			"instrument check: the two survivors were EQUALLY near the removed grid — one either "
			+ "side — so this is the tie the left-preference breaks (TP-111)")
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"the view is still focused on a grid, not left on nothing (TP-111)",
			"mode %d" % pa.view_mode)
	check(pa.focused_grid >= 0 and pa.focused_grid < view.game.state.grids.size(),
			"the focused index points at a grid that EXISTS (TP-111)",
			"focused_grid %d of %d" % [pa.focused_grid, view.game.state.grids.size()])
	check(view.game.state.grids[pa.focused_grid] == left,
			"...and it is the LEFT survivor, not the right one that slid into its index (TP-111)",
			"focused_grid %d" % pa.focused_grid)
	check(view.game.state.live_total() == banked,
			"removing a grid does not lose the accumulated score (TP-111)",
			"%d vs %d" % [view.game.state.live_total(), banked])
	await _tear_down(view)

# ==============================================================================
# TP-111 OVERVIEW CASE — losing the grid the OVERVIEW is on leaves the view and the arrow cursor
# naming the SAME grid: the nearest survivor, preferring the one to the left (owner ruling).
#
# ⚠ THE OVERVIEW IS THE DISCRIMINATING MODE. Focused, the refocus re-drives the pan and hides any
# disagreement between the two indices; in the overview nothing does, so the board can re-centre on
# the RIGHT survivor while the cursor sits on the LEFT one — and the next arrow then jumps two.
# ⚠ CHECKED ON THE SURVIVING GRID'S IDENTITY, never its index: the right neighbour slides into the
# index the removed grid had, so an index-only claim cannot tell a survivor from a leftover number.
# ==============================================================================
func run_the_overview_view_and_cursor_agree_after_a_removal_test() -> void:
	behavior_section("AFTER A REMOVAL THE OVERVIEW AND ITS CURSOR AGREE")
	var view := await _stand_up_grids(5)
	var pa := view.play_area
	await _settle_layout(view)
	pa.open_zoomed_out()
	pa.selected_grid = 2
	pa.pan_to_grid(2)
	await _settle_scroll(view)
	var left : GridData = view.game.state.grids[1]
	var right : GridData = view.game.state.grids[3]
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW and pa.pan_grid == 2
			and pa.selected_grid == 2,
			"precondition: the overview is on grid 2 of five, cursor and view together (TP-111)",
			"mode %d pan %d cursor %d" % [pa.view_mode, pa.pan_grid, pa.selected_grid])

	Board.remove_grid(view.game.state, 2)
	pa.flush_rebuild()
	await _settle_layout(view)
	await _settle_scroll(view)

	check(view.game.state.grids[1] == left and view.game.state.grids[2] == right,
			"instrument check: both neighbours survived, equally near — the tie the left-preference"
			+ " breaks (TP-111)")
	check(pa.pan_grid == pa.selected_grid,
			"the view and the arrow cursor still name the SAME grid (TP-111)",
			"pan %d cursor %d" % [pa.pan_grid, pa.selected_grid])
	check(view.game.state.grids[pa.pan_grid] == left,
			"...the nearest survivor, the LEFT one, not the right one that slid into its index"
			+ " (TP-111)",
			"pan_grid %d" % pa.pan_grid)
	check(_centre_offset(pa, pa.pan_grid) <= _centre_offset(pa, pa.pan_grid + 1),
			"...and the board re-centred on THAT grid, not on its right-hand neighbour (TP-111)",
			"%.1f px vs %.1f" % [_centre_offset(pa, pa.pan_grid),
					_centre_offset(pa, pa.pan_grid + 1)])

	# ONE ARROW, ONE GRID: a cursor and a view that disagree make the next press look like a jump.
	var before := pa.pan_grid
	pa._unhandled_input(_key(KEY_RIGHT))
	await _settle_scroll(view)
	check(pa.pan_grid == before + 1,
			"the next arrow moves the view exactly ONE grid, not two (TP-111)",
			"pan_grid %d -> %d" % [before, pa.pan_grid])
	await _tear_down(view)

## How far grid `gi`'s cell block sits from the middle of the board's window, in pixels.
func _centre_offset(pa: PlayArea, gi: int) -> float:
	var cells := pa._cells_root(pa.grid_container.get_child(gi) as Control)
	var win := _window_x(pa)
	return absf(cells.global_position.x + cells.size.x * 0.5 - (win.x + win.y) * 0.5)

# ==============================================================================
# TP-112 — the surviving grids re-centre, ANIMATED, on a removal the view was NOT focused on.
#
# ⚠ THAT IS THE DISCRIMINATING CASE: the re-centre is unconditional while the refocus is not, so a
# test that only ever removes the focused grid cannot tell a correct board from one that re-centres
# solely on the refocus path.
#
# ⚠ FIVE GRIDS, NOT THREE, AND THE VIEW ON THE MIDDLE ONE. Two weaker fixtures were measured and
# rejected: with three grids a removal leaves a board that FITS its window, so the layout centres
# it and the scroll never runs; and with the view near an edge the scroll container's own clamp
# drags the board to the same place a re-centre would, which passes with the wiring cut. The middle
# grid of five has slack on both sides, so only a re-centre can put it back in the middle.
#
# ⚠ A still frame is the wrong instrument for a move with a duration: the offset is sampled while
# the pan is still running and again at rest, and the settle must take longer than a single frame.
# ==============================================================================
func run_the_board_recentres_after_any_removal_test() -> void:
	behavior_section("THE SURVIVING GRIDS RE-CENTRE AFTER ANY REMOVAL")
	var view := await _stand_up_grids(5)
	var pa := view.play_area
	await _settle_layout(view)
	var kept : GridData = view.game.state.grids[2]
	pa.focus_grid(2)
	await _settle_scroll(view)
	check(_board_overflows(pa),
			"precondition: the board overflows its window, so centring is the scroll's job (TP-112)")
	check(pa.focused_grid == 2,
			"precondition: focused on a grid that is NOT the one about to be removed (TP-112)",
			"focused_grid %d" % pa.focused_grid)

	# ⚠ The clock starts at the removal, not at the pan: what is being timed is how long the board
	# takes to come to rest after losing a grid, and a snap would be done inside a few frames.
	var started := Time.get_ticks_msec()
	Board.remove_grid(view.game.state, 0)
	pa.flush_rebuild()
	await _settle_layout(view)
	# Sampled with the layout at rest and the board still travelling: the re-centre waits for the
	# panels to stop before it aims, so this is the board on its way, not before it started.
	var moving := _centre_offset(pa, view.game.state.grids.find(kept))
	await _settle_scroll(view)
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	var kept_index := view.game.state.grids.find(kept)
	var at_rest := _centre_offset(pa, kept_index)
	var grid_px : float = pa._cells_root(pa.grid_container.get_child(0) as Control).size.x
	# ⚠ THE REFERENCE IS AN EXPLICIT PAN TO THE SAME GRID, NOT THE WINDOW'S MIDDLE: where a grid
	# comes to rest is the layout's business — a board whose content is wider than its grid block
	# rests off the window's own centre — so the claim is that the removal put the board where the
	# player's own pan key would have put it, and that identity the layout does owe.
	pa.pan_to_grid(kept_index)
	await _settle_scroll(view)
	var reference := _centre_offset(pa, kept_index)

	check(view.game.state.grids.size() == 4 and _board_overflows(pa),
			"precondition: four grids survive and the board still overflows (TP-112)",
			"%d grids" % view.game.state.grids.size())
	check(view.game.state.grids[pa.focused_grid] == kept,
			"the view still follows the SAME grid after one to its left went (TP-112)",
			"focused_grid %d" % pa.focused_grid)
	check(absf(at_rest - reference) < grid_px * 0.05,
			"the survivors re-centre on a removal the view was not focused on — the board lands "
			+ "where an explicit pan to that same grid lands (TP-112)",
			"%.1f px off centre vs %.1f px for an explicit pan, grid %.1f px"
			% [at_rest, reference, grid_px])
	check(_grids_in_frame(pa).has(kept_index),
			"...with that grid wholly in frame (TP-112)",
			"%s in frame, wanted %d" % [_grids_in_frame(pa), kept_index])
	check(moving > at_rest + 1.0,
			"...and it TRAVELLED there — mid-move it is further off centre than at rest (TP-112)",
			"%.1f px mid-move vs %.1f px at rest" % [moving, at_rest])
	check(elapsed > SettingsManager.settings.grid_pan_duration * 0.5,
			"...over the grid pan clock — the board is still moving long after the layout that "
			+ "lost the grid has come to rest (TP-112)",
			"%.2f s to rest, pan clock %.2f s"
			% [elapsed, SettingsManager.settings.grid_pan_duration])
	await _tear_down(view)

# ==============================================================================
# TP-113 - the game picture IS one grid position: wide enough for exactly `grid_max_count` grids
# plus the buffers and margins between them, at the height the zoomed-out view needs. The size is
# read through `Wall.load_layout()` - the one seam every real wall build goes through - so a
# picture that stopped being sized fails here.
#
# The picture and the position are the SAME rect (owner ruling, superseding the earlier picture of
# `grid_max_count` positions each holding `grid_max_count` grids): the camera fills the picture
# whole at rest, which is what lets zooming out show every grid at once.
# ==============================================================================
func run_the_game_picture_fits_exactly_three_grids_test() -> void:
	behavior_section("THE GAME PICTURE FITS EXACTLY THREE GRIDS")
	var st := SettingsManager.settings
	var entry := _game_entry()
	check(entry != null, "the layout registers a game picture at all")
	if not entry: return
	var design := entry.design_size
	check(design != PictureEntry.new().design_size,
			"the game picture is SIZED by the board's rule, not left at the entry default every "
			+ "other picture inherits (TP-113)",
			"design %s, entry default %s" % [design, PictureEntry.new().design_size])
	var block := PlayArea.grid_block_size_px(st, GridData.new())
	var span_3 := _grid_span(block.x, 3)
	var span_4 := _grid_span(block.x, 4)
	check(st.grid_max_count == 3,
			"precondition: the shipped cap is three grids (TP-113)",
			"grid_max_count %d" % st.grid_max_count)
	var position_size := PlayArea.grid_position_size_px(st)
	check(absf(float(design.x) - position_size.x) <= 1.0,
			"the game picture IS the one grid position -- the whole picture, not `grid_max_count` "
			+ "of them (TP-113)",
			"design %d px, position %.1f px" % [design.x, position_size.x])
	check(position_size.x >= span_3,
			"one grid position is wide enough for three grid blocks and the two buffers between "
			+ "them (TP-113)",
			"position %.1f px, three grids span %.1f px" % [position_size.x, span_3])
	# ⚠ **"EXACTLY THREE" WAS RELAXED TO "HOLDS THREE" BY OWNER RULING (`GAP-039`=(b)).** Three
	# contracts were mutually unsatisfiable -- isolation, exactly-three, and no clipping -- and the
	# owner chose to keep isolation and the framing and give up the upper bound. The picture is now
	# the width that genuinely isolates a focused grid's neighbours, and that width happens to have
	# room for a fourth block; nothing places one, because `grid_max_count` is the cap.
	check(position_size.x >= span_3,
			"...and holds three with room to spare rather than being cut to exactly three -- the "
			+ "upper bound was what isolation cost (TP-113, GAP-039=(b))",
			"position %.1f px, four grids span %.1f px" % [position_size.x, span_4])
	var buffer := PlayArea.isolating_grid_buffer_px(st)
	check(absf(position_size.x - span_3 - 2.0 * buffer) <= 1.0,
			"...with the leftover width being exactly the isolating buffer again on each side "
			+ "(TP-113)",
			"leftover %.1f px, buffer %.1f px" % [position_size.x - span_3, buffer])
	# The height rule: the natural board height or the aspect minimum of ONE GRID POSITION,
	# whichever is LARGER. Measured on the position, never the whole picture: a picture at the
	# window's own aspect is framed whole at rest and leaves the camera nothing to step across.
	var ref_w : float = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var ref_h : float = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	var aspect_minimum := position_size.x * ref_h / ref_w
	check(float(design.y) >= block.y - 1.0,
			"the picture is at least the board's own natural height (TP-113)",
			"design %d px, natural %.1f px" % [design.y, block.y])
	check(float(design.y) >= aspect_minimum - 1.0,
			"...and at least the height one grid position's window aspect needs, so the zoomed-out "
			+ "view of that position is entirely picture (TP-113)",
			"design %d px, aspect minimum %.1f px" % [design.y, aspect_minimum])
	check(float(design.y) <= maxf(block.y, aspect_minimum) + 1.0,
			"...and no taller than the LARGER of the two - whichever is larger, not their sum "
			+ "(TP-113)",
			"design %d px, larger of %.1f / %.1f" % [design.y, block.y, aspect_minimum])
	# The camera's step, in the picture's own units: what `resting_state` frames against what
	# exists. This is the property `H22` names and the reason the picture was widened at all.
	var window_size := Vector2(ref_w, ref_h)
	var rest_zoom := WallPicture.focused_scale(Vector2(design), window_size,
			st.wall_overfill_margin)
	var visible_w := window_size.x / maxf(rest_zoom, 0.0001)
	check(float(design.x) - visible_w < block.x,
			"at its resting pose the camera sees the WHOLE picture within a grid block's width -- "
			+ "every grid in frame at once, not stepping onto one at a time (TP-113)",
			"sees %.1f px of %d px, slack %.1f px, block %.1f px" % [visible_w, design.x,
			float(design.x) - visible_w, block.x])

# ==============================================================================
# TP-114 - FIX-FULL-15: the focused game picture's render target never exceeds
# `game_picture_max_render_px`.
#
# WARNING: `SubViewport.size` LIES WHEN IT IS OVERSIZED - the framebuffer is destroyed and the
# size set to 0 internally while the property keeps reporting the number that broke it. So no
# assertion here treats a read-back as proof the GPU accepted it. What is asserted instead is
# what the code WROTE and the clamp it passed through: the pure clamp, that the tallest legal
# board does not grow the picture, and - with an entry deliberately past the cap - that the real
# `focus()` path writes the clamped size AND engages the canvas override. A regression that
# deleted the clamp would write the oversized number, and the last group catches that whether or
# not the property tells the truth afterwards.
# ==============================================================================
func run_the_render_target_never_exceeds_the_clamp_test() -> void:
	behavior_section("THE RENDER TARGET NEVER EXCEEDS THE CLAMP")
	var st := SettingsManager.settings
	var cap := st.game_picture_max_render_px
	var empty_design := _game_entry().design_size

	# FIX-FULL-15 standing in the real view: grid 0, all 25 cells at height 15.
	var view := await _stand_up_grids(1)
	var pa := view.play_area
	view.game.state.grids.assign(TestGridFixtures.build_fix_full_15().grids)
	# ⚠ Assigning the state directly fires no mutation broadcast, so the rebuild has to be ASKED
	# for -- `flush_rebuild()` alone only services a rebuild something else queued.
	pa.queue_rebuild()
	pa.flush_rebuild()
	await _settle_layout(view)
	var board_h := pa.grid_container.size.y
	check(board_h > float(empty_design.y),
			"precondition: FIX-FULL-15 makes the board TALLER than the whole picture (TP-114)",
			"board %.0f px, picture %d px" % [board_h, empty_design.y])
	check(_game_entry().design_size == empty_design,
			"the tallest legal board does not grow the picture - the render target is a fixed "
			+ "authored size and the scroll container carries the height (TP-114)",
			"%s with the board at %.0f px" % [_game_entry().design_size, board_h])
	await _tear_down(view)

	# The pure clamp, at and past the cap.
	check(WallPicture.clamped_render_size(Vector2i(cap, cap), cap) == Vector2i(cap, cap),
			"the clamp leaves a size exactly at the cap alone (TP-114)")
	check(WallPicture.clamped_render_size(Vector2i(cap * 3, cap + 1), cap) == Vector2i(cap, cap),
			"...and caps EVERY axis, not just the wide one (TP-114)")

	# The product path: the real game entry, built and focused the way `Main` does it.
	var host := Node2D.new()
	var viewports := Node.new()
	add_child(host)
	add_child(viewports)
	var entry := _game_entry()
	var rect := PictureRect.new(entry.id, Vector2.ZERO, Vector2(entry.design_size) * 0.5,
			Vector4(10, 10, 10, 10))
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	host.add_child(wp)
	wp.build(rect, entry, viewports)
	wp.focus()
	check(wp.viewport.size.x <= cap and wp.viewport.size.y <= cap,
			"the FOCUSED game picture asks for a render target inside the cap on both axes "
			+ "(TP-114)",
			"size %s, cap %d" % [wp.viewport.size, cap])
	check(wp.viewport.size_2d_override == Vector2i.ZERO,
			"...and, since the shipped picture is inside the cap, it renders 1:1 with the "
			+ "override CLEARED, which input routing depends on (TP-114)",
			str(wp.viewport.size_2d_override))
	wp.teardown()

	# The wiring, proved with an entry deliberately past the cap: this fails if the clamp stops
	# being CALLED, not merely if it stops existing.
	var huge := PictureEntry.new()
	huge.id = &"oversized"
	huge.design_size = Vector2i(cap * 2, cap + 1)
	var huge_rect := PictureRect.new(huge.id, Vector2.ZERO, Vector2(200.0, 100.0),
			Vector4(10, 10, 10, 10))
	var wp2 : WallPicture = WALL_PICTURE_SCENE.instantiate()
	host.add_child(wp2)
	wp2.build(huge_rect, huge, viewports)
	check(wp2.viewport.size == Vector2i(cap, cap),
			"build() writes the CLAMPED size for an entry past the cap (TP-114)",
			"size %s, design %s" % [wp2.viewport.size, huge.design_size])
	wp2.focus()
	check(wp2.viewport.size == Vector2i(cap, cap),
			"...and focus() writes the clamped size too - focus is the path that used to ask "
			+ "for full design size unconditionally (TP-114)",
			"size %s" % str(wp2.viewport.size))
	check(wp2.viewport.size_2d_override == huge.design_size,
			"...with the canvas override holding the LAYOUT at full design size (TP-114)",
			"override %s" % str(wp2.viewport.size_2d_override))
	check(wp2.viewport.size_2d_override_stretch,
			"...and the override actually stretching onto the smaller render target (TP-114)")
	wp2.teardown()
	host.queue_free()
	viewports.queue_free()
	await get_tree().process_frame

## The `game` entry as the real wall reads it -- through `Wall.load_layout()`, never a fresh
## `PictureEntry`, so anything that stopped sizing it shows up here.
func _game_entry() -> PictureEntry:
	for e : PictureEntry in Wall.load_layout().pictures:
		if e.id == Wall.GAME_PICTURE_ID: return e
	return null

## The board width `n` grid blocks of `block_x` px span, spaced by the DERIVED isolating buffer,
## matching `PlayArea.grid_position_size_px()`.
func _grid_span(block_x: float, n: int) -> float:
	var st := SettingsManager.settings
	return float(n) * block_x + float(n - 1) * PlayArea.isolating_grid_buffer_px(st)

# ==============================================================================
# TP-105 — THE CAMERA STEPS BETWEEN THE 3 GRID POSITIONS THE FRAME HOLDS (`H22`), through the
# `Main`-hosted fixture (`GAP-026`=(a)).
#
# ⚠ DRIVES REAL INPUT THROUGH `PlayArea`, THE SAME ROUTE A PLAYER TAKES — never a direct call to
# `Main._on_overview_pan_requested()`, which is exactly the shape the dead touch-swipe shipped in
# while its own tests stayed green.
# ==============================================================================

## The grid's own cell block, in the SAME world space as `%Camera2D.position` — the picture's
## design-pixel layout scaled by the WallPicture's real packed rect, never assumed 1:1.
func _grid_world_rect(main: Main, pa: PlayArea, gi: int) -> Rect2:
	return _control_world_rect(main, pa._cells_root(pa.grid_container.get_child(gi) as Control))

## Any control inside the game screen, in WALL WORLD space -- what the camera actually frames.
## ⚠ The screen draws at `rect.size / design_size`, so a control's own rect has to cross that
## scale before it can be compared with a camera rect. `_screen_rect` already carries the board
## zoom; this carries the picture's.
func _control_world_rect(main: Main, c: Control) -> Rect2:
	var wp : WallPicture = main._pictures[&"game"]
	var design := Vector2(PlayArea.game_picture_design_size(SettingsManager.settings))
	var local := _screen_rect(c)
	var scale := wp.rect.size / design
	var top_left := wp.rect.centre - wp.rect.size * 0.5
	return Rect2(top_left + local.position * scale, local.size * scale)

## How far `r` hangs outside `visible`, per edge, as "left, top, right, bottom" -- positive means
## OUTSIDE. ⚠ A single worst-case number cannot tell a cut top row from a cut Entrance, and those
## are different defects with different causes.
func _outside_px(r: Rect2, visible: Rect2) -> Array[float]:
	return [visible.position.x - r.position.x, visible.position.y - r.position.y,
			r.end.x - visible.end.x, r.end.y - visible.end.y] as Array[float]

func run_the_camera_steps_between_grid_positions_test() -> void:
	behavior_section("THE CAMERA STEPS BETWEEN GRID POSITIONS")
	var main := await _stand_up_main_grids(3)
	var view := _main_game_view(main)
	var pa := view.play_area
	var camera := _main_camera(main)
	var window_size := main.get_viewport().get_visible_rect().size
	pa.open_zoomed_out()
	await _settle_camera(camera)
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"precondition: the board is in the overview, where H22 stepping lives (TP-105)",
			"mode %d" % pa.view_mode)
	var rest_grid := pa.pan_grid
	var rest_x := camera.position.x
	# OBSERVED, not recomputed: the world-space distance between two adjacent grid panels' own
	# cell blocks, read the same way `stepped_rect` below is -- never the production formula that
	# lays them out, so this cannot agree with a wrong pitch the way a copy of it would.
	var pitch := _grid_world_rect(main, pa, rest_grid + 1).get_center().x 			- _grid_world_rect(main, pa, rest_grid).get_center().x

	_fire_key(KEY_PERIOD)
	await get_tree().process_frame
	_fire_key_release(KEY_PERIOD)
	await _settle_camera(camera)
	check(pa.pan_grid == rest_grid + 1,
			"a real grid_pan_right key press steps the view one grid (TP-105)",
			"pan_grid %d" % pa.pan_grid)
	check(is_equal_approx(camera.position.x - rest_x, pitch),
			"the camera stepped by EXACTLY one grid position's pitch, not a scroller's own aim "
			+ "(TP-105)",
			"moved %.3f vs pitch %.3f" % [camera.position.x - rest_x, pitch])
	var visible := WallTransition.visible_rect(camera.position, camera.zoom.x, window_size)
	var stepped_rect := _grid_world_rect(main, pa, pa.pan_grid)
	check(visible.encloses(stepped_rect),
			"the grid stepped onto sits wholly inside the camera's OWN visible_rect() (TP-105)",
			"visible %s vs grid %s" % [visible, stepped_rect])

	for _i : int in range(pa.grid_container.get_child_count() + 2):
		_fire_key(KEY_PERIOD)
		await get_tree().process_frame
		_fire_key_release(KEY_PERIOD)
		await _settle_camera(camera)
	check(pa.pan_grid == pa.grid_container.get_child_count() - 1,
			"repeated pan-right presses stop at the board's last grid (TP-105)",
			"pan_grid %d of %d" % [pa.pan_grid, pa.grid_container.get_child_count()])
	var edge_x := camera.position.x
	_fire_key(KEY_PERIOD)
	await get_tree().process_frame
	_fire_key_release(KEY_PERIOD)
	await _settle_camera(camera)
	check(is_equal_approx(camera.position.x, edge_x),
			"one more pan-right at the board's end does not move the camera past it (TP-105)",
			"edge %.3f vs after %.3f" % [edge_x, camera.position.x])
	await _tear_down_main(main)

# ==============================================================================
# THE FOCUSED VIEW'S MINIMUM FRAMING: the whole 5x5 cell block PLUS the Entrance row, inside what
# the CAMERA shows. Owner: "clicking on grid zooms in but everything is clipped instead of fitting
# in 5x5 grid + entrance row as minimum size."
#
# ⚠ **THE TARGET IS THE CAMERA'S RECT, NOT THE PLAY AREA'S.** Two scales stack: the board fits its
# content into the play area (`focused_board_zoom`), and then the wall camera fits the PICTURE into
# the WINDOW. A fit that exactly fills an 841 px picture still clips once the camera crops that
# picture into the window, and only a real `Main`/`Wall`/`%Camera2D` can answer the second half.
#
# ⚠ **ONE GRID, WHICH IS THE DEFAULT.** A deck of 52 or fewer unlocks exactly one, and a one-grid
# show opens focused, so this is the pose a player sees first.
#
# ⚠ **THE EDGES ARE NAMED SEPARATELY ON PURPOSE.** A cut top row and a cut Entrance have different
# causes; a single worst-case number cannot tell them apart, and the owner reported both at once.
# ==============================================================================
func run_the_focused_view_frames_the_block_and_the_entrance_test() -> void:
	behavior_section("THE FOCUSED VIEW FRAMES THE CELL BLOCK AND THE ENTRANCE")
	var main := await _stand_up_main_grids(1)
	var view := _main_game_view(main)
	var pa := view.play_area
	var camera := _main_camera(main)
	pa.focus_grid(0)
	await _settle_layout(view)
	await _settle_scroll(view)
	await _settle_camera(camera)
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED and not is_equal_approx(pa.board_zoom, 1.0),
			"precondition: the board is FOCUSED and off the overview's own zoom",
			"mode %d, board_zoom %.4f" % [pa.view_mode, pa.board_zoom])

	var window_size := main.get_viewport().get_visible_rect().size
	var visible := WallTransition.visible_rect(camera.position, camera.zoom.x, window_size)
	var block := _grid_world_rect(main, pa, 0)
	# ⚠ **THE ENTRANCE'S CARDS, NOT THE STRIP THEY SIT IN.** `entrance_strip` is a full-width
	# background container spanning the whole play area; whether IT fits the camera is a question
	# about a backdrop, not about whether the player can see the Entrance. The same distinction
	# `_publish_cell_rects()` documents for a grid panel against its cells -- and reading the wrong
	# one here reported the Entrance 15.45 px out of frame while every card in it was visible.
	var strip := _control_world_rect(main, pa.upper_zone_right)

	var b := _outside_px(block, visible)
	check(maxf(maxf(b[0], b[1]), maxf(b[2], b[3])) <= 1.0,
			"the whole 5x5 cell block is inside what the camera shows",
			"outside by left %.2f top %.2f right %.2f bottom %.2f" % [b[0], b[1], b[2], b[3]])
	var e := _outside_px(strip, visible)
	check(maxf(maxf(e[0], e[1]), maxf(e[2], e[3])) <= 1.0,
			"...and so is the Entrance row beneath it",
			"outside by left %.2f top %.2f right %.2f bottom %.2f" % [e[0], e[1], e[2], e[3]])
	await _tear_down_main(main)


# ==============================================================================
# A CARD MOVING BETWEEN GRIDS IS NEVER CLIPPED AWAY (owner: *"if an effect makes a card move
# between grids it should not disappear"*).
#
# ⚠ **THE CLIP AND THE CAMERA ARE DIFFERENT MECHANISMS AND ONLY ONE OF THEM MAY ISOLATE.** The
# owner ruled that "out of view" means OFF CAMERA. `%CardLayer` is a child of
# `SmoothScrollContainer/TopLevelVBox`, so a clip on that scroller CULLS card visuals outright --
# a neighbour hidden by the clip takes any card flying to it with it. The camera may hide a grid;
# the clip may not.
#
# ⚠ **THE BOARD THEREFORE DOES NOT CLIP AT ALL, and the owner's reason is not tall stacks:** props
# and animations are authored to leave the board's edges on purpose, and the clip was cutting those
# too. So this no longer asks whether a neighbour's cells happen to fall inside a window -- it asks
# the stronger question directly, that there IS no window to fall outside of.
# ==============================================================================
func run_a_card_between_grids_is_never_clipped_away_test() -> void:
	behavior_section("A CARD BETWEEN GRIDS IS NEVER CLIPPED AWAY")
	var view := await _stand_up_grids(3)
	var pa := view.play_area
	await _settle_layout(view)
	pa.focus_grid(1)
	await _settle_layout(view)
	await _settle_scroll(view)
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED and pa.grid_container.get_child_count() == 3,
			"precondition: three grids, focused on the middle one",
			"mode %d, %d panels" % [pa.view_mode, pa.grid_container.get_child_count()])

	check(not pa.scroll_container.clip_contents,
			"the board's scroller does not clip, so NOTHING on the card layer is ever culled -- "
			+ "not a card flying between grids, and not a prop or an animation that leaves the "
			+ "board's edge on purpose")
	var node : Node = pa.card_layer
	var clippers : Array[String] = []
	while node and node != pa.get_parent():
		var c := node as Control
		if c and c.clip_contents: clippers.append(str(node.name))
		node = node.get_parent()
	check(clippers.is_empty(),
			"...and nothing ELSE between the card layer and the play area clips either -- the "
			+ "whole chain is checked, so a clip re-appearing one level up cannot hide here",
			"clipping: %s" % [clippers])
	# The endpoints a cross-grid move runs between still have to EXIST off the focused window --
	# that is what makes the check above load-bearing rather than vacuous.
	var win := _screen_rect(pa.scroll_container)
	var outside_any := false
	for gi : int in 3:
		var at := pa.slot_center_global(BoardCoord.new(gi, 0, 0, 0))
		if at.x < win.position.x or at.x > win.end.x: outside_any = true
	check(outside_any,
			"instrument check: a neighbouring grid's cells really do sit outside the board's "
			+ "window, so 'never culled' is a claim about something that would otherwise be cut")
	await _tear_down(view)

# ==============================================================================
# S32 — THE SAVED PAN (`H18`, `H19`): TP-115, TP-116, TP-117.
#
# The picture is three grids wide, so the camera finally has somewhere to rest that is NOT the
# picture's centre, and `GAP-020`'s answer (b) — "resize the picture first, then implement H18
# literally" — is what these three rows prove landed.
#
# ⚠ **THE LOAD-BEARING CHECK IN EACH IS THE ONE THAT NAMES THE CENTRE.** A pose that happens to be
# one pitch from where the camera was is satisfied by any offset; only "and it is NOT the picture's
# centre" fails when the saved pan is dropped and `resting_state()` answers again.
#
# ⚠ The pitch here is OBSERVED between two real grid panels, the same way `TP-105` reads it, never
# recomputed from the production formula that placed them.
#
# ⚠ **SOME CHECKS HERE ARE REGRESSION GUARDS, NOT DISCRIMINATORS, AND THE RED RUN NAMED THEM.**
# While a board is mounted the camera ALREADY rested on the pan, by re-deriving it from `PlayArea`
# every settle — so "the camera is not at the centre", "the board comes back on the grid it was
# left on" and "the grid survives a resize" all pass with the saved pan deleted. They stay because
# each is a property a future change can break; what proves THIS step are the checks naming
# `saved_pan_x` itself, and the one that asks with no live board to read.
# ==============================================================================

## The world-space distance between two adjacent grids' cell blocks — `TP-105`'s own measurement,
## reused so a wrong pitch cannot agree with itself.
func _observed_pitch(main: Main, pa: PlayArea, gi: int) -> float:
	return _grid_world_rect(main, pa, gi + 1).get_center().x \
			- _grid_world_rect(main, pa, gi).get_center().x

## The camera pose the game picture would rest at with NO saved pan — `WallPicture.resting_state()`
## on the real packed rect. The thing every check below must differ from.
func _unpanned_rest_x(main: Main) -> float:
	var wp : WallPicture = main._pictures[&"game"]
	var window := main.get_viewport().get_visible_rect().size
	var state := WallPicture.resting_state(wp.rect, window, SettingsManager.settings)
	return (state["position"] as Vector2).x

func run_the_camera_rests_at_the_saved_pan_test() -> void:
	behavior_section("THE CAMERA RESTS AT THE SAVED PAN, NOT THE PICTURE CENTRE (TP-115)")
	var main := await _stand_up_main_grids(3)
	var view := _main_game_view(main)
	var pa := view.play_area
	var camera := _main_camera(main)
	var wp : WallPicture = main._pictures[&"game"]
	pa.open_zoomed_out()
	await _settle_camera(camera)
	check(pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"precondition: the board is in the overview, the one view whose pan the camera makes "
			+ "(TP-115)", "mode %d" % pa.view_mode)
	var centre_x := _unpanned_rest_x(main)
	check(is_equal_approx(wp.saved_pan_x, 0.0),
			"precondition: an unpanned picture's saved pan is zero, which IS its centre (TP-115)",
			"saved %.3f" % wp.saved_pan_x)

	var rest_grid := pa.pan_grid
	var pitch := _observed_pitch(main, pa, rest_grid)
	_fire_key(KEY_PERIOD)
	await get_tree().process_frame
	_fire_key_release(KEY_PERIOD)
	await _settle_camera(camera)
	check(pa.pan_grid == rest_grid + 1,
			"sanity: a real pan-right key press moved the view one grid, so there IS a pan to save "
			+ "(TP-115)", "pan_grid %d" % pa.pan_grid)
	check(is_equal_approx(wp.saved_pan_x, pitch),
			"the picture's saved pan is exactly one grid pitch — the step the player just made, "
			+ "stored on the picture (TP-115)",
			"saved %.3f vs pitch %.3f" % [wp.saved_pan_x, pitch])
	check(not is_equal_approx(camera.position.x, centre_x),
			"...and the camera is NOT at the picture's centre, which is where resting_state() "
			+ "alone would have put it (TP-115)",
			"camera %.3f vs centre %.3f" % [camera.position.x, centre_x])
	check(is_equal_approx(camera.position.x - centre_x, wp.saved_pan_x),
			"...it is the centre plus exactly the saved pan (TP-115)",
			"offset %.3f vs saved %.3f" % [camera.position.x - centre_x, wp.saved_pan_x])

	# ⚠ THE CASE A BARE `resting_state()` GOT WRONG. `Main._camera_resting_state()` reads the live
	# board back into the saved pan whenever there is one — so the only way to see the SAVED value
	# answering on its own is to ask while there is no board to read, which is the state every
	# frame of a transition and every detached show is in. The real field is set aside and put
	# back, never a stand-in board.
	var real_screen := wp.screen_root
	wp.screen_root = null
	var state := main._camera_resting_state(&"game", wp.rect, SettingsManager.settings)
	wp.screen_root = real_screen
	var pose_x : float = (state["position"] as Vector2).x
	check(is_equal_approx(pose_x - centre_x, pitch),
			"with no live board to read, the resting pose is still the SAVED pan — the frames a "
			+ "transition and a detached show run in (TP-115)",
			"pose %.3f, centre %.3f, saved %.3f" % [pose_x, centre_x, wp.saved_pan_x])
	await _tear_down_main(main)

func run_leaving_and_re_entering_restores_the_pan_test() -> void:
	behavior_section("LEAVING AND RE-ENTERING RESTORES THE PAN, SNAPPED (TP-116)")
	var settings := SettingsManager.settings
	var prev_delay : float = settings.wall_transition_delay
	settings.wall_transition_delay = 0.001
	var main := await _stand_up_main_grids(3)
	var view := _main_game_view(main)
	var pa := view.play_area
	var camera := _main_camera(main)
	var wp : WallPicture = main._pictures[&"game"]
	pa.open_zoomed_out()
	await _settle_camera(camera)
	var rest_grid := pa.pan_grid
	var pitch := _observed_pitch(main, pa, rest_grid)
	var centre_x := _unpanned_rest_x(main)
	_fire_key(KEY_PERIOD)
	await get_tree().process_frame
	_fire_key_release(KEY_PERIOD)
	await _settle_camera(camera)
	var left_on := pa.pan_grid
	check(left_on == rest_grid + 1,
			"sanity: the show is left on a grid that is NOT the one it rests on (TP-116)",
			"left on %d, rests on %d" % [left_on, rest_grid])

	await main._focus_picture(&"map")
	check(main._current_focus == &"map",
			"sanity: the player really left the show for another picture (TP-116)",
			str(main._current_focus))
	# A saved pan predates any grid-count change, so `Q173`=(b) restores it SNAPPED rather than
	# replayed. Nothing a player does produces a pan between two grids, so the value is set here
	# to one — 0.6 of a pitch past the grid it was left on, which rounds up onto the next grid and
	# then clamps back to the last grid the board has.
	wp.saved_pan_x = pitch * 1.6
	await main.enter_game()
	await _settle_camera(camera)
	check(pa.pan_grid == left_on,
			"re-entering puts the BOARD back on the grid the snapped pan names, not on whatever "
			+ "grid a fresh layout rests on (TP-116)",
			"pan_grid %d, expected %d" % [pa.pan_grid, left_on])
	check(is_equal_approx(wp.saved_pan_x, pitch),
			"...and the pan that was 1.6 pitches out is snapped back onto a whole grid (TP-116)",
			"saved %.3f vs pitch %.3f" % [wp.saved_pan_x, pitch])
	check(not is_equal_approx(camera.position.x, centre_x),
			"...and the camera came back to the pan, not to the picture's centre (TP-116)",
			"camera %.3f vs centre %.3f" % [camera.position.x, centre_x])
	check(is_equal_approx(camera.position.x - centre_x, wp.saved_pan_x),
			"...at exactly the restored pan's offset (TP-116)",
			"offset %.3f vs saved %.3f" % [camera.position.x - centre_x, wp.saved_pan_x])
	await _tear_down_main(main)
	settings.wall_transition_delay = prev_delay

func run_a_resize_re_derives_the_pose_from_the_saved_pan_test() -> void:
	behavior_section("A RESIZE RE-DERIVES THE POSE FROM THE SAVED PAN (TP-117)")
	var main := await _stand_up_main_grids(3)
	var view := _main_game_view(main)
	var pa := view.play_area
	var camera := _main_camera(main)
	var wp : WallPicture = main._pictures[&"game"]
	pa.open_zoomed_out()
	await _settle_camera(camera)
	var rest_grid := pa.pan_grid
	var pitch := _observed_pitch(main, pa, rest_grid)
	_fire_key(KEY_PERIOD)
	await get_tree().process_frame
	_fire_key_release(KEY_PERIOD)
	await _settle_camera(camera)
	var centre_x := _unpanned_rest_x(main)
	check(is_equal_approx(camera.position.x - centre_x, pitch),
			"sanity: the camera is one grid off centre before the resize (TP-117)",
			"offset %.3f vs pitch %.3f" % [camera.position.x - centre_x, pitch])

	# ⚠ `DisplayServer.window_set_size()` CANNOT go below the project minimum, so a suite cannot
	# drive a real resize to an arbitrary size. What a resize actually IS, to this code, is
	# `Main._window_size` disagreeing with the viewport — so that disagreement is created and the
	# real handler is run against the real window, rather than a size being faked into it.
	main._window_size = Vector2(1.0, 1.0)
	main._on_window_resized()
	await _settle_camera(camera)
	check(main._window_size.is_equal_approx(main.get_viewport().get_visible_rect().size),
			"sanity: the resize handler really ran and took the window's size (TP-117)",
			"%s" % main._window_size)
	check(is_equal_approx(wp.saved_pan_x, pitch),
			"the saved pan survives the resize — it is a board position, not a screen one "
			+ "(TP-117)", "saved %.3f vs pitch %.3f" % [wp.saved_pan_x, pitch])
	check(pa.pan_grid == rest_grid + 1,
			"...and so does the grid the board is on (TP-117)",
			"pan_grid %d" % pa.pan_grid)
	var after_centre_x := _unpanned_rest_x(main)
	check(not is_equal_approx(camera.position.x, after_centre_x),
			"...and the re-derived pose is NOT the picture's centre (TP-117)",
			"camera %.3f vs centre %.3f" % [camera.position.x, after_centre_x])
	check(is_equal_approx(camera.position.x - after_centre_x, wp.saved_pan_x),
			"...it is the centre plus the saved pan, re-derived after the resize (TP-117)",
			"offset %.3f vs saved %.3f" % [camera.position.x - after_centre_x, wp.saved_pan_x])
	await _tear_down_main(main)
