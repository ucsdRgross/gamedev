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
	for coord : Vector2i in coords:
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
