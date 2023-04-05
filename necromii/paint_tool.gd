extends TextureRect

var texture_size : int = 512
var last_mouse_pos : Vector2i
var mouse_pos : Vector2i
var start_pos : Vector2i
var can_transform := false
#[top left, bot right]
var bounds : PackedVector2Array = [Vector2(0,0), Vector2(0,0)]

enum TRANSFORMING {
	NOTHING,
	TRANSLATING,
	ROTATING,
	SCALING
}
var modifying := TRANSFORMING.NOTHING

@onready var line_2d = $Line2D
@onready var transform_ui = $TransformUI

var polygon : PackedVector2Array
signal polygon2d_created(polygon : PackedVector2Array)

func _ready():
	texture = ImageTexture.new()
	texture.set_size_override(Vector2i(texture_size, texture_size))

func _input(event):
	for mouse_event in [InputEventMouseButton, InputEventMouseMotion, InputEventScreenDrag, InputEventScreenTouch]:
		if is_instance_of(event, mouse_event):
			last_mouse_pos = mouse_pos
			mouse_pos = clamp_to_circle(event.position)
			break
	if event.is_action_pressed("Left Click"):
		if Global.is_modifying:
			if modifying != TRANSFORMING.NOTHING:
				can_transform = true
				transform_ui.visible = false
		else:
			line_2d.clear_points()
			Global.is_drawing = true
			start_pos = clamp_to_circle(event.position)
			bounds = [Vector2(start_pos.x, start_pos.y), Vector2(start_pos.x, start_pos.y)]
	if event.is_action_released("Left Click"):
		if Global.is_drawing:
			Global.is_drawing = false
			Global.is_modifying = true
			line_2d.add_point(line_2d.get_point_position(0))
			polygon = line_2d.points
			line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
			show_transform_ui()
			
		elif Global.is_modifying:
			if modifying == TRANSFORMING.ROTATING:
				line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
			can_transform = false
			show_transform_ui()
					
		
	if event.is_action_released("Right Click"):
		Global.is_modifying = false
		modifying = TRANSFORMING.NOTHING
		start_pos = clamp_to_circle(event.position)
		bounds = [Vector2(start_pos.x, start_pos.y), Vector2(start_pos.x, start_pos.y)]
		line_2d.clear_points()
		material.set_shader_parameter("size", line_2d.get_point_count())
		material.set_shader_parameter("points", line_2d.points)
		polygon2d_created.emit(line_2d.points)
		transform_ui.visible = false
		
	if Global.is_drawing:
		draw()	
		
	elif can_transform:
		modify()

