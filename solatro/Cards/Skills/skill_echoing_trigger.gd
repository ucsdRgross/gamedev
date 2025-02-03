class_name SkillEchoingTrigger
extends CardModifier

func _init() -> void:
	name = "Echoing Trigger"
	description = "ALL triggers repeat once"
	frame = 53

var triggered : Array[CardData]
func on_trigger(data:CardData, mod:Callable) -> void:
	if not is_active(): return
	if data not in triggered and data.skill:
		triggered.append(data)
		card_raise()
		await mod.call()
		card_lower()	
		#await game.on_mod_triggered(self.data, on_trigger.bind(data, mod))
		
func after_score() -> void:
	triggered.clear()
