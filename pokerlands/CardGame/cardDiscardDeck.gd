extends Area2D

signal discard_card(card:Card)

func _process(delta: float) -> void:
	var areas : Array[Area2D] = get_overlapping_areas()
	for area : Node in areas:
		if area.owner is Card:
			var card : Card = area.owner
			if card.in_play:
				discard_card.emit(card)
				delete_card(card)
			
func delete_card(card:Card) -> void:
	var tween : Tween = create_tween()
	card.held = false
	card.in_play = false
	tween.tween_property(card, "global_position", global_position, 0.2)
	tween.parallel().tween_property(card, "rotation", roundf(card.rotation/PI)*PI, 0.2)
	tween.tween_callback(card.queue_free)
