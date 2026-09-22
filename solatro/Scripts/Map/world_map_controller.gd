class_name WorldMapController
extends Node2D

## Traversal layer over the worldgen addon: the WorldMap2D, the camera, the token and the pick.

# Reachability is derived per lap over the DAG (forward on even laps, reversed on odd), which also
# restyles the overlay's own Line2Ds for the four edge states. Pointer, finger and pad all feed ONE
# standing pick; travelling is the map screen's own Travel button, never an input here.

signal map_ready
signal node_entered(node: WorldGraphNode)
signal node_hovered(node: WorldGraphNode)
signal node_unhovered

## The player picked a reachable node to look at. Travelling is a separate act, on a button of its own.
signal node_selected(node: WorldGraphNode)

## Nothing is picked any more -- the map screen goes back to its basic view.
signal selection_cleared

## Accept was pressed with a node picked. A map node is not a Control, so the pad is handed to the Travel button by the screen that owns it.
signal travel_focus_requested

## Traveled path, dim gold, kept across laps.
const HISTORY_COLOR := Color("#b8860b")
## Edges to directly reachable nodes.
const HIGHLIGHT_COLOR := Color("#ffe066")
## Booster node markers.
const BOOSTER_COLOR := Color("#9f7aea")
## Game node markers.
const GAME_COLOR := Color("#f7fafc")
const HIGHLIGHT_WIDTH_BONUS := 3.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
## Px of motion before a press becomes a pan.
const DRAG_THRESHOLD := 8.0

@onready var camera: Camera2D = %Camera2D
@onready var token: MapPlayerToken = %Token

var run : RunState = null
var map : WorldMap2D = null

var _current : WorldGraphNode = null
var _hovered : WorldGraphNode = null
## Node id -> Array[int] of forward-edge sources.
var _reverse_adj : Dictionary[int, Array] = {}
var _accepting_input : bool = false
var _moving : bool = false
var _follow_token : bool = true
var _press_pos := Vector2.ZERO
var _pressed : bool = false
var _dragging : bool = false
# The reachable node the player has picked, by pointer, finger or pad alike -- null at rest. ONE
# field for all three, so the Travel button can never aim somewhere other than what the map marks.
var _selected : WorldGraphNode = null

var _container_shift : Vector2 = Vector2.ZERO

# `Map._publish_map_inset()`'s shift, in the map picture's own local space: screen centre to the
# space left over beside the container. `Camera2D.offset` is a world offset Godot multiplies by
# `zoom` before it reaches the screen, so it is re-derived on every zoom change too.
func apply_container_shift(shift: Vector2) -> void:
	_container_shift = shift
	_apply_camera_offset()

func _apply_camera_offset() -> void:
	camera.offset = _container_shift / camera.zoom

# Fetching the overlay before add_child creates it BEFORE the map Sprite2D, so z_index must raise
# it over the map image. generate_on_ready=false auto-loads an existing bake on add_child, and
# graph_export is valid only right after a generation, so a reloaded bake is never re-baked.
func start_run(new_run: RunState) -> void:
	run = new_run
	if map == null:
		map = WorldMap2D.new()
		map.name = "WorldMap"
		map.generate_on_ready = false
		map.show_loading_screen = true
		map.world_seed = run.world_seed
		map.bake_directory = RunManager.MAP_BAKE_DIR
		map.overlay().z_index = 1
		map.overlay().graph_populated.connect(_on_graph_populated)
		add_child(map)
		move_child(map, 0)
	else:
		map.world_seed = run.world_seed
	if not FileAccess.file_exists(RunManager.MAP_BAKE_DIR.path_join("composite.png")):
		await map.generate()
		map.bake_to_files()
		map.release_generator()

## The clickable player position follows the camera each frame while travelling.
func _process(_delta: float) -> void:
	if _follow_token and token:
		camera.position = token.position
	_pulse_next_markers()

func _on_graph_populated() -> void:
	var overlay := map.overlay()
	_build_reverse_adj(overlay)
	MapNodeRoles.assign(overlay, run.world_seed, run)
	if run.current_node_id < 0:
		run.current_node_id = lap_origin().id
	_current = overlay.node(run.current_node_id)
	token.position = _current.position
	_follow_token = true
	refresh_visuals()
	_accepting_input = true
	_auto_select_if_single()
	map_ready.emit()

## Advance the run to the next lap: edge state is derived wholly from reachability, so every edge becoming usable again needs no reset; history coloring stays.
func on_lap_completed() -> void:
	run.lap += 1
	MapNodeRoles.assign(map.overlay(), run.world_seed, run)
	refresh_visuals()
	_auto_select_if_single()

# =============================================================================
# GRAPH DIRECTION / REACHABILITY
# =============================================================================

## The anchor the current lap starts from (start node on even laps, end node on odd).
func lap_origin() -> WorldGraphNode:
	return map.overlay().end_node() if run.is_reversed() else map.overlay().start_node()

