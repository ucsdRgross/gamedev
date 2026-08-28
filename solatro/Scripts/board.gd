class_name Board
## Pure board move logic over GameData (ARCHITECTURE_REVIEW.md §5).
##
## ============================ MUTATION GUIDELINES =============================
## Everything that keeps the game in sync (play-area UI, compare-mod cache, undo,
## validate()) hangs off ONE rule:
##
##   RULE: never write state's card arrays (upper/lower_zone, *_zone_type,
##   draw_deck, discard_deck, rules_deck) directly. Mutate only through:
##     Board.move_stack / place_card / add_column / remove_column
##     Game.draw_card / discard_data / add_deck / shuffle_deck / return_to_map
##   These all bump state.revision, whose setter emits board_changed -> the UI
##   rebuilds and the compare-mod cache invalidates. No bump = silent desync
##   (stale visuals AND possibly stale comparator results).
##
## If a new mutation path is truly needed, it must:
##   1. leave the state fully consistent FIRST (state.validate() returns empty --
##      zone/type arrays in lockstep, stages matching locations, no card in two
##      places),
##   2. bump state.revision exactly once, AFTER the mutation (never mid-way:
##      board_changed listeners run synchronously and will read the state),
##   3. be exercised in a debug build, where Game.debug_validate push_warnings
##      any broken invariant after moves/undo.
##
## Two non-array mutations ALSO count as board mutations and need a bump:
##   - assigning/removing a CardModifier on an in-play card (changes which mods
##     the comparator cache should see),
##   - anything that changes zone column/type pairing outside add/remove_column.
## Reads never need anything: locate / find_data_vec3 / validate are side-effect
## free, and rejected/no-op move_stack calls do not bump.
## ==============================================================================
## Destinations are ANCHORS (card references / column ends), not indices, so the
## extraction step can never invalidate the destination — the anchor is resolved
## AFTER extraction and the whole same-column compensation math disappears.
## No scene tree, no signals, no mod events: Game keeps Phase 4 (event firing).
##
## MUTATION GUIDELINES — follow these and board/UI/cache desync cannot happen:
## 1. Only mutate cards/zones/decks through: Board.move_stack / place_card /
##    add_column / remove_column, or Game.draw_card / discard_data / add_deck /
##    shuffle_deck / return_to_map. Never write state arrays directly from mods/UI.
## 2. If you MUST add a new mutation path: mutate to a fully consistent state
##    (state.validate() returns []), THEN bump state.revision exactly once. The bump
##    emits board_changed (queues the UI rebuild) and invalidates the compare-mod
##    cache — bumping mid-mutation would let the UI rebuild against a broken board.
## 3. Assigning or removing a CardModifier on an in-play card is also a mutation:
##    bump state.revision (the compare-mod cache is keyed on it).
## 4. PlayArea-side rule: any code reading ui_data/data_ui/data_card or the control
##    tree must call play_area.flush_rebuild() first (stale-layout crash otherwise).
## 5. Watch the debug output: state.validate() warnings after moves/undo mean a
##    mutation path broke an invariant — treat as a bug, not noise.

#move_stack result codes
const OK := 0
const OK_NOOP := 1                 #explicit no-op: nothing moved, fire no events
const ERR_NOT_ON_BOARD := 2        #moving card is not in a zone column
const ERR_DEST_NOT_ON_BOARD := 3   #OnTop anchor card is in no zone/header row
const ERR_DEST_INSIDE_STACK := 4   #OnTop anchor card is part of the moving stack
const ERR_DEST_OUT_OF_BOUNDS := 5  #ColumnEnd/Start column does not exist

const ERROR_NAMES : Array[String] = ["OK", "OK_NOOP", "ERR_NOT_ON_BOARD",
		"ERR_DEST_NOT_ON_BOARD", "ERR_DEST_INSIDE_STACK", "ERR_DEST_OUT_OF_BOUNDS"]

