class_name LineGeometry
## Pure geometry: which lines of each ScoringSection.LineKind pass through one cell of one grid.

#It never crosses a grid boundary and never wraps. Finding a line here says nothing about whether
#it is COMPLETE: that is a scoring question the caller asks separately, by checking every cell in
#Line.cells against the live board.

#Its kind and every cell it runs through, in order, as (x, y, h) triples within the queried grid.

## One line found by lines_through.
class Line:
	var kind : ScoringSection.LineKind
	var cells : Array[Vector3i] = []

	func _init(p_kind: ScoringSection.LineKind, p_cells: Array[Vector3i]) -> void:
		kind = p_kind
		cells = p_cells

#The two flat corner-to-corner runs at dz=0, the four one-horizontal-axis-plus-height climbs, and
#the four corner-to-corner 3-D climbs. dz is always 0 or 1: a climb never goes down.

## Every climbing or flat DIAG direction as (dx, dy, dz).
const _DIAG_DIRECTIONS : Array[Vector3i] = [
	Vector3i(1, 1, 0), Vector3i(1, -1, 0),
	Vector3i(1, 0, 1), Vector3i(-1, 0, 1), Vector3i(0, 1, 1), Vector3i(0, -1, 1),
	Vector3i(1, 1, 1), Vector3i(1, -1, 1), Vector3i(-1, 1, 1), Vector3i(-1, -1, 1),
]

#Callers decide completeness by re-checking Line.cells against the live board.

## Every line of every kind that runs through cell (x, y, h) of `grid`.
static func lines_through(grid: GridData, x: int, y: int, h: int) -> Array:
	var out : Array[Line] = []
	if x < 0 or x >= grid.grid_width or y < 0 or y >= grid.grid_height or h < 0:
		return out
	out.append(row_cells(grid, y, h))
	out.append(col_cells(grid, x, h))
	out.append(_height_v(x, y, h))
	out.append_array(_diagonals(grid, x, y, h))
	return out

#Public so route builders reuse this exact within-one-grid, never-crosses-a-boundary walk instead
#of writing new row geometry.

## Every cell of row `y` at height `h`, full grid width, left to right.
static func row_cells(grid: GridData, y: int, h: int) -> Line:
	var cells : Array[Vector3i] = []
	for xi in grid.grid_width:
		cells.append(Vector3i(xi, y, h))
	return Line.new(ScoringSection.LineKind.ROW, cells)

## Every cell of column `x` at height `h`, full grid height. Public beside `row_cells`.
static func col_cells(grid: GridData, x: int, h: int) -> Line:
	var cells : Array[Vector3i] = []
	for yi in grid.grid_height:
		cells.append(Vector3i(x, yi, h))
	return Line.new(ScoringSection.LineKind.COL, cells)

#Always the WHOLE stack from the floor, never a slice: height_line_scores decides which of these
#runs actually pays out.

## The vertical run of cell (x, y) from height 0 up to and including `h`.
static func _height_v(x: int, y: int, h: int) -> Line:
	var cells : Array[Vector3i] = []
	for hi in (h + 1):
		cells.append(Vector3i(x, y, hi))
	return Line.new(ScoringSection.LineKind.HEIGHT_V, cells)

#RULE: a vertical stack scores only when its height is a multiple of this many cards, and scoring
#always pays the WHOLE stack - 5 pays the five, 10 pays all ten rather than netting the bottom five
#off, 15 pays all fifteen. Heights 6 to 9 pay nothing.

#`h` is 0-based, so a stack of N cards has topmost height N - 1.
const HEIGHT_SCORE_INTERVAL := 5

## Whether the vertical run ending at 0-based height `h` is one of the heights that scores.
static func height_line_scores(h: int) -> bool:
	return (h + 1) % HEIGHT_SCORE_INTERVAL == 0

## Is (x, y) inside this grid's own bounds?
static func _in_grid(grid: GridData, x: int, y: int) -> bool:
	return x >= 0 and x < grid.grid_width and y >= 0 and y < grid.grid_height

#Full length along whichever spatial axis moves, no wrapping, and never crossing this grid's edge.

## Every DIAG line, flat or climbing, that passes through (x, y, h).
static func _diagonals(grid: GridData, x: int, y: int, h: int) -> Array[Line]:
	var out : Array[Line] = []
	for dir : Vector3i in _DIAG_DIRECTIONS:
		var dx := dir.x
		var dy := dir.y
		var dz := dir.z
#A diagonal is a run whose x and y change at the SAME RATE; where it starts and ends is not part
#of the definition. Its full length is bounded by whichever grid dimension runs out first, and only
#a full-length run is a line.
		var length : int
		if dx != 0 and dy != 0:
			length = mini(grid.grid_width, grid.grid_height)
		elif dx != 0:
			length = grid.grid_width
		else:
			length = grid.grid_height

#Walk back from the queried cell to the first in-bounds cell of this run, then check the run
#reaches `length` cells without leaving the grid.
		var back := 0
		while _in_grid(grid, x - (back + 1) * dx, y - (back + 1) * dy):
			back += 1
		var x0 := x - back * dx
		var y0 := y - back * dy
		var run := 0
		while _in_grid(grid, x0 + run * dx, y0 + run * dy):
			run += 1
		if run < length:
			continue
#The climb must not start below the board.
		var h0 := h - back * dz
		if dz == 1 and h0 < 0:
			continue

		var cells : Array[Vector3i] = []
		for i in length:
			cells.append(Vector3i(x0 + i * dx, y0 + i * dy, h0 + i * dz))
		out.append(Line.new(ScoringSection.LineKind.DIAG, cells))
	return out
