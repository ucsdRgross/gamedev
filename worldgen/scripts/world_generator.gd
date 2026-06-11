# world_generator.gd
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
	print("Executing World Pipeline. Active Runtime Seed: ", settings.main_seed)
	
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
	
	_step_1_generate_land()
	_step_2_tectonic_drift()
	_step_3_peaks_and_valleys()
	_step_4_hydraulic_erosion()
	_step_5_hydrography_and_climate()
	_step_6_civilizations()
	_step_7_gameplay_graph()
	
	_save_snapshot("All_Steps_Grid")
	print("World Generation Complete!")

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

func _step_1_generate_land() -> void:
	var continent_noise = FastNoiseLite.new()
	continent_noise.seed = settings.main_seed
	continent_noise.frequency = settings.continent_frequency
	
	for y in range(settings.map_height):
		for x in range(settings.map_width):
			var pos = Vector2i(x, y)
			var h = (continent_noise.get_noise_2d(x, y) + 1.0) / 2.0
			
			var center = Vector2(settings.map_width/2.0, settings.map_height/2.0)
			var d = Vector2(x, y).distance_to(center)
			var max_d = min(settings.map_width, settings.map_height) * 0.44
			var mask = clamp(1.0 - (d / max_d), 0.0, 1.0)
			mask = pow(mask, 0.7) 
			
			height_map[pos] = h * mask
	_save_snapshot("Landmass")

func _step_2_tectonic_drift() -> void:
	var plate_centers: Array[Vector2] = []
	var plate_directions: Array[Vector2] = []
	
	# Domain warp noise profile configuration to smooth out sharp edge line boundaries
	var warp_noise = FastNoiseLite.new()
	warp_noise.seed = settings.main_seed + 15
	warp_noise.frequency = 0.02
	
	for i in range(settings.plate_count):
		plate_centers.append(Vector2(randf() * settings.map_width, randf() * settings.map_height))
		plate_directions.append(Vector2(randf() - 0.5, randf() - 0.5).normalized())
		
	for pos in height_map.keys():
		if height_map[pos] > settings.ocean_threshold:
			# Apply continuous coordinate offset shifts to clean up cellular grid lines
			var wx = pos.x + int(warp_noise.get_noise_2d(pos.x, pos.y) * 45.0)
			var wy = pos.y + int(warp_noise.get_noise_2d(pos.y, pos.x) * 45.0)
			var warped_pos = Vector2(wx, wy)
			
			var closest_plate = 0
			var min_dist = 99999.0
			for i in range(plate_centers.size()):
				var d = warped_pos.distance_to(plate_centers[i])
				if d < min_dist:
					min_dist = d
					closest_plate = i
					
			var to_center = (plate_centers[closest_plate] - warped_pos).normalized()
			var collision_force = to_center.dot(plate_directions[closest_plate])
			
			if collision_force > 0.1: # Convergent border -> Carve mountain ridges
				height_map[pos] += collision_force * settings.drift_intensity * (1.0 - clamp(min_dist / 220.0, 0.0, 1.0))
			elif collision_force < -0.1: # Divergent border -> Form rift valley trenches
				height_map[pos] = max(settings.ocean_threshold + 0.02, height_map[pos] - abs(collision_force) * 0.18)
				
	_save_snapshot("Tectonics")

func _step_3_peaks_and_valleys() -> void:
	var ridge_noise = FastNoiseLite.new()
	ridge_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	ridge_noise.frequency = 0.015
	ridge_noise.seed = settings.main_seed + 2
	
	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = settings.main_seed + 5
	detail_noise.frequency = settings.detail_frequency
	
	for pos in height_map.keys():
		if height_map[pos] > settings.ocean_threshold:
			var ridge = 1.0 - abs(ridge_noise.get_noise_2d(pos.x, pos.y))
			var detail = detail_noise.get_noise_2d(pos.x, pos.y) * 0.12
			height_map[pos] = clamp(height_map[pos] + (pow(ridge, 3.0) * 0.45) + detail, 0.0, 1.2)
	_save_snapshot("PeaksAndValleys")