## The anchor the current lap is heading to (the boss show).
func lap_target() -> WorldGraphNode:
	return map.overlay().start_node() if run.is_reversed() else map.overlay().end_node()

# Forward edges are the only stored direction; odd laps walk them backwards via this map.
func _build_reverse_adj(overlay: WorldGraphOverlay) -> void:
	_reverse_adj = {}
	for n: WorldGraphNode in overlay.nodes():
		for e: Dictionary in n.outgoing:
			var to_id :int= e["to"]
			if not _reverse_adj.has(to_id):
				_reverse_adj[to_id] = []
			(_reverse_adj[to_id] as Array).append(n.id)

## Direct neighbors of `n` in the current lap direction (the clickable set from there).
func next_nodes_of(n: WorldGraphNode) -> Array[WorldGraphNode]:
	if not run.is_reversed():
		return n.next_nodes()
	var out: Array[WorldGraphNode] = []
	for src_id: int in (_reverse_adj.get(n.id, []) as Array):
		var src := map.overlay().node(src_id)
		if src != null:
			out.append(src)
	return out

## Every node id still reachable from the token in the current lap direction, as a set id -> true, the current node included.
func reachable_ids() -> Dictionary:
	var seen := {}
	var frontier: Array[WorldGraphNode] = [_current]
	seen[_current.id] = true
	while frontier:
		var n: WorldGraphNode = frontier.pop_back()
		for nxt in next_nodes_of(n):
			if not seen.has(nxt.id):
				seen[nxt.id] = true
				frontier.append(nxt)
	return seen

# =============================================================================
# VISUAL STATE
# =============================================================================

## Reassigns every edge Line2D and node marker to an explicit state rather than a delta, so lap resets and re-populates stay consistent; an unusable untraveled edge hides, a node marker never does.
func refresh_visuals() -> void:
	var overlay := map.overlay()
	var reachable := reachable_ids()
	var traveled_set : Dictionary[Vector2i, bool] = {}
	for t in run.traveled:
		traveled_set[Vector2i(t.x, t.y)] = true
	for n: WorldGraphNode in overlay.nodes():
		_style_marker(n)
		for e: Dictionary in n.outgoing:
			var to := overlay.node(e["to"] as int)
			var line := n.edge_line(to)
			if line == null:
				continue
			var ferry :bool= e["ferry"]
			line.visible = true
			line.width = overlay.ferry_width if ferry else overlay.edge_width
			if traveled_set.has(Vector2i(n.id, to.id)):
				line.default_color = HISTORY_COLOR
			elif _edge_from_current(n, to):
				line.default_color = HIGHLIGHT_COLOR
				line.width += HIGHLIGHT_WIDTH_BONUS
			elif _edge_usable(n, to, reachable):
				line.default_color = overlay.ferry_color if ferry else overlay.edge_color
			else:
				line.visible = false

# Does forward edge (u -> v) leave the token's node in the current lap direction?
func _edge_from_current(u: WorldGraphNode, v: WorldGraphNode) -> bool:
	return (v == _current) if run.is_reversed() else (u == _current)

# Can forward edge (u -> v) still be traversed this lap? Its direction-source must be
# reachable from the token.
func _edge_usable(u: WorldGraphNode, v: WorldGraphNode, reachable: Dictionary) -> bool:
	return reachable.has(v.id) if run.is_reversed() else reachable.has(u.id)

func _style_marker(n: WorldGraphNode) -> void:
	var overlay := map.overlay()
	if n.is_start:
		n.marker_color = overlay.start_color
	elif n.is_end:
		n.marker_color = overlay.end_color
	elif n.meta.get(MapNodeRoles.ROLE_KEY, "") as String == MapNodeRoles.ROLE_BOOSTER:
		n.marker_color = BOOSTER_COLOR
	else:
		n.marker_color = GAME_COLOR
	n.queue_redraw()

# Directly reachable node markers pulse so the clickable choices read at a glance; _style_marker
# re-derives the base color each frame so the pulse never compounds.
func _pulse_next_markers() -> void:
	if _current == null or _moving or not _accepting_input:
		return
	var t := 0.6 + 0.4 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0))
	for n in next_nodes_of(_current):
		_style_marker(n)
		n.marker_color = n.marker_color.lerp(Color.WHITE, 0.8 if n == _selected else 0.4)
		n.marker_color.a = t
		n.queue_redraw()

