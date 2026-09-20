## One scorer invocation's worth of cards.

#Rows and columns are the only shapes today; a future scorer may evaluate a diagonal, several rows
#at once, or an arbitrary set, and NOTHING that consumes this may assume otherwise.
class_name ScoringSection
extends RefCounted

#A row, a column, either diagonal family - flat or climbing through height - or a vertical run
#within one cell.

## Every shape a scoring line can take.
enum LineKind { ROW, COL, DIAG, HEIGHT_V }

#It is not derived from geometry and it is not result.meld.

## Every card participating in the hand. THIS IS THE SPOTLIGHT SET.
var cards : Array[CardData] = []
#NEVER branched on for behaviour; &"row" and &"col" are the values it takes today.

## Opaque provenance, for logging and the tuning tool only.
var origin : StringName = &""
var index : int = -1
var zone : Array = []
#score_line never branches on it: only construction and the legacy gutter write path may read it.

## Which shape this section is.
var kind : LineKind = LineKind.ROW
#score_line NEVER inspects its structure: the bucket derives from it downstream, not here.

## Opaque key identifying this line for whatever bucket it banks into.
var line_key : StringName = &""
#-1 means "not a grid line", a legacy zone section banking through the old zone-indexed path.
#These exist so the bucket a section banks into can be derived WITHOUT parsing the opaque line_key.

## Which grid this line belongs to, and where in it.
var grid : int = -1
#A grid's height-0 buckets are flat; raised levels are indexed by this.

## The height a ROW or COL line sits at.
var height : int = 0
#(-1, -1) for every other kind, none of which is tied to a single cell.

## The cell a HEIGHT_V line stands in, within its grid.
var cell : Vector2i = Vector2i(-1, -1)
## Every cell the line runs through as (x, y, h) in `grid`, card or no card; empty off the grid.
var line_cells : Array[Vector3i] = []
#Captured at construction so `origin` stays pure provenance, and so a future non-line shape
#supplies its own re-derivation instead of being misread as a column.

## How refresh() re-collects.
var _recollect : Callable = Callable()

#The section one Game.score_line() call evaluates is re-derived from the LIVE board.

#⚠ Never cache the result across a hook: a re-read is required after every one, because a
#handler may have added a card to the section or compacted one out of it.

#Ragged rows are the reason for the `row < a.size()` guard: it mirrors SkillEvalPokerBest exactly,
#so the section is the same card list the scorer evaluated.

#TODO(multi-meld membership): The Courier straddles two columns and The Puszta Five belongs to
#every one - one card scoring in SEVERAL MELDS. That is "which hand is this card in", decided here
#and in Game.score_line, not by grouping.

#⚠ Do not conflate that with multiplicity or with a grouping rule's pull-in: those are one meld
#reaching outward, this is one card belonging to several.

#⚠ LEGACY BRIDGE, temporary: it builds a section over the pre-grid upper_zone and lower_zone
#arrays, the only board SkillEvalPokerBest still reads. of_line_at is the grid-model constructor
#and is what every new caller should use; this one goes with the card it serves.
static func of_line(zone: Array, is_row: bool, index: int) -> ScoringSection:
	var section := ScoringSection.new()
	section.origin = &"row" if is_row else &"col"
	section.index = index
	section.zone = zone
	section.kind = LineKind.ROW if is_row else LineKind.COL
	section.line_key = StringName("legacy:%s:%d" % ["row" if is_row else "col", index])
	section._recollect = collect.bind(zone, is_row, index)
	section.cards = collect(zone, is_row, index)
	return section

#`grid` indexes state.grids, `index` is the row's y or the column's x, and `height` is the h every
#cell of a ROW or COL must hold a card at - a taller stack still counts.

#It re-derives from the LIVE board through state.card_at, so refresh() sees whatever a hook did to
#the board since construction.

## The grid-model constructor, for grid-backed callers.
static func of_line_at(state: GameData, grid: int, kind: LineKind, index: int, height: int) -> ScoringSection:
	var section := ScoringSection.new()
	section.kind = kind
	section.index = index
#⚠ THE GRID AND THE HEIGHT ARE PART OF THE SECTION, NOT ONLY OF ITS COLLECTION. Consumed here
#and thrown away, every section this constructor builds reads grid = -1, and a banked score then
#takes the LEGACY zone-gutter branch into an array the grid board does not render.

#The line still scores; nothing on the board shows it, and nothing pops.
	section.grid = grid
	section.height = height
	section.line_key = StringName("grid%d:%s:%d:%d" % [grid, LineKind.keys()[kind], index, height])
	section.line_cells = _line_cells_at(state, grid, kind, index, height)
	section._recollect = _collect_grid_line.bind(state, grid, kind, index, height)
	section.cards = section._recollect.call()
	return section

## THE card list for a ROW or COL of `state.grids[grid]` at `height`, re-derived live.
static func _collect_grid_line(state: GameData, grid: int, kind: LineKind, index: int, height: int) -> Array[CardData]:
	return _cards_on_cells(state, grid, _line_cells_at(state, grid, kind, index, height))

