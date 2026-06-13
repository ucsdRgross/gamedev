class_name WorldViewer
extends Node2D

var generator: WorldGenerator
var label: Label
var texture_rect: TextureRect

var step_names: Array[String] = ['Landmass', 'Tectonics_Debug', 'Tectonics', 'PeaksAndValleys', 'Flow', 'Erosion', 'Climate', 'Cities', 'All_Steps_Grid']
var current_step_index: int = 0

func _ready() -> void:
	label = get_node_or_null('CanvasLayer/Label')
	texture_rect = get_node_or_null('CanvasLayer/TextureRect')
	if texture_rect: texture_rect.visible = false # We use background _draw instead
	
	generator = $WorldGenerator
	generator.generation_step_finished.connect(_on_generation_step_finished)

func _on_generation_step_finished(step_name: String) -> void:
	if step_name == 'All_Steps_Grid':
		_download_result_to_disk()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed('ui_right'):
		current_step_index = (current_step_index + 1) % step_names.size()
		_display_snapshot()
	elif event.is_action_pressed('ui_left'):
		current_step_index = (current_step_index - 1 + step_names.size()) % step_names.size()
		_display_snapshot()

func _display_snapshot() -> void:
	if label: label.text = 'Step: ' + step_names[current_step_index] + ' (Arrows to Cycle)'
	queue_redraw()

func _download_result_to_disk() -> void:
	if generator.snapshots.has('Climate'):
		var tex = generator.snapshots['Climate']['texture']
		tex.get_image().save_png('res://procedural_generation_snapshot.png')
		print('[WorldViewer] Saved PNG to res://procedural_generation_snapshot.png')

func _draw() -> void:
	if not generator: return
	var step_name = step_names[current_step_index]
	var screen_size = get_viewport_rect().size
	
	if step_name == 'All_Steps_Grid':
		var grid_steps = ['Landmass', 'Tectonics_Debug', 'Tectonics', 'PeaksAndValleys', 'Erosion', 'Climate', 'Cities']
		var cell_size = screen_size / 3.0
		for i in range(grid_steps.size()):
			var s = grid_steps[i]
			if generator.snapshots.has(s):
				var tex = generator.snapshots[s]['texture']
				var pos = Vector2((i % 3) * cell_size.x, (i / 3) * cell_size.y)
				draw_texture_rect(tex, Rect2(pos, cell_size), false)
	else:
		if generator.snapshots.has(step_name):
			var tex = generator.snapshots[step_name]['texture']
			draw_texture_rect(tex, Rect2(Vector2.ZERO, screen_size), false)
