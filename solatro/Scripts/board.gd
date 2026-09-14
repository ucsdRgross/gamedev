class_name Board
## Pure board move logic over GameData.

#Destinations are ANCHORS - card references or column ends - never indices, so the extraction step
#can never invalidate the destination: the anchor is resolved AFTER extraction, and the whole
#same-column compensation disappears. No scene tree, no signals, no mod events.

#MUTATION GUIDELINES. Never write state's card arrays directly. Mutate only through
#Board.move_stack, place_card, add_column or remove_column, or Game.draw_card, discard_data,
#add_deck, shuffle_deck or return_to_map.

#Each of those bumps state.revision, whose setter emits board_changed, so the UI rebuilds and the
#compare-mod cache invalidates. No bump means a silent desync: stale visuals, and possibly stale
#comparator results.

#A new mutation path must leave the state fully consistent FIRST, with validate() returning empty,
#then bump state.revision exactly once AFTER the mutation - never mid-way, since board_changed
#listeners run synchronously and will read the state.

#Two non-array mutations also count and need a bump: assigning or removing a CardModifier on an
#in-play card, which changes what the comparator cache should see, and anything that changes zone
#column and type pairing outside add_column or remove_column.

#Reads never need anything: locate, find_data_vec3 and validate are side-effect free, and rejected
#or no-op move_stack calls do not bump.

#PlayArea-side rule: any code reading ui_data, data_ui, data_card or the control tree must call
#play_area.flush_rebuild() first, or it crashes on a stale layout. Watch the debug output too - a
#validate() warning after a move or undo means a mutation path broke an invariant.

#move_stack result codes. OK_NOOP is an explicit no-op: nothing moved, so fire no events.
const OK := 0
const OK_NOOP := 1
const ERR_NOT_ON_BOARD := 2
const ERR_DEST_NOT_ON_BOARD := 3
const ERR_DEST_INSIDE_STACK := 4
const ERR_DEST_OUT_OF_BOUNDS := 5

const ERROR_NAMES : Array[String] = ["OK", "OK_NOOP", "ERR_NOT_ON_BOARD",
		"ERR_DEST_NOT_ON_BOARD", "ERR_DEST_INSIDE_STACK", "ERR_DEST_OUT_OF_BOUNDS"]

## Destination anchor: OnTop(card) / ColumnEnd(x, col) / ColumnStart(x, col).
class Anchor:
	extends RefCounted
	enum Kind { ON_TOP, COLUMN_END, COLUMN_START }
	var kind : Kind
	var card : CardData
	var x : int = -1
	var col : int = -1

	static func on_top(target: CardData) -> Anchor:
		var a := Anchor.new()
		a.kind = Kind.ON_TOP
		a.card = target
		return a

	static func column_end(zone_x: int, zone_col: int) -> Anchor:
		var a := Anchor.new()
		a.kind = Kind.COLUMN_END
		a.x = zone_x
		a.col = zone_col
		return a

	static func column_start(zone_x: int, zone_col: int) -> Anchor:
		var a := Anchor.new()
		a.kind = Kind.COLUMN_START
		a.x = zone_x
		a.col = zone_col
		return a

	func _to_string() -> String:
		match kind:
			Kind.ON_TOP: return "OnTop(%s)" % card
			Kind.COLUMN_END: return "ColumnEnd(%d,%d)" % [x, col]
			_: return "ColumnStart(%d,%d)" % [x, col]

## What move_stack did, for Game's Phase-4 event dispatch.
class MoveResult:
	extends RefCounted
	var code : int = 0
	var stack : Array[CardData] = []
	var onto : CardData = null
	var src_x : int = -1
	var dest_x : int = -1

static func zone(state: GameData, x: int) -> Array[ArrayCardData]:
	return state.upper_zone if x == 0 else state.lower_zone

#O(1): it reads GameData's lazy position index, which rebuilds itself whenever state.revision
#moved - the same invalidation key as the compare-mod cache.

## Board position of a card as (x, col, row); headers get row -1, and MIN when not on the board.
static func locate(state: GameData, data: CardData) -> Vector3i:
	return state.position_of(data)

#The legacy convention is z < 0 append, z == 0 column start, z > 0 insert above the card at z-1.

