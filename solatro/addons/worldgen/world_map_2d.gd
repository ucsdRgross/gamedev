@tool
class_name WorldMap2D
extends Node2D

## Drag-and-drop deliverable of the worldgen addon: a @tool Node2D that generates a
## static colorized 2D map (a centered Sprite2D) plus an interactive DAG overlay
## (WorldGraphOverlay: node markers + curved edges), all centered on this node's origin.
##
## Generate/Randomize/Bake/Export run at edit-time via the tool buttons; at runtime the
## node self-generates when `generate_on_ready` is on (else it loads a prior bake). The
## world is reproducible from `world_seed` (0 = fresh random each run). Generation is
## await-driven so the loading overlay animates during GPU steps; the CPU-heavy image
## painting offloads to WorkerThreadPool (threaded_paint) so it stays smooth there too.
##
## The generator worker, map sprite, and overlay are created in code WITHOUT an owner, so
## they are never serialized into the scene (keeps the .tscn tiny, like map_viewer).

# --- tool buttons -------------------------------------------------------------
@export_tool_button("Generate", "Callable") var _btn_generate = generate
## Reroll every step's params from the shipped ranges bundle (seeded by world_seed), then
## generate. Same world_seed -> identical world while the bundle is unchanged.
@export_tool_button("Randomize + Generate", "Callable") var _btn_randomize = randomize_and_generate
## Write composite/land/water PNGs + height.exr + graph.json to the bake directory.
@export_tool_button("Bake to files", "Callable") var _btn_bake = bake_to_files
## Write just the three layer PNGs (composite/land/water) -- land stacked over water == composite.
@export_tool_button("Export PNGs", "Callable") var _btn_pngs = export_pngs
## Write the 32-bit float heightmap as height.exr (editor-only; runtime warns + skips).
@export_tool_button("Export heightmap EXR", "Callable") var _btn_exr = export_heightmap_exr
## Re-run only the painting over the cached buffers: biome palette/deco/tint edits show in
## under a second without regenerating. Region SHAPES still need Generate.
@export_tool_button("Repaint biomes", "Callable") var _btn_repaint = repaint_biomes

# --- generation config --------------------------------------------------------
## All tunable pipeline parameters. Auto-created with defaults on first generate.
@export var settings: WorldSettings
## Land/water palette. Auto-created (topo defaults keyed to current thresholds) if unset;
## assign one and edit its `bands` to restyle the map.
@export var colorizer: WorldHeightColorizer
## Reproducibility handle. 0 = pick a fresh random seed on every generation; any non-zero
## value reproduces the same world (params + terrain) while the ranges bundle is unchanged.
@export var world_seed: int = 0
## Exploration floor for Randomize sampling (higher = explore the band more; lower = exploit
## confirmed-good clusters). Matches the map_viewer tuning knob.
@export var exploration_base: float = 1.0
## Runtime behavior: true = generate in _ready(); false = load a prior bake from bake_directory.
@export var generate_on_ready: bool = true
## Where Bake/Export write and baked mode loads. Empty = beside the saved scene (falls back
## to user://worldgen_bake/ if the scene is unsaved).
@export_dir var bake_directory: String = ""

@export_group("Overlay")
## Show the DAG overlay (node markers + edges) over the map.
@export var show_graph: bool = true
@export var node_radius: float = 6.0
@export var node_color: Color = Color("#f7fafc")
@export var start_color: Color = Color("#38a169")
@export var end_color: Color = Color("#e53e3e")
@export var edge_color: Color = Color("#2d3748")
@export var edge_width: float = 3.0
@export var ferry_color: Color = Color("#3182ce")
@export var ferry_width: float = 2.0
## Tint node markers by their biome's legend color (start/end keep their own
## colors). Off by default so custom marker art/colors stay untouched.
@export var tint_nodes_by_biome: bool = false
@export_subgroup("Custom art (optional)")
## Node markers: assign to replace the drawn discs with your own art (tinted by the colors
## above). Edge textures tile along the line; edge_gradient colors it along its length.
## Leave empty for the vector defaults, or connect graph_populated to restyle by hand.
@export var node_texture: Texture2D
@export var start_texture: Texture2D
@export var end_texture: Texture2D
@export var edge_texture: Texture2D
@export var ferry_texture: Texture2D
@export var edge_gradient: Gradient

