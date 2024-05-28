extends Area2D

const CARD := preload("res://CardGame/Scenes/card.tscn")

signal draw_card(card_info : PackedScene, deck_position : Vector2, event : InputEvent)

func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			draw_card.emit(CARD, global_position, event)
