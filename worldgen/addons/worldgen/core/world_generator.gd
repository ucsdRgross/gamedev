class_name WorldGenerator
extends Node

## Orchestrates the world-generation pipeline. Steps 1-4 run as GPU canvas
## shaders (each driven by its own GenerationStep .gd file); rivers and graph
## building run on the CPU. Results land in the CPU buffers below, and
## snapshots feed the viewer for colorized debug display.

@export var settings: WorldSettings

var snapshots: Dictionary = {}
## Sentinel for "no inland water here" in water_surface_buffer.
const NO_WATER := -1.0
var height_buffer: PackedFloat32Array = PackedFloat32Array()
## Top-of-water elevation for inland water (rivers + lakes); NO_WATER where dry.
## height_buffer stays the pure terrain BED everywhere (incl. lake floors), so 3D
## can mesh terrain and water separately. Ocean is NOT stored here -- it is the
## implicit flat plane at settings.ocean_threshold (seabed varies below it).
var water_surface_buffer: PackedFloat32Array = PackedFloat32Array()
var plate_id_buffer: PackedInt32Array = PackedInt32Array()

var river_nodes: Array[Vector2i] = []
var lake_nodes: Array[Vector2i] = []  # cells where depression-fill raised a lake
# Full-res presence masks (index y*w+x, 1 = river/lake), built ONCE by StepRivers so the
# painter can test a pixel by index instead of hashing a Vector2i. Empty before Rivers runs.
# PackedByteArray is copy-on-write, so snapshots keep a cheap shared copy until mutated.
var river_set: PackedByteArray = PackedByteArray()
var lake_set: PackedByteArray = PackedByteArray()
# --- graph step outputs (StepGraph) ---
# Plain-data gameplay graph from GraphPlacement.export_graph: {start, end,
# max_depth, nodes:[{id,pos,depth,landmass,height,biome,out:[{to,ferry,points}]}]}.
var graph_export: Dictionary = {}
# The placement context (GraphPlacement.Ctx) + curved edge polylines ([u,v,points])
# and the sampling field (MapField, incl. water/river masks + landmass labels).
var graph_ctx = null
var graph_curves: Array = []
var map_field = null
var landmarks: Array[Dictionary] = []
var plate_data: PackedVector4Array = PackedVector4Array()  # padded to 15
var plate_is_land: PackedFloat32Array = PackedFloat32Array() # 1.0 continental, 0.0 oceanic
# Plate data is passed to shaders as data textures (texelFetch) because vec4[]
# array uniforms bind unreliably (only a middle slice survived).
var plate_tex: ImageTexture        # texel i = (pos.x, pos.y, dir.x, dir.y)
var plate_land_tex: ImageTexture   # texel i.r = is_land (1/0)
const MAX_PLATES := 15

## Opt-in: run the pure-CPU pipeline steps (Rivers, Graph) on a WorkerThreadPool task
## instead of blocking the main thread, so a caller polling process_frame (WorldMap2D's
## loading overlay) keeps animating through them. Default off so the verified map_viewer /
## test paths stay exactly synchronous; WorldMap2D flips it on at runtime.
var thread_cpu_steps: bool = false

var _viewports: Dictionary = {}
# CPU-baked noise maps: name -> { "img": Image, "tex": ImageTexture }. All noise
# is generated here so shaders only transform it (and the viewer can show it).
var noise_maps: Dictionary = {}
## Snapshot name of the last step that actually ran in the most recent generation
## (honoring toggles). final_snapshot() exposes it so "final image" consumers key
## off whatever executed instead of a hardcoded step name.
var _last_snapshot: String = ""

signal generation_step_finished(step_name: String)
## Emitted (on the main thread) just BEFORE a step runs, so a loading UI can name the step
## that is currently executing instead of the last one that finished.
signal generation_step_started(step_name: String)

# Maps a logical pass key to its shader. The blueprint/deform split and the
# flow ping-pong each get their own viewport so passes never clobber inputs.
const SHADER_DEFS := {
	"landmass": "res://addons/worldgen/shaders/landmass.gdshader",
	"blueprint": "res://addons/worldgen/shaders/tectonic_blueprint.gdshader",
	"deform": "res://addons/worldgen/shaders/tectonic_deformation.gdshader",
	"peaks": "res://addons/worldgen/shaders/peaks_and_valleys.gdshader",
	"erosion": "res://addons/worldgen/shaders/erosion.gdshader",
	# River generation (D8 flow accumulation) and the graph run on the CPU.
}

func _ready() -> void:
	if not settings:
		print("[WorldGenerator] No settings assigned, using defaults.")
		settings = WorldSettings.new()
	# Viewports are created lazily on first use (see _viewport), so a disabled GPU
	# step never allocates one. The viewer calls generate_world_map() after it has
	# connected to generation_step_finished, so we do not kick generation off here.

