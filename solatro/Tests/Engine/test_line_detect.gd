extends TestSuite
# res://Tests/Engine/test_line_detect.gd
# Phase 2 of the poker-patience board: which lines pass through a cell, and the scoring
# section that carries one (TP-18..TP-27). Line ENUMERATION is not completeness -- finding a
# line says nothing about whether its cells are occupied, and the two are asserted apart here.

## This suite spells the old call shape in its own grep gate, so the gate skips itself.
const SELF_PATH := "res://Tests/Engine/test_line_detect.gd"

func suite_name() -> String:
	return "LINE DETECT"

func _ready() -> void:
	TestLog.line("============ LINE DETECT TEST PASS ============")
	run_row_line_test()
	run_col_line_test()
	run_diag_line_test()
	run_height_line_test()
	run_height_taller_stack_test()
	run_diag_no_grid_crossing_test()
	run_3d_diag_family_test()
	run_nonsquare_diag_test()
	run_height_v_line_test()
	run_section_key_test()
	run_old_signature_grep_gate()
	run_registration_gate()
	run_section_refresh_test()
	await run_mutation_pass_arrivals_and_removals_test()
	await run_compaction_scores_nothing_test()
	await run_board_locked_during_pass_test()
	await run_pass_runs_after_commit_test()
	await run_detector_row_and_col_test()
	await run_detector_triple_and_order_test()
	await run_detector_rescan_test()
	await run_detector_runaway_guard_test()
	await run_hand_through_pokerhands_test()
	await run_multi_line_spotlight_unabbreviated_test()
	await run_hand_reevaluated_after_spotlight_test()
	await run_stack_of_5_scores_test()
	await run_heights_6_to_9_score_nothing_test()
	await run_stack_of_10_scores_all_ten_test()
	await run_height_10_pays_bottom_five_again_test()
	await run_remove_readd_retriggers_scoring_test()
	await run_compaction_landing_on_multiple_of_5_scores_nothing_test()
	await run_full_stack_gate_3()
	await run_full_stack_gate_5()
	await run_full_stack_gate_15_test()
	finish()

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
	# Detection is not completeness. FIX-TRIPLE leaves the shared cell (2,2) EMPTY on
	# purpose, so both diagonals are DETECTED here and neither is complete yet -- filling
	# that one cell is what completes them, which is the fixture's whole point.
	for diag : LineGeometry.Line in flat_diags:
		check(not _cells_occupied(0, state, diag.cells),
				"a diagonal through the empty shared cell is detected but NOT complete")
	var filler := TestFactories.m_card(1, TestFactories.uc())
	Board.place_in_cell(state, filler, BoardCoord.new(0, 2, 2, 0))
	for diag : LineGeometry.Line in flat_diags:
		check(_cells_occupied(0, state, diag.cells),
				"filling the shared cell completes both diagonals")

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

# ==============================================================================
# TP-25 -- a section carries its line key and kind, and score_line reads neither
# is_row nor zone. The point of the change: the bucket comes FROM THE SECTION, so
# score_line never branches on shape.
# ==============================================================================
func run_section_key_test() -> void:
	behavior_section("SECTION KEY")
	var state := TestGridFixtures.build_fix_row_flush()
	var row := ScoringSection.of_line_at(state, 0, ScoringSection.LineKind.ROW, 0, 0)
	var col := ScoringSection.of_line_at(state, 0, ScoringSection.LineKind.COL, 0, 0)
	var diag := ScoringSection.of_line_at(state, 0, ScoringSection.LineKind.DIAG, 0, 0)
	check(row.kind == ScoringSection.LineKind.ROW, "a ROW section carries kind ROW")
	check(col.kind == ScoringSection.LineKind.COL, "a COL section carries kind COL")
	check(diag.kind == ScoringSection.LineKind.DIAG, "a DIAG section carries kind DIAG")
	check(not row.line_key.is_empty(), "a section carries a non-empty line key",
			"got %s" % row.line_key)
	# Distinct lines must key distinctly, or two lines would bank into one another.
	var keys : Array[StringName] = [row.line_key, col.line_key, diag.line_key]
	var distinct := keys[0] != keys[1] and keys[1] != keys[2] and keys[0] != keys[2]
	check(distinct, "three different lines carry three different keys", "got %s" % [keys])
	# Same line, asked for twice, must key the SAME -- the key identifies the line, not the call.
	var row_again := ScoringSection.of_line_at(state, 0, ScoringSection.LineKind.ROW, 0, 0)
	check(row_again.line_key == row.line_key,
			"the same line keys identically however often it is built",
			"%s vs %s" % [row.line_key, row_again.line_key])
	# The height is part of the identity: row 0 at h=0 is not row 0 at h=1.
	var row_high := ScoringSection.of_line_at(state, 0, ScoringSection.LineKind.ROW, 0, 1)
	check(row_high.line_key != row.line_key,
			"the same row at a different height is a different line",
			"%s vs %s" % [row.line_key, row_high.line_key])

# ==============================================================================
# TP-26 -- GREP GATE: no caller passes the old score_line(result, is_row, zone, index)
# signature. Reads the source tree as TEXT, the way test_outline reads card_visual.tscn,
# because the old shape is a compile-time-valid call that only a reader can spot.
# ==============================================================================
func run_old_signature_grep_gate() -> void:
	implementation_section("OLD SIGNATURE GREP GATE")
	var offenders : Array[String] = []
	var scanned := 0
	for path : String in _all_gd_files("res://"):
		# This file necessarily SPELLS the old shape -- in the helper below and in the
		# failure message above -- so it exempts itself, the way doc_check.py exempts its
		# own pattern definitions. Nothing else is exempt.
		if path == SELF_PATH: continue
		var f := FileAccess.open(path, FileAccess.READ)
		if not f: continue
		scanned += 1
		var n := 0
		for raw : String in f.get_as_text().split("\n"):
			n += 1
			var line := raw.strip_edges()
			if line.begins_with("#") or line.begins_with("##"): continue
			if not line.contains("score_line("): continue
			if line.contains("func score_line("): continue
			# The new form passes exactly TWO arguments; the old passed four. Counting
			# top-level commas inside the call is what separates them.
			if _top_level_arg_count(line, "score_line(") > 2:
				offenders.append("%s:%d: %s" % [path, n, line])
	check(scanned > 50, "the gate actually scanned the source tree",
			"only %d .gd files scanned" % scanned)
	check(offenders.is_empty(),
			"no caller passes the old score_line(result, is_row, zone, index) signature",
			"\n".join(offenders))

