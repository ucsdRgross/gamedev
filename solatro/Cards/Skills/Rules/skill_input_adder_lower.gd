class_name SkillInputAdderLower
extends CardModifierSkill

func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD_DESCRIPTION')
func get_frame() -> int: return 0

func on_active() -> void:
	Game.CURRENT.lower_zone_type.append(CardData.new().with_type(TypeInput.new()))
	Game.CURRENT.lower_zone.append(ArrayCardData.new())
	
func on_deactive() -> void:
	Game.CURRENT.lower_zone_type.pop_back()
	var datas : ArrayCardData = Game.CURRENT.lower_zone.pop_back()
	for data in datas:
		pass
		# await discard
