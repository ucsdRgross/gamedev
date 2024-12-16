class_name Menu
extends Control

signal play_pressed



func _on_play_pressed() -> void:
	play_pressed.emit()
