class_name Step5Climate
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var t_noise = FastNoiseLite.new()
	t_noise.seed = settings.main_seed + 3
	t_noise.frequency = 0.006
	
	var h_noise = FastNoiseLite.new()
	h_noise.seed = settings.main_seed + 4
	h_noise.frequency = 0.007
	
	# COLLECT HIGH-ALTITUDE MOUNTAIN PEAKS FOR RIVER SEED ROOTS
	var mountain_tiles: Array[Vector2i] = []
	for pos in gen.height_map.keys():
		if gen.height_map[pos] >= settings.mountain_threshold:
			mountain_tiles.append(pos)
			
	# Fallback if specific seeds produce flat lands
	if mountain_tiles.is_empty():
		for pos in gen.height_map.keys():
			if gen.height_map[pos] > settings.ocean_threshold + 0.2:
				mountain_tiles.append(pos)
				
	mountain_tiles.shuffle()
	
	# TRACE CONVERGING SLOPES DOWN INTO VALLEYS & LAKE DEPRESSIONS
	var active_river_count = min(95, mountain_tiles.size())
	for i in range(active_river_count):
		var curr = Vector2(mountain_tiles[i])
		var lake_pooling_counter = 0
		
		for step in range(350):
			var curr_i = Vector2i(curr)
			if not gen.height_map.has(curr_i) or gen.height_map[curr_i] < settings.ocean_threshold: 
				break
				
			if not gen.river_nodes.has(curr_i): 
				gen.river_nodes.append(curr_i)
				
			var g = gen._calculate_gradient(curr)
			
			# LAKES GENERATION: If water hits a low rift valley floor basin, pool it into an inland lake
			if g.length() < 0.0012:
				lake_pooling_counter += 1
				if lake_pooling_counter > 5:
					# Dig down a localized depression water table pool
					for ox in range(-4, 5):
						for oy in range(-4, 5):
							var pool_p = curr_i + Vector2i(ox, oy)
							if gen.height_map.has(pool_p):
								gen.height_map[pool_p] = min(gen.height_map[pool_p], settings.ocean_threshold - 0.02)
					break
			else:
				lake_pooling_counter = 0
				
			curr -= g.normalized() * 1.5

	# MAP 12-TIER TACTICAL HAZARDOUS ECOSYSTEMS
	for pos in gen.height_map.keys():
		if gen.height_map[pos] < settings.ocean_threshold:
			gen.biome_map[pos] = "Ocean"
			continue
			
		var raw_t = (t_noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
		var raw_h = (h_noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
		
		var elevation = (gen.height_map[pos] - settings.ocean_threshold)
		gen.temperature_map[pos] = clamp(raw_t - (elevation * 0.5), 0.0, 1.0)
		
		var is_near_river = false
		for offset_x in range(-2, 3):
			for offset_y in range(-2, 3):
				if gen.river_nodes.has(pos + Vector2i(offset_x, offset_y)):
					is_near_river = true
					break
					
		gen.humidity_map[pos] = clamp(raw_h + (0.4 if is_near_river else 0.0), 0.0, 1.0)
		
		var t = gen.temperature_map[pos]
		var h = gen.humidity_map[pos]
		
		if gen.height_map[pos] >= settings.mountain_threshold:
			if t < 0.35: gen.biome_map[pos] = "Glacial Peak"
			elif t > 0.65: gen.biome_map[pos] = "Volcanic Crag"
			else: gen.biome_map[pos] = "Barren Ridges"
		elif t < 0.25: 
			gen.biome_map[pos] = "Cryo Frostwastes"
		elif t < 0.38: 
			if h < 0.4: gen.biome_map[pos] = "Tectonic Fissures"
			else: gen.biome_map[pos] = "Ashen Tundra"
		elif t > 0.65:
			if h < 0.3: gen.biome_map[pos] = "Salt Flats"
			elif h < 0.55: gen.biome_map[pos] = "Tornado Prairie"
			else: gen.biome_map[pos] = "Toxic Swamps"
		else:
			if h < 0.35: gen.biome_map[pos] = "Shattered Savannah"
			elif h < 0.6: gen.biome_map[pos] = "Seismic Plains"
			else: gen.biome_map[pos] = "Acidic Jungle"
			
	gen._sync_fast_buffer()
	
	gen.snapshots["Rivers_Only"] = {
		"height_map": gen.height_map.duplicate(),
		"biome_map": gen.biome_map.duplicate(),
		"river_nodes": gen.river_nodes.duplicate(),
		"city_nodes": [],
		"gameplay_graph": {},
		"start_node": Vector2.ZERO,
		"end_node": Vector2.ZERO,
		"landmarks": []
	}
	gen.generation_step_finished.emit("Rivers_Only")
	gen._save_snapshot("Climate")