## The cells a ROW or COL of state.grids[grid] at `height` runs through, in the order it runs.
static func _line_cells_at(state: GameData, grid: int, kind: LineKind, index: int,
		height: int) -> Array[Vector3i]:
	var out : Array[Vector3i] = []
	if grid < 0 or grid >= state.grids.size(): return out
	var g : GridData = state.grids[grid]
	if not g: return out
	if kind == LineKind.ROW: out = LineGeometry.row_cells(g, index, height).cells
	elif kind == LineKind.COL: out = LineGeometry.col_cells(g, index, height).cells
	return out

#Any LineGeometry.Line - ROW, COL, DIAG or HEIGHT_V - becomes a section keyed by its grid, kind
#and endpoints: the one shape general enough for a line that does not reduce to of_line_at's index
#and height pair. Re-derives from the LIVE board.

## The detector-card constructor.
static func of_geometric_line(state: GameData, grid: int, line: LineGeometry.Line) -> ScoringSection:
	var section := ScoringSection.new()
	section.kind = line.kind
	section.grid = grid
#A ROW is one row at one height and a COL one column at one height, both fixed by any cell on the
#line, so the first one names them.
	var first : Vector3i = line.cells[0]
	section.height = first.z
	if line.kind == LineKind.ROW: section.index = first.y
	elif line.kind == LineKind.COL: section.index = first.x
	elif line.kind == LineKind.HEIGHT_V: section.cell = Vector2i(first.x, first.y)
	section.line_key = _key_for_geometric_line(grid, line)
	section.line_cells = line.cells
	section._recollect = _cards_on_cells.bind(state, grid, line.cells)
	section.cards = section._recollect.call()
	return section

#Two lines of the same kind through different cells never collide, and the same line asked for
#twice keys the same, because Line.cells is rebuilt identically from the same geometry.

## Opaque and unique per line: grid, kind and the line's own first and last cell.
static func _key_for_geometric_line(grid: int, line: LineGeometry.Line) -> StringName:
	var first : Vector3i = line.cells[0]
	var last : Vector3i = line.cells[line.cells.size() - 1]
	return StringName("grid%d:%s:%s:%s" % [grid, LineKind.keys()[line.kind], first, last])

## THE card list any line collects: every one of its cells that holds a card, read live.
static func _cards_on_cells(state: GameData, grid: int, cells: Array[Vector3i]) -> Array[CardData]:
	var out : Array[CardData] = []
	for c : Vector3i in cells:
		var card := state.card_at(BoardCoord.new(grid, c.x, c.y, c.z))
		if card: out.append(card)
	return out

#⚠ THE ZONES DIFFER IN EXACTLY ONE PLACE, AND THIS IS IT. Callers do not branch on where a card
#sits; they hand over a coordinate.

#An Entrance ROW banks into the Entrance's own bucket, which sits past the grid's own last row - an
#index, not a different code path. An Entrance COLUMN banks into that column's SHARED bucket, the
#one the grid column above it uses, keyed on the grid the Entrance is committed to.

## The section a score attributed to the card at `coord`, shaped as `kind`, banks into.
static func of_line_for(state: GameData, coord: BoardCoord, kind: LineKind) -> ScoringSection:
	if coord.is_entrance():
		if kind == LineKind.ROW:
			return of_entrance_row(state, coord.h)
		return of_line_at(state, state.entrance_grid(), kind, coord.x, coord.h)
	var index := coord.y if kind == LineKind.ROW else coord.x
	return of_line_at(state, coord.grid, kind, index, coord.h)

#It banks into the Entrance's OWN row bucket, as if the grid were one row taller than it is.
#`height` is the card's height within its Entrance slot's stack.

#⚠ This does NOT make the Entrance a detected line. Nothing completes here by default: the
#section exists so a score that already happened lands in the right bucket instead of the legacy
#one, which live_total() does not read.

## A score attributed to a card sitting in the ENTRANCE, shaped as a ROW.
static func of_entrance_row(state: GameData, height: int) -> ScoringSection:
	var section := ScoringSection.new()
	section.kind = LineKind.ROW
	section.grid = state.entrance_grid()
	section.index = state.entrance_row_index(section.grid)
	section.height = height
	section.origin = &"entrance"
	section.line_key = StringName("grid%d:ENTRANCE:%d" % [section.grid, height])
	section._recollect = _collect_entrance_row.bind(state, height)
	section.cards = section._recollect.call()
	return section

## Every card the Entrance holds at `height`, left to right, read live like every other collector.
static func _collect_entrance_row(state: GameData, height: int) -> Array[CardData]:
	var out : Array[CardData] = []
	for col : ArrayCardData in state.upper_zone:
		if col and height < col.datas.size() and col.datas[height]:
			out.append(col.datas[height])
	return out

## THE card list for a row or a column of `zone`. Static and pure, so a re-derive is one call.
static func collect(zone: Array, is_row: bool, index: int) -> Array[CardData]:
	var out : Array[CardData] = []
	if is_row:
		for a : ArrayCardData in zone:
			if index < a.datas.size(): out.append(a.datas[index])
	elif index >= 0 and index < zone.size():
		var col : ArrayCardData = zone[index]
		if col: out.append_array(col.datas)
	return out

#Returns true when the set CHANGED, which is what ends the activation sweep's loop.

## Re-read this section's cards from the board.
func refresh() -> bool:
	if not _recollect.is_valid(): return false
	var fresh : Array[CardData] = _recollect.call()
	if fresh == cards:
		return false
	cards = fresh
	return true
