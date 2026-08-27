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
	run_position_index_test()
	run_reverse_index_test()
	run_place_in_cell_test()
	run_stack_anchor_test()
	run_remove_compaction_test()
	run_compaction_single_bump_test()
	run_compaction_flag_test()
	run_has_cell_test()
	run_row_line_test()
	run_col_line_test()
	run_diag_line_test()
	run_height_line_test()
	run_height_taller_stack_test()
	run_diag_no_grid_crossing_test()
	run_3d_diag_family_test()
	run_height_v_line_test()
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
	var stepped := c.step(-1, 0, widths)
	check(stepped.grid == 0 and stepped.x == 4,
			"one column left of (grid 1, x 0) is (grid 0, x 4)",
			"got grid=%d x=%d" % [stepped.grid, stepped.x])
	check(stepped.y == c.y and stepped.h == c.h,
			"step leaves y and h unchanged when dy is 0",
			"got y=%d h=%d" % [stepped.y, stepped.h])

	# lower-level: crossing the OTHER way, and by more than one grid's width
	var forward := BoardCoord.new(0, 3, 0, 0).step(4, 0, widths)
	check(forward.grid == 1 and forward.x == 2,
			"4 columns right of (grid 0, x 3) is (grid 1, x 2)",
			"got grid=%d x=%d" % [forward.grid, forward.x])

	var far := BoardCoord.new(0, 0, 0, 0).step(12, 0, widths)
	check(far.grid == 2 and far.x == 2,
			"step crosses more than one grid boundary in one call",
			"got grid=%d x=%d" % [far.grid, far.x])

	# a full grid-width step (5, matching FIX-GRID-3's width) lands on the SAME local x
	# one grid over -- the general shape of the source note's example.
	var full_width := BoardCoord.new(1, 0, 2, 0).step(-5, 0, widths)
	check(full_width.grid == 0 and full_width.x == 0,
			"a full grid-width step left keeps the same local x, one grid over",
			"got grid=%d x=%d" % [full_width.grid, full_width.x])

	# TP-02's literal fixture: 5 columns left of (grid 1, x 0)
	var tp02 := BoardCoord.new(1, 0, 2, 0).step(-5, 0, widths)
	check(tp02.grid == 0 and tp02.x == 0,
			"TP-02's fixture: 5 columns left of (grid 1, x 0) is (grid 0, x 0)",
			"got grid=%d x=%d" % [tp02.grid, tp02.x])

	# two-axis step: dx and dy together
	var diag := BoardCoord.new(0, 3, 2, 0).step(3, 4, widths)
	check(diag.grid == 1 and diag.x == 1 and diag.y == 6,
			"a two-axis step moves x across a grid boundary and y at the same time",
			"got grid=%d x=%d y=%d" % [diag.grid, diag.x, diag.y])

	# a step across grids of DIFFERENT widths proves nothing hard-codes 5
	var uneven : Array[int] = [5, 6, 5]
	var uneven_step := BoardCoord.new(0, 4, 0, 0).step(2, 0, uneven)
	check(uneven_step.grid == 1 and uneven_step.x == 1,
			"a step across grids of different widths lands using each grid's own width",
			"got grid=%d x=%d" % [uneven_step.grid, uneven_step.x])
	var uneven_step2 := BoardCoord.new(1, 5, 0, 0).step(1, 0, uneven)
	check(uneven_step2.grid == 2 and uneven_step2.x == 0,
			"stepping off the end of the wider middle grid lands at the start of the next",
			"got grid=%d x=%d" % [uneven_step2.grid, uneven_step2.x])

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

	# step walking off either edge of the board NEVER clamps and NEVER returns NOWHERE: it
	# lands on the virtual continuation, stepping at the width of the nearest real edge grid.
	var widths : Array[int] = [5, 5, 5]
	var off_left := BoardCoord.new(0, 0, 0, 0).step(-11, 0, widths)
	check(off_left.grid == -3 and off_left.x == 4,
			"stepping 11 past the left edge of grid 0 lands on virtual grid -3, x 4",
			"got grid=%d x=%d" % [off_left.grid, off_left.x])

	var off_right := BoardCoord.new(2, 4, 0, 0).step(11, 0, widths)
	check(off_right.grid == 5 and off_right.x == 0,
			"stepping 11 past the right edge of the last grid lands on virtual grid 5, x 0",
			"got grid=%d x=%d" % [off_right.grid, off_right.x])

	# a y step past the bottom of a grid lands virtually too (no y clamp)
	var off_bottom := BoardCoord.new(0, 0, 0, 0).step(0, -3, widths)
	check(off_bottom.grid == 0 and off_bottom.x == 0 and off_bottom.y == -3,
			"a y step below row 0 is not clamped either",
			"got grid=%d x=%d y=%d" % [off_bottom.grid, off_bottom.x, off_bottom.y])

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

