extends Node

## Multithreaded graph-parameter auto-tuning harness (run this scene with F6).
##
## For each selected size tier it scatter-samples every enabled graph-shaping
## parameter, scores each generated graph with GraphMetrics (coverage + hollow
## subdivision + biome variety - violations), and iteratively narrows each
## parameter's [min..max] range toward the best values (coordinate descent +
## range narrowing). Results are written as plain text under res://tuning/.
##
## Base maps (GPU pipeline) are generated on the MAIN thread and cached; the V
## graph variants for a graph-scope param are then built+scored across
## WorkerThreadPool worker threads (GraphBuilder.build(..., write_to_gen=false)
## is side-effect-free, so this is safe). Base-scope params regenerate the base
## and are swept serially.
##
## Debug-friendly: every knob below is a scene export, so a bring-up run can be
## tiny (tiers_to_run=["medium"], V=2, S=1, max_rounds=1).

# --- Scene exports (debug knobs) -------------------------------------------
@export var tiers_to_run: Array[String] = []   # empty = all map-size tiers
@export var city_targets: Array[int] = [5, 10, 15, 20]  # per-run city goals tested on EVERY tier
@export var V: int = 20                         # values sampled per param per round
@export var S: int = 20                         # seeds each value is scored over
@export var max_rounds: int = 6
@export var enable_phase_b: bool = true
@export var phase_b_configs: int = 40
@export var rng_seed: int = 1
# Reward weights (mirror GraphMetrics.RewardConfig)
@export var w_coverage: float = 1.0
@export var w_hollow: float = 1.0
@export_enum("uniform", "target") var hollow_mode: String = "uniform"
@export var ref_cells_per_hollow: float = 40.0  # uniform-mode scale factor (not a size target)
@export var hollow_target_cells: float = 40.0   # target-mode only
@export var hollow_spread: float = 30.0          # target-mode only
@export var w_biome: float = 0.0  # disabled until biome node-selection is a tunable lever
@export var w_violation: float = 0.05
@export var w_spread: float = 0.25
@export var grid_px: float = 8.0

const OUT_DIR := "res://tuning"

# --- Tiers ------------------------------------------------------------------
# Each tier sets the (fixed) map size + travel-node budget + the gameplay goal
# `target_cities` = how many cities a SINGLE start->end run must pass through.
# layer_count and the cities_visited window are NOT listed here: they are DERIVED
# from target_cities and the city spacing (see _apply_structure), because a path
# can only visit one city per `gap` layers, so the path length is dictated by the
# goal, not free to choose.
const TIERS := {
	"mini":    {"px": 256},
	"small":   {"px": 384},
	"medium":  {"px": 512},
	"large":   {"px": 768},
	"massive": {"px": 1024},
}
const TIER_ORDER := ["mini", "small", "medium", "large", "massive"]

# --- Parameter registry -----------------------------------------------------
# One row per tunable. scope "graph" = threaded (reuses cached base); "base" =
# serial (regenerates the GPU base). Add/remove a tunable by editing this array.
# type: "i" int, "f" float.
# DERIVED per-candidate in _apply_structure (NOT searched): layer_count,
# min/max_cities_visited (= target_cities), max_travel_count (= travel_per_city x
# target), max_city_count (= (target+2) x min_graph_width). Min/max pairs that
# bound one quantity are collapsed to a single 'target' param here (outgoing,
# nodes_between_cities) and expanded to min=max in _apply_structure.
const PARAMS := [
	{"name": "outgoing", "type": "i", "min": 1, "max": 6, "step": 1, "scope": "graph"},
	{"name": "min_outgoing_after_trim", "type": "i", "min": 1, "max": 3, "step": 1, "scope": "graph"},
	{"name": "edge_trim_chance", "type": "f", "min": 0.0, "max": 0.9, "step": 0.1, "scope": "graph"},
	{"name": "nodes_between_cities", "type": "i", "min": 0, "max": 8, "step": 1, "scope": "graph"},
	{"name": "city_bottleneck_strength", "type": "f", "min": 0.0, "max": 1.0, "step": 0.1, "scope": "graph"},
	{"name": "min_graph_width", "type": "i", "min": 1, "max": 6, "step": 1, "scope": "base"},
	{"name": "max_landmasses", "type": "i", "min": 1, "max": 8, "step": 1, "scope": "base"},
	{"name": "max_cross_ocean_per_band", "type": "i", "min": 0, "max": 4, "step": 1, "scope": "graph"},
	{"name": "water_crossing_ratio", "type": "f", "min": 0.05, "max": 0.45, "step": 0.025, "scope": "graph"},
	{"name": "start_end_island_penalty", "type": "f", "min": 0, "max": 10000, "step": 1000, "scope": "graph"},
	{"name": "start_end_min_connections", "type": "i", "min": 0, "max": 6, "step": 1, "scope": "graph"},
	{"name": "mountain_pass_bias", "type": "f", "min": 0.0, "max": 5.0, "step": 0.5, "scope": "graph"},
	{"name": "graph_anti_straight", "type": "f", "min": 0.0, "max": 3.0, "step": 0.25, "scope": "graph"},
	{"name": "graph_zigzag_penalty", "type": "f", "min": 0, "max": 200, "step": 20, "scope": "graph"},
	{"name": "failsafe_max_injected_nodes", "type": "i", "min": 0, "max": 80, "step": 10, "scope": "graph"},
	{"name": "graph_build_passes", "type": "i", "min": 1, "max": 4, "step": 1, "scope": "graph"},
	{"name": "city_dist_ratio", "type": "f", "min": 0.01, "max": 0.09, "step": 0.005, "scope": "base"},
	{"name": "travel_dist_ratio", "type": "f", "min": 0.005, "max": 0.045, "step": 0.0025, "scope": "base"},
	{"name": "travel_per_city", "type": "f", "min": 5, "max": 120, "step": 5, "scope": "base"},
	# coast_radius_ratio + path_curve_*_ratio are cosmetic -> not searched (fixed defaults).
]

