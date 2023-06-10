extends HFlowContainer

var selected_index : int = -1
@onready var placeholder = $CardPlaceholder

var drag_card

func _notification(what):
	match what:
		NOTIFICATION_DRAG_BEGIN:
			var card : Control = get_tree().get_root().gui_get_drag_data()
			drag_card = card
			move_child(card, -1)
			card.modulate = Color("ffffff00")
			move_child(placeholder, selected_index)
		NOTIFICATION_DRAG_END:
			if not get_tree().get_root().gui_is_drag_successful():
				drag_card.modulate = Color("ffffffff")
				move_child(drag_card, placeholder.get_index())
			move_child(placeholder, -1)
			
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
	data.modulate = Color("ffffffff")
#	data.reparent(self, false)
	move_child(data, placeholder.get_index())
#	move_child(placeholder, -1)