@export_group("Loading")
## Offload the full-res image painting to a background thread so a loading overlay stays
## smooth during the heaviest CPU work. Turn off to paint synchronously (editor always is).
@export var threaded_paint: bool = true
## Show the built-in placeholder loading overlay at runtime. Replace it by connecting to the
## generation_started/progress/finished signals (and set this false to hide the default).
@export var show_loading_screen: bool = true

# --- signals (loading-screen / gameplay hooks) --------------------------------
signal generation_started
signal generation_progress(stage: String, fraction: float)
signal generation_finished

const _TOTAL_STEPS := 7  # pipeline length; drives the progress fraction.

# --- runtime state (never serialized) -----------------------------------------
var _gen: WorldGenerator
var _overlay: WorldGraphOverlay
var _loading: CanvasLayer
var _loading_label: Label
var _loading_spinner: Label
var _spin_t: float = 0.0
var _busy: bool = false
var _steps_done: int = 0
# Generated images + the final snapshot (kept out of @export vars: anti-.tscn-bloat).
var _composite_img: Image
var _land_img: Image
var _water_img: Image
var _snapshot: Dictionary = {}

func _ready() -> void:
	# _process only animates the loading spinner; stay off until an overlay shows.
	set_process(false)
	if Engine.is_editor_hint():
		return
	if not generate_on_ready:
		_load_baked()
		return
	# No seed provided -> random TERRAIN each launch, keeping the configured settings params
	# (Randomize + Generate is the explicit "roll new params" action). A pinned world_seed
	# reproduces the same world; generate() applies it.
	if world_seed == 0:
		_ensure_config()
		var r := RandomNumberGenerator.new()
		r.randomize()
		settings.main_seed = (r.randi() % 999999) + 1
	generate()

## Keep the loading spinner turning each frame (proves the main thread is free while the
## background paint runs). No-op in the editor / when no overlay is visible.
func _process(delta: float) -> void:
	if _loading == null or not _loading.visible or _loading_spinner == null:
		return
	_spin_t += delta
	var frames := "|/-\\"
	_loading_spinner.text = frames[int(_spin_t * 8.0) % frames.length()]

# =============================================================================
# GENERATION
# =============================================================================
## Regenerate with the CURRENT settings. Respects the seed you set: if world_seed is
## non-zero it pins settings.main_seed to it; if it is 0 the existing settings.main_seed is
## used as-is (Generate never rerolls a random seed -- that is Randomize's job).
func generate() -> void:
	_ensure_config()
	if world_seed != 0:
		settings.main_seed = world_seed
	await _run_generation()

## Roll every step's params from the ranges bundle, then generate. world_seed != 0 seeds the
## draw (reproducible); world_seed == 0 picks a fresh random world each press. randomize_all
## derives settings.main_seed from the same rng, so the terrain matches the roll.
func randomize_and_generate() -> void:
	_ensure_config()
	var rng := RandomNumberGenerator.new()
	if world_seed != 0:
		rng.seed = world_seed
	else:
		rng.randomize()
	WorldRandomizer.randomize_all(settings, rng, exploration_base, WorldRandomizer.load_bundle())
	await _run_generation()