# =================================================================
# GPU PIPELINE PLUMBING
# =================================================================
## Get-or-create the SubViewport for a shader pass. Lazy so toggled-off GPU steps
## cost nothing; the two-frame wait in flush() covers a viewport created mid-run.
func _viewport(key: String) -> SubViewport:
	if not _viewports.has(key):
		_viewports[key] = _make_viewport(SHADER_DEFS[key])
	return _viewports[key]

func _make_viewport(shader_path: String) -> SubViewport:
	var w := settings.map_width
	var h := settings.map_height
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.use_hdr_2d = true  # half-float target so height data survives readback un-quantized
	vp.disable_3d = true
	add_child(vp)

	var rect := ColorRect.new()
	rect.size = Vector2(w, h)
	rect.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	rect.material = mat
	vp.add_child(rect)
	return vp

func get_material(key: String) -> ShaderMaterial:
	return _viewport(key).get_child(0).material

func noise_tex(name: String) -> Texture2D:
	return noise_maps[name]["tex"]

func noise_img(name: String) -> Image:
	return noise_maps[name]["img"]

func viewport_texture(key: String) -> Texture2D:
	return _viewport(key).get_texture()

## Force the pass to re-render and wait until the GPU has produced the frame,
## then hand back the rendered image. Two frame waits guarantees a populated
## target even on the very first run after the nodes entered the tree.
func flush(key: String) -> Image:
	var vp := _viewport(key)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()

# =================================================================
# CPU READBACK HELPERS (shared by the step files)
# =================================================================
func read_height_from_image(img: Image) -> void:
	var w := settings.map_width
	var h := settings.map_height
	for y in range(h):
		for x in range(w):
			height_buffer[(y * w) + x] = img.get_pixel(x, y).r

func read_plate_ids_from_image(img: Image) -> void:
	# Blueprint packs plate index into the blue channel as idx / 15.
	var w := settings.map_width
	var h := settings.map_height
	for y in range(h):
		for x in range(w):
			plate_id_buffer[(y * w) + x] = int(round(img.get_pixel(x, y).b * float(MAX_PLATES)))