# "Virtual" search params -- not WorldSettings fields. They are stashed as resource
# metadata on the candidate and expanded into real fields by _apply_structure
# (outgoing -> min/max_outgoing, nodes_between_cities -> min/max_nbc,
# travel_per_city -> max_travel_count). Defaults seed the baseline.
const VIRTUAL := {"outgoing": 3, "nodes_between_cities": 2, "travel_per_city": 30.0}

var _gen: WorldGenerator
var _rng := RandomNumberGenerator.new()
var _target_cities := 0  # current tier's per-run city goal (drives _apply_structure)
# Threaded-eval scratch (set on main thread before fanning out, read by workers):
var _task_settings: Array = []
var _task_out: Array = []
var _task_base: Dictionary = {}
var _cfg: GraphMetrics.RewardConfig

# ---------------------------------------------------------------------------
func _ready() -> void:
	_rng.seed = rng_seed
	_cfg = _make_cfg()
	_gen = WorldGenerator.new()
	add_child(_gen)
	await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# .gdignore stops the editor importing our plain-text CSVs as resources
	# (otherwise it spams .import/.translation sidecars next to them).
	if not FileAccess.file_exists("%s/.gdignore" % OUT_DIR):
		FileAccess.open("%s/.gdignore" % OUT_DIR, FileAccess.WRITE).close()
	# Fresh best_ranges.txt per run (tiers append into it during this run).
	FileAccess.open("%s/best_ranges.txt" % OUT_DIR, FileAccess.WRITE).close()
	_write_how_to_read()

	var run_start := Time.get_ticks_msec()
	var tiers := tiers_to_run if not tiers_to_run.is_empty() else TIER_ORDER
	# Matrix: every city target on every map-size tier.
	for t in tiers:
		if not TIERS.has(t):
			push_warning("Unknown tier '%s' -- skipping" % t)
			continue
		for target in city_targets:
			print("\n========== TIER: %s | target_cities: %d ==========" % [t, target])
			await _run_combo(t, int(target))
	var total_s := float(Time.get_ticks_msec() - run_start) / 1000.0
	print("\n=== Param search complete in %s (%.1f s) ===" % [_fmt_duration(total_s), total_s])
	get_tree().quit()

## "1h 23m 4s" style for the wall-clock summary.
func _fmt_duration(s: float) -> String:
	var t := int(s)
	var hh := t / 3600
	var mm := (t % 3600) / 60
	var ss := t % 60
	if hh > 0:
		return "%dh %dm %ds" % [hh, mm, ss]
	if mm > 0:
		return "%dm %ds" % [mm, ss]
	return "%ds" % ss

