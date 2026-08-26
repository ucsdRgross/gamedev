class_name BoardCoord
extends RefCounted
## The four-component board coordinate: which grid, a column continuous across every
## grid, a row (the Entrance is row -1 of whichever grid it is currently attached to),
## and a height within the cell's stack.

var grid : int
var x : int
var y : int
var h : int

## Row index of the Entrance: it is stacked above/below the grid it is attached to,
## never a row of the grid itself.
const ENTRANCE_ROW := -1

## The off-board sentinel. Never equal to any legal on-board coordinate (never
## `(0,0,0,0)`), matching `Vector3i.MIN`'s role for the old 3-component position.
static var NOWHERE : BoardCoord

static func _static_init() -> void:
	NOWHERE = BoardCoord.new(-2147483648, -2147483648, -2147483648, -2147483648)

func _init(p_grid: int = 0, p_x: int = 0, p_y: int = 0, p_h: int = 0) -> void:
	grid = p_grid
	x = p_x
	y = p_y
	h = p_h

## True when this coordinate is the Entrance (row -1 of its attached grid).
func is_entrance() -> bool:
	return y == ENTRANCE_ROW

## The single global column ordinate `x` is continuous across: every column of grid 0,
## then every column of grid 1, and so on.
static func global_x(p_grid: int, p_x: int, grid_widths: Array[int]) -> int:
	var total := 0
	for i : int in range(p_grid):
		total += grid_widths[i]
	return total + p_x

## Column arithmetic that crosses grid boundaries: `n` columns of the single continuous
## ordinate, then `grid`/`x` are re-derived from `grid_widths` (each grid's OWN width,
## left to right). `y` and `h` are unchanged. Walking off either edge of the board CLAMPS
## to the nearest legal column (provisional pending a design ruling -- see
## solatro/design/poker-patience/gaps/).
func step_x(n: int, grid_widths: Array[int]) -> BoardCoord:
	var target := BoardCoord.global_x(grid, x, grid_widths) + n
	var total := 0
	for w : int in grid_widths:
		total += w
	if target < 0:
		return BoardCoord.new(0, 0, y, h)
	if target >= total:
		return BoardCoord.new(grid_widths.size() - 1, grid_widths[grid_widths.size() - 1] - 1, y, h)
	var g := 0
	var remaining := target
	while remaining >= grid_widths[g]:
		remaining -= grid_widths[g]
		g += 1
	return BoardCoord.new(g, remaining, y, h)
