@abstract
class_name ZoneCardAdder
extends CardModifierSkill

#func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD')
#func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD_DESCRIPTION')
#func get_frame() -> int: return 0

var card_data : CardData

@abstract
func card_data_to_add() -> CardData
@abstract
func get_zone() -> Array[ArrayCardData]
@abstract
func get_zone_type() -> Array[CardData]

func on_active() -> void:
	if not card_data:
		card_data = card_data_to_add()
	card_data.stage = CardData.Stage.ZONE
	get_zone_type().append(card_data)
	get_zone().append(ArrayCardData.new())
	
func on_deactive() -> void:
	var index := get_zone_type().find(card_data)
	get_zone_type().remove_at(index)
	var datas : Array[CardData] = get_zone().pop_at(index).datas
	for d : CardData in datas:
		await Game.CURRENT.discard_data(d)
	card_data = null
		
