class_name WorldGenerator
extends Node

## Orchestrates the world-generation pipeline. Steps 1-5 run as GPU canvas
## shaders (each driven by its own GenerationStep .gd file); node scattering
## and graph building (steps 6-7) run on the CPU. Results land in the CPU
## buffers below, and snapshots feed the viewer for colorized debug display.

@export var settings: WorldSettings

var snapshots: Dictionary = {}
var height_buffer: PackedFloat32Array = PackedFloat32Array()
var temp_buffer: PackedFloat32Array = PackedFloat32Array()
var humid_buffer: PackedFloat32Array = PackedFloat32Array()
var biome_id_buffer: PackedInt32Array = PackedInt32Array()
var plate_id_buffer: PackedInt32Array = PackedInt32Array()

var biome_palette: Array[String] = [
	"Ocean", "Glacial Peak", "Volcanic Crag", "Barren Ridges",
	"Cryo Frostwastes", "Tectonic Fissures", "Ashen Tundra", "Salt Flats",
	"Tornado Prairie", "Toxic Swamps", "Shattered Savannah", "Seismic Plains", "Acidic Jungle"
]

var river_nodes: Array[Vector2i] = []
var lake_nodes: Array[Vector2i] = []  # cells where depression-fill raised a lake
var travel_nodes: Array[Vector2] = [] # dense evenly-distributed waypoints (vs sparse city_nodes)
var city_nodes: Array[Vector2] = []
var gameplay_graph: Dictionary = {}
# Cosmetic curved polylines (PackedVector2Array, map px) for each graph edge,
# routed around water / over passes. Used by the colored graph view only.
var edge_curves: Array = []
# Full result of the last graph build {graph, start, end, meta, injected}; the
# test suite reads this to validate/measure the exact graph produced.
var graph_result: Dictionary = {}
# Continent labeling from Step6: full-res cell (4px grid) -> continent id (0 =
# largest). landmass_sizes maps id -> cell count. The graph uses these to treat
# landmasses as nodes (inter-landmass water travel rules).
var landmass_labels: Dictionary = {}
var landmass_sizes: Dictionary = {}
var start_node: Vector2
var end_node: Vector2
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
	# Erosion (step 4) and river generation (D8 flow accumulation) both run on the
	# CPU now, so neither needs a viewport.
	"climate": "res://shaders/step_6_biomes_and_climate.gdshader",
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

func read_biomes_from_image(img: Image) -> void:
	# Climate packs biome id into red as id / 255.
	var w := settings.map_width
	var h := settings.map_height
	for y in range(h):
		for x in range(w):
			biome_id_buffer[(y * w) + x] = int(round(img.get_pixel(x, y).r * 255.0))

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

