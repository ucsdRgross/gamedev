class_name NoiseBaker
extends RefCounted

## Bakes every noise map the pipeline needs, on the CPU, as normalized 0..1
## grayscale Images (+ matching ImageTextures). No shader generates noise anymore;
## shaders sample these. One humidity map is baked once and shared by climate and
## rivers. Returns a Dictionary name -> { "img": Image, "tex": ImageTexture }.
##
## Maps: landmass, warp_x, warp_y (tectonic domain warp), peaks_ridge,
## peaks_detail, erosion_channel, erosion_humidity, temperature, humidity.
static func bake(s: WorldSettings) -> Dictionary:
	var w := s.map_width
	var h := s.map_height
	var warp_freq := s.warp_frequency / float(w)  # match old UV*warp_frequency cycles

	var out := {}
	out["landmass"] = _img(w, h, s.main_seed + s.landmass_seed_offset, s.continent_frequency, 4, false)
	# Two independent channels for the tectonic domain warp (jagged plate edges).
	out["warp_x"] = _img(w, h, s.main_seed + s.tectonic_seed_offset, warp_freq, 3, false)
	out["warp_y"] = _img(w, h, s.main_seed + s.tectonic_seed_offset + 991, warp_freq, 3, false)
	out["peaks_ridge"] = _img(w, h, s.main_seed + s.peaks_seed_offset, s.ridge_frequency, 4, true)
	out["peaks_detail"] = _img(w, h, s.main_seed + s.peaks_seed_offset + 13, s.detail_frequency, 1, false)
	out["erosion_channel"] = _img(w, h, s.main_seed + s.erosion_seed_offset, s.erosion_frequency, s.erosion_octaves, true)
	out["erosion_humidity"] = _img(w, h, s.main_seed + s.erosion_humidity_seed_offset, s.erosion_humidity_frequency, 2, false)
	out["temperature"] = _img(w, h, s.main_seed + s.temperature_seed_offset, s.temp_frequency, 2, false)
	out["humidity"] = _img(w, h, s.main_seed + s.humidity_seed_offset, s.humid_frequency, 2, false)
	return out

static func _img(w: int, h: int, seed_v: int, freq: float, octaves: int, ridged: bool) -> Dictionary:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var img := n.get_image(w, h)  # normalized 0..1 grayscale (L8)
	return {"img": img, "tex": ImageTexture.create_from_image(img)}
