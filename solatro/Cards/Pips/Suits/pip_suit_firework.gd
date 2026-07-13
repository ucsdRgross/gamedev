@tool
class_name PipSuitFirework
extends PipSuit
## Special 5th suit. NOT in PipSuit.STANDARD — never rolled randomly.

const FIREWORK_POINTS := 1

func get_suit_index() -> int: return 4
func get_str() -> String: return TRANSLATION.find('SUIT_FIREWORK')
func get_description() -> String: return TRANSLATION.find('SUIT_FIREWORK_DESCRIPTION')

## Fireworks rise up their column (a staggered rocket per tick) and each banks column score at
## the edge. The rise route may be empty (card at the top) — then it banks immediately.
func spawn_props() -> Array[PropSpawner]:
	var v := _spawn_origin()
	if v == Vector3i.MIN: return []
	var count := _spawn_count()
	var route := game.column_rise_path(v)
	var col := v.y
	var origin_card : CardData = data
	var sp := PropSpawner.new()
	sp.origin = v
	sp.remaining = count
	sp.batch_size = 1
	sp.interval = 1   # staggered rockets
	sp.factory = func(_i: int) -> PropData:
		var p := PropData.new()
		p.kind = 4
		p.route = route.duplicate()
		p.source = origin_card
		p.mods = [PropBankColScore.new(col, FIREWORK_POINTS)] as Array[PropModifier]
		return p
	return [sp] as Array[PropSpawner]
