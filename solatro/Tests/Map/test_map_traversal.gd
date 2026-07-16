extends TestSuite
# res://Tests/Map/test_map_traversal.gd
# ==============================================================================
# WORLD MAP TRAVERSAL — WorldMapController over a synthetic diamond graph:
#   0 (start) -> 1,2 -> 3 (end)
# Verifies direction-aware next/reachable sets, traveled history orientation, the
# four edge visual states (history / highlighted / normal / hidden), token movement
# along (reversed) edge curves, and the endless-lap flip.
# The controller subtree is built in code (no WorldMap2D generation — the overlay is
# populated from a hand-written export dict; expect one harmless "baked composite not
# found" warning from the stub WorldMap2D).
# ==============================================================================

# CATEGORY MAP: all BEHAVIOR — token movement, reachability, edge visuals, lap
# flips, and keyboard selection are what the player sees on the map. The traveled-
# history storage format checks are the one implementation pin (check_impl inline).

var controller: WorldMapController
var overlay: WorldGraphOverlay
var run: RunState

func suite_name() -> String:
	return "MAP TRAVERSAL"

func _ready() -> void:
	TestLog.line("============ MAP TRAVERSAL TEST PASS ============")
	behavior_section("MAP TRAVERSAL & LAPS")
	var real_run: RunState = RunManager.run
	_build_rig()
	await test_initial_state()
	await test_forward_move_and_edge_states()
	await test_reach_end()
	await test_lap_flip_and_reverse_move()
	await test_keyboard_selection()
	RunManager.run = real_run
	controller.queue_free()
	finish()

func _edge(from_id: int, to_id: int) -> Dictionary:
	var a: Vector2 = _pos(from_id)
	var b: Vector2 = _pos(to_id)
	return {"to": to_id, "ferry": false, "points": PackedVector2Array([a, b])}

func _pos(id: int) -> Vector2:
	return [Vector2(0, 0), Vector2(10, -10), Vector2(10, 10), Vector2(20, 0)][id]

## Diamond: 0(start,d0) -> 1,2(d1) -> 3(end,d2). Tiny distances keep travel tweens fast.
func _diamond_export() -> Dictionary:
	return {"start": 0, "end": 3, "max_depth": 2, "biomes": [], "nodes": [
		{"id": 0, "pos": _pos(0), "depth": 0, "landmass": 0, "height": 0.5, "biome": -1,
			"out": [_edge(0, 1), _edge(0, 2)]},
		{"id": 1, "pos": _pos(1), "depth": 1, "landmass": 0, "height": 0.5, "biome": -1,
			"out": [_edge(1, 3)]},
		{"id": 2, "pos": _pos(2), "depth": 1, "landmass": 0, "height": 0.5, "biome": -1,
			"out": [_edge(2, 3)]},
		{"id": 3, "pos": _pos(3), "depth": 2, "landmass": 0, "height": 0.5, "biome": -1,
			"out": []},
	]}

# Controller + Camera2D/Token (unique-named so the @onready %lookups resolve) + a stub
# WorldMap2D that never generates; overlay populated from the synthetic export.
func _build_rig() -> void:
	controller = WorldMapController.new()
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	controller.add_child(cam)
	cam.owner = controller
	cam.unique_name_in_owner = true
	var token := MapPlayerToken.new()
	token.name = "Token"
	controller.add_child(token)
	token.owner = controller
	token.unique_name_in_owner = true
	add_child(controller)

	var map := WorldMap2D.new()
	map.generate_on_ready = false
	map.bake_directory = "user://__traversal_test_no_bake__"
	controller.add_child(map)
	controller.map = map
	overlay = map.overlay()

	run = RunState.new()
	run.world_seed = 999
	RunManager.run = run
	controller.run = run
	overlay.populate(_diamond_export(), Vector2(40, 40))
	controller._on_graph_populated()

func _node(id: int) -> WorldGraphNode:
	return overlay.node(id)

func _line(from_id: int, to_id: int) -> Line2D:
	return _node(from_id).edge_line(_node(to_id))

func _ids(nodes: Array[WorldGraphNode]) -> Array[int]:
	var out: Array[int] = []
	for n in nodes:
		out.append(n.id)
	out.sort()
	return out

