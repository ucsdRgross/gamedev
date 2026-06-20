@tool
extends Node3D

## 3D step viewer for the worldgen pipeline. Renders the chosen generation step as
## a heightmap-displaced plane (terrain) plus a separate displaced plane for inland
## water (rivers + lakes) and a flat ocean plane. The lights/camera/sky/meshes live
## as real nodes in map_viewer.tscn so they are editable in the inspector; this
## script only drives generation, paints the colormap/heightmap images, and feeds
## them to the materials.
##
## Hybrid run mode: the tool buttons (and changing view_step) regenerate at
## edit-time, so settings can be recorded without pressing Play. The same node also
## runs at play-time with an orbit camera. Self-contained, so Plan 2 can host two of
## these (set manage_camera = false and frame both with an external camera).

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
@export_tool_button("Generate view", "Callable") var _btn_generate = generate_view
@export_tool_button("Randomize + Generate", "Callable") var _btn_randomize = randomize_and_regenerate
@export_tool_button("Save settings", "Callable") var _btn_save = save_current_preset
@export_tool_button("Process folder -> ranges", "Callable") var _btn_process = process_ranges

# --- generation / view config -------------------------------------------------
@export var settings: WorldSettings
@export var view_step: ViewStep = ViewStep.CLIMATE:
	set(v):
		view_step = v
		_request_regen()
## "auto" = the step's default paint kind; otherwise force one.
@export_enum("auto", "topo", "biome", "biome_river", "mono", "graph", "tectonics")
var terrain_kind: String = "auto":
	set(v):
		terrain_kind = v
		_request_repaint()
@export var show_water: bool = true:
	set(v):
		show_water = v
		if is_node_ready():
			_apply_to_meshes()
## When true, changing view_step / terrain_kind regenerates automatically at edit-time.
@export var auto_regenerate: bool = true

# --- 3D layout ----------------------------------------------------------------
## Plane subdivisions = displacement detail (verts per axis).
@export var resolution: int = 200:
	set(v):
		resolution = maxi(1, v)
		if is_node_ready():
			_apply_to_meshes()
## Vertical scale: world height of one unit of map height. Terrain is a thin slab,
## not a cube -- real DEMs have tiny vertical:horizontal ratios, so values around
## 0.05-0.2 read best on the 1x1 plane (a peak at height ~2 then rises ~0.1-0.4).
@export var cube_height_ratio: float = 0.12:
	set(v):
		cube_height_ratio = v
		if is_node_ready():
			_apply_to_meshes()
## Subtracted from height before scaling (raise toward ocean_threshold to flatten sea).
@export var sea_level: float = 0.0:
	set(v):
		sea_level = v
		if is_node_ready():
			_apply_to_meshes()
## Extra exaggeration of land relief (makes flattened peaks read better).
@export var relief_gain: float = 1.0:
	set(v):
		relief_gain = v
		if is_node_ready():
			_apply_to_meshes()

# --- camera (play mode) -------------------------------------------------------
@export var manage_camera: bool = true
@export var min_zoom: float = 0.6
@export var max_zoom: float = 6.0

# --- cached images (re-applied instantly without regenerating) -----------------
@export var heightmap: Image
@export var colored_map: Image
@export var water_heightmap: Image
@export var water_colored_map: Image

var _gen: WorldGenerator
var _painter: WorldViewer
var _zoom_distance: float = 2.0
var _dragging: bool = false
var _regen_pending: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_to_meshes()  # re-mesh whatever images are cached; gen is on a button / view_step
		return
	var cam := get_node_or_null("CameraRig/Camera3D") as Camera3D
	if cam:
		_zoom_distance = cam.position.z
	if colored_map == null:
		if settings == null:
			settings = WorldSettings.new()
			_apply_random_settings()
		await regenerate()
	else:
		_apply_to_meshes()

# =============================================================================
# GENERATION
# =============================================================================
func generate_view() -> void:
	await regenerate()

func randomize_and_regenerate() -> void:
	if settings == null:
		settings = WorldSettings.new()
	_apply_random_settings()
	await regenerate()

## Run the pipeline up to view_step, paint the 4 images, then push to the meshes.
func regenerate() -> void:
	if settings == null:
		settings = WorldSettings.new()
	var gen := _worker()
	print("[MapViewer] generating up to %s (seed %d)..." % [_step().name, settings.main_seed])
	await gen.generate_up_to(view_step as int)
	print("[MapViewer]   snapshots: ", gen.snapshots.keys())
	_paint_from(gen)
	_apply_to_meshes()
	print("[MapViewer] done (%s / %s)." % [_step().name, _kind()])

# Reuse one worker generator (its SubViewports persist between runs).
func _worker() -> WorldGenerator:
	if _gen == null or not is_instance_valid(_gen):
		_gen = WorldGenerator.new()
		_gen.name = "GenWorker"
		_gen.settings = settings
		add_child(_gen)
	_gen.settings = settings
	return _gen

