extends Node

## A/B gate for the worldgen_native GDExtension (run with F6): calls each ported
## function twice on identical inputs -- once through the native dll, once by
## forcing the GDScript path (GenerationStep._native = null) -- and diffs the
## outputs element-by-element. ZERO tolerance (bit-identical) per
## GDEXTENSION_PORT_HANDOFF.md. Inputs are real downscaled heightmaps generated
## through the Erosion step at seed 12356 plus random seeds, so the compared
## grids exercise real coasts/basins, not synthetic noise.

@export var seeds: Array[int] = [12356, 777, 424242]

var _gen: WorldGenerator
var _fails := 0

func _ready() -> void:
	print("=== worldgen_native A/B test ===")
	if GenerationStep._native == null:
		print("  [FAIL] WorldgenNative class not registered -- dll missing?")
		get_tree().quit(1)
		return
	_gen = WorldGenerator.new()
	add_child(_gen)
	await get_tree().process_frame
	for sd in seeds:
		await _run_seed(sd)
	print("=== worldgen_native A/B complete: %s ===" % [
		"PASS" if _fails == 0 else "FAIL (%d checks)" % _fails])
	get_tree().quit(_fails)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print("  [%s] %s" % ["PASS" if ok else "FAIL", msg])


func _diff_f32(a: PackedFloat32Array, b: PackedFloat32Array) -> int:
	if a.size() != b.size():
		return -1
	var bad := 0
	# Compare via to_byte_array so NaN/inf payloads and -0.0 vs 0.0 also count.
	var ba := a.to_byte_array()
	var bb := b.to_byte_array()
	if ba == bb:
		return 0
	for i in range(a.size()):
		if a[i] != b[i] or (is_nan(a[i]) != is_nan(b[i])):
			bad += 1
	return maxi(bad, 1)


func _diff_i32(a: PackedInt32Array, b: PackedInt32Array) -> int:
	if a.size() != b.size():
		return -1
	var bad := 0
	for i in range(a.size()):
		if a[i] != b[i]:
			bad += 1
	return bad


## Vector2 arrays compared via raw bytes: bit-identical, incl. -0.0 vs 0.0.
func _diff_v2(a: PackedVector2Array, b: PackedVector2Array) -> int:
	if a.size() != b.size():
		return -1
	return 0 if a.to_byte_array() == b.to_byte_array() else 1


