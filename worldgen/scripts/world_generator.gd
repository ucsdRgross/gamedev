class_name WorldGenerator
extends Node

@export var settings: WorldSettings

var snapshots: Dictionary = {}
var landmarks: Array[Dictionary] = []

var landmass_vp: SubViewport
var tectonic_blue_vp: SubViewport
var tectonic_deform_vp: SubViewport
var peaks_vp: SubViewport
var flow_ping_vp: SubViewport
var flow_pong_vp: SubViewport
var erosion_vp: SubViewport
var biomes_vp: SubViewport
var node_grid_vp: SubViewport

signal generation_step_finished(step_name: String)

func _ready() -> void:
	if not settings: 
		print('[WorldGenerator] Warning: No settings found, using defaults.')
		settings = WorldSettings.new()
	_setup_shader_viewport_pipeline_tree()
	generate_world_map()

func _setup_shader_viewport_pipeline_tree() -> void:
	var w = settings.map_width
	var h = settings.map_height
	print('[WorldGenerator] Initializing GPU Pipeline at ', w, 'x', h)
	
	landmass_vp = _create_sandbox_viewport(w, h, 'res://shaders/step_1_landmass.gdshader')
	tectonic_blue_vp = _create_sandbox_viewport(w, h, 'res://shaders/step_2_tectonic_blueprint.gdshader')
	tectonic_deform_vp = _create_sandbox_viewport(w, h, 'res://shaders/step_3_tectonic_deformation.gdshader')
	peaks_vp = _create_sandbox_viewport(w, h, 'res://shaders/step_4_peaks_and_valleys.gdshader')
	flow_ping_vp = _create_sandbox_viewport(w, h, 'res://shaders/step_5_flow_accumulation.gdshader')
	flow_pong_vp = _create_sandbox_viewport(w, h, 'res://shaders/step_5_flow_accumulation.gdshader')
	erosion_vp = _create_sandbox_viewport(w, h, 'res://shaders/step_5_erosion.gdshader')
	biomes_vp = _create_sandbox_viewport(w, h, 'res://shaders/step_6_biomes_and_climate.gdshader')
	node_grid_vp = _create_sandbox_viewport(w, h, 'res://shaders/step_7_node_sampling.gdshader')

