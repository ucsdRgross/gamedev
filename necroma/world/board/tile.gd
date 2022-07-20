extends Area2D


var is_mouse_hovered : bool = false
var coord : Vector2 = Vector2(-1,-1)

func _input(event):
	if event.is_action_pressed("left_mouse_button") and is_mouse_hovered:
		print(coord)

func setup(coord):
	self.coord = coord

func _on_tile_mouse_entered():
	is_mouse_hovered = true

func _on_tile_mouse_exited():
	is_mouse_hovered = false
