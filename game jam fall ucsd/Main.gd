extends Node2D

func _on_StartMenu_start_game():
	var r = get_tree().change_scene("res://Main/Game/Game.tscn")