## Destination anchor: OnTop(card) / ColumnEnd(x, col) / ColumnStart(x, col).
class Anchor:
	extends RefCounted
	enum Kind { ON_TOP, COLUMN_END, COLUMN_START }
	var kind : Kind
	var card : CardData      #ON_TOP only
	var x : int = -1         #column anchors only: 0 upper / 1 lower
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
	var code : int = 0           #Board.OK etc.
	var stack : Array[CardData] = []
	var onto : CardData = null   #card the stack landed on (null for ColumnStart/empty col)
	var src_x : int = -1
	var dest_x : int = -1

static func zone(state: GameData, x: int) -> Array[ArrayCardData]:
	return state.upper_zone if x == 0 else state.lower_zone

## Board position of a card: (x, col, row); headers get row -1; MIN if not on board.
## O(1): reads GameData's lazy position index (§5.4), which rebuilds itself whenever
## state.revision moved — the same invalidation key as the SE1 compare-mod cache.
static func locate(state: GameData, data: CardData) -> Vector3i:
	return state.position_of(data)

## Adapter from the legacy Vector3i destination convention (z < 0 append,
## z == 0 column start, z > 0 insert above card at z-1). Null when unmappable.
static func anchor_from_coord(state: GameData, dest: Vector3i) -> Anchor:
	if dest == Vector3i.MIN: return null
	if dest.z < 0: return Anchor.column_end(dest.x, dest.y)
	if dest.z == 0: return Anchor.column_start(dest.x, dest.y)
	var z := zone(state, dest.x)
	if dest.y < 0 or dest.y >= z.size(): return null
	var below : CardData = z[dest.y].datas.get(dest.z - 1) if dest.z - 1 < z[dest.y].datas.size() else null
	if below: return Anchor.on_top(below)
	return Anchor.column_end(dest.x, dest.y)

## The four-phase move (§5.2). Mutates state ONLY on OK; every error/no-op path
## provably leaves the board untouched. count < 0 means "rest of the column".
static func move_stack(state: GameData, moving: CardData, count: int, dest: Anchor) -> MoveResult:
	var res := MoveResult.new()

	# PHASE 1 — RESOLVE (read-only)
	if count == 0:
		res.code = OK_NOOP
		return res
	if not dest:
		res.code = ERR_DEST_NOT_ON_BOARD
		return res
	var src := locate(state, moving)
	if src == Vector3i.MIN or src.z < 0: #headers cannot move
		res.code = ERR_NOT_ON_BOARD
		return res
	var src_col : ArrayCardData = zone(state, src.x)[src.y]
	var available := src_col.datas.size() - src.z
	if count < 0 or count > available:
		count = available
	res.stack = src_col.datas.slice(src.z, src.z + count)
	res.src_x = src.x

	# PHASE 2 — VALIDATE (still read-only)
	if dest.kind == Anchor.Kind.ON_TOP:
		if dest.card in res.stack:
			res.code = ERR_DEST_INSIDE_STACK
			return res
		var dloc := locate(state, dest.card)
		if dloc == Vector3i.MIN:
			res.code = ERR_DEST_NOT_ON_BOARD
			return res
		if dloc.z < 0: #anchor is a zone header: same as inserting at column start
			dest = Anchor.column_start(dloc.x, dloc.y)
		elif dloc.x == src.x and dloc.y == src.y and dloc.z == src.z - 1:
			res.code = OK_NOOP #dropping the stack onto the card directly beneath it
			return res
	if dest.kind != Anchor.Kind.ON_TOP:
		if dest.col < 0 or dest.col >= zone(state, dest.x).size():
			res.code = ERR_DEST_OUT_OF_BOUNDS
			return res
		if dest.x == src.x and dest.col == src.y:
			if dest.kind == Anchor.Kind.COLUMN_START and src.z == 0:
				res.code = OK_NOOP #stack already starts the column
				return res
			if dest.kind == Anchor.Kind.COLUMN_END and src.z + count == src_col.datas.size():
				res.code = OK_NOOP #stack already ends the column
				return res

	# PHASE 3 — MUTATE (extract, then resolve the anchor, then insert)
	var src_cutoff : Array[CardData] = src_col.datas.slice(src.z + count)
	src_col.datas.resize(src.z)
	src_col.datas.append_array(src_cutoff)
	#the extraction shifted rows without a revision bump (the bump comes AFTER the
	#insert, per the guidelines) — invalidate so the post-extraction locate below
	#rebuilds the position index from the current arrays
	state.invalidate_pos_index()
	var dest_col : ArrayCardData
	var insert_row : int
	match dest.kind:
		Anchor.Kind.ON_TOP:
			var dloc := locate(state, dest.card) #post-extraction: always current
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

	# PHASE 4 (events) belongs to Game — board is consistent from here on
	state.revision += 1
	res.code = OK
	return res