func _make_cfg() -> GraphMetrics.RewardConfig:
	var c := GraphMetrics.RewardConfig.new()
	c.w_coverage = w_coverage
	c.w_hollow = w_hollow
	c.hollow_mode = hollow_mode
	c.ref_cells_per_hollow = ref_cells_per_hollow
	c.hollow_target_cells = hollow_target_cells
	c.hollow_spread = hollow_spread
	c.w_biome = w_biome
	c.w_violation = w_violation
	c.w_spread = w_spread
	c.grid_px = grid_px
	return c

# ---------------------------------------------------------------------------
# Per-tier coordinate-descent search.
# ---------------------------------------------------------------------------
func _run_combo(tier: String, target: int) -> void:
	var tier_start := Time.get_ticks_msec()
	var combo := "%s_t%d" % [tier, target]
	var td: Dictionary = TIERS[tier]
	_target_cities = target
	var baseline := _tier_baseline(td)
	# Mutable working ranges, seeded from the registry hard bounds.
	var ranges := {}
	for p in PARAMS:
		ranges[p["name"]] = [float(p["min"]), float(p["max"])]

	var csv_path := "%s/%s_samples.csv" % [OUT_DIR, combo]
	_csv_header(csv_path)

	for round_i in range(max_rounds):
		print("-- round %d/%d --" % [round_i + 1, max_rounds])
		# Cache S bases once per round using the current baseline (graph-scope
		# sweeps reuse these; base-scope sweeps regenerate themselves).
		var bases := await _cache_seed_bases(baseline)
		var any_moved := false

		for p in PARAMS:
			if not p.get("enabled", true):
				continue
			var moved := await _sweep_param(p, baseline, ranges, bases, round_i, csv_path)
			any_moved = any_moved or moved

		if not any_moved:
			print("   converged (no range moved > 5%%) after round %d" % (round_i + 1))
			break

	if enable_phase_b:
		await _phase_b(baseline, ranges, csv_path)

	_write_best(combo, baseline, ranges)
	await _save_best_image(combo, baseline)
	var tier_s := float(Time.get_ticks_msec() - tier_start) / 1000.0
	print("   combo '%s' took %s (%.1f s)" % [combo, _fmt_duration(tier_s), tier_s])

# Worker-thread atom: build+score _task_settings[i] against the shared restored
# base (_task_base). Reads only; build is side-effect-free (write_to_gen=false).
func _eval_task(i: int) -> void:
	var ps: WorldSettings = _task_settings[i]
	var res := GraphBuilder.new().build(_gen, ps, false)
	var vio := GraphRules.validate(_gen, res["graph"], res["start"], res["end"], ps, res["meta"])
	_task_out[i] = GraphMetrics.evaluate(res, _task_base["height"], _task_base["biome"],
		ps.map_width, ps.map_height, ps.ocean_threshold, _cfg, _distinct_violations(vio))

func _collect(sum_r: Array, min_r: Array, cov: Array, hol: Array, keff: Array, bio: Array, spr: Array, vio: Array) -> void:
	for i in range(_task_out.size()):
		var r: Dictionary = _task_out[i]
		sum_r[i] += r["reward"]; min_r[i] = minf(min_r[i], r["reward"])
		cov[i] += r["coverage"]; hol[i] += r["hollow"]; keff[i] += r["keff"]
		bio[i] += r["biome"]; spr[i] += r["spread"]; vio[i] += float(r["violations"])

# ---------------------------------------------------------------------------
func _tier_baseline(td: Dictionary) -> WorldSettings:
	var s := WorldSettings.new()
	s.map_width = td["px"]
	s.map_height = td["px"]
	for k in VIRTUAL:
		s.set_meta(k, VIRTUAL[k])  # seed virtual-param defaults
	_apply_structure(s)
	return s

# --- Virtual param routing (outgoing / nodes_between_cities / travel_per_city are
# stashed as metadata, everything else is a real WorldSettings field) ---------
func _set_param(s: WorldSettings, name: String, value) -> void:
	if VIRTUAL.has(name):
		s.set_meta(name, value)
	else:
		s.set(name, value)

func _get_param(s: WorldSettings, name: String):
	if VIRTUAL.has(name):
		return s.get_meta(name, VIRTUAL[name])
	return s.get(name)

