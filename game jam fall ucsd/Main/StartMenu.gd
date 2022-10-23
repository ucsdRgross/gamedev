extends Control

signal start_game

func _on_Button_button_up():
	emit_signal("start_game")
