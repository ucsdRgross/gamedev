extends HFlowContainer
class_name CardContainer

#tracks where mouse is in container
var selected_index : int = -1
var placeholder := Control.new()

#tracks which card is being dragged
var drag_card : Control
var drag_card_parent := false

const card := preload("res://card.tscn")

func _ready():
	self.child_entered_tree.connect(_on_child_entered_tree)
	self.child_exiting_tree.connect(_on_child_exiting_tree)
	self.mouse_exited.connect(_on_mouse_exited)
	
	#clear editor leftovers
	for c in get_children():
		c.free()
	
	#basically a blank card to create blank space
	placeholder.custom_minimum_size = Vector2(64, 64)
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(placeholder)
		
	for i in range(10):
		var new_card := card.instantiate()
		var rect := new_card.get_child(0)
		rect.texture.region = Rect2((randi() % 14) * 16, 0, 16, 16)
		add_child(new_card)
	
	move_child(placeholder, -1)

func _notification(what : int):
	match what:
		NOTIFICATION_DRAG_BEGIN:
			var card : Control = get_viewport().gui_get_drag_data()
			drag_card = card
			if self == card.get_parent():
				drag_card_parent = true
				remove_child(card)
				move_child(placeholder, selected_index)
			else:
				drag_card_parent = false
		NOTIFICATION_DRAG_END:
			if not get_viewport().gui_is_drag_successful():
				if drag_card_parent:
					add_child(drag_card)
					#drag_card.reparent(self, false)
					move_child(drag_card, placeholder.get_index())
			move_child(placeholder, -1)
			
func _on_child_entered_tree(node : Node):
	if node.has_signal("mouse_over_card"):
		node.mouse_over_card.connect(_on_mouse_over_card)
	if node.has_signal("mouse_leave_card"):
		node.mouse_leave_card.connect(_on_mouse_leave_card)

func _on_child_exiting_tree(node : Node):
	if node.is_connected("mouse_over_card", _on_mouse_over_card):
		node.mouse_over_card.disconnect(_on_mouse_over_card)
	if node.is_connected("mouse_leave_card", _on_mouse_leave_card):
		node.mouse_leave_card.disconnect(_on_mouse_leave_card)

func _on_mouse_over_card(index):
	selected_index = index
	if get_viewport().gui_is_dragging():
		move_child(placeholder, selected_index)

func _on_mouse_leave_card():
	selected_index = -1

func _can_drop_data(_pos, data):
	return true

func _drop_data(_pos, data):
	if data.get_parent():
		data.reparent(self)
	else:
		add_child(data)
	move_child(data, placeholder.get_index())

func _on_mouse_exited():
	var mp := get_local_mouse_position()
	if (mp.x < 0 or mp.x > size.x) or (mp.y < 0 or mp.y > size.y):
		move_child(placeholder, -1)