## Adapter from the legacy Vector3i destination convention. Null when unmappable.
static func anchor_from_coord(state: GameData, dest: Vector3i) -> Anchor:
	if dest == Vector3i.MIN: return null
	if dest.z < 0: return Anchor.column_end(dest.x, dest.y)
	if dest.z == 0: return Anchor.column_start(dest.x, dest.y)
	var z := zone(state, dest.x)
	if dest.y < 0 or dest.y >= z.size(): return null
	var below : CardData = z[dest.y].datas.get(dest.z - 1) if dest.z - 1 < z[dest.y].datas.size() else null
	if below: return Anchor.on_top(below)
	return Anchor.column_end(dest.x, dest.y)

#It mutates state ONLY on OK: every error and no-op path provably leaves the board untouched.
#A count below zero means "the rest of the column".

## The four-phase move.
static func move_stack(state: GameData, moving: CardData, count: int, dest: Anchor) -> MoveResult:
	var res := MoveResult.new()

#PHASE 1, RESOLVE: read-only.
	if count == 0:
		res.code = OK_NOOP
		return res
	if not dest:
		res.code = ERR_DEST_NOT_ON_BOARD
		return res
	var src := locate(state, moving)
#Headers cannot move.
	if src == Vector3i.MIN or src.z < 0:
		res.code = ERR_NOT_ON_BOARD
		return res
	var src_col : ArrayCardData = zone(state, src.x)[src.y]
	var available := src_col.datas.size() - src.z
	if count < 0 or count > available:
		count = available
	res.stack = src_col.datas.slice(src.z, src.z + count)
	res.src_x = src.x

#PHASE 2, VALIDATE: still read-only.
	if dest.kind == Anchor.Kind.ON_TOP:
		if dest.card in res.stack:
			res.code = ERR_DEST_INSIDE_STACK
			return res
		var dloc := locate(state, dest.card)
		if dloc == Vector3i.MIN:
			res.code = ERR_DEST_NOT_ON_BOARD
			return res
#An anchor that is a zone header is the same as inserting at the column start.
		if dloc.z < 0:
			dest = Anchor.column_start(dloc.x, dloc.y)
		elif dloc.x == src.x and dloc.y == src.y and dloc.z == src.z - 1:
#Dropping the stack onto the card directly beneath it.
			res.code = OK_NOOP
			return res
	if dest.kind != Anchor.Kind.ON_TOP:
		if dest.col < 0 or dest.col >= zone(state, dest.x).size():
			res.code = ERR_DEST_OUT_OF_BOUNDS
			return res
		if dest.x == src.x and dest.col == src.y:
			if dest.kind == Anchor.Kind.COLUMN_START and src.z == 0:
#The stack already starts the column.
				res.code = OK_NOOP
				return res
			if dest.kind == Anchor.Kind.COLUMN_END and src.z + count == src_col.datas.size():
#The stack already ends the column.
				res.code = OK_NOOP
				return res

#PHASE 3, MUTATE: extract, then resolve the anchor, then insert.
	var src_cutoff : Array[CardData] = src_col.datas.slice(src.z + count)
	src_col.datas.resize(src.z)
	src_col.datas.append_array(src_cutoff)
#The extraction shifted rows without a revision bump, the bump coming after the insert per the
#guidelines, so the index is invalidated here and the locate below rebuilds it from the current
#arrays.
	state.invalidate_pos_index()
	var dest_col : ArrayCardData
	var insert_row : int
	match dest.kind:
		Anchor.Kind.ON_TOP:
#Post-extraction, so always current.
			var dloc := locate(state, dest.card)
			dest_col = zone(state, dloc.x)[dloc.y]
			insert_row = dloc.z + 1
			res.onto = dest.card
			res.dest_x = dloc.x
		Anchor.Kind.COLUMN_END:
			dest_col = zone(state, dest.x)[dest.col]
			insert_row = dest_col.datas.size()
			res.onto = dest_col.datas.back() if dest_col.datas.size() > 0 else null
			res.dest_x = dest.x
		Anchor.Kind.COLUMN_START:
			dest_col = zone(state, dest.x)[dest.col]
			insert_row = 0
			res.onto = null
			res.dest_x = dest.x
	var dest_cutoff : Array[CardData] = dest_col.datas.slice(insert_row)
	dest_col.datas.resize(insert_row)
	dest_col.datas.append_array(res.stack)
	dest_col.datas.append_array(dest_cutoff)
	for c in res.stack:
		c.stage = CardData.Stage.PLAY

#PHASE 4, events, belongs to Game: the board is consistent from here on.
	state.revision += 1
	res.code = OK
	return res