func _step_4_hydraulic_erosion() -> void:
	var inertia = 0.05
	var sediment_capacity_factor = 5.0
	var min_sediment_capacity = 0.02
	var erode_speed = 0.5 
	var deposit_speed = 0.5
	
	for i in range(12000): 
		var pos = Vector2(randf() * settings.map_width, randf() * settings.map_height)
		var vel = Vector2.ZERO
		var sediment = 0.0
		
		for _step in range(30):
			var pos_i = Vector2i(pos)
			if not height_map.has(pos_i): break
			
			var g = _calculate_gradient(pos)
			vel = vel * inertia - g * (1.0 - inertia)
			var new_pos = pos + vel
			if not height_map.has(Vector2i(new_pos)): break
			
			var h_diff = height_map[Vector2i(new_pos)] - height_map[pos_i]
			var capacity = max(-h_diff * vel.length() * sediment_capacity_factor, min_sediment_capacity)
			
			if sediment > capacity or h_diff > 0:
				var amount = (sediment - capacity) * deposit_speed if h_diff < 0 else min(h_diff, sediment)
				sediment -= amount
				height_map[pos_i] += amount
			else:
				var amount = min((capacity - sediment) * erode_speed, -h_diff)
				sediment += amount
				height_map[pos_i] -= amount
			pos = new_pos
			
	_sync_fast_buffer() 
	_save_snapshot("Erosion")

func _calculate_gradient(pos: Vector2) -> Vector2:
	var x = int(pos.x)
	var y = int(pos.y)
	var h00 = height_map.get(Vector2i(x, y), 0.0)
	var h10 = height_map.get(Vector2i(x+1, y), h00)
	var h01 = height_map.get(Vector2i(x, y+1), h00)
	return Vector2(h10 - h00, h01 - h00)

