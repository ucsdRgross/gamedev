class_name StampDoubleTrigger 
extends CardModifier

func _init() -> void:
	name = "Double Trigger"
	description = "This card's effects triggers twice"
	frame = 57

@export_storage var triggers : int = 0
func on_trigger(data:CardData, mod:Callable) -> void:
	if not is_active(): return
	if triggers < 1 and data == self.data and self.data.skill:
		triggers += 1
		await mod.call()
		#await game.on_mod_triggered(self.data, on_trigger.bind(data, mod))
		
func after_score() -> void:
	triggers = 0