# ==============================================================================
# TP-08 -- position_of()/card_at() are O(1) and rebuild only when revision moved.
# FIX-MIXED-H. Legacy position_of() has no legacy-zone cards to read on this fixture (only
# grids are stocked), so the caching contract is exercised through card_at() -- the S3
# grid-side index shares the SAME revision-gated rebuild as the legacy one.
# ==============================================================================
func run_position_index_test() -> void:
	behavior_section("POSITION INDEX")
	var state := TestGridFixtures.build_fix_mixed_h()
	var g1 : GridData = state.grids[1]
	var known_card : CardData = g1.cells[g1.cell_index(0, 1)].datas[0]
	var coord := BoardCoord.new(1, 0, 1, 0)
	check(state.card_at(coord) == known_card,
			"card_at() finds the known card at grid 1 row 1 height 0",
			"got %s" % state.card_at(coord))

	# mutate a cell directly WITHOUT bumping revision -- the index must NOT reflect this
	# until revision moves, proving the rebuild is gated on revision, not on every call.
	var intruder := TestFactories.m_card(1, TestFactories.uc())
	intruder.stage = CardData.Stage.PLAY
	var g2 : GridData = state.grids[2]
	g2.cells[g2.cell_index(0, 1)].datas.append(intruder)
	var g2_coord := BoardCoord.new(2, 0, 1, 0)
	check(state.card_at(g2_coord) == null,
			"card_at() still reads the pre-mutation index before revision moves",
			"got %s" % state.card_at(g2_coord))

	state.revision += 1
	check(state.card_at(g2_coord) == intruder,
			"card_at() rebuilds once revision moves and finds the new card",
			"got %s" % state.card_at(g2_coord))

# ==============================================================================
# TP-09 -- the reverse index (card_at) agrees with the grid-side forward index after every
# mutation kind: a place, a move and a removal. FIX-MIXED-H. S4's mutation API does not
# exist yet, so the fixture is driven directly, bumping revision after each mutation the
# same way Board.* does today.
# ==============================================================================
func run_reverse_index_test() -> void:
	behavior_section("REVERSE INDEX")
	var state := TestGridFixtures.build_fix_mixed_h()
	var g0 : GridData = state.grids[0]

	# PLACE: a new card into an empty cell.
	var placed := TestFactories.m_card(1, TestFactories.uc())
	placed.stage = CardData.Stage.PLAY
	g0.cells[g0.cell_index(2, 3)].datas.append(placed)
	state.revision += 1
	check(state.card_at(BoardCoord.new(0, 2, 3, 0)) == placed,
			"after a place, card_at() finds the new card at its cell",
			"got %s" % state.card_at(BoardCoord.new(0, 2, 3, 0)))
	check(state.validate().is_empty(),
			"validate() reports no I4 violation after a place",
			"got %s" % [state.validate()])

	# MOVE: relocate the same card to a different cell.
	g0.cells[g0.cell_index(2, 3)].datas.erase(placed)
	g0.cells[g0.cell_index(4, 4)].datas.append(placed)
	state.revision += 1
	check(state.card_at(BoardCoord.new(0, 2, 3, 0)) == null,
			"after a move, the old cell reads empty",
			"got %s" % state.card_at(BoardCoord.new(0, 2, 3, 0)))
	check(state.card_at(BoardCoord.new(0, 4, 4, 0)) == placed,
			"after a move, the new cell reads the moved card",
			"got %s" % state.card_at(BoardCoord.new(0, 4, 4, 0)))
	check(state.validate().is_empty(),
			"validate() reports no I4 violation after a move",
			"got %s" % [state.validate()])

	# REMOVE: take the card off the board entirely.
	g0.cells[g0.cell_index(4, 4)].datas.erase(placed)
	state.revision += 1
	check(state.card_at(BoardCoord.new(0, 4, 4, 0)) == null,
			"after a removal, the cell reads empty",
			"got %s" % state.card_at(BoardCoord.new(0, 4, 4, 0)))
	check(state.validate().is_empty(),
			"validate() reports no I4 violation after a removal",
			"got %s" % [state.validate()])

