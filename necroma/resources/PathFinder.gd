# Finds the path between two points among walkable cells using the AStar pathfinding algorithm.
class_name PathFinder
extends Resource

const DIRECTIONS = [Vector2(-1,-1),Vector2(0,-1),Vector2(-1,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]

var _grid : Resource = preload("res://resources/Grid.tres")
var _astar := AStar2D.new()


func _init() -> void:
	_add_and_connect_points()


func path_between(start: Vector2, end: Vector2) -> PoolVector2Array:
	var start_index: int = _grid.id(start)
	var end_index: int = _grid.id(end)
	# We just ensure that the AStar graph has both points defined. If not, we return an empty
	# PoolVector2Array() to avoid errors.
	if _astar.has_point(start_index) and _astar.has_point(end_index):
		# The AStar2D object then finds the best path between the two indices.
		return _astar.get_point_path(start_index, end_index)
	return PoolVector2Array()


func _add_and_connect_points() -> void:
	var cell_mappings := {}
	
	var rows = _grid.size.x
	var cols = _grid.size.y

	for r in rows:
		for c in cols:
			var rowcol := Vector2(r,c)
			cell_mappings[rowcol] = _grid.id(rowcol)
	
	for point in cell_mappings:
		_astar.add_point(cell_mappings[point], point)

	for point in cell_mappings:
		for neighbor in DIRECTIONS:
			var n_point = point + neighbor
			if cell_mappings.has(n_point):
				_astar.connect_points(_grid.id(point),_grid.id(n_point),true)
