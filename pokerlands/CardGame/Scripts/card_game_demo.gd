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
	for round:int in 3:
		bet_round()
		#timer.start()
		#await timer.timeout
		#await button.pressed
		var players_betted : Promise = Promise.new([players[0].card_betted, players[1].card_betted], Promise.MODE.ALL)
		var move_data : Dictionary = await Promise.new([button.pressed, players_betted], Promise.MODE.ANY).completed
		print(move_data)
		#"data": [true, [false, true]] #player 1 never played a card before next round triggered
		#"data": [false, [true, true]] #both players betted
		#"data": [true, false] #neither player betted but round continued
		var moves : Array = move_data[&'data']
		#if next round occured due to passing
		if moves[0]:
			#player 1 played card
			if moves[1] and moves[1][0]:
				return
			#player 2 played card
			elif moves[1] and moves[1][1]:
				return
			#if neither player played a card and at least round 1 has been played, skip to check round
			elif round>0:
				break
			else:
				return
				#both players get punished for dilly dallying
			
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
