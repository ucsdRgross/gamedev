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

	# Downsample the eroded heightmap to the hydrology grid (point sample).
	var lbase := PackedFloat32Array()
	lbase.resize(ln)
	for ly in range(lh):
		for lx in range(lw):
			lbase[(ly * lw) + lx] = gen.height_buffer[((ly * s) * w) + (lx * s)]

	var lfilled := fill_depressions(lbase, lw, lh, oth)

	# Rainfall map: rivers REUSE the exact climate humidity map (the shared baked
	# image), so rivers source where the climate is wet.
	var hum_img := gen.noise_img("humidity")

	# Per-cell rainfall (accumulation seed). Rivers source MULTIPLICATIVELY from
	# wet AND high terrain, so a dry mountain spawns no river (not every mountain
	# gets one) -- unlike erosion, which sources additively (every mountain erodes).
	var inv_sea := 1.0 / maxf(1e-3, 1.0 - oth)
	var seed := PackedFloat32Array()
	seed.resize(ln)
	for ly in range(lh):
		for lx in range(lw):
			var i := (ly * lw) + lx
			if lbase[i] < oth:
				continue  # ocean is a sink
			var wet := hum_img.get_pixel(mini(lx * s, w - 1), mini(ly * s, h - 1)).r  # 0..1
			var elev := clampf((lbase[i] - oth) * inv_sea, 0.0, 1.0)
			seed[i] = pow(wet, settings.river_source_humidity_bias) \
				* pow(elev, settings.river_source_elevation_bias) + 0.001

	# Multiple-flow-direction accumulation: rivers can FORK on flats / at coasts
	# (deltas, distributaries) instead of collapsing to one D8 path.
	var accum := flow_accumulate_mfd(lfilled, seed, lw, lh, oth, settings.river_flow_exponent)

	# Normalise accumulation. Carve DEPTH uses a log scale (huge dynamic range);
	# WIDTH must instead grow from the source threshold so a river starts as a
	# single pixel and widens downstream. Using the log scale for width made every
	# river the same width (log compresses the range, then int() quantises it to
	# one or two radii) and made each source a full-radius circular blob (the head
	# is a lone cell that already sits at a high log value, so it stamps a big
	# disc). Width here ramps 0->1 from the river threshold to max flow and follows
	# sqrt(discharge) -- the physical channel-width law -- so heads are ~0 px.
	var max_accum := 0.0
	for i in range(ln):
		max_accum = maxf(max_accum, accum[i])
	var lmax := log(1.0 + max_accum)
	if lmax <= 0.0:
		lmax = 1.0
	var thr := settings.river_accum_threshold
	var accum_span := maxf(1e-6, max_accum - thr)

	# Low-res river depth map (>0 = river) with convergence-based widening.
	var depth_l := PackedFloat32Array()
	depth_l.resize(ln)
	for ly in range(lh):
		for lx in range(lw):
			var i := (ly * lw) + lx
			if lbase[i] < oth or accum[i] < thr:
				continue
			var an := log(1.0 + accum[i]) / lmax  # 0..1, depth only
			var carve := settings.river_carve_depth * an
			# 0 at the source threshold, ->1 at the largest river; sqrt so width
			# grows like channel width with discharge (tiny head, fat mouth).
			var wfrac := sqrt(clampf((accum[i] - thr) / accum_span, 0.0, 1.0))
			var rad := int(settings.river_width_gain * wfrac)
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

	# Low-res lake mask: cells the depression-fill raised above the terrain.
	var is_lake_l := PackedByteArray()
	is_lake_l.resize(ln)
	is_lake_l.fill(0)
	for i in range(ln):
		if lbase[i] >= oth and lfilled[i] - lbase[i] > settings.lake_min_depth:
			is_lake_l[i] = 1

	# FLAT lake surfaces: label connected basins and give every cell in a basin one
	# elevation -- the spill level (the basin's MINIMUM filled height, where water
	# escapes), minus lake_carve_depth -- instead of the per-cell epsilon-gradient
	# fill (which made lake surfaces stepped). Computed before dilation so rim cells
	# can't lower the level.
	var lake_surf_l := PackedFloat32Array()
	lake_surf_l.resize(ln)
	var comp := PackedInt32Array()
	comp.resize(ln)
	comp.fill(-1)
	for start in range(ln):
		if is_lake_l[start] == 0 or comp[start] != -1:
			continue
		var members := PackedInt32Array()
		var stack := PackedInt32Array()
		stack.append(start)
		comp[start] = start
		var spill := lfilled[start]
		while not stack.is_empty():
			var c := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			members.append(c)
			spill = minf(spill, lfilled[c])
			var cx := c % lw
			var cy := c / lw
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := cx + ox
					var ny := cy + oy
					if nx < 0 or ny < 0 or nx >= lw or ny >= lh:
						continue
					var ni := (ny * lw) + nx
					if is_lake_l[ni] == 1 and comp[ni] == -1:
						comp[ni] = start
						stack.append(ni)
		var surf := maxf(spill - settings.lake_carve_depth, oth + 0.004)
		for m in members:
			lake_surf_l[m] = surf

	# Dilate the lake outward, propagating each basin's flat surface to new cells.
	if settings.lake_width > 0:
		var res := _dilate_lake(is_lake_l, lake_surf_l, lw, lh, settings.lake_width)
		is_lake_l = res[0]
		lake_surf_l = res[1]

	# Apply to the full-resolution heightmap and collect the water network.
	# height_buffer stays the terrain BED everywhere (carved for rivers, untouched
	# floor for lakes); the WATER TOP goes into water_surface_buffer so 3D can mesh
	# terrain and water as separate surfaces. Ocean is not recorded here (it is the
	# implicit flat plane at oth).
	var fullbase := gen.height_buffer.duplicate()
	gen.water_surface_buffer.fill(WorldGenerator.NO_WATER)
	gen.river_nodes.clear()
	gen.lake_nodes.clear()
	for y in range(h):
		for x in range(w):
			var fi := (y * w) + x
			var lc := (mini(y / s, lh - 1) * lw) + mini(x / s, lw - 1)
			if is_lake_l[lc] == 1:
				# Keep the real lake floor as the bed; water sits at the spill surface.
				gen.water_surface_buffer[fi] = lake_surf_l[lc]
				gen.lake_nodes.append(Vector2i(x, y))
			elif depth_l[lc] > 0.0:
				# Carve the channel; water fills it back up to (near) original grade.
				gen.height_buffer[fi] = maxf(fullbase[fi] - depth_l[lc], oth + 0.004)
				gen.water_surface_buffer[fi] = fullbase[fi]
				gen.river_nodes.append(Vector2i(x, y))

	gen._save_snapshot_bridge("Rivers_Only")

## Grow the lake mask outward by `r` rings; each newly added cell inherits the
## (flat) water surface of an adjacent lake cell so dilated borders stay level.
## Returns [mask, surface] (PackedArrays pass by value, so both are handed back).
func _dilate_lake(mask: PackedByteArray, surf: PackedFloat32Array, w: int, h: int, r: int) -> Array:
	for _it in range(r):
		var added := PackedInt32Array()
		for y in range(h):
			for x in range(w):
				var i := (y * w) + x
				if mask[i] == 1:
					continue
				var s := -1.0
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if ox == 0 and oy == 0:
							continue
						var nx := x + ox
						var ny := y + oy
						if nx < 0 or ny < 0 or nx >= w or ny >= h:
							continue
						var ni := (ny * w) + nx
						if mask[ni] == 1:
							s = maxf(s, surf[ni])
				if s >= 0.0:
					added.append(i)
					surf[i] = s
		for i in added:
			mask[i] = 1
	return [mask, surf]
