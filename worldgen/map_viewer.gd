@tool
extends Node3D

## 3D step viewer for the worldgen pipeline. Renders any single generation step as
## a stack of `resolution` extruded MapSlice layers (terraced terrain), with an
## optional parallel water stack (rivers + lakes) and an ocean plane.
##
## Hybrid run mode: the tool buttons drive generation at edit-time (so settings can
## be recorded without pressing Play); the same node also runs at play-time with an
## orbit camera + sky. Self-contained so Plan 2 can host two of these under one
## external camera (set manage_camera = false).

const MAP_SLICE := preload("uid://dog1nnckhxf65")

## Stops after this pipeline step. Ordinals mirror WorldGenerator.GenStep
## (CITIES == CIVILIZATIONS), so view_step casts straight to it.
enum ViewStep { LANDMASS, TECTONICS, PEAKS, EROSION, RIVERS, CLIMATE, CITIES, GRAPH }

## Per-step folder name + default snapshot/paint kind + water source snapshot.
const STEP_INFO := [
	{"name": "Landmass", "snap": "Landmass", "kind": "topo", "water": ""},
	{"name": "Tectonics", "snap": "Tectonics_Debug", "kind": "tectonics", "water": ""},
	{"name": "Peaks", "snap": "PeaksAndValleys", "kind": "topo", "water": ""},
	{"name": "Erosion", "snap": "Erosion", "kind": "topo", "water": ""},
	{"name": "Rivers", "snap": "Rivers_Only", "kind": "topo", "water": "Rivers_Only"},
	{"name": "Climate", "snap": "Climate", "kind": "biome", "water": "Rivers_Only"},
	{"name": "Cities", "snap": "Climate", "kind": "biome", "water": "Rivers_Only"},
	{"name": "Graph", "snap": "Climate", "kind": "graph", "water": "Rivers_Only"},
]

# --- tool buttons -------------------------------------------------------------
@export_tool_button("Rebuild mesh", "Callable") var _btn_rebuild = rebuild_map
@export_tool_button("Generate view", "Callable") var _btn_generate = generate_view
@export_tool_button("Randomize + Rebuild", "Callable") var _btn_randomize = randomize_and_regenerate
@export_tool_button("Save settings", "Callable") var _btn_save = save_current_preset
@export_tool_button("Process folder -> ranges", "Callable") var _btn_process = process_ranges

# --- generation / view config -------------------------------------------------
@export var settings: WorldSettings
@export var view_step: ViewStep = ViewStep.CLIMATE
## "auto" = the step's default paint kind; otherwise force one.
@export_enum("auto", "topo", "biome", "biome_river", "mono", "graph", "tectonics")
var terrain_kind: String = "auto"
@export var show_water: bool = true

# --- 3D layout ----------------------------------------------------------------
@export var resolution: int = 100
## Viewer cube is 1 x cube_height_ratio x 1; lower this to squish vertically.
@export var cube_height_ratio: float = 1.0
## Multiplies the 1px base flare each slice uses to refill the trim above it.
@export var edge_flare: float = 1.0

# --- camera (play mode, standalone only) --------------------------------------
@export var manage_camera: bool = true
@export var min_zoom: float = 1.0
@export var max_zoom: float = 8.0

# --- cached images (re-meshed instantly by Rebuild) ---------------------------
@export var heightmap: Image
@export var colored_map: Image
@export var water_heightmap: Image
@export var water_colored_map: Image

var _gen: WorldGenerator
var _painter: WorldViewer
var _zoom_distance: float = 3.0
var _dragging: bool = false

func _ready() -> void:
	_ensure_groups()
	if Engine.is_editor_hint():
		rebuild_map()  # re-mesh whatever images are cached; generation is on a button
		return
	if manage_camera:
		_setup_environment()
	# Standalone runtime: generate a (random, if unconfigured) map on launch.
	if colored_map == null:
		if settings == null:
			settings = WorldSettings.new()
			_apply_random_settings()
		await regenerate()
	else:
		rebuild_map()

