class_name SkillPlacerOgLower
extends CardModifierSkill

func get_str() -> String:
	return "Placer Classic"
func get_description() -> String:
	return "Place stack in lower zone if top card ascends or descends in value and does not repeat suits"
func get_frame() -> int: return 6

func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
	if not (stack and target): return []
	var vec3 := Game.CURRENT.find_data_vec3(target)
	if vec3 == Vector3i.MIN or vec3.x == 0: return []
	if not Game.CURRENT.is_data_topmost(target): return []
	if not (await PipComparator.compare_suits(stack[0].suit,target.suit) != 0
			and abs(await PipComparator.compare_ranks(stack[0].rank,target.rank)) == 1):
		return []
	return stack
