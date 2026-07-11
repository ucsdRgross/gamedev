class_name StatusJuggling
extends CardModifierStatus
## Dropped by Ball props. When its card is scored, banks `stacks` into that card's COLUMN
## gutter (the balls it is juggling pay out). Self-scoped like every status.

func get_str() -> String: return "Juggling"
func get_description() -> String:
	return "When scored: +%d column score (balls juggled)." % stacks
func get_frame() -> int: return 0

func on_score(target: CardData) -> void:
	if target != data: return
	if not game: return
	var v := game.find_data_vec3(data)
	if v == Vector3i.MIN: return
	game.add_line_score(false, game.state.scores_col, v.y, stacks)
