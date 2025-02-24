extends Node2D

@onready var paint_tool = $Camera2D/PaintTool
@onready var camera_2d = $Camera2D
@onready var line_2d = $Line2D
@onready var transform_ui = $TransformUI

#texture size is overriden by viewport size
var texture_size : int = 512
var last_mouse_pos : Vector2
var mouse_pos : Vector2
var start_pos : Vector2
var can_transform := false
var last_origin : Vector2
#[top left, bot right]
var bounds : PackedVector2Array = [Vector2.ZERO, Vector2.ZERO]

enum TRANSFORMING {
	NOTHING,
	TRANSLATING,
	ROTATING,
	SCALING
}
var modifying := TRANSFORMING.NOTHING

var polygon : PackedVector2Array
var last_polygon : PackedVector2Array

func _ready():
	paint_tool.texture = ImageTexture.new()
	paint_tool.texture.set_size_override(Vector2i(texture_size, texture_size))
	Input.use_accumulated_input = false
	Signals.player_move_selection.connect(self._on_player_move_selection)

func _process(delta):
	paint_tool.material.set_shader_parameter(&"world_pos", paint_tool.global_position)

func _input(event):
	for mouse_event in [InputEventMouseButton, InputEventMouseMotion, InputEventScreenDrag, InputEventScreenTouch]:
		if is_instance_of(event, mouse_event):
			last_mouse_pos = mouse_pos
			mouse_pos = event.position + paint_tool.global_position
			
			if Global.is_drawing:
				draw()	
			elif can_transform:
				modify()
			if modifying != TRANSFORMING.ROTATING:
				last_origin = Vector2(bounds[0].x + bounds[1].x, bounds[0].y + bounds[1].y) / 2
			
			break
			
	if event.is_action_pressed(&"Left Click"):
		if Global.is_modifying:
			if modifying != TRANSFORMING.NOTHING:
				can_transform = true
				transform_ui.visible = false
		else:
			line_2d.clear_points()
			Global.is_drawing = true
			start_pos = event.position
			bounds = [start_pos, start_pos]
	
	if event.is_action_pressed(&"Right Click"):
		if not Global.is_drawing:	
			if Global.is_modifying:
				last_polygon = polygon
				Global.is_modifying = false
				can_transform = false
				modifying = TRANSFORMING.NOTHING
				start_pos = event.position
				line_2d.clear_points()
				paint_tool.material.set_shader_parameter(&"size", line_2d.get_point_count())
				paint_tool.material.set_shader_parameter(&"points", line_2d.points)
				Signals.new_selection.emit(line_2d.points)
				transform_ui.visible = false
			else:
				polygon = last_polygon
				Global.is_modifying = true
				line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
				paint_tool.material.set_shader_parameter(&"size", polygon.size())
				paint_tool.material.set_shader_parameter(&"points", polygon)
				Signals.new_selection.emit(polygon)
				show_transform_ui()

	if event.is_action_released(&"Left Click"):
		if Global.is_drawing:
			Global.is_drawing = false
			Global.is_modifying = true
			line_2d.add_point(line_2d.get_point_position(0))
			polygon = line_2d.points
			line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
			show_transform_ui()
			last_origin = Vector2(bounds[0].x + bounds[1].x, bounds[0].y + bounds[1].y) / 2
			
		elif Global.is_modifying:
			if modifying == TRANSFORMING.ROTATING:
				line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
			can_transform = false
			show_transform_ui()

