class_name Step5Climate
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var t_noise = FastNoiseLite.new()
	t_noise.seed = settings.main_seed + 3
	t_noise.frequency = 0.006
	
	var h_noise = FastNoiseLite.new()
	h_noise.seed = settings.main_seed + 4
	h_noise.frequency = 0.007
	
	var w = settings.map_width
	var h = settings.map_height
	
	var mountain_tiles: Array[Vector2i] = []
	for y in range(h):
		for x in range(w):
			var idx = (y * w) + x
			if gen.height_buffer[idx] >= settings.mountain_threshold:
				mountain_tiles.append(Vector2i(x, y))
				
	if mountain_tiles.is_empty():
		for y in range(h):
			for x in range(w):
				var idx = (y * w) + x
				if gen.height_buffer[idx] > settings.ocean_threshold + 0.2:
					mountain_tiles.append(Vector2i(x, y))
					
	var spaced_roots: Array[Vector2i] = []
	mountain_tiles.shuffle()
	for tile in mountain_tiles:
		var too_close = false
		for root in spaced_roots:
			if Vector2(tile).distance_to(Vector2(root)) < 32.0:
				too_close = true
				break
		if not too_close:
			spaced_roots.append(tile)
			if spaced_roots.size() >= 45: break

	for root in spaced_roots:
		var curr = Vector2(root)
		var visited_path: Array[Vector2i] = []
		
		for step in range(400):
			var cx = int(curr.x)
			var cy = int(curr.y)
			if cx < 0 or cx >= w or cy < 0 or cy >= h: break
			
			var idx = (cy * w) + cx
			if gen.height_buffer[idx] < settings.ocean_threshold: break
			
			var curr_i = Vector2i(cx, cy)
			if not gen.river_nodes.has(curr_i): 
				gen.river_nodes.append(curr_i)
			visited_path.append(curr_i)
			
			var g = gen._calculate_gradient_fast(cx, cy)
			
			if g.length() < 0.0015:
				var lowest_neighbor = curr_i
				var min_h = gen.height_buffer[idx]
				
				for ox in [-1, 0, 1]:
					for oy in [-1, 0, 1]:
						var nx = cx + ox
						var ny = cy + oy
						if nx >= 0 and nx < w and ny >= 0 and ny < h:
							var n_pos = Vector2i(nx, ny)
							if not visited_path.has(n_pos):
								var n_idx = (ny * w) + nx
								if gen.height_buffer[n_idx] < min_h:
									min_h = gen.height_buffer[n_idx]
									lowest_neighbor = n_pos
									
				if lowest_neighbor == curr_i:
					for ox in range(-5, 6):
						for oy in range(-5, 6):
							var lx = cx + ox
							var ly = cy + oy
							if lx >= 0 and lx < w and ly >= 0 and ly < h:
								if Vector2(ox, oy).length() <= 5.0:
									gen.height_buffer[(ly * w) + lx] = min(gen.height_buffer[(ly * w) + lx], settings.ocean_threshold - 0.03)
					break
				else:
					curr = Vector2(lowest_neighbor)
			else:
				curr -= g.normalized() * 1.5

	for y in range(h):
		for x in range(w):
			var idx = (y * w) + x
			var val = gen.height_buffer[idx]
			
			if val < settings.ocean_threshold:
				gen.biome_id_buffer[idx] = 0 # "Ocean"
				continue
				
			var raw_t = (t_noise.get_noise_2d(x, y) + 1.0) / 2.0
			var raw_h = (h_noise.get_noise_2d(x, y) + 1.0) / 2.0
			
			var elevation = (val - settings.ocean_threshold)
			gen.temp_buffer[idx] = clamp(raw_t - (elevation * 0.5), 0.0, 1.0)
			
			var is_near_river = false
			for offset_x in range(-2, 3):
				for offset_y in range(-2, 3):
					var rx = x + offset_x
					var ry = y + offset_y
					if rx >= 0 and rx < w and ry >= 0 and ry < h:
						if gen.river_nodes.has(Vector2i(rx, ry)):
							is_near_river = true
							break
							
			gen.humid_buffer[idx] = clamp(raw_h + (0.4 if is_near_river else 0.0), 0.0, 1.0)
			var t = gen.temp_buffer[idx]
			var h_val = gen.humid_buffer[idx]
			
			# Map to Palette Array Indices
			if val >= settings.mountain_threshold:
				if t < 0.35: gen.biome_id_buffer[idx] = 1 # "Glacial Peak"
				elif t > 0.65: gen.biome_id_buffer[idx] = 2 # "Volcanic Crag"
				else: gen.biome_id_buffer[idx] = 3 # "Barren Ridges"
			elif t < 0.25: 
				gen.biome_id_buffer[idx] = 4 # "Cryo Frostwastes"
			elif t < 0.38: 
				if h_val < 0.4: gen.biome_id_buffer[idx] = 5 # "Tectonic Fissures"
				else: gen.biome_id_buffer[idx] = 6 # "Ashen Tundra"
			elif t > 0.65:
				if h_val < 0.3: gen.biome_id_buffer[idx] = 7 # "Salt Flats"
				elif h_val < 0.55: gen.biome_id_buffer[idx] = 8 # "Tornado Prairie"
				else: gen.biome_id_buffer[idx] = 9 # "Toxic Swamps"
			else:
				if h_val < 0.35: gen.biome_id_buffer[idx] = 10 # "Shattered Savannah"
				elif h_val < 0.6: gen.biome_id_buffer[idx] = 11 # "Seismic Plains"
				else: gen.biome_id_buffer[idx] = 12 # "Acidic Jungle"