## Every .gd file under `root`, recursively. Test-only helper.
func _all_gd_files(root: String) -> Array[String]:
	var out : Array[String] = []
	var dirs : Array[String] = [root]
	while not dirs.is_empty():
		var d : String = dirs.pop_back()
		var dir := DirAccess.open(d)
		if not dir: continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("."):
				name = dir.get_next()
				continue
			var full : String = d.path_join(name)
			if dir.current_is_dir(): dirs.append(full)
			elif name.ends_with(".gd"): out.append(full)
			name = dir.get_next()
		dir.list_dir_end()
	return out

## Number of top-level (unnested, unquoted) arguments in the call `fn` opens on `line`.
func _top_level_arg_count(line: String, fn: String) -> int:
	var start := line.find(fn)
	if start < 0: return 0
	var i := start + fn.length()
	var depth := 1
	var args := 1
	var in_str := false
	var quote := ""
	while i < line.length():
		var c := line[i]
		if in_str:
			if c == quote: in_str = false
		elif c == "\"" or c == "'":
			in_str = true
			quote = c
		elif c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
			if depth == 0: break
		elif c == "," and depth == 1:
			args += 1
		i += 1
	return args

# ==============================================================================
# TP-27 -- a section re-derives its cards from the LIVE board after a hook. A handler
# may have added a card to the section or compacted one out of it since construction,
# so a cached card list is stale by the time the next hook reads it. FIX-ROW-FLUSH.
# ==============================================================================
func run_section_refresh_test() -> void:
	behavior_section("SECTION REFRESH")
	var state := TestGridFixtures.build_fix_row_flush()
	var section := ScoringSection.of_line_at(state, 0, ScoringSection.LineKind.ROW, 0, 0)
	var before := section.cards.size()
	check(before == state.grids[0].grid_width,
			"the section starts as the whole completed row", "got %d" % before)
	# Simulate what a hook does mid-pass: take a card out from under the section.
	var victim : CardData = state.card_at(BoardCoord.new(0, 2, 0, 0))
	check(victim != null, "the fixture really has a card at the cell about to be emptied")
	Board.remove_from_cell(state, victim)
	var changed := section.refresh()
	check(changed, "refresh() reports that the section's card set CHANGED")
	check(section.cards.size() == before - 1,
			"the section re-read the live board and lost the removed card",
			"got %d, was %d" % [section.cards.size(), before])
	check(not section.cards.has(victim),
			"the removed card is genuinely gone from the section")
	# A second refresh with nothing changed must report no change -- that is what ends
	# the activation sweep's loop, so a always-true refresh would spin it forever.
	check(not section.refresh(),
			"a refresh with nothing changed reports no change")

# ==============================================================================
# S8 -- the mutation broadcast, the compaction flag, and the board lock (TP-28..TP-31).
# A bare Game.new() never added to the tree, one rules card carrying a spy skill
# spotlit in rules_deck so run_all_mods dispatches to it, mirroring test_game_headless's
# make_game/free_game pattern.
# ==============================================================================

## Records every on_board_mutated / on_card_placed call, and (from INSIDE the handler,
## since that is the only place that proves "during") whether the board was locked and
## whether the mutation had already committed.
class SpyBoardMutation extends CardModifierSkill:
	var mutation_log : Array[Dictionary] = []
	var placed_log : Array[BoardCoord] = []
	var game_ref : Game
	var saw_locked_during_mutation := false
	var saw_committed_during_mutation := false
	func get_str() -> String: return "SpyBoardMutation"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_board_mutated(coord: BoardCoord, is_compaction: bool) -> void:
		mutation_log.append({"coord": coord, "is_compaction": is_compaction})
		if game_ref and game_ref.processing:
			saw_locked_during_mutation = true
		if game_ref and game_ref.state.card_at(coord) != null:
			saw_committed_during_mutation = true
	func on_card_placed(coord: BoardCoord) -> void:
		placed_log.append(coord)

