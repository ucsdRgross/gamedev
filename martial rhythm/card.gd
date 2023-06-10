extends Control

signal mouse_over_card(index)
signal mouse_leave_card

func _get_drag_data(_pos):
	var preview := self.duplicate()
	preview.modulate = Color("ffffffff")
	preview.get_child(0).position += Vector2(-32, -32)
	set_drag_preview(preview)
	return self


func _on_mouse_entered():
	mouse_over_card.emit(get_index()) 

func _on_mouse_exited():
	mouse_leave_card.emit()
