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

func on_pass_card(prop: PropData, _g: Game, card: CardData) -> void:
	var status := CardModifierStatus.stacked(status_script, 1)
	# Hand the dropped status whatever the prop was carrying BEFORE it lands, so per-stack
	# provenance survives the drop: a burning Ball prop used to leave its fire on the floor here.
	# Note this grants no Burning to the card — a burning ball landing raises that card's
	# StatusJuggling and nothing else (owner ruling 17).
	status.on_dropped_by(prop)
	card.add_status(status)

func reaction_for(_prop: PropData, _card: CardData) -> int:
	return reaction
