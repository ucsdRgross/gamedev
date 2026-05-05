class_name SkillStackGrabberOg
extends CardModifierSkill

func get_str() -> String:
	return "Grabber Classic"
func get_description() -> String:
	return "Pickup stack if cards ascend or descend in value and do not repeat suits"
func get_frame() -> int: return 5

func on_can_grab_stack(target : CardData) -> Array[CardData]:
	var vec3 := Game.CURRENT.find_data_vec3(target)
	var zone := Game.CURRENT.get_zone_from_vec3(vec3)
	var stack: Array[CardData] = zone[vec3.y].datas.slice(vec3.z)
	for i in stack.size() - 1:
		if not (await PipComparator.compare_suits(stack[i].suit,stack[i+1].suit) != 0
				and abs(await PipComparator.compare_ranks(stack[i].rank,stack[i+1].rank)) == 1):
			return []
	return stack
	
