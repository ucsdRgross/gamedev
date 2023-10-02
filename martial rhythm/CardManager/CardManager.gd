extends Control

@onready var card_player = %CardPlayer
@onready var deckbuilder = %Deckbuilder
@onready var deck_container = %DeckContainer

var deckbuilding : bool = false :
	set(value):
		if value:
			#gui
			if get_viewport().gui_is_dragging():
				set_drag_preview(get_viewport().gui_get_drag_data().create_preview())
			card_player.hide()
			deckbuilder.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			#logic
			card_player.clear_hand()
		else:
			#gui
			if get_viewport().gui_is_dragging():
				set_drag_preview(Control.new())
			card_player.show()
			deckbuilder.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			#logic
			fill_hand()
				
		deckbuilding = value

# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()
	deckbuilding = false

func _input(event):
	if event.is_action_pressed("ui_text_indent"):
		deckbuilding = !deckbuilding
		
func fill_hand():
	var cards : Array[Node]
	for card in deck_container.get_children():
		if card != deck_container.placeholder:
			cards.append(card.duplicate())
	cards.shuffle()
	card_player.fill_hand(cards)

func _on_card_player_hand_empty():
	fill_hand()
