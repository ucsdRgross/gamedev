extends YSort

onready var astar = AStar2D.new()
var tile = preload("res://world/board/tile.tscn")
export var width : int = 9
export var height : int = 4
var row_offset = Vector2(22,-9)
var col_offset = Vector2(2,20)
var tile_dict = {}

func _ready():
	create_grid()
	for key in tile_dict.keys():
		print(key)
		print(tile_dict.get(key).coord)
	#add_points()
	#connect_points()

func create_grid() -> void:
	for h in height:
		for w in width:
			var new_tile = tile.instance()
			var tile_coord = Vector2(w,h)
			new_tile.position = tile_to_world(tile_coord)
			new_tile.setup(tile_coord)
			tile_dict[tile_coord] = new_tile
			add_child(new_tile)

func add_points():
	for coord in tile_dict.keys():
		astar.add_point(id(coord),coord,1.0)

func tile_to_world(coord : Vector2) -> Vector2:
	var x = coord.x * row_offset
	var y = coord.y * col_offset
	var pos = x + y
	return Vector2(pos.x, pos.y)
	
func id(coord : Vector2) -> int:
	
