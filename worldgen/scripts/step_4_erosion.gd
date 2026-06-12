class_name Step4Erosion
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var inertia = 0.08
	var sediment_capacity_factor = 6.0
	var min_sediment_capacity = 0.01
	var erode_speed = 0.75 
	var deposit_speed = 0.75
	
	var w = settings.map_width
	var h = settings.map_height
	
	for i in range(16000): 
		var pos = Vector2(randf() * w, randf() * h)
		var vel = Vector2.ZERO
		var sediment = 0.0
		
		for _step in range(35):
			var px = int(pos.x)
			var py = int(pos.y)
			if px < 0 or px >= w or py < 0 or py >= h: break
			
			var idx = (py * w) + px
			var g = gen._calculate_gradient_fast(px, py)
			vel = vel * inertia - g * (1.0 - inertia)
			var new_pos = pos + vel
			
			var n_x = int(new_pos.x)
			var n_y = int(new_pos.y)
			if n_x < 0 or n_x >= w or n_y < 0 or n_y >= h: break
			
			var next_idx = (n_y * w) + n_x
			var h_diff = gen.height_buffer[next_idx] - gen.height_buffer[idx]
			var capacity = max(-h_diff * vel.length() * sediment_capacity_factor, min_sediment_capacity)
			
			if sediment > capacity or h_diff > 0:
				var amount = (sediment - capacity) * deposit_speed if h_diff < 0 else min(h_diff, sediment)
				sediment -= amount
				gen.height_buffer[idx] += amount
			else:
				var amount = min((capacity - sediment) * erode_speed, -h_diff)
				sediment += amount
				gen.height_buffer[idx] -= amount
			pos = new_pos
