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
		frame = 56
	
	
	var triggers : int = 0
	func on_trigger(data:CardData, mod:Callable) -> void:
		if triggers < 1 and data == self.data and self.data.skill:
			await mod.call()
			triggers += 1
			await mod_triggered.emit(self.data, on_trigger.bind(data, mod))
			
	#TODO make sure this works with all triggers triggers twice effect	
	func on_next_pass() -> void:
		triggers = 0
	
