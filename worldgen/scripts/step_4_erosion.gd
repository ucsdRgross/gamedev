class_name Step4Erosion
extends GenerationStep

## Hydraulic (stream-power) erosion, replacing the old ridged-Perlin channel carve.
##
## A whole-map, O(n) "every cell is a droplet" pass: each cell sources rainfall
## from the ancient erosion-humidity map (independent of the climate humidity the
## rivers use), flow is accumulated downstream on a depression-filled DEM, and the
## terrain is reshaped by stream power:
##   * CARVE where flow x slope is high (steep, wet -> valleys)            (subtract)
##   * DEPOSIT sediment where it goes flat (valley floors -> new land)     (add)
## then optional thermal slumping relaxes over-steep cliffs. Erosion carves harder
## AND builds land; rivers (a later, separate pass with its own accumulation and
## the climate humidity map) carve lightly and never deposit.
##
## Runs on its own downscaled grid (erosion_resolution_divisor) for speed; the
## per-cell height delta is bilinearly upsampled back to full resolution. Edits
## height only. ErosionDebug / "Erosion Channels" shows the carve vs PeaksAndValleys.
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var w := settings.map_width
	var h := settings.map_height
	var oth := settings.ocean_threshold
	var s: int = maxi(1, settings.erosion_resolution_divisor)
	var lw := w / s
	var lh := h / s
	var ln := lw * lh

	# Downsample the working heightmap to the erosion grid (point sample).
	var base := PackedFloat32Array()
	base.resize(ln)
	for ly in range(lh):
		for lx in range(lw):
			base[(ly * lw) + lx] = gen.height_buffer[((ly * s) * w) + (lx * s)]

	var filled := fill_depressions(base, lw, lh, oth)
	var hum_img := gen.noise_img("erosion_humidity")  # ancient rainfall

	# Per-cell rainfall (accum seed) + local slope. Erosion sources ADDITIVELY:
	# elevation ALWAYS contributes (every mountain top sheds runoff and erodes),
	# plus a humidity term so wet regions (incl. lowlands) erode extra. Slope is the
	# steepest ORIGINAL-terrain drop to any lower neighbor (filled flats read ~0).
	var inv_sea := 1.0 / maxf(1e-3, 1.0 - oth)
	var seed := PackedFloat32Array()
	seed.resize(ln)
	var slope := PackedFloat32Array()
	slope.resize(ln)
	for ly in range(lh):
		for lx in range(lw):
			var i := (ly * lw) + lx
			if base[i] < oth:
				continue  # ocean is a sink
			var wet := hum_img.get_pixel(mini(lx * s, w - 1), mini(ly * s, h - 1)).r
			var elev := clampf((base[i] - oth) * inv_sea, 0.0, 1.0)
			seed[i] = pow(elev, settings.erosion_rain_elevation_bias) \
				+ settings.erosion_rain_humidity_weight * pow(wet, settings.erosion_rain_humidity_bias) + 0.001
			var steepest := 0.0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := lx + ox
					var ny := ly + oy
					if nx < 0 or ny < 0 or nx >= lw or ny >= lh:
						continue
					var ni := (ny * lw) + nx
					var dist := 1.41421356 if (ox != 0 and oy != 0) else 1.0
					steepest = maxf(steepest, (base[i] - base[ni]) / dist)
			slope[i] = steepest

	# Multiple-flow-direction accumulation: flow spreads across slopes and flats
	# for diffuse, natural erosion and fan-out -- not a single-channel D8 path.
	var accum := flow_accumulate_mfd(filled, seed, lw, lh, oth, settings.erosion_flow_exponent)

	# Log-normalise accumulation (huge dynamic range).
	var max_accum := 0.0
	for i in range(ln):
		max_accum = maxf(max_accum, accum[i])
	var lmax := log(1.0 + max_accum)
	if lmax <= 0.0:
		lmax = 1.0

	# Stream-power reshape: carve on steep/wet cells, deposit on flats. sl_term
	# maps slope to 0..1 against the talus angle: >=talus -> all carve (steep),
	# ->0 on flats -> all deposition (valley-floor build-up).
	var inv_talus := 1.0 / maxf(1e-5, settings.erosion_talus)
	var nh := PackedFloat32Array()
	nh.resize(ln)
	for i in range(ln):
		nh[i] = base[i]
		if base[i] < oth:
			continue
		var an := log(1.0 + accum[i]) / lmax
		var flow := pow(an, settings.erosion_accum_exponent)
		var sl_term := clampf(slope[i] * inv_talus, 0.0, 1.0)
		var carve := settings.erosion_strength * flow * pow(sl_term, settings.erosion_slope_exponent)
		var dep := settings.erosion_strength * settings.erosion_deposition * flow * (1.0 - sl_term)
		nh[i] = base[i] + dep - carve

	# Thermal slumping: shave material above the talus angle to the lowest neighbor.
	for _p in range(settings.erosion_thermal_passes):
		nh = _thermal(nh, lw, lh, oth, settings.erosion_talus)

	# Low-res per-cell delta, bilinearly upsampled and applied at full resolution.
	var delta := PackedFloat32Array()
	delta.resize(ln)
	for i in range(ln):
		delta[i] = nh[i] - base[i]

	var fullbase := gen.height_buffer.duplicate()
	for y in range(h):
		for x in range(w):
			var fi := (y * w) + x
			if fullbase[fi] < oth:
				continue  # never erode/deposit the sea
			var d := _sample_bilinear(delta, lw, lh, float(x) / float(s), float(y) / float(s))
			# Deposition may raise; carve may not drop land below sea (keep coastline).
			gen.height_buffer[fi] = maxf(fullbase[fi] + d, oth + 0.002)

	gen._save_snapshot_bridge("Erosion")

## One thermal-erosion pass: any cell more than `talus` above its lowest neighbor
## sheds half the excess to that neighbor. Reads H, writes a copy, so the pass is
## order-independent (no within-pass cascading).
func _thermal(H: PackedFloat32Array, w: int, h: int, oth: float, talus: float) -> PackedFloat32Array:
	var out := H.duplicate()
	for y in range(h):
		for x in range(w):
			var i := (y * w) + x
			if H[i] < oth:
				continue
			var lowest := H[i]
			var li := -1
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := x + ox
					var ny := y + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni := (ny * w) + nx
					if H[ni] < lowest:
						lowest = H[ni]
						li = ni
			if li >= 0:
				var diff := H[i] - lowest
				if diff > talus:
					var move := (diff - talus) * 0.5
					out[i] -= move
					out[li] += move
	return out

## Bilinear sample of a low-res grid at fractional (fx, fy) in low-res cells.
func _sample_bilinear(arr: PackedFloat32Array, w: int, h: int, fx: float, fy: float) -> float:
	var x0 := clampi(int(floor(fx)), 0, w - 1)
	var y0 := clampi(int(floor(fy)), 0, h - 1)
	var x1 := mini(x0 + 1, w - 1)
	var y1 := mini(y0 + 1, h - 1)
	var tx := clampf(fx - float(x0), 0.0, 1.0)
	var ty := clampf(fy - float(y0), 0.0, 1.0)
	var a := arr[(y0 * w) + x0]
	var b := arr[(y0 * w) + x1]
	var c := arr[(y1 * w) + x0]
	var dd := arr[(y1 * w) + x1]
	return lerpf(lerpf(a, b, tx), lerpf(c, dd, tx), ty)
