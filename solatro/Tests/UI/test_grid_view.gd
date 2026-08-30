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
	await run_the_board_rests_positioned_test()
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
	var left := pa.scroll_container.global_position.x
	return Vector2(left, left + pa.scroll_container.size.x - taken)

## How far grid `gi`'s CELL BLOCK hangs outside that window, in pixels; 0 when it is wholly on
## screen. The instrument for "no cut-off grid at rest" — a rule scoped to the grid the view is ON:
## ⚠ ask it about that grid, never about every grid on the board (owner ruling).
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
	var view := await _stand_up()
	var pa := view.play_area
	await _settle_layout(view)
	await _settle_scroll(view)
	check(_board_overflows(pa),
			"precondition: three grids are wider than the window, so a pan can move (TP-101)",
			"content %f window %f" % [pa.grid_container.size.x, pa.scroll_container.size.x])
	var rest_grid := pa.pan_grid
	check(rest_grid == 1,
			"precondition: the overview rests on the middle of three grids (TP-101)",
			"pan_grid %d" % rest_grid)
	check(_cut_off_px(pa, rest_grid) <= 1.0,
			"the grid the view rests on is wholly on screen, with no pan asked for (TP-101)",
			"%f px off screen" % _cut_off_px(pa, rest_grid))

	pa._unhandled_input(_action(&"grid_pan_right"))
	await _settle_scroll(view)
	check(pa.pan_grid == rest_grid + 1,
			"a pan-right press steps ONE grid, to grid %d (TP-101)" % (rest_grid + 1),
			"pan_grid %d" % pa.pan_grid)
	check(_cut_off_px(pa, pa.pan_grid) <= 1.0,
			"the grid it stepped onto rests wholly on screen -- no cut-off grid UNDER THE VIEW",
			"%f px off screen" % _cut_off_px(pa, pa.pan_grid))

	for _i : int in [0, 1]:
		pa._unhandled_input(_action(&"grid_pan_left"))
		await _settle_scroll(view)
	check(pa.pan_grid == rest_grid - 1,
			"two pan-left presses step back two grids, to grid %d" % (rest_grid - 1),
			"pan_grid %d" % pa.pan_grid)
	check(_cut_off_px(pa, pa.pan_grid) <= 1.0,
			"and that grid rests wholly on screen too",
			"%f px off screen" % _cut_off_px(pa, pa.pan_grid))
	await _tear_down(view)