## Expand the virtual params into real fields and derive everything dictated by
## the per-run city goal. A forward path visits one city per `gap` layers, so to
## require `target_cities` cities on a run: layer_count = (target_cities+1)*gap and
## the cities_visited window is pinned to the goal. Travel/city counts scale off
## the goal too. Call after every candidate WorldSettings is set up.
func _apply_structure(s: WorldSettings) -> void:
	# Collapse the single 'target' params into the engine's min/max fields.
	var outgoing := int(_get_param(s, "outgoing"))
	s.min_outgoing = outgoing
	s.max_outgoing = outgoing
	s.min_outgoing_after_trim = mini(s.min_outgoing_after_trim, outgoing)
	var nbc := int(_get_param(s, "nodes_between_cities"))
	s.min_nodes_between_cities = nbc
	s.max_nodes_between_cities = nbc
	if _target_cities <= 0:
		return
	var gap := maxi(2, nbc + 1)
	s.layer_count = (_target_cities + 1) * gap
	s.min_cities_visited = _target_cities
	s.max_cities_visited = _target_cities
	# Travel nodes as a ratio of the per-run city goal; total cities from branching.
	var ratio := float(_get_param(s, "travel_per_city"))
	s.max_travel_count = maxi(1, int(round(ratio * float(_target_cities))))
	s.max_city_count = maxi(s.min_cities_visited + 1, (_target_cities + 2) * maxi(1, s.min_graph_width))

# Generate + cache S base maps for the seeds 1..S using `baseline` base params.
func _cache_seed_bases(baseline: WorldSettings) -> Array:
	var bases: Array = []
	for s in range(1, S + 1):
		var bs := baseline.duplicate(true) as WorldSettings
		bs.main_seed = s
		_gen.settings = bs
		await _gen.generate_base_through_civilizations()
		bases.append(_gen.cache_base_state())
	return bases

# ---------------------------------------------------------------------------
# Sweep one parameter: sample V values, score each over S seeds, narrow range,
# update baseline best. Returns true if the range moved meaningfully.
# ---------------------------------------------------------------------------
func _sweep_param(p: Dictionary, baseline: WorldSettings, ranges: Dictionary,
		bases: Array, round_i: int, csv_path: String) -> bool:
	var pname: String = p["name"]
	var lo: float = ranges[pname][0]
	var hi: float = ranges[pname][1]
	var values := _sample_values(lo, hi, p)
	var nv := values.size()
	var is_graph :bool= p["scope"] == "graph"

	# Per-value reward accumulators across seeds.
	var sum_r := []; sum_r.resize(nv); sum_r.fill(0.0)
	var min_r := []; min_r.resize(nv); min_r.fill(INF)
	var agg_cov := []; agg_cov.resize(nv); agg_cov.fill(0.0)
	var agg_hol := []; agg_hol.resize(nv); agg_hol.fill(0.0)
	var agg_keff := []; agg_keff.resize(nv); agg_keff.fill(0.0)
	var agg_bio := []; agg_bio.resize(nv); agg_bio.fill(0.0)
	var agg_spr := []; agg_spr.resize(nv); agg_spr.fill(0.0)
	var agg_vio := []; agg_vio.resize(nv); agg_vio.fill(0.0)
	var seed_count := 0

	if is_graph:
		# THREADED: for each cached base (seed), build+score all V values in
		# parallel. Every task reads the same restored base buffers (build with
		# write_to_gen=false is side-effect-free) so concurrent reads are safe.
		_task_settings.clear()
		for v in values:
			var ps := baseline.duplicate(true) as WorldSettings
			_set_param(ps, pname, _typed(v, p))
			_apply_structure(ps)
			_task_settings.append(ps)
		for base in bases:
			_gen.restore_base_state(base)          # main thread, once per seed
			_task_base = base
			_task_out = []; _task_out.resize(nv)
			var gid := WorkerThreadPool.add_group_task(_eval_task, nv, -1, false, pname)
			WorkerThreadPool.wait_for_group_task_completion(gid)
			_collect(sum_r, min_r, agg_cov, agg_hol, agg_keff, agg_bio, agg_spr, agg_vio)
			seed_count += 1
	else:
		# Base-scope: regenerate the base per (value, seed); serial (GPU). Each
		# value reuses the same V settings list shape but with the swept value.
		for vi in range(nv):
			var ps := baseline.duplicate(true) as WorldSettings
			_set_param(ps, pname, _typed(values[vi], p))
			_apply_structure(ps)
			for si in range(S):
				ps.main_seed = si + 1
				_gen.settings = ps
				await _gen.generate_base_through_civilizations()
				var base := _gen.cache_base_state()
				var r := _eval_on_base(ps, base)
				sum_r[vi] += r["reward"]; min_r[vi] = minf(min_r[vi], r["reward"])
				agg_cov[vi] += r["coverage"]; agg_hol[vi] += r["hollow"]; agg_keff[vi] += r["keff"]
				agg_bio[vi] += r["biome"]; agg_spr[vi] += r["spread"]; agg_vio[vi] += float(r["violations"])
		seed_count = S

	var ns := float(maxi(1, seed_count))
	var means: Array = []
	var rows: Array = []
	for vi in range(nv):
		var mean :float= sum_r[vi] / ns
		means.append(mean)
		rows.append("%d,%s,%s,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [
			round_i + 1, pname, str(_typed(values[vi], p)), mean, min_r[vi],
			agg_cov[vi] / ns, agg_hol[vi] / ns, agg_keff[vi] / ns,
			agg_bio[vi] / ns, agg_spr[vi] / ns, agg_vio[vi] / ns])

	_csv_append(csv_path, rows)

	# Rank by mean, keep top ~30% span (>=2 values), pad 10%, set baseline best.
	var order := range(values.size())
	order.sort_custom(func(a, b): return means[a] > means[b])
	var keep := maxi(2, int(ceil(0.3 * values.size())))
	var top := order.slice(0, keep)
	var new_lo := INF
	var new_hi := -INF
	for idx in top:
		new_lo = minf(new_lo, float(values[idx]))
		new_hi = maxf(new_hi, float(values[idx]))
	var pad := (new_hi - new_lo) * 0.1
	new_lo = clampf(new_lo - pad, float(p["min"]), float(p["max"]))
	new_hi = clampf(new_hi + pad, float(p["min"]), float(p["max"]))
	if new_hi <= new_lo:
		new_hi = minf(float(p["max"]), new_lo + float(p["step"]))

	_set_param(baseline, pname, _typed(values[order[0]], p))
	_apply_structure(baseline)
	var old_w := hi - lo
	var new_w := new_hi - new_lo
	var moved := old_w <= 0.0 or absf(new_w - old_w) / maxf(old_w, 1e-6) > 0.05
	ranges[pname] = [new_lo, new_hi]
	print("   %-26s best=%s mean=%.3f range=[%.3f..%.3f]" % [pname, str(_typed(values[order[0]], p)), means[order[0]], new_lo, new_hi])
	return moved

