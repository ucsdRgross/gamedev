extends Control

signal mouse_over_card(index)
signal mouse_leave_card

func _get_drag_data(_pos):
	set_drag_preview(self.duplicate())
	return self


func _on_mouse_entered():
	mouse_over_card.emit(get_index()) 

func _on_mouse_exited():
	mouse_leave_card.emit()
