# Finds the path between two points among walkable cells using the AStar pathfinding algorithm.
class_name PathFinder
extends Resource

const even_row_neighbors = [Vector2(-1,-1),Vector2(0,-1),Vector2(-1,0),Vector2(1,0),Vector2(-1,1),Vector2(0,1)]
const odd_row_neighbors = [Vector2(0,-1),Vector2(1,-1),Vector2(-1,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]

#var _grid : Resource = preload("res://resources/Grid.tres")
var _astar := AStar2D.new()

#dictionary matching cell rowcol keys to unit values
var units := {}
var claims := {}
var playground : PoolVector2Array

func setup(background : PoolVector2Array, play_area : PoolVector2Array) -> void:
	playground = play_area
	_add_and_connect_points(background, play_area)
	for tile in background:
		claims[tile] = false

#cant do unit:Unit due to gdscript wonkiness
func unit_enter(unit) -> void:
	if units.has(unit.cell):
		print("ERROR unit entered and stacked on another unit at: " + str(unit.cell))
	units[unit.cell] = unit	

func unit_moved(unit, old_cell: Vector2, new_cell: Vector2) -> void:
#	if units.has(new_cell):
#		print("ERROR unit moved onto occupied cell at: " + str(new_cell) )
	#var unit = units[old_cell]
	if units[old_cell] == unit:
		units.erase(old_cell)
	units[new_cell] = unit

func unit_removed(cell: Vector2) -> void:
	units.erase(cell)

#returns true if cell empty or occupant is moving
#returns false if cell is already claimed by another unit
#recursively checks if units in the way can move, allow syncing of movement
#if units move at different speeds may need to add second paramater to only allow recursion forward with same speed units
func can_move_to(original_unit, unit, cell: Vector2) -> bool:
	if is_claimed(cell):
		return false
	if not units.has(cell):
		return true
	var unit_ahead = units[cell]
	#if units are in a merry go round formation, so it doesnt recurse forever
	if unit_ahead == original_unit:
		return true
	if not unit_ahead.is_walking:
		return false
	#if units are facing towards each other, dont phase through each other
	if unit.facing_direction == unit_ahead.facing_direction * -1:
		return false
	if unit_ahead.will_move:
		return true
	if unit_ahead.current_path.size() < 2:
		return false
	#recursive check
	if can_move_to(original_unit, unit_ahead, unit_ahead.current_path[1]):
		unit_ahead.will_move = true
		return true
	return false

func claim(cell: Vector2) -> void:
	claims[cell] = true

func unclaim(cell: Vector2) -> void:
	claims[cell] = false

func is_claimed(cell: Vector2) -> bool:
	return claims[cell]


func path_between(start: Vector2, end: Vector2, is_friend:bool) -> PoolVector2Array:
	var start_index: int = tile_id(start)
	var end_index: int = tile_id(end)
	# We just ensure that the AStar graph has both points defined. If not, we return an empty
	# PoolVector2Array() to avoid errors.
	if _astar.has_point(start_index) and _astar.has_point(end_index):
		#if end cell is occupied, path to closest cell to end cell
		var path : PoolVector2Array
		if _astar.is_point_disabled(end_index):
			_astar.set_point_disabled(end_index, false)
			path = _astar.get_point_path(start_index, end_index)
			_astar.set_point_disabled(end_index, true)
			if path.empty():
				return PoolVector2Array()
			#remove last point from path as its a disabled point
			path.remove(path.size() - 1)
			#if already next to target, would return a size 1 path, return nothing instead
			if path.size() < 2:
				return PoolVector2Array()
			#prevent friend from following enemy outside of arena
			if is_friend:
				for i in path:
					if not playground.has(i):
						return PoolVector2Array()
		else:
			path = _astar.get_point_path(start_index, end_index)
		# The AStar2D object then finds the best path between the two indices.
		return path
	return PoolVector2Array()


func _add_and_connect_points(background : PoolVector2Array, play_area : PoolVector2Array) -> void:
	var cell_mappings := {}
	
	for tile in background:
		cell_mappings[tile] = tile_id(tile)
		#play area cell costs make units prefer to stay inside play area
		if tile in play_area:
			_astar.add_point(cell_mappings[tile], tile, .001)
		else:
			_astar.add_point(cell_mappings[tile], tile, 100)

	for point in cell_mappings:
		var directions
		if int(point.y) % 2 == 0:
			directions = even_row_neighbors
		else:
			directions = odd_row_neighbors
		for neighbor in directions:
			var n_point = point + neighbor
			if cell_mappings.has(n_point):
				_astar.connect_points(tile_id(point),tile_id(n_point),true)

func is_point_disabled(point:Vector2) -> bool:
	return _astar.is_point_disabled(tile_id(point))

func set_point_disabled(point:Vector2, disabled:bool) -> void:	
	_astar.set_point_disabled(tile_id(point), disabled)

# Cantor pairing function for negative values
func tile_id(coord : Vector2) -> int:
	var x = coord.x
	var y = coord.y
	var a = 2 * x if x >= 0 else -2 * x - 1
	var b = 2 * y if y >= 0 else -2 * y - 1
	var c = (0.5 * (a + b) * (a + b + 1)) + b
	#var c = (a * a) + a + b if a >= b else (b * b) + a
	#c *= 0.5
	#if (((a >= 0.0) && (b < 0.0)) || ((a < 0.0) && (b >= 0.0))):
	#	return -c - 1
	return c
