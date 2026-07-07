class_name DeckViewer
extends CanvasLayer

const DECK_VIEWER = preload("uid://dnvpthmsneqjl")

@onready var flow_container: FlowContainer = %FlowContainer

enum SORTING_TYPE {RANK,SUIT,EFFECT}
enum SORTING_ORDER {ASCENDING,DESCENDING}

var deck : Array[CardData]
var randomized : bool = false
var sorting_type : SORTING_TYPE = SORTING_TYPE.RANK
var sorting_order : SORTING_ORDER = SORTING_ORDER.ASCENDING

# Only one viewer at a time: opening a new one (Deck button, deck picker Inspect, Enter
# re-triggering a still-focused button, ...) replaces the previous instead of stacking.
static var _open : DeckViewer = null
# Focus to restore on close, so keyboard/controller users land back on the button that
# opened the viewer instead of nowhere.
var _return_focus : Control = null

static func show_deck(parent:Node, new_deck:Array[CardData]) -> DeckViewer:
	if is_instance_valid(_open):
		_open.queue_free()
	var viewer :DeckViewer= DECK_VIEWER.instantiate()
	viewer.deck = new_deck
	viewer._return_focus = parent.get_viewport().gui_get_focus_owner() if parent.is_inside_tree() else null
	parent.add_child(viewer)
	viewer.update_viewer()
	_open = viewer
	return viewer

func _close() -> void:
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()
	queue_free()

func update_viewer() -> void:
	var first : ControlCard = null
	for data in deck:
		var control_card := ControlCard.add_child_control_card(
			flow_container, data, CardVisual.DisplayContext.DECK_VIEWER)
		if not first: first = control_card
	# Steal focus from whatever button opened the viewer, so ui_accept can't re-open it
	# and arrow keys walk the cards (ControlCards are focusable).
	if first: first.grab_focus()

## Keyboard/controller close: Escape/back AND Enter/accept both close (the viewer is
## read-only, so accept has no other meaning). Mouse click on the margin closes below.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_close()

func _on_flow_container_hidden() -> void:
	if flow_container:
		for child in flow_container.get_children():
			flow_container.remove_child(child)
			child.queue_free()

func _on_margin_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_close()
