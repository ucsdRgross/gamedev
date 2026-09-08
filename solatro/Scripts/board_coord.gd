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

## ⚠ VALUE EQUALITY, BECAUSE `==` ON THIS TYPE IS IDENTITY.
##
## This is a RefCounted and GDScript has no operator overloading, so `a == b` compares OBJECTS:
## two coordinates naming the same cell are not equal, and a rebuilt sentinel is not `NOWHERE`.
## Compare with this, key dictionaries on `pack()`, and test the sentinel with `is_nowhere()`.
## A suite gate fails any `== BoardCoord.NOWHERE`, which is the shape that reads correctly and
## is wrong.
func equals(other: BoardCoord) -> bool:
	return other != null and grid == other.grid and x == other.x and y == other.y and h == other.h


## The value form, for dictionary keys and `Array.find` -- both of which hash and compare by
## identity on a RefCounted. `GameData._card_at_index` is already keyed this way.
func pack() -> Vector4i:
	return Vector4i(grid, x, y, h)


## Rebuilds a coordinate from its value form.
static func unpack(v: Vector4i) -> BoardCoord:
	return BoardCoord.new(v.x, v.y, v.z, v.w)


## True for the off-board sentinel, whether or not it is the shared `NOWHERE` instance.
func is_nowhere() -> bool:
	return grid == NOWHERE.grid and x == NOWHERE.x and y == NOWHERE.y and h == NOWHERE.h


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

## Two-axis step over the unbounded lattice. `dx` crosses grid boundaries along the single
## continuous ordinate (re-deriving `grid`/`x` from `grid_widths`, each grid's OWN bounding
## block width, left to right); `dy` simply offsets `y`, unbounded, grids are laid out
## horizontally only. NEVER fails, clamps or returns NOWHERE: past either end of the real
## board it keeps stepping through a virtual continuation at the nearest real edge grid's
## width, so movement looks identical to a grid being there. Whether a cell exists at the
## result is a separate question (GameData.has_cell) asked at landing, not here.
func step(dx: int, dy: int, grid_widths: Array[int]) -> BoardCoord:
	var target := BoardCoord.global_x(grid, x, grid_widths) + dx
	var total := 0
	for w : int in grid_widths:
		total += w
	var g : int
	var local_x : int
	if target < 0:
		var edge_width : int = grid_widths[0]
		var offset := -target
		var steps_back := (offset + edge_width - 1) / edge_width
		g = -steps_back
		local_x = edge_width * steps_back + target
	elif target >= total:
		var edge_width : int = grid_widths[grid_widths.size() - 1]
		var beyond := target - total
		g = grid_widths.size() + beyond / edge_width
		local_x = beyond % edge_width
	else:
		g = 0
		var remaining := target
		while remaining >= grid_widths[g]:
			remaining -= grid_widths[g]
			g += 1
		local_x = remaining
	return BoardCoord.new(g, local_x, y + dy, h)
