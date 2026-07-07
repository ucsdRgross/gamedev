class_name WorldMapController
extends Node2D

## Traversal layer over the worldgen addon: owns the WorldMap2D (created in code), the
## Camera2D (pan/zoom/follow) and the player token, derives per-lap reachability over the
## DAG (forward on even laps, reversed on odd laps), restyles the overlay's own Line2Ds
## for the four edge states (traveled / next / usable / hidden), and turns mouse input
## into node hover + travel.

signal map_ready
signal node_entered(node: WorldGraphNode)
signal node_hovered(node: WorldGraphNode)
signal node_unhovered

const HISTORY_COLOR := Color("#b8860b")    ## traveled path (dim gold), kept across laps
const HIGHLIGHT_COLOR := Color("#ffe066")  ## edges to directly reachable nodes
const BOOSTER_COLOR := Color("#9f7aea")    ## booster node markers
const GAME_COLOR := Color("#f7fafc")       ## game node markers
const HIGHLIGHT_WIDTH_BONUS := 3.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const DRAG_THRESHOLD := 8.0                ## px of motion before a press becomes a pan

@onready var camera: Camera2D = %Camera2D
@onready var token: MapPlayerToken = %Token

var run : RunState = null
var map : WorldMap2D = null

var _current : WorldGraphNode = null
var _hovered : WorldGraphNode = null
var _reverse_adj : Dictionary = {}     # node id -> Array[int] of forward-edge sources
var _accepting_input : bool = false
var _moving : bool = false
var _follow_token : bool = true
var _press_pos := Vector2.ZERO
var _pressed : bool = false
var _dragging : bool = false
# Keyboard/controller selection: index into _sorted_next(), -1 = nothing selected.
var _kb_index : int = -1

## Build (or rebind) the WorldMap2D for this run: reload the bake when one exists, else
## generate from the pinned seed and bake exactly once (graph_export is only valid right
## after a generation this session — never re-bake after a reload).
func start_run(new_run: RunState) -> void:
	run = new_run
	if map == null:
		map = WorldMap2D.new()
		map.name = "WorldMap"
		map.generate_on_ready = false
		map.show_loading_screen = true
		map.world_seed = run.world_seed
		map.bake_directory = RunManager.MAP_BAKE_DIR
		# Fetching the overlay early (to connect before any populate) also creates it
		# BEFORE the map Sprite2D — raise it so nodes/edges draw over the map image.
		map.overlay().z_index = 1
		map.overlay().graph_populated.connect(_on_graph_populated)
		add_child(map)
		move_child(map, 0)  # render under camera/token
	else:
		map.world_seed = run.world_seed
	# WorldMap2D._ready (generate_on_ready=false) auto-loads an existing bake on
	# add_child; only a fresh run needs a generation here.
	if not FileAccess.file_exists(RunManager.MAP_BAKE_DIR.path_join("composite.png")):
		await map.generate()
		map.bake_to_files()
		# Drop the generation worker (SubViewports) + loading overlay: this session only
		# reloads the bake from here on.
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
	map_ready.emit()

## Advance the run to the next lap: direction flips (RunState.is_reversed), roles and
## goals re-derive for the new lap, and every edge becomes usable again (edge state is
## fully derived from reachability, so the reset is implicit). History coloring stays.
func on_lap_completed() -> void:
	run.lap += 1
	MapNodeRoles.assign(map.overlay(), run.world_seed, run)
	refresh_visuals()

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

## Every node id still reachable from the token in the current lap direction
## (Dictionary as a set: id -> true; includes the current node).
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

## Reassign every edge Line2D and node marker to one of the explicit states (never
## deltas, so lap resets and re-populates are always consistent):
## traveled -> history color; from-current -> highlight; still-usable -> normal;
## unusable & untraveled -> hidden. All node markers stay visible.
func refresh_visuals() -> void:
	var overlay := map.overlay()
	var reachable := reachable_ids()
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
			if _is_traveled(n.id, to.id):
				line.default_color = HISTORY_COLOR
			elif _edge_from_current(n, to):
				line.default_color = HIGHLIGHT_COLOR
				line.width += HIGHLIGHT_WIDTH_BONUS
			elif _edge_usable(n, to, reachable):
				line.default_color = overlay.ferry_color if ferry else overlay.edge_color
			else:
				line.visible = false

