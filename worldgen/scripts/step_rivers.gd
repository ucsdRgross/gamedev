class_name StepRivers
extends GenerationStep

## River generation via D8 flow accumulation on a depression-filled DEM.
##
## For speed the hydrology runs on a downscaled grid (river_resolution_divisor):
## the priority-flood fill cost scales with cell count, so a divisor of 2/3/4
## gives a 4x/9x/16x speedup. The resulting river/lake masks are upsampled back
## to full resolution for carving and the water network.
##
## 1. Depression-fill the eroded terrain (priority-flood + epsilon) so every land
##    cell drains to the sea -> no traps. Basins raised above terrain are LAKES.
## 2. D8 flow direction (steepest descent on the filled surface).
## 3. Flow accumulation: each cell sources rainfall (weighted by humidity AND
##    elevation); summed downstream (Kahn topological pass, O(n)). Cells above the
##    accumulation threshold are rivers; bigger accumulation carves deeper / wider.
## Rivers and lakes carve the heightmap by independent depths/widths so they sit
## just below the surrounding land.
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var w := settings.map_width
	var h := settings.map_height
	var oth := settings.ocean_threshold
	var s: int = maxi(1, settings.river_resolution_divisor)
	var lw := w / s
	var lh := h / s
	var ln := lw * lh
	var t0 := Time.get_ticks_msec()

	# Downsample the eroded heightmap to the hydrology grid (point sample).
	var lbase := PackedFloat32Array()
	lbase.resize(ln)
	for ly in range(lh):
		for lx in range(lw):
			lbase[(ly * lw) + lx] = gen.height_buffer[((ly * s) * w) + (lx * s)]

	var lfilled := _fill_depressions(lbase, lw, lh, oth)
	var t_fill := Time.get_ticks_msec()

	# Rainfall map: rivers REUSE the exact climate humidity map (the shared baked
	# image), so rivers source where the climate is wet.
	var hum_img := gen.noise_img("humidity")

	# D8 downstream index + per-cell rainfall (accumulation seed).
	var inv_sea := 1.0 / maxf(1e-3, 1.0 - oth)
	var down := PackedInt32Array()
	down.resize(ln)
	down.fill(-1)
	var accum := PackedFloat32Array()
	accum.resize(ln)
	for ly in range(lh):
		for lx in range(lw):
			var i := (ly * lw) + lx
			if lbase[i] < oth:
				accum[i] = 0.0
				continue  # ocean is a sink: flow ends here
			var wet := hum_img.get_pixel(mini(lx * s, w - 1), mini(ly * s, h - 1)).r  # 0..1
			var elev := clampf((lbase[i] - oth) * inv_sea, 0.0, 1.0)
			accum[i] = pow(wet, settings.river_source_humidity_bias) \
				* pow(elev, settings.river_source_elevation_bias) + 0.001
			var best := lfilled[i]
			var bi := -1
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := lx + ox
					var ny := ly + oy
					if nx < 0 or ny < 0 or nx >= lw or ny >= lh:
						continue
					var ni := (ny * lw) + nx
					if lfilled[ni] < best:
						best = lfilled[ni]
						bi = ni
			down[i] = bi

	# Accumulate downstream with a topological pass (Kahn) -- O(n), exact, no sort.
	var indeg := PackedInt32Array()
	indeg.resize(ln)
	indeg.fill(0)
	for i in range(ln):
		if down[i] >= 0:
			indeg[down[i]] += 1
	var queue := PackedInt32Array()
	queue.resize(ln)
	var qh := 0
	var qt := 0
	for i in range(ln):
		if indeg[i] == 0:
			queue[qt] = i
			qt += 1
	while qh < qt:
		var c := queue[qh]
		qh += 1
		var d := down[c]
		if d >= 0:
			accum[d] += accum[c]
			indeg[d] -= 1
			if indeg[d] == 0:
				queue[qt] = d
				qt += 1

	# Normalise accumulation on a log scale (huge dynamic range).
	var max_accum := 0.0
	for i in range(ln):
		max_accum = maxf(max_accum, accum[i])
	var lmax := log(1.0 + max_accum)
	if lmax <= 0.0:
		lmax = 1.0

	# Low-res river depth map (>0 = river) with convergence-based widening.
	var depth_l := PackedFloat32Array()
	depth_l.resize(ln)
	for ly in range(lh):
		for lx in range(lw):
			var i := (ly * lw) + lx
			if lbase[i] < oth or accum[i] < settings.river_accum_threshold:
				continue
			var an := log(1.0 + accum[i]) / lmax  # 0..1
			var carve := settings.river_carve_depth * an
			var rad := int(settings.river_width_gain * an)
			for oy in range(-rad, rad + 1):
				for ox in range(-rad, rad + 1):
					if (ox * ox) + (oy * oy) > rad * rad:
						continue
					var nx := lx + ox
					var ny := ly + oy
					if nx < 0 or ny < 0 or nx >= lw or ny >= lh:
						continue
					var ni := (ny * lw) + nx
					if lbase[ni] >= oth:
						depth_l[ni] = maxf(depth_l[ni], carve)

	# Low-res lake mask + water-surface height (sits lake_carve_depth below spill).
	var is_lake_l := PackedByteArray()
	is_lake_l.resize(ln)
	is_lake_l.fill(0)
	for i in range(ln):
		if lbase[i] >= oth and lfilled[i] - lbase[i] > settings.lake_min_depth:
			is_lake_l[i] = 1
	if settings.lake_width > 0:
		is_lake_l = _dilate(is_lake_l, lw, lh, settings.lake_width)
	var lake_surf_l := PackedFloat32Array()
	lake_surf_l.resize(ln)
	for i in range(ln):
		if is_lake_l[i] == 1:
			lake_surf_l[i] = maxf(lfilled[i] - settings.lake_carve_depth, oth + 0.004)

	# Apply to the full-resolution heightmap and collect the water network.
	var fullbase := gen.height_buffer.duplicate()
	gen.river_nodes.clear()
	gen.lake_nodes.clear()
	for y in range(h):
		for x in range(w):
			var fi := (y * w) + x
			var lc := (mini(y / s, lh - 1) * lw) + mini(x / s, lw - 1)
			if is_lake_l[lc] == 1:
				gen.height_buffer[fi] = lake_surf_l[lc]
				gen.lake_nodes.append(Vector2i(x, y))
			elif depth_l[lc] > 0.0:
				gen.height_buffer[fi] = maxf(fullbase[fi] - depth_l[lc], oth + 0.004)
				gen.river_nodes.append(Vector2i(x, y))

	var t_end := Time.get_ticks_msec()
	print("[Rivers] res=", lw, "x", lh, " river cells=", gen.river_nodes.size(),
		" lake cells=", gen.lake_nodes.size(),
		" | fill=", t_fill - t0, "ms rest=", t_end - t_fill, "ms total=", t_end - t0, "ms")

	gen._save_snapshot_bridge("Rivers_Only")

