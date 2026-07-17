class_name TypeStone
extends CardModifierType

func get_str() -> String: return "Stone Card"
func get_description() -> String: return "Sinks to bottom of every stack"
func get_frame() -> int: return 4

# TODO(stone sinking): the described behavior is UNIMPLEMENTED — a Stone card should
# sink below non-Stone cards when stacked (on_stack_card: move itself under the stack)
# and sort to the front of the deck on shuffle (on_append: erase + insert after the
# leading Stone run). The old draft targeted the deleted `Card` class; a rewrite goes
# through Board.move_stack / the sanctioned on_append hook (see Game.shuffle_deck).
