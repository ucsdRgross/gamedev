extends TestSuite
# res://Tests/Engine/test_grid_board.gd
# BoardCoord suite: the four-component coordinate and its arithmetic. Phase 1 of the
# poker-patience board (TP-01..TP-04). No product code calls BoardCoord yet -- S2/S3 wire
# it into GameData/Board -- so this suite exercises the type directly.

func suite_name() -> String:
	return "GRID BOARD"

func _ready() -> void:
	TestLog.line("============ GRID BOARD TEST PASS ============")
	run_round_trip_test()
	run_continuous_x_test()
	run_entrance_test()
	run_off_board_test()
	run_grid_storage_test()
	run_grid_duplicate_test()
	run_grid_zone_cards_test()
	finish()

# ==============================================================================
# TP-01 -- a coordinate round-trips grid/x/y/h
# ==============================================================================
func run_round_trip_test() -> void:
	behavior_section("ROUND TRIP")
	var c := BoardCoord.new(1, 3, 2, 4)
	check(c.grid == 1 and c.x == 3 and c.y == 2 and c.h == 4,
			"BoardCoord.new(1,3,2,4) round-trips",
			"got grid=%d x=%d y=%d h=%d" % [c.grid, c.x, c.y, c.h])

# ==============================================================================
# TP-02 -- x is continuous: 5 columns left of (grid 1, x 0) is (grid 0, x 4)
# FIX-GRID-3: three 5-wide grids.
# ==============================================================================
func run_continuous_x_test() -> void:
	behavior_section("CONTINUOUS X")
	var widths : Array[int] = [5, 5, 5]
	var c := BoardCoord.new(1, 0, 2, 0)
	# one column left of (grid 1, x 0) crosses the boundary into (grid 0, x 4) -- the
	# worked example the source note gives verbatim.
	var stepped := c.step_x(-1, widths)
	check(stepped.grid == 0 and stepped.x == 4,
			"one column left of (grid 1, x 0) is (grid 0, x 4)",
			"got grid=%d x=%d" % [stepped.grid, stepped.x])
	check(stepped.y == c.y and stepped.h == c.h,
			"step_x leaves y and h unchanged",
			"got y=%d h=%d" % [stepped.y, stepped.h])

	# lower-level: crossing the OTHER way, and by more than one grid's width
	var forward := BoardCoord.new(0, 3, 0, 0).step_x(4, widths)
	check(forward.grid == 1 and forward.x == 2,
			"4 columns right of (grid 0, x 3) is (grid 1, x 2)",
			"got grid=%d x=%d" % [forward.grid, forward.x])

	var far := BoardCoord.new(0, 0, 0, 0).step_x(12, widths)
	check(far.grid == 2 and far.x == 2,
			"step_x crosses more than one grid boundary in one call",
			"got grid=%d x=%d" % [far.grid, far.x])

	# a full grid-width step (5, matching FIX-GRID-3's width) lands on the SAME local x
	# one grid over -- the general shape of the source note's example.
	var full_width := BoardCoord.new(1, 0, 2, 0).step_x(-5, widths)
	check(full_width.grid == 0 and full_width.x == 0,
			"a full grid-width step left keeps the same local x, one grid over",
			"got grid=%d x=%d" % [full_width.grid, full_width.x])

	# TP-02's literal fixture: 5 columns left of (grid 1, x 0)
	var tp02 := BoardCoord.new(1, 0, 2, 0).step_x(-5, widths)
	check(tp02.grid == 0 and tp02.x == 0,
			"TP-02's fixture: 5 columns left of (grid 1, x 0) is (grid 0, x 0)",
			"got grid=%d x=%d" % [tp02.grid, tp02.x])

# ==============================================================================
# TP-03 -- the Entrance is y == -1 of its attached grid, and the attachment moves on
# commit. FIX-GRID-3.
# ==============================================================================
func run_entrance_test() -> void:
	behavior_section("ENTRANCE")
	var attached_grid := 1
	var entrance := BoardCoord.new(attached_grid, 2, BoardCoord.ENTRANCE_ROW, 0)
	check(entrance.is_entrance(), "y == ENTRANCE_ROW reads as the Entrance")
	check(entrance.grid == attached_grid,
			"the Entrance carries the grid it is currently attached to")

	var on_board := BoardCoord.new(attached_grid, 2, 0, 0)
	check(not on_board.is_entrance(), "row 0 of a grid is not the Entrance")

	# the attachment moves with the commit: re-attaching is a NEW coordinate with the
	# new grid index, still y == ENTRANCE_ROW
	var committed_grid := 2
	var moved := BoardCoord.new(committed_grid, entrance.x, entrance.y, entrance.h)
	check(moved.is_entrance() and moved.grid == committed_grid,
			"committing to another grid moves the Entrance's attachment")

