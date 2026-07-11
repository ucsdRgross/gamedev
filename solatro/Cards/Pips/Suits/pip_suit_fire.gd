@tool
class_name PipSuitFire
extends PipSuit

func get_suit_index() -> int: return 3
func get_str() -> String: return "Fire"
func get_description() -> String:
	return "On score: fire equal to rank flies down the column (skipping talents and Fire), leaving Burning."
func spawn_props() -> Array: return []   # Phase 3
