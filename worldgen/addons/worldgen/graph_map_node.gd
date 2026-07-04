@tool
class_name WorldGraphNode
extends Node2D

## One DAG node in a WorldGraphOverlay, positioned in the map's local space (origin =
## map centre). Holds the gameplay properties exported by GraphPlacement.export_graph and
## the token-movement API used to walk the graph: next_nodes(), edge_to(), edge_line().
## `meta` is a free-form Dictionary reserved as the biome/WFC extension point (empty now).

## Compact node id (matches the export; stable within one populate()).
var id: int = -1
## Layer index: 0 = start, max_depth = end. Advancing an edge increases depth.
var depth: int = 0
## Landmass label this node sits on (edges between differing labels are ferries).
var landmass: int = 0
## Terrain height at the node position (>= ocean threshold; nodes never sit on water).
var height: float = 0.0
## True for the single start node (depth 0) / end node (depth max_depth).
var is_start: bool = false
var is_end: bool = false
## Extension point for future min-conflict/WFC biome assignment. Untouched by the addon.
var meta: Dictionary = {}
## Forward edges as exported: [{to: int, ferry: bool, points: PackedVector2Array}], with
## `points` already converted to map-local space by the overlay. `to` is a node id.
var outgoing: Array = []

## Set by the overlay so id-based lookups (next_nodes, edge_line) resolve without a
## global registry.
var overlay: WorldGraphOverlay = null
## Marker look (set by the overlay from WorldMap2D's display exports). When marker_texture
## is assigned it is drawn (tinted by marker_color) centered at 2*marker_radius instead of
## the default disc, so custom node art needs no subclassing.
var marker_radius: float = 6.0
var marker_color: Color = Color.WHITE
var marker_texture: Texture2D = null
# to_id -> Line2D drawn for that edge (owned by the overlay).
var _edge_lines: Dictionary = {}

## Draw the node marker: the assigned texture (tinted) if any, else a filled disc + outline.
func _draw() -> void:
	if marker_texture != null:
		var d := marker_radius * 2.0
		draw_texture_rect(marker_texture, Rect2(Vector2(-marker_radius, -marker_radius), Vector2(d, d)), false, marker_color)
		return
	draw_circle(Vector2.ZERO, marker_radius, marker_color)
	draw_arc(Vector2.ZERO, marker_radius, 0.0, TAU, 24, Color(0, 0, 0, 0.6), maxf(1.0, marker_radius * 0.2), true)

## Register the Line2D the overlay drew for the edge to `to_id` (used by edge_line()).
func _set_edge_line(to_id: int, line: Line2D) -> void:
	_edge_lines[to_id] = line

## The nodes this node has a forward edge to (each advances toward the end node).
func next_nodes() -> Array[WorldGraphNode]:
	var out: Array[WorldGraphNode] = []
	if overlay == null:
		return out
	for e in outgoing:
		var n := overlay.node(int(e["to"]))
		if n != null:
			out.append(n)
	return out

## The routed curve (map-local points) from this node to `other`, or an empty array if
## there is no forward edge. Follow these points to move a token along the edge.
func edge_to(other: WorldGraphNode) -> PackedVector2Array:
	if other == null:
		return PackedVector2Array()
	for e in outgoing:
		if int(e["to"]) == other.id:
			return e["points"]
	return PackedVector2Array()

## The Line2D drawing the edge to `other` (for restyling/highlighting), or null.
func edge_line(other: WorldGraphNode) -> Line2D:
	if other == null:
		return null
	return _edge_lines.get(other.id, null)

## True when the edge to `other` is an ocean ferry (crosses to another landmass).
func is_ferry_to(other: WorldGraphNode) -> bool:
	if other == null:
		return false
	for e in outgoing:
		if int(e["to"]) == other.id:
			return bool(e["ferry"])
	return false
