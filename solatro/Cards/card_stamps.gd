class_name CardStamp

class Revealing extends CardModifier:
	func _init() -> void:
		name = "Revealing"
		description = "Trigger effects even when covered"
		frame = 56

class DoubleTrigger extends CardModifier:
	func _init() -> void:
		name = "Double Trigger"
		description = "This card's effects triggers twice"
		frame = 57
	
	var triggers : int = 0
	func on_trigger(data:CardData, mod:Callable) -> void:
		if triggers < 1 and data == self.data and self.data.skill:
			triggers += 1
			await mod.call()
			await game.on_mod_triggered(self.data, on_trigger.bind(data, mod))
			
	func after_score() -> void:
		triggers = 0
	
