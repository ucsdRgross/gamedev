extends Node2D

## First-run example for the worldgen addon: builds a WorldMap2D + camera + HUD in code and
## wires up every entry point. Run the scene (examples/demo.tscn) and use the keys:
##   G  Generate (current params, current seed)
##   R  Randomize + Generate (roll new params from the ranges bundle)
##   B  Bake to files (composite/land/water/exr/graph.json in bake_directory)
##   L  Reload from the last bake (simulates loading a saved world)
##   T  print a token walk (start -> end) to the Output
##   wheel / +/-  zoom
##
## Everything here is ordinary API a game would call; nothing is editor-only.

const BAKE_DIR := "user://worldgen_demo_bake"

var map: WorldMap2D
var cam: Camera2D
var hud: Label

func _ready() -> void:
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_build_hud()

	# Build + connect the map BEFORE adding it to the tree, so its own _ready() (which starts
	# generate_on_ready) fires with our signal handlers + HUD already in place.
	map = WorldMap2D.new()
	map.world_seed = 0             # 0 = random terrain each launch; set non-zero to pin
	map.bake_directory = BAKE_DIR  # where B/L read+write
	map.show_loading_screen = false  # this demo drives its OWN loading UI from the signals
	map.generation_started.connect(func(): _set_hud("Generating…"))
	map.generation_progress.connect(func(stage: String, frac: float): _set_hud("%s  %d%%" % [stage, int(frac * 100.0)]))
	map.generation_finished.connect(_on_finished)
	add_child(map)

func _on_finished() -> void:
	_fit_camera()
	_set_hud("seed %d — [G]enerate [R]andomize [B]ake [L]oad [T]oken-walk" % map.settings.main_seed)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_G: map.generate()
			KEY_R: map.randomize_and_generate()
			KEY_B:
				map.bake_to_files()
				_set_hud("baked to %s" % BAKE_DIR)
			KEY_L:
				map.reload_from_bake()
				_fit_camera()
				_set_hud("reloaded baked map from %s" % BAKE_DIR)
			KEY_T: _walk()
			KEY_EQUAL, KEY_KP_ADD: cam.zoom *= 1.2
			KEY_MINUS, KEY_KP_SUBTRACT: cam.zoom /= 1.2
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: cam.zoom *= 1.1
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam.zoom /= 1.1

## Walk the DAG start -> end (first forward edge each hop) and print each step.
func _walk() -> void:
	var ov := map.overlay()
	var n := ov.start_node()
	if n == null:
		print("[Demo] no graph to walk.")
		return
	var hops := 0
	print("[Demo] token walk start(%d) -> end(%d):" % [ov.start_node().id, ov.end_node().id])
	while n != null and not n.is_end and hops < 500:
		var nexts := n.next_nodes()
		if nexts.is_empty():
			break
		var nxt: WorldGraphNode = nexts[0]
		print("  %d -> %d  [%s]  %d pts" % [n.id, nxt.id, "ferry" if n.is_ferry_to(nxt) else "land", n.edge_to(nxt).size()])
		n = nxt
		hops += 1
	print("[Demo] %s in %d hops." % ["reached end" if (n != null and n.is_end) else "stopped", hops])

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(12, 10)
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(hud)
	_set_hud("starting…")

func _set_hud(text: String) -> void:
	if hud != null:
		hud.text = "WorldMap2D demo — " + text

func _fit_camera() -> void:
	var size := Vector2(map.settings.map_width, map.settings.map_height)
	var vp := get_viewport_rect().size
	cam.zoom = Vector2.ONE * minf(vp.x / size.x, vp.y / size.y) * 0.9