func test_initial_state() -> void:
	check(run.current_node_id == 0, "fresh run starts on the lap-origin anchor")
	check(controller.token.position == _node(0).position, "token placed on the start node")
	check(_ids(controller.next_nodes_of(_node(0))) == [1, 2], "start offers both branches")
	check(controller.reachable_ids().size() == 4, "everything reachable before moving")
	for pair: Array in [[0, 1], [0, 2], [1, 3], [2, 3]]:
		check(_line(pair[0] as int, pair[1] as int).visible, "edge %s visible at lap start" % str(pair))
	check(_line(0, 1).default_color == WorldMapController.HIGHLIGHT_COLOR,
			"edges from the token are highlighted")
	check(_line(1, 3).default_color == overlay.edge_color, "future edges keep the normal color")

func test_forward_move_and_edge_states() -> void:
	await controller.move_to(_node(1))
	check(run.current_node_id == 1, "token arrived at node 1")
	check(controller.token.position == _node(1).position, "token walked to the node position")
	check_impl(run.traveled == ([Vector3i(0, 1, 0)] as Array[Vector3i]),
			"history records the forward edge with the lap (Vector3i storage format)", str(run.traveled))
	check(_line(0, 1).default_color == WorldMapController.HISTORY_COLOR,
			"traveled edge shows the history color")
	check(not _line(0, 2).visible, "abandoned branch edge is removed from display")
	check(not _line(2, 3).visible, "edge only usable via the abandoned branch is removed")
	check(_line(1, 3).default_color == WorldMapController.HIGHLIGHT_COLOR,
			"the remaining path is highlighted")
	check(_ids(controller.next_nodes_of(_node(1))) == [3], "only the end remains reachable")

func test_reach_end() -> void:
	await controller.move_to(_node(3))
	check(run.current_node_id == 3, "token reached the end anchor")
	check(run.traveled.size() == 2 and run.traveled[1] == Vector3i(1, 3, 0),
			"second leg recorded")

func test_lap_flip_and_reverse_move() -> void:
	controller.on_lap_completed()
	check(run.lap == 1 and run.is_reversed(), "lap completion flips the direction")
	check(_ids(controller.next_nodes_of(_node(3))) == [1, 2],
			"reversed lap offers the forward-edge sources as next nodes")
	check(_line(0, 2).visible and _line(2, 3).visible,
			"per-lap edge removal fully resets on the new lap")
	check(_line(0, 1).default_color == WorldMapController.HISTORY_COLOR \
			and _line(1, 3).default_color == WorldMapController.HISTORY_COLOR,
			"traveled history stays colored across laps")
	await controller.move_to(_node(2))
	check(run.current_node_id == 2, "reverse move lands on the predecessor")
	check(controller.token.position == _node(2).position,
			"token walked the reversed edge curve to the node")
	check_impl(run.traveled[2] == Vector3i(2, 3, 1),
			"reverse travel is stored in forward-edge orientation", str(run.traveled))
	check(_ids(controller.next_nodes_of(_node(2))) == [0], "next step heads to the old start")
	check(not _line(0, 1).visible or _line(0, 1).default_color == WorldMapController.HISTORY_COLOR,
			"unreachable-but-traveled edges keep their history color")

# Runs after test_lap_flip_and_reverse_move: reversed lap, token on node 2, next = [0].
func test_keyboard_selection() -> void:
	var hovered: Array[WorldGraphNode] = []
	controller.node_hovered.connect(func(n: WorldGraphNode) -> void: hovered.append(n))
	controller._kb_cycle(1)
	check(controller._kb_selected() == _node(0), "keyboard cycle selects the next node")
	check(hovered.size() == 1 and hovered[0] == _node(0),
			"keyboard selection emits node_hovered (drives the info panel)")
	controller._kb_cycle(1)
	check(controller._kb_selected() == _node(0), "cycling wraps around the option list")
	controller._kb_cycle(-1)
	check(controller._kb_selected() == _node(0), "cycling backwards also wraps")
	await controller.move_to(controller._kb_selected())
	check(run.current_node_id == 0, "accepting the keyboard selection travels there")
	check(controller._kb_index == -1, "keyboard selection resets after travelling")
