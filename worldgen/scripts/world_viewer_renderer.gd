# world_viewer_renderer.gd
class_name WorldViewerRenderer
extends WorldViewer

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
	var sub_h = int(h / 3)
	var scale = 1.0 / 3.0
	
	if generator.snapshots.has("Tectonics_Debug"):
		var tect_data: Dictionary = generator.snapshots["Tectonics_Debug"]
		_draw_vector_layer(tect_data, "Tectonics_Debug", Vector2(sub_w, 0), scale)
		
	if generator.snapshots.has("Climate"):
		var clim_data: Dictionary = generator.snapshots["Climate"]
		_draw_vector_layer(clim_data, "Draw_Vectors", Vector2(sub_w * 2, sub_h), scale)
		
	if generator.snapshots.has("Cities"):
		var city_data: Dictionary = generator.snapshots["Cities"]
		_draw_vector_layer(city_data, "Draw_Vectors", Vector2(sub_w, sub_h * 2), scale)
		
	if generator.snapshots.has("Graph"):
		var graph_data: Dictionary = generator.snapshots["Graph"]
		_draw_vector_layer(graph_data, "Draw_Vectors", Vector2(sub_w * 2, sub_h * 2), scale)
		
	# Draw lines dividing the 3x3 sectors
	draw_line(Vector2(sub_w, 0), Vector2(sub_w, h), Color.BLACK, 2.0)
	draw_line(Vector2(sub_w * 2, 0), Vector2(sub_w * 2, h), Color.BLACK, 2.0)
	draw_line(Vector2(0, sub_h), Vector2(w, sub_h), Color.BLACK, 2.0)
	draw_line(Vector2(0, sub_h * 2), Vector2(w, sub_h * 2), Color.BLACK, 2.0)

func _draw_vector_layer(data: Dictionary, step: String, offset: Vector2, scale: float) -> void:
	var cities: Array = data.get("city_nodes", [])
	var graph: Dictionary = data.get("gameplay_graph", {})
	var start: Vector2 = data.get("start_node", Vector2.ZERO)
	var end: Vector2 = data.get("end_node", Vector2.ZERO)
	var h_map: Dictionary = data.get("height_map", {})
	var landmarks: Array = data.get("landmarks", [])
	
	if step == "Tectonics_Debug":
		var plate_ids: PackedInt32Array = data.get("plate_id_buffer", PackedInt32Array())
		var mw = generator.settings.map_width
		
		for plate in landmarks:
			var p_center = (plate.pos * scale) + offset
			var p_dir = plate.dir
			var p_color = Color.html("#f43f5e") if not plate.ocean else Color.html("#0ea5e9")
			
			draw_circle(p_center, 6.0 * scale, p_color)
			draw_line(p_center, p_center + (p_dir * 55.0 * scale), p_color, 3.0 * scale, true)
			
			var arrow_tip = p_center + (p_dir * 55.0 * scale)
			var perp = Vector2(-p_dir.y, p_dir.x)
			var wing_l = arrow_tip - (p_dir * 12.0 * scale) + (perp * 8.0 * scale)
			var wing_r = arrow_tip - (p_dir * 12.0 * scale) - (perp * 8.0 * scale)
			draw_colored_polygon([arrow_tip, wing_l, wing_r], p_color)
			
		if not plate_ids.is_empty():
			for y in range(0, int(generator.settings.map_height * scale)):
				for x in range(0, int(mw * scale)):
					var ox = int(x / scale)
					var oy = int(y / scale)
					var idx = (oy * mw) + ox
					var right_idx = (oy * mw) + (ox + 3) if ox + 3 < mw else idx
					var down_idx = ((oy + 3) * mw) + ox if oy + 3 < generator.settings.map_height else idx
					
					if plate_ids[idx] != plate_ids[right_idx] or plate_ids[idx] != plate_ids[down_idx]:
						draw_rect(Rect2(Vector2(x, y) + offset, Vector2(1.5, 1.5)), Color.html("#a855f7"), true)
		return

	if step in ["Cities", "Graph", "Climate", "Draw_Vectors"]:
		for parent_node in graph.keys():
			for child_node in graph[parent_node]:
				var p1 = (parent_node * scale) + offset
				var p2 = (child_node * scale) + offset
				
				var is_sea_route = h_map.get(Vector2i(parent_node), 0.5) < generator.settings.ocean_threshold
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
			
		if start != Vector2.ZERO: draw_circle((start * scale) + offset, 9.0 * scale, Color.GREEN)
		if end != Vector2.ZERO: draw_circle((end * scale) + offset, 9.0 * scale, Color.RED)

func _draw_ui_legend(step: String) -> void:
	var items = []
	if step in ["Landmass", "Tectonics", "PeaksAndValleys", "Erosion"]:
		items = [
			{"c": Color.html("#1a365d"), "n": "Ocean Abyss"}, {"c": Color.html("#2b6cb0"), "n": "Shallow Water"},
			{"c": Color.html("#2f855a"), "n": "Green Plains"}, {"c": Color.html("#ecc94b"), "n": "Hills/Foothills"},
			{"c": Color.html("#718096"), "n": "Rocky Canyons"}, {"c": Color.html("#ffffff"), "n": "Snow Peaks"}
		]
	elif step == "Tectonics_Debug":
		items = [
			{"c": Color.html("#f43f5e"), "n": "Continental Crust Plates"},
			{"c": Color.html("#0ea5e9"), "n": "Oceanic Basin Plates"},
			{"c": Color.html("#a855f7"), "n": "Tectonic Fault Boundary Lines"}
		]
	elif step == "Rivers_Only":
		items = [
			{"c": Color.html("#38bdf8"), "n": "Pure River Network"}, {"c": Color.html("#0f172a"), "n": "Substrate Floor"}
		]
	else:
		items = [
			{"c": Color.html("#2563eb"), "n": "Rivers/Lakes"}, {"c": Color.html("#991b1b"), "n": "Volcanic Crag"},
			{"c": Color.html("#047857"), "n": "Toxic Swamp"}, {"c": Color.html("#7c2d12"), "n": "Fissures"},
			{"c": Color.html("#38bdf8"), "n": "Frostwastes"}, {"c": Color.html("#ecc94b"), "n": "City Node"}
		]
	
	var font = ThemeDB.get_fallback_font()
	var start_y = generator.settings.map_height - 35
	for i in range(items.size()):
		var x_offset = 12 + (i * 125)
		draw_rect(Rect2(x_offset, start_y, 14, 14), items[i].c, true)
		draw_string(font, Vector2(x_offset + 20, start_y + 12), items[i].n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
