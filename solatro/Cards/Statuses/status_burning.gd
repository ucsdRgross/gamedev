class_name StatusBurning
extends CardModifierStatus
## Dropped by Fire props. Has no hooks of its own — it is read at spawn time by
## PipSuit.fire_stacks() / fire_mult(), which multiply the card's OWN suit-effect prop COUNT.
## The same-act cascade (a row meld's Burning buffing those cards' columns when they score
## later in the same submit) is intended (owner ruling).

func get_str() -> String: return TRANSLATION.find('STATUS_BURNING')
func get_description() -> String:
	return TRANSLATION.find('STATUS_BURNING_DESCRIPTION') % stacks
func get_frame() -> int: return 1

## The card's own fire. Declared here rather than in the FX layer — so FxAttachment never learns that
## fire exists. This is the CARD's effect only: a burning card does NOT light the balls it is juggling
## (owner rulings 3 and 21); those carry their own levels.
func fx_request() -> Array[FxRequest]:
	return [FxFire.request(&"fire", stacks, CARD_FIRE_STYLE)]

const CARD_FIRE_STYLE := preload("res://Shaders/Styles/fire_card.tres")