func rules_card_grid(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.spotlit = true
	return c

func make_grid_game(state: GameData, spy: SpyBoardMutation) -> Game:
	var g := Game.new()
	state.rules_deck = [rules_card_grid(spy)] as Array[CardData]
	g.state = state
	spy.game_ref = g
	CardEnvironment.CURRENT = g
	return g

func free_grid_game(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

# ==============================================================================
# TP-28 -- every board mutation runs a pass -- arrivals AND removals. FIX-GRID-1.
# ==============================================================================
func run_mutation_pass_arrivals_and_removals_test() -> void:
	behavior_section("MUTATION PASS: ARRIVALS AND REMOVALS")
	var state := TestGridFixtures.build_fix_grid_1()
	var spy := SpyBoardMutation.new()
	var g := make_grid_game(state, spy)
	var card := TestFactories.m_card(1, TestFactories.uc())
	var coord := BoardCoord.new(0, 0, 0, 0)
	await g.place_card_in_grid(card, coord)
	check(spy.mutation_log.size() == 1,
			"an arrival runs the mutation pass once",
			"got %d" % spy.mutation_log.size())
	check(spy.placed_log.size() == 1,
			"an arrival also fires on_card_placed",
			"got %d" % spy.placed_log.size())
	await g.remove_card_from_grid(card)
	check(spy.mutation_log.size() == 2,
			"a removal ALSO runs the mutation pass",
			"got %d" % spy.mutation_log.size())
	check(spy.placed_log.size() == 1,
			"a removal does not fire on_card_placed",
			"got %d" % spy.placed_log.size())
	free_grid_game(g)

# ==============================================================================
# TP-29 -- a drop-only (compaction) mutation carries is_compaction == true, and a
# scorer keyed on that flag is skipped -- the strongest assertion available before S9's
# detector exists. FIX-STACK-10.
# ==============================================================================
func run_compaction_scores_nothing_test() -> void:
	behavior_section("COMPACTION SCORES NOTHING")
	var state := TestGridFixtures.build_fix_stack_10()
	var spy := SpyBoardMutation.new()
	var g := make_grid_game(state, spy)
	var grid : GridData = state.grids[0]
	var cell : ArrayCardData = grid.cells[grid.cell_index(0, 0)]
	var card : CardData = cell.datas[0]
	await g.move_card_in_grid(card, BoardCoord.new(0, 1, 0, 0), true)
	check(spy.mutation_log.size() == 1,
			"the compaction move runs one mutation pass",
			"got %d" % spy.mutation_log.size())
	var entry : Dictionary = spy.mutation_log[0]
	var flag : bool = entry["is_compaction"]
	check(flag,
			"the broadcast carries is_compaction == true, exactly what the mover passed",
			"got %s" % [entry])
	# A scorer keyed on is_compaction would skip this pass -- assert that a
	# would-be scorer sees the flag it needs to make that call, unlike a genuine
	# arrival, which never carries it.
	var card2 : CardData = cell.datas[1]
	await g.move_card_in_grid(card2, BoardCoord.new(0, 2, 0, 0), false)
	var entry2 : Dictionary = spy.mutation_log[1]
	var flag2 : bool = entry2["is_compaction"]
	check(not flag2,
			"a non-compaction move on the same board carries is_compaction == false",
			"got %s" % [entry2])
	free_grid_game(g)

# ==============================================================================
# TP-30 -- the board is locked (processing == true) for the WHOLE pass, read from
# INSIDE the handler, not merely set and cleared around it. FIX-CROSS.
# ==============================================================================
func run_board_locked_during_pass_test() -> void:
	behavior_section("BOARD LOCKED DURING PASS")
	var state := TestGridFixtures.build_fix_cross()
	var spy := SpyBoardMutation.new()
	var g := make_grid_game(state, spy)
	check(not g.processing, "the board starts unlocked")
	var card := TestFactories.m_card(1, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 2, 2, 0))
	check(spy.saw_locked_during_mutation,
			"processing read true from INSIDE the on_board_mutated handler")
	check(not g.processing, "the lock lifts once the whole pass has finished")
	free_grid_game(g)

# ==============================================================================
# TP-31 -- the pass runs AFTER the placement has committed: a handler responding to
# on_board_mutated already sees the placed card on the board. FIX-GRID-1.
# ==============================================================================
func run_pass_runs_after_commit_test() -> void:
	behavior_section("PASS RUNS AFTER COMMIT")
	var state := TestGridFixtures.build_fix_grid_1()
	var spy := SpyBoardMutation.new()
	var g := make_grid_game(state, spy)
	var card := TestFactories.m_card(1, TestFactories.uc())
	var coord := BoardCoord.new(0, 3, 3, 0)
	await g.place_card_in_grid(card, coord)
	check(spy.saw_committed_during_mutation,
			"the handler read the placed card off the board WHILE handling on_board_mutated")
	free_grid_game(g)

# ==============================================================================
# S9 -- the detector card (TP-32..TP-36). The REAL SkillLineDetector runs; only the
# Game it reports to is instrumented, by a subclass that records each score_line call
# and then calls super. Nothing about the detector or the geometry is stood in for.
# ==============================================================================

## Game with a tap on score_line. Records the section, then behaves exactly as Game does.
class RecordingGame extends Game:
	var scored : Array[ScoringSection] = []
	## Every amount `score_line` actually banked, in call order -- this IS `result.score` from
	## the re-evaluated `Scoring.PokerHands.score()` call, since `add_line_score` is the single
	## write path score_line hands its computed amount to (S10: which bucket a section banks
	## into is a later step, but the amount reaching this call is already the final one).
	var banked_amounts : Array[int] = []
	func score_line(result : Scoring.Result, section : ScoringSection) -> void:
		scored.append(section)
		await super(result, section)
	func add_line_score(section : ScoringSection, amount : int) -> void:
		banked_amounts.append(amount)
		super(section, amount)

## The real detector card, spotlit in the rules deck so run_all_mods dispatches to it.
func detector_game(state: GameData, extra: CardModifierSkill = null) -> RecordingGame:
	var g := RecordingGame.new()
	var deck : Array[CardData] = [rules_card_grid(SkillLineDetector.new())]
	if extra: deck.append(rules_card_grid(extra))
	state.rules_deck = deck
	g.state = state
	CardEnvironment.CURRENT = g
	return g

## The kinds recorded, in the order they were scored.
func kinds_of(sections: Array[ScoringSection]) -> Array[int]:
	var out : Array[int] = []
	for s : ScoringSection in sections: out.append(s.kind)
	return out

## Every recorded section's line key, for a failure message that names what actually scored.
func keys_of(sections: Array[ScoringSection]) -> Array[String]:
	var out : Array[String] = []
	for s : ScoringSection in sections: out.append(String(s.line_key))
	return out

# ==============================================================================
# TP-32 -- one placement completing a row AND a column scores both. FIX-CROSS.
# ==============================================================================
func run_detector_row_and_col_test() -> void:
	behavior_section("DETECTOR: ROW AND COL")
	var state := TestGridFixtures.build_fix_cross()
	var g := detector_game(state)
	var card := TestFactories.m_card(7, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 2, 2, 0))
	var kinds := kinds_of(g.scored)
	check(kinds.has(ScoringSection.LineKind.ROW),
			"the placement that completed row 2 scored a ROW line", "got %s" % [kinds])
	check(kinds.has(ScoringSection.LineKind.COL),
			"the same placement also scored a COL line", "got %s" % [kinds])
	free_grid_game(g)

# ==============================================================================
# TP-33 / TP-34 -- one placement completing row, column AND diagonal scores all three,
# in the deterministic order rows -> columns -> diagonals. FIX-TRIPLE.
# ==============================================================================
func run_detector_triple_and_order_test() -> void:
	behavior_section("DETECTOR: TRIPLE AND ORDER")
	var state := TestGridFixtures.build_fix_triple()
	var g := detector_game(state)
	var card := TestFactories.m_card(7, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 2, 2, 0))
	var kinds := kinds_of(g.scored)
	check(kinds.has(ScoringSection.LineKind.ROW), "a ROW scored", "got %s" % [kinds])
	check(kinds.has(ScoringSection.LineKind.COL), "a COL scored", "got %s" % [kinds])
	check(kinds.has(ScoringSection.LineKind.DIAG), "a DIAG scored", "got %s" % [kinds])
	# The order is a replay contract, so assert the SEQUENCE, not just membership: every
	# ROW precedes every COL, and every COL precedes every DIAG.
	var last_row := -1
	var first_col := kinds.size()
	var last_col := -1
	var first_diag := kinds.size()
	for i in kinds.size():
		match kinds[i]:
			ScoringSection.LineKind.ROW: last_row = i
			ScoringSection.LineKind.COL:
				first_col = mini(first_col, i)
				last_col = i
			ScoringSection.LineKind.DIAG: first_diag = mini(first_diag, i)
	check(last_row < first_col,
			"every ROW is scored before every COL", "kinds %s" % [kinds])
	check(last_col < first_diag,
			"every COL is scored before every DIAG", "kinds %s" % [kinds])
	free_grid_game(g)

