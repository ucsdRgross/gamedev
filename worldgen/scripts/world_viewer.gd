# world_viewer.gd
class_name WorldViewer
extends Node2D

var generator: WorldGenerator
var label: Label

var step_names: Array[String] = []
var current_step_index: int = -1
var cached_texture: ImageTexture

func _ready() -> void:
	label = get_node_or_null("CanvasLayer/Label")
	
	if not generator:
		generator = $WorldGenerator
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
		_download_grid_to_disk_direct_pixel_method()

func _unhandled_input(event: InputEvent) -> void:
	if step_names.is_empty(): return
	
	if event.is_action_pressed("ui_right"):
		current_step_index = (current_step_index + 1) % step_names.size()
		_display_snapshot(step_names[current_step_index])
	elif event.is_action_pressed("ui_left"):
		current_step_index = (current_step_index - 1 + step_names.size()) % step_names.size()
		_display_snapshot(step_names[current_step_index])

func _display_snapshot(step_name: String) -> void:
	if label:
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
			
			if step in ["Landmass", "Tectonics", "Tectonics_Debug", "PeaksAndValleys", "Erosion"]:
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
	var scale = 1.0 / 3.0
	var sub_w = int(w / 3)
	var sub_h = int(h / 3)
	
	for idx in range(pipelines.size()):
		var step = pipelines[idx]
		if not generator.snapshots.has(step): continue
		var offset = Vector2i((idx % 3) * sub_w, (idx / 3) * sub_h)
		_fill_image_with_step_pixels(comp_img, generator.snapshots[step], step, offset, w, h, scale)
		
	cached_texture = ImageTexture.create_from_image(comp_img)
	queue_redraw()

# =================================================================
# THE SAFE DIRECT DIRECT-PIXEL MASTER RASTERIZER (Bypasses viewports entirely)
# =================================================================
func _download_grid_to_disk_direct_pixel_method() -> void:
	var w = generator.settings.map_width
	var h = generator.settings.map_height
	var out_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	
	var pipelines = ["Landmass", "Tectonics_Debug", "Tectonics", "PeaksAndValleys", "Erosion", "Rivers_Only", "Climate", "Cities", "Graph"]
	var scale = 1.0 / 3.0
	var sub_w = int(w / 3)
	var sub_h = int(h / 3)
	
	# 1. Base Landscape Pass Layer
	for idx in range(pipelines.size()):
		var step = pipelines[idx]
		if generator.snapshots.has(step):
			var offset = Vector2i((idx % 3) * sub_w, (idx / 3) * sub_h)
			_fill_image_with_step_pixels(out_img, generator.snapshots[step], step, offset, w, h, scale)
			
	# 2. Burn Tectonic fault line boundaries onto Slot 2 (Row 0, Col 1)
	if generator.snapshots.has("Tectonics_Debug"):
		var data = generator.snapshots["Tectonics_Debug"]
		var plate_ids: PackedInt32Array = data.get("plate_id_buffer", PackedInt32Array())
		var landmarks: Array = data.get("landmarks", [])
		var offset = Vector2i(sub_w, 0)
		var mw = generator.settings.map_width
		
		if not plate_ids.is_empty():
			for y in range(sub_h):
				for x in range(sub_w):
					var ox = int(x / scale)
					var oy = int(y / scale)
					var idx = (oy * mw) + ox
					var right_idx = (oy * mw) + (ox + 3) if ox + 3 < mw else idx
					var down_idx = ((oy + 3) * mw) + ox if oy + 3 < generator.settings.map_height else idx
					
					if plate_ids[idx] != plate_ids[right_idx] or plate_ids[idx] != plate_ids[down_idx]:
						out_img.set_pixelv(Vector2i(x, y) + offset, Color.html("#a855f7"))
						
		for plate in landmarks:
			var plot_c = Vector2i((plate.pos * scale)) + offset
			var p_dir = plate.dir
			var p_color = Color.html("#f43f5e") if not plate.ocean else Color.html("#0ea5e9")
			
			for ox in range(-2, 3):
				for oy in range(-2, 3):
					var tp = plot_c + Vector2i(ox, oy)
					if tp.x >= 0 and tp.x < w and tp.y >= 0 and tp.y < h: out_img.set_pixelv(tp, p_color)
			for s in range(int(55 * scale)):
				var tl = Vector2i(Vector2(plot_c) + (p_dir * float(s)))
				if tl.x >= 0 and tl.x < w and tl.y >= 0 and tl.y < h: out_img.set_pixelv(tl, p_color)

	# 3. Burn Poisson Disc Nodes onto Slot 8 (Row 2, Col 1)
	if generator.snapshots.has("Cities"):
		_rasterize_graph_primitives_direct(out_img, generator.snapshots["Cities"], Vector2i(sub_w, sub_h * 2), scale)
		
	# 4. Burn Path Tracks onto Slot 9 (Row 2, Col 2)
	if generator.snapshots.has("Graph"):
		_rasterize_graph_primitives_direct(out_img, generator.snapshots["Graph"], Vector2i(sub_w * 2, sub_h * 2), scale)
		
	# 5. Burn Black Grid Borders Framework Lines
	for y in range(h):
		out_img.set_pixel(sub_w, y, Color.BLACK)
		out_img.set_pixel(sub_w * 2, y, Color.BLACK)
	for x in range(w):
		out_img.set_pixel(x, sub_h, Color.BLACK)
		out_img.set_pixel(x, sub_h * 2, Color.BLACK)
		
	var export_path = "res://procedural_generation_snapshot.png"
	out_img.save_png(export_path)
	print("SUCCESS: High-resolution direct 3x3 layout matrix written cleanly to disk: ", export_path)

