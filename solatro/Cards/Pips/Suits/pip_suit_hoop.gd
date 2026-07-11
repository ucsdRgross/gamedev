@tool
class_name PipSuitHoop
extends PipSuit

const HOOP_POINTS := 1
const HOOP_TICKS_PER_SLOT := 2

func get_suit_index() -> int: return 0
func get_str() -> String: return "Hoop"
func get_description() -> String:
	return "On score: hoops equal to rank cross this row. Talents they pass jump through and score."

## Hoops burst all at once from the card and cross the whole row (deterministic side), scoring
## every talent they pass.
func spawn_props() -> Array[PropSpawner]:
	var v := _spawn_origin()
	if v == Vector3i.MIN: return []
	var count := _spawn_count()
	var route := game.row_slot_path(v, game.entity_side_for_row(v))
	var burning := _burning_mods()
	var origin_card : CardData = data
	var sp := PropSpawner.new()
	sp.origin = v
	sp.remaining = count
	sp.batch_size = count   # all at once, staged as a train
	sp.factory = func(_i: int) -> PropData:
		var p := PropData.new()
		p.kind = 0
		p.ticks_per_slot = HOOP_TICKS_PER_SLOT
		p.route = route.duplicate()   # each prop pops its OWN copy
		p.source = origin_card
		p.mods = [PropScoreTalents.new(HOOP_POINTS)] as Array[PropModifier]
		p.mods.append_array(burning)
		return p
	return [sp] as Array[PropSpawner]
