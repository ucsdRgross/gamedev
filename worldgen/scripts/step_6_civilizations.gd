class_name Step6Civilizations
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var attempts = 0
	var initial_candidates: Array[Vector2] = []
	var w = settings.map_width
	var h = settings.map_height
	
	while initial_candidates.size() < settings.max_city_count * 2 and attempts < 5000:
		var candidate = Vector2(randf() * w, randf() * h)
		var px = int(candidate.x)
		var py = int(candidate.y)
		
		if px >= 0 and px < w and py >= 0 and py < h:
			var idx = (py * w) + px
			var h_val = gen.height_buffer[idx]
			
			if h_val > (settings.ocean_threshold + 0.05) and h_val < settings.mountain_threshold:
				initial_candidates.append(candidate)
		attempts += 1
		
	var valid_mainland_map := _find_major_continents_mask_fast(gen, settings)
	
	for candidate in initial_candidates:
		if gen.city_nodes.size() >= settings.max_city_count: 
			break
		var pos_i = Vector2i(candidate)
		
		if valid_mainland_map.has(pos_i):
			var too_close = false
			for city in gen.city_nodes:
				if city.distance_to(candidate) < settings.min_city_dist:
					too_close = true
					break
			if not too_close:
				gen.city_nodes.append(candidate)
				
	# FIX: Points to the unified snapshot bridge configuration function
	gen._save_snapshot_bridge("Cities")

func _find_major_continents_mask_fast(gen: WorldGenerator, settings: WorldSettings) -> Dictionary:
	var visited := {}
	var continents: Array[Array] = []
	var w = settings.map_width
	var h = settings.map_height
	
	for y in range(0, h, 4): 
		for x in range(0, w, 4):
			var start_p = Vector2i(x, y)
			if visited.has(start_p): continue
			
			var idx = (y * w) + x
			if gen.height_buffer[idx] <= settings.ocean_threshold: 
				continue
				
			var current_continent: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start_p]
			visited[start_p] = true
			
			while not queue.is_empty():
				var curr = queue.pop_back()
				current_continent.append(curr)
				
				for offset in [Vector2i(-4,0), Vector2i(4,0), Vector2i(0,-4), Vector2i(0,4)]:
					var n = curr + offset
					if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h:
						var n_idx = (n.y * w) + n.x
						if not visited.has(n) and gen.height_buffer[n_idx] > settings.ocean_threshold:
							visited[n] = true
							queue.push_back(n)
			continents.append(current_continent)
			
	var major_continents_dict := {}
	if not continents.is_empty():
		continents.sort_custom(func(a, b): return a.size() > b.size())
		var kept_islands_count = min(2, continents.size())
		for i in range(kept_islands_count):
			for pos in continents[i]:
				for ox in range(4):
					for oy in range(4):
						var fill_p = pos + Vector2i(ox, oy)
						if fill_p.x < w and fill_p.y < h:
							major_continents_dict[fill_p] = true
							
	return major_continents_dict