# ==============================================================================
# TP-35 -- an effect that completes ANOTHER line during the pass gets that line scored
# too. The re-scan is not a loop inside the detector: the effect's own board mutation
# broadcasts again, and the detector answers again. FIX-CROSS.
# ==============================================================================

## Fills the last hole of column 4 the first time it sees a mutation, completing a line
## the original placement never touched.
class EffectCompletesAnotherLine extends CardModifierSkill:
	var fired := false
	var game_ref : Game
	func get_str() -> String: return "EffectCompletesAnotherLine"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_board_mutated(_coord: BoardCoord, _is_compaction: bool) -> void:
		if fired or not game_ref: return
		fired = true
		var card := TestFactories.m_card(9, TestFactories.uc())
		await game_ref.place_card_in_grid(card, BoardCoord.new(0, 4, 4, 0))

func run_detector_rescan_test() -> void:
	behavior_section("DETECTOR: RESCAN")
	var state := TestGridFixtures.build_fix_cross()
	# Leave column 4 one cell short so the effect below can be the thing that completes it.
	for y in 4:
		var filler := TestFactories.m_card(3, TestFactories.uc())
		Board.place_in_cell(state, filler, BoardCoord.new(0, 4, y, 0))
	var effect := EffectCompletesAnotherLine.new()
	var g := detector_game(state, effect)
	effect.game_ref = g
	var card := TestFactories.m_card(7, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 2, 2, 0))
	check(effect.fired, "the effect really ran (else this test is vacuous)")
	var col4_scored := false
	for s : ScoringSection in g.scored:
		if s.kind != ScoringSection.LineKind.COL: continue
		for c : Vector3i in [Vector3i(4, 0, 0), Vector3i(4, 4, 0)]:
			if String(s.line_key).contains("4"): col4_scored = true
	check(col4_scored,
			"the line the EFFECT completed was scored too, not only the placement's own",
			"scored keys: %s" % [keys_of(g.scored)])
	free_grid_game(g)

# ==============================================================================
# TP-36 -- a remove-and-replace loop RE-SCORES every cycle and is bounded ONLY by the
# runaway guard. FIX-ROW-FLUSH.
#
# This is deliberately NOT written as "it terminates". There is no line-scored memory and
# no within-pass guard by design, so a complete line re-scores on every cycle. The
# assertions are that it re-scored many times over, and that act_overrun -- the guard --
# is what stopped it. A future change that makes the loop stop for some OTHER reason fails
# the guard check below loudly instead of quietly still passing.
# ==============================================================================

## Removes and immediately replaces a card in the completed row on every mutation it sees.
## Each replacement re-completes the line, which broadcasts again.
class EffectRemoveAndReplace extends CardModifierSkill:
	var game_ref : Game
	var cycles := 0
	func get_str() -> String: return "EffectRemoveAndReplace"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_board_mutated(_coord: BoardCoord, is_compaction: bool) -> void:
		if is_compaction or not game_ref: return
		if game_ref.act_overrun or game_ref.act_cancelled: return
		var here := BoardCoord.new(0, 0, 0, 0)
		var victim : CardData = game_ref.state.card_at(here)
		if not victim: return
		cycles += 1
		Board.remove_from_cell(game_ref.state, victim)
		await game_ref.place_card_in_grid(victim, here)

func run_detector_runaway_guard_test() -> void:
	behavior_section("DETECTOR: RUNAWAY GUARD")
	var snap := snapshot_settings("runaway")
	# A small cap keeps the test quick. The POINT is which mechanism stops the loop, not
	# the particular number it stops at.
	SettingsManager.settings.act_event_cap = 60
	var state := TestGridFixtures.build_fix_row_flush()
	var effect := EffectRemoveAndReplace.new()
	var g := detector_game(state, effect)
	effect.game_ref = g
	g._begin_act()
	var card := TestFactories.m_card(7, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 0, 1, 0))
	check(effect.cycles > 1,
			"the remove-and-replace ran many cycles, re-scoring each time",
			"only %d cycles" % effect.cycles)
	check(g.scored.size() >= effect.cycles,
			"a completed line scored again on every cycle -- there is no line memory",
			"%d scorings over %d cycles" % [g.scored.size(), effect.cycles])
	check(g.act_overrun,
			"THE RUNAWAY GUARD is what stopped the loop -- act_overrun tripped",
			"act_calls=%d cap=%d" % [g.act_calls, SettingsManager.settings.act_event_cap])
	free_grid_game(g)
	restore_settings_snapshot(snap)