func _step_5_hydrography_and_climate() -> void:
	var t_noise = FastNoiseLite.new()
	t_noise.seed = settings.main_seed + 3
	t_noise.frequency = 0.006
	
	var h_noise = FastNoiseLite.new()
	h_noise.seed = settings.main_seed + 4
	h_noise.frequency = 0.007
	
	for i in range(85): 
		var curr = Vector2(randf() * settings.map_width, randf() * settings.map_height)
		if height_map.get(Vector2i(curr), 0.0) > 0.55:
			for step in range(300):
				var curr_i = Vector2i(curr)
				if not height_map.has(curr_i) or height_map[curr_i] < settings.ocean_threshold: break
				if not river_nodes.has(curr_i): river_nodes.append(curr_i)
				var g = _calculate_gradient(curr)
				if g.length() < 0.001: break
				curr -= g.normalized() * 1.5

	for pos in height_map.keys():
		if height_map[pos] < settings.ocean_threshold:
			biome_map[pos] = "Ocean"
			continue
			
		var raw_t = (t_noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
		var raw_h = (h_noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
		
		var elevation = (height_map[pos] - settings.ocean_threshold)
		temperature_map[pos] = clamp(raw_t - (elevation * 0.5), 0.0, 1.0)
		
		var is_near_river = false
		for offset_x in range(-2, 3):
			for offset_y in range(-2, 3):
				if river_nodes.has(pos + Vector2i(offset_x, offset_y)):
					is_near_river = true
					break
					
		humidity_map[pos] = clamp(raw_h + (0.4 if is_near_river else 0.0), 0.0, 1.0)
		
		var t = temperature_map[pos]
		var h = humidity_map[pos]
		
		# 12-Tier Tactical Hazard Biome Matrix mapping configuration
		if height_map[pos] >= settings.mountain_threshold:
			if t < 0.35: biome_map[pos] = "Glacial Peak"
			elif t > 0.65: biome_map[pos] = "Volcanic Crag"
			else: biome_map[pos] = "Barren Ridges"
		elif t < 0.25: 
			biome_map[pos] = "Cryo Frostwastes"
		elif t < 0.38: 
			if h < 0.4: biome_map[pos] = "Tectonic Fissures"
			else: biome_map[pos] = "Ashen Tundra"
		elif t > 0.65:
			if h < 0.3: biome_map[pos] = "Salt Flats"
			elif h < 0.55: biome_map[pos] = "Tornado Prairie"
			else: biome_map[pos] = "Toxic Swamps"
		else:
			if h < 0.35: biome_map[pos] = "Shattered Savannah"
			elif h < 0.6: biome_map[pos] = "Seismic Plains"
			else: biome_map[pos] = "Acidic Jungle"
	_save_snapshot("Climate")

func _step_6_civilizations() -> void:
	var attempts = 0
	while city_nodes.size() < settings.max_city_count and attempts < 6000:
		var candidate = Vector2(randf() * settings.map_width, randf() * settings.map_height)
		var pos_i = Vector2i(candidate)
		var h_val = height_map.get(pos_i, 0.0)
		
		var valid_placement = false
		if h_val > (settings.ocean_threshold + 0.04) and h_val < settings.mountain_threshold:
			valid_placement = true
			
		if valid_placement:
			var too_close = false
			for city in city_nodes:
				if city.distance_to(candidate) < settings.min_city_dist:
					too_close = true
					break
			if not too_close:
				city_nodes.append(candidate)
		attempts += 1
	_save_snapshot("Cities")

func _step_7_gameplay_graph() -> void:
	if city_nodes.size() < 2: return
	
	var best_pair: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
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
	var is_horizontal: bool = abs(travel_normalized.x) > abs(travel_normalized.y)
	
	var layers: Array = []
	for i in range(settings.path_steps + 1):
		var typed_inner: Array[Vector2] = []
		layers.append(typed_inner)
		
	for city in city_nodes:
		var projection = (city - start_node).dot(travel_normalized)
		var idx = clampi(int(projection / step_size), 0, settings.path_steps)
		layers[idx].push_back(city)
		
	var layers_has_start = false
	for layer in layers:
		if layer.has(start_node): 
			layers_has_start = true
			break
	if not layers_has_start: 
		layers[0].push_back(start_node)
		
	var layers_has_end = false
	if layers[settings.path_steps].has(end_node): 
		layers_has_end = true
	if not layers_has_end: 
		layers[settings.path_steps].push_back(end_node)
		
	for i in range(1, settings.path_steps):
		if layers[i].is_empty():
			var fallback_pos = start_node + (travel_normalized * (step_size * i))
			city_nodes.append(fallback_pos)
			layers[i].push_back(fallback_pos)
			
	for i in range(settings.path_steps + 1):
		if is_horizontal: 
			layers[i].sort_custom(func(a, b): return a.y < b.y)
		else: 
			layers[i].sort_custom(func(a, b): return a.x < b.x)
			
	for i in range(settings.path_steps):
		var current_layer = layers[i]
		var next_layer = layers[i+1]
		
		for current in current_layer:
			gameplay_graph[current] = []
			var valid_targets = []
			
			for candidate in next_layer:
				var d = current.distance_to(candidate)
				# ENFORCE SHIFT DISTANCE BOUNDS: Block zig-zags by requiring links to sit inside min/max length caps
				if d >= settings.min_path_dist and d <= settings.max_path_dist:
					var penalty = _evaluate_raycast_cost(current, candidate)
					if penalty >= 0.0:
						valid_targets.append({"pos": candidate, "score": d + penalty})
						
			valid_targets.sort_custom(func(a, b): return a.score < b.score)
			
			# TUNE BRANCHING CHOICES: Clamps options dynamically based on setting handles
			var target_branches = min(randi_range(settings.min_choices, settings.max_choices), valid_targets.size())
			for b in range(target_branches):
				gameplay_graph[current].append(valid_targets[b].pos)
				
	gameplay_graph[end_node] = []
	_save_snapshot("Graph")

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