# ---------------------------------------------------------------------------
# Optional Phase B: joint random search within the narrowed ranges.
# ---------------------------------------------------------------------------
func _phase_b(baseline: WorldSettings, ranges: Dictionary, csv_path: String) -> void:
	print("-- phase B: %d joint random configs --" % phase_b_configs)
	var bases := await _cache_seed_bases(baseline)
	var best_reward := -INF
	var best_cfg: WorldSettings = null
	var rows: Array = []
	for n in range(phase_b_configs):
		var ps := baseline.duplicate(true) as WorldSettings
		for p in PARAMS:
			if p["scope"] != "graph":
				continue  # base-scope held at baseline (regen too costly per config)
			var r: Array = ranges[p["name"]]
			_set_param(ps, p["name"], _typed(_rng.randf_range(r[0], r[1]), p))
		_apply_structure(ps)
		var rewards: Array = []
		for b in bases:
			rewards.append(_eval_on_base(ps, b)["reward"])
		var mean := _mean(rewards)
		rows.append("phaseB,joint_%d,-,%.4f,%.4f,-,-,-,-,-,-" % [n, mean, _min(rewards)])
		if mean > best_reward:
			best_reward = mean
			best_cfg = ps
	_csv_append(csv_path, rows)
	if best_cfg != null:
		print("   phase B best mean reward=%.3f" % best_reward)
		for p in PARAMS:
			if p["scope"] == "graph":
				_set_param(baseline, p["name"], _get_param(best_cfg, p["name"]))
		_apply_structure(baseline)

# ---------------------------------------------------------------------------
# Build + score one settings config on one cached base. Pure (write_to_gen=false).
# ---------------------------------------------------------------------------
func _eval_on_base(ps: WorldSettings, base: Dictionary) -> Dictionary:
	_gen.restore_base_state(base)
	_gen.settings = ps
	var res := GraphBuilder.new().build(_gen, ps, false)
	var vio := GraphRules.validate(_gen, res["graph"], res["start"], res["end"], ps, res["meta"])
	return GraphMetrics.evaluate(res, base["height"], base["biome"],
		ps.map_width, ps.map_height, ps.ocean_threshold, _cfg, _distinct_violations(vio))

