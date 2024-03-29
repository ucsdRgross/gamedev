extends Node

@export var PlayerScene : PackedScene
@onready var card_player_1: Player = $CardPlayer1
@onready var card_player_2: Player = $CardPlayer2

# Called when the node enters the scene tree for the first time.
func _ready():
	var index = 1
	for i in GameManager.Players:
		if GameManager.Players[i].index == 1:
				card_player_1.set_authority(GameManager.Players[i].id)
		if GameManager.Players[i].index == 2:
			card_player_2.set_authority(GameManager.Players[i].id)
			if multiplayer.get_unique_id() == GameManager.Players[i].id:
				$Label.text = str(GameManager.Players[i].index)
				$camera.rotation_degrees = 180
		index += 1
		
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == 1 and event.pressed:
			get_tree().call_group("cards", "_on_mouse_button_1_pressed")
		elif event.button_index == 1 and not event.pressed:
			get_tree().call_group("cards", "_on_mouse_button_1_not_pressed")