# ==============================================================================
# TP-10 -- place_in_cell into an empty cell bumps revision exactly once. FIX-GRID-1.
# ==============================================================================
func run_place_in_cell_test() -> void:
	behavior_section("PLACE IN CELL")
	var state := TestGridFixtures.build_fix_grid_1()
	var before := state.revision
	var card := TestFactories.m_card(1, TestFactories.uc())
	var ok := Board.place_in_cell(state, card, BoardCoord.new(0, 0, 0, 0))
	check(ok, "place_in_cell into an empty cell succeeds")
	check(state.revision == before + 1,
			"place_in_cell bumps revision exactly once",
			"got %d, expected %d" % [state.revision, before + 1])
	check(state.card_at(BoardCoord.new(0, 0, 0, 0)) == card,
			"the placed card is found at (0,0,0)")
	check(state.validate().is_empty(),
			"validate() returns empty after the placement",
			"got %s" % [state.validate()])

# ==============================================================================
# TP-11 -- stacking uses Anchor.ON_TOP and lands at h+1. FIX-STACK-5 (cell (0,0) already
# holds 4 cards).
# ==============================================================================
func run_stack_anchor_test() -> void:
	behavior_section("STACK ANCHOR")
	var state := TestGridFixtures.build_fix_stack_5()
	var card := TestFactories.m_card(1, TestFactories.uc())
	var ok := Board.place_in_cell(state, card, BoardCoord.new(0, 0, 0, 0))
	check(ok, "the 5th card stacks onto cell (0,0)")
	check(state.card_at(BoardCoord.new(0, 0, 0, 4)) == card,
			"it lands at h=4 -- ON_TOP of the existing 4 cards (h+1)",
			"got %s" % state.card_at(BoardCoord.new(0, 0, 0, 4)))
	check(state.validate().is_empty(),
			"validate() returns empty after stacking",
			"got %s" % [state.validate()])

# ==============================================================================
# TP-12 -- removing from mid-stack compacts the cards above down. FIX-STACK-5.
# ==============================================================================
func run_remove_compaction_test() -> void:
	behavior_section("REMOVE COMPACTION")
	var state := TestGridFixtures.build_fix_stack_5()
	var grid : GridData = state.grids[0]
	var cell : ArrayCardData = grid.cells[grid.cell_index(0, 0)]
	var mid_card : CardData = cell.datas[1]     #h=1 of 4 (h=0..3)
	var top_card : CardData = cell.datas[3]     #was h=3, must land at h=2
	var ok := Board.remove_from_cell(state, mid_card)
	check(ok, "remove_from_cell removes the mid-stack card")
	check(state.card_at(BoardCoord.new(0, 0, 0, 1)) != mid_card,
			"the removed card no longer occupies its old height")
	check(state.card_at(BoardCoord.new(0, 0, 0, 2)) == top_card,
			"the card above it compacts down by one height",
			"got %s" % state.card_at(BoardCoord.new(0, 0, 0, 2)))
	check(cell.datas.size() == 3, "the stack is now 3 tall", "got %d" % cell.datas.size())
	check(state.validate().is_empty(),
			"validate() returns empty after the compaction",
			"got %s" % [state.validate()])

# ==============================================================================
# TP-13 -- a compaction bumps revision ONCE for the whole compaction. FIX-STACK-10 (9
# cards; removing the bottom one compacts 8 cards down in one mutation).
# ==============================================================================
func run_compaction_single_bump_test() -> void:
	behavior_section("COMPACTION SINGLE BUMP")
	var state := TestGridFixtures.build_fix_stack_10()
	var grid : GridData = state.grids[0]
	var cell : ArrayCardData = grid.cells[grid.cell_index(0, 0)]
	var bottom_card : CardData = cell.datas[0]
	var before := state.revision
	var ok := Board.remove_from_cell(state, bottom_card)
	check(ok, "remove_from_cell removes the bottom card of a 9-tall stack")
	check(state.revision == before + 1,
			"one revision bump covers the whole 8-card compaction, not one per card",
			"got %d, expected %d" % [state.revision, before + 1])
	check(cell.datas.size() == 8, "the stack is now 8 tall", "got %d" % cell.datas.size())
	check(state.validate().is_empty(),
			"validate() returns empty after the compaction",
			"got %s" % [state.validate()])