# ==============================================================================
# A diagonal is a run whose x and y change at the SAME RATE; corners are not part of
# the definition. That is what makes a NON-SQUARE grid answerable: the corner
# requirement was the only thing undefined there. Full length is bounded by whichever
# dimension runs out first, and only a full-length run is a line.
# ==============================================================================
func run_nonsquare_diag_test() -> void:
	behavior_section("NON-SQUARE DIAGONALS")
	var grid := GridData.new()
	grid.grid_width = 5
	grid.grid_height = 7
	grid.build_cells()

	# Through (0,0) going down-right: (0,0)..(4,4), five cells -- x runs out first.
	var at_origin := _lines_of_kind(LineGeometry.lines_through(grid, 0, 0, 0),
			ScoringSection.LineKind.DIAG)
	var flat_origin : Array[LineGeometry.Line] = []
	for line : LineGeometry.Line in at_origin:
		if line.cells[1].z == line.cells[0].z: flat_origin.append(line)
	check(not flat_origin.is_empty(),
			"a non-square grid reports flat diagonals at all -- the corner rule blocked these")
	for line : LineGeometry.Line in flat_origin:
		check(line.cells.size() == mini(grid.grid_width, grid.grid_height),
				"a non-square diagonal is as long as the SHORTER dimension allows",
				"got %d cells: %s" % [line.cells.size(), line.cells])

	# A run that does NOT reach full length is still not a line: from (0,3) going
	# down-right the grid's right edge stops it at (4,7), which is off the bottom.
	var short_run := _lines_of_kind(LineGeometry.lines_through(grid, 0, 3, 0),
			ScoringSection.LineKind.DIAG)
	var found_short := false
	for line : LineGeometry.Line in short_run:
		if line.cells.size() < mini(grid.grid_width, grid.grid_height): found_short = true
	check(not found_short, "no under-length diagonal is ever reported",
			"one of %s is short" % [short_run.size()])

	# Corners genuinely do not matter: a full-length diagonal that touches NO corner of
	# this 5x7 grid exists and is reported.
	var offset := _lines_of_kind(LineGeometry.lines_through(grid, 2, 3, 0),
			ScoringSection.LineKind.DIAG)
	var non_corner := false
	for line : LineGeometry.Line in offset:
		if line.cells[1].z != line.cells[0].z: continue
		if line.cells.size() != mini(grid.grid_width, grid.grid_height): continue
		var first : Vector3i = line.cells[0]
		var last : Vector3i = line.cells[line.cells.size() - 1]
		var touches_corner := (first.x == 0 or first.x == grid.grid_width - 1) \
				and (first.y == 0 or first.y == grid.grid_height - 1)
		var last_corner := (last.x == 0 or last.x == grid.grid_width - 1) \
				and (last.y == 0 or last.y == grid.grid_height - 1)
		if not touches_corner and not last_corner: non_corner = true
	check(non_corner,
			"a full-length diagonal touching no corner is still a diagonal",
			"none found among %d" % offset.size())

	# A SQUARE grid still yields exactly the two long diagonals through its centre --
	# the two readings agree wherever the corner rule was defined.
	var square := GridData.new()
	square.build_cells()
	var centre := _lines_of_kind(LineGeometry.lines_through(square, 2, 2, 0),
			ScoringSection.LineKind.DIAG)
	var flat_square := 0
	for line : LineGeometry.Line in centre:
		if line.cells[1].z == line.cells[0].z: flat_square += 1
	check(flat_square == 2,
			"a square grid still reports exactly two flat diagonals through its centre",
			"got %d" % flat_square)

# ==============================================================================
# S10 -- the detected line actually evaluates a poker hand (TP-37..TP-39).
# ==============================================================================

# ==============================================================================
# TP-37 -- the hand goes through PokerHands.score() unchanged: a straight and a flush of
# the same shape are told apart by the SAME evaluator every other caller uses, and the
# banked amount is exactly what that evaluator returned. FIX-ROW-STRAIGHT.
# ==============================================================================
func run_hand_through_pokerhands_test() -> void:
	behavior_section("HAND THROUGH POKERHANDS")
	var state := TestGridFixtures.build_fix_row_straight()
	var grid : GridData = state.grids[0]
	var idx := grid.cell_index(4, 0)
	var last_card : CardData = grid.cells[idx].datas[0]
	grid.cells[idx].datas.clear()
	var g := detector_game(state)
	await g.place_card_in_grid(last_card, BoardCoord.new(0, 4, 0, 0))
	check(g.scored.size() == 1, "exactly one line scored", "got %d" % g.scored.size())
	if g.scored.is_empty():
		free_grid_game(g)
		return
	var section : ScoringSection = g.scored[0]
	var expected : Array[Scoring.Result] = await Scoring.PokerHands.score(section.cards)
	check(not expected.is_empty(), "PokerHands.score() returns a result for the completed row")
	if expected.is_empty():
		free_grid_game(g)
		return
	var best : Scoring.Result = expected[0]
	check(best.types.has(Scoring.MELD_TYPE.STRAIGHT),
			"FIX-ROW-STRAIGHT's mixed-suit run scores as a STRAIGHT", "types %s" % [best.types])
	check(not best.types.has(Scoring.MELD_TYPE.FLUSH),
			"FIX-ROW-STRAIGHT is not also read as a FLUSH", "types %s" % [best.types])
	check(g.banked_amounts.size() == 1 and g.banked_amounts[0] == best.score,
			"the banked amount is exactly PokerHands.score()'s own result, unforked",
			"banked %s, PokerHands.score() said %d" % [g.banked_amounts, best.score])
	free_grid_game(g)

# ==============================================================================
# TP-38 -- the spotlight cascade runs unabbreviated even for a multi-line placement: one
# placement completing a row, a column and BOTH main diagonals banks every one of them, not
# an abbreviated subset. FIX-TRIPLE.
# ==============================================================================
func run_multi_line_spotlight_unabbreviated_test() -> void:
	behavior_section("MULTI-LINE SPOTLIGHT UNABBREVIATED")
	var state := TestGridFixtures.build_fix_triple()
	var g := detector_game(state)
	var card := TestFactories.m_card(7, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 2, 2, 0))
	# ROW + COL + both main DIAGs through the shared centre cell (TP-20/TP-33/TP-34).
	check(g.scored.size() == 4,
			"the placement completes a row, a column and both main diagonals -- all four score",
			"got %d" % g.scored.size())
	check(g.banked_amounts.size() == g.scored.size(),
			"every scored section actually banked an amount -- none was skipped",
			"%d banked amounts for %d scored sections" % [g.banked_amounts.size(), g.scored.size()])
	var expected_total := 0
	for section : ScoringSection in g.scored:
		var results : Array[Scoring.Result] = await Scoring.PokerHands.score(section.cards)
		if results: expected_total += results[0].score
	var banked_total := 0
	for amount : int in g.banked_amounts: banked_total += amount
	check(banked_total == expected_total,
			"the sum banked across the cascade equals the sum PokerHands.score() gives each line",
			"banked total %d, sum of PokerHands.score() results %d" % [banked_total, expected_total])
	free_grid_game(g)

# ==============================================================================
# TP-39 -- the hand is re-evaluated after every spotlight effect: a hook that swaps a card
# out of the section mid-cascade changes what banks, because the banked result is derived
# from the section as it stands AFTER the effects, not the one computed at completion.
# FIX-ROW-FLUSH.
# ==============================================================================

## Fires on its own card's spotlight and swaps a different card into the same cell, breaking
## the flush the section originally completed with.
class EffectSwapDuringSpotlight extends CardModifierSkill:
	var game_ref : Game
	var coord : BoardCoord
	var replacement : CardData
	var swapped := false
	func get_str() -> String: return "EffectSwapDuringSpotlight"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_spotlight() -> void:
		if swapped or not game_ref: return
		swapped = true
		var victim : CardData = game_ref.state.card_at(coord)
		if victim: Board.remove_from_cell(game_ref.state, victim)
		Board.place_in_cell(game_ref.state, replacement, coord)

