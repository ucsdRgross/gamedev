# world_generator.gd
class_name WorldGenerator
extends Node

## A data-driven procedural world generator for an FTL-style map.
## Generates landmasses, biomes, cities, and a traversal graph.

@export var settings: WorldSettings

# --- Pipeline State Data ---
var height_map: Dictionary       # Vector2i -> float (0.0 to 1.0)
var temperature_map: Dictionary  # Vector2i -> float
var humidity_map: Dictionary     # Vector2i -> float
var biome_map: Dictionary        # Vector2i -> String (Biome name)
var river_nodes: Array[Vector2i] # Points that are part of rivers
var city_nodes: Array[Vector2]    # Poisson disc sampled points
var gameplay_graph: Dictionary   # Vector2 -> Array[Vector2] (Node connections)
var start_node: Vector2
var end_node: Vector2

# Signals for visualization
signal generation_step_finished(step_name: String)

func _ready() -> void:
	if not settings:
		settings = WorldSettings.new()
	# generate_world_map() # Called by WorldViewer after signal connection

# ==========================================
# MAIN GENERATION PIPELINE
# ==========================================
func generate_world_map() -> void:
	print("Starting World Generation...")
	seed(settings.main_seed)
	
	_step_1_generate_land()
	_step_2_tectonics_and_erosion()
	_step_3_hydrography_and_climate()
	_step_4_civilizations_and_territory()
	_step_5_gameplay_graph()
	
	print("World Generation Complete!")

# ==========================================
# STEP 1: LANDMASS & COASTLINES (STALBERG / NOISE)
# ==========================================
func _step_1_generate_land() -> void:
	print("Step 1: Generating Landmass...")
	var continent_noise = FastNoiseLite.new()
	continent_noise.seed = settings.main_seed
	continent_noise.frequency = settings.continent_frequency
	
	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = settings.main_seed + 1
	detail_noise.frequency = settings.detail_frequency
	
	for y in range(settings.map_height):
		for x in range(settings.map_width):
			var pos = Vector2i(x, y)
			
			# Base Continent Shape
			var h = (continent_noise.get_noise_2d(x, y) + 1.0) / 2.0
			h += (detail_noise.get_noise_2d(x, y) * 0.1)
			
			# Stalberg Grid / Radial Mask
			var center = Vector2(settings.map_width/2.0, settings.map_height/2.0)
			var d = Vector2(x, y).distance_to(center)
			var max_d = min(settings.map_width, settings.map_height) * 0.45
			var mask = clamp(1.0 - (d / max_d), 0.0, 1.0)
			mask = pow(mask, 0.5) 
			
			height_map[pos] = h * mask
	
	generation_step_finished.emit("Landmass")

# ==========================================
# STEP 2: TECTONICS & EROSION
# ==========================================
func _step_2_tectonics_and_erosion() -> void:
	print("Step 2: Simulating Tectonics & Erosion...")
	
	# simplified "continental drift" ridges
	var ridge_noise = FastNoiseLite.new()
	ridge_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	ridge_noise.frequency = 0.01
	ridge_noise.seed = settings.main_seed + 2
	
	for pos in height_map.keys():
		if height_map[pos] > settings.ocean_threshold:
			var ridge = abs(ridge_noise.get_noise_2d(pos.x, pos.y))
			height_map[pos] += ridge * 0.15
			
	# Simple Hydraulic Erosion
	_apply_erosion(5000)
	
	generation_step_finished.emit("Erosion")

func _apply_erosion(iterations: int) -> void:
	var inertia = 0.05
	var sediment_capacity_factor = 4.0
	var min_sediment_capacity = 0.01
	var erode_speed = 0.3
	var deposit_speed = 0.3
	var evaporate_speed = 0.01
	var gravity = 4.0
	
	for i in range(iterations):
		var pos = Vector2(randf() * settings.map_width, randf() * settings.map_height)
		var vel = Vector2.ZERO
		var water = 1.0
		var sediment = 0.0
		
		for step in range(30):
			var pos_i = Vector2i(pos)
			if not height_map.has(pos_i): break
			
			# Calculate gradient
			var g = _calculate_gradient(pos)
			vel = vel * inertia - g * (1.0 - inertia)
			var new_pos = pos + vel
			
			if not height_map.has(Vector2i(new_pos)): break
			
			var h_diff = height_map[Vector2i(new_pos)] - height_map[pos_i]
			var capacity = max(-h_diff * vel.length() * water * sediment_capacity_factor, min_sediment_capacity)
			
			if sediment > capacity or h_diff > 0:
				var amount = (sediment - capacity) * deposit_speed if h_diff < 0 else min(h_diff, sediment)
				sediment -= amount
				height_map[pos_i] += amount
			else:
				var amount = min((capacity - sediment) * erode_speed, -h_diff)
				sediment += amount
				height_map[pos_i] -= amount
				
			vel = vel.normalized() * sqrt(vel.length_squared() + h_diff * gravity)
			water *= (1.0 - evaporate_speed)
			pos = new_pos

