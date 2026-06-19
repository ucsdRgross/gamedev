extends Node

## Step-A robustness test (run this scene with F6). Pure data, NO map.
##
## GraphSpec must produce a valid, rule-correct DAG for ANY parameter combination.
## This test hammers the whole value space three ways:
##   1. Named representative specs (readable sanity checks).
##   2. EXTREME edge cases (0s, 1s, and large 100-scale values, mismatched ratios).
##   3. A large random fuzz over wide ranges x many seeds.
## Every built graph is checked with GraphSpec.validate(); any violation is a FAIL
## and prints the exact spec/seed/rule. The run does not stop on failure.

# {name, cities, nbc, width, outgoing, after_trim, trim}
const NAMED := [
	{"name": "tiny",        "cities": 2,  "nbc": 1,  "w": 2,  "out": 2, "at": 1, "trim": 0.0},
	{"name": "small-narrow","cities": 3,  "nbc": 1,  "w": 2,  "out": 2, "at": 1, "trim": 0.3},
	{"name": "medium",      "cities": 5,  "nbc": 2,  "w": 3,  "out": 3, "at": 1, "trim": 0.3},
	{"name": "wide",        "cities": 4,  "nbc": 2,  "w": 5,  "out": 3, "at": 2, "trim": 0.2},
	{"name": "long-chain",  "cities": 8,  "nbc": 4,  "w": 3,  "out": 2, "at": 1, "trim": 0.4},
	{"name": "dense",       "cities": 6,  "nbc": 3,  "w": 4,  "out": 4, "at": 2, "trim": 0.5},
]

# Deliberately pathological / boundary inputs (incl. values that get clamped).
const EXTREME := [
	{"name": "x-cities0",    "cities": 0,  "nbc": 0,  "w": 0,  "out": 0,  "at": 0,  "trim": 0.0},
	{"name": "x-min",        "cities": 2,  "nbc": 0,  "w": 1,  "out": 1,  "at": 1,  "trim": 1.0},
	{"name": "x-nbc0-wide",  "cities": 6,  "nbc": 0,  "w": 8,  "out": 3,  "at": 1,  "trim": 0.5},
	{"name": "x-width>>out", "cities": 5,  "nbc": 1,  "w": 40, "out": 2,  "at": 1,  "trim": 0.3},
	{"name": "x-out>>width", "cities": 5,  "nbc": 2,  "w": 2,  "out": 30, "at": 1,  "trim": 0.3},
	{"name": "x-at>out",     "cities": 5,  "nbc": 2,  "w": 4,  "out": 3,  "at": 9,  "trim": 0.3},
	{"name": "x-trim>1",     "cities": 5,  "nbc": 2,  "w": 4,  "out": 3,  "at": 1,  "trim": 5.0},
	{"name": "x-big-cities", "cities": 100,"nbc": 1,  "w": 3,  "out": 2,  "at": 1,  "trim": 0.3},
	{"name": "x-big-nbc",    "cities": 3,  "nbc": 100,"w": 4,  "out": 3,  "at": 1,  "trim": 0.3},
	{"name": "x-big-width",  "cities": 4,  "nbc": 3,  "w": 100,"out": 5,  "at": 1,  "trim": 0.3},
	{"name": "x-big-out",    "cities": 4,  "nbc": 2,  "w": 6,  "out": 100,"at": 2,  "trim": 0.3},
	{"name": "x-all-100",    "cities": 12, "nbc": 5,  "w": 20, "out": 8,  "at": 3,  "trim": 0.9},
]

@export var named_seeds: int = 20
@export var fuzz_count: int = 1500    # random specs, each with its own random seed

# Fuzz ranges (kept bounded so node counts stay sane while still spanning the space).
const F_CITIES := Vector2i(2, 40)
const F_NBC := Vector2i(0, 15)
const F_WIDTH := Vector2i(1, 40)
const F_OUT := Vector2i(1, 20)
const F_AT := Vector2i(1, 6)

var _total := 0
var _failed := 0

func _ready() -> void:
	print("=== GraphSpec robustness test ===")
	print("-- named specs (%d seeds each) --" % named_seeds)
	for spec in NAMED:
		_run_spec(spec, named_seeds, true)
	print("-- extreme edge cases (%d seeds each) --" % named_seeds)
	for spec in EXTREME:
		_run_spec(spec, named_seeds, true)
	print("-- fuzz: %d random specs --" % fuzz_count)
	_run_fuzz()
	print("=== complete: %d/%d passed, %d failed ===" % [_total - _failed, _total, _failed])
	get_tree().quit()

func _run_spec(spec: Dictionary, seeds: int, verbose: bool) -> void:
	var fail_rules := {}
	var sample := ""
	for s in range(1, seeds + 1):
		_total += 1
		var g := GraphSpec.build(spec["cities"], spec["nbc"], spec["w"], spec["out"],
			spec["at"], spec["trim"], s)
		if s == 1:
			sample = "nodes=%d edges=%d ranks=%d" % [g["nodes"].size(), _edges(g["adj"]), g["ranks"]]
		var vios := GraphSpec.validate(g, spec["cities"], spec["nbc"], spec["w"], spec["out"], spec["at"])
		if not vios.is_empty():
			_failed += 1
			for vio in vios:
				fail_rules[vio["rule"]] = fail_rules.get(vio["rule"], 0) + 1
			if verbose:
				print("  FAIL %s seed%d: %s" % [spec["name"], s, _summarize(vios)])
	var status := "OK" if fail_rules.is_empty() else "FAIL " + str(fail_rules)
	if verbose:
		print("  %-14s %-30s %s" % [spec["name"], sample, status])

func _run_fuzz() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234567
	var fuzz_fails := 0
	var fail_rules := {}
	for i in range(fuzz_count):
		_total += 1
		var cities := rng.randi_range(F_CITIES.x, F_CITIES.y)
		var nbc := rng.randi_range(F_NBC.x, F_NBC.y)
		var w := rng.randi_range(F_WIDTH.x, F_WIDTH.y)
		var out := rng.randi_range(F_OUT.x, F_OUT.y)
		var at := rng.randi_range(F_AT.x, F_AT.y)
		var trim := rng.randf()
		var sd := rng.randi()
		var g := GraphSpec.build(cities, nbc, w, out, at, trim, sd)
		var vios := GraphSpec.validate(g, cities, nbc, w, out, at)
		if not vios.is_empty():
			_failed += 1
			fuzz_fails += 1
			for vio in vios:
				fail_rules[vio["rule"]] = fail_rules.get(vio["rule"], 0) + 1
			if fuzz_fails <= 25:   # don't flood the log
				print("  FAIL fuzz c=%d nbc=%d w=%d out=%d at=%d trim=%.2f seed=%d: %s" % [
					cities, nbc, w, out, at, trim, sd, _summarize(vios)])
	if fuzz_fails == 0:
		print("  fuzz: all %d passed" % fuzz_count)
	else:
		print("  fuzz: %d/%d failed, rules=%s" % [fuzz_fails, fuzz_count, fail_rules])

func _edges(adj: Dictionary) -> int:
	var n := 0
	for u in adj.keys():
		n += adj[u].size()
	return n

func _summarize(vios: Array) -> String:
	var by_rule := {}
	var sample := {}
	for v in vios:
		var r: String = v["rule"]
		by_rule[r] = by_rule.get(r, 0) + 1
		if not sample.has(r):
			sample[r] = v["detail"]
	var parts: Array = []
	for r in by_rule.keys():
		parts.append("%s x%d {%s}" % [r, by_rule[r], sample[r]])
	return ", ".join(parts)