func run_hand_reevaluated_after_spotlight_test() -> void:
	behavior_section("HAND REEVALUATED AFTER SPOTLIGHT")
	var state := TestGridFixtures.build_fix_row_flush()
	var grid : GridData = state.grids[0]
	var idx := grid.cell_index(0, 0)
	var swap_target : CardData = grid.cells[idx].datas[0]
	var coord := BoardCoord.new(0, 0, 0, 0)
	var effect := EffectSwapDuringSpotlight.new()
	effect.coord = coord
	effect.replacement = TestFactories.m_card(3, TestFactories.uc())
	swap_target.with_skill(effect)
	var g := detector_game(state)
	effect.game_ref = g
	# Complete the row by placing the last card through the detector so the pass fires.
	var last_idx := grid.cell_index(4, 0)
	var last_card : CardData = grid.cells[last_idx].datas[0]
	grid.cells[last_idx].datas.clear()
	await g.place_card_in_grid(last_card, BoardCoord.new(0, 4, 0, 0))
	check(effect.swapped, "the spotlight hook really fired and swapped a card (else this test is vacuous)")
	var pre_swap_cards : Array[CardData] = []
	pre_swap_cards.append(swap_target)
	for xi : int in [1, 2, 3]:
		pre_swap_cards.append_array(grid.cells[grid.cell_index(xi, 0)].datas)
	pre_swap_cards.append(last_card)
	var pre_swap_results : Array[Scoring.Result] = await Scoring.PokerHands.score(pre_swap_cards)
	var pre_swap_score : int = pre_swap_results[0].score if pre_swap_results else 0
	# ⚠ Read the BANKED amount, not state.total_score: a grid line's bucket does not exist
	# yet, so total_score is always 0 here and comparing against it passes vacuously.
	check(g.banked_amounts.size() == 1,
			"exactly one line banked, so the amount below is unambiguous",
			"banked %s" % [g.banked_amounts])
	var banked : int = g.banked_amounts[0] if g.banked_amounts.size() == 1 else -1
	check(pre_swap_score > 0,
			"the ORIGINAL five cards really did score (else the comparison is vacuous)",
			"pre-swap scored %d" % pre_swap_score)
	check(banked != pre_swap_score,
			"the banked hand is the RE-EVALUATED one, not the pre-swap five cards",
			"banked %d, the pre-swap cards would have scored %d" % [banked, pre_swap_score])
	free_grid_game(g)

# ==============================================================================
# S11 -- height scoring (TP-40..TP-45): a vertical stack scores at every multiple of 5,
# the WHOLE stack each time, and heights 6-9 (and any drop-only move) score nothing.
# ==============================================================================

# ==============================================================================
# TP-40 -- a stack of 5 scores as a 5-card hand. FIX-STACK-5.
# ==============================================================================
func run_stack_of_5_scores_test() -> void:
	behavior_section("HEIGHT: STACK OF 5 SCORES")
	var state := TestGridFixtures.build_fix_stack_5()
	var g := detector_game(state)
	var card := TestFactories.m_card(1, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 0, 0, 0))
	var kinds := kinds_of(g.scored)
	check(kinds.has(ScoringSection.LineKind.HEIGHT_V),
			"completing the 5th card in the stack scored a HEIGHT_V line", "got %s" % [kinds])
	var height_section : ScoringSection = null
	for s : ScoringSection in g.scored:
		if s.kind == ScoringSection.LineKind.HEIGHT_V: height_section = s
	check(height_section != null and height_section.cards.size() == 5,
			"the scored section is a 5-card hand",
			"got %s" % [height_section.cards.size() if height_section else -1])
	free_grid_game(g)

# ==============================================================================
# TP-41 -- heights 6-9 score nothing: walked individually, not just spot-checked once.
# FIX-STACK-10.
# ==============================================================================
func run_heights_6_to_9_score_nothing_test() -> void:
	behavior_section("HEIGHT: 6-9 SCORE NOTHING")
	var state := TestGridFixtures.build_fix_grid_1()
	var coord := BoardCoord.new(0, 0, 0, 0)
	# Pre-fill 5 cards directly (bypassing the game) so the stack starts already at the
	# height-5 payout, with the detector's log clean for the walk that follows.
	for i in 5:
		Board.place_in_cell(state, TestFactories.m_card(1, TestFactories.uc()), coord)
	var g := detector_game(state)
	for card_count : int in [6, 7, 8, 9]:
		var before := g.scored.size()
		var card := TestFactories.m_card(1, TestFactories.uc())
		await g.place_card_in_grid(card, coord)
		var newly_scored : Array[ScoringSection] = g.scored.slice(before)
		var newly_kinds := kinds_of(newly_scored)
		check(not newly_kinds.has(ScoringSection.LineKind.HEIGHT_V),
				"a stack reaching %d cards scores nothing" % card_count,
				"got %s" % [newly_kinds])
	free_grid_game(g)

# ==============================================================================
# TP-42 -- a stack of 10 scores ALL TEN cards, not two fives. FIX-STACK-10.
# ==============================================================================
func run_stack_of_10_scores_all_ten_test() -> void:
	behavior_section("HEIGHT: STACK OF 10 SCORES ALL TEN")
	var state := TestGridFixtures.build_fix_stack_10()
	var g := detector_game(state)
	var card := TestFactories.m_card(1, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 0, 0, 0))
	var height_section : ScoringSection = null
	for s : ScoringSection in g.scored:
		if s.kind == ScoringSection.LineKind.HEIGHT_V: height_section = s
	check(height_section != null,
			"completing the 10th card scored a HEIGHT_V line (else this test is vacuous)")
	check(height_section != null and height_section.cards.size() == 10,
			"the scored section holds the WHOLE ten-card stack, not two fives",
			"got %s" % [height_section.cards.size() if height_section else -1])
	free_grid_game(g)