func _painter_for(gen: WorldGenerator) -> WorldViewer:
	if _painter == null:
		_painter = WorldViewer.new()  # never entered into the tree; used only for its painters
	_painter.generator = gen
	return _painter

func _paint_from(gen: WorldGenerator) -> void:
	var info := _step()
	var painter := _painter_for(gen)
	var n := gen.settings.map_width  # project maps are square

	if not gen.snapshots.has(info.snap):
		push_warning("[MapViewer] snapshot '%s' missing; nothing to paint" % info.snap)
		return
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

## Pack a snapshot float field into an RGBAH image (R = height; GL-compat safe).
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
# MESH UPDATE (no generation -- just push cached images to the materials)
# =============================================================================
func _apply_to_meshes() -> void:
	var terrain := get_node_or_null("Terrain") as MeshInstance3D
	var water := get_node_or_null("Water") as MeshInstance3D
	if terrain == null:
		return
	if colored_map == null:
		terrain.visible = false
		if water: water.visible = false
		return
	terrain.visible = true

	var w := colored_map.get_width()
	var h := colored_map.get_height()
	var size := Vector2(1.0, float(h) / float(w))
	var sw := maxi(1, resolution)
	var sd := maxi(1, int(round(resolution * size.y)))

	var ct := ImageTexture.create_from_image(colored_map)
	var ht: Texture2D = ImageTexture.create_from_image(heightmap) if heightmap else null
	_setup_plane(terrain, size, sw, sd, ht, ct)
	_set_disp_params(terrain.material_override as ShaderMaterial, size, sw, sd)

	var has_water := show_water and water != null and water_colored_map != null
	if water:
		water.visible = has_water
	if has_water:
		var wct := ImageTexture.create_from_image(water_colored_map)
		var wht: Texture2D = ImageTexture.create_from_image(water_heightmap) if water_heightmap else null
		_setup_plane(water, size, sw, sd, wht, wct)
		_set_disp_params(water.material_override as ShaderMaterial, size, sw, sd)

	_update_ocean(size)

func _setup_plane(mi: MeshInstance3D, size: Vector2, sw: int, sd: int, height_t: Texture2D, color_t: Texture2D) -> void:
	var pm := mi.mesh as PlaneMesh
	if pm:
		pm.size = size
		pm.subdivide_width = sw
		pm.subdivide_depth = sd
	var mat := mi.material_override as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("color_map", color_t)
	if height_t:
		mat.set_shader_parameter("height_map", height_t)

func _set_disp_params(mat: ShaderMaterial, size: Vector2, sw: int, sd: int) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("height_scale", cube_height_ratio)
	mat.set_shader_parameter("sea_level", sea_level)
	mat.set_shader_parameter("relief_gain", relief_gain)
	mat.set_shader_parameter("uv_texel", Vector2(1.0 / float(sw + 1), 1.0 / float(sd + 1)))
	mat.set_shader_parameter("xz_step", size.x / float(sw + 1))

func _update_ocean(size: Vector2) -> void:
	var ocean := get_node_or_null("Ocean") as MeshInstance3D
	if ocean == null:
		return
	if settings == null:
		ocean.visible = false
		return
	var pm := ocean.mesh as PlaneMesh
	if pm:
		pm.size = size
	var y := (settings.ocean_threshold - sea_level) * relief_gain * cube_height_ratio
	ocean.position = Vector3(0, maxf(y, 0.0), 0)
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
# CAMERA / INPUT (play mode)
# =============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not manage_camera:
		return
	var rig := get_node_or_null("CameraRig") as Node3D
	if rig == null:
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
		rig.rotation.y -= event.relative.x * 0.01
		rig.rotation.x = clampf(rig.rotation.x - event.relative.y * 0.01, -1.45, 0.2)

func _apply_zoom() -> void:
	var cam := get_node_or_null("CameraRig/Camera3D") as Camera3D
	if cam:
		cam.position = Vector3(0, 0, _zoom_distance)

# =============================================================================
# EDIT-TIME AUTO REGEN / REPAINT
# =============================================================================
func _request_regen() -> void:
	if not is_node_ready() or not auto_regenerate or not Engine.is_editor_hint():
		return
	if _regen_pending:
		return
	_regen_pending = true
	call_deferred("_deferred_regen")

func _deferred_regen() -> void:
	_regen_pending = false
	await regenerate()

# A terrain_kind change only needs a recolor from the existing worker snapshots.
func _request_repaint() -> void:
	if not is_node_ready() or not auto_regenerate or not Engine.is_editor_hint():
		return
	if _gen != null and is_instance_valid(_gen) and _gen.snapshots.has(_step().snap):
		_paint_from(_gen)
		_apply_to_meshes()
	else:
		_request_regen()

# =============================================================================
# HELPERS
# =============================================================================
func _step() -> Dictionary:
	return STEP_INFO[view_step]

func _kind() -> String:
	return _step().kind if terrain_kind == "auto" else terrain_kind
