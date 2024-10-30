class_name CardType
extends Resource

class Heavy extends CardModifier:
	func _init() -> void:
		name = "Heavy Card"
		description = "Sinks to bottom of deck after shuffling"
		frame = 4
