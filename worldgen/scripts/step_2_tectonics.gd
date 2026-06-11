class_name Step2Tectonics
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var plate_centers: Array[Vector2] = []
	var plate_directions: Array[Vector2] = []
	var plate_is_ocean: Array[bool] = []
	
	var warp_noise = FastNoiseLite.new()
	warp_noise.seed = settings.main_seed + 15
	warp_noise.frequency = 0.02
	
	for i in range(settings.plate_count):
		plate_centers.append(Vector2(randf() * settings.map_width, randf() * settings.map_height))
		plate_directions.append(Vector2(randf() - 0.5, randf() - 0.5).normalized())
		plate_is_ocean.append(randf() < 0.3)
		
	# Store vector data in landmarks so the viewer script can access and render the debug overlay
	gen.landmarks.clear()
	for i in range(plate_centers.size()):
		gen.landmarks.append({
			"pos": plate_centers[i],
			"dir": plate_directions[i],
			"ocean": plate_is_ocean[i]
		})

	# FIX: Process tectonics globally across all tiles to generate continuous mountain ridges
	for pos in gen.height_map.keys():
		var wx = pos.x + int(warp_noise.get_noise_2d(pos.x, pos.y) * 35.0)
		var wy = pos.y + int(warp_noise.get_noise_2d(pos.y, pos.x) * 35.0)
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
		
		if collision_force > 0.08:
			# Collision: push up mountain ranges along fault lines
			gen.height_map[pos] += collision_force * settings.drift_intensity * 1.4 * (1.0 - clamp(min_dist / 260.0, 0.0, 1.0))
		elif collision_force < -0.12 and not plate_is_ocean[closest_plate] and gen.height_map[pos] > settings.ocean_threshold:
			# Separation: carve valleys only when slicing through land tiles
			gen.height_map[pos] = clamp(gen.height_map[pos] - (abs(collision_force) * settings.drift_intensity * 0.4), 0.0, 1.0)
			
	# Save an explicit diagnostic snapshot step showing plate boundaries
	gen.snapshots["Tectonics_Debug"] = {
		"height_map": gen.height_map.duplicate(),
		"biome_map": gen.biome_map.duplicate(),
		"river_nodes": [],
		"city_nodes": [],
		"gameplay_graph": {},
		"start_node": Vector2.ZERO,
		"end_node": Vector2.ZERO,
		"landmarks": gen.landmarks.duplicate()
	}
	gen.generation_step_finished.emit("Tectonics_Debug")
	gen._save_snapshot("Tectonics")
