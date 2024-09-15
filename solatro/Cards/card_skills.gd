class_name CardSkill

class ExtraPoint extends CardModifier:
	func _init() -> void:
		name = "Extra Point"
		description = "Gain 1 Extra Point Per Score"
		frame = 52
	
	func on_score(target:Card) -> void:
		if target.data == data:
			await card_shake()
