class_name TestGridFixtures
## Board fixtures for the poker-patience grid model (TEST_PLAN.md §1) -- shared across every
## Phase 1+ suite that needs a stocked GridData board, so two sessions never invent two
## datasets for the same fixture id.

## FIX-GRID-1: one 5x5 grid, empty.
static func build_fix_grid_1() -> GameData:
	var state := GameData.new()
	state.grids = [_new_grid(5, 5)]
	return state

## FIX-GRID-3: three 5x5 grids, empty.
static func build_fix_grid_3() -> GameData:
	var state := GameData.new()
	state.grids = [_new_grid(5, 5), _new_grid(5, 5), _new_grid(5, 5)]
	return state

## FIX-MIXED-H: three grids; grid 0 row 1 at height 6, grid 1 row 1 at height 1, grid 2
## row 1 empty.
static func build_fix_mixed_h() -> GameData:
	var state := GameData.new()
	var g0 := _new_grid(5, 5)
	var g1 := _new_grid(5, 5)
	var g2 := _new_grid(5, 5)
	_fill_row(g0, 1, 6)
	_fill_row(g1, 1, 1)
	state.grids = [g0, g1, g2]
	return state

## FIX-CROSS: grid 0 row 2 and column 2 both one card short, sharing cell (2,2) empty --
## so one placement into (2,2) completes both.
static func build_fix_cross() -> GameData:
	var state := GameData.new()
	var grid := _new_grid(5, 5)
	for x in grid.grid_width:
		if x == 2: continue
		var card := TestFactories.m_card(1, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		grid.cells[grid.cell_index(x, 2)].datas.append(card)
	for y in grid.grid_height:
		if y == 2: continue
		var card := TestFactories.m_card(1, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		grid.cells[grid.cell_index(2, y)].datas.append(card)
	state.grids = [grid]
	return state

## FIX-STACK-5: grid 0 cell (0,0) holding 4 cards; the 5th completes a vertical line.
static func build_fix_stack_5() -> GameData:
	var state := GameData.new()
	var grid := _new_grid(5, 5)
	_fill_cell(grid, 0, 0, 4)
	state.grids = [grid]
	return state

## FIX-STACK-10: grid 0 cell (0,0) holding 9 cards; the 10th completes at height 10.
static func build_fix_stack_10() -> GameData:
	var state := GameData.new()
	var grid := _new_grid(5, 5)
	_fill_cell(grid, 0, 0, 9)
	state.grids = [grid]
	return state

## FIX-ROW-FLUSH: grid 0 row 0 filled with five cards of one suit, ranks 2,4,6,8,10 -- a
## flush, not a straight.
static func build_fix_row_flush() -> GameData:
	var state := GameData.new()
	var grid := _new_grid(5, 5)
	var suit := TestFactories.uc()
	var ranks : Array[int] = [2, 4, 6, 8, 10]
	for x in grid.grid_width:
		var idx := grid.cell_index(x, 0)
		var card := TestFactories.m_card(ranks[x], suit)
		card.stage = CardData.Stage.PLAY
		grid.cells[idx].datas.append(card)
	state.grids = [grid]
	return state

## FIX-ROW-STRAIGHT: grid 0 row 0 filled with five cards ranks 3,4,5,6,7 across mixed suits --
## a straight, not a flush. Pairs with FIX-ROW-FLUSH so the evaluator is shown telling the two
## apart, not merely returning something non-null.
static func build_fix_row_straight() -> GameData:
	var state := GameData.new()
	var grid := _new_grid(5, 5)
	var ranks : Array[int] = [3, 4, 5, 6, 7]
	for x in grid.grid_width:
		var idx := grid.cell_index(x, 0)
		var card := TestFactories.m_card(ranks[x], TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		grid.cells[idx].datas.append(card)
	state.grids = [grid]
	return state

## FIX-TRIPLE: grid 0 arranged so cell (2,2) completes row 2, column 2 and a diagonal at
## once -- both main diagonals, row 2 and column 2 fully filled.
static func build_fix_triple() -> GameData:
	var state := GameData.new()
	var grid := _new_grid(5, 5)
	var coords : Array[Vector2i] = []
	for x in grid.grid_width:
		coords.append(Vector2i(x, 2))
	for y in grid.grid_height:
		coords.append(Vector2i(2, y))
	for i in grid.grid_width:
		coords.append(Vector2i(i, i))
		coords.append(Vector2i(i, grid.grid_width - 1 - i))
	# (2,2) is the cell all three lines share and is left EMPTY on purpose: the fixture's
	# whole point is that ONE placement there completes row 2, column 2 and both diagonals.
	# Filling it would make that placement land at height 1, where none of them is complete.
	var shared := Vector2i(2, 2)
	for coord : Vector2i in coords:
		if coord == shared: continue
		var idx := grid.cell_index(coord.x, coord.y)
		if grid.cells[idx].datas.is_empty():
			var card := TestFactories.m_card(1, TestFactories.uc())
			card.stage = CardData.Stage.PLAY
			grid.cells[idx].datas.append(card)
	state.grids = [grid]
	return state

## FIX-LEVEL-3: grid 0 with every cell of row 0 at height 3, so a horizontal line exists at
## levels 0, 1 and 2.
static func build_fix_level_3() -> GameData:
	var state := GameData.new()
	var grid := _new_grid(5, 5)
	_fill_row(grid, 0, 3)
	state.grids = [grid]
	return state

static func _new_grid(width: int, height: int) -> GridData:
	var grid := GridData.new()
	grid.grid_width = width
	grid.grid_height = height
	grid.build_cells()
	return grid

## Fills every cell of `row` with `height` distinct, real cards (bottom to top).
static func _fill_row(grid: GridData, row: int, height: int) -> void:
	for x in grid.grid_width:
		var idx := grid.cell_index(x, row)
		for h in height:
			var card := TestFactories.m_card(1, TestFactories.uc())
			card.stage = CardData.Stage.PLAY
			grid.cells[idx].datas.append(card)

## Fills grid cell (x, y) with `height` distinct, real cards (bottom to top).
static func _fill_cell(grid: GridData, x: int, y: int, height: int) -> void:
	var idx := grid.cell_index(x, y)
	for h in height:
		var card := TestFactories.m_card(1, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		grid.cells[idx].datas.append(card)

## FIX-FULL-15: grid 0 with all 25 cells at height 15 -- 375 cards.
## ⚠ This returns the FINISHED board. The phase gate does NOT use it: that test builds the
## same shape one card at a time through the real placement path, because a board conjured
## into existence completes no lines and so scores nothing. Use this only where the packed
## board itself is the subject (a snapshot size, a walk, a render).
static func build_fix_full_15() -> GameData:
	var state := GameData.new()
	var grid := _new_grid(5, 5)
	for y in grid.grid_height:
		for x in grid.grid_width:
			var idx := grid.cell_index(x, y)
			for z in 15:
				var card := TestFactories.m_card((x + y + z) % 13 + 1, TestFactories.uc())
				card.stage = CardData.Stage.PLAY
				grid.cells[idx].datas.append(card)
	state.grids = [grid] as Array[GridData]
	return state


# ==============================================================================
# DRIVING A LIVE GAME ONTO A GRID BOARD
# These take a real `Game` (view or headless) that has already bootstrapped, and put cards on
# its grids through `place_card_in_grid` -- the same path the engine uses, so the mutation
# broadcast fires, the detector scores, and the Entrance refills. Shared so the suites that
# need "a board with something on it" do not each grow their own.
#
# Cards come from the game's OWN draw deck via `draw_card()`, never from the Entrance: lifting
# a card out of an Entrance slot has no mutation path yet (see gaps/GAP-008), and placing one
# that is still in `upper_zone` would leave it in two collections at once.
# ==============================================================================

## Draws `count` cards and places them into consecutive cells of row `y`, left to right.
## Returns the cards actually placed -- fewer than `count` if the deck ran out.
static func place_row_from_deck(game: Game, grid: int, y: int, count: int) -> Array[CardData]:
	var placed : Array[CardData] = []
	for x : int in count:
		var card := game.draw_card()
		if not card: break
		await game.place_card_in_grid(card, BoardCoord.new(grid, x, y, 0))
		placed.append(card)
	return placed


## A stable text digest of everything a show's outcome is made of: every grid cell bottom to
## top, the Entrance, the deck and discard IN ORDER, and every score bucket. Cards are named
## by VALUE (rank/suit), never by instance -- a restored snapshot carries its own copies, so
## two states that are "the same board" never share a single card object.
## Shared because more than one claim reduces to it: that a replayed action reproduces the
## board it interrupted, and that a headless show and a viewed one end up in the same place.
static func board_digest(state: GameData) -> String:
	var parts : Array[String] = []
	for gi : int in state.grids.size():
		var grid : GridData = state.grids[gi]
		for ci : int in grid.cells.size():
			var names : Array[String] = []
			for card : CardData in grid.cells[ci].datas:
				names.append(card.log_str())
			parts.append("g%d.c%d=[%s]" % [gi, ci, ",".join(names)])
	for col : int in state.upper_zone.size():
		var names : Array[String] = []
		for card : CardData in state.upper_zone[col].datas:
			names.append(card.log_str())
		parts.append("e%d=[%s]" % [col, ",".join(names)])
	for deck_name : String in ["draw", "discard"]:
		var deck : Array[CardData] = state.draw_deck if deck_name == "draw" else state.discard_deck
		var names : Array[String] = []
		for card : CardData in deck:
			names.append(card.log_str())
		parts.append("%s=[%s]" % [deck_name, ",".join(names)])
	parts.append("row=%s" % _bucket_digest(state.scores_row))
	parts.append("col=%s" % _bucket_digest(state.scores_col))
	parts.append("special=%s" % _bucket_digest(state.score_special))
	var cell_keys : Array = state.scores_cell.keys()
	cell_keys.sort()
	for key : Vector3i in cell_keys:
		parts.append("cell%s=%f" % [key, state.scores_cell[key].to_float()])
	parts.append("committed=%d" % state.committed_grid)
	parts.append("total=%d" % state.live_total())
	return "
".join(parts)

static func _bucket_digest(bucket: Array[BigNumber]) -> String:
	var out : Array[String] = []
	for n : BigNumber in bucket:
		out.append("%f" % n.to_float())
	return "[%s]" % ",".join(out)

