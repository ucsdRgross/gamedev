class_name MapNamePopup
extends PanelContainer

## The small name-only popup above a map node, whose name the sidebar alone would not put at the dot.

@onready var _name_label : Label = %Name

# Names `node_name` centred directly above `node_rect`, both in the map viewport's own
# coordinates. Placed once per hovered node and never followed: a name that drifted with the
# pointer would stop reading as a label ON the dot.
func show_above(node_name: String, node_rect: Rect2) -> void:
	_name_label.text = node_name
	visible = true
	reset_size()
	position = Vector2(node_rect.get_center().x - size.x * 0.5, node_rect.position.y - size.y)