func modify():
	if modifying == TRANSFORMING.TRANSLATING:
		var change : Vector2 = mouse_pos - last_mouse_pos
		move_selection(change)
		
	elif modifying == TRANSFORMING.SCALING:
		var origin := Vector2(bounds[0].x + bounds[1].x, bounds[0].y + bounds[1].y) / 2
		var scale_factor := (mouse_pos - origin) / (last_mouse_pos - last_origin)
		last_origin = origin
		#accomadate divide by zero
		if is_inf(scale_factor.x) or is_nan(scale_factor.x):
			scale_factor.x = 0
		if is_inf(scale_factor.y) or is_nan(scale_factor.y):
			scale_factor.y = 0
		var new_bound : PackedVector2Array = [origin, origin]
		for i:int in range(polygon.size()):
			var og_point := polygon[i]
			var vector := og_point - origin
			polygon[i] = vector * scale_factor + origin
			if polygon[i].x < new_bound[0].x:
				new_bound[0].x = polygon[i].x
			elif polygon[i].x > new_bound[1].x:
				new_bound[1].x = polygon[i].x
			if polygon[i].y < new_bound[0].y:
				new_bound[0].y = polygon[i].y
			elif polygon[i].y > new_bound[1].y:
				new_bound[1].y = polygon[i].y
		paint_tool.material.set_shader_parameter(&"points", polygon)
		#polygon2d_created.emit(polygon)
		bounds = new_bound
		paint_tool.material.set_shader_parameter(&"bounds", bounds)
		line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
		Signals.selection_scaled.emit(scale_factor, origin)
	
	elif modifying == TRANSFORMING.ROTATING:
		var origin := Vector2(line_2d.points[0].x + line_2d.points[2].x, line_2d.points[0].y + line_2d.points[2].y) / 2
		var rotate := (last_mouse_pos - last_origin).angle_to(mouse_pos - origin)
		last_origin = origin
		var new_bound : PackedVector2Array = [origin, origin]
		for i:int in range(polygon.size()):
			var og_point := polygon[i]
			var vector := og_point - origin
			polygon[i] = vector.rotated(rotate) + origin
			if polygon[i].x < new_bound[0].x:
				new_bound[0].x = polygon[i].x
			elif polygon[i].x > new_bound[1].x:
				new_bound[1].x = polygon[i].x
			if polygon[i].y < new_bound[0].y:
				new_bound[0].y = polygon[i].y
			elif polygon[i].y > new_bound[1].y:
				new_bound[1].y = polygon[i].y
		paint_tool.material.set_shader_parameter(&"points", polygon)
		#polygon2d_created.emit(polygon)
		bounds = new_bound
		paint_tool.material.set_shader_parameter(&"bounds", bounds)
		for i:int in range(line_2d.get_point_count()):
			var og_point : Vector2 = line_2d.get_point_position(i)
			var vector := og_point - origin
			line_2d.set_point_position(i, vector.rotated(rotate) + origin)
		Signals.selection_rotated.emit(rotate, origin)
	

func move_selection(change : Vector2):
	for i:int in range(polygon.size()):
		polygon[i] += change
	paint_tool.material.set_shader_parameter(&"points", polygon)
	Signals.new_selection.emit(polygon)
	for i:int in range(bounds.size()):
		bounds[i] += change
	#last_origin += change
	#material.set_shader_parameter("bounds", bounds)
	line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
	transform_ui.position = (bounds[0] + bounds[1]) / 2 - transform_ui.size * transform_ui.scale / 2
	Signals.selection_moved.emit(change)

func draw():
	find_bounds()
	var array_size = line_2d.get_point_count()
	if array_size < 2:
		line_2d.add_point(mouse_pos)
	else:
		var dot : float = (mouse_pos - line_2d.get_point_position(array_size - 1)).normalized().dot((line_2d.get_point_position(array_size - 1) - line_2d.get_point_position(array_size - 2)).normalized())	 
		if dot >= 0.95:
			line_2d.remove_point(array_size - 1)
			line_2d.add_point(mouse_pos)
		else:
			var distance_squared : int = line_2d.get_point_position(array_size - 1).distance_squared_to(mouse_pos)
			if distance_squared > 8:
				line_2d.add_point(mouse_pos)
		
	if array_size >= 3:
		line_2d.add_point(line_2d.get_point_position(0))
		paint_tool.material.set_shader_parameter(&"size", line_2d.get_point_count())
		paint_tool.material.set_shader_parameter(&"points", line_2d.points)	
		Signals.new_selection.emit(line_2d.points)
		line_2d.remove_point(line_2d.get_point_count() - 1)

func show_transform_ui():
	transform_ui.visible = true
	var center := (bounds[0] + bounds[1]) / 2
	var new_scale : Vector2 = (bounds[1] - bounds[0]) / transform_ui.size
	#makes scale and rotate outside of polygon, which looks better for now, but can be removed once there is actual ui art
	new_scale *= 1.5
	transform_ui.scale = new_scale.clamp(Vector2(1, 1), new_scale)
	transform_ui.position = center - transform_ui.size * transform_ui.scale / 2

func find_bounds():
	if mouse_pos.x < bounds[0].x:
		bounds[0].x = mouse_pos.x
	elif mouse_pos.x > bounds[1].x:
		bounds[1].x = mouse_pos.x
	if mouse_pos.y < bounds[0].y:
		bounds[0].y = mouse_pos.y
	elif mouse_pos.y > bounds[1].y:
		bounds[1].y = mouse_pos.y
	paint_tool.material.set_shader_parameter(&"bounds", bounds)
	
func _on_scale_region_mouse_entered():
	modifying = TRANSFORMING.SCALING

func _on_rotating_region_mouse_entered():
	modifying = TRANSFORMING.ROTATING

func _on_translating_region_mouse_entered():
	modifying = TRANSFORMING.TRANSLATING

func _on_transform_ui_mouse_exited():
	if !can_transform:
		modifying = TRANSFORMING.NOTHING
	
func _on_player_move_selection(change : Vector2):
	if not (modifying == TRANSFORMING.TRANSLATING and can_transform):
		move_selection(change)
