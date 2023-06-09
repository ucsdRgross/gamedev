extends HFlowContainer

var selected_index : int = -1
@onready var placeholder = $CardPlaceholder

func _on_child_entered_tree(node):
	if node.has_signal("mouse_over_card"):
		node.mouse_over_card.connect(_on_mouse_over_card)
	if node.has_signal("mouse_leave_card"):
		node.mouse_leave_card.connect(_on_mouse_leave_card)

func _on_mouse_over_card(index):
	selected_index = index
	if get_tree().get_root().gui_is_dragging():
		move_child(placeholder, selected_index)

func _on_mouse_leave_card():
	selected_index = -1

func _can_drop_data(_pos, data):
	return true

func _drop_data(_pos, data):
	data.reparent(self, false)
	move_child(data, placeholder.get_index())
	move_child(placeholder, -1)
	