# ==============================================================================
# TP-14 -- a compaction move carries the compaction flag; a placement does not.
# is_compaction is set BY THE CALLER, never inferred from before/after heights.
# FIX-STACK-5.
# ==============================================================================
func run_compaction_flag_test() -> void:
	behavior_section("COMPACTION FLAG")
	var state := TestGridFixtures.build_fix_stack_5()
	var grid : GridData = state.grids[0]
	var cell : ArrayCardData = grid.cells[grid.cell_index(0, 0)]
	var card : CardData = cell.datas[0]

	var compaction_res := Board.move_to_cell(state, card, BoardCoord.new(0, 1, 0, 0), true)
	check(compaction_res.ok, "move_to_cell moves a card already on the grid board")
	check(compaction_res.is_compaction,
			"a caller-declared compaction move carries is_compaction == true")

	var plain_res := Board.move_to_cell(state, card, BoardCoord.new(0, 2, 0, 0), false)
	check(plain_res.ok, "a second move_to_cell call also succeeds")
	check(not plain_res.is_compaction,
			"a caller-declared non-compaction move carries is_compaction == false")

	var new_card := TestFactories.m_card(1, TestFactories.uc())
	var place_ok := Board.place_in_cell(state, new_card, BoardCoord.new(0, 3, 0, 0))
	check(place_ok, "place_in_cell succeeds for a fresh card")
	check(state.validate().is_empty(),
			"validate() returns empty after the moves and the placement",
			"got %s" % [state.validate()])

# ==============================================================================
# has_cell -- the landing question a step's result asks separately from moving.
# ==============================================================================
func run_has_cell_test() -> void:
	behavior_section("HAS CELL")
	var state := TestGridFixtures.build_fix_grid_1()
	check(state.has_cell(BoardCoord.new(0, 2, 2, 0)),
			"has_cell is true for a real cell of a real grid")

	check(not state.has_cell(BoardCoord.new(-1, 4, 0, 0)),
			"has_cell is false for a virtual off-edge grid index")
	check(not state.has_cell(BoardCoord.new(0, 5, 0, 0)),
			"has_cell is false for an x outside the grid's own bounds")
	check(not state.has_cell(BoardCoord.new(0, 0, -1, 0)),
			"has_cell is false for a y outside the grid's own bounds")

	# a ragged/hole grid: cells is shorter than grid_width * grid_height, representing
	# missing cells at the tail of the row-major array.
	var ragged : GridData = state.grids[0]
	ragged.cells.resize(ragged.cells.size() - 1)
	var hole_index := ragged.cell_index(4, 4)
	check(hole_index >= ragged.cells.size(),
			"the hole sits at the truncated tail of the row-major cell array")
	check(not state.has_cell(BoardCoord.new(0, 4, 4, 0)),
			"has_cell is false for a coordinate inside a real grid's block with no cell there")

# ==============================================================================
# Helpers for the line-geometry section below.
# ==============================================================================
func _lines_of_kind(lines: Array, kind: ScoringSection.LineKind) -> Array:
	var out : Array = []
	for line : LineGeometry.Line in lines:
		if line.kind == kind: out.append(line)
	return out

func _cells_occupied(grid_idx: int, state: GameData, cells: Array[Vector3i]) -> bool:
	for c : Vector3i in cells:
		if state.card_at(BoardCoord.new(grid_idx, c.x, c.y, c.z)) == null:
			return false
	return true

# ==============================================================================
# TP-18 -- a row completes and is detected. FIX-ROW-FLUSH.
# ==============================================================================
func run_row_line_test() -> void:
	behavior_section("ROW LINE")
	var state := TestGridFixtures.build_fix_row_flush()
	var grid : GridData = state.grids[0]
	var lines := LineGeometry.lines_through(grid, 0, 0, 0)
	var rows := _lines_of_kind(lines, ScoringSection.LineKind.ROW)
	check(rows.size() == 1, "exactly one ROW line runs through (0,0,0)",
			"got %d" % rows.size())
	var row : LineGeometry.Line = rows[0]
	check(row.cells.size() == grid.grid_width,
			"the ROW line spans the grid's own width", "got %d" % row.cells.size())
	check(_cells_occupied(0, state, row.cells),
			"every cell of FIX-ROW-FLUSH's row 0 is occupied -- the row completes")

