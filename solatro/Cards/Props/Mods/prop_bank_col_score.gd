class_name PropBankColScore
extends PropModifier
## Firework effect: when the rocket finishes its column rise (or immediately, if it started at
## the top with an empty route), bank `points` into its column's gutter. Cards it rises past
## still hear on_prop_passed (a free extension point) but are not scored by this mod.

var col : int
var points : int

func _init(c := 0, p := 1) -> void:
	col = c
	points = p

func on_finish(_prop: PropData, g: Game) -> void:
	g.add_line_score(false, g.state.scores_col, col, points)
