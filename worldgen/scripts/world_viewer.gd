# world_viewer.gd
class_name WorldViewer
extends Node2D

@onready var generator: WorldGenerator = $WorldGenerator
@onready var label: Label = $CanvasLayer/Label

var step_names: Array[String] = []
var current_step_index: int = -1
var cached_texture: ImageTexture

func _ready() -> void:
	generator.generation_step_finished.connect(_on_generation_step_finished)
	generator.generate_world_map()
	
	if not step_names.is_empty():
		current_step_index = step_names.size() - 1
		_display_snapshot(step_names[current_step_index])

func _on_generation_step_finished(step_name: String) -> void:
	if step_name == "Landmass":
		step_names.clear()
		
	if not step_names.has(step_name):
		step_names.append(step_name)
		
	if step_name == "All_Steps_Grid":
		_download_grid_to_disk()

func _unhandled_input(event: InputEvent) -> void:
	if step_names.is_empty(): return
	
	if event.is_action_pressed("ui_right"):
		current_step_index = (current_step_index + 1) % step_names.size()
		_display_snapshot(step_names[current_step_index])
	elif event.is_action_pressed("ui_left"):
		current_step_index = (current_step_index - 1 + step_names.size()) % step_names.size()
		_display_snapshot(step_names[current_step_index])

func _display_snapshot(step_name: String) -> void:
	label.text = "Step: " + step_name + " (Arrow Keys to Cycle)"
	
	var w: int = generator.settings.map_width
	var h: int = generator.settings.map_height
	
	if step_name == "All_Steps_Grid":
		_render_all_steps_grid(w, h)
		return
		
	var data: Dictionary = generator.snapshots[step_name]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	_fill_image_with_step_pixels(img, data, step_name, Vector2i.ZERO, w, h, 1.0)
	
	cached_texture = ImageTexture.create_from_image(img)
	queue_redraw()

func _fill_image_with_step_pixels(img: Image, data: Dictionary, step: String, offset: Vector2i, w: int, h: int, scale: float) -> void:
	var h_map: Dictionary = data["height_map"]
	var b_map: Dictionary = data["biome_map"]
	var rivers: Array = data["river_nodes"]
	
	for y in range(int(h * scale)):
		for x in range(int(w * scale)):
			var orig_pos = Vector2i(int(x / scale), int(y / scale))
			var target_pos = offset + Vector2i(x, y)
			
			if target_pos.x >= img.get_width() or target_pos.y >= img.get_height(): continue
			
			var color := Color.BLACK
			var val: float = h_map.get(orig_pos, 0.0)
			
			if step == "Rivers_Only":
				var is_river_pixel = false
				for rx in range(-1, 2):
					for ry in range(-1, 2):
						if rivers.has(orig_pos + Vector2i(rx, ry)):
							is_river_pixel = true
							break
				color = Color.html("#38bdf8") if (is_river_pixel and val >= generator.settings.ocean_threshold) else Color.html("#0f172a")
				img.set_pixelv(target_pos, color)
				continue
			
			if step in ["Landmass", "Tectonics", "Tectonics_Debug", "PeaksAndValleys", "Erosion", "Cities", "Graph"]:
				if val < generator.settings.ocean_threshold:
					color = Color.html("#1a365d")
				elif val < generator.settings.ocean_threshold + 0.04:
					color = Color.html("#2b6cb0") 
				elif val < 0.46:
					color = Color.html("#2f855a") 
				elif val < generator.settings.mountain_threshold:
					color = Color.html("#ecc94b") 
				elif val < 0.82:
					color = Color.html("#718096") 
				else:
					color = Color.html("#ffffff") 
			else:
				if b_map.has(orig_pos):
					match b_map[orig_pos]:
						"Ocean": color = Color.html("#1a365d")
						"Glacial Peak": color = Color.html("#e2e8f0")
						"Volcanic Crag": color = Color.html("#991b1b")
						"Barren Ridges": color = Color.html("#4b5563")
						"Cryo Frostwastes": color = Color.html("#38bdf8")
						"Tectonic Fissures": color = Color.html("#7c2d12")
						"Ashen Tundra": color = Color.html("#9ca3af")
						"Salt Flats": color = Color.html("#f9fafb")
						"Tornado Prairie": color = Color.html("#65a30d")
						"Toxic Swamps": color = Color.html("#047857")
						"Shattered Savannah": color = Color.html("#b45309")
						"Seismic Plains": color = Color.html("#15803d")
						"Acidic Jungle": color = Color.html("#065f46")
						_: color = Color.BLACK
			
			var thick_river = false
			for rx in range(-1, 2):
				for ry in range(-1, 2):
					if rivers.has(orig_pos + Vector2i(rx, ry)):
						thick_river = true
						break
						
			if step in ["Climate", "Cities", "Graph"] and thick_river and val >= generator.settings.ocean_threshold:
				color = Color.html("#2563eb")
				
			img.set_pixelv(target_pos, color)

