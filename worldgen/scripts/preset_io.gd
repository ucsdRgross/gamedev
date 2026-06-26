class_name PresetIO
extends RefCounted

## Static helpers for the map_viewer recording workflow. Density-model edition:
##   - save_preset(step, "good"/"bad") : record a per-step preset tagged good or bad
##   - process_step_ranges(step)       : build a weighted histogram per param from the
##                                       current batch (good adds weight, bad subtracts),
##                                       write ranges.json, then ARCHIVE the batch so the
##                                       next round narrows fresh (epoch behavior)
##   - load_ranges(step) / sample_entry(): weighted draw -- values confirmed more often
##                                       are sampled more; bad pockets are avoided
##   - clear_step_data(step)           : reset valve (archive presets + drop ranges.json)
##
## Per-step isolation: a step's folder holds only that step's params, so tuning a
## later step never disturbs an earlier one. Persistence is plain JSON via FileAccess
## (+ a .tres for good presets); neither gets an .import sidecar, so no .gdignore.

const PRESET_ROOT := "res://presets"

## Never randomized: seeds, per-step seed offsets, and map dimensions.
const EXCLUDE := {
	"main_seed": true, "map_width": true, "map_height": true,
	"landmass_seed_offset": true, "tectonic_seed_offset": true,
	"peaks_seed_offset": true, "erosion_seed_offset": true,
	"erosion_humidity_seed_offset": true, "temperature_seed_offset": true,
	"humidity_seed_offset": true,
}

## Fallback [lo, hi] for params that carry no @export_range hint (plain int/float).
const DEFAULT_RANGES := {
	"continent_frequency": [0.001, 0.01], "detail_frequency": [0.01, 0.1],
	"ridge_frequency": [0.004, 0.03], "ocean_threshold": [0.25, 0.5],
	"mountain_threshold": [0.5, 0.8], "island_radius": [0.4, 0.9],
	"land_contrast": [0.8, 2.0], "boundary_radius": [0.3, 0.6],
	"edge_jag": [0.0, 0.2], "peak_uplift": [0.0, 0.6],
	"highland_range": [0.1, 0.5], "peak_detail_strength": [0.0, 0.3],
	"continent_warp_amp": [0.0, 40.0], "continent_warp_freq": [0.002, 0.03],
	"peaks_warp_amp": [0.0, 60.0], "peaks_warp_freq": [0.002, 0.03],
	"billow_frequency": [0.005, 0.05], "peak_billow_strength": [0.0, 0.3],
	"plate_count": [3, 12], "drift_intensity": [0.0, 0.6],
	"plate_move": [0.0, 0.1], "tectonic_band": [20.0, 100.0],
	"warp_strength": [10.0, 100.0], "warp_frequency": [1.0, 10.0],
	"temp_frequency": [0.005, 0.05], "humid_frequency": [0.005, 0.05],
	"erosion_amplitude": [0.0, 0.2], "erosion_frequency": [8.0, 48.0],
	"erosion_lacunarity": [1.0, 2.5], "erosion_branch_angle_deg": [0.0, 90.0],
	"erosion_detail": [0.5, 2.0], "erosion_steepness_scale": [20.0, 200.0],
	"river_accum_threshold": [20.0, 120.0], "river_carve_depth": [0.0, 0.06],
	"erosion_min_elevation": [0.38, 0.6], "erosion_elevation_falloff": [0.02, 0.3],
	"peak_detail_min_elevation": [0.38, 0.7], "peak_detail_falloff": [0.02, 0.3],
	"island_falloff": [0.3, 1.6], "boundary_falloff": [0.01, 0.15],
	"temp_lapse_rate": [0.0, 1.0], "river_humidity_boost": [0.0, 0.6],
	"lowland_flatten": [1.0, 4.0],
}

