class_name PlayerSave
extends Resource

## Serialized card-list container for the Deck Maker dev tool (deck_builder.gd profiles
## at user://soltaro_save.tres). Run progression moved to RunState/RunManager.

#Only variables with @export are saved
@export var card_datas : Array[CardData]

func write_card_data(data: CardData) -> void:
	card_datas.append(data)

func read_card_data() -> Array[CardData]:
	return card_datas
