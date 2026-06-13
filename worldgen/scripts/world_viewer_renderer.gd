class_name WorldViewerRenderer
extends WorldViewer

func _draw() -> void:
	super._draw()
	
	if current_step_index >= step_names.size(): return
	var step_name = step_names[current_step_index]
	var screen_size = get_viewport_rect().size
	var scale = screen_size.x / float(generator.settings.map_width)
	
	if step_name == 'Tectonics_Debug' and generator.snapshots.has(step_name):
		_draw_tectonics(generator.snapshots[step_name], Vector2.ZERO, scale)
	elif step_name == 'All_Steps_Grid':
		var cell_size = screen_size / 3.0
		var grid_scale = cell_size.x / float(generator.settings.map_width)
		if generator.snapshots.has('Tectonics_Debug'):
			_draw_tectonics(generator.snapshots['Tectonics_Debug'], Vector2(cell_size.x, 0), grid_scale)

	_draw_legend(step_name)

func _draw_tectonics(data: Dictionary, offset: Vector2, s: float) -> void:
	for plate in data.get('landmarks', []):
		var p = plate.pos * s + offset
		var c = Color.RED if not plate.ocean else Color.CYAN
		draw_circle(p, 5 * s, c)
		draw_line(p, p + plate.dir * 30 * s, c, 2 * s)

func _draw_legend(step: String) -> void:
	var items = generator.get_step_metadata(step)
	var font = ThemeDB.get_fallback_font()
	var y = get_viewport_rect().size.y - 30
	for i in range(items.size()):
		var x = 20 + (i * 150)
		draw_rect(Rect2(x, y, 14, 14), items[i].c, true)
		draw_string(font, Vector2(x + 20, y + 12), items[i].n, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