# =============================================================================
# INPUT: hover, click-to-travel, pan, zoom
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _accepting_input:
		return
	if event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
		_cycle_selection(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
		_cycle_selection(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_accept"):
		if _selected != null and not _moving:
			get_viewport().set_input_as_handled()
			travel_focus_requested.emit()
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _selected != null:
			clear_selection()
			get_viewport().set_input_as_handled()
		return
	if _consumed_as_touch(event):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_pos = mb.position
			else:
				if _pressed and not _dragging:
					select_node(_node_at_mouse())
				_pressed = false
				_dragging = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressed and (_dragging or mm.position.distance_to(_press_pos) > DRAG_THRESHOLD):
			_dragging = true
			_follow_token = false
			camera.position -= mm.relative / camera.zoom.x
		else:
			_update_hover()

# Next nodes in a stable visual order (top to bottom) so cycling feels predictable.
func _sorted_next() -> Array[WorldGraphNode]:
	var nexts := next_nodes_of(_current)
	nexts.sort_custom(func(a: WorldGraphNode, b: WorldGraphNode) -> bool:
		return a.position.y < b.position.y if a.position.y != b.position.y \
				else a.position.x < b.position.x)
	return nexts

## The reachable node the player has picked, or null while the map is at rest.
func selected() -> WorldGraphNode:
	return _selected

# Walks the reachable set from wherever the pick already is, so the pad and the pointer share one
# selection rather than keeping a cursor each.
func _cycle_selection(dir: int) -> void:
	if _moving:
		return
	var nexts := _sorted_next()
	if nexts.is_empty():
		return
	var at := nexts.find(_selected)
	select_node(nexts[wrapi((at if at >= 0 else (-1 if dir > 0 else 0)) + dir, 0, nexts.size())])

func _zoom_at(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	_apply_camera_offset()

# World-space radius test against all markers (camera zoom is baked into the overlay's own
# local space, so no per-zoom math is needed).
func _node_at(overlay_pos: Vector2) -> WorldGraphNode:
	var overlay := map.overlay()
	var best: WorldGraphNode = null
	var best_d := maxf(overlay.node_radius * 2.0, 12.0)
	for n: WorldGraphNode in overlay.nodes():
		var d := n.position.distance_to(overlay_pos)
		if d < best_d:
			best_d = d
			best = n
	return best

func _node_at_mouse() -> WorldGraphNode:
	return _node_at(map.overlay().get_local_mouse_position())

# Where `node`'s marker draws in the map viewport's own coordinates -- the space the map's `$UI`
# overlays live in, so a caller can place something against the dot the player is pointing at.
# Static because the name popup re-asks it every frame and holds no controller.
static func node_screen_rect(node: WorldGraphNode) -> Rect2:
	var xform := node.get_global_transform_with_canvas()
	var radius := node.marker_radius * xform.get_scale()
	return Rect2(xform.origin - radius, radius * 2.0)

# A MAP NODE IS A BARE DOT, so a tap picks it and says what it is; travelling is the Travel button's,
# for a finger exactly as for a pointer, so no tap count is counted any more.
# ⚠ ONLY A TAP IS TAKEN -- a finger that travelled is a pan, and pans by the mouse path below.
func _consumed_as_touch(event: InputEvent) -> bool:
	var lift := event as InputEventMouseButton
	if lift == null or lift.device != -1 or lift.pressed \
			or lift.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not _pressed or _dragging:
		return false
	_pressed = false
	var local := map.overlay().make_input_local(lift) as InputEventMouseButton
	select_node(_node_at(local.position))
	return true

func _update_hover() -> void:
	var n := _node_at_mouse()
	if n == _hovered:
		return
	_hovered = n
	if n != null:
		node_hovered.emit(n)
	else:
		node_unhovered.emit()

# PICKING IS NOT TRAVELLING: a pick only says which node the sidebar describes and the Travel button
# aims at. Empty space and an unreachable node are the ordinary outcomes of a click on a map, so
# neither is a refusal and neither disturbs the pick already standing.
func select_node(node: WorldGraphNode) -> void:
	if node == null or _moving or node == _selected:
		return
	if node not in next_nodes_of(_current):
		return
	_selected = node
	node_selected.emit(node)

## True only while `node_selected` fires for a pick nobody clicked, so a listener can tell the two apart.
var auto_picking := false

## A single reachable node needs no click -- picked the moment it is the only option; two or more leaves the pick alone.
func _auto_select_if_single() -> void:
	var nexts := next_nodes_of(_current)
	if nexts.size() != 1: return
	auto_picking = true
	select_node(nexts[0])
	auto_picking = false

## Puts the map back to its basic view: nothing picked, nothing marked, and the screen's own buttons gone with it.
func clear_selection() -> void:
	if _selected == null: return
	var was := _selected
	_selected = null
	_style_marker(was)
	selection_cleared.emit()

# Travel to a directly reachable node: the routed edge curve is walked with its point order
# reversed on odd laps while the history entry is always recorded in forward-edge orientation, and
# _style_marker drops the pulse tint from the node being left.
func move_to(next: WorldGraphNode) -> void:
	_moving = true
	var pts: PackedVector2Array
	if run.is_reversed():
		pts = next.edge_to(_current)
		pts.reverse()
		run.traveled.append(Vector3i(next.id, _current.id, run.lap))
	else:
		pts = _current.edge_to(next)
		run.traveled.append(Vector3i(_current.id, next.id, run.lap))
	_style_marker(_current)
	clear_selection()
	_follow_token = true
	await token.travel_along(pts)
	run.current_node_id = next.id
	_current = next
	refresh_visuals()
	_moving = false
	node_entered.emit(next)
