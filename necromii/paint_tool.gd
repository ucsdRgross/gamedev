extends TextureRect

var bitmap_size : int = 512/2
var size_v := Vector2(bitmap_size,bitmap_size)
var bitmap : BitMap = BitMap.new()
var last_mouse_pos : Vector2i
var mouse_pos : Vector2i
var is_drawing := false

func _ready():
	bitmap.create(size_v)
	self.texture = ImageTexture.create_from_image(bitmap.convert_to_image())

func _gui_input(event):
	for mouse_event in [InputEventMouseButton, InputEventMouseMotion, InputEventScreenDrag, InputEventScreenTouch]:
		if is_instance_of(event, mouse_event):
			last_mouse_pos = mouse_pos
			mouse_pos = event.position
			draw()
			break
	if event.is_action_pressed("Left Click"):
		is_drawing = true
	if event.is_action_released("Left Click"):
		is_drawing = false
	if event.is_action_pressed("Right Click"):
		var polygons = bitmap.opaque_to_polygons(Rect2(Vector2(0, 0), bitmap.get_size()))
		for polygon in polygons:
			var collider = CollisionPolygon2D.new()
			collider.polygon = polygon
			add_child(collider)
		
func clamp_to_circle(pos : Vector2) -> Vector2:
	pos = pos - size_v/2
	pos = pos.limit_length(bitmap_size/2 - 1)
	pos = pos + size_v/2
	return pos
		
func draw():
	if is_drawing:
		mouse_pos = clamp_to_circle(mouse_pos)
		last_mouse_pos = clamp_to_circle(last_mouse_pos)
		
		plot_line(mouse_pos.x, mouse_pos.y, last_mouse_pos.x, last_mouse_pos.y)
		
		var image = bitmap.convert_to_image()
		self.texture.update(image)
		
#https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
func plot_line(x0 : int, y0 : int, x1 : int, y1 : int):
	var dx : int = abs(x1 - x0)
	var sx : int = 1 if x0 < x1 else -1
	var dy : int = -abs(y1 - y0)
	var sy : int = 1 if y0 < y1 else -1
	var error : int = dx + dy
	
	while true:
		bitmap.set_bit(x0, y0, true)
		if x0 == x1 && y0 == y1:
			break
		var e2 : int = 2 * error
		if e2 >= dy:
			if x0 == x1:
				break
			error = error + dy
			x0 = x0 + sx
		if e2 <= dx:
			if y0 == y1:
				break
			error = error + dx
			y0 = y0 + sy
