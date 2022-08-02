class_name Grid
extends Resource

# The grid's size in rows and columns.
export var size := Vector2(20, 20)
# roughly size of hex if it was a square
export var cell_size := Vector2(32, 18)
#moving over one to the right from one hex
var row_offset = Vector2(23,-7)
#moving down from hex
var col_offset = Vector2(1,17)

# Returns the position of a hex's center in pixels.
func rowcol_to_grid_position(rowcol : Vector2) -> Vector2:
	var x = rowcol.x * row_offset
	var y = rowcol.y * col_offset
	var pos = x + y
	return Vector2(pos.x, pos.y)

# reverse of above, not perfect though since it assumes cells are squares
# but its only for placing units in editor
func world_to_rowcol(map_position: Vector2) -> Vector2:
	return (map_position / cell_size).floor()

# single unique number assigned to a row and col
# Szudzik pairing function, does not work with negative values
func rowcol_id(cell: Vector2) -> int:
	var a = cell.x
	var b = cell.y
	return (a * a) + a + b if a >= b else (b * b) + a

# Szudzik pairing function for negative values
#func rowcol_id(coord : Vector2) -> int:
#	var x = coord.x
#	var y = coord.y
#	var a = 2 * x if x >= 0 else -2 * x - 1
#	var b = 2 * y if y >= 0 else -2 * y - 1
#	var c = (a * a) + a + b if a >= b else (b * b) + a
#	c *= 0.5
#	if (((a >= 0.0) && (b < 0.0)) || ((a < 0.0) && (b >= 0.0))):
#		return -c - 1
#	return c

