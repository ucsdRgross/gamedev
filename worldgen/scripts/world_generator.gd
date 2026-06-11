class_name WorldGenerator
extends Node

@export var settings: WorldSettings

var snapshots: Dictionary = {} 
var height_map: Dictionary       
var temperature_map: Dictionary  
var humidity_map: Dictionary     
var biome_map: Dictionary        
var river_nodes: Array[Vector2i] = [] 
var city_nodes: Array[Vector2] = []    
var gameplay_graph: Dictionary = {}   
var start_node: Vector2
var end_node: Vector2
var landmarks: Array[Dictionary] = [] 

var fast_height_buffer: PackedFloat32Array
signal generation_step_finished(step_name: String)

func _ready() -> void:
	settings = WorldSettings.new() 
	generate_world_map()

func generate_world_map() -> void:
	print("Orchestrating Modular Pipeline. Runtime Seed: ", settings.main_seed)
	
	snapshots.clear()
	height_map.clear()
	temperature_map.clear()
	humidity_map.clear()
	biome_map.clear()
	river_nodes.clear()
	city_nodes.clear()
	gameplay_graph.clear()
	landmarks.clear()
	
	fast_height_buffer.resize(settings.map_width * settings.map_height)
	seed(settings.main_seed)
	
	Step1Landmass.new().execute(self, settings)
	Step2Tectonics.new().execute(self, settings)
	Step3PeaksAndValleys.new().execute(self, settings)
	Step4Erosion.new().execute(self, settings)
	Step5Climate.new().execute(self, settings)
	Step6Civilizations.new().execute(self, settings)
	Step7Graph.new().execute(self, settings)
	
	_save_snapshot("All_Steps_Grid")
	print("Modular Generation Passes Complete!")

func _save_snapshot(step_name: String) -> void:
	snapshots[step_name] = {
		"height_map": height_map.duplicate(),
		"biome_map": biome_map.duplicate(),
		"river_nodes": river_nodes.duplicate(),
		"city_nodes": city_nodes.duplicate(),
		"gameplay_graph": gameplay_graph.duplicate(),
		"start_node": start_node,
		"end_node": end_node,
		"landmarks": landmarks.duplicate()
	}
	generation_step_finished.emit(step_name)

func _sync_fast_buffer() -> void:
	var w = settings.map_width
	for pos in height_map.keys():
		fast_height_buffer[(pos.y * w) + pos.x] = height_map[pos]

func _calculate_gradient(pos: Vector2) -> Vector2:
	var x = int(pos.x)
	var y = int(pos.y)
	var h00 = height_map.get(Vector2i(x, y), 0.0)
	var h10 = height_map.get(Vector2i(x+1, y), h00)
	var h01 = height_map.get(Vector2i(x, y+1), h00)
	return Vector2(h10 - h00, h01 - h00)

func _evaluate_raycast_cost(start_p: Vector2, end_p: Vector2) -> float:
	var total_penalty = 0.0
	var steps = 15
	var w = settings.map_width
	var h = settings.map_height
	
	for step in range(steps + 1):
		var check_p = Vector2i(start_p.lerp(end_p, float(step) / steps))
		if check_p.x < 0 or check_p.x >= w or check_p.y < 0 or check_p.y >= h: 
			return -1.0
			
		var height_val = fast_height_buffer[(check_p.y * w) + check_p.x]
		if height_val < settings.ocean_threshold:
			total_penalty += settings.water_penalty
		elif height_val >= settings.mountain_threshold:
			total_penalty += settings.mountain_penalty
			
	return total_penalty
