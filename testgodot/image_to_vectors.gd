extends Control

@onready var paint_root: Control = $PaintRoot
@onready var drawing_area: Panel = paint_root.drawing_area_bg
@onready var paint_control: Control = paint_root.paint_control
@onready var texture_rect: TextureRect = paint_root.texture

var img : Image

func _process(_delta):
	if Input.is_action_just_pressed("rightclick"):
		texture_rect.hide()
		await get_tree().process_frame
		img = paint_control.get_viewport().get_texture().get_image().get_region(Rect2(drawing_area.position, drawing_area.size))
		texture_rect.show()
		spread(get_global_mouse_position())
		
func spread(pos):
	print(img.get_size())
	var new_size = img.get_size() / 10
	img.resize(new_size.x,new_size.y, 0)
	print(img.get_size())
	pos -= drawing_area.global_position 
	var res : Vector2 = img.get_size()
	var rel = pos/(drawing_area.size as Vector2) * res
	img.set_pixel(rel.x, rel.y, Color(1,0,1,1))
	texture_rect.texture = ImageTexture.create_from_image(img)
