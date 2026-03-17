class_name StampDoubleTrigger 
extends CardModifierStamp

func get_str() -> String: return "Double Trigger"
func get_description() -> String: return "This card's effects triggers twice"
func get_frame() -> int: return 57

var triggers : int = 0
func on_trigger(data:CardData, mod:Callable) -> void:
	if not is_active(): return
	if triggers < 1 and data == self.data and self.data.skill:
		triggers += 1
		await mod.call()
		#await game.on_mod_triggered(self.data, on_trigger.bind(data, mod))
		
func on_after_score() -> void:
	triggers = 0
