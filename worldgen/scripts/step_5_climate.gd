class_name Step5Climate
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var t_noise = FastNoiseLite.new()
	t_noise.seed = settings.main_seed + 3
	t_noise.frequency = 0.006
	
	var h_noise = FastNoiseLite.new()
	h_noise.seed = settings.main_seed + 4
	h_noise.frequency = 0.007
	
	var peak_tiles: Array[Vector2i] = []
	for pos in gen.height_map.keys():
		if gen.height_map[pos] >= settings.mountain_threshold:
			peak_tiles.append(pos)
	peak_tiles.shuffle()
	
	# FIX: Distribute river sources evenly using a Poisson separation distance check
	var seeded_river_origins: Array[Vector2i] = []
	for peak in peak_tiles:
		if seeded_river_origins.size() >= 45: 
			break
		var too_close = false
		for existing in seeded_river_origins:
			if Vector2(peak).distance_to(Vector2(existing)) < 40.0:
				too_close = true
				break
		if not too_close:
			seeded_river_origins.append(peak)
			
	for origin in seeded_river_origins:
		var curr = Vector2(origin)
		var stagnation_ticks = 0
		
		for step in range(250):
			var curr_i = Vector2i(curr)
			if not gen.height_map.has(curr_i) or gen.height_map[curr_i] < settings.ocean_threshold: 
				break
				
			if not gen.river_nodes.has(curr_i): 
				gen.river_nodes.append(curr_i)
				
			var g = gen._calculate_gradient(curr)
			
			# LAKE FORMATION: Water pools into natural valleys instead of cutting unlimited channels
			if g.length() < 0.0015:
				stagnation_ticks += 1
				if stagnation_ticks > 4:
					# Carve a localized lake basin depression
					for ox in range(-3, 4):
						for oy in range(-3, 4):
							var lake_p = curr_i + Vector2i(ox, oy)
							if gen.height_map.has(lake_p) and gen.height_map[lake_p] > settings.ocean_threshold:
								# Drop terrain slightly below ocean threshold to reveal a distinct inland lake color
								gen.height_map[lake_p] = min(gen.height_map[lake_p], settings.ocean_threshold - 0.01)
					break
			else:
				stagnation_ticks = 0
			curr -= g.normalized() * 1.5

	for pos in gen.height_map.keys():
		if gen.height_map[pos] < settings.ocean_threshold:
			gen.biome_map[pos] = "Ocean"
			continue
			
		var raw_t = (t_noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
		var raw_h = (h_noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
		var elevation = (gen.height_map[pos] - settings.ocean_threshold)
		
		gen.temperature_map[pos] = clamp(raw_t - (elevation * 0.5), 0.0, 1.0)
		
		var is_near_river = false
		for offset_x in range(-1, 2):
			for offset_y in range(-1, 2):
				if gen.river_nodes.has(pos + Vector2i(offset_x, offset_y)):
					is_near_river = true
					break
					
		gen.humidity_map[pos] = clamp(raw_h + (0.35 if is_near_river else 0.0), 0.0, 1.0)
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
