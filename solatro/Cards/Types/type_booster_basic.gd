class_name TypeBoosterBasic
extends CardModifierType
	
func get_str() -> String: return "Basic Booster"
func get_description() -> String: return "Contains 5 standard cards"
func get_frame() -> int: return 5

func get_possible_ranks() -> Array[PipRank]:
	var ranks : Array[PipRank]
	ranks.resize(13)
	for i in 13:
		ranks[i] = PipRank.Numeral.new().with_value(i + 1)
	return ranks
func get_possible_suits() -> Array[PipSuit]:
	var suits : Array[PipSuit]
	suits.resize(4)
	for i in 4:
		suits[i] = PipSuit.Standard.new().with_value(i + 1)
	return suits
func get_possible_stamps() -> Array[CardModifierStamp]:
	return []
func get_possible_skills() -> Array[CardModifierSkill]:
	return []
func get_possible_types() -> Array[CardModifierType]:
	return []
	
