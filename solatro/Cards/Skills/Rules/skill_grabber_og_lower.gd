class_name SkillGrabberOgLower
extends CardModifierSkill

func get_str() -> String:
	return "Grabber Classic"
func get_description() -> String:
	return "Pickup stack in lower zone if cards ascend or descend in value and do not repeat suits"
func get_frame() -> int: return 5

## Engine rules machinery (§15a): never a combo class.
func combo_key(_hook: StringName = &"") -> String: return ""

func on_can_grab_stack(target : CardData) -> Array[CardData]:
	if not game: return []
	var vec3 := game.find_data_vec3(target)
	if vec3 == Vector3i.MIN or vec3.x == 0: return []
	var zone := game.get_zone_from_vec3(vec3)
	var stack: Array[CardData] = zone[vec3.y].datas.slice(vec3.z)
	for i in stack.size() - 1:
		var same_suit := await PipComparator.is_suit_same(stack[i].suit,stack[i+1].suit)
		var rank_diff := await PipComparator.compare_ranks(stack[i].rank,stack[i+1].rank)
		#incomparable (NAN) ranks / repeated suits never form a valid run
		if is_nan(rank_diff): return []
		if not (not same_suit and absf(rank_diff) == 1): return []
	return stack
	