## Shared driver: run the pipeline, paint the layers (threaded off the main thread when
## enabled), push the composite to the map sprite, and (re)populate the graph overlay.
func _run_generation() -> void:
	if _busy:
		return
	_busy = true
	_steps_done = 0
	_show_loading("Generating world…")
	generation_started.emit()

	var gen := _worker()
	await gen.generate_world_map()

	var snap := gen.final_snapshot()
	_snapshot = gen.snapshots.get(snap, {})
	generation_progress.emit("Painting", 0.95)
	_set_loading_text("Painting map…")
	var w := settings.map_width
	var h := settings.map_height
	var bset := settings.active_biome_set()
	await _paint_layers(_snapshot, w, h, settings.ocean_threshold, _active_colorizer(),
		bset, _deco_ctx(bset, gen.graph_export))
	_apply_map_texture()

	if show_graph:
		_push_overlay_style()
		_overlay_node().populate(gen.graph_export, Vector2(w, h))
	elif _overlay != null:
		_overlay.populate({}, Vector2(w, h))

	generation_progress.emit("Done", 1.0)
	_hide_loading()
	generation_finished.emit()
	_busy = false

## Paint composite/land/water. Threaded (WorkerThreadPool) at runtime when threaded_paint is
## on, so the loading overlay keeps animating; synchronous in the editor / when off.
func _paint_layers(data: Dictionary, w: int, h: int, oth: float, col: WorldHeightColorizer,
		bset: WorldBiomeSet = null, deco: Dictionary = {}) -> void:
	if threaded_paint and not Engine.is_editor_hint():
		var tid := WorkerThreadPool.add_task(_paint_task.bind(data, w, h, oth, col, bset, deco), true, "worldmap_paint")
		while not WorkerThreadPool.is_task_completed(tid):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(tid)
	else:
		_paint_task(data, w, h, oth, col, bset, deco)

## The actual per-pixel painting (runs on a worker thread when threaded). Touches only
## PackedArray/Image data -- no scene tree / RenderingServer -- so it is thread-safe
## (deco texture Images were prefetched on the main thread by _deco_ctx). Land paints,
## decorations stamp into it, water paints, and the composite is their exact merge
## (water over land) -- which drops the third full per-pixel classifier pass.
func _paint_task(data: Dictionary, w: int, h: int, oth: float, col: WorldHeightColorizer,
		bset: WorldBiomeSet = null, deco: Dictionary = {}) -> void:
	_land_img = WorldMapPainter.land_only_image(data, w, h, oth, col, bset)
	if not deco.is_empty():
		WorldBiomeDeco.scatter(_land_img, data, w, h, oth, bset, deco)
	_water_img = WorldMapPainter.water_only_image(data, w, h, oth, col, true)
	_composite_img = WorldMapPainter.merge_layers(_land_img, _water_img)

## MAIN THREAD: everything the deco scatter needs that is not thread-safe to fetch on the
## paint worker -- texture Images (RenderingServer), node positions (clearance), knobs.
func _deco_ctx(bset: WorldBiomeSet, graph_export: Dictionary) -> Dictionary:
	var nodes := PackedVector2Array()
	for nd in graph_export.get("nodes", []):
		nodes.append(nd["pos"])
	return {"images": WorldBiomeDeco.prepare_images(bset),
		"mul": settings.biome_deco_density_mul,
		"seed": settings.main_seed + settings.biome_seed_offset, "nodes": nodes}

## Ensure settings + colorizer exist (auto-created with defaults).
func _ensure_config() -> void:
	if settings == null:
		settings = WorldSettings.new()
	if colorizer == null:
		colorizer = WorldHeightColorizer.make_default(settings.ocean_threshold, settings.mountain_threshold)

## The palette to paint with: the assigned colorizer when it has bands, else a fresh
## default keyed to the current ocean/mountain thresholds.
func _active_colorizer() -> WorldHeightColorizer:
	if colorizer != null and not colorizer.bands.is_empty():
		return colorizer
	return WorldHeightColorizer.make_default(settings.ocean_threshold, settings.mountain_threshold)