## Build an RGBAH float texture whose red channel is the current height buffer.
## Used as the read-only base (H0) reference for the GPU erosion sim.
func height_texture() -> ImageTexture:
	var w := settings.map_width
	var h := settings.map_height
	var img := Image.create(w, h, false, Image.FORMAT_RGBAH)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, Color(height_buffer[(y * w) + x], 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(img)

# =================================================================
# DRIVER
# =================================================================
## Reset all per-run state and (re)size the CPU buffers. Shared by the full
## driver and the test-suite base generator.
func _reset_state() -> void:
	snapshots.clear()
	river_nodes.clear()
	lake_nodes.clear()
	# Reassign (not clear()): snapshots/cached bases share these dicts by reference.
	river_set = PackedByteArray()
	lake_set = PackedByteArray()
	graph_export.clear()
	graph_ctx = null
	graph_curves.clear()
	map_field = null
	landmarks.clear()
	_last_snapshot = ""

	var total := settings.map_width * settings.map_height
	height_buffer.resize(total)
	water_surface_buffer.resize(total)
	water_surface_buffer.fill(NO_WATER)
	plate_id_buffer.resize(total)

## Which pipeline step to stop after. Ordinals match the STEPS table order below,
## so int(GenStep) indexes straight into it. The map viewer uses this so it only
## pays for the steps it actually shows.
enum GenStep { LANDMASS, TECTONICS, PEAKS, EROSION, RIVERS, GRAPH }

## Ordered pipeline. Each entry: the GenerationStep subclass to run, the snapshot it
## emits (final_snapshot() = the last ENABLED one), whether it is a GPU coroutine
## (awaited) or a synchronous CPU pass, and the WorldSettings bool that toggles it
## ("" = always on: Landmass has no toggle). A disabled step is skipped and its
## buffers pass through, so the next enabled step consumes the previous output.
func _pipeline() -> Array:
	return [
		{"script": Step1Landmass, "snapshot": "Landmass", "gpu": true, "toggle": ""},
		{"script": Step2Tectonics, "snapshot": "Tectonics", "gpu": true, "toggle": "enable_tectonics"},
		{"script": Step3PeaksAndValleys, "snapshot": "PeaksAndValleys", "gpu": true, "toggle": "enable_peaks"},
		{"script": Step4Erosion, "snapshot": "Erosion", "gpu": true, "toggle": "enable_erosion"},
		# Rivers + Graph are pure CPU (no SubViewport/await): gpu:false so they can run on a
		# worker thread when thread_cpu_steps is set (else they run synchronously as before).
		{"script": StepRivers, "snapshot": "Rivers_Only", "gpu": false, "toggle": "enable_rivers"},
		{"script": StepGraph, "snapshot": "Graph", "gpu": false, "toggle": "enable_graph"},
	]

## Core driver: run enabled steps in order, stopping after the step at `stop_index`
## (pass the last index to run everything). Disabled steps are skipped. Tracks
## _last_snapshot; prints a timing report when `report` is set.
func _run_pipeline(stop_index: int, report: bool) -> void:
	var pipe := _pipeline()
	var timings: Array = []
	var gen_start := Time.get_ticks_msec()
	for i in range(pipe.size()):
		var s: Dictionary = pipe[i]
		var on: bool = s.toggle == "" or bool(settings.get(s.toggle))
		if on:
			generation_step_started.emit(s.snapshot)  # name the step now running (main thread)
			var ts := Time.get_ticks_msec()
			if s.gpu:
				await s.script.new().execute(self, settings)
			elif thread_cpu_steps:
				await _run_cpu_step_threaded(s.script.new())
			else:
				s.script.new().execute(self, settings)
			_last_snapshot = s.snapshot
			timings.append([s.snapshot, Time.get_ticks_msec() - ts])
		if i == stop_index:
			break
	if report:
		var total := Time.get_ticks_msec() - gen_start
		print("[WorldGenerator] --- Timing (enabled steps: %d ms) ---" % total)
		for e in timings:
			var ms: int = e[1]
			print("  %-16s %6d ms  %5.1f%%" % [e[0], ms, 100.0 * float(ms) / float(maxi(1, total))])

## Run one pure-CPU step on a WorkerThreadPool task, yielding to the main loop until it
## finishes so the caller's loading UI keeps animating. The step touches only CPU buffers
## (no SubViewport/RenderingServer); its snapshot emit is marshalled to the main thread by
## _save_snapshot_bridge. Requires being in the tree (WorldMap2D always is when threading).
func _run_cpu_step_threaded(step: GenerationStep) -> void:
	var tid := WorkerThreadPool.add_task(step.execute.bind(self, settings), true, "worldgen_cpu_step")
	while not WorkerThreadPool.is_task_completed(tid):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(tid)

## Bake the noise maps. When thread_cpu_steps is set, compute the (independent) maps in
## PARALLEL across a WorkerThreadPool group task -- one element per map -- while the main
## thread polls frames so the loading overlay animates; total time collapses toward the
## slowest single map instead of their sum. Textures are built on the main thread after.
## Synchronous single-thread bake otherwise (editor / map_viewer / tests).
func _bake_noise() -> void:
	if not thread_cpu_steps:
		noise_maps = NoiseBaker.bake(settings)
		return
	var recipes := NoiseBaker.image_recipes(settings)
	var imgs: Array = []
	imgs.resize(recipes.size())
	# Each group element i computes one map into its own slot -> no shared writes to race.
	var worker := func(i: int) -> void: imgs[i] = (recipes[i]["fn"] as Callable).call()
	var gid := WorkerThreadPool.add_group_task(worker, recipes.size(), -1, true, "worldgen_noise")
	while not WorkerThreadPool.is_group_task_completed(gid):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var by_name := {}
	for i in range(recipes.size()):
		by_name[recipes[i]["name"]] = imgs[i]
	noise_maps = NoiseBaker.make_textures(by_name)

func generate_world_map() -> void:
	_reset_state()
	seed(settings.main_seed)
	# Setup (noise + plates) is timed separately from the step budget.
	var ts := Time.get_ticks_msec()
	await _bake_noise()  # all CPU noise, generated once (threaded when thread_cpu_steps)
	print("[WorldGenerator]   setup NoiseBake %d ms" % (Time.get_ticks_msec() - ts))
	ts = Time.get_ticks_msec()
	_init_plates()
	print("[WorldGenerator]   setup Plates    %d ms" % (Time.get_ticks_msec() - ts))

	await _run_pipeline(_pipeline().size() - 1, true)  # run all enabled steps

	# The emit (not the stored dict) triggers the viewer's debug-sheet export. Each
	# step already emitted its own snapshot inside execute(); the viewer ignores all
	# but this one, so no per-step re-emit loop is needed.
	_save_snapshot_bridge("All_Steps_Grid")

## The snapshot name of the last step that actually ran (honoring toggles), so
## "final image" consumers key off whatever executed rather than a fixed step.
func final_snapshot() -> String:
	return _last_snapshot

## Run the pipeline only up to (and including) `target`, honoring toggles: same
## setup preamble as the full driver, then the shared step loop with an early-out.
func generate_up_to(target: GenStep) -> void:
	_reset_state()
	seed(settings.main_seed)
	noise_maps = NoiseBaker.bake(settings)
	_init_plates()
	await _run_pipeline(int(target), false)

## Snapshot/restore the post-Rivers base so many graph configs can be rebuilt on
## the identical base map (tuning-harness support).
func cache_base_state() -> Dictionary:
	return {
		"height": height_buffer.duplicate(),
		"water_surface": water_surface_buffer.duplicate(),
		"river_nodes": river_nodes.duplicate(),
		"lake_nodes": lake_nodes.duplicate(),
		"river_set": river_set,  # PackedByteArray mask (COW: cheap shared copy)
		"lake_set": lake_set,
	}

func restore_base_state(b: Dictionary) -> void:
	height_buffer = b["height"].duplicate()
	water_surface_buffer = b["water_surface"].duplicate()
	river_nodes = b["river_nodes"].duplicate()
	lake_nodes = b["lake_nodes"].duplicate()
	river_set = b["river_set"]
	lake_set = b["lake_set"]
	graph_export = {}
	graph_ctx = null
	graph_curves = []
	map_field = null

func _init_plates() -> void:
	plate_data.resize(MAX_PLATES)
	plate_is_land.resize(MAX_PLATES)
	plate_is_land.fill(0.0)
	for i in range(MAX_PLATES):
		plate_data[i] = Vector4(-9999.0, -9999.0, 0.0, 0.0)

	# Distribute plate centers evenly over a jittered grid (matches old CPU step)
	# so plate cells and their drift arrows are spread across the map. Driven by a
	# dedicated RNG keyed on the tectonic seed, so the tectonic seed offset moves
	# the plates (positions/drift/land) -- not just the warp noise.
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.main_seed + settings.tectonic_seed_offset
	var grid_cols: int = int(ceil(sqrt(float(settings.plate_count))))
	var grid_rows: int = int(ceil(float(settings.plate_count) / float(grid_cols)))
	var cell_w: float = float(settings.map_width) / float(grid_cols)
	var cell_h: float = float(settings.map_height) / float(grid_rows)

	var assigned: int = 0
	for r in range(grid_rows):
		for c in range(grid_cols):
			if assigned >= settings.plate_count:
				break
			var pos := Vector2(
				(c * cell_w) + (cell_w * 0.5) + (rng.randf() - 0.5) * (cell_w * 0.4),
				(r * cell_h) + (cell_h * 0.5) + (rng.randf() - 0.5) * (cell_h * 0.4))
			var dir := Vector2(rng.randf() - 0.5, rng.randf() - 0.5).normalized()
			# Seeded land/ocean choice (sampling skews oceanic, so we roll it).
			var is_land := rng.randf() < settings.land_plate_ratio
			plate_data[assigned] = Vector4(pos.x, pos.y, dir.x, dir.y)
			plate_is_land[assigned] = 1.0 if is_land else 0.0
			landmarks.append({"pos": pos, "dir": dir, "ocean": not is_land})
			assigned += 1

	_build_plate_textures()

## Encode plate position/drift and land flags into small data textures, sampled
## with texelFetch in the shaders (reliable, unlike vec4[] array uniforms).
func _build_plate_textures() -> void:
	var pimg := Image.create(MAX_PLATES, 1, false, Image.FORMAT_RGBAF)
	var limg := Image.create(MAX_PLATES, 1, false, Image.FORMAT_RGBAF)
	for i in range(MAX_PLATES):
		var p := plate_data[i]
		pimg.set_pixel(i, 0, Color(p.x, p.y, p.z, p.w))
		limg.set_pixel(i, 0, Color(plate_is_land[i], 0.0, 0.0, 1.0))
	plate_tex = ImageTexture.create_from_image(pimg)
	plate_land_tex = ImageTexture.create_from_image(limg)

# =================================================================
# SNAPSHOTS (array-backed; the viewer colorizes from these)
# =================================================================
func _save_snapshot_bridge(step_name: String) -> void:
	snapshots[step_name] = {
		"height": height_buffer.duplicate(),
		"water_surface": water_surface_buffer.duplicate(),
		"plate_ids": plate_id_buffer.duplicate(),
		"river_set": river_set,  # built once by StepRivers; empty before it runs
		"lake_set": lake_set,
		"graph_export": graph_export.duplicate(true),
		"graph_curves": graph_curves.duplicate(),
		"landmarks": landmarks.duplicate(),
	}
	# When a CPU step runs on a worker thread, marshal the signal to the main thread so
	# connected slots (loading UI) never touch the scene tree off-thread.
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		generation_step_finished.emit(step_name)
	else:
		generation_step_finished.emit.call_deferred(step_name)