func modify():
	if modifying == TRANSFORMING.TRANSLATING:
		var change : Vector2 = mouse_pos - last_mouse_pos
		#clamp changes to circle
		for corner in polygon:
			var clamped := clamp_to_circle(corner + change)
			if clamped != corner + change:
				change = clamped - corner
				
		for i in range(polygon.size()):
			polygon[i] += change
		material.set_shader_parameter("points", polygon)
		polygon2d_created.emit(polygon)
		for i in range(bounds.size()):
			bounds[i] += change
		#material.set_shader_parameter("bounds", bounds)
		
		line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
		transform_ui.position = (bounds[0] + bounds[1]) / 2 - transform_ui.size / 2
		
	elif modifying == TRANSFORMING.SCALING:
		var origin := Vector2(bounds[0].x + bounds[1].x, bounds[0].y + bounds[1].y) / 2
		var scale_factor := (Vector2(mouse_pos) - origin) / (Vector2(last_mouse_pos) - origin)
		#accomadate divide by zero
		if is_inf(scale_factor.x) or is_nan(scale_factor.x):
			scale_factor.x = 0
		if is_inf(scale_factor.y) or is_nan(scale_factor.y):
			scale_factor.y = 0
		print(scale_factor)
		for corner in polygon:
			var vector := corner - origin
			var new_point := vector * scale_factor + origin
			var clamped := clamp_to_circle(new_point)
			if clamped != new_point:
				scale_factor = (clamped - origin) / vector
				if is_inf(scale_factor.x) or is_nan(scale_factor.x):
					scale_factor.x = 0
				if is_inf(scale_factor.y) or is_nan(scale_factor.y):
					scale_factor.y = 0
		
		var new_bound : PackedVector2Array = [origin, origin]
		for i in range(polygon.size()):
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
		print(polygon[0])
		material.set_shader_parameter("points", polygon)
		polygon2d_created.emit(polygon)
		bounds = new_bound
		material.set_shader_parameter("bounds", bounds)
		line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
	
	elif modifying == TRANSFORMING.ROTATING:
		var origin := Vector2(line_2d.points[0].x + line_2d.points[2].x, line_2d.points[0].y + line_2d.points[2].y) / 2
		var rotate := (Vector2(last_mouse_pos) - origin).angle_to((Vector2(mouse_pos) - origin))
		for corner in polygon:
			var vector := corner - origin
			var new_point := vector.rotated(rotate) + origin
			var clamped := clamp_to_circle(new_point)
			#cannot use != because of floating point error
			if clamped.distance_squared_to(new_point) > 0.0001:
				rotate = 0
				break
		var new_bound : PackedVector2Array = [origin, origin]
		for i in range(polygon.size()):
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
		material.set_shader_parameter("points", polygon)
		polygon2d_created.emit(polygon)
		bounds = new_bound
		material.set_shader_parameter("bounds", bounds)
		for i in range(line_2d.get_point_count()):
			var og_point : Vector2 = line_2d.get_point_position(i)
			var vector := og_point - origin
			line_2d.set_point_position(i, vector.rotated(rotate) + origin)
	
func draw():
	find_bounds()
	var array_size = line_2d.get_point_count()
	if array_size < 2:
		line_2d.add_point(mouse_pos)
	else:
		var dot : float = (Vector2(mouse_pos) - line_2d.get_point_position(array_size - 1)).normalized().dot((line_2d.get_point_position(array_size - 1) - line_2d.get_point_position(array_size - 2)).normalized())	 
		if dot >= 0.95:
			line_2d.remove_point(array_size - 1)
			line_2d.add_point(mouse_pos)
		else:
			var distance_squared : int = line_2d.get_point_position(array_size - 1).distance_squared_to(mouse_pos)
			if distance_squared > 8:
				line_2d.add_point(mouse_pos)
		
	if array_size >= 3:
		line_2d.add_point(line_2d.get_point_position(0))
		create_colliders()
		line_2d.remove_point(line_2d.get_point_count() - 1)

func show_transform_ui():
	transform_ui.visible = true
	var center := (bounds[0] + bounds[1]) / 2
	var new_scale : Vector2 = (bounds[1] - bounds[0]) / transform_ui.size
	#makes scale and rotate outside of polygon, which looks better for now, but can be removed once there is actual ui art
	new_scale *= 4.5/3
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
	material.set_shader_parameter("bounds", bounds)

func create_colliders():
	material.set_shader_parameter("size", line_2d.get_point_count())
	material.set_shader_parameter("points", line_2d.points)	
	polygon2d_created.emit(line_2d.points)

func clamp_to_circle(pos : Vector2) -> Vector2:
	var texture_center := Vector2(texture_size, texture_size)/2
	pos = pos - texture_center
	pos = pos.limit_length(texture_center.x - 1)
	pos = pos + texture_center
	return pos

func _on_scale_region_mouse_entered():
	modifying = TRANSFORMING.SCALING

func _on_rotating_region_mouse_entered():
	modifying = TRANSFORMING.ROTATING

func _on_translating_region_mouse_entered():
	modifying = TRANSFORMING.TRANSLATING

func _on_transform_ui_mouse_exited():
	modifying = TRANSFORMING.NOTHING
