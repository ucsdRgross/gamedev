class_name Step4Erosion
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var inertia = 0.08
	var sediment_capacity_factor = 6.0
	var min_sediment_capacity = 0.01
	var erode_speed = 0.75 # Amplified variables to carve visible valleys
	var deposit_speed = 0.75
	
	for i in range(16000): # Increased pass loop count
		var pos = Vector2(randf() * settings.map_width, randf() * settings.map_height)
		var vel = Vector2.ZERO
		var sediment = 0.0
		
		for _step in range(35):
			var pos_i = Vector2i(pos)
			if not gen.height_map.has(pos_i): break
			
			var g = gen._calculate_gradient(pos)
			vel = vel * inertia - g * (1.0 - inertia)
			var new_pos = pos + vel
			if not gen.height_map.has(Vector2i(new_pos)): break
			
			var h_diff = gen.height_map[Vector2i(new_pos)] - gen.height_map[pos_i]
			var capacity = max(-h_diff * vel.length() * sediment_capacity_factor, min_sediment_capacity)
			
			if sediment > capacity or h_diff > 0:
				var amount = (sediment - capacity) * deposit_speed if h_diff < 0 else min(h_diff, sediment)
				sediment -= amount
				gen.height_map[pos_i] += amount
			else:
				var amount = min((capacity - sediment) * erode_speed, -h_diff)
				sediment += amount
				gen.height_map[pos_i] -= amount
			pos = new_pos
			
	gen._sync_fast_buffer() 
	gen._save_snapshot("Erosion")
