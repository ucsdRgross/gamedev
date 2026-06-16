extends Node

## Graph rule fuzz-test suite (run this scene with F6).
##
## For each run i in 1..run_count it generates a world ONCE through the
## Civilizations step using main_seed = i (so reruns reproduce the same maps),
## caches that base map, then builds + validates a graph for every preset in
## graph_presets on top of the identical base. Rule failures are printed with
## the failing seed/preset/rule and DO NOT stop the run. At the end, per preset,
## it prints the combined "average generated graph": mean/min/max of every A5
## statistic across runs, plus histograms of the variable-length path shapes.
##
## base_settings supplies the map (terrain/climate/civ) parameters; each preset
## overrides only the graph parameters listed in GRAPH_FIELDS.

@export var run_count: int = 20
@export var base_settings: WorldSettings
@export var graph_presets: Array[WorldSettings] = []

# Graph-only parameters a preset is allowed to override (map/terrain come from
# base_settings). max_landmasses is intentionally excluded: it shapes the base
# map (Step6 labeling), not the graph rebuild.
const GRAPH_FIELDS := [
	"layer_count", "min_path_dist", "max_path_search_dist", "min_outgoing",
	"max_outgoing", "min_nodes_between_cities",
	"max_nodes_between_cities", "min_cities_visited", "max_cities_visited",
	"city_bottleneck_strength",
	"min_biomes_per_path", "max_biomes_per_path", "max_cross_ocean_per_band",
	"max_water_crossing_dist", "min_outgoing_after_trim", "edge_trim_chance",
	"start_end_island_penalty", "start_end_min_connections", "mountain_pass_bias",
	"graph_anti_straight", "path_ortho_length_bonus", "graph_zigzag_penalty",
	"min_graph_width", "graph_build_passes",
	"failsafe_max_injected_nodes", "max_paths_enumerated",
]

const STAT_GROUPS := ["path_dist", "biomes", "steps_between_cities", "steps_in_biome", "graph_width", "biome_width", "city_length"]
const STAT_FIELDS := ["longest", "shortest", "median", "average"]

var _gen: WorldGenerator

func _ready() -> void:
	if base_settings == null:
		base_settings = WorldSettings.new()
	if graph_presets.is_empty():
		graph_presets = [base_settings]  # at least test the base graph params
	await _run()

func _run() -> void:
	# One generator for the whole suite; viewports are sized from base_settings
	# (map size is constant across the suite).
	_gen = WorldGenerator.new()
	_gen.settings = base_settings
	add_child(_gen)
	await get_tree().process_frame

	# Per-preset accumulators and per-rule failure tallies.
	var acc: Array = []
	var rule_fail: Array = []
	var preset_params: Array = []
	for p in range(graph_presets.size()):
		acc.append(_new_accumulator())
		rule_fail.append({})
		preset_params.append("")

	print("=== Graph test suite: %d runs x %d presets ===" % [run_count, graph_presets.size()])
	for i in range(1, run_count + 1):
		var bs := base_settings.duplicate(true) as WorldSettings
		bs.main_seed = i
		_gen.settings = bs
		await _gen.generate_base_through_civilizations()
		var base := _gen.cache_base_state()

		for p in range(graph_presets.size()):
			_gen.restore_base_state(base)
			var ps := _merge_preset(bs, graph_presets[p])
			preset_params[p] = GraphRules.format_graph_params(ps)
			_gen.settings = ps
			var res := GraphBuilder.new().build(_gen, ps)
			var violations := GraphRules.validate(_gen, res["graph"], res["start"], res["end"], ps, res["meta"])
			var stats := GraphRules.collect_stats(res["graph"], res["start"], res["end"], ps, res["meta"])
			for vio in violations:
				rule_fail[p][vio["rule"]] = rule_fail[p].get(vio["rule"], 0) + 1
			# Only print failing seeds in full; passing seeds get a one-word line.
			if violations.is_empty():
				print("s%d passed" % i)
			else:
				acc[p]["fail_runs"] += 1
				print("s%d FAIL %s | %s | %s" % [i, _stat_shorthand(stats), _node_shorthand(), _summarize(violations)])
			_accumulate(acc[p], stats)

	# Final per-preset report.
	for p in range(graph_presets.size()):
		_report(_preset_name(graph_presets[p], p), acc[p], rule_fail[p], preset_params[p])
	print("=== Graph test suite complete ===")
	get_tree().quit()

# ---------------------------------------------------------------------------
# Preset merge + naming
# ---------------------------------------------------------------------------
func _merge_preset(base: WorldSettings, preset: WorldSettings) -> WorldSettings:
	var s := base.duplicate(true) as WorldSettings
	for f in GRAPH_FIELDS:
		s.set(f, preset.get(f))
	return s

func _preset_name(preset: WorldSettings, idx: int) -> String:
	if preset.resource_name != "":
		return preset.resource_name
	if preset.resource_path != "":
		return preset.resource_path.get_file()
	return "preset_%d" % idx

const RULE_SHORT := {
	"outgoing_degree": "odeg", "water_node": "wat", "same_landmass_ocean": "slo",
	"graph_width": "gw", "biomes_per_path": "bpp", "nodes_between_cities": "nbc",
	"cities_visited": "cv", "dead_end": "de", "cycle": "cyc", "no_path": "nopath",
	"path_too_long": "ptl", "water_edge_too_long": "wetl", "water_edge_hits_land": "wehl",
	"water_edge_not_coastal_city": "wnc", "band_cross_ocean": "bxo",
	"self_edge": "self", "duplicate_edge": "dup",
}

