class_name LineGeometry
## Pure geometry: which lines of each ScoringSection.LineKind pass through one cell, within
## one grid. Never crosses a grid boundary and never wraps. Finding a line here says nothing
## about whether it is COMPLETE -- that is a scoring question the caller asks separately by
## checking every cell in `Line.cells` against the live board.

## One line found by `lines_through`: its kind and every cell it runs through, in order,
## as (x, y, h) triples within the queried grid.
class Line:
	var kind : ScoringSection.LineKind
	var cells : Array[Vector3i] = []

	func _init(p_kind: ScoringSection.LineKind, p_cells: Array[Vector3i]) -> void:
		kind = p_kind
		cells = p_cells

## Every climbing/flat DIAG direction as (dx, dy, dz): the two flat corner-to-corner runs
## (dz=0), the four "one horizontal axis plus height" climbs, and the four corner-to-corner
## 3-D climbs -- the full family the design calls for. dz is always 0 or 1; a climb never
## goes down.
const _DIAG_DIRECTIONS : Array[Vector3i] = [
	Vector3i(1, 1, 0), Vector3i(1, -1, 0),
	Vector3i(1, 0, 1), Vector3i(-1, 0, 1), Vector3i(0, 1, 1), Vector3i(0, -1, 1),
	Vector3i(1, 1, 1), Vector3i(1, -1, 1), Vector3i(-1, 1, 1), Vector3i(-1, -1, 1),
]

## Every line of every kind that runs through cell (x, y, h) of `grid`. Callers decide
## completeness by re-checking `Line.cells` against the live board.
static func lines_through(grid: GridData, x: int, y: int, h: int) -> Array:
	var out : Array[Line] = []
	if x < 0 or x >= grid.grid_width or y < 0 or y >= grid.grid_height or h < 0:
		return out
	out.append(_row(grid, y, h))
	out.append(_col(grid, x, h))
	out.append(_height_v(x, y, h))
	out.append_array(_diagonals(grid, x, y, h))
	return out

## Every cell of row `y` at height `h`, full grid width.
static func _row(grid: GridData, y: int, h: int) -> Line:
	var cells : Array[Vector3i] = []
	for xi in grid.grid_width:
		cells.append(Vector3i(xi, y, h))
	return Line.new(ScoringSection.LineKind.ROW, cells)

## Every cell of column `x` at height `h`, full grid height.
static func _col(grid: GridData, x: int, h: int) -> Line:
	var cells : Array[Vector3i] = []
	for yi in grid.grid_height:
		cells.append(Vector3i(x, yi, h))
	return Line.new(ScoringSection.LineKind.COL, cells)

## The vertical run of cell (x, y) from height 0 up to and including h. The 5/10/15
## multiple-of-5 windowing that decides which of these runs actually SCORES is a later
## step's rule, not geometry's.
static func _height_v(x: int, y: int, h: int) -> Line:
	var cells : Array[Vector3i] = []
	for hi in (h + 1):
		cells.append(Vector3i(x, y, hi))
	return Line.new(ScoringSection.LineKind.HEIGHT_V, cells)

## Every DIAG line (flat or climbing) that passes through (x, y, h), full length along
## whichever spatial axis moves, no wrapping, never crossing this grid's boundary.
static func _in_grid(grid: GridData, x: int, y: int) -> bool:
	return x >= 0 and x < grid.grid_width and y >= 0 and y < grid.grid_height

## Every DIAG line (flat or climbing) that passes through (x, y, h), full length along
## whichever spatial axis moves, no wrapping, never crossing this grid's boundary.
static func _diagonals(grid: GridData, x: int, y: int, h: int) -> Array[Line]:
	var out : Array[Line] = []
	for dir : Vector3i in _DIAG_DIRECTIONS:
		var dx := dir.x
		var dy := dir.y
		var dz := dir.z
		# A diagonal is a run whose x and y change at the SAME RATE; where it starts and
		# ends is not part of the definition. Its full length is bounded by whichever grid
		# dimension runs out first, and only a full-length run is a line.
		var length : int
		if dx != 0 and dy != 0:
			length = mini(grid.grid_width, grid.grid_height)
		elif dx != 0:
			length = grid.grid_width
		else:
			length = grid.grid_height

		# Walk back from the queried cell to the first in-bounds cell of this run, then
		# check the run reaches `length` cells without leaving the grid.
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
		# The climb must not start below the board.
		var h0 := h - back * dz
		if dz == 1 and h0 < 0:
			continue

		var cells : Array[Vector3i] = []
		for i in length:
			cells.append(Vector3i(x0 + i * dx, y0 + i * dy, h0 + i * dz))
		out.append(Line.new(ScoringSection.LineKind.DIAG, cells))
	return out
