extends Node2D

@export var PlayerScene : PackedScene
#@onready var card_player_1: Player = $CardPlayer1
#@onready var card_player_2: Player = $CardPlayer2
@onready var players: Array[CardPlayer] = [$Player1, $Player2]
@onready var timer: Timer = $Countdown/Timer

func _ready() -> void:
	game_loop()

func game_loop() -> void:
	for i:int in 3:
		bet_round()
		timer.start()
		await timer.timeout
	#bet 1
	#bet 2
	#bet 3
	#check
	reset()
	game_loop()

func bet_round() -> void:
	for player:CardPlayer in players:
		player.play_zone.max_cards += 1
		#player.card_spaces[space].activate()
		
func check() -> void:
	pass
	#for player:CardPlayer in players:
		#player.card_spaces[3].activate()
		#player.card_spaces[4].activate()

func reset() -> void:
	for player:CardPlayer in players:
		player.reset()