# Reuse one generator worker (its SubViewports persist and need the scene tree). Connect
# the per-step signal once so generation progress drives the loading overlay.
func _worker() -> WorldGenerator:
	if _gen == null or not is_instance_valid(_gen):
		_gen = WorldGenerator.new()
		_gen.name = "GenWorker"
		_gen.settings = settings  # assign before add_child so its _ready sees real settings
		add_child(_gen)
	_gen.settings = settings
	# Thread the pure-CPU steps (Rivers/Graph) at runtime so the loading overlay animates
	# through them; the editor stays synchronous (tool-button generate is a one-off).
	_gen.thread_cpu_steps = threaded_paint and not Engine.is_editor_hint()
	if not _gen.generation_step_finished.is_connected(_on_step_finished):
		_gen.generation_step_finished.connect(_on_step_finished)
	if not _gen.generation_step_started.is_connected(_on_step_started):
		_gen.generation_step_started.connect(_on_step_started)
	return _gen

# Friendly step labels (snapshot names -> what the player sees) for the loading overlay.
const _STEP_LABELS := {
	"Landmass": "Shaping landmasses", "Tectonics": "Colliding plates",
	"PeaksAndValleys": "Raising mountains", "Erosion": "Eroding terrain",
	"Rivers_Only": "Carving rivers & lakes", "Graph": "Routing paths",
	"Biomes": "Painting biomes",
}

# Name the step that is about to run (so the label tracks the CURRENT step, not the last
# finished one -- Rivers/Graph take a while and would otherwise read "Erosion").
func _on_step_started(step_name: String) -> void:
	_set_loading_text(_STEP_LABELS.get(step_name, step_name))

# Advance the progress fraction as each step reports done (the final "All_Steps_Grid"
# bridge is ignored; painting owns the last 5%).
func _on_step_finished(step_name: String) -> void:
	if step_name == "All_Steps_Grid":
		return
	_steps_done += 1
	generation_progress.emit(step_name, clampf(float(_steps_done) / float(_TOTAL_STEPS), 0.0, 0.9))

func _apply_map_texture() -> void:
	if _composite_img == null:
		return
	_map_sprite().texture = ImageTexture.create_from_image(_composite_img)

func _map_sprite() -> Sprite2D:
	var s := get_node_or_null("Map") as Sprite2D
	if s == null:
		s = Sprite2D.new()
		s.name = "Map"
		s.centered = true  # origin-centered map
		add_child(s)
	return s

func _overlay_node() -> WorldGraphOverlay:
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = get_node_or_null("GraphOverlay") as WorldGraphOverlay
		if _overlay == null:
			_overlay = WorldGraphOverlay.new()
			_overlay.name = "GraphOverlay"
			add_child(_overlay)
	return _overlay

# Push the inspector display exports onto the overlay before it populates.
func _push_overlay_style() -> void:
	var o := _overlay_node()
	o.node_radius = node_radius
	o.node_color = node_color
	o.start_color = start_color
	o.end_color = end_color
	o.edge_color = edge_color
	o.edge_width = edge_width
	o.ferry_color = ferry_color
	o.ferry_width = ferry_width
	o.tint_by_biome = tint_nodes_by_biome
	o.node_texture = node_texture
	o.start_texture = start_texture
	o.end_texture = end_texture
	o.edge_texture = edge_texture
	o.ferry_texture = ferry_texture
	o.edge_gradient = edge_gradient

# =============================================================================
# COORDINATES
# =============================================================================
## Map pixel -> this node's local space (origin = map centre).
func map_to_local(p: Vector2) -> Vector2:
	return p - _map_size() * 0.5

## Local space -> map pixel.
func local_to_map(p: Vector2) -> Vector2:
	return p + _map_size() * 0.5

func _map_size() -> Vector2:
	if _composite_img != null:
		return Vector2(_composite_img.get_width(), _composite_img.get_height())
	return Vector2(settings.map_width, settings.map_height) if settings else Vector2.ZERO

