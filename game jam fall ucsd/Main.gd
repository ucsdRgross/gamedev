extends Node2D

onready var game = $Game
onready var menu = $StartMenu

func _on_StartMenu_start_game():
	game.create_instance()
	menu.queue_free()
