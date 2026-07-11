@tool
class_name PipSuitFirework
extends PipSuit
## Special 5th suit. NOT in PipSuit.STANDARD — never rolled randomly.

func get_suit_index() -> int: return 4
func get_str() -> String: return "Firework"
func get_description() -> String:
	return "On score: fireworks equal to rank rise up the column and bank column score at the top."
func spawn_props() -> Array: return []   # Phase 3
