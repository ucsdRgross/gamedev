extends YSort

onready var astar = AStar2D.new()
var tile = preload("res://world/board/tile.tscn")
export var width : int = 9
export var height : int = 4
var row_offset = Vector2(23,-7)
var col_offset = Vector2(1,17)
var tile_dict = {}
var last_tile_clicked : Vector2

func _ready():
	create_grid()
	add_points()
	connect_points()

func find_path(start : Vector2, end : Vector2) -> PoolVector2Array:
	return astar.get_point_path(id(start),id(end))

func create_grid() -> void:
	for h in height:
		for w in width:
			var new_tile = tile.instance()
			var tile_coord = Vector2(w,h)
			new_tile.position = tile_to_grid(tile_coord)
			tile_dict[tile_coord] = new_tile
			add_child(new_tile)
			new_tile.setup(tile_coord)

func add_points() -> void:
	for coord in tile_dict.keys():
		astar.add_point(id(coord),coord,1.0)

func connect_points() -> void:
	var neighbors = [Vector2(-1,-1),Vector2(0,-1),Vector2(-1,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]
	for tile_coord in tile_dict.keys():
		for neighbor in neighbors:
			var next_tile = tile_coord + neighbor
			if tile_dict.has(next_tile):
				astar.connect_points(id(tile_coord),id(next_tile),true)
			
func tile_to_grid(coord : Vector2) -> Vector2:
	var x = coord.x * row_offset
	var y = coord.y * col_offset
	var pos = x + y
	return Vector2(pos.x, pos.y)

func tile_to_world(coord : Vector2) -> Vector2:
	var pos_on_grid = tile_to_grid(coord)
	return pos_on_grid + Vector2(position.x, position.y)

func id(coord : Vector2) -> int:
	var x = coord.x
	var y = coord.y
	var a = 2 * x if x >= 0 else -2 * x - 1
	var b = 2 * y if y >= 0 else -2 * y - 1
	var c = (a * a) + a + b if a >= b else (b * b) + a
	c *= 0.5
	if (((a >= 0.0) && (b < 0.0)) || ((a < 0.0) && (b >= 0.0))):
		return -c - 1
	return c
	
func on_tile_clicked(coord : Vector2):
	last_tile_clicked = coord
	print(last_tile_clicked)