func _rasterize_graph_primitives_direct(img: Image, data: Dictionary, offset: Vector2i, scale: float) -> void:
	var cities: Array = data.get("city_nodes", [])
	var graph: Dictionary = data.get("gameplay_graph", {})
	var start: Vector2 = data.get("start_node", Vector2.ZERO)
	var end: Vector2 = data.get("end_node", Vector2.ZERO)
	
	# Draw lines link connections
	for parent in graph.keys():
		for child in graph[parent]:
			var p1 = parent * scale + Vector2(offset)
			var p2 = child * scale + Vector2(offset)
			var length = int(p1.distance_to(p2))
			for s in range(length):
				var pt = Vector2i(p1.lerp(p2, float(s) / maxf(1.0, float(length))))
				if pt.x >= 0 and pt.x < img.get_width() and pt.y >= 0 and pt.y < img.get_height():
					img.set_pixelv(pt, Color.WHITE)
					
	# Draw node dot entries
	for city in cities:
		var plot_c = Vector2i(city * scale) + offset
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var tp = plot_c + Vector2i(ox, oy)
				if tp.x >= 0 and tp.x < img.get_width() and tp.y >= 0 and tp.y < img.get_height():
					img.set_pixelv(tp, Color.html("#ecc94b"))
					
	# Draw start / end markers
	if start != Vector2.ZERO:
		var ps = Vector2i(start * scale) + offset
		for ox in range(-2, 3):
			for oy in range(-2, 3):
				if ps.x+ox >= 0 and ps.x+ox < img.get_width() and ps.y+oy >= 0 and ps.y+oy < img.get_height():
					img.set_pixelv(ps + Vector2i(ox, oy), Color.GREEN)
	if end != Vector2.ZERO:
		var pe = Vector2i(end * scale) + offset
		for ox in range(-2, 3):
			for oy in range(-2, 3):
				if pe.x+ox >= 0 and pe.x+ox < img.get_width() and pe.y+oy >= 0 and pe.y+oy < img.get_height():img.set_pixelv(pe + Vector2i(ox, oy), Color.RED)
