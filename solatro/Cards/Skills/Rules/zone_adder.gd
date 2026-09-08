@abstract
class_name ZoneAdder
extends CardModifierSkill

#func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD')
#func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD_DESCRIPTION')
#func get_frame() -> int: return 0

@export_storage var card_data : CardData

## Engine rules machinery (§15a): zone adders never count as a combo class.
func combo_key(_hook: StringName = &"") -> String: return ""

@abstract
func card_data_to_add() -> CardData
@abstract
func get_zone() -> Array[ArrayCardData]
@abstract
func get_zone_type() -> Array[CardData]

func on_spotlight() -> void:
	if not api or not api.is_live(): return
	if not card_data:
		card_data = card_data_to_add()
	api.add_column(get_zone(), get_zone_type(), card_data)

func on_unspotlight() -> void:
	if not api or not api.is_live(): return
	var index := get_zone_type().find(card_data)
	if index == -1:
		card_data = null
		return
	for d : CardData in api.remove_column(get_zone(), get_zone_type(), index):
		await api.discard_data(d)
	card_data = null
		