# ==============================================================================
# Non-move mutations (§5 step 4) so mods don't write the zone arrays directly.
# ==============================================================================

## Places a card that is NOT on the board (e.g. freshly drawn) at a column end.
static func place_card(state: GameData, card: CardData, x: int, col: int) -> bool:
	if not card: return false
	if col < 0 or col >= zone(state, x).size(): return false
	if locate(state, card) != Vector3i.MIN: return false #already on the board
	zone(state, x)[col].datas.append(card)
	#don't re-set an already-PLAY stage: previous_stage drives the visual's spawn
	#origin (DRAW -> fly in from the deck), and re-setting would clobber it
	if card.stage != CardData.Stage.PLAY:
		card.stage = CardData.Stage.PLAY
	state.revision += 1
	return true

## Appends a header + empty column in lockstep (I2). ZoneAdder's add path.
static func add_column(state: GameData, zone_cols: Array[ArrayCardData], zone_types: Array[CardData], header: CardData) -> void:
	header.stage = CardData.Stage.ZONE
	zone_types.append(header)
	zone_cols.append(ArrayCardData.new())
	state.revision += 1

## Removes header + column in lockstep; returns the orphaned column cards so the
## caller can discard/relocate them. ZoneAdder's remove path.
static func remove_column(state: GameData, zone_cols: Array[ArrayCardData], zone_types: Array[CardData], index: int) -> Array[CardData]:
	if index < 0 or index >= zone_types.size() or index >= zone_cols.size():
		return []
	zone_types.remove_at(index)
	#pop BEFORE the bump: board_changed listeners run synchronously inside the bump and
	#must see types/columns already back in lockstep (the old order bumped mid-mutation)
	var orphans : Array[CardData] = zone_cols.pop_at(index).datas
	state.revision += 1
	return orphans


# ==============================================================================
# Grid-board mutations: place, move, remove-with-compaction. Same MUTATION
# GUIDELINES as above -- consistent state first, ONE revision bump after, no
# scene tree, no signals.
# ==============================================================================

## Result of a grid mutation: whether it happened, and whether the MOVER declared it a
## compaction. `is_compaction` is never computed from before/after heights -- it is
## whatever the caller passed to move_to_cell, echoed back so the board-mutation
## broadcast can read it without re-deriving it.
class GridMoveResult:
	extends RefCounted
	var ok : bool = false
	var is_compaction : bool = false

## Cell (x, y) of grid `grid_index` in `state`, or null when out of range.
static func _grid_at(state: GameData, grid_index: int) -> GridData:
	if grid_index < 0 or grid_index >= state.grids.size():
		return null
	return state.grids[grid_index]

## [grid_index, cell_index, height] of `card` in the grid board, or [] when the card is
## not in any grid cell.
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

## Public grid-board counterpart of `locate`: the card's coordinate, or `BoardCoord.NOWHERE` when
## it is not on any grid. Callers outside this file use this instead of `_locate_in_grid`'s raw
## triple, and test the result with `is_nowhere()` -- never `== BoardCoord.NOWHERE`.
static func locate_in_cell(state: GameData, card: CardData) -> BoardCoord:
	var loc := _locate_in_grid(state, card)
	if loc.is_empty(): return BoardCoord.NOWHERE
	var grid : GridData = state.grids[loc[0]]
	var cell_idx : int = loc[1]
	return BoardCoord.new(loc[0], cell_idx % grid.grid_width, cell_idx / grid.grid_width, loc[2])

