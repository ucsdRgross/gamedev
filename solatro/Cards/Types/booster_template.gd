@abstract
class_name BoosterTemplate
extends CardModifierType

@abstract
func get_possible_ranks() -> Array[PipRank]
@abstract
func get_possible_suits() -> Array[PipSuit]
@abstract
func get_possible_stamps() -> Array[CardModifierStamp]
@abstract
func get_possible_skills() -> Array[CardModifierSkill]
@abstract
func get_possible_types() -> Array[CardModifierType]

func on_map_picked(map:Node) -> void:
	var choices : int = 5
	var choose : int = 0
	ChoiceViewer.add_to_scene(map, create_one_choice, choices, choose)
	
func create_one_choice() -> CardData:
	var data := CardData.new()
	# return new array of possible results after running through run all mods
	return data

func view_choices() -> void:
	pass
