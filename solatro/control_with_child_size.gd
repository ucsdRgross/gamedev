@tool
extends Control

var card : Card

func _ready() -> void:
	child_order_changed.connect(_on_child_order_changed)
	_on_child_order_changed()
	update_minimum_size()

func _get_minimum_size() -> Vector2:
	if card:
		card.position = -card.area.position * card.scale
		return card.area.size * card.scale
	return Vector2.ZERO

func _on_child_order_changed() -> void:
	if get_child_count() > 0:
		var child : Node = get_child(0)
		if child is Card:
			card = child
		else:
			card = null
	else:
		card = null
	update_minimum_size()
