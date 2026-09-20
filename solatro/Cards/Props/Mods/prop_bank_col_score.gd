class_name PropBankColScore
extends PropModifier
## Firework effect: the finished rocket -- at once if its rise route was empty -- banks `points` into its own column's score bucket.

## Where the rocket launched from -- the ONE naming of its column, so nothing re-derives it.
var origin : BoardCoord
var points : int

func _init(v: BoardCoord, p := 1) -> void:
	origin = v
	points = p

func on_finish(_prop: PropData, g: Game) -> void:
	g.register_combo(combo_key())
	g.add_line_score(ScoringSection.of_line_for(g.state, origin, ScoringSection.LineKind.COL),
			points)
