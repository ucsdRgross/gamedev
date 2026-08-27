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
	run_height_v_line_test()
	run_section_key_test()
	run_old_signature_grep_gate()
	run_section_refresh_test()
	await run_mutation_pass_arrivals_and_removals_test()
	await run_compaction_scores_nothing_test()
	await run_board_locked_during_pass_test()
	await run_pass_runs_after_commit_test()
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
