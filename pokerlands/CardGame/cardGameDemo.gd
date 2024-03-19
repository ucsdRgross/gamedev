extends Control

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
