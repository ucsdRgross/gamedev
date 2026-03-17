class_name SkillInputAdderLower
extends CardModifierSkill

func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD_DESCRIPTION')
func get_frame() -> int: return 0

func on_active() -> void:
	pass
	
func on_deactive() -> void:
	pass
