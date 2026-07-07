class_name BiomeRegions
extends RefCounted

## Map-side biome regions. Pipeline (all pure CPU, thread-safe):
##   build_cells  : noise-warped multi-source flood from the MapField's Poisson
##                  samples -> every land pixel joins an organic "cell" (warped
##                  Voronoi super-pixel); cells never cross water. Pixels on
##                  sample-less islets become synthetic orphan cells.
##   paint_cells  : label cells -- graph-node pins grow round-robin territories,
##                  unclaimed cells fill with climate-prior patches, then a
##                  single sliver-absorption pass merges tiny regions (there are
##                  deliberately NO biome adjacency rules).
##   rasterize    : cells -> per-pixel biome buffer (-1 = water).
##   legend       : plain-data [{id, name, color, required}] for bakes/overlays.

## Dial bucket count for the warped flood (quantized non-negative step costs).
const NB := 8192


## Flood every land pixel to its cheapest sample by warped cost. Returns
## {cell_of: PackedInt32Array (pixel -> cell id, -1 water), n_cells, orphan_cells,
##  px_count/sum_h/sum_m per cell, adj: Array[Dictionary cell->true],
##  cell_label: PackedInt32Array (landmass per cell), ms}.
static func build_cells(field, warp_bytes: PackedByteArray, humid_bytes: PackedByteArray,
		opts: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var w: int = field.w
	var h: int = field.h
	var n := w * h
	var heightb: PackedFloat32Array = field.height
	var waterm: PackedByteArray = field.water
	var labelm: PackedInt32Array = field.label
	var samples: PackedVector2Array = field.samples
	var warp_amp: float = opts.get("warp_amp", 2.0)
	var height_cost: float = opts.get("height_cost", 3.0)
	var has_warp := warp_bytes.size() >= n

	var best := PackedFloat32Array()
	best.resize(n)
	best.fill(INF)
	var owner := PackedInt32Array()
	owner.resize(n)
	owner.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	closed.fill(0)
	# Bucket queue (Dial's algorithm). Same COW discipline as fill_depressions:
	# never cache buckets[cur] in a local across an append -- index it directly.
	var buckets: Array = []
	buckets.resize(NB)
	for b in range(NB):
		buckets[b] = PackedInt32Array()
	var max_cost := float(w + h) * (1.0 + warp_amp + height_cost * 0.05)
	var inv_bw := float(NB) / max_cost

	for si in range(samples.size()):
		var p := samples[si]
		var i := (int(p.y) * w) + int(p.x)
		if i < 0 or i >= n or waterm[i] == 1 or owner[i] != -1:
			continue
		best[i] = 0.0
		owner[i] = si
		buckets[0].append(i)

	var dx := PackedInt32Array([1, -1, 0, 0])
	var dy := PackedInt32Array([0, 0, 1, -1])
	var cur := 0
	var cursor := 0
	while cur < NB:
		if cursor >= (buckets[cur] as PackedInt32Array).size():
			cur += 1
			cursor = 0
			continue
		var ci: int = buckets[cur][cursor]
		cursor += 1
		if closed[ci] == 1:
			continue                        # stale (relaxed again after this push)
		closed[ci] = 1
		var cx := ci % w
		var cy := ci / w
		var bc := best[ci]
		var hc := heightb[ci]
		for k in range(4):
			var nx: int = cx + dx[k]
			var ny: int = cy + dy[k]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni := (ny * w) + nx
			if closed[ni] == 1 or waterm[ni] == 1:
				continue
			var step := 1.0 + height_cost * absf(heightb[ni] - hc)
			if has_warp:
				step += warp_amp * (float(warp_bytes[ni]) / 255.0)
			var nc := bc + step
			if nc < best[ni]:
				best[ni] = nc
				owner[ni] = owner[ci]
				buckets[mini(int(nc * inv_bw), NB - 1)].append(ni)

	# Orphan islets (no Poisson sample landed there): each connected component
	# becomes its own synthetic cell so ALL land is covered.
	var n_cells := samples.size()
	var orphan_first: Array = []            # first pixel per orphan cell (for its landmass)
	for i0 in range(n):
		if waterm[i0] == 1 or owner[i0] != -1:
			continue
		var cid := n_cells
		n_cells += 1
		orphan_first.append(i0)
		owner[i0] = cid
		var stack := PackedInt32Array([i0])
		var sp := 0
		while sp < stack.size():
			var c: int = stack[sp]
			sp += 1
			var ccx := c % w
			var ccy := c / w
			for k in range(4):
				var nx: int = ccx + dx[k]
				var ny: int = ccy + dy[k]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := (ny * w) + nx
				if waterm[ni] == 0 and owner[ni] == -1:
					owner[ni] = cid
					stack.append(ni)

	# Per-cell stats + exact cell adjacency (right/down neighbor pairs).
	var px_count := PackedInt32Array()
	px_count.resize(n_cells)
	var sum_h := PackedFloat32Array()
	sum_h.resize(n_cells)
	var sum_m := PackedFloat32Array()
	sum_m.resize(n_cells)
	var adj: Array = []
	adj.resize(n_cells)
	for c in range(n_cells):
		adj[c] = {}
	var has_humid := humid_bytes.size() >= n
	for y in range(h):
		for x in range(w):
			var i := (y * w) + x
			var o := owner[i]
			if o < 0:
				continue
			px_count[o] += 1
			sum_h[o] += heightb[i]
			sum_m[o] += (float(humid_bytes[i]) / 255.0) if has_humid else 0.5
			if x + 1 < w:
				var o2 := owner[i + 1]
				if o2 >= 0 and o2 != o:
					adj[o][o2] = true
					adj[o2][o] = true
			if y + 1 < h:
				var o3 := owner[i + w]
				if o3 >= 0 and o3 != o:
					adj[o][o3] = true
					adj[o3][o] = true

	var cell_label := PackedInt32Array()
	cell_label.resize(n_cells)
	var sample_label: PackedInt32Array = field.sample_label
	for si in range(samples.size()):
		cell_label[si] = sample_label[si] if si < sample_label.size() else -1
	for k in range(orphan_first.size()):
		cell_label[samples.size() + k] = labelm[orphan_first[k]]

	return {"cell_of": owner, "n_cells": n_cells, "orphan_cells": orphan_first.size(),
		"px_count": px_count, "sum_h": sum_h, "sum_m": sum_m, "adj": adj,
		"cell_label": cell_label, "ms": Time.get_ticks_msec() - t0}


## Label every cell with a biome: pins -> round-robin territory growth ->
## climate-prior filler patches -> sliver absorption. `pins` is
## [{cell: int, biome: int}, ...] from the graph nodes (may be empty: pure
## climate-map mode). Returns {cell_biome, pinned, pin_fail, slivers_fixed, ms}.
static func paint_cells(cells: Dictionary, bset: WorldBiomeSet, pins: Array,
		opts: Dictionary, seed_val: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var n_cells: int = cells.n_cells
	var adj: Array = cells.adj
	var cell_label: PackedInt32Array = cells.cell_label
	var cell_biome := PackedInt32Array()
	cell_biome.resize(n_cells)
	cell_biome.fill(-1)
	var pinned := PackedByteArray()
	pinned.resize(n_cells)
	pinned.fill(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var used := {}                          # biome -> true (novelty damp for filler)

	# --- Pins: a node's cell takes its biome; a rare collision (two nodes, one
	# cell) falls back to the nearest unpinned same-landmass neighbor (BFS <= 2).
	var pin_recs: Array = []                # [cell, biome, landmass]
	var pin_fail := 0
	for p in pins:
		var c: int = p.cell
		var b: int = p.biome
		if c < 0 or c >= n_cells or b < 0:
			pin_fail += 1
			continue
		if pinned[c] == 1 and cell_biome[c] != b:
			c = _free_neighbor(adj, pinned, cell_label, c)
			if c < 0:
				pin_fail += 1
				continue
		cell_biome[c] = b
		pinned[c] = 1
		used[b] = true
		pin_recs.append([c, b, cell_label[c]])

	# --- Territory growth: round-robin, one frontier cell per pin per round, so
	# territories stay balanced and nodes sit INSIDE organic blobs, not at centers.
	var target: int = maxi(1, opts.get("territory_cells", 8))
	var quota: Array = []
	var frontier: Array = []
	for r in pin_recs:
		quota.append(maxi(1, roundi(target * (0.75 + 0.5 * rng.randf()))))
		var f: Array = []
		for nb in adj[r[0]]:
			f.append(nb)
		frontier.append(f)
	var progressed := true
	while progressed:
		progressed = false
		for pi in range(pin_recs.size()):
			if quota[pi] <= 0:
				continue
			var f: Array = frontier[pi]
			var got := -1
			while not f.is_empty():
				var idx := rng.randi_range(0, f.size() - 1)
				var cand: int = f[idx]
				f.remove_at(idx)
				if cell_biome[cand] == -1 and cell_label[cand] == pin_recs[pi][2]:
					got = cand
					break
			if got == -1:
				quota[pi] = 0
				continue
			cell_biome[got] = pin_recs[pi][1]
			quota[pi] -= 1
			progressed = true
			for nb in adj[got]:
				if cell_biome[nb] == -1:
					f.append(nb)

	# --- Climate-prior filler: patch-grow every still-unclaimed cell (far
	# islands, untouched interior) with the best-fitting biome from the pool.
	var patch: int = maxi(1, opts.get("filler_patch_cells", 6))
	if bset != null and not bset.biomes.is_empty():
		for c0 in range(n_cells):
			if cell_biome[c0] != -1:
				continue
			var b := _best_biome(bset, cells, c0, used, rng)
			used[b] = true
			cell_biome[c0] = b
			var lab := cell_label[c0]
			var goal := maxi(1, roundi(patch * (0.75 + 0.5 * rng.randf())))
			var q: Array = [c0]
			var grown := 1
			var qi := 0
			while qi < q.size() and grown < goal:
				var c: int = q[qi]
				qi += 1
				for nb in adj[c]:
					if grown >= goal:
						break
					if cell_biome[nb] == -1 and cell_label[nb] == lab:
						cell_biome[nb] = b
						grown += 1
						q.append(nb)

	# --- Sliver absorption (the whole cleanup -- no adjacency rules): connected
	# same-biome components under min_region_cells merge into their most common
	# neighboring biome. Pinned components are exempt. One deterministic pass.
	var min_region: int = opts.get("min_region_cells", 3)
	var slivers_fixed := 0
	var seen := PackedByteArray()
	seen.resize(n_cells)
	seen.fill(0)
	for c0 in range(n_cells):
		if seen[c0] == 1 or cell_biome[c0] < 0:
			continue
		var b := cell_biome[c0]
		var comp: Array = [c0]
		seen[c0] = 1
		var has_pin := pinned[c0] == 1
		var qi := 0
		while qi < comp.size():
			var c: int = comp[qi]
			qi += 1
			for nb in adj[c]:
				if seen[nb] == 0 and cell_biome[nb] == b:
					seen[nb] = 1
					comp.append(nb)
					has_pin = has_pin or pinned[nb] == 1
		if has_pin or comp.size() >= min_region:
			continue
		var votes := {}
		for c in comp:
			for nb in adj[c]:
				var ob := cell_biome[nb]
				if ob >= 0 and ob != b:
					votes[ob] = votes.get(ob, 0) + 1
		if votes.is_empty():
			continue                        # whole islet is one tiny region: keep it
		var win := -1
		var wv := -1
		for k in votes:
			if votes[k] > wv:
				wv = votes[k]
				win = k
		for c in comp:
			cell_biome[c] = win
		slivers_fixed += 1

	return {"cell_biome": cell_biome, "pinned": pinned, "pin_fail": pin_fail,
		"slivers_fixed": slivers_fixed, "ms": Time.get_ticks_msec() - t0}


## Expand the cell labeling to the per-pixel biome buffer (-1 = water).
static func rasterize(cells: Dictionary, cell_biome: PackedInt32Array, field) -> PackedInt32Array:
	var n: int = field.w * field.h
	var owner: PackedInt32Array = cells.cell_of
	var buf := PackedInt32Array()
	buf.resize(n)
	buf.fill(-1)
	for i in range(n):
		var o := owner[i]
		if o >= 0:
			buf[i] = cell_biome[o]
	return buf


## Plain-data legend [{id, name, color, required}] so bakes/overlays stay
## self-contained even if the WorldBiomeSet is later edited. Color = the
## biome's first band swatch.
static func legend(bset: WorldBiomeSet, assign: Dictionary = {}) -> Array:
	var cast := {}
	for b in assign.get("cast", PackedInt32Array()):
		cast[b] = true
	var out: Array = []
	if bset == null:
		return out
	for i in range(bset.biomes.size()):
		var wb: WorldBiome = bset.biomes[i]
		var col: Color = wb.bands[0].color if not wb.bands.is_empty() else Color.MAGENTA
		out.append({"id": i, "name": String(wb.name), "color": "#" + col.to_html(false),
			"required": cast.has(i)})
	return out


## Nearest unpinned same-landmass cell within 2 adjacency hops (pin-collision fallback).
static func _free_neighbor(adj: Array, pinned: PackedByteArray, cell_label: PackedInt32Array, c: int) -> int:
	var lab := cell_label[c]
	for nb in adj[c]:
		if pinned[nb] == 0 and cell_label[nb] == lab:
			return nb
	for nb in adj[c]:
		for nb2 in adj[nb]:
			if pinned[nb2] == 0 and cell_label[nb2] == lab:
				return nb2
	return -1


## Climate-prior filler score: weight x height-fit x moisture-fit x jitter,
## halved for biomes already on the map so unused ones fill first.
static func _best_biome(bset: WorldBiomeSet, cells: Dictionary, c: int, used: Dictionary,
		rng: RandomNumberGenerator) -> int:
	var cnt: int = maxi(1, cells.px_count[c])
	var hm: float = cells.sum_h[c] / cnt
	var mm: float = cells.sum_m[c] / cnt
	var best := 0
	var best_score := -1.0
	for i in range(bset.biomes.size()):
		var wb: WorldBiome = bset.biomes[i]
		var s := maxf(0.001, wb.weight)
		s *= _fit(hm, wb.height_range, 0.08)
		s *= _fit(mm, wb.moisture_range, 0.15)
		s *= 0.75 + 0.5 * rng.randf()
		if used.has(i):
			s *= 0.5
		if s > best_score:
			best_score = s
			best = i
	return best


## 1.0 inside [r.x, r.y], gaussian falloff (width s) outside.
static func _fit(x: float, r: Vector2, s: float) -> float:
	if x >= r.x and x <= r.y:
		return 1.0
	var d := (r.x - x) if x < r.x else (x - r.y)
	return exp(-pow(d / s, 2.0))
