class_name Step1Landmass
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var continent_noise = FastNoiseLite.new()
	continent_noise.seed = settings.main_seed
	continent_noise.frequency = settings.continent_frequency
	
	var w = settings.map_width
	var h = settings.map_height
	var cx = w / 2.0
	var cy = h / 2.0
	var max_d = min(w, h) * 0.65
	
	for y in range(h):
		for x in range(w):
			var idx = (y * w) + x
			var noise_val = (continent_noise.get_noise_2d(x, y) + 1.0) / 2.0
			
			var d = Vector2(x, y).distance_to(Vector2(cx, cy))
			var mask = clamp(1.0 - (d / max_d), 0.0, 1.0)
			mask = pow(mask, 0.5) 
			
			gen.height_buffer[idx] = noise_val * mask
