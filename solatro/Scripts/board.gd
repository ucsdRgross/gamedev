class_name Board
## Pure board move logic over GameData (ARCHITECTURE_REVIEW.md §5).
## Destinations are ANCHORS (card references / column ends), not indices, so the
## extraction step can never invalidate the destination — the anchor is resolved
## AFTER extraction and the whole same-column compensation math disappears.
## No scene tree, no signals, no mod events: Game keeps Phase 4 (event firing).

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
static func locate(state: GameData, data: CardData) -> Vector3i:
	var i := state.upper_zone_type.find(data)
	if i > -1: return Vector3i(0, i, -1)
	i = state.lower_zone_type.find(data)
	if i > -1: return Vector3i(1, i, -1)
	for zone_x in 2:
		var z := zone(state, zone_x)
		for c in z.size():
			var row := z[c].datas.find(data)
			if row > -1: return Vector3i(zone_x, c, row)
	return Vector3i.MIN

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
	card.stage = CardData.Stage.PLAY
	return true

## Appends a header + empty column in lockstep (I2). ZoneAdder's add path.
static func add_column(zone_cols: Array[ArrayCardData], zone_types: Array[CardData], header: CardData) -> void:
	header.stage = CardData.Stage.ZONE
	zone_types.append(header)
	zone_cols.append(ArrayCardData.new())

## Removes header + column in lockstep; returns the orphaned column cards so the
## caller can discard/relocate them. ZoneAdder's remove path.
static func remove_column(zone_cols: Array[ArrayCardData], zone_types: Array[CardData], index: int) -> Array[CardData]:
	if index < 0 or index >= zone_types.size() or index >= zone_cols.size():
		return []
	zone_types.remove_at(index)
	return zone_cols.pop_at(index).datas
