class_name Step4Erosion
extends GenerationStep

## Light erosion (Step 4). Carves faint, branching, river-like channels into the
## heightmap by combining three Perlin (FastNoiseLite) maps:
##   1. the working heightmap   -> biased toward taller terrain
##   2. an ancient humidity map -> biased toward wetter terrain
##   3. a ridged channel map    -> the channel network itself
## The carve is height -= strength * channel * height_bias * humidity_bias, and
## it ONLY subtracts. Using FastNoiseLite avoids the diagonal banding the
## sin-hash shader noise produced at high frequency. Edits height only; the
## droplet-driven rivers (widening + lakes) are a separate later step.
## ErosionDebug shows the carve as the diff vs the pre-erosion (PeaksAndValleys).
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var w := settings.map_width
	var h := settings.map_height
	var oth := settings.ocean_threshold

	# All three inputs come from the CPU noise baker:
	#   channel = ridged crests (the branching network), humidity = wet weighting,
	#   heightmap = the working buffer (tall weighting).
	var chan_img := gen.noise_img("erosion_channel")
	var hum_img := gen.noise_img("erosion_humidity")

	# Combine all three per pixel.
	var inv_sea := 1.0 / maxf(1e-3, 1.0 - oth)
	for y in range(h):
		for x in range(w):
			var idx := (y * w) + x
			var height := gen.height_buffer[idx]
			if height <= oth:
				continue  # never carve the sea
			var channel := chan_img.get_pixel(x, y).r          # 0..1, crests ~1
			channel = smoothstep(settings.erosion_channel_threshold, 1.0, channel)  # crest cutoff -> channel width
			var wet := hum_img.get_pixel(x, y).r               # 0..1
			var elev := clampf((height - oth) * inv_sea, 0.0, 1.0)
			var carve := settings.erosion_strength * channel \
				* pow(elev, settings.erosion_height_bias) \
				* pow(wet, settings.erosion_humidity_bias)
			gen.height_buffer[idx] = height - carve

	gen._save_snapshot_bridge("Erosion")
