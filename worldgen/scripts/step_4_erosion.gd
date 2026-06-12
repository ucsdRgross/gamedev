# step_4_erosion_and_rivers.gd
class_name Step4ErosionAndRivers
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var start_t = Time.get_ticks_msec()
	
	var t_noise = FastNoiseLite.new()
	t_noise.seed = settings.main_seed + 3
	t_noise.frequency = 0.006
	
	var h_noise = FastNoiseLite.new()
	h_noise.seed = settings.main_seed + 4
	h_noise.frequency = 0.007
	
	var w = settings.map_width
	var h = settings.map_height
	var total_cells = w * h
	
	# =================================================================
	# PHASE 1: PRE-CALCULATE BASE CLIMATE BUFFER MAPS
	# =================================================================
	for y in range(h):
		for x in range(w):
			var idx = (y * w) + x
			var val = gen.height_buffer[idx]
			if val < settings.ocean_threshold: continue
			
			var raw_t = (t_noise.get_noise_2d(x, y) + 1.0) / 2.0
			var raw_h = (h_noise.get_noise_2d(x, y) + 1.0) / 2.0
			var elevation = (val - settings.ocean_threshold)
			
			gen.temp_buffer[idx] = clamp(raw_t - (elevation * 0.5), 0.0, 1.0)
			gen.humid_buffer[idx] = clamp(raw_h, 0.0, 1.0)

	# =================================================================
	# PHASE 2: INSTANT O(N) BUCKET HEIGHT SORTING (Fixes 10-Min Freeze)
	# =================================================================
	var flow_accumulation: PackedFloat32Array = PackedFloat32Array()
	flow_accumulation.resize(total_cells)
	flow_accumulation.fill(1.0) 
	
	# Allocate 101 discrete height bins to categorize cell structures
	var buckets: Array[Array] = []
	for b in range(101):
		var inner_bucket: Array[int] = []
		buckets.append(inner_bucket)
		
	for i in range(total_cells):
		if gen.height_buffer[i] >= settings.ocean_threshold:
			# Translate float metrics into clean integer array tracking keys
			var height_pct = clampi(int(gen.height_buffer[i] * 100.0), 0, 100)
			buckets[height_pct].append(i)

	# =================================================================
	# PHASE 3: CASCADING FLOW ACCUMULATION LOOP (Carves Real Rivers)
	# =================================================================
	# Read buckets backwards from highest peaks (100) down to lowlands (0)
	for b in range(100, -1, -1):
		var current_bucket = buckets[b]
		for idx in current_bucket:
			var cx = idx % w
			var cy = idx / w
			
			var climate_humidity = gen.humid_buffer[idx]
			flow_accumulation[idx] *= (1.0 + (climate_humidity * 1.2))
			
			var current_height = gen.height_buffer[idx]
			var lowest_neighbor_idx = -1
			var min_h = current_height
			
			for ox in [-1, 0, 1]:
				for oy in [-1, 0, 1]:
					if ox == 0 and oy == 0: continue
					var nx = cx + ox
					var ny = cy + oy
					if nx >= 0 and nx < w and ny >= 0 and ny < h:
						var n_idx = (ny * w) + nx
						if gen.height_buffer[n_idx] < min_h:
							min_h = gen.height_buffer[n_idx]
							lowest_neighbor_idx = n_idx
							
			if lowest_neighbor_idx != -1:
				flow_accumulation[lowest_neighbor_idx] += flow_accumulation[idx]
				
				# BALANCED EROSION: Water carves localized river incisions without flattening land
				if flow_accumulation[idx] > 30.0:
					gen.height_buffer[lowest_neighbor_idx] = max(gen.height_buffer[lowest_neighbor_idx] - 0.002, settings.ocean_threshold)

	# =================================================================
	# PHASE 4: STABLE RIVER NETWORK EXTRACTION
	# =================================================================
	# Check cells sequentially to extract high-volume paths
	for i in range(total_cells):
		if gen.height_buffer[i] < settings.ocean_threshold: continue
		
		# High drainage threshold ensures streams form narrow river vectors, not lake blobs
		if flow_accumulation[i] >= 220.0:
			var pos_i = Vector2i(i % w, i / w)
			if not gen.river_nodes.has(pos_i):
				gen.river_nodes.append(pos_i)
				
				# Minor valley carving pass that keeps landmasses intact
				gen.height_buffer[i] = max(gen.height_buffer[i] - 0.008, settings.ocean_threshold)

	# =================================================================
	# PHASE 5: MULTI-HAZARD BIOME ECOSYSTEM MATRIX CONVERSION
	# =================================================================
	for y in range(h):
		for x in range(w):
			var idx = (y * w) + x
			var val = gen.height_buffer[idx]
			
			if val < settings.ocean_threshold:
				gen.biome_id_buffer[idx] = 0 # Ocean
				continue
				
			var is_near_river = false
			for offset_x in range(-2, 3):
				for offset_y in range(-2, 3):
					var rx = clamp(x + offset_x, 0, w - 1)
					var ry = clamp(y + offset_y, 0, h - 1)
					if gen.river_nodes.has(Vector2i(rx, ry)):
						is_near_river = true
						break
						
			var h_val = clamp(gen.humid_buffer[idx] + (0.35 if is_near_river else 0.0), 0.0, 1.0)
			var t = gen.temp_buffer[idx]
			
			if val >= settings.mountain_threshold:
				if t < 0.35: gen.biome_id_buffer[idx] = 1 # Glacial Peak
				elif t > 0.65: gen.biome_id_buffer[idx] = 2 # Volcanic Crag
				else: gen.biome_id_buffer[idx] = 3 # Barren Ridges
			elif t < 0.25: 
				gen.biome_id_buffer[idx] = 4 # Cryo Frostwastes
			elif t < 0.38: 
				if h_val < 0.4: gen.biome_id_buffer[idx] = 5 # Tectonic Fissures
				else: gen.biome_id_buffer[idx] = 6 # Ashen Tundra
			elif t > 0.65:
				if h_val < 0.3: gen.biome_id_buffer[idx] = 7 # Salt Flats
				elif h_val < 0.55: gen.biome_id_buffer[idx] = 8 # Tornado Prairie
				else: gen.biome_id_buffer[idx] = 9 # Toxic Swamps
			else:
				if h_val < 0.35: gen.biome_id_buffer[idx] = 10 # Shattered Savannah
				elif h_val < 0.6: gen.biome_id_buffer[idx] = 11 # Seismic Plains
				else: gen.biome_id_buffer[idx] = 12 # Acidic Jungle
				
	print("  --> Optimized Index-Bucket River Pass Execution Time: ", Time.get_ticks_msec() - start_t, " ms")