func _summarize(violations: Array) -> String:
	# Compact "code xN {first sample detail}" list, deduped by rule.
	var by_rule := {}
	var sample := {}
	for v in violations:
		var r: String = v["rule"]
		by_rule[r] = by_rule.get(r, 0) + 1
		if not sample.has(r):
			sample[r] = v["detail"]
	var parts: Array = []
	for r in by_rule.keys():
		parts.append("%s x%d {%s}" % [RULE_SHORT.get(r, r), by_rule[r], sample[r]])
	return ", ".join(parts)

## Extreme-shorthand per-run stats: path count + medians of each metric.
func _stat_shorthand(stats: Dictionary) -> String:
	if stats.get("path_count", 0) == 0:
		return "no-paths"
	return "paths=%d Plen=%d Bio=%d SBC=%d SIB=%d GW=%d BW=%d" % [
		stats["path_count"], int(stats["path_dist"]["median"]), int(stats["biomes"]["median"]),
		int(stats["steps_between_cities"]["median"]), int(stats["steps_in_biome"]["median"]),
		int(stats["graph_width"]["median"]), int(stats["biome_width"]["median"])]

## Node counts produced by Step6 for this run (cities/travel).
func _node_shorthand() -> String:
	return "C=%d T=%d" % [_gen.city_nodes.size(), _gen.travel_nodes.size()]

# ---------------------------------------------------------------------------
# Accumulation + histograms
# ---------------------------------------------------------------------------
func _new_accumulator() -> Dictionary:
	var a := {"runs": 0, "fail_runs": 0, "scalars": {},
		"hist_cities_per_path": {}, "hist_nodes_between_cities": {},
		"hist_biomes_per_path": {}, "hist_nodes_per_biome": {},
		"hist_graph_width": {}, "hist_biome_width": {}}
	for g in STAT_GROUPS:
		for f in STAT_FIELDS:
			a["scalars"]["%s.%s" % [g, f]] = []
	return a

func _accumulate(a: Dictionary, stats: Dictionary) -> void:
	a["runs"] += 1
	if stats.get("path_count", 0) == 0:
		return
	for g in STAT_GROUPS:
		var blk: Dictionary = stats[g]
		for f in STAT_FIELDS:
			a["scalars"]["%s.%s" % [g, f]].append(blk[f])
	_bin(a["hist_cities_per_path"], stats.get("raw_cities_per_path", []))
	_bin(a["hist_nodes_between_cities"], stats.get("raw_nodes_between_cities", []))
	_bin(a["hist_biomes_per_path"], stats.get("raw_biomes_per_path", []))
	_bin(a["hist_nodes_per_biome"], stats.get("raw_nodes_per_biome", []))
	_bin(a["hist_graph_width"], stats.get("raw_graph_width", []))
	_bin(a["hist_biome_width"], stats.get("raw_biome_width", []))

func _bin(hist: Dictionary, values: Array) -> void:
	for v in values:
		hist[v] = hist.get(v, 0) + 1

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
func _report(name: String, a: Dictionary, rule_fail: Dictionary, params: String) -> void:
	print("\n--- Preset '%s' over %d runs (%d with rule failures) ---" % [name, a["runs"], a["fail_runs"]])
	print("  params (seeds vary 1..N): ", params)
	if not rule_fail.is_empty():
		var parts: Array = []
		for r in rule_fail.keys():
			parts.append("%s:%d" % [r, rule_fail[r]])
		print("  rule failures: ", ", ".join(parts))
	print("  Combined 'average generated graph' (mean [min..max] across runs):")
	for g in STAT_GROUPS:
		var line := "    %-20s" % g
		for f in STAT_FIELDS:
			var vals: Array = a["scalars"]["%s.%s" % [g, f]]
			line += "  %s=%s" % [f, _mm(vals)]
		print(line)
	print("  Histograms (value -> occurrences across all runs):")
	print("    cities per path     : ", _fmt_hist(a["hist_cities_per_path"]))
	print("    nodes between cities: ", _fmt_hist(a["hist_nodes_between_cities"]))
	print("    biomes per path     : ", _fmt_hist(a["hist_biomes_per_path"]))
	print("    nodes per biome run : ", _fmt_hist(a["hist_nodes_per_biome"]))
	print("    graph width (cities): ", _fmt_hist(a["hist_graph_width"]))
	print("    biome width (nodes) : ", _fmt_hist(a["hist_biome_width"]))

func _mm(vals: Array) -> String:
	if vals.is_empty():
		return "-"
	var total := 0.0; var lo := INF; var hi := -INF
	for v in vals:
		total += float(v); lo = minf(lo, float(v)); hi = maxf(hi, float(v))
	return "%.1f[%.1f..%.1f]" % [total / float(vals.size()), lo, hi]

func _fmt_hist(hist: Dictionary) -> String:
	if hist.is_empty():
		return "{}"
	var keys: Array = hist.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s:%d" % [k, hist[k]])
	return "{" + ", ".join(parts) + "}"
