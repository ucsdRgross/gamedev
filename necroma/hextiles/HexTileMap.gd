extends TileMap

onready var astar = AStar2D.new()
onready var used_cells = get_used_cells()
onready var sprite = $testSprite

var travel_path : PoolVector2Array
var tile_width = cell_size.x
var tile_height = cell_size.y
var tile_size = tile_width / sqrt(3)

func _input(event):
	if event.is_action_pressed("left_mouse_button"):
		var mouse_pos = world_to_map(get_global_mouse_position())
		if used_cells.has(mouse_pos):
			var sprite_pos = world_to_map(sprite.global_position)
			set_travel_path(sprite_pos, mouse_pos)
			print(travel_path)
			print(world_to_hex(get_global_mouse_position()))

var testSprite = preload("res://testSprite.tscn")

func _ready():
	add_points()
	connect_points()
	for cell in used_cells:
		var new_node = testSprite.instance()
		new_node.position = map_to_world(cell)
		add_child(new_node)
		

func add_points() -> void:
	for cell in used_cells:
		print(cell)
		astar.add_point(id(cell),cell,1.0)

func connect_points() -> void:
	var even_row_neighbors = [Vector2(-1,-1),Vector2(0,-1),Vector2(-1,0),Vector2(1,0),Vector2(-1,1),Vector2(0,-1)]
	var odd_row_neighbors = [Vector2(0,-1),Vector2(1,-1),Vector2(-1,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]
	for cell in used_cells:
		var neighbors
		if int(cell.y) % 2 == 0:
			neighbors = even_row_neighbors
		else:
			neighbors = odd_row_neighbors
		for neighbor in neighbors:
			var next_cell = cell + neighbor
			if used_cells.has(next_cell):
				astar.connect_points(id(cell),id(next_cell),true)		

func set_travel_path(start, end) -> void:
	travel_path = astar.get_point_path(id(start),id(end))

func world_to_hex(glo_pos : Vector2) -> Vector2:
	#pixel to hex, https://www.redblobgames.com/grids/hexagons/#pixel-to-hex
	var x = glo_pos.x 
	var y = glo_pos.y * 1/scale.y
	var frac_q = (sqrt(3)/3 * x - (1.0/3) * y) / tile_size
	var frac_r = (2.0/3 * y) / tile_size
	#cube round
	var frac_s = -frac_q - frac_r
	var s = int(round(frac_s))
	var q = int(round(frac_q))
	var r = int(round(frac_r))
	var q_diff = abs(q - frac_q)
	var r_diff = abs(r - frac_r)
	var s_diff = abs(s - frac_s)
	if q_diff > r_diff and q_diff > s_diff:
		q = -r-s
	elif r_diff > s_diff:
		r = -q-s
	else:
		s = -q-r
	#axial_to_oddr
	q = (q + (r - (r&1))) / 2
	#finally done jesus christ that was heck
	return Vector2(q, r)

# Szudzik pairing function, does not work with negative values
func id(point: Vector2) -> int:
	var a = point.x
	var b = point.y
	return (a * a) + a + b if a >= b else (b * b) + a
