class_name StatusBurning
extends CardModifierStatus
## Dropped by Fire props. Has no hooks of its own — it is read at spawn time by
## PipSuit.fire_stacks() / fire_mult(), which multiply the card's OWN suit-effect prop COUNT.
## The same-act cascade (a row meld's Burning buffing those cards' columns when they score
## later in the same submit) is intended (owner ruling).

func get_str() -> String: return "Burning"
func get_description() -> String:
	return "This card's suit effect count is boosted by %d." % stacks
func get_frame() -> int: return 1