# ==============================================================================
# TP-19 -- a column completes and is detected. FIX-GRID-1, column 2 filled by hand.
# ==============================================================================
func run_col_line_test() -> void:
	behavior_section("COL LINE")
	var state := TestGridFixtures.build_fix_grid_1()
	var grid : GridData = state.grids[0]
	for y in grid.grid_height:
		var card := TestFactories.m_card(1, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		Board.place_in_cell(state, card, BoardCoord.new(0, 2, y, 0))

	var lines := LineGeometry.lines_through(grid, 2, 3, 0)
	var cols := _lines_of_kind(lines, ScoringSection.LineKind.COL)
	check(cols.size() == 1, "exactly one COL line runs through (2,3,0)",
			"got %d" % cols.size())
	var col : LineGeometry.Line = cols[0]
	check(col.cells.size() == grid.grid_height,
			"the COL line spans the grid's own height", "got %d" % col.cells.size())
	check(_cells_occupied(0, state, col.cells),
			"every cell of the filled column 2 is occupied -- the column completes")

# ==============================================================================
# TP-20 -- both main diagonals are detected; no broken or wrapped diagonal is.
# FIX-TRIPLE.
# ==============================================================================
func run_diag_line_test() -> void:
	behavior_section("DIAG LINE")
	var state := TestGridFixtures.build_fix_triple()
	var grid : GridData = state.grids[0]
	var lines := LineGeometry.lines_through(grid, 2, 2, 0)
	var flat_diags : Array = []
	for line : LineGeometry.Line in _lines_of_kind(lines, ScoringSection.LineKind.DIAG):
		if line.cells[0].z == line.cells[line.cells.size() - 1].z:
			flat_diags.append(line)
	check(flat_diags.size() == 2,
			"both main diagonals are found through the shared centre cell (2,2)",
			"got %d" % flat_diags.size())
	for diag : LineGeometry.Line in flat_diags:
		check(diag.cells.size() == grid.grid_width,
				"a flat diagonal is full grid width", "got %d" % diag.cells.size())
		check(_cells_occupied(0, state, diag.cells),
				"FIX-TRIPLE's filled diagonal is fully occupied -- it completes")

	# No broken diagonal: a cell off both main diagonals of a 5x5 grid finds none.
	var off_lines := LineGeometry.lines_through(grid, 0, 1, 0)
	var off_flat_diags : Array = []
	for line : LineGeometry.Line in _lines_of_kind(off_lines, ScoringSection.LineKind.DIAG):
		if line.cells[0].z == line.cells[line.cells.size() - 1].z:
			off_flat_diags.append(line)
	check(off_flat_diags.is_empty(),
			"a cell off both main diagonals finds no broken/wrapped diagonal",
			"got %d" % off_flat_diags.size())

# ==============================================================================
# TP-21 -- a horizontal line at height 2 is detected when every cell has a card at 2.
# FIX-LEVEL-3.
# ==============================================================================
func run_height_line_test() -> void:
	behavior_section("HEIGHT LINE")
	var state := TestGridFixtures.build_fix_level_3()
	var grid : GridData = state.grids[0]
	var lines := LineGeometry.lines_through(grid, 0, 0, 2)
	var rows := _lines_of_kind(lines, ScoringSection.LineKind.ROW)
	check(rows.size() == 1, "exactly one ROW line runs through height 2",
			"got %d" % rows.size())
	var row : LineGeometry.Line = rows[0]
	check(_cells_occupied(0, state, row.cells),
			"every cell of FIX-LEVEL-3's row 0 has a card at height 2 -- it completes")

# ==============================================================================
# TP-22 -- a cell taller than h still counts toward the line at h. FIX-LEVEL-3, with one
# cell built taller by hand.
# ==============================================================================
func run_height_taller_stack_test() -> void:
	behavior_section("HEIGHT TALLER STACK")
	var state := TestGridFixtures.build_fix_level_3()
	var grid : GridData = state.grids[0]
	var tall_idx := grid.cell_index(0, 0)
	var extra := TestFactories.m_card(1, TestFactories.uc())
	extra.stage = CardData.Stage.PLAY
	grid.cells[tall_idx].datas.append(extra)
	state.invalidate_pos_index()
	check(grid.cells[tall_idx].datas.size() == 4,
			"cell (0,0) is now taller than the rest of row 0", "got %d" % grid.cells[tall_idx].datas.size())

	var lines := LineGeometry.lines_through(grid, 0, 0, 2)
	var row : LineGeometry.Line = _lines_of_kind(
			lines, ScoringSection.LineKind.ROW)[0]
	check(_cells_occupied(0, state, row.cells),
			"the taller cell still has a card at height 2, so the row at h=2 still completes")

# ==============================================================================
# TP-23 -- no line crosses a grid boundary. FIX-GRID-3.
# ==============================================================================
func run_diag_no_grid_crossing_test() -> void:
	behavior_section("NO GRID CROSSING")
	var state := TestGridFixtures.build_fix_grid_3()
	var grid0 : GridData = state.grids[0]
	var lines := LineGeometry.lines_through(grid0, 4, 0, 0)
	var row : LineGeometry.Line = _lines_of_kind(
			lines, ScoringSection.LineKind.ROW)[0]
	for c : Vector3i in row.cells:
		check(c.x >= 0 and c.x < grid0.grid_width,
				"the ROW line through the grid's rightmost column never reaches into grid 1",
				"got x=%d" % c.x)
	var col_lines := LineGeometry.lines_through(grid0, 4, 4, 0)
	var col : LineGeometry.Line = _lines_of_kind(
			col_lines, ScoringSection.LineKind.COL)[0]
	for c : Vector3i in col.cells:
		check(c.y >= 0 and c.y < grid0.grid_height,
				"the COL line stays within its own grid's height",
				"got y=%d" % c.y)

# ==============================================================================
# TP-24 -- 3-D diagonals in the full family are detected. FIX-LEVEL-3, queried at its
# grid's own centre cell, where all eight climbing directions fit.
# ==============================================================================
func run_3d_diag_family_test() -> void:
	behavior_section("3D DIAG FAMILY")
	var state := TestGridFixtures.build_fix_level_3()
	var grid : GridData = state.grids[0]
	var lines := LineGeometry.lines_through(grid, 2, 2, 2)
	var climbing_dirs : Array[Vector3i] = []
	for line : LineGeometry.Line in _lines_of_kind(lines, ScoringSection.LineKind.DIAG):
		var step := line.cells[1] - line.cells[0]
		if step.z != 0: climbing_dirs.append(step)

	var expected : Array[Vector3i] = [
		Vector3i(1, 0, 1), Vector3i(-1, 0, 1), Vector3i(0, 1, 1), Vector3i(0, -1, 1),
		Vector3i(1, 1, 1), Vector3i(1, -1, 1), Vector3i(-1, 1, 1), Vector3i(-1, -1, 1),
	]
	check(climbing_dirs.size() == expected.size(),
			"eight climbing 3-D diagonals are found through the grid's centre cell",
			"got %d: %s" % [climbing_dirs.size(), climbing_dirs])
	var all_found := true
	for dir : Vector3i in expected:
		if dir not in climbing_dirs: all_found = false
	check(all_found,
			"the found directions are literally the eight from Q86(c)'s full family",
			"got %s" % [climbing_dirs])

# ==============================================================================
# Lower-level, beyond the planned rows: HEIGHT_V is one of the four kinds S6 owes, and
# the planned rows only reach it at S11. Enumerating it is shipped code, so it is tested
# here rather than shipping unexercised.
# ==============================================================================
func run_height_v_line_test() -> void:
	behavior_section("HEIGHT V LINE")
	var state := TestGridFixtures.build_fix_level_3()
	var grid : GridData = state.grids[0]
	var lines := LineGeometry.lines_through(grid, 1, 0, 2)
	var vertical := _lines_of_kind(lines, ScoringSection.LineKind.HEIGHT_V)
	check(vertical.size() == 1, "exactly one HEIGHT_V line runs through a cell",
			"got %d" % vertical.size())
	if vertical.is_empty(): return
	var run : LineGeometry.Line = vertical[0]
	check(run.cells == [Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(1, 0, 2)],
			"the HEIGHT_V run is the queried cell's own stack, bottom to top up to h",
			"got %s" % [run.cells])
	var stays_in_cell := true
	for c : Vector3i in run.cells:
		if c.x != 1 or c.y != 0: stays_in_cell = false
	check(stays_in_cell, "a HEIGHT_V run never leaves its own cell",
			"got %s" % [run.cells])
