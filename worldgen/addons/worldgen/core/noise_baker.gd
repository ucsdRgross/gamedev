class_name NoiseBaker
extends RefCounted

## Bakes every noise map the pipeline needs, on the CPU, as normalized 0..1
## grayscale Images (+ matching ImageTextures). No shader generates noise anymore;
## shaders sample these. (Erosion is a GPU gabor-noise pass that reads the
## heightmap, so it bakes no noise here.) Returns a Dictionary name -> { "img", "tex" }.
##
## All maps use OpenSimplex2 (SIMPLEX_SMOOTH) -- no Perlin grid artifacts. Maps:
## landmass (fBm+warp), warp_x/warp_y (tectonic domain warp), peaks_ridge
## (ridged-multifractal+warp), peaks_billow (billow-multifractal+warp),
## peaks_detail (fBm), humidity (river rainfall weighting). The peaks shader
## altitude-blends ridge (high ground) and billow (foothills) over the fBm detail.
##
## Split into bake_images (pure CPU, thread-safe) + make_textures (RenderingServer, main
## thread) so a caller can offload the heavy image generation to a worker thread; bake()
## keeps the original one-shot behavior for synchronous callers.
static func bake(s: WorldSettings) -> Dictionary:
	return make_textures(bake_images(s))

## Compute every noise Image sequentially (no RenderingServer -> safe on one worker task).
static func bake_images(s: WorldSettings) -> Dictionary:
	var out := {}
	for r in image_recipes(s):
		out[r["name"]] = (r["fn"] as Callable).call()
	return out

## The noise maps as independent { "name", "fn": Callable() -> Image } recipes. Each fn is
## self-contained (its own FastNoiseLite + Image), so the maps can be computed in ANY order
## or in parallel across threads (WorkerThreadPool.add_group_task) -- see WorldGenerator.
static func image_recipes(s: WorldSettings) -> Array:
	var w := s.map_width
	var h := s.map_height
	var warp_freq := s.warp_frequency / float(w)  # match old UV*warp_frequency cycles
	return [
		# Continents: simplex fBm with optional domain warp for non-circular coasts.
		{"name": "landmass", "fn": func() -> Image: return _fbm(w, h, s.main_seed + s.landmass_seed_offset, s.continent_frequency,
			s.continent_octaves, s.continent_gain, s.continent_lacunarity, s.continent_warp_amp, s.continent_warp_freq)},
		# Two independent channels for the tectonic domain warp (jagged plate edges).
		{"name": "warp_x", "fn": func() -> Image: return _fbm(w, h, s.main_seed + s.tectonic_seed_offset, warp_freq, 3, 0.5, 2.0, 0.0, 0.0)},
		{"name": "warp_y", "fn": func() -> Image: return _fbm(w, h, s.main_seed + s.tectonic_seed_offset + 991, warp_freq, 3, 0.5, 2.0, 0.0, 0.0)},
		# Peaks: ridged-multifractal (sharp crests) + billow-multifractal (rounded foothills).
		{"name": "peaks_ridge", "fn": func() -> Image: return _multi(w, h, s.main_seed + s.peaks_seed_offset, s.ridge_frequency,
			s.peaks_octaves, s.peaks_gain, s.peaks_lacunarity, true, s.ridge_offset, s.peaks_warp_amp, s.peaks_warp_freq)},
		{"name": "peaks_billow", "fn": func() -> Image: return _multi(w, h, s.main_seed + s.peaks_seed_offset + 57, s.billow_frequency,
			s.peaks_octaves, s.peaks_gain, s.peaks_lacunarity, false, s.ridge_offset, s.peaks_warp_amp, s.peaks_warp_freq)},
		{"name": "peaks_detail", "fn": func() -> Image: return _fbm(w, h, s.main_seed + s.peaks_seed_offset + 13, s.detail_frequency, 1, 0.5, 2.0, 0.0, 0.0)},
		# Humidity (independent of height/latitude) -- rivers weight rainfall by it.
		{"name": "humidity", "fn": func() -> Image: return _fbm(w, h, s.main_seed + s.humidity_seed_offset, s.humid_frequency, 2, 0.5, 2.0, 0.0, 0.0)},
		# Biome border warp -- BiomeRegions adds it to the region flood's step cost
		# so biome frontiers wander organically instead of tracing clean Voronoi edges.
		{"name": "biome_warp", "fn": func() -> Image: return _fbm(w, h, s.main_seed + s.biome_seed_offset, s.biome_warp_freq, 3, 0.5, 2.0, 0.0, 0.0)},
	]

