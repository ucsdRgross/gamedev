extends Control

@onready var card_player = %CardPlayer
@onready var deckbuilder = %Deckbuilder

var deckbuilding : bool = false :
	set(value):
		if value:
			if get_viewport().gui_is_dragging():
				set_drag_preview(get_viewport().gui_get_drag_data().create_preview())
			card_player.hide()
			deckbuilder.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			if get_viewport().gui_is_dragging():
				set_drag_preview(Control.new())
			card_player.show()
			deckbuilder.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
		deckbuilding = value

# Called when the node enters the scene tree for the first time.
func _ready():
	deckbuilding = false

func _input(event):
	if event.is_action_pressed("ui_text_indent"):
		deckbuilding = !deckbuilding
		