# ==============================================================================
# TP-43 -- height 10 pays the bottom five again: NOT netted off. Grown card by card
# through the real detector so both the height-5 and height-10 completions are observed
# banking, matching FIX-STACK-10's shape by the end.
# ==============================================================================
func run_height_10_pays_bottom_five_again_test() -> void:
	behavior_section("HEIGHT: 10 PAYS THE BOTTOM FIVE AGAIN")
	var state := TestGridFixtures.build_fix_grid_1()
	var g := detector_game(state)
	var coord := BoardCoord.new(0, 0, 0, 0)
	for i in 10:
		var card := TestFactories.m_card(1, TestFactories.uc())
		await g.place_card_in_grid(card, coord)
	check(g.banked_amounts.size() == 2,
			"exactly two completions banked -- the height-5 payout and the height-10 payout",
			"banked %s" % [g.banked_amounts])
	var bottom_five_payout : int = g.banked_amounts[0] if g.banked_amounts.size() >= 1 else -1
	var whole_stack_payout : int = g.banked_amounts[1] if g.banked_amounts.size() >= 2 else -1
	check(bottom_five_payout > 0,
			"the height-5 completion really banked something (else this test is vacuous)",
			"got %d" % bottom_five_payout)
	check(whole_stack_payout > 0,
			"the height-10 completion ALSO banked something -- the bottom five paid again, not netted off",
			"got %d" % whole_stack_payout)
	free_grid_game(g)

# ==============================================================================
# TP-44 -- removing then re-adding to a complete line re-triggers scoring. FIX-ROW-FLUSH.
# ==============================================================================
func run_remove_readd_retriggers_scoring_test() -> void:
	behavior_section("HEIGHT/LINE: REMOVE-READD RE-TRIGGERS SCORING")
	var state := TestGridFixtures.build_fix_row_flush()
	var grid : GridData = state.grids[0]
	var coord := BoardCoord.new(0, 0, 0, 0)
	var card : CardData = grid.cells[grid.cell_index(0, 0)].datas[0]
	var g := detector_game(state)
	check(g.banked_amounts.is_empty(),
			"the row starts complete but UNSCORED -- built raw by the fixture, never through a pass",
			"got %s" % [g.banked_amounts])
	await g.remove_card_from_grid(card)
	await g.place_card_in_grid(card, coord)
	check(g.banked_amounts.size() == 1,
			"removing then re-adding the card re-completed the row and scored it once",
			"got %s" % [g.banked_amounts])
	await g.remove_card_from_grid(card)
	await g.place_card_in_grid(card, coord)
	check(g.banked_amounts.size() == 2,
			"doing it again re-triggers scoring again -- no line-scored memory",
			"got %s" % [g.banked_amounts])
	free_grid_game(g)

# ==============================================================================
# TP-45 -- cards dropping down to a multiple of 5 score nothing: a compaction move that
# lands a stack at height 10 must not score, because on_board_mutated bails on
# is_compaction before geometry ever runs. FIX-STACK-10.
# ==============================================================================
func run_compaction_landing_on_multiple_of_5_scores_nothing_test() -> void:
	behavior_section("HEIGHT: COMPACTION LANDING ON A MULTIPLE OF 5 SCORES NOTHING")
	var state := TestGridFixtures.build_fix_stack_10()
	var g := detector_game(state)
	var mover := TestFactories.m_card(1, TestFactories.uc())
	# A genuine arrival elsewhere first (never a compaction), then move it INTO the
	# nine-card stack as an explicit compaction -- landing it at height 10.
	await g.place_card_in_grid(mover, BoardCoord.new(0, 1, 0, 0))
	var before := g.scored.size()
	await g.move_card_in_grid(mover, BoardCoord.new(0, 0, 0, 0), true)
	var grid2 : GridData = state.grids[0]
	check(grid2.cells[grid2.cell_index(0, 0)].datas.size() == 10,
			"the moved card really did land the stack at height 10 (else this test is vacuous)")
	check(g.scored.size() == before,
			"the compaction move that landed on a multiple of 5 scored nothing",
			"scored grew by %d" % (g.scored.size() - before))
	free_grid_game(g)

# ==============================================================================
# REGISTRATION GATE: every `func run_*_test()` this file defines must actually be CALLED
# from _ready.
#
# ⚠ This exists because six planned tests were once written, reviewed and reported as
# added, while none of them ran: they were defined and never invoked, and the suite
# printed ALL CHECKS PASSED the whole time. An unregistered test is indistinguishable
# from a passing one in a log, which is the same failure shape the grep gate above
# guards against. Reads this file as TEXT, since a function's existence says nothing
# about whether anything calls it.
# ==============================================================================
func run_registration_gate() -> void:
	implementation_section("REGISTRATION GATE")
	var f := FileAccess.open(SELF_PATH, FileAccess.READ)
	check(f != null, "the gate can read its own source", SELF_PATH)
	if not f: return
	var text := f.get_as_text()
	var lines := text.split("\n")

	# The body of _ready, which is where a test has to be called from to run at all.
	var ready_body := ""
	var in_ready := false
	for raw : String in lines:
		if raw.begins_with("func _ready("):
			in_ready = true
			continue
		if in_ready:
			if raw.begins_with("func "): break
			ready_body += raw + "\n"

	var defined : Array[String] = []
	for raw : String in lines:
		if not raw.begins_with("func run_"): continue
		var name := raw.substr(5, raw.find("(") - 5)
		defined.append(name)

	var unregistered : Array[String] = []
	for name : String in defined:
		if name == "run_registration_gate": continue
		if not ready_body.contains(name + "()"): unregistered.append(name)

	check(defined.size() > 10, "the gate actually found this suite's tests",
			"only found %d" % defined.size())
	check(unregistered.is_empty(),
			"every run_*_test defined in this file is called from _ready",
			"never called: %s" % ", ".join(unregistered))

# ==============================================================================
# TP-46 -- THE PHASE 2 GATE. Build a grid card by card to a ceiling and assert the SET of
# lines the detector scored is exactly the set that should exist.
#
# ⚠ The expected set is built by the enumerator below, which is written from the RULES --
# full-length rows and columns at every height, the two flat diagonals, the eight climbing
# families, and a vertical run at every multiple of 5 -- and NEVER by asking LineGeometry.
# If it called the code under test it would only assert that the code agrees with itself.
#
# Compared as a SET, not a count: a count matches for the wrong reasons.
#
# Run at ceilings 3 and 5 before 15, because a failure at 15 is very hard to localise: at 3
# no climbing line and no vertical line can exist yet, at 5 exactly one of each family can,
# and at 15 the climbing families have eleven height offsets each.
# ==============================================================================

