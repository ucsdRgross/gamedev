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
static func bake(s: WorldSettings) -> Dictionary:
	var w := s.map_width
	var h := s.map_height
	var warp_freq := s.warp_frequency / float(w)  # match old UV*warp_frequency cycles

	var out := {}
	# Continents: simplex fBm with optional domain warp for non-circular coasts.
	out["landmass"] = _fbm(w, h, s.main_seed + s.landmass_seed_offset, s.continent_frequency,
		s.continent_octaves, s.continent_gain, s.continent_lacunarity, s.continent_warp_amp, s.continent_warp_freq)
	# Two independent channels for the tectonic domain warp (jagged plate edges).
	out["warp_x"] = _fbm(w, h, s.main_seed + s.tectonic_seed_offset, warp_freq, 3, 0.5, 2.0, 0.0, 0.0)
	out["warp_y"] = _fbm(w, h, s.main_seed + s.tectonic_seed_offset + 991, warp_freq, 3, 0.5, 2.0, 0.0, 0.0)
	# Peaks: ridged-multifractal (sharp crests, detail only on high ground) and
	# billow-multifractal (rounded foothills), both domain-warped for organic flow.
	out["peaks_ridge"] = _multi(w, h, s.main_seed + s.peaks_seed_offset, s.ridge_frequency,
		s.peaks_octaves, s.peaks_gain, s.peaks_lacunarity, true, s.ridge_offset, s.peaks_warp_amp, s.peaks_warp_freq)
	out["peaks_billow"] = _multi(w, h, s.main_seed + s.peaks_seed_offset + 57, s.billow_frequency,
		s.peaks_octaves, s.peaks_gain, s.peaks_lacunarity, false, s.ridge_offset, s.peaks_warp_amp, s.peaks_warp_freq)
	out["peaks_detail"] = _fbm(w, h, s.main_seed + s.peaks_seed_offset + 13, s.detail_frequency, 1, 0.5, 2.0, 0.0, 0.0)
	# Humidity (independent of height/latitude) -- rivers weight rainfall by it.
	out["humidity"] = _fbm(w, h, s.main_seed + s.humidity_seed_offset, s.humid_frequency, 2, 0.5, 2.0, 0.0, 0.0)
	return out

## Standard fBm (or ridged-fBm) via FastNoiseLite's native, C++-fast get_image.
## Optional domain warp perturbs sample coords for organic, non-grid features.
static func _fbm(w: int, h: int, seed_v: int, freq: float, octaves: int, gain: float,
		lacunarity: float, warp_amp: float, warp_freq: float, ridged: bool = false) -> Dictionary:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	n.fractal_lacunarity = lacunarity
	_apply_warp(n, warp_amp, warp_freq)
	var img := n.get_image(w, h)  # normalized 0..1 grayscale (L8)
	return {"img": img, "tex": ImageTexture.create_from_image(img)}

## True multifractal: each octave's contribution is weighted by the running sum of
## the LOWER octaves, so high-frequency detail concentrates on already-high ground
## (smooth lowlands, detailed peaks) -- unlike fBm's uniform-everywhere weights.
## ridged=true folds each octave to (offset-|n|)^2 (sharp crests); ridged=false
## uses |n| (rounded billow lobes). Hand-rolled because FastNoiseLite has no
## multifractal mode. Heavier than _fbm (per-pixel octave loop) but bake-time only.
static func _multi(w: int, h: int, seed_v: int, base_freq: float, octaves: int, gain: float,
		lacunarity: float, ridged: bool, offset: float, warp_amp: float, warp_freq: float) -> Dictionary:
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

	var span := maxf(1e-6, vmax - vmin)
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	for y in range(h):
		for x in range(w):
			var nrm := (vals[(y * w) + x] - vmin) / span
			img.set_pixel(x, y, Color(nrm, nrm, nrm))
	return {"img": img, "tex": ImageTexture.create_from_image(img)}

static func _apply_warp(n: FastNoiseLite, amp: float, freq: float) -> void:
	if amp <= 0.0:
		return
	n.domain_warp_enabled = true
	n.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	n.domain_warp_amplitude = amp
	n.domain_warp_frequency = freq
