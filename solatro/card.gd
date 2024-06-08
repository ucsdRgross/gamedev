extends Node2D
class_name Card

signal clicked

@export var child_offset : Vector2
@export var is_zone := false
@export var clickable := true
@export var rank : int = 0
#: 
	#set(value):
		#rank = value
		#set_card_front() 
@export_enum("Clubs", "Spades", "Diamonds", "Hearts") var suit: int = 0
#: 
	#set(value):
		#rank = value
		#set_card_front() 

static var num_cards : int = 0



@onready var front: Sprite2D = $Front
@onready var area: Control = $Front/Control

func _ready() -> void:
	if not is_zone:
		set_card_front() 
	else:
		child_offset = Vector2(0,0)

func set_card_front() -> void:
	front.frame = 13 * suit + rank
		
func _on_control_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			#print("clicked")
			if clickable:
				clicked.emit(self)

func add_card(card : Card) -> void:
	card.reparent(self)
	card.reposition()

func pickup() -> void:
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = num_cards	
	
func drop() -> void:
	area.mouse_filter = Control.MOUSE_FILTER_STOP
	reposition()
	z_index = 0

func reposition() -> void:
	var parent : Node = get_parent()
	if parent is Card:
		global_position = (parent as Card).global_position + (parent as Card).child_offset

func _enter_tree() -> void:
	num_cards += 1
	
func _exit_tree() -> void:
	num_cards -= 1
