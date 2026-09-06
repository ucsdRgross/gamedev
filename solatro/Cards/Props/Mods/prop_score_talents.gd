class_name PropScoreTalents
extends PropModifier
## Hoop effect: on passing a TALENTED card (one carrying a skill), bank `points` into that
## card's row gutter. Talents jump through the hoop and score; plain cards are ignored.

var points : int

func _init(p := 1) -> void:
	points = p

## An Entrance card banks into the Entrance's OWN row bucket, a grid card into its row's; both register their combo class here.
func on_pass_card(_prop: PropData, g: Game, card: CardData) -> void:
	if card.skill:   # talent PRESENCE (not .active — covered talents still count)
		var v := g.state.grid_position_of(card)
		if v.is_nowhere(): return
		g.register_combo(combo_key())
		g.add_line_score(ScoringSection.of_row_at(g.state, v), points)

func reaction_for(_prop: PropData, card: CardData) -> int:
	return PropData.Reaction.JUMP if card.skill else PropData.Reaction.NONE
