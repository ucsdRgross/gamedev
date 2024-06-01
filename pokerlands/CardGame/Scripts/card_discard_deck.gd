extends Area2D

signal discard_card(card:Card)

func _process(delta: float) -> void:
	var areas : Array[Area2D] = get_overlapping_areas()
	for area : Node in areas:
		if area.owner is Card:
			var card : Card = area.owner
			if card.in_play:
				delete_card(card)
			
func delete_card(card:Card) -> void:
	discard_card.emit(card)
	card.held = false
	card.in_play = false
	card.tween_move(global_position)
	card.tween.tween_callback(card.queue_free)