# =============================================================================
# LOADING OVERLAY (runtime placeholder; replaceable via signals)
# =============================================================================
func _show_loading(text: String) -> void:
	if Engine.is_editor_hint() or not show_loading_screen:
		return
	if _loading == null:
		_loading = CanvasLayer.new()
		_loading.layer = 128
		var bg := ColorRect.new()
		bg.color = Color(0.06, 0.07, 0.09, 0.9)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		_loading.add_child(bg)
		_loading_spinner = Label.new()
		_loading_spinner.set_anchors_preset(Control.PRESET_CENTER)
		_loading_spinner.position = Vector2(0, -24)
		_loading_spinner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading.add_child(_loading_spinner)
		_loading_label = Label.new()
		_loading_label.set_anchors_preset(Control.PRESET_CENTER)
		_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading.add_child(_loading_label)
		add_child(_loading)
	_loading.visible = true
	set_process(true)  # spinner ticks only while the overlay is up
	_set_loading_text(text)

func _set_loading_text(text: String) -> void:
	if _loading_label != null:
		_loading_label.text = text

func _hide_loading() -> void:
	set_process(false)
	if _loading != null:
		_loading.visible = false

# =============================================================================
# BAKE / EXPORT / LOAD
# =============================================================================
## Write every layer (composite/land/water PNG + height.exr + graph.json) to the bake dir.
func bake_to_files() -> void:
	var dir := _bake_dir()
	if not _images_ready("Bake"):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_save_pngs(dir)
	_save_exr(dir)
	_save_graph(dir)
	print("[WorldMap2D] baked to %s" % dir)

## Write just the three layer PNGs (for the land-over-water == composite check).
func export_pngs() -> void:
	if not _images_ready("Export PNGs"):
		return
	var dir := _bake_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_save_pngs(dir)
	print("[WorldMap2D] exported PNGs to %s" % dir)

## Write the heightmap as 32-bit float EXR (editor-only; TinyEXR is absent from templates).
func export_heightmap_exr() -> void:
	if not _images_ready("Export EXR"):
		return
	var dir := _bake_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_save_exr(dir)

func _save_pngs(dir: String) -> void:
	_composite_img.save_png(dir.path_join("composite.png"))
	_land_img.save_png(dir.path_join("land.png"))
	_water_img.save_png(dir.path_join("water.png"))

func _save_exr(dir: String) -> void:
	if Engine.is_editor_hint():
		var w := settings.map_width
		var h := settings.map_height
		var img := WorldMapPainter.height_image_rf(_snapshot, w, h)
		img.save_exr(dir.path_join("height.exr"), true)
	else:
		push_warning("[WorldMap2D] EXR export is editor-only (TinyEXR absent from export templates); skipped.")

