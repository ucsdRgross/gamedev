class_name Step1Landmass
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var continent_noise = FastNoiseLite.new()
	continent_noise.seed = settings.main_seed
	continent_noise.frequency = settings.continent_frequency
	
	for y in range(settings.map_height):
		for x in range(settings.map_width):
			var pos = Vector2i(x, y)
			var h = (continent_noise.get_noise_2d(x, y) + 1.0) / 2.0
			
			var center = Vector2(settings.map_width / 2.0, settings.map_height / 2.0)
			var d = Vector2(x, y).distance_to(center)
			var max_d = min(settings.map_width, settings.map_height) * 0.65
			var mask = clamp(1.0 - (d / max_d), 0.0, 1.0)
			mask = pow(mask, 0.5) 
			
			gen.height_map[pos] = h * mask
	gen._save_snapshot("Landmass")
