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
	await run_clicking_a_grid_zooms_in_on_it_test()
	await run_back_zooms_out_and_forward_returns_test()
	await run_panning_has_its_own_actions_test()
	await run_every_pan_lands_a_grid_centred_test()
	await run_the_board_edge_bounces_test()
	await run_the_clamp_collapses_to_centre_when_it_fits_test()
	finish()

## FIX-GRID-3 standing in a real GameView: the show's own board grown to three empty 5x5 grids.
## Mirrors `test_grid_layout._stand_up` — same goal-out-of-reach and same CardEnvironment
## re-assertion, for the same reasons its comments give.
func _stand_up() -> GameView:
	return await _stand_up_grids(3)

## The same stand-up at any grid count: FIX-GRID-3 at 3, FIX-GRID-1 at 1.
func _stand_up_grids(n: int) -> GameView:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260829)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	while view.game.state.grids.size() < n:
		Board.add_grid(view.game.state, GridData.new())
	while view.game.state.grids.size() > n:
		Board.remove_grid(view.game.state, view.game.state.grids.size() - 1)
	view.play_area.flush_rebuild()
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
func _settle_scroll(view: GameView) -> void:
	var smooth := _scroller(view.play_area)
	var last := INF
	var waited := 0.0
	while waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		CardEnvironment.CURRENT = view.game
		var now := smooth.pos.x
		if is_equal_approx(now, last): return
		last = now

## The board's VISIBLE window in global x: the scroll container's own rect less whatever a visible
## vertical scrollbar takes off its right edge. ⚠ Not the rect itself — a shown v-scrollbar narrows
## the content area, and the board is laid out inside what is left, so the rect's own centre is off
## by half the bar (measured: 4 px).
func _window_x(pa: PlayArea) -> Vector2:
	var bar := pa.scroll_container.get_v_scroll_bar()
	var taken : float = bar.size.x if bar and bar.visible else 0.0
	var left := pa.scroll_container.global_position.x
	return Vector2(left, left + pa.scroll_container.size.x - taken)

## How far grid `gi`'s CELL BLOCK hangs outside that window, in pixels; 0 when it is wholly on
## screen. The instrument for "no cut-off grid at rest".
func _cut_off_px(pa: PlayArea, gi: int) -> float:
	var cells := pa._cells_root(pa.grid_container.get_child(gi) as Control)
	var win := _window_x(pa)
	return maxf(maxf(win.x - cells.global_position.x, 0.0),
			maxf(cells.global_position.x + cells.size.x - win.y, 0.0))

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
# TP-101 - FIX-GRID-3: every pan lands a grid centred; no cut-off grid at rest.
# ==============================================================================
func run_every_pan_lands_a_grid_centred_test() -> void:
	behavior_section("EVERY PAN LANDS A GRID CENTRED")
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)
	pa.pan_to_grid(0)
	await _settle_scroll(view)
	check(_board_overflows(pa),
			"precondition: three grids are wider than the window, so a pan can move (TP-101)",
			"content %f window %f" % [pa.grid_container.size.x, pa.scroll_container.size.x])
	check(_cut_off_px(pa, 0) <= 1.0,
			"grid 0 rests wholly on screen",
			"%f px off screen" % _cut_off_px(pa, 0))

	for step : int in [1, 2]:
		pa._unhandled_input(_action(&"grid_pan_right"))
		await _settle_scroll(view)
		check(pa.pan_grid == step,
				"a pan-right press steps ONE grid, to grid %d (TP-101)" % step,
				"pan_grid %d" % pa.pan_grid)
		check(_cut_off_px(pa, step) <= 1.0,
				"grid %d rests wholly on screen -- no cut-off grid at rest" % step,
				"%f px off screen" % _cut_off_px(pa, step))

	pa._unhandled_input(_action(&"grid_pan_left"))
	await _settle_scroll(view)
	check(pa.pan_grid == 1,
			"a pan-left press steps back one grid",
			"pan_grid %d" % pa.pan_grid)
	check(_cut_off_px(pa, 1) <= 1.0,
			"and that grid rests wholly on screen too",
			"%f px off screen" % _cut_off_px(pa, 1))
	await _tear_down(view)

# ==============================================================================
# TP-102 - FIX-GRID-3: the board edge bounces.
#
# A BOUNCE IS A MOTION, NOT A POSE. Sampled over frames: the board must MOVE past its resting edge
# and then come back to it. A still frame either side proves nothing.
# ==============================================================================
func run_the_board_edge_bounces_test() -> void:
	behavior_section("THE BOARD EDGE BOUNCES")
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)
	check(_board_overflows(pa),
			"precondition: the board overflows, so it has an edge to bounce off (TP-102)")
	var smooth := _scroller(pa)
	pa.pan_to_grid(2)
	await _settle_scroll(view)
	check(pa.pan_grid == 2,
			"precondition: the view is on the LAST grid, with nowhere further right to go")
	var rest := smooth.pos.x

	pa._unhandled_input(_action(&"grid_pan_right"))
	var farthest := 0.0
	var waited := 0.0
	while waited < 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		CardEnvironment.CURRENT = view.game
		farthest = maxf(farthest, absf(smooth.pos.x - rest))
	check(farthest > 1.0,
			"pressing right at the last grid PUSHES the board past its edge (TP-102)",
			"%f px past rest" % farthest)
	check(pa.pan_grid == 2,
			"...without stepping onto a grid that is not there",
			"pan_grid %d" % pa.pan_grid)
	await _settle_scroll(view)
	check(absf(smooth.pos.x - rest) <= 1.0,
			"...and the board comes back to its edge: a bounce, not a scroll",
			"rest %f -> %f" % [rest, smooth.pos.x])
	check(_cut_off_px(pa, 2) <= 1.0,
			"the last grid is wholly on screen again once the bounce settles",
			"%f px off screen" % _cut_off_px(pa, 2))
	await _tear_down(view)

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
	var panel := pa.grid_container.get_child(0) as Control
	var win := _window_x(pa)
	var window_centre := (win.x + win.y) * 0.5
	var grid_centre := panel.global_position.x + panel.size.x * 0.5
	check(absf(grid_centre - window_centre) <= 2.0,
			"the board that already fits sits CENTRED, not parked at an edge (TP-103)",
			"grid %f vs window %f" % [grid_centre, window_centre])

	for a : StringName in [&"grid_pan_right", &"grid_pan_left"]:
		pa._unhandled_input(_action(a))
	await _settle_scroll(view)
	var after := pa.grid_container.get_child(0) as Control
	var after_centre := after.global_position.x + after.size.x * 0.5
	check(absf(after_centre - window_centre) <= 2.0,
			"panning either way leaves it centred: the clamp collapsed the whole range",
			"grid %f vs window %f" % [after_centre, window_centre])
	check(pa.pan_grid == 0,
			"and there was never another grid to step onto",
			"pan_grid %d" % pa.pan_grid)
	await _tear_down(view)