func _render_all_steps_grid(w: int, h: int) -> void:
	var comp_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pipelines = ["Landmass", "Tectonics_Debug", "Tectonics", "PeaksAndValleys", "Erosion", "Rivers_Only", "Climate", "Cities", "Graph"]
	
	var sub_w = int(w / 3)
	var sub_h = int(h / 3)
	var scale = 1.0 / 3.0
	
	for idx in range(pipelines.size()):
		var step = pipelines[idx]
		if not generator.snapshots.has(step): continue
		
		var offset = Vector2i((idx % 3) * sub_w, (idx / 3) * sub_h)
		_fill_image_with_step_pixels(comp_img, generator.snapshots[step], step, offset, w, h, scale)
		
	cached_texture = ImageTexture.create_from_image(comp_img)
	queue_redraw()

func _download_grid_to_disk() -> void:
	var w = generator.settings.map_width
	var h = generator.settings.map_height
	var out_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	
	var pipelines = ["Landmass", "Tectonics_Debug", "Tectonics", "PeaksAndValleys", "Erosion", "Rivers_Only", "Climate", "Cities", "Graph"]
	var sub_w = int(w / 3)
	var sub_h = int(h / 3)
	var scale = 1.0 / 3.0
	
	for idx in range(pipelines.size()):
		var step = pipelines[idx]
		if generator.snapshots.has(step):
			var offset = Vector2i((idx % 3) * sub_w, (idx / 3) * sub_h)
			_fill_image_with_step_pixels(out_img, generator.snapshots[step], step, offset, w, h, scale)
			
	# EXPORT BUFFER BINDINGS FIX: Maps vector calculations precisely onto output cells
	if generator.snapshots.has("Tectonics_Debug"):
		_rasterize_tectonics_to_disk_buffer(out_img, generator.snapshots["Tectonics_Debug"], Vector2(sub_w, 0), scale)
	if generator.snapshots.has("Cities"):
		_rasterize_vectors_to_image_buffer(out_img, generator.snapshots["Cities"], Vector2(sub_w, sub_h * 2), scale)
	if generator.snapshots.has("Graph"):
		_rasterize_vectors_to_image_buffer(out_img, generator.snapshots["Graph"], Vector2(sub_w * 2, sub_h * 2), scale)
	
	var export_path = "res://procedural_generation_snapshot.png"
	out_img.save_png(export_path)
	print("SUCCESS: High-resolution 3x3 array matrix matrix serialized cleanly back to: ", export_path)

func _rasterize_tectonics_to_disk_buffer(img: Image, data: Dictionary, offset: Vector2, scale: float) -> void:
	var landmarks: Array = data["landmarks"]
	for plate in landmarks:
		var plot_c = Vector2i((plate.pos * scale) + offset)
		var p_dir = plate.dir
		for ox in range(-2, 3):
			for oy in range(-2, 3):
				var target_p = plot_c + Vector2i(ox, oy)
				if target_p.x >= 0 and target_p.x < img.get_width() and target_p.y >= 0 and target_p.y < img.get_height():
					img.set_pixelv(target_p, Color.MAGENTA if not plate.ocean else Color.CYAN)
		for s in range(25):
			var plot_l = Vector2i(Vector2(plot_c) + (p_dir * float(s)))
			if plot_l.x >= 0 and plot_l.x < img.get_width() and plot_l.y >= 0 and plot_l.y < img.get_height():
				img.set_pixelv(plot_l, Color.WHITE)

func _rasterize_vectors_to_image_buffer(img: Image, data: Dictionary, offset: Vector2, scale: float) -> void:
	var cities: Array = data["city_nodes"]
	var graph: Dictionary = data["gameplay_graph"]
	var start: Vector2 = data["start_node"]
	var end: Vector2 = data["end_node"]
	
	for parent in graph.keys():
		for child in graph[parent]:
			var p1 = parent * scale + offset
			var p2 = child * scale + offset
			var steps = int(p1.distance_to(p2))
			for s in range(steps):
				var plot_p = Vector2i(p1.lerp(p2, float(s) / maxf(1.0, float(steps))))
				if plot_p.x >= 0 and plot_p.x < img.get_width() and plot_p.y >= 0 and plot_p.y < img.get_height():
					img.set_pixelv(plot_p, Color.WHITE)
					
	for city in cities:
		var plot_c = Vector2i(city * scale + offset)
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var target_p = plot_c + Vector2i(ox, oy)
				if target_p.x >= 0 and target_p.x < img.get_width() and target_p.y >= 0 and target_p.y < img.get_height():
					img.set_pixelv(target_p, Color.html("#ecc94b"))
					
	if start != Vector2.ZERO:
		var plot_s = Vector2i(start * scale + offset)
		for ox in range(-3, 4):
			for oy in range(-3, 4):
				var target_p = plot_s + Vector2i(ox, oy)
				if target_p.x >= 0 and target_p.x < img.get_width() and target_p.y >= 0 and target_p.y < img.get_height():
					img.set_pixelv(target_p, Color.GREEN)
				
	if end != Vector2.ZERO:
		var plot_e = Vector2i(end * scale + offset)
		for ox in range(-3, 4):
			for oy in range(-3, 4):
				var target_p = plot_e + Vector2i(ox, oy)
				if target_p.x >= 0 and target_p.x < img.get_width() and target_p.y >= 0 and target_p.y < img.get_height():
					img.set_pixelv(target_p, Color.RED)
