class_name Step6Civilizations
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var attempts = 0
	while gen.city_nodes.size() < settings.max_city_count and attempts < 7000:
		var candidate = Vector2(randf() * settings.map_width, randf() * settings.map_height)
		var pos_i = Vector2i(candidate)
		
		var h_val = gen.fast_height_buffer[(pos_i.y * settings.map_width) + pos_i.x]
		
		# CRITICAL PLACEMENT RULE: Rejects water tiles and mountain peaks entirely
		var valid_placement = false
		if h_val > (settings.ocean_threshold + 0.05) and h_val < settings.mountain_threshold:
			valid_placement = true
			
		if valid_placement:
			var too_close = false
			for city in gen.city_nodes:
				if city.distance_to(candidate) < settings.min_city_dist:
					too_close = true
					break
			if not too_close:
				gen.city_nodes.append(candidate)
		attempts += 1
	gen._save_snapshot("Cities")
