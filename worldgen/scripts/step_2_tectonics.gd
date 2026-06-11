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
		# Mix ocean plates and continental plates to ensure diverse geology
		plate_is_ocean.append(randf() < 0.4)
		
	for pos in gen.height_map.keys():
		var base_h = gen.height_map[pos]
		if base_h > settings.ocean_threshold:
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
			
			# RULE-BASED FLUID DRIFT INTERSECTIONS:
			if collision_force > 0.1:
				# Collision: push up high mountain chains
				gen.height_map[pos] += collision_force * settings.drift_intensity * (1.0 - clamp(min_dist / 220.0, 0.0, 1.0))
			elif collision_force < -0.1 and not plate_is_ocean[closest_plate]:
				# Separation between two continental landmasses: carve out deep rift valleys
				gen.height_map[pos] = max(settings.ocean_threshold - 0.05, gen.height_map[pos] - abs(collision_force) * 0.22)
				
	gen._save_snapshot("Tectonics")