#Non-move mutations, so mods do not write the zone arrays directly.

## Places a card that is NOT on the board (e.g. freshly drawn) at a column end.
static func place_card(state: GameData, card: CardData, x: int, col: int) -> bool:
	if not card: return false
	if col < 0 or col >= zone(state, x).size(): return false
#Already on the board.
	if locate(state, card) != Vector3i.MIN: return false
	zone(state, x)[col].datas.append(card)
#An already-PLAY stage is not re-set: previous_stage drives the visual's spawn origin, a DRAW
#flying in from the deck, and re-setting would clobber it.
	if card.stage != CardData.Stage.PLAY:
		card.stage = CardData.Stage.PLAY
	state.revision += 1
	return true

## Appends a header and an empty column in lockstep. ZoneAdder's add path.
static func add_column(state: GameData, zone_cols: Array[ArrayCardData], zone_types: Array[CardData], header: CardData) -> void:
	header.stage = CardData.Stage.ZONE
	zone_types.append(header)
	zone_cols.append(ArrayCardData.new())
	state.revision += 1

#Returns the orphaned column cards so the caller can discard or relocate them.

## Removes header and column in lockstep. ZoneAdder's remove path.
static func remove_column(state: GameData, zone_cols: Array[ArrayCardData], zone_types: Array[CardData], index: int) -> Array[CardData]:
	if index < 0 or index >= zone_types.size() or index >= zone_cols.size():
		return []
	zone_types.remove_at(index)
#Popped BEFORE the bump: board_changed listeners run synchronously inside the bump and must see
#types and columns already back in lockstep.
	var orphans : Array[CardData] = zone_cols.pop_at(index).datas
	state.revision += 1
	return orphans


#Grid-board mutations: place, move, and remove with compaction. Same MUTATION GUIDELINES as
#above - consistent state first, ONE revision bump after, no scene tree and no signals.

#`is_compaction` is never computed from before-and-after heights: it is whatever the caller passed
#to move_to_cell, echoed back so the board-mutation broadcast can read it without re-deriving it.

## Result of a grid mutation: whether it happened, and whether the MOVER called it a compaction.
class GridMoveResult:
	extends RefCounted
	var ok : bool = false
	var is_compaction : bool = false

## Cell (x, y) of grid `grid_index` in `state`, or null when out of range.
static func _grid_at(state: GameData, grid_index: int) -> GridData:
	if grid_index < 0 or grid_index >= state.grids.size():
		return null
	return state.grids[grid_index]

## [grid_index, cell_index, height] of `card` in the grid board, or [] when it is in no cell.
static func _locate_in_grid(state: GameData, card: CardData) -> Array[int]:
	for gi in state.grids.size():
		var grid : GridData = state.grids[gi]
		if not grid: continue
		for ci in grid.cells.size():
			var cell : ArrayCardData = grid.cells[ci]
			if not cell: continue
			var h := cell.datas.find(card)
			if h != -1:
				var found : Array[int] = [gi, ci, h]
				return found
	return []

#Callers outside this file use this instead of _locate_in_grid's raw triple, and test the result
#with is_nowhere(), never with == BoardCoord.NOWHERE.

## Public grid-board counterpart of locate: the card's coordinate, or BoardCoord.NOWHERE.
static func locate_in_cell(state: GameData, card: CardData) -> BoardCoord:
	var loc := _locate_in_grid(state, card)
	if loc.is_empty(): return BoardCoord.NOWHERE
	var grid : GridData = state.grids[loc[0]]
	var cell_idx : int = loc[1]
	return BoardCoord.new(loc[0], cell_idx % grid.grid_width, cell_idx / grid.grid_width, loc[2])

#It reuses the Anchor.ON_TOP rule, inserting above whatever is already there, rather than trusting
#coord.h, so a caller can never hand in a height that disagrees with the stack it lands on.

#⚠ IT LIFTS THE CARD OUT OF THE ZONE COLUMN IT CAME FROM, as one mutation with the append. A card
#placed from the Entrance stays in upper_zone until something takes it out, and there is no other
#path that does, so appending without the lift leaves it in TWO collections.

#validate() reports that as a duplicate and every position index then disagrees about it. Zone
#HEADERS at row -1 are never lifted: they belong to their column. Bumps revision once, after.

