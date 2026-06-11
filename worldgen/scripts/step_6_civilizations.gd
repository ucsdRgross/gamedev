class_name Step6Civilizations
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var attempts = 0
	var initial_candidates: Array[Vector2] = []
	
	while initial_candidates.size() < settings.max_city_count * 2 and attempts < 5000:
		var candidate = Vector2(randf() * settings.map_width, randf() * settings.map_height)
		var pos_i = Vector2i(candidate)
		var h_val = gen.fast_height_buffer[(pos_i.y * settings.map_width) + pos_i.x]
		
		if h_val > (settings.ocean_threshold + 0.05) and h_val < settings.mountain_threshold:
			initial_candidates.append(candidate)
		attempts += 1
		
	# FLOOD-FILL VALIDATION: Identifies and targets the largest continuous landmass
	var valid_mainland_map := _find_main_continent_mask(gen, settings)
	
	for candidate in initial_candidates:
		if gen.city_nodes.size() >= settings.max_city_count: 
			break
		var pos_i = Vector2i(candidate)
		
		# Only place nodes on the verified main continent, completely avoiding island traps
		if valid_mainland_map.has(pos_i):
			var too_close = false
			for city in gen.city_nodes:
				if city.distance_to(candidate) < settings.min_city_dist:
					too_close = true
					break
			if not too_close:
				gen.city_nodes.append(candidate)
				
	gen._save_snapshot("Cities")

func _find_main_continent_mask(gen: WorldGenerator, settings: WorldSettings) -> Dictionary:
	var visited := {}
	var continents: Array[Array] = []
	
	for y in range(0, settings.map_height, 4): # Step sample to speed up search loops
		for x in range(0, settings.map_width, 4):
			var start_p = Vector2i(x, y)
			if visited.has(start_p): continue
			if gen.fast_height_buffer[(start_p.y * settings.map_width) + start_p.x] <= settings.ocean_threshold: 
				continue
				
			# Run a local flood-fill queue scan
			var current_continent: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start_p]
			visited[start_p] = true
			
			while not queue.is_empty():
				var curr = queue.pop_back()
				current_continent.append(curr)
				
				for offset in [Vector2i(-4,0), Vector2i(4,0), Vector2i(0,-4), Vector2i(0,4)]:
					var n = curr + offset
					if n.x >= 0 and n.x < settings.map_width and n.y >= 0 and n.y < settings.map_height:
						if not visited.has(n) and gen.fast_height_buffer[(n.y * settings.map_width) + n.x] > settings.ocean_threshold:
							visited[n] = true
							queue.push_back(n)
			continents.append(current_continent)
			
	var main_continent_dict := {}
	if not continents.is_empty():
		continents.sort_custom(func(a, b): return a.size() > b.size())
		for pos in continents[0]:
			# Fill in the local micro block pixels
			for ox in range(4):
				for oy in range(4):
					main_continent_dict[pos + Vector2i(ox, oy)] = true
	return main_continent_dict