# ==============================================================================
# TP-138 — THE BOARD RESTS POSITIONED: at rest, with nothing panned, the board sits where an
# explicit pan to the grid the view is on puts it.
#
# ⚠ FIVE GRIDS, NOT THREE. With the view on grid 0 the scroll container's own clamp parks the board
# hard left anyway, so an unpositioned board and a correctly positioned one are the SAME number and
# the check passes with the wiring cut. The resting grid has to be one the clamp cannot supply.
#
# ⚠ THE CLAIM IS AN IDENTITY, NOT A TOLERANCE: where a grid comes to rest is the layout's business,
# so the reference is the player's own pan to that same grid — the same reference TP-112 uses.
# ==============================================================================
func run_the_board_rests_positioned_test() -> void:
	behavior_section("THE BOARD RESTS POSITIONED ON THE GRID THE VIEW IS ON")
	var view := await _stand_up_grids(5)
	var pa := view.play_area
	var smooth := _scroller(pa)
	await _settle_layout(view)
	await _settle_scroll(view)
	check(_board_overflows(pa),
			"precondition: five grids overflow the window, so resting position is the scroll's job"
			+ " (TP-138)")
	check(pa.pan_grid == 2,
			"the overview rests on the MIDDLE grid, so the whole board is centred (TP-138)",
			"pan_grid %d" % pa.pan_grid)
	check(_cut_off_px(pa, pa.pan_grid) <= 1.0,
			"...and the grid it rests on is wholly in frame (TP-138)",
			"%f px off screen" % _cut_off_px(pa, pa.pan_grid))
	var rest := smooth.pos.x
	pa.pan_to_grid(pa.pan_grid)
	await _settle_scroll(view)
	check(absf(smooth.pos.x - rest) <= 1.0,
			"the board at rest is already where an explicit pan to that grid puts it -- it was "
			+ "POSITIONED, not left at scroll zero (TP-138)",
			"rest %.1f vs explicit pan %.1f" % [rest, smooth.pos.x])

	# FOCUSED: the resting grid is the focused one, and it is the only grid the cut-off rule speaks
	# about — its neighbours may be sliced by the window edge and that is not a defect.
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
	var view := await _stand_up_grids(5)
	var pa := view.play_area
	await _settle_layout(view)
	check(pa.grid_container.get_child_count() == 5,
			"precondition: five grids on the board (TP-106)",
			"%d panels" % pa.grid_container.get_child_count())
	check(pa.grid_container.get_child_count() > SettingsManager.settings.grid_max_count,
			"precondition: that is MORE than the cap, which is the case TP-106 is about",
			"cap %d" % SettingsManager.settings.grid_max_count)

	pa.pan_to_grid(1)
	await _settle_scroll(view)
	var before := _grids_in_frame(pa)
	check(not before.is_empty(),
			"instrument check: some grid is in frame at rest, so 'in frame' means something",
			"%s" % [before])
	check(before.size() < 5,
			"precondition: five grids do NOT all fit -- there is something to shift into frame",
			"%s in frame" % [before])
	# ⚠ **THE GRID THE VIEW IS ON, NOT ITS NEIGHBOUR.** This asked for grid 0 while the view sat on
	# grid 1, which held only while grids were spaced 4 px apart and two of them fitted the window
	# at once. `grid_buffer_px` puts a real gap between cell blocks, so at this window size the
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
	check(pa.pan_grid == 3,
			"two pan-right presses step the view onto grid 3 (TP-106)",
			"pan_grid %d" % pa.pan_grid)
	var after := _grids_in_frame(pa)
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
	var back := _grids_in_frame(pa)
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
	await _tear_down(view)

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
	var view := await _stand_up_grids(5)
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
# TP-113 - the game picture is sized for exactly `grid_max_count` grids, plus margins, at the
# height the zoomed-out view needs. The size is read through `Wall.load_layout()` - the one seam
# every real wall build goes through - so a picture that stopped being sized fails here.
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
	check(float(design.x) >= span_3,
			"the game picture is wide enough for three grid blocks and the two buffers between "
			+ "them (TP-113)",
			"design %d px, three grids span %.1f px" % [design.x, span_3])
	check(float(design.x) < span_4,
			"...and NOT wide enough for a fourth - exactly three, not merely at least three "
			+ "(TP-113)",
			"design %d px, four grids span %.1f px" % [design.x, span_4])
	check(absf(float(design.x) - span_3 - 2.0 * st.grid_overview_margin * span_3) <= 1.0,
			"...with the leftover width being exactly the overview margin on each side (TP-113)",
			"leftover %.1f px, margin %.3f of %.1f px" % [float(design.x) - span_3,
			st.grid_overview_margin, span_3])
	# The height rule: the natural board height or the aspect minimum, whichever is LARGER.
	var ref_w : float = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var ref_h : float = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	var aspect_minimum := float(design.x) * ref_h / ref_w
	check(float(design.y) >= block.y - 1.0,
			"the picture is at least the board's own natural height (TP-113)",
			"design %d px, natural %.1f px" % [design.y, block.y])
	check(float(design.y) >= aspect_minimum - 1.0,
			"...and at least the height the window aspect needs, so the zoomed-out view is "
			+ "entirely picture (TP-113)",
			"design %d px, aspect minimum %.1f px" % [design.y, aspect_minimum])
	check(float(design.y) <= maxf(block.y, aspect_minimum) + 1.0,
			"...and no taller than the LARGER of the two - whichever is larger, not their sum "
			+ "(TP-113)",
			"design %d px, larger of %.1f / %.1f" % [design.y, block.y, aspect_minimum])

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

## The board width `n` grid blocks of `block_x` px span, spaced by `grid_buffer_px`.
func _grid_span(block_x: float, n: int) -> float:
	return float(n) * block_x + float(n - 1) * SettingsManager.settings.grid_buffer_px
