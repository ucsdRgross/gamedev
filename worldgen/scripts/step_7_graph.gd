class_name Step7Graph
extends GenerationStep

## Thin driver: build the rule-driven traversal DAG (GraphBuilder), print the
## traversal statistics block (GraphRules), and snapshot for the viewer.
## The result Dictionary is cached on the generator so the test suite can
## validate/measure the exact graph that was produced.
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	if gen.travel_nodes.size() < 2 and gen.city_nodes.size() < 2:
		return

	var result := GraphBuilder.new().build(gen, settings)
	gen.graph_result = result  # {graph, start, end, meta, injected}

	print("[Graph] params: ", GraphRules.format_graph_params(settings))
	if result["injected"] > 0:
		print("[Graph] failsafe injected %d node(s) to keep paths valid" % result["injected"])

	var stats := GraphRules.collect_stats(result["graph"], result["start"], result["end"], settings, result["meta"])
	GraphRules.print_stats(stats)

	_build_edge_curves(gen, settings, result["graph"])
	gen._save_snapshot_bridge("Graph")

# ---------------------------------------------------------------------------
# Cosmetic curved edges: route each graph edge around water (ocean + rivers +
# lakes) and over passes (penalize terrain above the endpoints), so the colored
# view shows believable winding roads instead of straight lines. The straight
# graph stays in the debug "lines only" cell. Only edges that actually hit
# water/high terrain are routed (A*); clear edges stay straight (fast).
# ---------------------------------------------------------------------------
func _build_edge_curves(gen: WorldGenerator, settings: WorldSettings, graph: Dictionary) -> void:
	gen.edge_curves.clear()
	var water := {}
	for r in gen.river_nodes:
		water[r] = true
	for l in gen.lake_nodes:
		water[l] = true
	for parent in graph.keys():
		for child in graph[parent]:
			gen.edge_curves.append(_curve_edge(gen, settings, parent, child, water))

func _height_at(gen: WorldGenerator, p: Vector2) -> float:
	var w := gen.settings.map_width
	var h := gen.settings.map_height
	return gen.height_buffer[(clampi(int(p.y), 0, h - 1) * w) + clampi(int(p.x), 0, w - 1)]

## Every edge becomes a quadratic-bezier road bowed sideways. We scan a range of
## perpendicular control offsets and pick the one that crosses the least water
## (ocean hard, river/lake soft) and high terrain, with a penalty on how far it
## bows -- so it only curves as much as actually helps, and a road that can't be
## improved stays straight (crossing the shortest water span). A small minimum
## bow is applied to every road for looks, and a per-edge sign keeps near-parallel
## roads from overlapping.
func _curve_edge(gen: WorldGenerator, settings: WorldSettings, a: Vector2, b: Vector2, water: Dictionary) -> PackedVector2Array:
	var straight := a.distance_to(b)
	if straight < 2.0:
		return PackedVector2Array([a, b])
	var target := maxf(_height_at(gen, a), _height_at(gen, b)) + 0.03
	# Split into 1-3 sub-segments and bow each with ALTERNATING sign, so the road
	# reads as an S / chain (straight runs where the bow lands near zero) instead
	# of one perfect arc. Per-edge jitter keeps parallel roads distinct.
	var k := clampi(int(straight / 45.0), 1, 3)
	var seg_max := minf(settings.path_curve_max_px, (straight / float(k)) * 0.7)
	var jit := 1.0 if (int(a.x + a.y * 3.0 + b.x * 7.0 + b.y * 11.0) % 2) == 0 else -1.0

	var poly := PackedVector2Array()
	poly.append(a)
	for si in range(k):
		var pa := a.lerp(b, float(si) / float(k))
		var pb := a.lerp(b, float(si + 1) / float(k))
		var side := jit * (1.0 if (si % 2 == 0) else -1.0)  # alternate for the S
		var best_off := 0.0
		var best_cost := INF
		for j in range(-6, 7):
			var off := (float(j) / 6.0) * seg_max
			# small reward for bowing to this segment's alternating side
			var cost := _curve_cost(gen, settings, pa, pb, off, water, target) \
				+ absf(off) * 0.08 - (off * side) * 0.03
			if cost < best_cost:
				best_cost = cost
				best_off = off
		# Sample the chosen bezier into a chain of short straight segments. This
		# follows the SAME path _curve_cost validated (so corners never overshoot
		# into water like using the control point directly did), at ~4x density.
		var ctrl := ((pa + pb) * 0.5) + (pb - pa).normalized().orthogonal() * best_off
		var samples := maxi(4, int(pa.distance_to(pb) / 10.0))
		for s in range(1, samples + 1):
			poly.append(_qbez(pa, ctrl, pb, float(s) / float(samples)))
	return poly

## Weighted crossing cost of a bezier with the given perpendicular control offset.
func _curve_cost(gen: WorldGenerator, settings: WorldSettings, a: Vector2, b: Vector2, off: float, water: Dictionary, target: float) -> float:
	var w := settings.map_width
	var h := settings.map_height
	var oth := settings.ocean_threshold
	var ctrl := ((a + b) * 0.5) + (b - a).normalized().orthogonal() * off
	var n := 12
	var cost := 0.0
	for s in range(1, n):
		var p := _qbez(a, ctrl, b, float(s) / float(n))
		var px := clampi(int(p.x), 0, w - 1)
		var py := clampi(int(p.y), 0, h - 1)
		var ht := gen.height_buffer[(py * w) + px]
		if ht < oth:
			cost += 10.0
		elif water.has(Vector2i(px, py)):
			cost += 4.0
		cost += maxf(0.0, ht - target) * 20.0
	return cost

func _qbez(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var it := 1.0 - t
	return (it * it * a) + (2.0 * it * t * c) + (t * t * b)
