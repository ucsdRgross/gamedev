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
# Vector2i -> true lookup sets over the arrays above, built ONCE by StepRivers so
# snapshots and painters never rebuild them per use.
var river_set: Dictionary = {}
var lake_set: Dictionary = {}
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

var _viewports: Dictionary = {}
# CPU-baked noise maps: name -> { "img": Image, "tex": ImageTexture }. All noise
# is generated here so shaders only transform it (and the viewer can show it).
var noise_maps: Dictionary = {}

signal generation_step_finished(step_name: String)

# Maps a logical pass key to its shader. The blueprint/deform split and the
# flow ping-pong each get their own viewport so passes never clobber inputs.
const SHADER_DEFS := {
	"landmass": "res://shaders/step_1_landmass.gdshader",
	"blueprint": "res://shaders/step_2_tectonic_blueprint.gdshader",
	"deform": "res://shaders/step_3_tectonic_deformation.gdshader",
	"peaks": "res://shaders/step_4_peaks_and_valleys.gdshader",
	"erosion": "res://shaders/step_4_erosion.gdshader",
	# River generation (D8 flow accumulation) and the graph run on the CPU.
}

func _ready() -> void:
	if not settings:
		print("[WorldGenerator] No settings assigned, using defaults.")
		settings = WorldSettings.new()
	_build_viewports()
	# The viewer (our parent) calls generate_world_map() after it has connected
	# to generation_step_finished, so we do not kick generation off here.

# =================================================================
# GPU PIPELINE PLUMBING
# =================================================================
func _build_viewports() -> void:
	for key in SHADER_DEFS:
		_viewports[key] = _make_viewport(SHADER_DEFS[key])

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
	return _viewports[key].get_child(0).material

func noise_tex(name: String) -> Texture2D:
	return noise_maps[name]["tex"]

func noise_img(name: String) -> Image:
	return noise_maps[name]["img"]

func viewport_texture(key: String) -> Texture2D:
	return _viewports[key].get_texture()

## Force the pass to re-render and wait until the GPU has produced the frame,
## then hand back the rendered image. Two frame waits guarantees a populated
## target even on the very first run after the nodes entered the tree.
func flush(key: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _viewports[key].get_texture().get_image()

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
	river_set = {}
	lake_set = {}
	graph_export.clear()
	graph_ctx = null
	graph_curves.clear()
	map_field = null
	landmarks.clear()

	var total := settings.map_width * settings.map_height
	height_buffer.resize(total)
	water_surface_buffer.resize(total)
	water_surface_buffer.fill(NO_WATER)
	plate_id_buffer.resize(total)

func generate_world_map() -> void:
	_reset_state()
	seed(settings.main_seed)

	# Setup (noise + plates) is timed separately; the generation total is measured
	# strictly from before Landmass to after Graph (excludes debug sheet + PNG).
	var setup: Array = []
	var ts := Time.get_ticks_msec()
	noise_maps = NoiseBaker.bake(settings)  # all CPU noise, generated once
	setup.append(["NoiseBake", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	_init_plates()
	setup.append(["Plates", Time.get_ticks_msec() - ts])

	var timings: Array = []
	var gen_start := Time.get_ticks_msec()
	ts = gen_start
	await Step1Landmass.new().execute(self, settings)        # GPU
	timings.append(["Landmass", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	await Step2Tectonics.new().execute(self, settings)       # GPU
	timings.append(["Tectonics", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	await Step3PeaksAndValleys.new().execute(self, settings)  # GPU
	timings.append(["Peaks", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	await Step4Erosion.new().execute(self, settings)         # GPU directional-gabor branching erosion
	timings.append(["Erosion", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	await StepRivers.new().execute(self, settings)           # CPU D8 flow-accumulation rivers + lakes
	timings.append(["Rivers", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	StepGraph.new().execute(self, settings)                  # CPU spec -> place -> curves -> export
	timings.append(["Graph", Time.get_ticks_msec() - ts])
	var gen_total := Time.get_ticks_msec() - gen_start

	# Timing report (generation window only; setup + debug excluded from the %).
	print("[WorldGenerator] --- Timing (generation Landmass->Graph: ", gen_total, " ms) ---")
	for entry in setup:
		print("  %-14s %6d ms  (setup)" % [entry[0], entry[1]])
	for entry in timings:
		var ms: int = entry[1]
		print("  %-14s %6d ms  %5.1f%%" % [entry[0], ms, 100.0 * float(ms) / float(maxi(1, gen_total))])

	# Debug sheet + PNG (not part of the generation budget).
	var ordered := ["Landmass", "Tectonics_Debug", "Tectonics", "PeaksAndValleys",
		"Erosion", "Rivers_Only", "Graph"]
	for k in ordered:
		if snapshots.has(k):
			generation_step_finished.emit(k)
	_save_snapshot_bridge("All_Steps_Grid")  # this emit triggers the viewer's export

## Which pipeline step to stop after. Matches the snapshot order; the map viewer
## uses this so it only pays for the steps it actually shows.
enum GenStep { LANDMASS, TECTONICS, PEAKS, EROSION, RIVERS, GRAPH }

## Run the pipeline only up to (and including) `target`: same setup preamble as
## the full driver, then the step chain with an early-out.
func generate_up_to(target: GenStep) -> void:
	_reset_state()
	seed(settings.main_seed)
	noise_maps = NoiseBaker.bake(settings)
	_init_plates()
	await Step1Landmass.new().execute(self, settings)
	if target == GenStep.LANDMASS: return
	await Step2Tectonics.new().execute(self, settings)
	if target == GenStep.TECTONICS: return
	await Step3PeaksAndValleys.new().execute(self, settings)
	if target == GenStep.PEAKS: return
	await Step4Erosion.new().execute(self, settings)
	if target == GenStep.EROSION: return
	await StepRivers.new().execute(self, settings)
	if target == GenStep.RIVERS: return
	StepGraph.new().execute(self, settings)

## Snapshot/restore the post-Rivers base so many graph configs can be rebuilt on
## the identical base map (tuning-harness support).
func cache_base_state() -> Dictionary:
	return {
		"height": height_buffer.duplicate(),
		"water_surface": water_surface_buffer.duplicate(),
		"river_nodes": river_nodes.duplicate(),
		"lake_nodes": lake_nodes.duplicate(),
		"river_set": river_set,  # never mutated after StepRivers -> share by ref
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
	generation_step_finished.emit(step_name)
