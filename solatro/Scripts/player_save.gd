class_name PlayerSave
extends Resource

@export var card_datas : Array[CardData]

func write_card_data(data: CardData) -> void:
	card_datas.append(data)
	
func read_card_data() -> Array[CardData]:
	return card_datas