func _create_sandbox_viewport(w: int, h: int, shader_path: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.use_hdr_2d = true
	add_child(vp)
	
	var rect := ColorRect.new()
	rect.size = Vector2(w, h) # CRITICAL: Viewport children need explicit size
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	rect.material = mat
	vp.add_child(rect)
	return vp

func generate_world_map() -> void:
	print('[WorldGenerator] --- Starting Generation ---')
	var start_time = Time.get_ticks_msec()
	snapshots.clear()
	seed(settings.main_seed)
	
	var plate_centers_and_dirs: Array[Vector4] = []
	for i in range(settings.plate_count):
		var pos = Vector2(randf() * settings.map_width, randf() * settings.map_height)
		var dir = Vector2(randf() - 0.5, randf() - 0.5).normalized()
		plate_centers_and_dirs.append(Vector4(pos.x, pos.y, dir.x, dir.y))
		landmarks.append({'pos': pos, 'dir': dir, 'ocean': randf() < 0.3})
		
	# Step 1
	var land_mat: ShaderMaterial = landmass_vp.get_child(0).material
	land_mat.set_shader_parameter('seed', settings.main_seed)
	land_mat.set_shader_parameter('frequency', settings.continent_frequency)
	_save_snapshot('Landmass', landmass_vp)
	
	# Step 2
	var blue_mat: ShaderMaterial = tectonic_blue_vp.get_child(0).material
	blue_mat.set_shader_parameter('seed', settings.main_seed + 15)
	blue_mat.set_shader_parameter('plate_count', settings.plate_count)
	blue_mat.set_shader_parameter('plates', plate_centers_and_dirs)
	_save_snapshot('Tectonics_Debug', tectonic_blue_vp)
	
	# Step 3
	var deform_mat: ShaderMaterial = tectonic_deform_vp.get_child(0).material
	deform_mat.set_shader_parameter('landmass_tex', snapshots['Landmass']['texture'])
	deform_mat.set_shader_parameter('blueprint_tex', snapshots['Tectonics_Debug']['texture'])
	deform_mat.set_shader_parameter('drift_intensity', settings.drift_intensity) 
	_save_snapshot('Tectonics', tectonic_deform_vp)
	
	# Step 4
	var peaks_mat: ShaderMaterial = peaks_vp.get_child(0).material
	peaks_mat.set_shader_parameter('deformed_tex', snapshots['Tectonics']['texture'])
	peaks_mat.set_shader_parameter('ocean_threshold', settings.ocean_threshold)
	peaks_mat.set_shader_parameter('seed', settings.main_seed + 2)
	_save_snapshot('PeaksAndValleys', peaks_vp)
	
	# Step 5 (Ping-Pong)
	print('[WorldGenerator] Running flow accumulation...')
	var flow_input_tex = snapshots['PeaksAndValleys']['texture']
	for loop in range(16):
		flow_ping_vp.get_child(0).material.set_shader_parameter('height_tex', flow_input_tex)
		flow_ping_vp.get_child(0).material.set_shader_parameter('pass_index', loop * 2)
		RenderingServer.force_draw()
		flow_pong_vp.get_child(0).material.set_shader_parameter('height_tex', flow_ping_vp.get_texture())
		flow_pong_vp.get_child(0).material.set_shader_parameter('pass_index', (loop * 2) + 1)
		RenderingServer.force_draw()
		flow_input_tex = flow_pong_vp.get_texture()
	_save_snapshot('Flow', flow_pong_vp)

	# Step 6
	var erosion_mat: ShaderMaterial = erosion_vp.get_child(0).material
	erosion_mat.set_shader_parameter('height_tex', snapshots['PeaksAndValleys']['texture'])
	erosion_mat.set_shader_parameter('flow_tex', snapshots['Flow']['texture'])
	_save_snapshot('Erosion', erosion_vp)
	
	# Step 7
	var biome_mat: ShaderMaterial = biomes_vp.get_child(0).material
	biome_mat.set_shader_parameter('height_tex', snapshots['Erosion']['texture'])
	biome_mat.set_shader_parameter('flow_tex', snapshots['Flow']['texture'])
	biome_mat.set_shader_parameter('seed_t', settings.main_seed + 3)
	biome_mat.set_shader_parameter('seed_h', settings.main_seed + 4)
	biome_mat.set_shader_parameter('ocean_threshold', settings.ocean_threshold)
	biome_mat.set_shader_parameter('mountain_threshold', settings.mountain_threshold)
	_save_snapshot('Climate', biomes_vp)
	
	# Step 8
	var node_mat: ShaderMaterial = node_grid_vp.get_child(0).material
	node_mat.set_shader_parameter('biome_tex', snapshots['Climate']['texture'])
	node_mat.set_shader_parameter('seed', settings.main_seed + 99)
	_save_snapshot('Cities', node_grid_vp)
	
	generation_step_finished.emit('All_Steps_Grid')
	print('[WorldGenerator] Completed in ', Time.get_ticks_msec() - start_time, ' ms')

func _save_snapshot(step_name: String, vp: SubViewport) -> void:
	RenderingServer.force_draw()
	var img = vp.get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	snapshots[step_name] = {'texture': ImageTexture.create_from_image(img), 'landmarks': landmarks.duplicate()}
	print('[WorldGenerator] Saved: ', step_name)
	generation_step_finished.emit(step_name)

func get_step_metadata(step: String) -> Array:
	match step:
		'Climate':
			return [{'c': Color.html('#2563eb'), 'n': 'Rivers'}, {'c': Color.html('#991b1b'), 'n': 'Volcano'}, {'c': Color.html('#047857'), 'n': 'Swamp'}]
		'Tectonics_Debug':
			return [{'c': Color.RED, 'n': 'Continental'}, {'c': Color.CYAN, 'n': 'Oceanic'}]
		_:
			return [{'c': Color.html('#1a365d'), 'n': 'Ocean'}, {'c': Color.html('#2f855a'), 'n': 'Land'}]