# =============================================================================
# GENERATION PIPELINE
# =============================================================================
func generate_view() -> void:
	await regenerate()

func randomize_and_regenerate() -> void:
	if settings == null:
		settings = WorldSettings.new()
	_apply_random_settings()
	await regenerate()

## Run the pipeline up to view_step, paint the 4 images, then mesh them.
func regenerate() -> void:
	if settings == null:
		settings = WorldSettings.new()
	var gen := _make_worker()
	print("[MapViewer] generating up to %s (seed %d)..." % [_step().name, settings.main_seed])
	await gen.generate_up_to(view_step as int)
	_paint_from(gen)
	rebuild_map()
	print("[MapViewer] generation complete.")

# A fresh worker generator each run (its SubViewports are sized to the settings).
func _make_worker() -> WorldGenerator:
	if _gen and is_instance_valid(_gen):
		_gen.queue_free()
	_gen = WorldGenerator.new()
	_gen.name = "GenWorker"
	_gen.settings = settings
	add_child(_gen)
	return _gen

func _painter_for(gen: WorldGenerator) -> WorldViewer:
	if _painter == null:
		_painter = WorldViewer.new()  # never entered into the tree; used for its painters
	_painter.generator = gen
	return _painter

func _paint_from(gen: WorldGenerator) -> void:
	var info := _step()
	var painter := _painter_for(gen)
	var n := gen.settings.map_width  # project maps are square

	var cimg := Image.create(n, n, false, Image.FORMAT_RGBA8)
	painter._paint_cell(cimg, _kind(), info.snap, Vector2i.ZERO, n)
	colored_map = cimg
	heightmap = _height_image(gen, info.snap, "height")

	if info.water != "" and gen.snapshots.has(info.water):
		water_colored_map = painter.water_only_image()
		water_heightmap = _height_image(gen, info.water, "water_surface")
	else:
		water_colored_map = null
		water_heightmap = null

## Pack a snapshot float field into an RGBAH texture image (R = height, matching
## the generator's height_texture() convention; GL-compat safe). NO_WATER -> 0.
func _height_image(gen: WorldGenerator, snap: String, field: String) -> Image:
	var n := gen.settings.map_width
	var img := Image.create(n, n, false, Image.FORMAT_RGBAH)
	var data: Dictionary = gen.snapshots.get(snap, {})
	var src: PackedFloat32Array = data.get(field, PackedFloat32Array())
	if src.is_empty():
		return img
	for y in range(n):
		for x in range(n):
			img.set_pixel(x, y, Color(maxf(src[(y * n) + x], 0.0), 0.0, 0.0, 1.0))
	return img

# =============================================================================
# MESHING
# =============================================================================
## Rebuild both slice stacks from the cached images (no generation).
func rebuild_map() -> void:
	_ensure_groups()
	_clear_group($Terrain)
	_clear_group($Water)
	if colored_map == null:
		return

	var color_t := ImageTexture.create_from_image(colored_map)
	var height_t: Texture2D = ImageTexture.create_from_image(heightmap) if heightmap else null
	for i in range(resolution):
		_spawn_slice($Terrain, i, height_t, color_t)

	if show_water and water_colored_map != null:
		var wc := ImageTexture.create_from_image(water_colored_map)
		var wh: Texture2D = ImageTexture.create_from_image(water_heightmap) if water_heightmap else null
		for i in range(resolution):
			_spawn_slice($Water, i, wh, wc)

	_update_ocean()