## Count DISTINCT violated rule types, not raw instances. Per-path rules in
## GraphRules.validate fire once per enumerated path (up to thousands), which would
## otherwise let a single window mismatch dwarf every other reward term and floor
## the reward to 0. Distinct-type count is bounded (~0..16) and comparable.
func _distinct_violations(vio: Array) -> int:
	var seen := {}
	for x in vio:
		seen[x["rule"]] = true
	return seen.size()

# ---------------------------------------------------------------------------
# Sampling + typing helpers.
# ---------------------------------------------------------------------------
func _sample_values(lo: float, hi: float, p: Dictionary) -> Array:
	var step := float(p["step"])
	var vals := {}
	# Always include the endpoints for coverage of the range extremes.
	vals[_snap(lo, lo, hi, step)] = true
	vals[_snap(hi, lo, hi, step)] = true
	var tries := 0
	while vals.size() < V and tries < V * 8:
		tries += 1
		vals[_snap(_rng.randf_range(lo, hi), lo, hi, step)] = true
	var out: Array = vals.keys()
	out.sort()
	return out

func _snap(v: float, lo: float, hi: float, step: float) -> float:
	if step <= 0.0:
		return clampf(v, lo, hi)
	return clampf(round(v / step) * step, lo, hi)

func _typed(v, p: Dictionary):
	return int(round(v)) if p["type"] == "i" else float(v)

func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / float(a.size())