## Pack the current CPU state into a float texture for the climate shader:
##   R = height, G = river flag (1 if this cell is a river).
func build_state_texture() -> ImageTexture:
	var w := settings.map_width
	var h := settings.map_height
	var img := Image.create(w, h, false, Image.FORMAT_RGBAH)
	var river_set := {}
	for r in river_nodes:
		river_set[r] = true
	for l in lake_nodes:  # lakes are water too -> count toward the river/water flag
		river_set[l] = true
	for y in range(h):
		for x in range(w):
			var river_flag := 1.0 if river_set.has(Vector2i(x, y)) else 0.0
			img.set_pixel(x, y, Color(height_buffer[(y * w) + x], river_flag, 0.0, 1.0))
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
	travel_nodes.clear()
	city_nodes.clear()
	gameplay_graph.clear()
	edge_curves.clear()
	graph_result.clear()
	landmass_labels.clear()
	landmass_sizes.clear()
	landmarks.clear()

	var total := settings.map_width * settings.map_height
	height_buffer.resize(total)
	temp_buffer.resize(total)
	humid_buffer.resize(total)
	biome_id_buffer.resize(total)
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
	await Step4Erosion.new().execute(self, settings)         # CPU hydraulic (flow-accumulation stream-power) erosion
	timings.append(["Erosion", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	await StepRivers.new().execute(self, settings)           # CPU D8 flow-accumulation rivers + lakes
	timings.append(["Rivers", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	await Step5Climate.new().execute(self, settings)         # GPU (reads carved height + river network)
	timings.append(["Climate", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	Step6Civilizations.new().execute(self, settings)
	timings.append(["Civilizations", Time.get_ticks_msec() - ts])
	ts = Time.get_ticks_msec()
	Step7Graph.new().execute(self, settings)
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
		"Erosion", "Rivers_Only", "Climate", "Cities", "Graph"]
	for k in ordered:
		if snapshots.has(k):
			generation_step_finished.emit(k)
	_save_snapshot_bridge("All_Steps_Grid")  # this emit triggers the viewer's export

# =================================================================
# TEST-SUITE SUPPORT
# Generate a map *through Civilizations* (no graph), then snapshot/restore the
# base so many graph presets can be built on the identical base map.
# =================================================================
func generate_base_through_civilizations() -> void:
	_reset_state()
	seed(settings.main_seed)
	noise_maps = NoiseBaker.bake(settings)
	_init_plates()
	await Step1Landmass.new().execute(self, settings)
	await Step2Tectonics.new().execute(self, settings)
	await Step3PeaksAndValleys.new().execute(self, settings)
	await Step4Erosion.new().execute(self, settings)
	await StepRivers.new().execute(self, settings)
	await Step5Climate.new().execute(self, settings)
	Step6Civilizations.new().execute(self, settings)

func cache_base_state() -> Dictionary:
	return {
		"height": height_buffer.duplicate(),
		"biome": biome_id_buffer.duplicate(),
		"city_nodes": city_nodes.duplicate(),
		"travel_nodes": travel_nodes.duplicate(),
		"landmass_labels": landmass_labels.duplicate(),
		"landmass_sizes": landmass_sizes.duplicate(),
	}

func restore_base_state(b: Dictionary) -> void:
	height_buffer = b["height"].duplicate()
	biome_id_buffer = b["biome"].duplicate()
	city_nodes = b["city_nodes"].duplicate()
	travel_nodes = b["travel_nodes"].duplicate()
	landmass_labels = b["landmass_labels"].duplicate()
	landmass_sizes = b["landmass_sizes"].duplicate()
	gameplay_graph = {}
	graph_result = {}

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
	var river_set := {}
	for r in river_nodes:
		river_set[r] = true
	var lake_set := {}
	for l in lake_nodes:
		lake_set[l] = true

	snapshots[step_name] = {
		"height": height_buffer.duplicate(),
		"biome": biome_id_buffer.duplicate(),
		"plate_ids": plate_id_buffer.duplicate(),
		"river_nodes": river_nodes.duplicate(),
		"river_set": river_set,
		"lake_set": lake_set,
		"city_nodes": city_nodes.duplicate(),
		"travel_nodes": travel_nodes.duplicate(),
		"gameplay_graph": gameplay_graph.duplicate(),
		"edge_curves": edge_curves.duplicate(),
		"start_node": start_node,
		"end_node": end_node,
		"landmarks": landmarks.duplicate(),
	}
	generation_step_finished.emit(step_name)

# =================================================================
# CPU UTILITIES (used by erosion/civ/graph)
# =================================================================
func _clamp_island_boundaries_fast() -> void:
	var w := settings.map_width
	var cx := w / 2.0
	var cy := settings.map_height / 2.0
	var max_radius :int= min(w, settings.map_height) * 0.44

	for y in range(settings.map_height):
		for x in range(w):
			var idx := (y * w) + x
			var d := Vector2(x, y).distance_to(Vector2(cx, cy))
			if d > max_radius:
				var fade := clampf(1.0 - ((d - max_radius) / 45.0), 0.0, 1.0)
				height_buffer[idx] *= fade
				if fade <= 0.0:
					height_buffer[idx] = min(height_buffer[idx], settings.ocean_threshold - 0.05)

func _calculate_gradient_fast(x: int, y: int) -> Vector2:
	var w := settings.map_width
	var h := settings.map_height
	var idx := (y * w) + x
	var h00 := height_buffer[idx]
	var h10 := height_buffer[(y * w) + (x + 1)] if x + 1 < w else h00
	var h01 := height_buffer[((y + 1) * w) + x] if y + 1 < h else h00
	return Vector2(h10 - h00, h01 - h00)
