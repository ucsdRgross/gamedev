class_name Step3PeaksAndValleys
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var ridge_noise = FastNoiseLite.new()
	ridge_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	ridge_noise.frequency = 0.015
	ridge_noise.seed = settings.main_seed + 2
	
	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = settings.main_seed + 5
	detail_noise.frequency = settings.detail_frequency
	
	var w = settings.map_width
	for y in range(settings.map_height):
		for x in range(w):
			var idx = (y * w) + x
			if gen.height_buffer[idx] > settings.ocean_threshold:
				var ridge = 1.0 - abs(ridge_noise.get_noise_2d(x, y))
				var detail = detail_noise.get_noise_2d(x, y) * 0.12
				gen.height_buffer[idx] = clamp(gen.height_buffer[idx] + (pow(ridge, 3.0) * 0.45) + detail, 0.0, 1.2)
