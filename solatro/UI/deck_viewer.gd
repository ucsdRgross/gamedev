class_name DeckViewer
extends CanvasLayer

@onready var flow_container: FlowContainer = %FlowContainer

const CARD_VISUAL = preload("uid://bynh2btoahe5i")

var deck : Array[CardData]

func with_deck(new_deck:Array[CardData]) -> DeckViewer:
	deck = new_deck
	update_viewer()
	return self

func update_viewer() -> void:
	for data in deck:
		var visual : CardVisual = CARD_VISUAL.instantiate()

func create_card_visual(connected_data:CardData) -> CardVisual:
	var card : CardVisual = (CARD_VISUAL.instantiate() as CardVisual).with_data(connected_data)
	#wait for play area containers to update control positions at next frame
	call_deferred("add_child", card)
	return card
