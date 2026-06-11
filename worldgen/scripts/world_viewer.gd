# world_viewer.gd
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
			
			# HIGH-CONTRAST RIVERS VISUAL SNAPSHOT STEP: Clears out mapping artifacts to track river networks cleanly
			if step == "Rivers_Highlight":
				var is_river_pixel = false
				for rx in range(-1, 2):
					for ry in range(-1, 2):
						if rivers.has(orig_pos + Vector2i(rx, ry)):
							is_river_pixel = true
							break
				color = Color.html("#00ffff") if (is_river_pixel and val >= generator.settings.ocean_threshold) else Color.html("#1a365d")
				img.set_pixelv(target_pos, color)
				continue
			
			if step in ["Landmass", "Tectonics", "PeaksAndValleys", "Erosion"]:
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
						"Arctic": color = Color.html("#f7fafc")
						"Tundra": color = Color.html("#edf2f7")
						"Plains": color = Color.html("#9ae6b4")
						"Forest": color = Color.html("#2f855a")
						"Desert": color = Color.html("#feebc8")
						"Rainforest": color = Color.html("#22543d")
						"Mountain":
							if val > 0.82: color = Color.html("#ffffff")
							else: color = Color.html("#4a5568")
						_: color = Color.BLACK
			
			var thick_river = false
			for rx in range(-1, 2):
				for ry in range(-1, 2):
					if rivers.has(orig_pos + Vector2i(rx, ry)):
						thick_river = true
						break
						
			if step in ["Climate", "Cities", "Graph"] and thick_river and val >= generator.settings.ocean_threshold:
				color = Color.html("#3182ce")
				
			img.set_pixelv(target_pos, color)

func _render_all_steps_grid(w: int, h: int) -> void:
	var comp_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pipelines = ["Landmass", "Tectonics", "PeaksAndValleys", "Rivers_Highlight", "Climate", "Graph"]
	
	# CLEAN THREE-COLUMN NO-PADDING TILING
	var sub_w = int(w / 3)
	var sub_h = int(h / 2)
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
	
	var pipelines = ["Landmass", "Tectonics", "PeaksAndValleys", "Rivers_Highlight", "Climate", "Graph"]
	var sub_w = int(w / 3)
	var sub_h = int(h / 2)
	var scale = 1.0 / 3.0
	
	for idx in range(pipelines.size()):
		var step = pipelines[idx]
		if generator.snapshots.has(step):
			var offset = Vector2i((idx % 3) * sub_w, (idx / 3) * sub_h)
			_fill_image_with_step_pixels(out_img, generator.snapshots[step], step, offset, w, h, scale)
			
	# EXPORT INTEGRATION VECTOR RASTERIZER: Burns your nodes and pathway vectors directly onto the output .png image
	_rasterize_vectors_to_image_buffer(out_img, generator.snapshots["Climate"], Vector2(sub_w, sub_h), scale)
	_rasterize_vectors_to_image_buffer(out_img, generator.snapshots["Graph"], Vector2(sub_w * 2, sub_h), scale)
	
	var export_path = "res://procedural_generation_snapshot.png"
	out_img.save_png(export_path)
	print("SUCCESS: Full high-resolution snapshot exported with active node tracks directly to: ", export_path)

func _rasterize_vectors_to_image_buffer(img: Image, data: Dictionary, offset: Vector2, scale: float) -> void:
	var cities: Array = data["city_nodes"]
	var graph: Dictionary = data["gameplay_graph"]
	var start: Vector2 = data["start_node"]
	var end: Vector2 = data["end_node"]
	
	for parent in graph.keys():
		for child in graph[parent]:
			var p1 = parent * scale + offset
			var p2 = child * scale + offset
			# Draw simple line segments on pixel buffer tracks
			var steps = int(p1.distance_to(p2))
			for s in range(steps):
				var plot_p = Vector2i(p1.lerp(p2, float(s) / steps))
				if plot_p.x >= 0 and plot_p.x < img.get_width() and plot_p.y >= 0 and plot_p.y < img.get_height():
					img.set_pixelv(plot_p, Color.WHITE)
					
	for city in cities:
		var plot_c = Vector2i(city * scale + offset)
		for ox in range(-2, 3):
			for oy in range(-2, 3):
				var target_p = plot_c + Vector2i(ox, oy)
				if target_p.x >= 0 and target_p.x < img.get_width() and target_p.y >= 0 and target_p.y < img.get_height():
					img.set_pixelv(target_p, Color.html("#ecc94b"))
					
	if start != Vector2.ZERO:
		var plot_s = Vector2i(start * scale + offset)
		for ox in range(-4, 5):
			for oy in range(-4, 5):
				img.set_pixelv(plot_s + Vector2i(ox, oy), Color.GREEN)
				
	if end != Vector2.ZERO:
		var plot_e = Vector2i(end * scale + offset)
		for ox in range(-4, 5):
			for oy in range(-4, 5):
				img.set_pixelv(plot_e + Vector2i(ox, oy), Color.RED)

