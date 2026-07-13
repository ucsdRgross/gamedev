@tool
class_name PipSuitBall
extends PipSuit

func get_suit_index() -> int: return 2
func get_str() -> String: return TRANSLATION.find('SUIT_BALL')
func get_description() -> String: return TRANSLATION.find('SUIT_BALL_DESCRIPTION')

## Balls are ballistic: a mancala walk down the column picks `count` talent targets at spawn
## (pure data), and one ball per tick flies straight to each, dropping Juggling on arrival.
func spawn_props() -> Array[PropSpawner]:
	var v := _spawn_origin()
	if v == Vector3i.MIN: return []
	var count := _spawn_count()
	var targets := game.mancala_targets(v, count, func(c: CardData) -> bool: return c.skill != null)
	if targets.is_empty(): return []
	var burning := _burning_mods()
	var origin_card : CardData = data
	var sp := PropSpawner.new()
	sp.origin = v
	sp.remaining = targets.size()
	sp.batch_size = 1
	sp.interval = 1   # one drop lands per tick, in emission order
	sp.factory = func(i: int) -> PropData:
		var p := PropData.new()
		p.kind = 2
		p.route = [targets[i]] as Array[Vector3i]
		p.source = origin_card
		p.mods = [PropDropStatus.new(StatusJuggling, PropData.Reaction.JUGGLE)] as Array[PropModifier]
		p.mods.append_array(burning)
		return p
	return [sp] as Array[PropSpawner]
