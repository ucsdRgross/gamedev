extends TextureRect

var bitmap_size = Vector2(512/2,512/2)
var bitmap : BitMap = BitMap.new()
var last_mouse_pos : Vector2i
var mouse_pos : Vector2i
var is_drawing := false

func _ready():
	bitmap.create(bitmap_size)
	self.texture = ImageTexture.create_from_image(bitmap.convert_to_image())

func _gui_input(event):
	for mouse_event in [InputEventMouseButton, InputEventMouseMotion, InputEventScreenDrag, InputEventScreenTouch]:
		if is_instance_of(event, mouse_event):
			mouse_pos = event.position
			break
	if event.is_action_pressed("Left Click"):
		is_drawing = true
	if event.is_action_released("Left Click"):
		is_drawing = false
		
func _process(delta):
	if is_drawing:
		var pos : Vector2i = mouse_pos
		pos.x = clamp(pos.x, 0, bitmap_size.x - 1)
		pos.y = clamp(pos.y, 0, bitmap_size.y - 1)
		bitmap.set_bit(pos.x, pos.y, true)
		var image = bitmap.convert_to_image()
		self.texture = ImageTexture.create_from_image(image)

func resize(new_size : Vector2i):
	bitmap_size = new_size
	bitmap.resize(new_size)
