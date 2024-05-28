extends Area2D
class_name CardSpace

var held_card : Card = null
var active := false

@onready var timer: Timer = $Timer

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not held_card or held_card.in_play:
		var areas : Array[Area2D] = get_overlapping_areas()
		if areas.size() == 1:
			if areas[0].owner is Card:
				var card : Card = areas[0].owner
				if not card.held:
					if held_card != card and card.in_play:
						held_card = card
						timer.stop()
					if timer.is_stopped():
						if active:
							timer.start()
				else:
					timer.stop()
		else:
			held_card = null
			timer.stop()

func confirm_card() -> void:
	timer.stop()
	if held_card and held_card.in_play:
		held_card.in_play = false
		var tween : Tween = create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_parallel()
		tween.tween_property(held_card, "global_position", global_position, 0.3)
		tween.tween_property(held_card, "rotation", roundf(held_card.rotation/PI)*PI, 0.3)
	else:
		held_card = null

func activate() -> void:
	active = true
	confirm_card()

func _on_timer_timeout() -> void:
	confirm_card()
