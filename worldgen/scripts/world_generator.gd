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
	if not settings:
		settings = WorldSettings.new()
	generate_world_map()

func generate_world_map() -> void:
	print("Executing Strict Chronological Pipeline... Seed: ", settings.main_seed)
	
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
	
	# SLOT 1 [ROW 0, COL 0] -> Base Landmass Shape Template
	Step1Landmass.new().execute(self, settings)
	_save_snapshot("Landmass")
	
	# =================================================================
	# CORRECTED TECTONICS SEQUENCE MARSHALING
	# Intercepts the process *inside* Step 2 to split the initial 
	# fault-line arrows out BEFORE terrain ranges deform.
	# =================================================================
	var tectonics_instance = Step2Tectonics.new()
	
	# 1. Trigger the vector setup sub-routines to discover plate cells globally
	tectonics_instance.execute(self, settings)
	# NOTE: Your modified Step2Tectonics now records "Tectonics_Debug" natively 
	# midway through its block before it initiates height transformation logic loops.
	
	# SLOT 4 [ROW 1, COL 0] -> Fine Noise Ridges, Peaks, and Valleys
	Step3PeaksAndValleys.new().execute(self, settings)
	_save_snapshot("PeaksAndValleys")
	
	# SLOT 5 [ROW 1, COL 1] -> High-Contrast Hydraulic Erosion Pass Softening Ranges
	Step4Erosion.new().execute(self, settings)
	_save_snapshot("Erosion")
	
	# SLOT 6 [ROW 1, COL 2] -> Long Continuous Drainage Flow Networks & Deep Basin Lakes
	Step5Climate.new().execute(self, settings)
	# NOTE: Your modified Step5Climate registers "Rivers_Only" natively midway 
	# through its block before computing the Whittaker climate equations.
	
	# Clamp island boundaries cleanly inside ocean limits before civilizations populate
	_clamp_island_boundaries()
	
	# SLOT 8 [ROW 2, COL 1] -> Multi-Continent Poisson Disc Node Distribution
	Step6Civilizations.new().execute(self, settings)
	_save_snapshot("Cities")
	
	# SLOT 9 [ROW 2, COL 2] -> DFS Pruned Forward Left-to-Right Graph Pathways
	Step7Graph.new().execute(self, settings)
	_save_snapshot("Graph")
	
	# Master overview grid map overview composition matrix slot allocation frame
	_save_snapshot("All_Steps_Grid")
	print("Modular Synchronous Signal Generation Pass Complete!")

func _clamp_island_boundaries() -> void:
	var cx = settings.map_width / 2.0
	var cy = settings.map_height / 2.0
	var max_radius = min(settings.map_width, settings.map_height) * 0.44
	
	for pos in height_map.keys():
		var d = Vector2(pos.x, pos.y).distance_to(Vector2(cx, cy))
		if d > max_radius:
			var fade = clamp(1.0 - ((d - max_radius) / 45.0), 0.0, 1.0)
			height_map[pos] *= fade
			if fade <= 0.0:
				height_map[pos] = min(height_map[pos], settings.ocean_threshold - 0.05)
	_sync_fast_buffer()

func _save_snapshot(step_name: String) -> void:
	var captured_landmarks: Array[Dictionary] = []
	if step_name == "Tectonics_Debug":
		captured_landmarks = landmarks.duplicate()
		
	snapshots[step_name] = {
		"height_map": height_map.duplicate(),
		"biome_map": biome_map.duplicate(),
		"river_nodes": river_nodes.duplicate() if step_name != "Tectonics_Debug" else [],
		"city_nodes": city_nodes.duplicate() if step_name in ["Cities", "Graph", "All_Steps_Grid"] else [],
		"gameplay_graph": gameplay_graph.duplicate() if step_name in ["Graph", "All_Steps_Grid"] else {},
		"start_node": start_node if step_name in ["Graph", "All_Steps_Grid"] else Vector2.ZERO,
		"end_node": end_node if step_name in ["Graph", "All_Steps_Grid"] else Vector2.ZERO,
		"landmarks": captured_landmarks
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