func _spawn_slice(group: Node3D, i: int, height_t: Texture2D, color_t: Texture2D) -> void:
	var s := MAP_SLICE.instantiate()
	group.add_child(s)
	var thickness := cube_height_ratio / float(maxi(1, resolution))
	# Slice thin along local Z (its image faces +-Z); positioned along local Z. The
	# parent group is rotated so local Z becomes world up (see _ensure_groups).
	var z := (float(i) + 0.5) * thickness - cube_height_ratio * 0.5
	s.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1, thickness)), Vector3(0, 0, z))
	s.edge_flare = edge_flare
	s.height = i
	s.total_slices = resolution
	s.heightmap_tex = height_t
	s.color_tex = color_t  # set last: triggers the slice's update() with all fields set

func _ensure_groups() -> void:
	for gname in ["Terrain", "Water"]:
		if not has_node(gname):
			var g := Node3D.new()
			g.name = gname
			# Stand the stack up: local +Z (slice image / stack axis) -> world +Y.
			g.transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)), Vector3.ZERO)
			add_child(g)

func _clear_group(group: Node3D) -> void:
	for c in group.get_children():
		c.queue_free()

func _update_ocean() -> void:
	var ocean := get_node_or_null("Ocean") as MeshInstance3D
	if settings == null:
		if ocean: ocean.visible = false
		return
	if ocean == null:
		ocean = MeshInstance3D.new()
		ocean.name = "Ocean"
		ocean.mesh = PlaneMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.10, 0.21, 0.36, 0.65)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ocean.material_override = mat
		add_child(ocean)
	(ocean.mesh as PlaneMesh).size = Vector2(1, 1)
	ocean.position = Vector3(0, settings.ocean_threshold * cube_height_ratio - cube_height_ratio * 0.5, 0)
	ocean.visible = show_water

# =============================================================================
# RECORDING (settings presets + ranges)
# =============================================================================
func _apply_random_settings() -> void:
	var ranges := PresetIO.load_step_ranges(_step().name)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	settings.main_seed = rng.randi() % 1000000
	for pname in ranges:
		var r: Array = ranges[pname]
		var v := rng.randf_range(r[0], r[1])
		settings.set(pname, int(round(v)) if r[2] else v)

func save_current_preset() -> void:
	if settings == null:
		push_warning("[MapViewer] no settings to save")
		return
	var stem := PresetIO.save_preset(settings, _step().name)
	if stem != "":
		print("[MapViewer] saved preset: %s.tres / .json" % stem)

func process_ranges() -> void:
	var env := PresetIO.process_step_ranges(_step().name)
	print("[MapViewer] ranges for '%s': %s" % [_step().name, env])

# =============================================================================
# CAMERA / ENVIRONMENT (runtime, standalone)
# =============================================================================
func _setup_environment() -> void:
	if has_node("ViewerEnv"):
		return
	var we := WorldEnvironment.new()
	we.name = "ViewerEnv"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "ViewerSun"
	sun.rotation_degrees = Vector3(-50, -40, 0)
	add_child(sun)

	var pivot := Node3D.new()
	pivot.name = "CameraRig"
	pivot.rotation_degrees = Vector3(-35, 0, 0)
	add_child(pivot)
	var cam := Camera3D.new()
	cam.name = "ViewerCamera"
	_zoom_distance = clampf(3.0, min_zoom, max_zoom)
	cam.position = Vector3(0, 0, _zoom_distance)
	pivot.add_child(cam)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not manage_camera:
		return
	var pivot := get_node_or_null("CameraRig") as Node3D
	if pivot == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_distance = clampf(_zoom_distance - 0.2, min_zoom, max_zoom)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_distance = clampf(_zoom_distance + 0.2, min_zoom, max_zoom)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		pivot.rotation.y -= event.relative.x * 0.01
		pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * 0.01, -1.45, 0.2)

func _apply_zoom() -> void:
	var cam := get_node_or_null("CameraRig/ViewerCamera") as Camera3D
	if cam:
		cam.position = Vector3(0, 0, _zoom_distance)

# =============================================================================
# HELPERS
# =============================================================================
func _step() -> Dictionary:
	return STEP_INFO[view_step]

func _kind() -> String:
	return _step().kind if terrain_kind == "auto" else terrain_kind
