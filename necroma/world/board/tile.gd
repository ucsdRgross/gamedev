extends Area2D


var is_mouse_hovered : bool = false
var coord : Vector2 = Vector2(-1,-1)

signal tile_clicked(coord)

func _input(event):
	if event.is_action_pressed("left_mouse_button") and is_mouse_hovered:
		emit_signal("tile_clicked", coord)
		#print(coord)

func setup(coord):
	self.coord = coord
	self.connect('tile_clicked', get_parent(), 'on_tile_clicked')

func _on_tile_mouse_entered():
	is_mouse_hovered = true

func _on_tile_mouse_exited():
	is_mouse_hovered = false
