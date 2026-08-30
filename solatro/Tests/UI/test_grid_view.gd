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
	finish()

## FIX-GRID-3 standing in a real GameView: the show's own board grown to three empty 5x5 grids.
## Mirrors `test_grid_layout._stand_up` — same goal-out-of-reach and same CardEnvironment
## re-assertion, for the same reasons its comments give.
func _stand_up() -> GameView:
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
	while view.game.state.grids.size() < 3:
		Board.add_grid(view.game.state, GridData.new())
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
