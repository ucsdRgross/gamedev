@tool
class_name WorldGraphOverlay
extends Node2D

## Interactive DAG overlay for a WorldMap2D: one WorldGraphNode child per graph node and
## one Line2D child per edge, all in the map's local space (origin = map centre). Built
## from GraphPlacement.export_graph output by populate(); exposes start/end/id lookups so
## a token can walk the graph (start_node -> WorldGraphNode.next_nodes() -> edge_to()).

## Emitted after populate() finishes rebuilding the node/edge children. A consumer's
## biome/WFC pass (the deferred min-conflict work) hooks here to fill WorldGraphNode.meta.
signal graph_populated

## Marker + edge look (WorldMap2D pushes its display exports here before populate()).
var node_radius: float = 6.0
var node_color: Color = Color("#f7fafc")
var start_color: Color = Color("#38a169")
var end_color: Color = Color("#e53e3e")
var edge_color: Color = Color("#2d3748")
var edge_width: float = 3.0
## Ferry (ocean-crossing) edges are styled distinctly so water travel reads apart.
var ferry_color: Color = Color("#3182ce")
var ferry_width: float = 2.0
## Tint node markers by their biome legend color (start/end keep their own colors).
var tint_by_biome: bool = false
## Optional custom art. Node textures (tint by the color above) replace the drawn disc;
## edge textures tile along the Line2D; edge_gradient colors the line along its length.
## Leave null to use the vector defaults. For finer control, connect graph_populated and
## restyle nodes()/edge_line() directly.
var node_texture: Texture2D = null
var start_texture: Texture2D = null
var end_texture: Texture2D = null
var edge_texture: Texture2D = null
var ferry_texture: Texture2D = null
var edge_gradient: Gradient = null

## Raw export dict last populated from (start, end, max_depth, nodes[...]). Retained so
## consumers can read the plain-data graph without walking the Node2D tree.
var graph_data: Dictionary = {}
# Compact id -> WorldGraphNode.
var _nodes: Dictionary = {}

## Rebuild the overlay from an export_graph dict. `map_size` is the map's pixel size, used
## to shift map-pixel coordinates into local space (origin-centered): local = pixel - size/2.
## Lines are added before markers so nodes render on top. Emits graph_populated when done.
func populate(export: Dictionary, map_size: Vector2) -> void:
	_clear()
	graph_data = export
	var offset := map_size * 0.5
	var start_id := int(export.get("start", 0))
	var end_id := int(export.get("end", 0))
	var node_dicts: Array = export.get("nodes", [])
	# Biome legend baked into the export by StepBiomes: id -> {name, color}.
	var legend := {}
	for e in export.get("biomes", []):
		legend[int(e.get("id", -1))] = e

	# Pass 1: node objects (positions needed before edges reference them).
	for nd in node_dicts:
		var gn := WorldGraphNode.new()
		gn.id = int(nd["id"])
		gn.depth = int(nd.get("depth", 0))
		gn.landmass = int(nd.get("landmass", 0))
		gn.height = float(nd.get("height", 0.0))
		gn.biome = int(nd.get("biome", -1))
		gn.is_start = gn.id == start_id
		gn.is_end = gn.id == end_id
		gn.overlay = self
		gn.position = (nd["pos"] as Vector2) - offset
		gn.marker_radius = node_radius
		gn.marker_color = start_color if gn.is_start else (end_color if gn.is_end else node_color)
		gn.marker_texture = start_texture if gn.is_start else (end_texture if gn.is_end else node_texture)
		if legend.has(gn.biome):
			gn.meta["biome_name"] = legend[gn.biome].get("name", "")
			gn.meta["biome_color"] = Color(legend[gn.biome].get("color", "#ffffff"))
			if tint_by_biome and not gn.is_start and not gn.is_end:
				gn.marker_color = gn.meta["biome_color"]
		_nodes[gn.id] = gn

	# Pass 2: edges as Line2D children + fill each node's local-space outgoing list.
	for nd in node_dicts:
		var gn: WorldGraphNode = _nodes[int(nd["id"])]
		for e in nd.get("out", []):
			var to_id := int(e["to"])
			var ferry := bool(e.get("ferry", false))
			var local_pts := PackedVector2Array()
			for p in (e.get("points", PackedVector2Array()) as PackedVector2Array):
				local_pts.append(p - offset)
			gn.outgoing.append({"to": to_id, "ferry": ferry, "points": local_pts})
			var line := Line2D.new()
			line.points = local_pts
			line.width = ferry_width if ferry else edge_width
			line.default_color = ferry_color if ferry else edge_color
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			var tex: Texture2D = ferry_texture if ferry else edge_texture
			if tex != null:
				line.texture = tex
				line.texture_mode = Line2D.LINE_TEXTURE_TILE
			if edge_gradient != null:
				line.gradient = edge_gradient
			add_child(line)
			gn._set_edge_line(to_id, line)

	# Markers last so they render above the edges.
	for id in _nodes:
		add_child(_nodes[id])
	graph_populated.emit()

## The node with compact id `id`, or null.
func node(id: int) -> WorldGraphNode:
	return _nodes.get(id, null)

## The single start node (depth 0) / end node (depth max_depth), or null before populate().
func start_node() -> WorldGraphNode:
	return node(int(graph_data.get("start", 0)))

func end_node() -> WorldGraphNode:
	return node(int(graph_data.get("end", 0)))

## Every WorldGraphNode, ordered by id.
func nodes() -> Array:
	var out: Array = []
	var ids := _nodes.keys()
	ids.sort()
	for id in ids:
		out.append(_nodes[id])
	return out

# Free all node + edge children immediately (tool-safe) and drop the lookup.
func _clear() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	_nodes.clear()
	graph_data = {}
