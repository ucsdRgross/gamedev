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

static func show_deck(parent:Node, new_deck:Array[CardData]) -> DeckViewer:
	var viewer :DeckViewer= DECK_VIEWER.instantiate()
	viewer.deck = new_deck
	parent.add_child(viewer)
	viewer.update_viewer()
	return viewer

func update_viewer() -> void:
	for data in deck:
		var control_card := ControlCard.add_child_control_card(
			flow_container, data, CardVisual.DisplayContext.DECK_VIEWER)

func _on_flow_container_hidden() -> void:
	if flow_container:
		for child in flow_container.get_children():
			flow_container.remove_child(child)
			child.queue_free()

func _on_margin_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			queue_free()
