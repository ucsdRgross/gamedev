# world_data_context.gd
class_name WorldDataContext
extends RefCounted

var height_map: Dictionary       # Vector2i -> float
var temperature_map: Dictionary  # Vector2i -> float
var humidity_map: Dictionary     # Vector2i -> float
var biome_map: Dictionary        # Vector2i -> String
var river_nodes: Array[Vector2i] = [] 
var city_nodes: Array[Vector2] = []    
var gameplay_graph: Dictionary = {}   
var start_node: Vector2
var end_node: Vector2
var landmarks: Array[Dictionary] = [] 
var fast_height_buffer: PackedFloat32Array

func resize_buffers(w: int, h: int) -> void:
	fast_height_buffer.resize(w * h)

func sync_fast_buffer(w: int) -> void:
	for pos in height_map.keys():
		fast_height_buffer[(pos.y * w) + pos.x] = height_map[pos]

func calculate_gradient(pos: Vector2) -> Vector2:
	var x = int(pos.x)
	var y = int(pos.y)
	var h00 = height_map.get(Vector2i(x, y), 0.0)
	var h10 = height_map.get(Vector2i(x+1, y), h00)
	var h01 = height_map.get(Vector2i(x, y+1), h00)
	return Vector2(h10 - h00, h01 - h00)
