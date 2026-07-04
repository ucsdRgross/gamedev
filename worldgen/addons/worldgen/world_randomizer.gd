class_name WorldRandomizer
extends RefCounted

## Single source of truth for the worldgen parameter tables + density-model sampler.
## Owns which WorldSettings params are tunable, which generation step each belongs to,
## their fallback ranges, and the inverse-CDF draw used by Randomize. The addon reads a
## compact merged density model (`ranges_bundle.json`) via load_bundle()/randomize_*();
## the dev-side recording workflow (PresetIO) delegates its tables + sampler here so the
## two never drift. Nothing in this file touches the dev `presets/` tree -- bundle export
## is fed a loader Callable so the addon stays self-contained.

## Merged density model shipped inside the addon (regenerated from presets/ by the dev
## "Export ranges bundle" button). Format: {"version":1, "steps": {step: {param: entry}}}.
const BUNDLE_PATH := "res://addons/worldgen/ranges_bundle.json"

## Never randomized: seeds, per-step seed offsets, and map dimensions.
const EXCLUDE := {
	"main_seed": true, "map_width": true, "map_height": true,
	"landmass_seed_offset": true, "tectonic_seed_offset": true,
	"peaks_seed_offset": true, "erosion_seed_offset": true,
	"erosion_humidity_seed_offset": true, "humidity_seed_offset": true,
}

## Fallback [lo, hi] for params that carry no @export_range hint (plain int/float).
const DEFAULT_RANGES := {
	"continent_frequency": [0.001, 0.01], "detail_frequency": [0.01, 0.1],
	"ridge_frequency": [0.004, 0.03], "ocean_threshold": [0.25, 0.5],
	"mountain_threshold": [0.5, 0.8], "island_radius": [0.4, 0.9],
	"land_contrast": [0.8, 2.0], "boundary_radius": [0.4, 0.45],
	"edge_jag": [0.0, 0.2], "peak_uplift": [0.0, 0.6],
	"highland_range": [0.1, 0.5], "peak_detail_strength": [0.0, 0.3],
	"continent_warp_amp": [0.0, 40.0], "continent_warp_freq": [0.002, 0.03],
	"peaks_warp_amp": [0.0, 60.0], "peaks_warp_freq": [0.002, 0.03],
	"billow_frequency": [0.005, 0.05], "peak_billow_strength": [0.0, 0.3],
	"plate_count": [3, 12], "drift_intensity": [0.0, 0.6],
	"plate_move": [0.0, 0.1], "tectonic_band": [20.0, 100.0],
	"warp_strength": [10.0, 100.0], "warp_frequency": [1.0, 10.0],
	"humid_frequency": [0.005, 0.05],
	"erosion_amplitude": [0.0, 0.2], "erosion_frequency": [8.0, 48.0],
	"erosion_lacunarity": [1.0, 2.5], "erosion_branch_angle_deg": [0.0, 90.0],
	"erosion_detail": [0.5, 2.0], "erosion_steepness_scale": [20.0, 200.0],
	"river_accum_threshold": [20.0, 120.0], "river_carve_depth": [0.0, 0.06],
	"erosion_min_elevation": [0.38, 0.6], "erosion_elevation_falloff": [0.02, 0.3],
	"peak_detail_min_elevation": [0.38, 0.7], "peak_detail_falloff": [0.02, 0.3],
	"island_falloff": [0.3, 1.6], "boundary_falloff": [0.01, 0.05],
	"lowland_flatten": [1.0, 2.0],
	# Graph (ladder placement + edge routing) params without @export_range hints.
	"spec_cities": [2, 12], "spec_nodes_between_cities": [0, 6],
	"spec_outgoing": [1, 6], "graph_min_width": [1, 3],
	"graph_max_width": [3, 8], "graph_lane_tol": [1.2, 2.5],
	"graph_branch_local_mul": [1.5, 4.0], "graph_pole_sep": [0.5, 3.0],
	"coast_radius_ratio": [0.008, 0.03], "graph_sample_spacing_ratio": [0.008, 0.02],
	"route_downscale": [2, 6], "route_node_clearance": [4.0, 16.0],
	"route_node_penalty": [5.0, 40.0], "route_border_penalty": [10.0, 50.0],
	"route_backtrack_penalty": [0.0, 8.0], "route_land_penalty": [2.0, 20.0],
	"route_water_penalty": [2.0, 20.0], "route_slope_weight": [0.0, 30.0],
	"route_occupancy_penalty": [0.0, 30.0], "route_corridor_penalty": [0.0, 30.0],
	"route_corridor_ratio": [0.15, 0.7], "route_overshoot_penalty": [0.0, 40.0],
	"route_margin": [0.4, 1.2], "route_height_tol": [0.05, 0.4],
	"route_smooth_iterations": [0, 4],
}

