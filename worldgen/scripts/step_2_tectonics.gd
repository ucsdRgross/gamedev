# step_2_tectonics.gd
class_name Step2Tectonics
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var plate_centers: Array[Vector2] = []
	var plate_directions: Array[Vector2] = []
	var plate_is_ocean: Array[bool] = []
	
	var warp_noise = FastNoiseLite.new()
	warp_noise.seed = settings.main_seed + 15
	warp_noise.frequency = 0.02
	
	var grid_cols: int = int(ceil(sqrt(settings.plate_count)))
	var grid_rows: int = int(ceil(float(settings.plate_count) / grid_cols))
	var cell_w: float = float(settings.map_width) / grid_cols
	var cell_h: float = float(settings.map_height) / grid_rows
	
	var assigned_count: int = 0
	for r in range(grid_rows):
		for c in range(grid_cols):
			if assigned_count >= settings.plate_count: break
			var final_center = Vector2((c * cell_w) + (cell_w * 0.5) + (randf()-0.5)*(cell_w*0.4), (r * cell_h) + (cell_h * 0.5) + (randf()-0.5)*(cell_h*0.4))
			plate_centers.append(final_center)
			plate_directions.append(Vector2(randf() - 0.5, randf() - 0.5).normalized())
			plate_is_ocean.append(randf() < 0.3)
			assigned_count += 1

	gen.landmarks.clear()
	for i in range(plate_centers.size()):
		gen.landmarks.append({"pos": plate_centers[i], "dir": plate_directions[i], "ocean": plate_is_ocean[i]})

	var w = settings.map_width
	for y in range(settings.map_height):
		for x in range(w):
			var idx = (y * w) + x
			var wx = x + int(warp_noise.get_noise_2d(x, y) * 45.0)
			var wy = y + int(warp_noise.get_noise_2d(y, x) * 45.0)
			var warped_pos = Vector2(wx, wy)
			
			var closest_plate = 0
			var min_dist = 99999.0
			for i in range(plate_centers.size()):
				var d = warped_pos.distance_to(plate_centers[i])
				if d < min_dist:
					min_dist = d
					closest_plate = i
					
			# PRECOMPUTE ZONE POINTER ID INDICES FOR FAST BOUNDARY LOOKUPS
			gen.plate_id_buffer[idx] = closest_plate
			
			var to_center = (plate_centers[closest_plate] - warped_pos).normalized()
			var collision_force = to_center.dot(plate_directions[closest_plate])
			
			if collision_force > 0.08:
				gen.height_buffer[idx] += collision_force * settings.drift_intensity * 1.5 * (1.0 - clamp(min_dist / 260.0, 0.0, 1.0))
			elif collision_force < -0.12 and not plate_is_ocean[closest_plate] and gen.height_buffer[idx] > settings.ocean_threshold:
				gen.height_buffer[idx] = clamp(gen.height_buffer[idx] - (abs(collision_force) * settings.drift_intensity * 0.45), 0.0, 1.0)