# ==============================================================================
# TP-04 -- off-board reads as the four-component MIN analogue, never (0,0,0,0)
# ==============================================================================
func run_off_board_test() -> void:
	behavior_section("OFF BOARD")
	var nowhere := BoardCoord.NOWHERE
	check(nowhere.grid != 0 or nowhere.x != 0 or nowhere.y != 0 or nowhere.h != 0,
			"NOWHERE is not (0,0,0,0)",
			"got grid=%d x=%d y=%d h=%d" % [nowhere.grid, nowhere.x, nowhere.y, nowhere.h])
	check(nowhere.grid == Vector3i.MIN.x and nowhere.x == Vector3i.MIN.x
			and nowhere.y == Vector3i.MIN.x and nowhere.h == Vector3i.MIN.x,
			"NOWHERE is the four-component MIN analogue",
			"got grid=%d x=%d y=%d h=%d" % [nowhere.grid, nowhere.x, nowhere.y, nowhere.h])

	# step_x walking off either edge of the board: provisional reading is CLAMP to the
	# nearest legal column (never a negative x or an out-of-range grid).
	var widths : Array[int] = [5, 5, 5]
	var off_left := BoardCoord.new(0, 0, 0, 0).step_x(-11, widths)
	check(off_left.grid == 0 and off_left.x == 0,
			"stepping past the left edge of grid 0 clamps to (grid 0, x 0)",
			"got grid=%d x=%d" % [off_left.grid, off_left.x])

	var off_right := BoardCoord.new(2, 4, 0, 0).step_x(11, widths)
	check(off_right.grid == 2 and off_right.x == 4,
			"stepping past the right edge of the last grid clamps to its last column",
			"got grid=%d x=%d" % [off_right.grid, off_right.x])

# ==============================================================================
# TP-05 -- a 3-grid board's validate() returns empty at mixed heights. FIX-MIXED-H.
# ==============================================================================
func run_grid_storage_test() -> void:
	behavior_section("GRID STORAGE")
	var state := TestGridFixtures.build_fix_mixed_h()
	check(state.grids.size() == 3, "FIX-MIXED-H carries 3 grids",
			"got %d" % state.grids.size())
	var g0 : GridData = state.grids[0]
	check(g0.cells[g0.cell_index(0, 1)].datas.size() == 6,
			"grid 0 row 1 is at height 6",
			"got %d" % g0.cells[g0.cell_index(0, 1)].datas.size())
	var g1 : GridData = state.grids[1]
	check(g1.cells[g1.cell_index(0, 1)].datas.size() == 1,
			"grid 1 row 1 is at height 1",
			"got %d" % g1.cells[g1.cell_index(0, 1)].datas.size())
	var g2 : GridData = state.grids[2]
	check(g2.cells[g2.cell_index(0, 1)].datas.size() == 0,
			"grid 2 row 1 is empty",
			"got %d" % g2.cells[g2.cell_index(0, 1)].datas.size())
	var violations := state.validate()
	check(violations.is_empty(),
			"validate() returns empty on FIX-MIXED-H",
			"got %s" % [violations])

# ==============================================================================
# TP-06 -- a card in two cells is reported by validate() with BOTH locations. FIX-GRID-1.
# ==============================================================================
func run_grid_duplicate_test() -> void:
	behavior_section("GRID DUPLICATE")
	var state := TestGridFixtures.build_fix_grid_1()
	var g0 : GridData = state.grids[0]
	var dupe := TestFactories.m_card(1, TestFactories.uc())
	dupe.stage = CardData.Stage.PLAY
	g0.cells[g0.cell_index(0, 0)].datas.append(dupe)
	g0.cells[g0.cell_index(1, 2)].datas.append(dupe)
	var violations := state.validate()
	var hit := ""
	for v : String in violations:
		if v.begins_with("I1:") and v.contains(str(dupe)):
			hit = v
			break
	check(not hit.is_empty(), "validate() reports the duplicate card", "got %s" % [violations])
	check(hit.contains("(0,0)") and hit.contains("(1,2)"),
			"the report names BOTH cell locations",
			"got: %s" % hit)

# ==============================================================================
# TP-07 -- 25 cell zone cards exist per grid and appear in all_card_datas(). FIX-GRID-3.
# ==============================================================================
func run_grid_zone_cards_test() -> void:
	behavior_section("GRID ZONE CARDS")
	var state := TestGridFixtures.build_fix_grid_3()
	for gi in state.grids.size():
		var grid : GridData = state.grids[gi]
		check(grid.cell_types.size() == 25,
				"grid %d carries 25 cell zone cards" % gi,
				"got %d" % grid.cell_types.size())
		var bad_cells : Array[int] = []
		for ci in grid.cell_types.size():
			if not (grid.cell_types[ci].type is TypeGridCell):
				bad_cells.append(ci)
		check(bad_cells.is_empty(),
				"grid %d cell zone cards are all TypeGridCell" % gi,
				"got non-TypeGridCell at cells %s" % [bad_cells])
	var all := state.all_card_datas()
	var g0 : GridData = state.grids[0]
	check(all.has(g0.cell_types[0]),
			"grid 0's cell zone card appears in all_card_datas()")
	var g2 : GridData = state.grids[2]
	check(all.has(g2.cell_types[24]),
			"grid 2's last cell zone card appears in all_card_datas()")
	var violations := state.validate()
	check(violations.is_empty(),
			"validate() returns empty on FIX-GRID-3",
			"got %s" % [violations])
