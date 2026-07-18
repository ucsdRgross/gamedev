class_name SkillPlacerOgLower
extends CardModifierSkill

func get_str() -> String:
	return "Placer Classic"
func get_description() -> String:
	return "Place stack in lower zone if top card ascends or descends in value and does not repeat suits"
func get_frame() -> int: return 6

## Engine rules machinery (§15a): never a combo class.
func combo_key(_hook: StringName = &"") -> String: return ""

func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
	if not (stack and target): return []
	if not game: return []
	var vec3 := game.find_data_vec3(target)
	if vec3 == Vector3i.MIN or vec3.x == 0: return []
	if not game.is_data_topmost(target): return []
	var same_suit := await PipComparator.is_suit_same(stack[0].suit,target.suit)
	var rank_diff := await PipComparator.compare_ranks(stack[0].rank,target.rank)
	#incomparable (NAN) ranks / repeated suits never form a valid run
	if is_nan(rank_diff): return []
	if not (not same_suit and absf(rank_diff) == 1): return []
	return stack
