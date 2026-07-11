@tool
class_name PipSuitFire
extends PipSuit

func get_suit_index() -> int: return 3
func get_str() -> String: return "Fire"
func get_description() -> String:
	return "On score: fire equal to rank flies down the column (skipping talents and Fire), leaving Burning."

## Fire is ballistic like Ball, but its mancala eligibility skips talents AND other Fire cards,
## and it drops Burning (which buffs the target's own suit-effect count). The same-act cascade
## (row Burning buffing those cards' columns later this submit) is intended.
func spawn_props() -> Array[PropSpawner]:
	var v := _spawn_origin()
	if v == Vector3i.MIN: return []
	var count := _spawn_count()
	var eligible := func(c: CardData) -> bool: return c.skill == null and not (c.suit is PipSuitFire)
	var targets := game.mancala_targets(v, count, eligible)
	if targets.is_empty(): return []
	var burning := _burning_mods()
	var origin_card : CardData = data
	var sp := PropSpawner.new()
	sp.origin = v
	sp.remaining = targets.size()
	sp.batch_size = 1
	sp.interval = 1
	sp.factory = func(i: int) -> PropData:
		var p := PropData.new()
		p.kind = 3
		p.route = [targets[i]] as Array[Vector3i]
		p.source = origin_card
		p.mods = [PropDropStatus.new(StatusBurning, PropData.Reaction.BURN)] as Array[PropModifier]
		p.mods.append_array(burning)
		return p
	return [sp] as Array[PropSpawner]