func _calculate_gradient(pos: Vector2) -> Vector2:
	var x = int(pos.x)
	var y = int(pos.y)
	var h00 = height_map.get(Vector2i(x, y), 0.0)
	var h10 = height_map.get(Vector2i(x+1, y), h00)
	var h01 = height_map.get(Vector2i(x, y+1), h00)
	return Vector2(h10 - h00, h01 - h00)

# ==========================================
# STEP 3: HYDROGRAPHY & CLIMATE
# ==========================================
func _step_3_hydrography_and_climate() -> void:
	print("Step 3: Generating Climate...")
	
	for pos in height_map.keys():
		var lat_temp = 1.0 - abs(float(pos.y) / settings.map_height - 0.5) * 2.0
		temperature_map[pos] = lat_temp - (height_map[pos] * 0.4)
		
		# Humidity: Proximity to "ocean" (< 0.3)
		var hum = 0.4
		if height_map[pos] < settings.ocean_threshold + 0.1: hum += 0.4
		humidity_map[pos] = clamp(hum, 0.0, 1.0)
		
		if height_map[pos] < settings.ocean_threshold:
			biome_map[pos] = "Ocean"
		else:
			var t = temperature_map[pos]
			var h = humidity_map[pos]
			if t < 0.2: biome_map[pos] = "Arctic"
			elif t < 0.4: biome_map[pos] = "Tundra"
			elif t > 0.7:
				if h < 0.4: biome_map[pos] = "Desert"
				else: biome_map[pos] = "Rainforest"
			else:
				if h < 0.5: biome_map[pos] = "Savanna"
				else: biome_map[pos] = "Forest"

	generation_step_finished.emit("Climate")

# ==========================================
# STEP 4: CIVILIZATIONS
# ==========================================
func _step_4_civilizations_and_territory() -> void:
	print("Step 4: Distributing Cities...")
	var attempts = 0
	while city_nodes.size() < settings.max_city_count and attempts < 2000:
		var candidate = Vector2(randf() * settings.map_width, randf() * settings.map_height)
		var pos_i = Vector2i(candidate)
		
		if height_map.get(pos_i, 0.0) > settings.ocean_threshold + 0.1:
			var too_close = false
			for city in city_nodes:
				if city.distance_to(candidate) < settings.min_city_dist:
					too_close = true
					break
			if not too_close:
				city_nodes.append(candidate)
		attempts += 1
		
	generation_step_finished.emit("Cities")

# ==========================================
# STEP 5: GAMEPLAY PATH
# ==========================================
func _step_5_gameplay_graph() -> void:
	print("Step 5: Building Gameplay Graph...")
	if city_nodes.size() < 2: return
	
	# Select Start and End
	var best_pair = [city_nodes[0], city_nodes[1]]
	var max_d = 0.0
	for i in range(city_nodes.size()):
		for j in range(i + 1, city_nodes.size()):
			var d = city_nodes[i].distance_to(city_nodes[j])
			if d > max_d:
				max_d = d
				best_pair = [city_nodes[i], city_nodes[j]]
	
	start_node = best_pair[0]
	end_node = best_pair[1]
	
	var travel_vec = end_node - start_node
	var travel_normalized = travel_vec.normalized()
	var step_size = travel_vec.length() / settings.path_steps
	
	var layers: Array[Array] = []
	for i in range(settings.path_steps + 1):
		layers.append([])
	
	for city in city_nodes:
		var projection = (city - start_node).dot(travel_normalized)
		var idx = clampi(int(projection / step_size), 0, settings.path_steps)
		layers[idx].append(city)
	
	if not start_node in layers[0]: layers[0].append(start_node)
	if not end_node in layers[settings.path_steps]: layers[settings.path_steps].append(end_node)
	
	for i in range(settings.path_steps):
		for current in layers[i]:
			gameplay_graph[current] = []
			var next_options = layers[i+1]
			if next_options.is_empty() and i+2 <= settings.path_steps:
				next_options = layers[i+2]
			
			next_options.sort_custom(func(a, b): return current.distance_to(a) < current.distance_to(b))
			for j in range(min(3, next_options.size())):
				gameplay_graph[current].append(next_options[j])
				
	generation_step_finished.emit("Graph")
