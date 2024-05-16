extends Node2D

@export var PlayerScene : PackedScene
#@onready var card_player_1: Player = $CardPlayer1
#@onready var card_player_2: Player = $CardPlayer2
@onready var players: Array[CardPlayer] = [$Player1, $Player2]
@onready var timer: Timer = $Countdown/Timer
@onready var button: Button = $Button

func _ready() -> void:
	while true:
		await game_round()
		reset()

func game_round() -> void:
	for i:int in 3:
		bet_round()
		#timer.start()
		#await timer.timeout
		await button.pressed
		if folded() > 0:
			#damage 
			return
	check_round()
	#timer.start()
	#await timer.timeout
	await button.pressed
	#bet 1
	#bet 2
	#bet 3
	#check
	

func bet_round() -> void:
	for player:CardPlayer in players:
		player.bet_round()
		
func folded() -> int:
	return 0
		
func check_round() -> void:
	for player:CardPlayer in players:
		player.check_round()

func reset() -> void:
	for player:CardPlayer in players:
		player.reset()