func _save_graph(dir: String) -> void:
	var f := FileAccess.open(dir.path_join("graph.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_graph_to_json(_worker().graph_export), "  "))
		f.close()

## Public: (re)load the map + graph from a prior bake in the bake directory. Use for
## "resume saved world" flows (see generate_on_ready = false).
func reload_from_bake() -> void:
	_load_baked()

## Free the generation worker (and its SubViewports) plus the loading overlay once you
## are done generating for this session — e.g. right after bake_to_files() in a
## generate-once-then-reload flow. A later generate() recreates both on demand.
## NOTE: bake_to_files()/_save_graph() read the worker's graph_export, so always bake
## BEFORE releasing.
func release_generator() -> void:
	if _gen != null and is_instance_valid(_gen):
		_gen.queue_free()
		_gen = null
	if _loading != null and is_instance_valid(_loading):
		set_process(false)
		_loading.queue_free()
		_loading = null
		_loading_label = null
		_loading_spinner = null

# Baked mode: load composite.png (+ graph.json) from the bake dir instead of generating.
func _load_baked() -> void:
	var dir := _bake_dir()
	var cpath := dir.path_join("composite.png")
	if not FileAccess.file_exists(cpath):
		push_warning("[WorldMap2D] baked composite not found: %s (generate + bake first?)" % cpath)
		return
	_composite_img = Image.load_from_file(cpath)
	_apply_map_texture()
	var gpath := dir.path_join("graph.json")
	if show_graph and FileAccess.file_exists(gpath):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(gpath))
		if typeof(parsed) == TYPE_DICTIONARY:
			_push_overlay_style()
			var size := Vector2(_composite_img.get_width(), _composite_img.get_height())
			_overlay_node().populate(_graph_from_json(parsed), size)

# Bake target: the explicit bake_directory if set, else the addon's own exports folder.
# NOTE: res:// is read-only in exported builds, so set bake_directory to a user:// path
# for runtime baking/saving (the editor tool buttons write res:// fine).
const DEFAULT_EXPORT_DIR := "res://addons/worldgen/exports"
func _bake_dir() -> String:
	return bake_directory if bake_directory != "" else DEFAULT_EXPORT_DIR

func _images_ready(action: String) -> bool:
	if _composite_img == null:
		push_warning("[WorldMap2D] %s: no map generated yet (press Generate first)." % action)
		return false
	return true

# --- graph.json (de)serialization (Vector2 / PackedVector2Array are not JSON-native) ---
func _graph_to_json(export: Dictionary) -> Dictionary:
	var nodes: Array = []
	for nd in export.get("nodes", []):
		var outs: Array = []
		for e in nd.get("out", []):
			var pts: Array = []
			for p in (e["points"] as PackedVector2Array):
				pts.append([p.x, p.y])
			outs.append({"to": e["to"], "ferry": e["ferry"], "points": pts})
		var pos: Vector2 = nd["pos"]
		nodes.append({
			"id": nd["id"], "pos": [pos.x, pos.y], "depth": nd["depth"],
			"landmass": nd["landmass"], "height": nd["height"],
			"biome": nd.get("biome", -1), "out": outs,
		})
	return {
		"version": 2, "start": export.get("start", 0), "end": export.get("end", 0),
		"max_depth": export.get("max_depth", 0),
		"biomes": export.get("biomes", []),  # legend [{id,name,color,required}]; v2 addition
		"nodes": nodes,
	}

func _graph_from_json(d: Dictionary) -> Dictionary:
	var nodes: Array = []
	for nd in d.get("nodes", []):
		var outs: Array = []
		for e in nd.get("out", []):
			var pts := PackedVector2Array()
			for p in e.get("points", []):
				pts.append(Vector2(float(p[0]), float(p[1])))
			outs.append({"to": int(e["to"]), "ferry": bool(e["ferry"]), "points": pts})
		var pos: Array = nd["pos"]
		nodes.append({
			"id": int(nd["id"]), "pos": Vector2(float(pos[0]), float(pos[1])),
			"depth": int(nd.get("depth", 0)), "landmass": int(nd.get("landmass", 0)),
			"height": float(nd.get("height", 0.0)), "biome": int(nd.get("biome", -1)),
			"out": outs,
		})
	return {
		"start": int(d.get("start", 0)), "end": int(d.get("end", 0)),
		"max_depth": int(d.get("max_depth", 0)),
		"biomes": d.get("biomes", []),  # absent in v1 files -> overlay skips biome meta
		"nodes": nodes,
	}

# =============================================================================
# BIOME REPAINT (designer iteration)
# =============================================================================
## Re-run ONLY the painting over the cached snapshot: WorldBiome band/palette edits, deco
## changes, and tint_nodes_by_biome all show without regenerating (~0.5 s at 512^2). Region
## SHAPES live in the generated buffers, so changing territory/warp knobs or the set's
## composition still needs Generate. For custom node styling hook graph_populated instead.
func repaint_biomes() -> void:
	if _snapshot.is_empty():
		push_warning("[WorldMap2D] repaint_biomes: no generated snapshot yet (press Generate first).")
		return
	_ensure_config()
	var w := settings.map_width
	var h := settings.map_height
	var bset := settings.active_biome_set()
	await _paint_layers(_snapshot, w, h, settings.ocean_threshold, _active_colorizer(),
		bset, _deco_ctx(bset, _worker().graph_export))
	_apply_map_texture()
	if show_graph and not _worker().graph_export.is_empty():
		_push_overlay_style()
		_overlay_node().populate(_worker().graph_export, Vector2(w, h))

## The graph overlay (creating it if needed), so consumers can walk it for token movement.
func overlay() -> WorldGraphOverlay:
	return _overlay_node()
