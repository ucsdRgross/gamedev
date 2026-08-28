extends TestSuite
# res://Tests/UI/test_grid_layout.gd
# ==============================================================================
# S20b — THE GRID BOARD IS DRAWN. Phase 5's first view step: the play area builds one panel per
# grid, one slot per cell, and a real control and CardVisual for every card on a grid.
#
# WHY THIS SUITE EXISTS AT ALL. Every Phase 1-4 and Phase 8 test is headless by design, and that
# is the right call — but it means the engine shipped a complete, tested board that NOTHING
# DREW, and no suite could see it. `grids` did not appear in `UI/play_area.gd` at all
# (design/poker-patience/gaps/GAP-009.md). These checks are the ones that would have caught it.
#
# CATEGORY MAP: BEHAVIOR — a card on a grid has a control, a visual and a position is what the
# player experiences as "the board exists". IMPLEMENTATION pins: the cell count comes from the
# data, and the panels are in lockstep with the grid list.
#
# ⚠ NONE OF THIS IS EVIDENCE ABOUT PIXELS (repo rule 4). It proves the tree and the numbers; a
# rendered snapshot signed off by eye is what proves the board LOOKS right.
# ==============================================================================

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")

var _prev_run : RunState
var _prev_save_info : RunState

func suite_name() -> String:
	return "GRID LAYOUT"

func _ready() -> void:
	TestLog.line("============ GRID LAYOUT TEST PASS ============")
	check_all_tests_registered()
	await run_a_panel_per_grid_and_a_slot_per_cell_test()
	await run_a_placed_card_has_a_control_a_visual_and_a_position_test()
	await run_every_grid_sits_on_the_same_floor_test()
	finish()

## A real GameView on the frozen 52-card deck: one grid, dealt Entrance, nothing crafted.
func _stand_up() -> GameView:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	seed(20260828)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	# ⚠ RE-ASSERT IT. The PREVIOUS test's Game nulls CardEnvironment.CURRENT from its own
	# _exit_tree, and queue_free lands whenever the frame ends -- which can be AFTER this view's
	# Game entered the tree and set it. A null CURRENT makes PlayArea.set_card_zones return
	# immediately and do nothing, so the board silently stops rebuilding and every check here
	# reads a stale control tree.
	CardEnvironment.CURRENT = view.game
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

## The cell grid inside grid `gi`'s panel.
func _cell_grid(pa: PlayArea, gi: int) -> GridContainer:
	var panel : Control = pa.grid_container.get_child(gi)
	return panel.get_child(0) as GridContainer

# ==============================================================================
# TP-80b — one panel per grid, and a slot per cell, sized FROM THE DATA.
# ==============================================================================
func run_a_panel_per_grid_and_a_slot_per_cell_test() -> void:
	behavior_section("A PANEL PER GRID AND A SLOT PER CELL")
	var view := await _stand_up()
	var pa := view.play_area
	pa.flush_rebuild()
	await get_tree().process_frame
	var grids : Array[GridData] = view.game.state.grids

	check(grids.size() > 0, "precondition: the show built at least one grid",
			"%d grids" % grids.size())
	check(pa.grid_container.get_child_count() == grids.size(),
			"the board has exactly one panel per grid",
			"%d panels vs %d grids" % [pa.grid_container.get_child_count(), grids.size()])

	var grid : GridData = grids[0]
	var cells := _cell_grid(pa, 0)
	# ⚠ Compared against the DATA's own width and height, never against 5. A grid carries its
	# own size and a later card could make one a different shape; a check written against 5
	# would pass today and silently stop describing the board the day that happens.
	check(cells.columns == grid.grid_width,
			"the cell grid is as wide as the DATA says, not a hard-coded 5",
			"%d columns vs grid_width %d" % [cells.columns, grid.grid_width])
	check(cells.get_child_count() == grid.cells.size(),
			"there is exactly one cell slot per cell in the data",
			"%d slots vs %d cells" % [cells.get_child_count(), grid.cells.size()])
	await _tear_down(view)

# ==============================================================================
# TP-80c — THE CHECK GAP-009 WOULD HAVE FAILED. A card on a grid is a card the player can see.
# ==============================================================================
func run_a_placed_card_has_a_control_a_visual_and_a_position_test() -> void:
	behavior_section("A PLACED CARD HAS A CONTROL, A VISUAL AND A POSITION")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var coord := BoardCoord.new(0, 2, 3, 0)
	var placed : CardData = g.state.upper_zone[0].datas[0]
	await g.place_card_in_grid(placed, coord)
	pa.flush_rebuild()
	await get_tree().process_frame
	await get_tree().process_frame

	check(g.state.card_at(coord) == placed, "precondition: the card is in the cell")
	var control : Control = pa.data_ui.get(placed)
	check(control != null, "the placed card has a board control")
	var visual : CardVisual = pa.data_card.get(placed)
	check(visual != null and is_instance_valid(visual),
			"the placed card has a CardVisual in the card layer")
	if control:
		# Inside the panel, not left in some legacy zone: walk up to the cell grid.
		var slot : Node = control.get_parent()
		check(slot != null and slot.get_parent() == _cell_grid(pa, 0),
				"...and its control lives in grid 0's cell grid",
				str(slot.get_parent().name) if slot and slot.get_parent() else "<none>")
	if visual and is_instance_valid(visual):
		check(visual.global_position != Vector2.ZERO,
				"...and the visual has a real position on screen, not the origin",
				str(visual.global_position))
	await _tear_down(view)

# ==============================================================================
# TP-80g — every grid sits on the same floor. With cross-grid row alignment OFF (the default)
# the rows do NOT line up, and the bottom edges are the only thing that does.
# ==============================================================================
func run_every_grid_sits_on_the_same_floor_test() -> void:
	behavior_section("EVERY GRID SITS ON THE SAME FLOOR")
	var view := await _stand_up()
	var pa := view.play_area
	pa.flush_rebuild()
	await get_tree().process_frame
	var panels := pa.grid_container.get_child_count()
	if panels < 2:
		check(true, "only one grid in this show — nothing to align against",
				"%d panels" % panels)
		await _tear_down(view)
		return
	var floor_y : float = (pa.grid_container.get_child(0) as Control).get_global_rect().end.y
	var worst := 0.0
	for gi : int in range(1, panels):
		var rect := (pa.grid_container.get_child(gi) as Control).get_global_rect()
		worst = maxf(worst, absf(rect.end.y - floor_y))
	check(worst < 1.0, "every grid's bottom edge sits on the same floor",
			"worst %.2f px off" % worst)
	await _tear_down(view)