## Places a card into a cell, at the TOP of its stack.
static func place_in_cell(state: GameData, card: CardData, coord: BoardCoord) -> bool:
	if not card: return false
	var grid := _grid_at(state, coord.grid)
	if not grid: return false
	if coord.x < 0 or coord.x >= grid.grid_width or coord.y < 0 or coord.y >= grid.grid_height:
		return false
	if not _locate_in_grid(state, card).is_empty():
#Already on the grid board.
		return false
	var held := locate(state, card)
	if held != Vector3i.MIN and held.z > -1:
		zone(state, held.x)[held.y].datas.erase(card)
	var idx := grid.cell_index(coord.x, coord.y)
	grid.cells[idx].datas.append(card)
#An already-PLAY stage is not re-set: previous_stage drives the visual's spawn origin.
	if card.stage != CardData.Stage.PLAY:
		card.stage = CardData.Stage.PLAY
	state.revision += 1
	return true

#It lands at that cell's top, Anchor.ON_TOP again. `is_compaction` is set BY THE CALLER, never
#inferred from the source and destination heights, and is carried on the returned result. Bumps
#revision exactly once.

## Moves a card already on the grid board to another cell.
static func move_to_cell(state: GameData, card: CardData, coord: BoardCoord, is_compaction: bool) -> GridMoveResult:
	var res := GridMoveResult.new()
	res.is_compaction = is_compaction
	if not card: return res
	var loc := _locate_in_grid(state, card)
#Not on the grid board, which is place_in_cell's job.
	if loc.is_empty(): return res
	var dest_grid := _grid_at(state, coord.grid)
	if not dest_grid: return res
	if coord.x < 0 or coord.x >= dest_grid.grid_width \
			or coord.y < 0 or coord.y >= dest_grid.grid_height:
		return res
	var src_grid : GridData = state.grids[loc[0]]
	src_grid.cells[loc[1]].datas.remove_at(loc[2])
	var dest_idx := dest_grid.cell_index(coord.x, coord.y)
	dest_grid.cells[dest_idx].datas.append(card)
	state.revision += 1
	res.ok = true
	return res

#The array holding the stack IS the height axis, so popping the card out already drops every card
#above it down by one and no separate per-card move is needed to compact. ONE bump for the whole.

## Removes `card` from its cell.
static func remove_from_cell(state: GameData, card: CardData) -> bool:
	var loc := _locate_in_grid(state, card)
	if loc.is_empty(): return false
	var grid : GridData = state.grids[loc[0]]
	grid.cells[loc[1]].datas.remove_at(loc[2])
	state.revision += 1
	return true

#It ensures the grid's cells and cell_types are built to its own size BEFORE the append,
#mirroring add_column's header-and-column lockstep. One bump.

## Appends one grid to the board.
static func add_grid(state: GameData, grid: GridData) -> void:
	if not grid: return
	var expected := grid.grid_width * grid.grid_height
	if grid.cells.size() != expected or grid.cell_types.size() != expected:
		grid.build_cells()
	state.grids.append(grid)
	deal_marks(state)
	state.revision += 1

#Every unmarked cell is dealt from the plan's STORED seed, so a grid arriving mid-show replays.
#It happens here, ahead of the bump, because the rebuild the bump triggers must see a marked board.
#A board with no plan is the opening deal's to write.
static func deal_marks(state: GameData) -> void:
	if state.plan_seed == 0: return
	BoardPlan.deal(state, _plan_rng(state))

#A batch of cells redrawn from the same stored seed, so a resumed show rerolls them to the same
#cards. False when the offer held nothing else, which leaves the marks standing and nothing to bump.
static func redraw_marks(state: GameData, cells: Array[CardData]) -> bool:
	return BoardPlan.redraw(state, cells, _plan_rng(state))

#The plan's own generator: the deal and a redraw replay from the seed the state stores, never from
#the global one.
static func _plan_rng(state: GameData) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = state.plan_seed
	return rng

#It returns the orphaned in-play cards, not the cell zone type cards, for the caller to discard,
#mirroring remove_column's orphan contract. One bump.

## Removes grid `index`.
static func remove_grid(state: GameData, index: int) -> Array[CardData]:
	if index < 0 or index >= state.grids.size():
		return []
	var grid : GridData = state.grids.pop_at(index)
	state.remove_grid_score_data(index)
	state.rebase_commitment(index)
	state.revision += 1
	var orphans : Array[CardData] = []
	if grid:
		for cell : ArrayCardData in grid.cells:
			if cell: orphans.append_array(cell.datas)
	return orphans
