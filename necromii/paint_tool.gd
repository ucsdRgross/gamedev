extends TextureRect

var bitmap_size : int = 512
var size_v := Vector2(bitmap_size,bitmap_size)
var bitmap : BitMap = BitMap.new()
var last_mouse_pos : Vector2i
var mouse_pos : Vector2i
var start_pos : Vector2i
var is_drawing := false
#[top left x, top left y, bot right x, bot right y]
var bounds : PackedVector2Array = [Vector2(0,0), Vector2(0,0)]
var polygon : PackedVector2Array

enum TRANSFORMING {
	NOTHING,
	TRANSLATING,
	ROTATING,
	SCALING
}
var modifying := TRANSFORMING.NOTHING

@onready var line_2d = $Line2D

signal polygon2d_created(polygon : PackedVector2Array)

func _ready():
	bitmap.create(size_v)
	self.texture = ImageTexture.create_from_image(bitmap.convert_to_image())

func _gui_input(event):
	for mouse_event in [InputEventMouseButton, InputEventMouseMotion, InputEventScreenDrag, InputEventScreenTouch]:
		if is_instance_of(event, mouse_event):
			last_mouse_pos = mouse_pos
			mouse_pos = clamp_to_circle(event.position)
			break
	if event.is_action_pressed("Left Click"):
		if Global.is_modifying:# and Geometry2D.is_point_in_polygon(mouse_pos, line_2d.points):
			#modifying = TRANSFORMING.TRANSLATING
			#modifying = TRANSFORMING.SCALING
			modifying = TRANSFORMING.ROTATING
		else:
			line_2d.clear_points()
			#bitmap.set_bit_rect(Rect2(Vector2(0, 0), bitmap.get_size()), false)
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
		elif Global.is_modifying:
			modifying = TRANSFORMING.NOTHING
		
	if event.is_action_released("Right Click"):
		Global.is_modifying = false
		modifying = TRANSFORMING.NOTHING
		start_pos = clamp_to_circle(event.position)
		bounds = [Vector2(start_pos.x, start_pos.y), Vector2(start_pos.x, start_pos.y)]
		#bitmap.set_bit_rect(Rect2(Vector2(0, 0), bitmap.get_size()), false)
		#var image = bitmap.convert_to_image()
		#self.texture.update(image)
		#for child in get_children():
		#	remove_child(child)
		line_2d.clear_points()
		material.set_shader_parameter("size", line_2d.get_point_count())
		material.set_shader_parameter("points", line_2d.points)
		polygon2d_created.emit(line_2d.points)
		
	if Global.is_drawing:
		draw()	
		
	elif Global.is_modifying:
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
			var vector := corner - Vector2(origin)
			var new_point := vector * scale_factor + Vector2(origin)
			var clamped := clamp_to_circle(new_point)
			if clamped != new_point:
				scale_factor = (clamped - origin) / (corner - origin)
				if is_inf(scale_factor.x) or is_nan(scale_factor.x):
					scale_factor.x = 0
				if is_inf(scale_factor.y) or is_nan(scale_factor.y):
					scale_factor.y = 0
		
		var new_bound : PackedVector2Array = [origin, origin]
		for i in range(polygon.size()):
			var og_point := polygon[i]
			var vector := og_point - Vector2(origin)
			polygon[i] = vector * scale_factor + Vector2(origin)
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
		#print(bounds)
		
		bounds = new_bound
		material.set_shader_parameter("bounds", bounds)
		line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
	
	elif modifying == TRANSFORMING.ROTATING:
		var origin := Vector2(bounds[0].x + bounds[1].x, bounds[0].y + bounds[1].y) / 2
		var rotate := (Vector2(last_mouse_pos) - origin).angle_to((Vector2(mouse_pos) - origin))
		for corner in polygon:
			var vector := corner - Vector2(origin)
			var new_point := vector.rotated(rotate) + Vector2(origin)
			var clamped := clamp_to_circle(new_point)
			if clamped != new_point:
				rotate = 0 #(corner - origin).angle_to(clamped - origin)
		var new_bound : PackedVector2Array = [origin, origin]
		for i in range(polygon.size()):
			var og_point := polygon[i]
			var vector := og_point - Vector2(origin)
			polygon[i] = vector.rotated(rotate) + Vector2(origin)
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
		line_2d.points = [bounds[0], Vector2(bounds[0].x, bounds[1].y), bounds[1], Vector2(bounds[1].x, bounds[0].y), bounds[0]]
	
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

#		#plot_line(mouse_pos.x, mouse_pos.y, last_mouse_pos.x, last_mouse_pos.y)
#		#lasso finisher straight line
#		#var drawn : PackedVector2Array = plot_line(mouse_pos.x, mouse_pos.y, start_pos.x, start_pos.y, true, true)
#		#create_colliders()
#
#		var image = bitmap.convert_to_image()
#		self.texture.update(image)
#
#		for point in drawn:
#			bitmap.set_bit(point.x, point.y, false)

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
#	for child in get_children():
#		remove_child(child)
#	var polygons := bitmap.opaque_to_polygons(Rect2(Vector2(0, 0), bitmap.get_size()), 2.0)
#	#var polygons : Array[PackedVector2Array] = Geometry2D.decompose_polygon_in_convex(line_2d.points)
#	#var p : Array[PackedVector2Array] = [line_2d.points]
#	#polygons2d_created.emit(p)
#	var count := 0
#	for polygon in polygons:
#		count += polygon.size()
##		var collider := CollisionPolygon2D.new()
##		collider.polygon = polygon
##		add_child(collider)	
#	print("opqaue" + str(count))
#	print("size" + str(line_2d.get_point_count()))
	#polygon_2d.set_polygons(polygons)
	material.set_shader_parameter("size", line_2d.get_point_count())
	#since gpu can only accept so many points, take the newest 4000 points
	material.set_shader_parameter("points", line_2d.points)	
	polygon2d_created.emit(line_2d.points)
		
	#var collider := CollisionPolygon2D.new()
	#collider.polygon = [Vector2(bounds[0], bounds[1]), Vector2(bounds[0], bounds[3]), Vector2(bounds[2], bounds[3]), Vector2(bounds[2], bounds[1])]
	#add_child(collider)			

func clamp_to_circle(pos : Vector2) -> Vector2:
	pos = pos - size_v/2
	pos = pos.limit_length(bitmap_size/2 - 1)
	pos = pos + size_v/2
	return pos
	


#https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
#func plot_line(x0 : int, y0 : int, x1 : int, y1 : int, bit : bool = true, record : bool = false):
#	var dx : int = abs(x1 - x0)
#	var sx : int = 1 if x0 < x1 else -1
#	var dy : int = -abs(y1 - y0)
#	var sy : int = 1 if y0 < y1 else -1
#	var error : int = dx + dy
#	var drawn : PackedVector2Array 
#
#	while true:
#		if record:
#			if !bitmap.get_bit(x0, y0):
#				drawn.append(Vector2i(x0, y0))
#		bitmap.set_bit(x0, y0, bit)
#		if x0 == x1 && y0 == y1:
#			break
#		var e2 : int = 2 * error
#		if e2 >= dy:
#			if x0 == x1:
#				break
#			error = error + dy
#			x0 = x0 + sx
#		if e2 <= dx:
#			if y0 == y1:
#				break
#			error = error + dx
#			y0 = y0 + sy
#
#	if record:
#		return drawn
