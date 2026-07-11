@tool
class_name PipSuitKnife
extends PipSuit

const KNIFE_POINTS := 1
const KNIFE_TICKS_PER_SLOT := 2

func get_suit_index() -> int: return 1
func get_str() -> String: return "Knife"
func get_description() -> String:
	return "On score: knives equal to rank cross this row from the far side. Props they pass are scored; talents spin."

## Knives mirror hoops: same batch burst, but from the OPPOSITE side, scoring plain cards
## (props) instead of talents. The route includes the knife's own card (self-scored by design).
func spawn_props() -> Array[PropSpawner]:
	var v := _spawn_origin()
	if v == Vector3i.MIN: return []
	var count := _spawn_count()
	var route := game.row_slot_path(v, not game.entity_side_for_row(v))
	var burning := _burning_mods()
	var origin_card : CardData = data
	var sp := PropSpawner.new()
	sp.origin = v
	sp.remaining = count
	sp.batch_size = count
	sp.factory = func(_i: int) -> PropData:
		var p := PropData.new()
		p.kind = 1
		p.ticks_per_slot = KNIFE_TICKS_PER_SLOT
		p.route = route.duplicate()
		p.source = origin_card
		p.mods = [PropScoreProps.new(KNIFE_POINTS)] as Array[PropModifier]
		p.mods.append_array(burning)
		return p
	return [sp] as Array[PropSpawner]
