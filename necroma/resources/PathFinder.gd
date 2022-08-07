# Finds the path between two points among walkable cells using the AStar pathfinding algorithm.
class_name PathFinder
extends Resource

const even_row_neighbors = [Vector2(-1,-1),Vector2(0,-1),Vector2(-1,0),Vector2(1,0),Vector2(-1,1),Vector2(0,1)]
const odd_row_neighbors = [Vector2(0,-1),Vector2(1,-1),Vector2(-1,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]

#var _grid : Resource = preload("res://resources/Grid.tres")
var _astar := AStar2D.new()


func setup(tiles : PoolVector2Array) -> void:
	_add_and_connect_points(tiles)


func path_between(start: Vector2, end: Vector2) -> PoolVector2Array:
	var start_index: int = tile_id(start)
	var end_index: int = tile_id(end)
	# We just ensure that the AStar graph has both points defined. If not, we return an empty
	# PoolVector2Array() to avoid errors.
	if _astar.has_point(start_index) and _astar.has_point(end_index):
		# The AStar2D object then finds the best path between the two indices.
		return _astar.get_point_path(start_index, end_index)
	return PoolVector2Array()


func _add_and_connect_points(tiles : PoolVector2Array) -> void:
	var cell_mappings := {}
	
	for tile in tiles:
		cell_mappings[tile] = tile_id(tile)
	
	for point in cell_mappings:
		_astar.add_point(cell_mappings[point], point)

	for point in cell_mappings:
		var directions
		if int(point.y) % 2 == 0:
			print("even")
			directions = even_row_neighbors
		else:
			directions = odd_row_neighbors
		for neighbor in directions:
			var n_point = point + neighbor
			if cell_mappings.has(n_point):
				_astar.connect_points(tile_id(point),tile_id(n_point),true)

# Szudzik pairing function for negative values
func tile_id(coord : Vector2) -> int:
	var x = coord.x
	var y = coord.y
	var a = 2 * x if x >= 0 else -2 * x - 1
	var b = 2 * y if y >= 0 else -2 * y - 1
	var c = (a * a) + a + b if a >= b else (b * b) + a
	c *= 0.5
	if (((a >= 0.0) && (b < 0.0)) || ((a < 0.0) && (b >= 0.0))):
		return -c - 1
	return c
