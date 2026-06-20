class_name PresetIO
extends RefCounted

## Static helpers for the map_viewer recording workflow:
##   - param_ranges()        : discover per-parameter [lo, hi, is_int] envelopes
##   - save_preset()         : write a tuned WorldSettings into a per-step folder
##   - process_step_ranges() : aggregate a folder of saved presets -> min/max/mean
##   - load_step_ranges()    : ranges.json if present, else the export-hint ranges
##
## Persistence mirrors the res://tuning convention: plain JSON via FileAccess, plus
## a canonical .tres per preset (drag-droppable back onto the generator). JSON and
## .tres do not get .import sidecars, so no .gdignore is needed.

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
}

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

## Snapshot the randomizable params (+ main_seed) into a flat dict tagged by step.
static func settings_to_dict(settings: WorldSettings, step: String) -> Dictionary:
	var d := {"_step": step, "main_seed": settings.main_seed}
	for pname in param_ranges():
		d[pname] = settings.get(pname)
	return d

## Save settings to res://presets/<step>/<seed>_<unixtime>.{tres,json}. Returns the
## stem path (without extension), or "" on failure.
static func save_preset(settings: WorldSettings, step: String) -> String:
	var dir := "%s/%s" % [PRESET_ROOT, step]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK \
			and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		push_error("[PresetIO] could not create %s" % dir)
		return ""
	var stamp := "%d_%d" % [settings.main_seed, int(Time.get_unix_time_from_system())]
	var stem := "%s/%s" % [dir, stamp]
	ResourceSaver.save(settings, stem + ".tres")
	var f := FileAccess.open(stem + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings_to_dict(settings, step), "  "))
		f.close()
	return stem

## Aggregate every *.json preset in a step folder into a min/max/mean envelope,
## written to ranges.json. Returns the envelope dict (empty if no presets).
static func process_step_ranges(step: String) -> Dictionary:
	var dir := "%s/%s" % [PRESET_ROOT, step]
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return {}
	var agg := {}
	var count := 0
	for fn in DirAccess.get_files_at(dir):
		if not fn.ends_with(".json") or fn == "ranges.json":
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [dir, fn]))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		count += 1
		for k in parsed:
			if String(k).begins_with("_"):
				continue
			var tv := typeof(parsed[k])
			if tv != TYPE_FLOAT and tv != TYPE_INT:
				continue
			var v := float(parsed[k])
			if not agg.has(k):
				agg[k] = {"min": v, "max": v, "sum": 0.0, "n": 0}
			agg[k]["min"] = minf(agg[k]["min"], v)
			agg[k]["max"] = maxf(agg[k]["max"], v)
			agg[k]["sum"] += v
			agg[k]["n"] += 1
	var out := {}
	for k in agg:
		out[k] = {"min": agg[k]["min"], "max": agg[k]["max"],
			"mean": agg[k]["sum"] / float(maxi(1, agg[k]["n"]))}
	var f := FileAccess.open("%s/ranges.json" % dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	print("[PresetIO] processed %d presets for '%s' -> %d params" % [count, step, out.size()])
	return out

## Effective sampling ranges for a step: export-hint ranges narrowed by ranges.json
## where present. Returns name -> [lo, hi, is_int].
static func load_step_ranges(step: String) -> Dictionary:
	var base := param_ranges()
	var path := "%s/%s/ranges.json" % [PRESET_ROOT, step]
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			for k in parsed:
				if base.has(k) and typeof(parsed[k]) == TYPE_DICTIONARY:
					var e: Dictionary = parsed[k]
					base[k] = [float(e.get("min", base[k][0])),
						float(e.get("max", base[k][1])), base[k][2]]
	return base