## Which generation step each tunable parameter belongs to (the step at which you
## tune + judge it). Keys match map_viewer's STEP_INFO names. Used so saving,
## range-finding, and randomization can be isolated to a single step -- tuning a
## later step never touches an earlier step's values. Every tunable param must
## appear here exactly once (see coverage_gaps()).
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
	"Peaks Ridges": [
		"ridge_frequency", "ridge_offset", "peaks_octaves", "peaks_gain",
		"peaks_lacunarity", "peaks_warp_amp", "peaks_warp_freq", "peak_uplift",
		"highland_range", "peak_height_cap", "mountain_threshold",
	],
	"Peaks Detail": [
		"detail_frequency", "peak_detail_strength", "peak_detail_min_elevation",
		"peak_detail_falloff", "billow_frequency", "peak_billow_strength",
		"lowland_flatten", "boundary_radius", "boundary_falloff",
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
		"humid_frequency",
	],
	"Graph": [
		"spec_cities", "spec_nodes_between_cities", "spec_outgoing", "graph_min_width",
		"graph_max_width", "graph_jitter", "graph_landmass_min_frac", "graph_lane_tol",
		"graph_branch_local_mul", "graph_pole_sep", "coast_radius_ratio",
		"graph_sample_spacing_ratio", "route_downscale", "route_node_clearance",
		"route_node_penalty", "route_border_penalty", "route_backtrack_penalty",
		"route_land_penalty", "route_water_penalty", "route_slope_weight",
		"route_occupancy_penalty", "route_corridor_penalty", "route_corridor_ratio",
		"route_overshoot_penalty", "route_margin", "route_height_tol",
		"route_smooth_iterations",
	],
}

# =============================================================================
# PARAM TABLES
# =============================================================================
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

## name -> [lo, hi, is_int] for every randomizable WorldSettings parameter (range hint
## if present, else DEFAULT_RANGES). Params with neither are omitted.
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
		var is_int: bool = p.type == TYPE_INT
		if int(p.hint) == PROPERTY_HINT_RANGE and String(p.hint_string) != "":
			var nums := _parse_range_hint(String(p.hint_string))
			if nums.size() >= 2:
				out[pname] = [nums[0], nums[1], is_int]
				continue
		if DEFAULT_RANGES.has(pname):
			var r: Array = DEFAULT_RANGES[pname]
			out[pname] = [float(r[0]), float(r[1]), is_int]
	return out

# "lo,hi" or "lo,hi,step" or "lo,hi,step,or_greater" -> first two numeric tokens.
static func _parse_range_hint(hint: String) -> Array:
	var nums := []
	for tok in hint.split(","):
		var t := tok.strip_edges()
		if t.is_valid_float():
			nums.append(float(t))
	return nums

## name -> is_int for EVERY tunable WorldSettings param (all editor int/float minus
## EXCLUDE), regardless of whether it has a predefined range. The canonical "save
## everything" set, so no finetuned value is silently dropped from a preset.
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

# =============================================================================
# SAMPLER (density-model inverse-CDF draw)
# =============================================================================
## Draw a value from one density entry by inverse-CDF sampling of a CONTINUOUS
## piecewise-linear curve through the bin-centre weights w[i] = max(base + good - bad, 0).
## Picks land anywhere under the line (interpolated between bins), weighted by the
## local area. `base` is a uniform exploration floor: with no good yet (first epoch),
## the curve is base minus the accumulated bad, so you still explore everything
## except known-bad pockets. If the whole curve is flat-zero, fall back to uniform.
static func sample_entry(entry: Dictionary, rng: RandomNumberGenerator, base: float) -> float:
	var lo: float = float(entry.get("lo", 0.0))
	var hi: float = float(entry.get("hi", 1.0))
	var good: Array = entry.get("good", [])
	var bad: Array = entry.get("bad", [])
	var n := good.size()
	if n == 0:
		return rng.randf_range(lo, hi)
	var bstep := (hi - lo) / float(n)
	var w := []
	for i in n:
		var b: float = float(bad[i]) if i < bad.size() else 0.0
		w.append(maxf(base + float(good[i]) - b, 0.0))
	# Trapezoid area of each segment between adjacent bin centres.
	var areas := []
	var total := 0.0
	for i in range(n - 1):
		var a: float = 0.5 * (w[i] + w[i + 1]) * bstep
		areas.append(a)
		total += a
	if total <= 0.0:
		return rng.randf_range(lo, hi)
	var u := rng.randf() * total
	var seg := n - 2
	for i in range(n - 1):
		if u <= areas[i]:
			seg = i
			break
		u -= areas[i]
	var t := _trapezoid_t(w[seg], w[seg + 1], bstep, u)
	var x0 := lo + (float(seg) + 0.5) * bstep
	return clampf(x0 + t * bstep, lo, hi)

