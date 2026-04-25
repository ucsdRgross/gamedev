class_name SkillEchoingTrigger
extends CardModifierSkill

func get_str() -> String: return "Echoing Trigger"
func get_description() -> String: return "ALL triggers repeat once"
func get_frame() -> int: return 1

var triggered : Array[CardData]
func on_trigger(data:CardData, mod:Callable) -> void:
	if not is_active(): return
	if data not in triggered and data.skill:
		triggered.append(data)
		#card_raise()
		await mod.call()
		#card_lower()	
		#await game.on_mod_triggered(self.data, on_trigger.bind(data, mod))
		
func on_after_score() -> void:
	triggered.clear()
