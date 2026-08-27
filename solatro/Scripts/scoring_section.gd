## One scorer invocation's worth of cards. Rows and columns are the only shapes today; a future
## scorer may evaluate a diagonal, several rows at once, or an arbitrary set, and NOTHING that
## consumes this may assume otherwise (design Q260=a, Q266=a).
class_name ScoringSection
extends RefCounted

## Every shape a scoring line can take: a row, a column, either diagonal family (flat or
## climbing through height), or a vertical run within one cell.
enum LineKind { ROW, COL, DIAG, HEIGHT_V }

## Every card participating in the hand. THIS IS THE SPOTLIGHT SET (design Q31=d) — it is not
## derived from geometry and it is not `result.meld`.
var cards : Array[CardData] = []
## Opaque provenance, for logging and the tuning tool only. NEVER branched on for behaviour.
var origin : StringName = &""          # e.g. &"row", &"col"
var index : int = -1
var zone : Array = []
## Which shape this section is. `score_line` never branches on it — only construction and the
## (still legacy) gutter write path may read it.
var kind : LineKind = LineKind.ROW
## Opaque key identifying this line for whatever bucket it banks into. `score_line` NEVER
## inspects its structure — the bucket derives from it downstream, not here.
var line_key : StringName = &""
## How `refresh()` re-collects — captured at construction so `origin` stays pure provenance and a
## future non-line shape supplies its own re-derivation instead of being misread as a column.
var _recollect : Callable = Callable()

## The section one `Game.score_line(result, section)` call evaluates, re-derived from
## the LIVE board. ⚠ Never cache the result across a hook — `Q252`=(b) requires a re-read after
## every one, because a handler may have added a card to the section or compacted one out of it.
## Ragged rows are the reason for the `row < a.size()` guard: it mirrors `SkillEvalPokerBest`
## exactly, so the section is the same card list the scorer evaluated.
# TODO(multi-meld membership, Q54=a / comparator_buckets DEFERRED.md D4): The Courier straddles two
# columns and The Puszta Five belongs to every one — one card scoring in SEVERAL MELDS. That is
# "which hand is this card in", which is decided HERE and in `Game.score_line`, not by grouping.
# ⚠ Do not conflate it with multiplicity (D1) or with a grouping rule's pull-in (Q14=d): those are
# one meld reaching outward, this is one card belonging to several.
## ⚠ LEGACY BRIDGE, temporary: builds a section over the pre-grid `upper_zone`/`lower_zone`
## arrays, the only board `SkillEvalPokerBest` still reads. `of_line_at` is the grid-model
## constructor and is what every new caller should use; this one goes with the card it serves.
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

## The grid-model constructor (replaces `of_line` for grid-backed callers). `grid` indexes
## `state.grids`; `index` is the row's y or the column's x; `height` is the h every cell of a
## ROW/COL must hold a card at -- a taller stack still counts. Re-derives from the LIVE board,
## via `state.card_at`, so
## `refresh()` sees whatever a hook did to the board since construction.
static func of_line_at(state: GameData, grid: int, kind: LineKind, index: int, height: int) -> ScoringSection:
	var section := ScoringSection.new()
	section.kind = kind
	section.index = index
	section.line_key = StringName("grid%d:%s:%d:%d" % [grid, LineKind.keys()[kind], index, height])
	section._recollect = _collect_grid_line.bind(state, grid, kind, index, height)
	section.cards = section._recollect.call()
	return section

## THE card list for a ROW or COL of `state.grids[grid]` at `height`. DIAG/HEIGHT_V collection
## belongs to the detector card that finds those lines, not to this generic index+height shape.
static func _collect_grid_line(state: GameData, grid: int, kind: LineKind, index: int, height: int) -> Array[CardData]:
	var out : Array[CardData] = []
	if grid < 0 or grid >= state.grids.size(): return out
	var g : GridData = state.grids[grid]
	if not g: return out
	if kind == LineKind.ROW:
		for x in g.grid_width:
			var c := state.card_at(BoardCoord.new(grid, x, index, height))
			if c: out.append(c)
	elif kind == LineKind.COL:
		for y in g.grid_height:
			var c := state.card_at(BoardCoord.new(grid, index, y, height))
			if c: out.append(c)
	return out

## The detector-card constructor: any `LineGeometry.Line` (ROW, COL, DIAG or HEIGHT_V) becomes
## a section keyed by its grid, kind and endpoints -- the one shape general enough for a line
## that does not reduce to `of_line_at`'s index+height pair. Re-derives from the LIVE board.
static func of_geometric_line(state: GameData, grid: int, line: LineGeometry.Line) -> ScoringSection:
	var section := ScoringSection.new()
	section.kind = line.kind
	section.line_key = _key_for_geometric_line(grid, line)
	section._recollect = _collect_geometric_line.bind(state, grid, line.cells)
	section.cards = section._recollect.call()
	return section

## Opaque and unique per line: grid, kind and the line's own first/last cell -- two lines of the
## same kind through different cells never collide, and the same line asked for twice keys the
## same because `Line.cells` is rebuilt identically from the same geometry.
static func _key_for_geometric_line(grid: int, line: LineGeometry.Line) -> StringName:
	var first : Vector3i = line.cells[0]
	var last : Vector3i = line.cells[line.cells.size() - 1]
	return StringName("grid%d:%s:%s:%s" % [grid, LineKind.keys()[line.kind], first, last])

## THE card list for an arbitrary geometric line: every cell that holds a card, read live.
static func _collect_geometric_line(state: GameData, grid: int, cells: Array[Vector3i]) -> Array[CardData]:
	var out : Array[CardData] = []
	for c : Vector3i in cells:
		var card := state.card_at(BoardCoord.new(grid, c.x, c.y, c.z))
		if card: out.append(card)
	return out

## THE card list for a row or a column of `zone`. Static and pure so a re-derive is one call.
static func collect(zone: Array, is_row: bool, index: int) -> Array[CardData]:
	var out : Array[CardData] = []
	if is_row:
		for a : ArrayCardData in zone:
			if index < a.datas.size(): out.append(a.datas[index])
	elif index >= 0 and index < zone.size():
		var col : ArrayCardData = zone[index]
		if col: out.append_array(col.datas)
	return out

## Re-read this section's cards from the board (`Q252`=b). Returns true when the set CHANGED,
## which is what ends the activation sweep's loop.
func refresh() -> bool:
	if not _recollect.is_valid(): return false
	var fresh : Array[CardData] = _recollect.call()
	if fresh == cards:
		return false
	cards = fresh
	return true
