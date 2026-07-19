extends Node

## Gate for the deterministic (CPU) heightmap path — see
## worldgen/DETERMINISM_FINDINGS.md. Unlike native_ab_test, the contract here is
## NOT "matches the GDScript/GPU twin": a GPU's pow/atan cannot be reproduced
## across vendors, which is the very problem this path exists to solve. What must
## hold is:
##   1. REPEATABLE — the CPU path gives byte-identical heights run to run.
##   2. DIVERGENCE BOUNDED — CPU vs GPU terrain is close enough that the map still
##      looks like the same world (reported, not asserted; it is a design call).
##   3. The land/water mask (what the GRAPH is actually built from) is reported,
##      since that is the thing that must not move between machines.
## Run WINDOWED (the GPU comparison arm needs frame_post_draw).

@export var seeds: Array[int] = [12356, 777]

var _gen: WorldGenerator
var _fails := 0


func _ready() -> void:
	print("=== deterministic terrain test ===")
	if GenerationStep._native == null:
		print("  [FAIL] worldgen_native missing — the CPU path needs it")
		get_tree().quit(1)
		return
	_gen = WorldGenerator.new()
	add_child(_gen)
	await get_tree().process_frame
	for sd in seeds:
		await _run_seed(sd)
	print("=== deterministic terrain: %s ===" % ["PASS" if _fails == 0 else "FAIL (%d)" % _fails])
	get_tree().quit(_fails)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print("  [%s] %s" % ["PASS" if ok else "FAIL", msg])


## Height buffer for one seed at the given terrain mode, stopped after `upto`.
func _heights(sd: int, deterministic: bool, upto: WorldGenerator.GenStep) -> PackedFloat32Array:
	var ws := WorldSettings.new()
	ws.main_seed = sd
	ws.deterministic_terrain = deterministic
	_gen.settings = ws
	await _gen.generate_up_to(upto)
	return _gen.height_buffer.duplicate()


func _run_seed(sd: int) -> void:
	await _compare(sd, WorldGenerator.GenStep.LANDMASS, "Landmass only")
	# Deltas compound across the four heightmap steps, so the number that decides
	# whether the GRAPH moves is the full-chain flip count, not the Landmass one.
	await _compare(sd, WorldGenerator.GenStep.EROSION, "full heightmap chain")


func _compare(sd: int, upto: WorldGenerator.GenStep, label: String) -> void:
	var cpu_a := await _heights(sd, true, upto)
	var cpu_b := await _heights(sd, true, upto)
	var gpu := await _heights(sd, false, upto)
	print("-- seed %d (%s) --" % [sd, label])

	# 1. Repeatability: the whole point.
	_check(cpu_a.to_byte_array() == cpu_b.to_byte_array(),
		"[%s] CPU terrain is byte-identical across runs (%d px)" % [label, cpu_a.size()])

	if gpu.size() != cpu_a.size():
		_check(false, "size mismatch cpu=%d gpu=%d" % [cpu_a.size(), gpu.size()])
		return

	# Guard against a vacuous pass: if the deterministic seam silently stopped
	# engaging, both "CPU" arms would run the GPU path and the repeatability check
	# would still pass. CPU and GPU terrain are known-divergent (max|d|~0.03), so
	# byte-equal buffers here mean the native path did NOT actually run.
	_check(cpu_a.to_byte_array() != gpu.to_byte_array(),
		"[%s] CPU path engaged (output differs from the GPU arm)" % label)

	# 2. How far the CPU path sits from today's GPU output.
	var oth: float = _gen.settings.ocean_threshold
	var maxd := 0.0
	var sumd := 0.0
	var mask_flips := 0
	for i in range(cpu_a.size()):
		var d: float = absf(cpu_a[i] - gpu[i])
		sumd += d
		if d > maxd:
			maxd = d
		if (cpu_a[i] >= oth) != (gpu[i] >= oth):
			mask_flips += 1
	print("   CPU vs GPU: max|d|=%.5f mean|d|=%.6f  land/water flips=%d (%.3f%% of px)" % [
		maxd, sumd / float(cpu_a.size()), mask_flips,
		100.0 * mask_flips / float(cpu_a.size())])