## Grow a boolean mask outward by `r` cells (Chebyshev dilation).
func _dilate(mask: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var out := mask.duplicate()
	for y in range(h):
		for x in range(w):
			if mask[(y * w) + x] == 0:
				continue
			for oy in range(-r, r + 1):
				for ox in range(-r, r + 1):
					var nx := x + ox
					var ny := y + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					out[(ny * w) + nx] = 1
	return out

## Priority-Flood (+epsilon) depression filling (Barnes et al. 2014). Returns a
## surface W >= H where every land cell has a strictly monotonic downhill path to
## the open boundary (map edge / ocean), so flow never gets trapped in a local
## minimum. Basins are raised to their spill level plus a tiny epsilon gradient
## toward the outlet (which also resolves flats). Cells where W rose meaningfully
## above H are lakes.
func _fill_depressions(H: PackedFloat32Array, w: int, h: int, oth: float) -> PackedFloat32Array:
	var n := w * h
	var W := PackedFloat32Array()
	W.resize(n)
	W.fill(INF)
	var closed := PackedByteArray()
	closed.resize(n)
	closed.fill(0)
	const EPS := 0.00001
	# Parallel-array binary min-heap over (priority, cell index).
	var hp := PackedFloat32Array()  # priorities
	var hi := PackedInt32Array()    # cell indices

	# Seed the open boundary: map edges and every ocean cell drain freely.
	for y in range(h):
		for x in range(w):
			var i := (y * w) + x
			if x == 0 or y == 0 or x == w - 1 or y == h - 1 or H[i] < oth:
				W[i] = H[i]
				closed[i] = 1
				hp.append(H[i])
				hi.append(i)
				var c := hp.size() - 1
				while c > 0:
					var p := (c - 1) >> 1
					if hp[p] <= hp[c]:
						break
					var fp := hp[p]; hp[p] = hp[c]; hp[c] = fp
					var ip := hi[p]; hi[p] = hi[c]; hi[c] = ip
					c = p

	while hp.size() > 0:
		# Pop the lowest cell.
		var ci := hi[0]
		var last := hp.size() - 1
		hp[0] = hp[last]
		hi[0] = hi[last]
		hp.resize(last)
		hi.resize(last)
		var sz := hp.size()
		var c := 0
		while true:
			var l := (2 * c) + 1
			var r := (2 * c) + 2
			var sm := c
			if l < sz and hp[l] < hp[sm]:
				sm = l
			if r < sz and hp[r] < hp[sm]:
				sm = r
			if sm == c:
				break
			var fc := hp[c]; hp[c] = hp[sm]; hp[sm] = fc
			var ic := hi[c]; hi[c] = hi[sm]; hi[sm] = ic
			c = sm
		# Raise each un-closed neighbour to at least our level + epsilon.
		var cx := ci % w
		var cy := ci / w
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var nx := cx + ox
				var ny := cy + oy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := (ny * w) + nx
				if closed[ni] == 1:
					continue
				W[ni] = maxf(H[ni], W[ci] + EPS)
				closed[ni] = 1
				hp.append(W[ni])
				hi.append(ni)
				var c2 := hp.size() - 1
				while c2 > 0:
					var p2 := (c2 - 1) >> 1
					if hp[p2] <= hp[c2]:
						break
					var fp2 := hp[p2]; hp[p2] = hp[c2]; hp[c2] = fp2
					var ip2 := hi[p2]; hi[p2] = hi[c2]; hi[c2] = ip2
					c2 = p2
	return W