func _min(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var m := INF
	for v in a:
		m = minf(m, float(v))
	return m

# ---------------------------------------------------------------------------
# Output files.
# ---------------------------------------------------------------------------
func _csv_header(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("round,param,value,seed_mean,seed_min,coverage,hollow,keff,biome,spread,violations")
	f.close()

func _csv_append(path: String, rows: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	f.seek_end()
	for r in rows:
		f.store_line(r)
	f.close()

func _write_best(combo: String, baseline: WorldSettings, ranges: Dictionary) -> void:
	var txt := FileAccess.open("%s/best_ranges.txt" % OUT_DIR, FileAccess.READ_WRITE if FileAccess.file_exists("%s/best_ranges.txt" % OUT_DIR) else FileAccess.WRITE)
	txt.seek_end()
	txt.store_line("\n[%s]  (target_cities=%d)" % [combo, _target_cities])
	var jdict := {}
	for p in PARAMS:
		var nm: String = p["name"]
		var r: Array = ranges[nm]
		var best = _get_param(baseline, nm)
		txt.store_line("  %-26s [%.4f .. %.4f]  best=%s" % [nm, r[0], r[1], str(best)])
		jdict[nm] = best
	# Derived (not searched): dictated by target_cities + spacing.
	txt.store_line("  -- derived from target_cities=%d --" % _target_cities)
	for nm in ["layer_count", "min_cities_visited", "max_cities_visited", "max_travel_count", "max_city_count"]:
		var dv = baseline.get(nm)
		txt.store_line("  %-26s (derived) = %s" % [nm, str(dv)])
		jdict[nm] = dv
	txt.close()

	# best_ranges.json: merge keyed by combo (tier_target).
	var jpath := "%s/best_ranges.json" % OUT_DIR
	var root := {}
	if FileAccess.file_exists(jpath):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(jpath))
		if typeof(parsed) == TYPE_DICTIONARY:
			root = parsed
	root[combo] = jdict
	var jf := FileAccess.open(jpath, FileAccess.WRITE)
	jf.store_string(JSON.stringify(root, "  "))
	jf.close()
	print("   wrote best_ranges.txt/.json + %s_samples.csv" % combo)

# ---------------------------------------------------------------------------
# Best-graph image: with the converged baseline, build the graph over a few
# seeds, keep the highest-reward one, and save a full-res PNG of the graph drawn
# on the heightmap (graph-only view, heightmap background for the landmasses).
# ---------------------------------------------------------------------------
func _save_best_image(combo: String, baseline: WorldSettings) -> void:
	var best_reward := -INF
	var best_res := {}
	var best_height := PackedFloat32Array()
	var best_w := 0; var best_h := 0; var best_ot := 0.0
	var seeds := mini(maxi(1, S), 8)  # cap regen cost; best of these seeds
	for s in range(1, seeds + 1):
		var bs := baseline.duplicate(true) as WorldSettings
		bs.main_seed = s
		_gen.settings = bs
		await _gen.generate_base_through_civilizations()
		var base := _gen.cache_base_state()
		var res := GraphBuilder.new().build(_gen, bs, false)
		if res["graph"].is_empty():
			continue
		var vio := GraphRules.validate(_gen, res["graph"], res["start"], res["end"], bs, res["meta"])
		var r := GraphMetrics.evaluate(res, base["height"], base["biome"],
			bs.map_width, bs.map_height, bs.ocean_threshold, _cfg, _distinct_violations(vio))
		if r["reward"] > best_reward:
			best_reward = r["reward"]
			best_res = res
			best_height = base["height"].duplicate()
			best_w = bs.map_width; best_h = bs.map_height; best_ot = bs.ocean_threshold
	if best_res.is_empty():
		print("   (no buildable graph to image for %s)" % combo)
		return
	var img := _render_graph_image(best_height, best_w, best_h, best_ot, best_res)
	var path := "%s/%s_best_graph.png" % [OUT_DIR, combo]
	img.save_png(path)
	print("   saved %s_best_graph.png (reward=%.3f)" % [combo, best_reward])

## Heightmap background (ocean dark, land warm-grey by elevation) with the graph
## drawn over it: white edges + direction arrowheads, yellow cities, blue routed
## travel nodes, green start, red end. Mirrors world_viewer._burn_graph colors.
func _render_graph_image(height: PackedFloat32Array, w: int, h: int, ot: float, res: Dictionary) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in range(h):
		for x in range(w):
			var v := height[(y * w) + x]
			var col: Color
			if v < ot:
				col = Color(0.05, 0.08, 0.18)  # deep ocean
			else:
				var t := clampf((v - ot) / maxf(0.001, 1.0 - ot), 0.0, 1.0)
				var g := lerpf(0.30, 0.95, t)
				col = Color(g * 0.88, g * 0.92, g * 0.80)  # warm grey land by elevation
			img.set_pixel(x, y, col)

	var graph: Dictionary = res["graph"]
	for parent in graph.keys():
		var p1: Vector2 = parent
		for child in graph[parent]:
			var p2: Vector2 = child
			_plot_line(img, p1, p2, Color.WHITE)
			_plot_arrowhead(img, p1, p1.lerp(p2, 0.55), Color("#fb923c"), 6.0)

	var route := {}
	for parent in graph.keys():
		route[parent] = true
		for child in graph[parent]:
			route[child] = true
	var meta: Dictionary = res["meta"]
	for node in route.keys():
		var p: Vector2 = node
		if meta.get(node, {}).get("is_city", false):
			_plot_disc(img, p, 4.0, Color("#ecc94b"))
		else:
			_plot_disc(img, p, 2.5, Color("#60a5fa"))
	_plot_disc(img, res["start"], 6.0, Color.GREEN)
	_plot_disc(img, res["end"], 6.0, Color.RED)
	return img

# --- pixel primitives (mirror world_viewer.gd) -----------------------------
func _plot_disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	var ri := int(ceil(r))
	for ox in range(-ri, ri + 1):
		for oy in range(-ri, ri + 1):
			if Vector2(ox, oy).length() <= r:
				_safe_set(img, int(c.x) + ox, int(c.y) + oy, col)

func _plot_line(img: Image, p1: Vector2, p2: Vector2, col: Color) -> void:
	var steps := int(maxf(1.0, p1.distance_to(p2)))
	for s in range(steps + 1):
		var p := p1.lerp(p2, float(s) / float(steps))
		_safe_set(img, int(p.x), int(p.y), col)

func _plot_arrowhead(img: Image, from: Vector2, tip: Vector2, col: Color, size: float) -> void:
	var dir := tip - from
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	_plot_line(img, tip, tip - dir * size + perp * size * 0.6, col)
	_plot_line(img, tip, tip - dir * size - perp * size * 0.6, col)

func _safe_set(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, col)

func _write_how_to_read() -> void:
	var f := FileAccess.open("%s/HOW_TO_READ.txt" % OUT_DIR, FileAccess.WRITE)
	f.store_string("""HOW TO READ THE GRAPH PARAMETER SEARCH OUTPUT
=============================================

A "combo" = one map-size tier x one per-run city target, named <tier>_t<target>
(e.g. medium_t10 = 512px map, must visit 10 cities on a run). Every city target is
tested on every tier.

Files in this folder (res://tuning/):

  <combo>_samples.csv  one row per (round, parameter value) sampled. The reward
                       is broken into its component terms so you can see WHY a
                       value scored well, not just that it did.
  best_ranges.txt      human-readable summary: per combo, per parameter, the
                       narrowed [min..max] range and the single best value found,
                       plus the DERIVED values. THIS is the artifact -- start here.
  best_ranges.json     same best values, machine-readable, keyed by combo; load
                       these into a WorldSettings to reproduce the best config.
  <combo>_best_graph.png  full-res picture of the best graph found for the combo,
                       drawn over the heightmap (ocean dark, land grey by
                       elevation): white edges + arrowheads, yellow cities, blue
                       travel nodes, green start, red end.
  HOW_TO_READ.txt      this file.

The console prints per-combo and total wall-clock time at the end of the run.

Derived params (NOT searched -- printed under each combo in best_ranges.txt):
  layer_count, min/max_cities_visited come from target_cities + spacing (a run
  visits one city per `gap=nodes_between_cities+1` layers, so
  layer_count=(target+1)*gap and cities_visited is pinned to the target).
  max_travel_count = round(travel_per_city * target_cities).
  max_city_count   = (target_cities+2) * min_graph_width.
Collapsed targets: `outgoing` sets min=max_outgoing; `nodes_between_cities` sets
min=max. (min/max_path_dist were removed -- edges now connect to the nearest nodes
in the next band, scaling with map size instead of a fixed pixel radius.)

CSV columns
-----------
  round       search round number (1..max_rounds), or "phaseB" for joint search.
  param       the parameter being swept that row (or "joint_N" in phase B).
  value       the sampled value applied to that parameter.
  seed_mean   mean reward across the S seeds (the ranking signal).
  seed_min    worst-case reward across seeds (low = fragile on some maps).
  coverage    fraction of LAND cells the graph footprint touches (0..1).
  hollow      hollow-subdivision score (0..1), depends on hollow_mode (below).
  keff        raw "effective number of equal-sized hollows" (inverse-Simpson).
              Many equal hollows -> high; one huge hollow -> ~1; few big + many
              tiny slivers -> ~1. This is the unnormalized signal behind the
              uniform-mode hollow score.
  biome       distinct biomes among graph nodes / distinct biomes on the map.
  spread      node bounding-box area / land bounding-box area (0..1); low when the
              graph clusters in one corner, high when it spans the landmass.
  violations  mean count of GraphRules violations (penalized in the reward).

How reward is composed
----------------------
  reward = max(0,  w_coverage*coverage + w_hollow*hollow + w_biome*biome
                 + w_spread*spread - w_violation*violations)
  reward = 0 if the graph has no start->end path.

  Weights used for THIS run (scene exports):
    w_coverage=%s  w_hollow=%s  w_biome=%s  w_spread=%s  w_violation=%s
    hollow_mode=%s  ref_cells_per_hollow=%s
    hollow_target_cells=%s  hollow_spread=%s  grid_px=%s

The hollow lever (two modes)
----------------------------
  hollow_mode="uniform" (default, honeycomb): rewards MANY EQUAL-sized hollows
    via keff (the inverse-Simpson effective count), with NO size target. A graph
    that tiles the land into equal medium/small faces (a web) wins; one big empty
    or parallel-close slivers lose. keff is normalized by total_land /
    ref_cells_per_hollow so the score sits ~0..1 and w_hollow is comparable across
    tiers -- ref_cells_per_hollow is only a scale factor, NOT a per-hollow size
    target. Subdivision does not run away: more hollows need more edges, which
    raises coverage, which is capped by the node budget.
  hollow_mode="target" (legacy): each hollow weighted by a gaussian bump peaking
    at hollow_target_cells (cells), area-weighted. Raise hollow_target_cells for
    larger enclosed spaces; lower for finer subdivision.

Range narrowing
---------------
  Each round samples V values per parameter across its current range, scores each
  over S seeds, then resets the range to the span of the top ~30%% of values (plus
  a 10%% pad) and sets the running baseline to the single best value. Rounds stop
  early once no range moves more than 5%%. Coordinate descent holds other params
  at the running baseline; Phase B (if enabled) does a joint random search within
  the narrowed graph-scope ranges to catch interactions.
""" % [str(w_coverage), str(w_hollow), str(w_biome), str(w_spread), str(w_violation),
		str(hollow_mode), str(ref_cells_per_hollow),
		str(hollow_target_cells), str(hollow_spread), str(grid_px)])
	f.close()