func _is_traveled(from_id: int, to_id: int) -> bool:
	for t in run.traveled:
		if t.x == from_id and t.y == to_id:
			return true
	return false

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

# Directly reachable node markers pulse so the clickable choices read at a glance.
func _pulse_next_markers() -> void:
	if _current == null or _moving or not _accepting_input:
		return
	var t := 0.6 + 0.4 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0))
	var kb_sel := _kb_selected()
	for n in next_nodes_of(_current):
		_style_marker(n)  # re-derive the base color so the pulse never compounds
		n.marker_color = n.marker_color.lerp(Color.WHITE, 0.8 if n == kb_sel else 0.4)
		n.marker_color.a = t
		n.queue_redraw()

# =============================================================================
# INPUT: hover, click-to-travel, pan, zoom
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _accepting_input:
		return
	# Keyboard/controller: cycle the reachable next nodes, accept to travel.
	if event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
		_kb_cycle(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
		_kb_cycle(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_accept"):
		var sel := _kb_selected()
		if sel != null and not _moving:
			get_viewport().set_input_as_handled()
			move_to(sel)
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _kb_index >= 0:
			_kb_index = -1
			node_unhovered.emit()
			get_viewport().set_input_as_handled()
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
					_try_click()
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

func _kb_selected() -> WorldGraphNode:
	var nexts := _sorted_next()
	if _kb_index < 0 or nexts.is_empty():
		return null
	return nexts[_kb_index % nexts.size()]

func _kb_cycle(dir: int) -> void:
	if _moving:
		return
	var nexts := _sorted_next()
	if nexts.is_empty():
		return
	_kb_index = wrapi((_kb_index if _kb_index >= 0 else (-1 if dir > 0 else 0)) + dir, 0, nexts.size())
	node_hovered.emit(nexts[_kb_index])

func _zoom_at(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)

# World-space radius test against all markers (camera zoom is baked into the global
# mouse position, so no per-zoom math is needed).
func _node_at_mouse() -> WorldGraphNode:
	var overlay := map.overlay()
	var mouse := overlay.get_local_mouse_position()
	var best: WorldGraphNode = null
	var best_d := maxf(overlay.node_radius * 2.0, 12.0)
	for n: WorldGraphNode in overlay.nodes():
		var d := n.position.distance_to(mouse)
		if d < best_d:
			best_d = d
			best = n
	return best

func _update_hover() -> void:
	var n := _node_at_mouse()
	if n == _hovered:
		return
	_hovered = n
	if n != null:
		node_hovered.emit(n)
	else:
		node_unhovered.emit()

func _try_click() -> void:
	if _moving:
		return
	var n := _node_at_mouse()
	if n != null and n in next_nodes_of(_current):
		move_to(n)

## Travel to a directly reachable node: walk the routed edge curve (reversed point order
## on odd laps), record the history entry in forward-edge orientation, then re-derive
## visuals and announce the arrival so Map can resolve the node's role.
func move_to(next: WorldGraphNode) -> void:
	_moving = true
	var pts: PackedVector2Array
	if run.is_reversed():
		pts = next.edge_to(_current)  # forward edge next -> current, walked backwards
		pts.reverse()
		run.traveled.append(Vector3i(next.id, _current.id, run.lap))
	else:
		pts = _current.edge_to(next)
		run.traveled.append(Vector3i(_current.id, next.id, run.lap))
	_style_marker(_current)  # drop any pulse tint on the node we leave
	_kb_index = -1
	_follow_token = true
	await token.travel_along(pts)
	run.current_node_id = next.id
	_current = next
	refresh_visuals()
	_moving = false
	node_entered.emit(next)
