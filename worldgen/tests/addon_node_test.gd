extends Node2D

## Attached to the test scene root (siblings: a configured WorldMap2D + a Camera2D). Waits
## for the child map to finish generating, frames it, then walks the DAG start -> end,
## printing each hop. Run with F6. Demonstrates the runtime token-movement API.

@onready var map: WorldMap2D = $WorldMap2D
@onready var cam: Camera2D = get_node_or_null("Camera2D")

func _ready() -> void:
	if map == null:
		push_warning("[AddonNodeTest] expected a WorldMap2D child named 'WorldMap2D'.")
		return
	# The child map already started generating in its own _ready(); the walk runs once it
	# reports finished (generation is async, so this connects in time).
	map.generation_finished.connect(_on_generation_finished, CONNECT_ONE_SHOT)

func _on_generation_finished() -> void:
	_fit_camera()
	_walk()

## Follow start -> end, always taking the first forward edge, printing land/ferry + point count.
func _walk() -> void:
	var ov := map.overlay()
	var n := ov.start_node()
	if n == null:
		print("[AddonNodeTest] no graph nodes (graph step disabled?).")
		return
	print("[AddonNodeTest] walk start(%d) -> end(%d), max_depth=%d" % [
		ov.start_node().id, ov.end_node().id, int(ov.graph_data.get("max_depth", 0))])
	var hops := 0
	while n != null and not n.is_end and hops < 500:
		var nexts := n.next_nodes()
		if nexts.is_empty():
			print("  dead end at node %d (depth %d)" % [n.id, n.depth])
			return
		var nxt: WorldGraphNode = nexts[0]
		print("  node %d (depth %d, %s) -> %d  [%s]  %d path pts" % [
			n.id, n.depth, n.meta.get("biome_name", "biome -1"),
			nxt.id, "ferry" if n.is_ferry_to(nxt) else "land", n.edge_to(nxt).size()])
		n = nxt
		hops += 1
	if n != null and n.is_end:
		print("[AddonNodeTest] reached end node %d in %d hops." % [n.id, hops])

## Frame the whole map (centered on origin) in the viewport.
func _fit_camera() -> void:
	if cam == null:
		return
	var size := Vector2(map.settings.map_width, map.settings.map_height)
	var vp := get_viewport_rect().size
	cam.zoom = Vector2.ONE * minf(vp.x / size.x, vp.y / size.y) * 0.9