# Solve for t in [0,1] where the partial trapezoid area w0*L*t + 0.5*(w1-w0)*L*t^2 = u.
# (Inverse CDF within one linear segment; the +sqrt root is correct for both slopes.)
static func _trapezoid_t(w0: float, w1: float, L: float, u: float) -> float:
	var lin := w1 - w0
	if absf(lin) < 1e-9:
		var denom := w0 * L
		return clampf(u / denom, 0.0, 1.0) if denom > 1e-12 else 0.5
	var a := 0.5 * lin * L
	var b := w0 * L
	var disc := maxf(b * b + 4.0 * a * u, 0.0)
	return clampf((-b + sqrt(disc)) / (2.0 * a), 0.0, 1.0)

# =============================================================================
# BUNDLE (addon-shipped merged density model)
# =============================================================================
## Read the merged density model. Returns the inner {step: {param: entry}} map (empty
## if the bundle is missing or malformed). Consumers (WorldMap2D) sample from this only.
static func load_bundle() -> Dictionary:
	if not FileAccess.file_exists(BUNDLE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BUNDLE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var steps = parsed.get("steps", {})
	return steps if typeof(steps) == TYPE_DICTIONARY else {}

## Dev-side: build ranges_bundle.json from the per-step density models. `loader` is a
## Callable(step: String) -> Dictionary returning that step's ranges.json contents (i.e.
## PresetIO.load_ranges). Only params still in STEP_PARAMS survive (deleted climate/city
## params in old presets are dropped); values are rounded compact. Returns the bundle.
static func export_bundle(loader: Callable) -> Dictionary:
	var steps := {}
	for step in STEP_PARAMS:
		var raw = loader.call(step)
		if typeof(raw) != TYPE_DICTIONARY or raw.is_empty():
			continue
		var whitelist := {}
		for p in step_params(step):
			whitelist[p] = true
		var kept := {}
		for p in raw:
			if whitelist.has(p) and raw[p] is Dictionary:
				kept[p] = _compact_entry(raw[p])
		if not kept.is_empty():
			steps[step] = kept
	var bundle := {"version": 1, "steps": steps}
	var f := FileAccess.open(BUNDLE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(bundle, "  "))
		f.close()
	return bundle

# Keep only the fields the sampler needs, rounding domains to 4 sig digits and
# histograms to ints (drops good_n/bad_n bookkeeping). Shrinks the shipped file.
static func _compact_entry(e: Dictionary) -> Dictionary:
	return {
		"lo": _round_sig(float(e.get("lo", 0.0)), 4),
		"hi": _round_sig(float(e.get("hi", 1.0)), 4),
		"bins": int(e.get("bins", 12)),
		"is_int": bool(e.get("is_int", false)),
		"good": _to_int_bins(e.get("good", [])),
		"bad": _to_int_bins(e.get("bad", [])),
	}

# Round to `sig` significant digits (0 stays 0). Keeps the JSON compact + readable.
static func _round_sig(x: float, sig: int) -> float:
	if x == 0.0:
		return 0.0
	var d := ceili(log(absf(x)) / log(10.0))
	var power := pow(10.0, sig - d)
	return round(x * power) / power

# Histogram counts are integer-valued; store them as ints to halve the digits.
static func _to_int_bins(arr) -> Array:
	var out := []
	if arr is Array:
		for v in arr:
			out.append(int(round(float(v))))
	return out

# =============================================================================
# RANDOMIZE (bundle-driven; used by WorldMap2D)
# =============================================================================
## Roll one step's params into `settings` from the bundle's density model where present,
## else from the predefined default range. Params with neither are left untouched.
static func randomize_step(settings: WorldSettings, step: String, rng: RandomNumberGenerator, base: float, bundle: Dictionary) -> void:
	var model: Dictionary = bundle.get(step, {})
	var defaults := param_ranges()
	for pname in step_params(step):
		if model.has(pname) and model[pname] is Dictionary:
			var e: Dictionary = model[pname]
			var v := sample_entry(e, rng, base)
			settings.set(pname, int(round(v)) if bool(e.get("is_int", false)) else v)
		elif defaults.has(pname):
			var r: Array = defaults[pname]
			var v := rng.randf_range(r[0], r[1])
			settings.set(pname, int(round(v)) if r[2] else v)

## Full random world: reroll the seed and sample every step's params from the bundle.
## Loads the bundle itself when one isn't supplied.
static func randomize_all(settings: WorldSettings, rng: RandomNumberGenerator, base: float, bundle: Dictionary = {}) -> void:
	if bundle.is_empty():
		bundle = load_bundle()
	settings.main_seed = rng.randi() % 1000000
	for step in STEP_PARAMS:
		randomize_step(settings, step, rng, base, bundle)