## Wrap each noise Image into { "img", "tex" } (ImageTexture upload -> main thread only).
static func make_textures(imgs: Dictionary) -> Dictionary:
	var out := {}
	for k in imgs:
		var img: Image = imgs[k]
		out[k] = {"img": img, "tex": ImageTexture.create_from_image(img)}
	return out

## Standard fBm (or ridged-fBm) via FastNoiseLite's native, C++-fast get_image.
## Optional domain warp perturbs sample coords for organic, non-grid features.
static func _fbm(w: int, h: int, seed_v: int, freq: float, octaves: int, gain: float,
		lacunarity: float, warp_amp: float, warp_freq: float, ridged: bool = false) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	n.fractal_lacunarity = lacunarity
	_apply_warp(n, warp_amp, warp_freq)
	return n.get_image(w, h)  # normalized 0..1 grayscale (L8)

## True multifractal: each octave's contribution is weighted by the running sum of
## the LOWER octaves, so high-frequency detail concentrates on already-high ground
## (smooth lowlands, detailed peaks) -- unlike fBm's uniform-everywhere weights.
## ridged=true folds each octave to (offset-|n|)^2 (sharp crests); ridged=false
## uses |n| (rounded billow lobes). Hand-rolled because FastNoiseLite has no
## multifractal mode. Heavier than _fbm (per-pixel octave loop) but bake-time only.
static func _multi(w: int, h: int, seed_v: int, base_freq: float, octaves: int, gain: float,
		lacunarity: float, ridged: bool, offset: float, warp_amp: float, warp_freq: float) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = base_freq
	n.fractal_type = FastNoiseLite.FRACTAL_NONE  # we do the octave loop ourselves
	_apply_warp(n, warp_amp, warp_freq)

	var vals := PackedFloat32Array()
	vals.resize(w * h)
	var vmin := INF
	var vmax := -INF
	for y in range(h):
		for x in range(w):
			var freq_mul := 1.0
			var amp := 1.0
			var weight := 1.0
			var sum := 0.0
			for o in range(octaves):
				var nv := n.get_noise_2d(float(x) * freq_mul, float(y) * freq_mul)  # -1..1
				var sig: float
				if ridged:
					sig = offset - absf(nv)
					sig = sig * sig
				else:
					sig = absf(nv)
				sum += sig * amp * weight
				# Multifractal modulation: next octave is gated by this octave's signal.
				weight = clampf(sig * 2.0, 0.0, 1.0)
				amp *= gain
				freq_mul *= lacunarity
			var i := (y * w) + x
			vals[i] = sum
			vmin = minf(vmin, sum)
			vmax = maxf(vmax, sum)

	# Normalize into an L8 byte buffer and build the Image in one shot: create_from_data
	# is ~10x faster than a per-pixel set_pixel loop (which the profiler flagged), and the
	# bytes are identical to what set_pixel(Color(nrm,nrm,nrm)) produced.
	var span := maxf(1e-6, vmax - vmin)
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in range(w * h):
		bytes[i] = roundi(clampf((vals[i] - vmin) / span, 0.0, 1.0) * 255.0)
	return Image.create_from_data(w, h, false, Image.FORMAT_L8, bytes)

static func _apply_warp(n: FastNoiseLite, amp: float, freq: float) -> void:
	if amp <= 0.0:
		return
	n.domain_warp_enabled = true
	n.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	n.domain_warp_amplitude = amp
	n.domain_warp_frequency = freq
