extends Node2D

@export var PlayerScene : PackedScene
#@onready var card_player_1: Player = $CardPlayer1
#@onready var card_player_2: Player = $CardPlayer2
@onready var mouse_pin: PinJoint2D = $MousePin

var held_card : Card = null

# Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#var index := 1
	#for i:String in GameManager.Players:
		#if GameManager.Players[i].index == 1:
				#card_player_1.set_authority(type_convert(GameManager.Players[i].id, TYPE_INT))
		#if GameManager.Players[i].index == 2:
			#card_player_2.set_authority(GameManager.Players[i].id)
			#if multiplayer.get_unique_id() == GameManager.Players[i].id:
				#$Label.text = str(GameManager.Players[i].index)
				#$camera.rotation_degrees = 180
		#index += 1

func _physics_process(delta: float) -> void:
	mouse_pin.global_position = get_global_mouse_position()
	
func _on_cards_child_entered_tree(card : Card) -> void:
	card.clicked.connect(_on_card_clicked)
		
func _on_card_clicked(card : Card) -> void:
	if !held_card:
		card.pickup()
		held_card = card
		mouse_pin.node_b = mouse_pin.get_path_to(held_card)
		%Cards.move_child(card,-1)

func _input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == 1 and not mouse_event.pressed:
			if held_card:
				held_card.drop(Input.get_last_mouse_velocity())
				held_card = null
				mouse_pin.node_b = NodePath()