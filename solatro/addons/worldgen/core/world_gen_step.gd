class_name GenerationStep
extends RefCounted

## Virtual base for one map-generation pass.
##
## Each concrete step owns a single shader (or a small ping-pong group),
## configures its uniforms, flushes the GPU, and reads the result back into
## the generator's CPU buffers. `execute` is a coroutine — callers must
## `await` it because every GPU flush waits for real rendered frames.
func execute(_gen: WorldGenerator, _settings: WorldSettings) -> void:
	pass

## Cached instance of the optional C++ acceleration (worldgen_native GDExtension).
## Null when the dll is missing or the platform is unsupported -- every call site
## must keep the GDScript path as fallback. Outputs are bit-identical (verified by
## tests/native_ab_test.tscn); see GDEXTENSION_PORT_HANDOFF.md.
static var _native: Object = ClassDB.instantiate(&"WorldgenNative") if ClassDB.class_exists(&"WorldgenNative") else null

## Multiple-Flow-Direction (MFD) accumulation on a depression-filled surface.
## Each land cell distributes its (fully summed) flow to ALL strictly-lower
## neighbors, split by drop^exponent: a large exponent (~8) collapses to a single
## steepest path (D8-like, crisp rivers), a small one (~1.5) spreads flow widely.
## On flats and at coasts the spread makes flow FAN OUT -> river deltas / braids
## and diffuse hillslope erosion, which single-flow D8 can never produce.
##
## `seed` is per-cell local input (rainfall; ocean cells should be 0). Cells below
## `oth` are sinks (ocean: no out-edges, flow terminates there). Because the filled
## surface is strictly monotone (priority-flood +epsilon), every edge goes to a
## strictly lower cell -> the flow graph is a DAG, summed exactly in one Kahn
## topological pass. O(n * 8). Returns total accumulated flow per cell.
static func flow_accumulate_mfd(filled: PackedFloat32Array, seed: PackedFloat32Array,
		w: int, h: int, oth: float, exponent: float) -> PackedFloat32Array:
	if _native:
		return _native.flow_accumulate_mfd(filled, seed, w, h, oth, exponent)
	var n := w * h
	var accum := seed.duplicate()
	# Fixed 8-slot edge table per cell (each cell has <= 8 downhill neighbors).
	var et := PackedInt32Array()
	et.resize(n * 8)
	var ew := PackedFloat32Array()
	ew.resize(n * 8)
	var ec := PackedInt32Array()  # out-edge count per cell
	ec.resize(n)
	ec.fill(0)
	var indeg := PackedInt32Array()
	indeg.resize(n)
	indeg.fill(0)

	for y in range(h):
		for x in range(w):
			var i := (y * w) + x
			if filled[i] < oth:
				continue  # ocean: sink, no out-edges
			var hi := filled[i]
			var base := i * 8
			var k := 0
			var sum_w := 0.0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := x + ox
					var ny := y + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni := (ny * w) + nx
					var drop := hi - filled[ni]
					if drop <= 0.0:
						continue
					et[base + k] = ni
					ew[base + k] = pow(drop, exponent)
					sum_w += ew[base + k]
					k += 1
			ec[i] = k
			if sum_w > 0.0:
				for j in range(k):
					ew[base + j] /= sum_w
					indeg[et[base + j]] += 1

	# Kahn topological accumulation: a cell is only drained once all upstream
	# contributors are summed, so its flow is final before it is distributed.
	var queue := PackedInt32Array()
	queue.resize(n)
	var qh := 0
	var qt := 0
	for i in range(n):
		if indeg[i] == 0:
			queue[qt] = i
			qt += 1
	while qh < qt:
		var c := queue[qh]
		qh += 1
		var base := c * 8
		var ac := accum[c]
		for j in range(ec[c]):
			var ch := et[base + j]
			accum[ch] += ac * ew[base + j]
			indeg[ch] -= 1
			if indeg[ch] == 0:
				queue[qt] = ch
				qt += 1
	return accum

## Priority-Flood (+epsilon) depression filling (Barnes et al. 2014), bucket-queue
## variant. Shared by the erosion and river steps. Returns a surface W >= H where
## every land cell has a strictly monotonic downhill path to the open boundary
## (map edge / ocean), so flow never traps in a local minimum; basins are raised
## to their spill level plus a tiny epsilon gradient toward the outlet (which also
## resolves flats). O(n + buckets): pops happen in non-decreasing elevation order
## by advancing a single level cursor; each bucket is read FIFO so the epsilon
## gradient grows along the BFS from each outlet.
const FILL_BUCKETS := 1024
static func fill_depressions(H: PackedFloat32Array, w: int, h: int, oth: float) -> PackedFloat32Array:
	if _native:
		return _native.fill_depressions(H, w, h, oth)
	var n := w * h
	var W := PackedFloat32Array()
	W.resize(n)
	W.fill(INF)
	var closed := PackedByteArray()
	closed.resize(n)
	closed.fill(0)
	const EPS := 0.00001

	# Quantization range for bucket indexing.
	var hmin := INF
	var hmax := -INF
	for i in range(n):
		var v := H[i]
		if v < hmin: hmin = v
		if v > hmax: hmax = v
	var span := maxf(1e-6, hmax - hmin)
	var scale := float(FILL_BUCKETS - 1) / span

	# Unboxed-int FIFO queue per quantized level (faster + lighter than an
	# Array[Array] of boxed Variants). We must NOT cache buckets[cur] in a local
	# across an append: a cached reference would raise the packed array's refcount,
	# so append() would copy-on-write the whole bucket. Indexing buckets[cur]
	# directly each step keeps refcount at 1 -> append mutates in place, O(1).
	var buckets: Array = []
	buckets.resize(FILL_BUCKETS)
	for b in range(FILL_BUCKETS):
		buckets[b] = PackedInt32Array()

	# Seed the open boundary: map edges and every ocean cell drain freely.
	for y in range(h):
		for x in range(w):
			var i := (y * w) + x
			if x == 0 or y == 0 or x == w - 1 or y == h - 1 or H[i] < oth:
				W[i] = H[i]
				closed[i] = 1
				var lv := int((H[i] - hmin) * scale)
				buckets[lv].append(i)

	var cur := 0
	var cursor := 0
	while cur < FILL_BUCKETS:
		if cursor >= (buckets[cur] as PackedInt32Array).size():
			cur += 1
			cursor = 0
			continue
		var ci: int = buckets[cur][cursor]
		cursor += 1
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
				var wn := maxf(H[ni], W[ci] + EPS)
				W[ni] = wn
				closed[ni] = 1
				var lv := mini(int((wn - hmin) * scale), FILL_BUCKETS - 1)
				buckets[lv].append(ni)
	return W
