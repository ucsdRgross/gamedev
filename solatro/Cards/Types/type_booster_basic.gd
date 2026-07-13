class_name TypeBoosterBasic
extends BoosterTemplate

func get_str() -> String: return "Basic Booster"
func get_description() -> String: return "Contains 5 standard cards"
func get_frame() -> int: return 5

func get_possible_ranks() -> Array[PipRank]:
	var ranks : Array[PipRank]
	ranks.resize(13)
	for i in 13:
		ranks[i] = PipRankNumeral.new().with_value(i + 1)
	return ranks
func get_possible_suits() -> Array[PipSuit]:
	var suits : Array[PipSuit]
	for suit : GDScript in PipSuit.STANDARD:
		suits.append(suit.new() as PipSuit)
	return suits
## Luck-gated extras: these only appear on generated cards when RunManager.luck rolls hit.
func get_possible_stamps() -> Array[CardModifierStamp]:
	return [StampRevealing.new(), StampGlobal.new(), StampDoubleTrigger.new()]
func get_possible_skills() -> Array[CardModifierSkill]:
	return [SkillExtraPoint.new(), SkillEchoingTrigger.new(), SkillHungryHippo.new()]
func get_possible_types() -> Array[CardModifierType]:
	return [TypePaper.new(), TypeHeavy.new(), TypeStone.new()]
