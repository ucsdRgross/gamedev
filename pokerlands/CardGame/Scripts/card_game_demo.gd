extends Node2D

@export var PlayerScene : PackedScene
@onready var players: Array[CardPlayer] = [$Player1, $Player2]
@onready var timer: Timer = $Countdown/Timer
@onready var button: Button = $Button

func _ready() -> void:
	while players[0].health > 0 and players[1].health > 0 :
		await game_round()
		reset()
	print('game over')

func game_round() -> void:
	for i:int in 3:
		bet_round()
		#timer.start()
		#await timer.timeout
		#await button.pressed
		var players_betted : Promise = Promise.new([players[0].card_betted, players[1].card_betted], Promise.MODE.ALL)
		var move_data : Dictionary = await Promise.new([button.pressed, players_betted], Promise.MODE.ANY).completed
		print(move_data)
		
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

func check_round() -> void:
	for player:CardPlayer in players:
		player.check_round()

func reset() -> void:
	for player:CardPlayer in players:
		player.reset()
