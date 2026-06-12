class_name WorldGenerator
extends Node

@export var settings: WorldSettings

# --- Master Snapshot Dict Cache Storage for the Viewer ---
var snapshots: Dictionary = {} 

# --- FAST DATA-ORIENTED 1D CONTINUOUS ARRAYS (Bypasses Hashmaps) ---
var height_buffer: PackedFloat32Array = PackedFloat32Array()
var temp_buffer: PackedFloat32Array = PackedFloat32Array()
var humid_buffer: PackedFloat32Array = PackedFloat32Array()
var biome_id_buffer: PackedInt32Array = PackedInt32Array()
var plate_id_buffer: PackedInt32Array = PackedInt32Array()

# Maps string biome keys to packed integers for low-level performance
var biome_palette: Array[String] = [
	"Ocean", "Glacial Peak", "Volcanic Crag", "Barren Ridges", 
	"Cryo Frostwastes", "Tectonic Fissures", "Ashen Tundra", "Salt Flats", 
	"Tornado Prairie", "Toxic Swamps", "Shattered Savannah", "Seismic Plains", "Acidic Jungle"
]

# Structural trackers needed for your gameplay vector loops
var river_nodes: Array[Vector2i] = [] 
var city_nodes: Array[Vector2] = []    
var gameplay_graph: Dictionary = {}   
var start_node: Vector2
var end_node: Vector2
var landmarks: Array[Dictionary] = [] 

signal generation_step_finished(step_name: String)

func _ready() -> void:
	if not settings: 
		settings = WorldSettings.new() 
	generate_world_map()

func generate_world_map() -> void:
	var start_time = Time.get_ticks_msec()
	
	snapshots.clear()
	river_nodes.clear()
	city_nodes.clear()
	gameplay_graph.clear()
	landmarks.clear()
	
	var total_cells = settings.map_width * settings.map_height
	height_buffer.resize(total_cells)
	temp_buffer.resize(total_cells)
	humid_buffer.resize(total_cells)
	biome_id_buffer.resize(total_cells)
	plate_id_buffer.resize(total_cells)
	
	seed(settings.main_seed)
	
	# SLOT 1 [ROW 0, COL 0] -> Base Landmass Shape Template
	Step1Landmass.new().execute(self, settings)
	_save_snapshot_bridge("Landmass")
	
	# SLOT 2 & 3 [ROW 0, COL 1 & 2] -> Tectonics Blueprint and Deformation Ranges
	Step2Tectonics.new().execute(self, settings)
	# NOTE: Step2Tectonics handles internal memory arrays, and we record 
	# their translated states down directly in order below:
	_save_snapshot_bridge("Tectonics_Debug")
	_save_snapshot_bridge("Tectonics")
	
	# SLOT 4 [ROW 1, COL 0] -> Fine Noise Ridges, Peaks, and Valleys
	Step3PeaksAndValleys.new().execute(self, settings)
	_save_snapshot_bridge("PeaksAndValleys")
	
	# SLOT 5 [ROW 1, COL 1] -> High-Contrast Hydraulic Erosion Pass Softening Ranges
	Step4Erosion.new().execute(self, settings)
	_save_snapshot_bridge("Erosion")
	
	# SLOT 6 & 7 [ROW 1, COL 2 & ROW 2, COL 0] -> Hydrography Continuous Streams and Climate Biomes
	Step5Climate.new().execute(self, settings)
	_save_snapshot_bridge("Rivers_Only")
	_save_snapshot_bridge("Climate")
	
	# Clamp island boundaries cleanly inside ocean limits before cities populate
	_clamp_island_boundaries_fast()
	
	# SLOT 8 [ROW 2, COL 1] -> Multi-Continent Poisson Disc Node Distribution
	Step6Civilizations.new().execute(self, settings)
	
	# SLOT 9 [ROW 2, COL 2] -> DFS Pruned Forward Left-to-Right Graph Pathways
	Step7Graph.new().execute(self, settings)
	
	# Emit standard 3x3 layout notifications
	var ordered_keys = ["Landmass", "Tectonics_Debug", "Tectonics", "PeaksAndValleys", "Erosion", "Rivers_Only", "Climate", "Cities", "Graph"]
	for k in ordered_keys:
		if snapshots.has(k):
			generation_step_finished.emit(k)
		
	_save_snapshot_bridge("All_Steps_Grid")
	generation_step_finished.emit("All_Steps_Grid") 
	print("OPTIMIZED SYNC ENGINE COMPLETION TIME: ", Time.get_ticks_msec() - start_time, " ms")

func _clamp_island_boundaries_fast() -> void:
	var w = settings.map_width
	var cx = w / 2.0
	var cy = settings.map_height / 2.0
	var max_radius = min(w, settings.map_height) * 0.44
	
	for y in range(settings.map_height):
		for x in range(w):
			var idx = (y * w) + x
			var d = Vector2(x, y).distance_to(Vector2(cx, cy))
			if d > max_radius:
				var fade = clamp(1.0 - ((d - max_radius) / 45.0), 0.0, 1.0)
				height_buffer[idx] *= fade
				if fade <= 0.0:
					height_buffer[idx] = min(height_buffer[idx], settings.ocean_threshold - 0.05)

func _save_snapshot_bridge(step_name: String) -> void:
	# FIX: Translates all flat array elements to full dictionary mappings globally 
	# to stop "height_map missing" lookup crashes inside the viewer loop.
	var w = settings.map_width
	var fake_h_map: Dictionary = {}
	var fake_b_map: Dictionary = {}
	
	for y in range(settings.map_height):
		for x in range(w):
			var idx = (y * w) + x
			var pos = Vector2i(x, y)
			fake_h_map[pos] = height_buffer[idx]
			var b_id = biome_id_buffer[idx]
			fake_b_map[pos] = biome_palette[b_id] if b_id < biome_palette.size() else "Ocean"
			
	snapshots[step_name] = {
		"height_map": fake_h_map,
		"biome_map": fake_b_map,
		"river_nodes": river_nodes.duplicate(),
		"city_nodes": city_nodes.duplicate(),
		"gameplay_graph": gameplay_graph.duplicate(),
		"start_node": start_node, "end_node": end_node,
		"landmarks": landmarks.duplicate(),
		"plate_id_buffer": plate_id_buffer.duplicate() # Keep the plate ID array cached for fast border scanner lookups
	}

func _calculate_gradient_fast(x: int, y: int) -> Vector2:
	var w = settings.map_width
	var h = settings.map_height
	var idx = (y * w) + x
	var h00 = height_buffer[idx]
	var h10 = height_buffer[(y * w) + (x + 1)] if x + 1 < w else h00
	var h01 = height_buffer[((y + 1) * w) + x] if y + 1 < h else h00
	return Vector2(h10 - h00, h01 - h00)

func _evaluate_raycast_cost(start_p: Vector2, end_p: Vector2) -> float:
	var total_penalty = 0.0
	var steps = 15
	var w = settings.map_width
	
	for step in range(steps + 1):
		var check_p = Vector2i(start_p.lerp(end_p, float(step) / steps))
		if check_p.x < 0 or check_p.x >= w or check_p.y < 0 or check_p.y >= settings.map_height: 
			return -1.0
			
		var height_val = height_buffer[(check_p.y * w) + check_p.x]
		if height_val < settings.ocean_threshold:
			total_penalty += settings.water_penalty
		elif height_val >= settings.mountain_threshold:
			total_penalty += settings.mountain_penalty
			
	return total_penalty