## Which generation step each tunable parameter belongs to (the step at which you
## tune + judge it). Keys match map_viewer's STEP_INFO names. Used so saving,
## range-finding, and randomization can be isolated to a single step -- tuning a
## later step never touches an earlier step's values. Every tunable param must
## appear here exactly once (see _coverage_check()).
const STEP_PARAMS := {
	"Landmass": [
		"continent_frequency", "ocean_threshold", "island_radius", "land_contrast",
		"island_falloff", "edge_jag", "continent_octaves", "continent_gain",
		"continent_lacunarity", "continent_warp_amp", "continent_warp_freq",
	],
	"Tectonics": [
		"plate_count", "drift_intensity", "plate_move", "tectonic_band",
		"warp_strength", "warp_frequency", "land_plate_ratio", "land_rift_damping",
		"tectonic_height_cap",
	],
	"Peaks": [
		"detail_frequency", "ridge_frequency", "mountain_threshold", "lowland_flatten",
		"boundary_radius", "boundary_falloff", "peak_uplift", "highland_range",
		"peak_detail_strength", "peak_height_cap", "peak_detail_min_elevation",
		"peak_detail_falloff", "peaks_octaves", "peaks_gain", "peaks_lacunarity",
		"ridge_offset", "peaks_warp_amp", "peaks_warp_freq", "billow_frequency",
		"peak_billow_strength",
	],
	"Erosion": [
		"erosion_octaves", "erosion_amplitude", "erosion_frequency", "erosion_gain",
		"erosion_lacunarity", "erosion_branch_angle_deg", "erosion_ridge_rounding",
		"erosion_gully_rounding", "erosion_detail", "erosion_steepness_scale",
		"erosion_min_elevation", "erosion_elevation_falloff",
	],
	"Rivers": [
		"river_resolution_divisor", "river_source_humidity_bias",
		"river_source_elevation_bias", "river_accum_threshold", "river_carve_depth",
		"river_width_gain", "river_flow_exponent", "river_smooth_passes",
		"lake_min_depth", "lake_min_area", "lake_carve_depth", "lake_width",
	],
	"Climate": [
		"temp_frequency", "humid_frequency", "temp_lapse_rate", "river_humidity_boost",
		"height_bands", "temp_bands", "humid_bands",
	],
	"Cities": [
		"city_dist_ratio", "max_city_count", "travel_dist_ratio", "max_travel_count",
		"coast_radius_ratio",
	],
	"Graph": [
		"spec_cities", "spec_nodes_between_cities", "spec_graph_width", "spec_outgoing",
		"spec_min_outgoing_after_trim", "spec_edge_trim_chance", "layer_count",
		"min_outgoing", "max_outgoing", "min_outgoing_after_trim",
		"min_nodes_between_cities", "max_nodes_between_cities", "min_cities_visited",
		"max_cities_visited", "city_bottleneck_strength", "min_graph_width",
		"min_biomes_per_path", "max_biomes_per_path", "max_landmasses",
		"max_cross_ocean_per_band", "water_crossing_ratio", "start_end_island_penalty",
		"start_end_min_connections", "mountain_pass_bias", "graph_anti_straight",
		"graph_zigzag_penalty", "edge_trim_chance", "path_curve_max_ratio",
		"path_curve_min_ratio", "failsafe_max_injected_nodes", "max_paths_enumerated",
		"graph_build_passes",
	],
}

## The tunable params assigned to a step (empty Array if the step is unknown).
static func step_params(step: String) -> Array:
	return STEP_PARAMS.get(step, [])

## Debug: any tunable params not assigned to exactly one step. Print at startup if
## you add a new @export and forget to slot it into STEP_PARAMS.
static func coverage_gaps() -> Array:
	var assigned := {}
	for s in STEP_PARAMS:
		for p in STEP_PARAMS[s]:
			assigned[p] = true
	var missing := []
	for p in tunable_params():
		if not assigned.has(p):
			missing.append(p)
	return missing