func _diff_bytes(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return -1
	var bad := 0
	for i in range(a.size()):
		if a[i] != b[i]:
			bad += 1
	return bad


## Build a real hydrology-grid input by generating through Erosion, then A/B
## every ported function along the same chain rivers.gd uses (each stage's
## GDScript output feeds the next stage's comparison, so divergence can't hide).
func _run_seed(sd: int) -> void:
	var ws := WorldSettings.new()
	ws.main_seed = sd
	_gen.settings = ws
	await _gen.generate_up_to(WorldGenerator.GenStep.EROSION)
	var w := ws.map_width
	var h := ws.map_height
	var oth := ws.ocean_threshold
	var s: int = maxi(1, ws.river_resolution_divisor)
	var lw := w / s
	var lh := h / s
	var ln := lw * lh
	var lbase := PackedFloat32Array()
	lbase.resize(ln)
	for ly in range(lh):
		for lx in range(lw):
			lbase[(ly * lw) + lx] = _gen.height_buffer[((ly * s) * w) + (lx * s)]
	print("-- seed %d: grid %dx%d" % [sd, lw, lh])

	var native: Object = GenerationStep._native

	# 1) box_blur
	var t0 := Time.get_ticks_msec()
	var blur_n: PackedFloat32Array = native.box_blur(lbase, lw, lh, 2)
	var t1 := Time.get_ticks_msec()
	GenerationStep._native = null
	var blur_g := StepRivers.new()._box_blur(lbase, lw, lh, 2)
	GenerationStep._native = native
	var t2 := Time.get_ticks_msec()
	_check(_diff_f32(blur_n, blur_g) == 0,
		"box_blur bit-identical (%d bad) native %d ms vs gd %d ms" % [
			_diff_f32(blur_n, blur_g), t1 - t0, t2 - t1])

	# 2) fill_depressions (on the blurred grid, as rivers.gd does)
	t0 = Time.get_ticks_msec()
	var fill_n: PackedFloat32Array = native.fill_depressions(blur_g, lw, lh, oth)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var fill_g := GenerationStep.fill_depressions(blur_g, lw, lh, oth)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_f32(fill_n, fill_g) == 0,
		"fill_depressions bit-identical (%d bad) native %d ms vs gd %d ms" % [
			_diff_f32(fill_n, fill_g), t1 - t0, t2 - t1])

	# 3) flow_accumulate_mfd (uniform-ish deterministic seed field)
	var seedf := PackedFloat32Array()
	seedf.resize(ln)
	for i in range(ln):
		if blur_g[i] >= oth:
			seedf[i] = 0.001 + 0.5 * float(i % 17) / 17.0
	t0 = Time.get_ticks_msec()
	var acc_n: PackedFloat32Array = native.flow_accumulate_mfd(fill_g, seedf, lw, lh, oth, ws.river_flow_exponent)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var acc_g := GenerationStep.flow_accumulate_mfd(fill_g, seedf, lw, lh, oth, ws.river_flow_exponent)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_f32(acc_n, acc_g) == 0,
		"flow_accumulate_mfd bit-identical (%d bad) native %d ms vs gd %d ms" % [
			_diff_f32(acc_n, acc_g), t1 - t0, t2 - t1])

	# 4) dilate_lake (lake mask from the fill, as rivers.gd builds it)
	var mask := PackedByteArray()
	mask.resize(ln)
	var surf := PackedFloat32Array()
	surf.resize(ln)
	for i in range(ln):
		if blur_g[i] >= oth and fill_g[i] - blur_g[i] > ws.lake_min_depth:
			mask[i] = 1
			surf[i] = fill_g[i]
	t0 = Time.get_ticks_msec()
	var dil_n: Array = native.dilate_lake(mask, surf, lw, lh, 2)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var dil_g := StepRivers.new()._dilate_lake(mask.duplicate(), surf.duplicate(), lw, lh, 2)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_bytes(dil_n[0], dil_g[0]) == 0 and _diff_f32(dil_n[1], dil_g[1]) == 0,
		"dilate_lake bit-identical (mask %d, surf %d bad) native %d ms vs gd %d ms" % [
			_diff_bytes(dil_n[0], dil_g[0]), _diff_f32(dil_n[1], dil_g[1]), t1 - t0, t2 - t1])

	# --- NoiseBake: _multi (ridge + billow variants; engine noise both ways) ---
	t0 = Time.get_ticks_msec()
	var mr_n: Image = NoiseBaker._multi(w, h, sd + ws.peaks_seed_offset, ws.ridge_frequency,
		ws.peaks_octaves, ws.peaks_gain, ws.peaks_lacunarity, true, ws.ridge_offset,
		ws.peaks_warp_amp, ws.peaks_warp_freq)
	var mb_n: Image = NoiseBaker._multi(w, h, sd + ws.peaks_seed_offset + 57, ws.billow_frequency,
		ws.peaks_octaves, ws.peaks_gain, ws.peaks_lacunarity, false, ws.ridge_offset,
		ws.peaks_warp_amp, ws.peaks_warp_freq)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var mr_g := NoiseBaker._multi(w, h, sd + ws.peaks_seed_offset, ws.ridge_frequency,
		ws.peaks_octaves, ws.peaks_gain, ws.peaks_lacunarity, true, ws.ridge_offset,
		ws.peaks_warp_amp, ws.peaks_warp_freq)
	var mb_g := NoiseBaker._multi(w, h, sd + ws.peaks_seed_offset + 57, ws.billow_frequency,
		ws.peaks_octaves, ws.peaks_gain, ws.peaks_lacunarity, false, ws.ridge_offset,
		ws.peaks_warp_amp, ws.peaks_warp_freq)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(mr_n.get_data() == mr_g.get_data() and mb_n.get_data() == mb_g.get_data()
			and mr_n.get_format() == mr_g.get_format() and mb_n.get_format() == mb_g.get_format(),
		"bake_multifractal bit-identical (ridge %s, billow %s) native %d ms vs gd %d ms" % [
			mr_n.get_data() == mr_g.get_data(), mb_n.get_data() == mb_g.get_data(), t1 - t0, t2 - t1])

	# --- Rivers residual: the extracted execute() loops (same input chain) ---
	var riv := StepRivers.new()

	# 4b) river_downsample (full-res height at EROSION state)
	t0 = Time.get_ticks_msec()
	var down_n: PackedFloat32Array = native.river_downsample(_gen.height_buffer, w, h, s, lw, lh)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var down_g := riv._downsample_grid(_gen.height_buffer, w, h, s, lw, lh)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_f32(down_n, down_g) == 0,
		"river_downsample bit-identical (%d bad) native %d ms vs gd %d ms" % [
			_diff_f32(down_n, down_g), t1 - t0, t2 - t1])

	# 4c) river_seed_field (humidity via the engine's Image.get_pixel both ways)
	var hum := _gen.noise_img("humidity")
	t0 = Time.get_ticks_msec()
	var sf_n: PackedFloat32Array = native.river_seed_field(blur_g, hum, w, h, s, lw, lh, oth,
		ws.river_source_humidity_bias, ws.river_source_elevation_bias)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var sf_g := riv._seed_field(blur_g, hum, w, h, s, lw, lh, oth,
		ws.river_source_humidity_bias, ws.river_source_elevation_bias)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_f32(sf_n, sf_g) == 0,
		"river_seed_field bit-identical (%d bad) native %d ms vs gd %d ms" % [
			_diff_f32(sf_n, sf_g), t1 - t0, t2 - t1])

	# 4d) river_depth_stamp (on the real MFD accumulation)
	t0 = Time.get_ticks_msec()
	var dp_n: PackedFloat32Array = native.river_depth_stamp(blur_g, acc_g, lw, lh, oth,
		ws.river_accum_threshold, ws.river_carve_depth, ws.river_width_gain)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var dp_g := riv._depth_stamp(blur_g, acc_g, lw, lh, oth,
		ws.river_accum_threshold, ws.river_carve_depth, ws.river_width_gain)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_f32(dp_n, dp_g) == 0,
		"river_depth_stamp bit-identical (%d bad) native %d ms vs gd %d ms" % [
			_diff_f32(dp_n, dp_g), t1 - t0, t2 - t1])

	# 4e) river_lake_surfaces (basin labeling + spill levels)
	t0 = Time.get_ticks_msec()
	var lk_n: Array = native.river_lake_surfaces(blur_g, fill_g, lw, lh, oth,
		ws.lake_min_depth, ws.lake_min_area, ws.lake_carve_depth)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var lk_g := riv._lake_surfaces(blur_g, fill_g, lw, lh, oth,
		ws.lake_min_depth, ws.lake_min_area, ws.lake_carve_depth)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_bytes(lk_n[0], lk_g[0]) == 0 and _diff_f32(lk_n[1], lk_g[1]) == 0,
		"river_lake_surfaces bit-identical (mask %d, surf %d bad) native %d ms vs gd %d ms" % [
			_diff_bytes(lk_n[0], lk_g[0]), _diff_f32(lk_n[1], lk_g[1]), t1 - t0, t2 - t1])

	# 4f) river_apply_water (full-res carve + node lists + masks)
	var wsurf := PackedFloat32Array()
	wsurf.resize(w * h)
	wsurf.fill(WorldGenerator.NO_WATER)
	t0 = Time.get_ticks_msec()
	var ap_n: Array = native.river_apply_water(_gen.height_buffer, wsurf,
		lk_g[0], lk_g[1], dp_g, w, h, s, lw, lh, oth)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var ap_g := riv._apply_water(_gen.height_buffer, wsurf,
		lk_g[0], lk_g[1], dp_g, w, h, s, lw, lh, oth)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_f32(ap_n[0], ap_g[0]) == 0 and _diff_f32(ap_n[1], ap_g[1]) == 0
			and _diff_i32(ap_n[2], ap_g[2]) == 0 and _diff_i32(ap_n[3], ap_g[3]) == 0
			and _diff_bytes(ap_n[4], ap_g[4]) == 0 and _diff_bytes(ap_n[5], ap_g[5]) == 0,
		"river_apply_water bit-identical (h %d ws %d rn %d ln %d rm %d lm %d bad) native %d ms vs gd %d ms" % [
			_diff_f32(ap_n[0], ap_g[0]), _diff_f32(ap_n[1], ap_g[1]),
			_diff_i32(ap_n[2], ap_g[2]), _diff_i32(ap_n[3], ap_g[3]),
			_diff_bytes(ap_n[4], ap_g[4]), _diff_bytes(ap_n[5], ap_g[5]), t1 - t0, t2 - t1])

	# --- Phase 2: GraphPlacement.MapField (full-res, real lakes/rivers) ---
	await _gen.generate_up_to(WorldGenerator.GenStep.RIVERS)
	var fn := GraphPlacement.MapField.new()
	var fg := GraphPlacement.MapField.new()
	for f: GraphPlacement.MapField in [fn, fg]:
		f.w = w
		f.h = h
		f.oth = oth
		f.height = _gen.height_buffer
		f._build_masks(_gen.lake_nodes, _gen.river_nodes)

	# 5) label_landmasses (fn = native, fg = forced GDScript; fg's outputs feed
	# nothing native later, mirroring how divergence can't hide in the chain).
	t0 = Time.get_ticks_msec()
	fn._label_landmasses()
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	fg._label_landmasses()
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	var lab_bad := _diff_i32(fn.label, fg.label)
	_check(lab_bad == 0 and fn.sizes == fg.sizes and fn.label_seed == fg.label_seed
			and fn.main_label == fg.main_label and fn.total_land == fg.total_land,
		"label_landmasses identical (%d bad, sizes %s, main %s) native %d ms vs gd %d ms" % [
			lab_bad, fn.sizes == fg.sizes, fn.main_label == fg.main_label, t1 - t0, t2 - t1])

	# 5b) measure_land (float32 accumulation must match exactly)
	t0 = Time.get_ticks_msec()
	fn._measure_land()
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	fg._measure_land()
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(fn.land_min == fg.land_min and fn.land_max == fg.land_max
			and fn.land_centroid == fg.land_centroid,
		"measure_land identical (min %s max %s centroid %s) native %d ms vs gd %d ms" % [
			fn.land_min == fg.land_min, fn.land_max == fg.land_max,
			fn.land_centroid == fg.land_centroid, t1 - t0, t2 - t1])

	# 6) distance transform (default downscale 2)
	t0 = Time.get_ticks_msec()
	fn._build_distance_transform(2)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	fg._build_distance_transform(2)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_f32(fn.dt, fg.dt) == 0,
		"map_distance_transform bit-identical (%d bad) native %d ms vs gd %d ms" % [
			_diff_f32(fn.dt, fg.dt), t1 - t0, t2 - t1])

	# 7) Poisson land samples (default path; RNG sequence must match exactly)
	var spacing: float = ws.map_diag() * ws.graph_sample_spacing_ratio
	t0 = Time.get_ticks_msec()
	fn.build_land_samples(spacing, sd, true)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	fg.build_land_samples(spacing, sd, true)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_v2(fn.samples, fg.samples) == 0 and _diff_i32(fn.sample_label, fg.sample_label) == 0,
		"poisson_land_samples bit-identical (%d samples, v2 %d, lab %d bad) native %d ms vs gd %d ms" % [
			fn.samples.size(), _diff_v2(fn.samples, fg.samples),
			_diff_i32(fn.sample_label, fg.sample_label), t1 - t0, t2 - t1])

	# 8) Poisson again confined to the main landmass (the "largest" domain mode)
	fn.confine_main = true
	fg.confine_main = true
	fn.build_land_samples(spacing, sd, true)
	GenerationStep._native = null
	fg.build_land_samples(spacing, sd, true)
	GenerationStep._native = native
	_check(_diff_v2(fn.samples, fg.samples) == 0,
		"poisson_land_samples (confine_main) bit-identical (%d samples, %d bad)" % [
			fn.samples.size(), _diff_v2(fn.samples, fg.samples)])
	fn.confine_main = false
	fg.confine_main = false

	# 9) jittered fallback path
	t0 = Time.get_ticks_msec()
	fn.build_land_samples(spacing, sd, false)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	fg.build_land_samples(spacing, sd, false)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(_diff_v2(fn.samples, fg.samples) == 0,
		"jittered_land_samples bit-identical (%d samples, %d bad) native %d ms vs gd %d ms" % [
			fn.samples.size(), _diff_v2(fn.samples, fg.samples), t1 - t0, t2 - t1])

	# --- Phase 3: BiomeRegions.build_cells (uses fg with fresh Poisson samples) ---
	GenerationStep._native = null
	fg.build_land_samples(spacing, sd, true)  # restore the default lattice (GDScript path)
	GenerationStep._native = native
	var warpb: PackedByteArray = _gen.noise_img("biome_warp").get_data()
	var humidb: PackedByteArray = _gen.noise_img("humidity").get_data()
	var bopts := ws.biome_opts()
	t0 = Time.get_ticks_msec()
	var cells_n := BiomeRegions.build_cells(fg, warpb, humidb, bopts)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var cells_g := BiomeRegions.build_cells(fg, warpb, humidb, bopts)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	var adj_ok := int(cells_n.n_cells) == int(cells_g.n_cells)
	if adj_ok:
		for c in range(int(cells_n.n_cells)):
			# keys() compares CONTENT AND ORDER -- paint_cells iterates these dicts.
			if (cells_n.adj[c] as Dictionary).keys() != (cells_g.adj[c] as Dictionary).keys():
				adj_ok = false
				break
	_check(_diff_i32(cells_n.cell_of, cells_g.cell_of) == 0
			and _diff_i32(cells_n.px_count, cells_g.px_count) == 0
			and _diff_f32(cells_n.sum_h, cells_g.sum_h) == 0
			and _diff_f32(cells_n.sum_m, cells_g.sum_m) == 0
			and _diff_i32(cells_n.cell_label, cells_g.cell_label) == 0
			and int(cells_n.orphan_cells) == int(cells_g.orphan_cells) and adj_ok,
		"biome_build_cells bit-identical (%d cells, of %d px %d sh %d sm %d cl %d adj %s) native %d ms vs gd %d ms" % [
			int(cells_n.n_cells), _diff_i32(cells_n.cell_of, cells_g.cell_of),
			_diff_i32(cells_n.px_count, cells_g.px_count), _diff_f32(cells_n.sum_h, cells_g.sum_h),
			_diff_f32(cells_n.sum_m, cells_g.sum_m), _diff_i32(cells_n.cell_label, cells_g.cell_label),
			adj_ok, t1 - t0, t2 - t1])

	# --- Phase 4A: GraphDetail.compute_curves (A* edge routing) ---------------
	# Whole-step A/B: the per-edge loop, occupancy stamping and route ORDER stay
	# GDScript both ways, so any divergence is _route's. Curves are compared as
	# raw PackedVector2Array bytes.
	var rfield := GraphPlacement.MapField.from_generator(_gen, ws.field_opts())
	var spec := GraphSpec.build_nodes(ws.spec_cities, ws.spec_nodes_between_cities, 2, 5, sd)
	var ctx = GraphPlacement.place(spec, rfield, ws, sd, ws.place_opts())["ctx"]
	var ropts := ws.route_opts()
	t0 = Time.get_ticks_msec()
	var cur_n := GraphDetail.compute_curves(ctx, rfield, ropts)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var cur_g := GraphDetail.compute_curves(ctx, rfield, ropts)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	var curve_bad := 0
	if cur_n.size() != cur_g.size():
		curve_bad = -1
	else:
		for i in range(cur_n.size()):
			if int(cur_n[i][0]) != int(cur_g[i][0]) or int(cur_n[i][1]) != int(cur_g[i][1]) \
					or _diff_v2(cur_n[i][2], cur_g[i][2]) != 0:
				curve_bad += 1
	_check(curve_bad == 0,
		"route_edge bit-identical (%d curves, %d bad) native %d ms vs gd %d ms" % [
			cur_n.size(), curve_bad, t1 - t0, t2 - t1])

	# --- Phase 4B: WorldMapPainter._paint (per-pixel classifier) --------------
	# All three layer variants (land / water+ocean / composite) over the real
	# post-Biomes snapshot, compared as raw Image bytes -- which is also the gate
	# on the RGBA8 truncation the native writer reproduces by hand.
	await _gen.generate_up_to(WorldGenerator.GenStep.BIOMES)
	var pdata: Dictionary = _gen.snapshots.get("Biomes", {})
	var pcol := WorldHeightColorizer.make_default(oth, ws.mountain_threshold)
	var pset := ws.active_biome_set()
	t0 = Time.get_ticks_msec()
	var land_n := WorldMapPainter.land_only_image(pdata, w, h, oth, pcol, pset)
	var water_n := WorldMapPainter.water_only_image(pdata, w, h, oth, pcol, true)
	var comp_n := WorldMapPainter.composite_image(pdata, w, h, oth, pcol, pset)
	t1 = Time.get_ticks_msec()
	GenerationStep._native = null
	var land_g := WorldMapPainter.land_only_image(pdata, w, h, oth, pcol, pset)
	var water_g := WorldMapPainter.water_only_image(pdata, w, h, oth, pcol, true)
	var comp_g := WorldMapPainter.composite_image(pdata, w, h, oth, pcol, pset)
	GenerationStep._native = native
	t2 = Time.get_ticks_msec()
	_check(land_n.get_data() == land_g.get_data() and water_n.get_data() == water_g.get_data()
			and comp_n.get_data() == comp_g.get_data()
			and land_n.get_format() == land_g.get_format(),
		"paint_map bit-identical (land %s, water %s, composite %s) native %d ms vs gd %d ms" % [
			land_n.get_data() == land_g.get_data(), water_n.get_data() == water_g.get_data(),
			comp_n.get_data() == comp_g.get_data(), t1 - t0, t2 - t1])