## Places a card into a cell, at the TOP of its stack -- reuses the Anchor.ON_TOP rule
## (insert above whatever is already there) rather than trusting `coord.h`, so a caller can
## never hand in a height that disagrees with the stack it is landing on.
## ⚠ IT LIFTS THE CARD OUT OF THE ZONE COLUMN IT CAME FROM, as one mutation with the append.
## A card placed from the Entrance is in `upper_zone` until something takes it out, and there
## is no other path that does: appending without the lift leaves it in TWO collections, which
## validate() reports as a duplicate and which every position index then disagrees about.
## Zone HEADERS (row -1) are never lifted -- they belong to their column.
## Bumps revision exactly once, after the state is consistent again.
static func place_in_cell(state: GameData, card: CardData, coord: BoardCoord) -> bool:
	if not card: return false
	var grid := _grid_at(state, coord.grid)
	if not grid: return false
	if coord.x < 0 or coord.x >= grid.grid_width or coord.y < 0 or coord.y >= grid.grid_height:
		return false
	if not _locate_in_grid(state, card).is_empty():
		return false #already on the grid board
	var held := locate(state, card)
	if held != Vector3i.MIN and held.z > -1:
		zone(state, held.x)[held.y].datas.erase(card)
	var idx := grid.cell_index(coord.x, coord.y)
	grid.cells[idx].datas.append(card)
	#don't re-set an already-PLAY stage: previous_stage drives the visual's spawn origin
	if card.stage != CardData.Stage.PLAY:
		card.stage = CardData.Stage.PLAY
	state.revision += 1
	return true

## Moves a card already on the grid board to another cell, landing at that cell's top
## (Anchor.ON_TOP again). `is_compaction` is set BY THE CALLER -- never inferred from the
## source/destination heights -- and is carried on the returned result. Bumps revision
## exactly once.
static func move_to_cell(state: GameData, card: CardData, coord: BoardCoord, is_compaction: bool) -> GridMoveResult:
	var res := GridMoveResult.new()
	res.is_compaction = is_compaction
	if not card: return res
	var loc := _locate_in_grid(state, card)
	if loc.is_empty(): return res #not on the grid board -- place_in_cell's job
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

## Removes `card` from its cell. The array holding the stack IS the height axis, so
## popping the card out already drops every card above it down by one -- no separate
## per-card move is needed to compact. ONE revision bump for the whole compaction.
static func remove_from_cell(state: GameData, card: CardData) -> bool:
	var loc := _locate_in_grid(state, card)
	if loc.is_empty(): return false
	var grid : GridData = state.grids[loc[0]]
	grid.cells[loc[1]].datas.remove_at(loc[2])
	state.revision += 1
	return true

## Appends one grid to the board. Ensures its cells/cell_types are built to its own size
## BEFORE the append, mirroring add_column's header-and-column lockstep. One bump.
static func add_grid(state: GameData, grid: GridData) -> void:
	if not grid: return
	var expected := grid.grid_width * grid.grid_height
	if grid.cells.size() != expected or grid.cell_types.size() != expected:
		grid.build_cells()
	state.grids.append(grid)
	state.revision += 1

## Removes grid `index` and returns the orphaned in-play cards (not the cell zone type
## cards) for the caller to discard, mirroring remove_column's orphan contract. One bump.
static func remove_grid(state: GameData, index: int) -> Array[CardData]:
	if index < 0 or index >= state.grids.size():
		return []
	var grid : GridData = state.grids.pop_at(index)
	state.remove_grid_score_data(index)
	state.revision += 1
	var orphans : Array[CardData] = []
	if grid:
		for cell : ArrayCardData in grid.cells:
			if cell: orphans.append_array(cell.datas)
	return orphans
