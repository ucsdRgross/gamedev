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
	if not api or not api.is_live(): return []
	var vec3 := api.find_data_vec3(target)
	if vec3 == Vector3i.MIN or vec3.x == 0: return []
	var zone := api.get_zone_from_vec3(vec3)
	var stack: Array[CardData] = zone[vec3.y].datas.slice(vec3.z)
	for i in stack.size() - 1:
		#S21: the STACK sameness hooks, not the ordering ones (QR3=c, Q62=a, Q83=a, Q97).
		var same_suit := await PipComparator.stack_suits_same(stack[i].suit,stack[i+1].suit)
		var rank_diff := await PipComparator.compare_ranks(stack[i].rank,stack[i+1].rank)
		#incomparable (NAN) ranks / repeated suits never form a valid run
		if is_nan(rank_diff): return []
		if not (not same_suit and absf(rank_diff) == 1): return []
	return stack
	
