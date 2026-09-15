class_name MapNamePopup
extends PanelContainer

## The small name-only popup above a map node, whose name the sidebar alone would not put at the dot.

@onready var _name_label : Label = %Name

## The node this label is anchored to, or null while nothing is named.
var _node : WorldGraphNode = null

# Nothing is named until a hover says so, and the follow below would have no dot to read.
func _ready() -> void:
	set_process(false)

# Names `node` centred directly above it. The dot moves under the camera every frame while the
# token travels, and a pan, a zoom or a resize move it too, so the label is re-placed against the
# node's CURRENT position instead of being left where the hover found it.
func show_above(node_name: String, node: WorldGraphNode) -> void:
	_name_label.text = node_name
	_node = node
	visible = true
	set_process(true)
	_place_above_node()

func _process(_delta: float) -> void:
	_place_above_node()

func _place_above_node() -> void:
	reset_size()
	var dot := WorldMapController.node_screen_rect(_node)
	position = Vector2(dot.get_center().x - size.x * 0.5, dot.position.y - size.y)

# There is no dot to name any more -- the run started over, the node was entered, or the map screen
# was left -- and a label left behind over one of those names nothing.
func hide_name() -> void:
	visible = false
	_node = null
	set_process(false)