## name -> [lo, hi, is_int] for every randomizable WorldSettings parameter.
static func param_ranges() -> Dictionary:
	var out := {}
	var ws := WorldSettings.new()
	for p in ws.get_property_list():
		if (int(p.usage) & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if not (p.type == TYPE_FLOAT or p.type == TYPE_INT):
			continue
		var pname: String = p.name
		if EXCLUDE.has(pname):
			continue
		var is_int :bool= p.type == TYPE_INT
		if int(p.hint) == PROPERTY_HINT_RANGE and String(p.hint_string) != "":
			var nums := _parse_range_hint(String(p.hint_string))
			if nums.size() >= 2:
				out[pname] = [nums[0], nums[1], is_int]
				continue
		if DEFAULT_RANGES.has(pname):
			var r: Array = DEFAULT_RANGES[pname]
			out[pname] = [float(r[0]), float(r[1]), is_int]
	return out

static func _parse_range_hint(hint: String) -> Array:
	# "lo,hi" or "lo,hi,step" or "lo,hi,step,or_greater" -> first two numerics.
	var nums := []
	for tok in hint.split(","):
		var t := tok.strip_edges()
		if t.is_valid_float():
			nums.append(float(t))
	return nums

## name -> is_int for EVERY tunable WorldSettings param (all editor int/float minus
## EXCLUDE), regardless of whether it has a predefined range. This is the canonical
## "save everything" set, so no finetuned value is silently dropped from a preset.
static func tunable_params() -> Dictionary:
	var out := {}
	for p in WorldSettings.new().get_property_list():
		if (int(p.usage) & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if not (p.type == TYPE_FLOAT or p.type == TYPE_INT):
			continue
		var pname: String = p.name
		if EXCLUDE.has(pname):
			continue
		out[pname] = (p.type == TYPE_INT)
	return out

## Snapshot ONLY this step's params (+ main_seed for provenance) into a flat dict.
## Per-step isolation: a Landmass preset holds only Landmass params, so processing
## the Landmass folder yields Landmass ranges and never disturbs other steps.
static func settings_to_dict(settings: WorldSettings, step: String) -> Dictionary:
	var d := {"_step": step, "main_seed": settings.main_seed}
	for pname in step_params(step):
		d[pname] = settings.get(pname)
	return d

# Histogram resolution for the density model.
const BINS := 12

## Save a GOOD or BAD preset to res://presets/<step>/. Good presets also write a
## .tres (drag-droppable). verdict is "good" or "bad". Returns the json path or "".
static func save_preset(settings: WorldSettings, step: String, verdict: String = "good") -> String:
	var dir := "%s/%s" % [PRESET_ROOT, step]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK \
			and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		push_error("[PresetIO] could not create %s" % dir)
		return ""
	var stamp := "%s_%d_%d" % [verdict, settings.main_seed, int(Time.get_unix_time_from_system())]
	var stem := "%s/%s" % [dir, stamp]
	if verdict == "good":
		ResourceSaver.save(settings, stem + ".tres")
	var d := settings_to_dict(settings, step)
	d["_verdict"] = verdict
	var f := FileAccess.open(stem + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "  "))
		f.close()
	return stem + ".json"

## Build a density model from this batch of good/bad presets, write it to
## ranges.json, then ARCHIVE the consumed presets so the next batch starts fresh
## (epoch narrowing -- new results are not mixed with old generations). Per param:
##   good saves add weight to their value's histogram bin, bad saves subtract.
## Randomize then samples bins proportional to (clamped) weight, so values you
## confirmed multiple times dominate and bad pockets are avoided.
static func process_step_ranges(step: String) -> Dictionary:
	var dir := "%s/%s" % [PRESET_ROOT, step]
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return {}
	var good := {}   # param -> Array[float]
	var bad := {}
	var move_list := []
	for fn in DirAccess.get_files_at(dir):
		if fn == "ranges.json":
			continue
		move_list.append(fn)  # everything else gets archived after processing
		if not fn.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [dir, fn]))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var bucket: Dictionary = bad if String(parsed.get("_verdict", "good")) == "bad" else good
		for k in parsed:
			if String(k).begins_with("_") or EXCLUDE.has(k):
				continue
			var tv := typeof(parsed[k])
			if tv != TYPE_FLOAT and tv != TYPE_INT:
				continue
			if not bucket.has(k):
				bucket[k] = []
			bucket[k].append(float(parsed[k]))

	var tp := tunable_params()
	var params := {}
	for k in good: params[k] = true
	for k in bad: params[k] = true
	var out := {}
	for p in params:
		var gv: Array = good.get(p, [])
		if gv.is_empty():
			continue  # only bad seen -> nothing positive to sample; leave to defaults
		var bv: Array = bad.get(p, [])
		var lo: float = gv.min()
		var hi: float = gv.max()
		for v in bv:  # widen the domain to include nearby bad values so they can carve
			lo = minf(lo, v); hi = maxf(hi, v)
		if hi <= lo:
			hi = lo + maxf(absf(lo) * 0.01, 1e-4)
		var bins := []
		bins.resize(BINS)
		bins.fill(0.0)
		var bstep := (hi - lo) / float(BINS)
		for v in gv:
			bins[clampi(int((v - lo) / bstep), 0, BINS - 1)] += 1.0
		for v in bv:
			bins[clampi(int((v - lo) / bstep), 0, BINS - 1)] -= 1.0
		for i in BINS:
			bins[i] = maxf(bins[i], 0.0)
		out[p] = {"lo": lo, "hi": hi, "bins": bins, "is_int": tp.get(p, false),
			"good_n": gv.size(), "bad_n": bv.size()}

	var f := FileAccess.open("%s/ranges.json" % dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	_archive_files(dir, move_list)
	print("[PresetIO] '%s': %d presets -> %d param models, archived batch." % [step, move_list.size(), out.size()])
	return out

## Read the density model (rich entries) written by process_step_ranges.
static func load_ranges(step: String) -> Dictionary:
	var path := "%s/%s/ranges.json" % [PRESET_ROOT, step]
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

## Draw a value from one density entry. Bins with weight < min_conf are ignored
## (so values confirmed fewer than min_conf times are dropped); if nothing
## qualifies, fall back to a uniform draw over the whole [lo, hi] band.
static func sample_entry(entry: Dictionary, rng: RandomNumberGenerator, min_conf: float) -> float:
	var lo: float = float(entry.get("lo", 0.0))
	var hi: float = float(entry.get("hi", 1.0))
	var bins: Array = entry.get("bins", [])
	if bins.is_empty():
		return rng.randf_range(lo, hi)
	var total := 0.0
	var elig := []
	for w in bins:
		var ww: float = float(w) if float(w) >= min_conf else 0.0
		elig.append(ww)
		total += ww
	if total <= 0.0:
		return rng.randf_range(lo, hi)
	var pick := rng.randf() * total
	var idx := elig.size() - 1
	for i in elig.size():
		pick -= elig[i]
		if pick <= 0.0:
			idx = i
			break
	var bstep := (hi - lo) / float(bins.size())
	return rng.randf_range(lo + float(idx) * bstep, lo + float(idx + 1) * bstep)

## Reset valve: archive every preset for a step and delete its ranges.json so the
## step starts from defaults again.
static func clear_step_data(step: String) -> void:
	var dir := "%s/%s" % [PRESET_ROOT, step]
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return
	var move_list := []
	for fn in DirAccess.get_files_at(dir):
		if fn == "ranges.json":
			continue
		move_list.append(fn)
	_archive_files(dir, move_list)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/ranges.json" % dir))
	print("[PresetIO] cleared '%s' (archived %d presets, removed ranges.json)." % [step, move_list.size()])

# Move the listed files from a step dir into a timestamped archive subfolder.
static func _archive_files(dir: String, files: Array) -> void:
	if files.is_empty():
		return
	var adir := "%s/archive/%d" % [dir, int(Time.get_unix_time_from_system())]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(adir))
	for fn in files:
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path("%s/%s" % [dir, fn]),
			ProjectSettings.globalize_path("%s/%s" % [adir, fn]))