func _draw() -> void:
	if current_step_index == -1 or step_names.is_empty(): return
	if cached_texture: draw_texture(cached_texture, Vector2.ZERO)
	
	var step_name: String = step_names[current_step_index]
	
	if step_name == "All_Steps_Grid":
		_draw_grid_vector_overlays()
		return
		
	var data: Dictionary = generator.snapshots[step_name]
	_draw_vector_layer(data, step_name, Vector2.ZERO, 1.0)
	_draw_ui_legend(step_name)

func _draw_grid_vector_overlays() -> void:
	var w = generator.settings.map_width
	var h = generator.settings.map_height
	var sub_w = int(w / 3)
	var sub_h = int(h / 2)
	var scale = 1.0 / 3.0
	
	if generator.snapshots.has("Climate"):
		_draw_vector_layer(generator.snapshots["Climate"], "Climate", Vector2(1 * sub_w, 1 * sub_h), scale)
	if generator.snapshots.has("Graph"):
		_draw_vector_layer(generator.snapshots["Graph"], "Graph", Vector2(2 * sub_w, 1 * sub_h), scale)
		
	draw_line(Vector2(sub_w, 0), Vector2(sub_w, h), Color.BLACK, 2.0)
	draw_line(Vector2(sub_w * 2, 0), Vector2(sub_w * 2, h), Color.BLACK, 2.0)
	draw_line(Vector2(0, sub_h), Vector2(w, sub_h), Color.BLACK, 2.0)

func _draw_vector_layer(data: Dictionary, step: String, offset: Vector2, scale: float) -> void:
	var cities: Array = data["city_nodes"]
	var graph: Dictionary = data["gameplay_graph"]
	var start: Vector2 = data["start_node"]
	var end: Vector2 = data["end_node"]
	var h_map: Dictionary = data["height_map"]
	
	if step in ["Climate", "Cities", "Graph", "Rivers_Highlight"]:
		for parent_node in graph.keys():
			for child_node in graph[parent_node]:
				var p1 = (parent_node * scale) + offset
				var p2 = (child_node * scale) + offset
				
				var is_sea_route = false
				var steps = 10
				for s in range(steps + 1):
					var sample_pos = Vector2i(parent_node.lerp(child_node, float(s) / steps))
					if h_map.get(sample_pos, 0.5) < generator.settings.ocean_threshold:
						is_sea_route = true
						break
						
				var line_color = Color.html("#ffffff") if not is_sea_route else Color.html("#38bdf8")
				draw_line(p1, p2, line_color, 2.0 * scale, true)
				
				var mid = p1.lerp(p2, 0.55)
				var dir = (p2 - p1).normalized()
				var perp = Vector2(-dir.y, dir.x)
				var arrow_size = 6.0 * scale
				
				var a_tip = mid + dir * arrow_size
				var a_left = mid - dir * arrow_size + perp * (arrow_size * 0.6)
				var a_right = mid - dir * arrow_size - perp * (arrow_size * 0.6)
				
				draw_colored_polygon([a_tip, a_left, a_right], Color.html("#fb923c"))
				
		for city in cities:
			draw_circle((city * scale) + offset, 4.5 * scale, Color.html("#ecc94b"))
			
		if start != Vector2.ZERO: 
			draw_circle((start * scale) + offset, 9.0 * scale, Color.GREEN)
		if end != Vector2.ZERO: 
			draw_circle((end * scale) + offset, 9.0 * scale, Color.RED)

func _draw_ui_legend(step: String) -> void:
	var items = []
	if step in ["Landmass", "Tectonics", "PeaksAndValleys", "Erosion"]:
		items = [
			{"c": Color.html("#1a365d"), "n": "Ocean Abyss"},
			{"c": Color.html("#2b6cb0"), "n": "Shallow Water"},
			{"c": Color.html("#2f855a"), "n": "Green Plains"},
			{"c": Color.html("#ecc94b"), "n": "Hills/Foothills"},
			{"c": Color.html("#718096"), "n": "Rocky Canyons"},
			{"c": Color.html("#ffffff"), "n": "Snow Peaks"}
		]
	elif step == "Rivers_Highlight":
		items = [
			{"c": Color.html("#00ffff"), "n": "Neon Water Networks"},
			{"c": Color.html("#1a365d"), "n": "Ocean Abyss"}
		]
	else:
		items = [
			{"c": Color.html("#3182ce"), "n": "Rivers/Lakes"},
			{"c": Color.html("#9ae6b4"), "n": "Plains"},
			{"c": Color.html("#2f855a"), "n": "Forest"},
			{"c": Color.html("#feebc8"), "n": "Desert Sand"},
			{"c": Color.html("#4a5568"), "n": "Mountains"},
			{"c": Color.html("#ecc94b"), "n": "Standard Node"}
		]
	
	var font = ThemeDB.get_fallback_font()
	var start_y = generator.settings.map_height - 35
	for i in range(items.size()):
		var x_offset = 12 + (i * 125)
		draw_rect(Rect2(x_offset, start_y, 14, 14), items[i].c, true)
		draw_string(font, Vector2(x_offset + 20, start_y + 12), items[i].n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
