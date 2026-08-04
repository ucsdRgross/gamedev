class_name SpotlightTestKuroko
extends CardModifierStamp
## The ONLY `blocks_spotlight() == false` implementation in the tree. Blocking is the DEFAULT —
## a card stacked on top hides the talent underneath it — and this is the Kuroko / Ghost Light
## shape that opts out, so the card beneath stays spotlit while covered (owner, GAP-001 answer
## 2026-08-04; design `Q9`=a, chart A8).
##
## It exists so S3's done-when can be asserted at all. Real content using the seam is out of
## scope (`Q185`=a).

func get_str() -> String: return "Kuroko"
func get_description() -> String: return "The card beneath this one stays spotlit"
func get_frame() -> int: return 0

func blocks_spotlight() -> bool:
	return false
