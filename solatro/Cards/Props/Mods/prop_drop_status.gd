class_name PropDropStatus
extends PropModifier
## Ballistic Ball/Fire effect: on arrival at the target card, apply one stack of a status
## (the drop IS the arrival). `reaction` is the fixed view hint (JUGGLE for balls, BURN for
## fire). The target already passed the spawner's eligibility filter, so no re-check here.

var status_script : GDScript
var reaction : int

func _init(script: GDScript = null, react := PropData.Reaction.JUGGLE) -> void:
	status_script = script
	reaction = react

func on_pass_card(_prop: PropData, _g: Game, card: CardData) -> void:
	card.add_status(CardModifierStatus.stacked(status_script, 1))

func reaction_for(_prop: PropData, _card: CardData) -> int:
	return reaction
