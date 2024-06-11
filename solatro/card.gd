extends Node2D
class_name Card

signal clicked

@export var child_offset : Vector2
@export var is_zone := false
@export var clickable := true
@export var rank : int = 0
@export var stack_limit : int = -1
@export var transform3d : Transform3D
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

var top_card : Card
var stack_size : int
var target_position : Vector2

@onready var front: Sprite2D = $Front
@onready var area: Control = $Front/Control

func _ready() -> void:
	if not is_zone:
		set_card_front() 
	else:
		child_offset = Vector2(0,0)

func move_to(pos : Vector2) -> void:
	global_position = pos

func set_card_front() -> void:
	front.frame = 13 * (suit - 1) + (rank - 1)
		
func _on_control_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			#print("clicked")
			if clickable:
				clicked.emit(self)

func add_card(card : Card) -> void:
	var parent := card.get_parent()
	if parent is Card:
		(parent as Card).top_card = null
	card.reparent(self)
	top_card = card
	card.reposition()
	if stack_limit > -1:
		while card:
			card.stack_limit = stack_limit - 1
			card = card.top_card
	else:
		while card:
			card.stack_limit = stack_limit
			card = card.top_card

func pickup() -> void:
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = num_cards	
	scale = Vector2(1.15,1.15)
	stack_size = get_stack_size()
	
func drop() -> void:
	area.mouse_filter = Control.MOUSE_FILTER_STOP
	reposition()
	z_index = 0
	scale = Vector2(1,1)

func reposition() -> void:
	var parent : Node = get_parent()
	if parent is Card:
		move_to((parent as Card).global_position + (parent as Card).child_offset)

func get_last_card() -> Card:
	var last_card := self
	while last_card.top_card:
		last_card = last_card.top_card
	return last_card

func get_stack_size() -> int:
	var stack_size : int = 1
	var last_card := self
	while last_card.top_card:
		last_card = last_card.top_card
		stack_size += 1
	return stack_size

func _enter_tree() -> void:
	num_cards += 1
	
func _exit_tree() -> void:
	num_cards -= 1