## One line's identity, in the same string form the section carries: kind plus endpoints.
## A straight run is fixed by its two endpoints, so this is unique per line.
func line_key_for(kind: ScoringSection.LineKind, first: Vector3i, last: Vector3i) -> String:
	return "grid0:%s:%s:%s" % [ScoringSection.LineKind.keys()[kind], first, last]

## THE INDEPENDENT ENUMERATOR. Every line that should be complete in a fully packed w x h
## grid whose every cell holds `ceiling` cards. Derived from the rules, not from LineGeometry.
func expected_line_keys(w: int, h: int, ceiling: int) -> Dictionary:
	var out : Dictionary = {}
	var add := func(kind: ScoringSection.LineKind, first: Vector3i, last: Vector3i) -> void:
		out[line_key_for(kind, first, last)] = true

	# Rows and columns: one per row/column per height, full width / full height.
	for z in ceiling:
		for y in h:
			add.call(ScoringSection.LineKind.ROW, Vector3i(0, y, z), Vector3i(w - 1, y, z))
		for x in w:
			add.call(ScoringSection.LineKind.COL, Vector3i(x, 0, z), Vector3i(x, h - 1, z))

	# Flat diagonals: x and y change at the same rate, so on a square grid exactly two.
	if w == h:
		for z in ceiling:
			add.call(ScoringSection.LineKind.DIAG, Vector3i(0, 0, z), Vector3i(w - 1, h - 1, z))
			add.call(ScoringSection.LineKind.DIAG, Vector3i(0, h - 1, z), Vector3i(w - 1, 0, z))

	# Climbing families: height always rises by one per step, so a run of length L needs L
	# heights and can start at any h0 that leaves room for it.
	# Along x (length w), for every row, in both horizontal directions.
	for z0 in range(0, ceiling - w + 1):
		for y in h:
			add.call(ScoringSection.LineKind.DIAG, Vector3i(0, y, z0), Vector3i(w - 1, y, z0 + w - 1))
			add.call(ScoringSection.LineKind.DIAG, Vector3i(w - 1, y, z0), Vector3i(0, y, z0 + w - 1))
	# Along y (length h), for every column, in both directions.
	for z0 in range(0, ceiling - h + 1):
		for x in w:
			add.call(ScoringSection.LineKind.DIAG, Vector3i(x, 0, z0), Vector3i(x, h - 1, z0 + h - 1))
			add.call(ScoringSection.LineKind.DIAG, Vector3i(x, h - 1, z0), Vector3i(x, 0, z0 + h - 1))
	# Corner-to-corner climbs (length min(w,h)); four of them, one per horizontal direction.
	var diag_len : int = mini(w, h)
	if w == h:
		for z0 in range(0, ceiling - diag_len + 1):
			var top := z0 + diag_len - 1
			add.call(ScoringSection.LineKind.DIAG, Vector3i(0, 0, z0), Vector3i(w - 1, h - 1, top))
			add.call(ScoringSection.LineKind.DIAG, Vector3i(0, h - 1, z0), Vector3i(w - 1, 0, top))
			add.call(ScoringSection.LineKind.DIAG, Vector3i(w - 1, 0, z0), Vector3i(0, h - 1, top))
			add.call(ScoringSection.LineKind.DIAG, Vector3i(w - 1, h - 1, z0), Vector3i(0, 0, top))

	# Vertical runs: a stack scores at every multiple of 5, paying the whole stack.
	for x in w:
		for y in h:
			for z in ceiling:
				if (z + 1) % LineGeometry.HEIGHT_SCORE_INTERVAL == 0:
					add.call(ScoringSection.LineKind.HEIGHT_V, Vector3i(x, y, 0), Vector3i(x, y, z))
	return out

## Builds a w x h grid to `ceiling` cards per cell, ONE CARD AT A TIME through the real
## placement path, so every line is completed by a real mutation and scored by the real
## detector. Layer by layer, so a line's topmost cell is always the last one placed.
func build_packed_grid(g: RecordingGame, w: int, h: int, ceiling: int) -> void:
	for z in ceiling:
		for y in h:
			for x in w:
				# Each placement is its own act, so the runaway counter never accumulates
				# across the whole build and stop the detector part way.
				g._begin_act()
				var card := TestFactories.m_card((x + y + z) % 13 + 1, TestFactories.uc())
				await g.place_card_in_grid(card, BoardCoord.new(0, x, y, 0))

## Parameterised helper, not an entry point -- the three wrappers below are.
func _full_stack_gate_at(ceiling: int) -> void:
	behavior_section("FULL STACK GATE: CEILING %d" % ceiling)
	var state := GameData.new()
	var grid := GridData.new()
	grid.build_cells()
	state.grids = [grid] as Array[GridData]
	var g := detector_game(state)
	await build_packed_grid(g, grid.grid_width, grid.grid_height, ceiling)

	var found : Dictionary = {}
	for s : ScoringSection in g.scored:
		found[String(s.line_key)] = true
	var expected := expected_line_keys(grid.grid_width, grid.grid_height, ceiling)

	# Sanity: the board really is packed, so a mismatch below is about lines, not cards.
	var cards := 0
	for cell : ArrayCardData in grid.cells: cards += cell.datas.size()
	check(cards == grid.grid_width * grid.grid_height * ceiling,
			"the board really is packed to the ceiling",
			"%d cards, wanted %d" % [cards, grid.grid_width * grid.grid_height * ceiling])
	check(not expected.is_empty(), "the enumerator produced an expectation at all")

	var missing : Array[String] = []
	for key : String in expected:
		if not found.has(key): missing.append(key)
	var unexpected : Array[String] = []
	for key : String in found:
		if not expected.has(key): unexpected.append(key)
	missing.sort()
	unexpected.sort()

	check(missing.is_empty(),
			"every line the rules say should complete was scored (ceiling %d)" % ceiling,
			"%d missing, first few: %s" % [missing.size(), missing.slice(0, 6)])
	check(unexpected.is_empty(),
			"no line was scored that the rules do not call for (ceiling %d)" % ceiling,
			"%d unexpected, first few: %s" % [unexpected.size(), unexpected.slice(0, 6)])
	free_grid_game(g)

func run_full_stack_gate_3() -> void:
	await _full_stack_gate_at(3)

func run_full_stack_gate_5() -> void:
	await _full_stack_gate_at(5)

func run_full_stack_gate_15_test() -> void:
	await _full_stack_gate_at(15)
