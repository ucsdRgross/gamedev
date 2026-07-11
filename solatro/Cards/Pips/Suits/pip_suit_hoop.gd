@tool
class_name PipSuitHoop
extends PipSuit

func get_suit_index() -> int: return 0
func get_str() -> String: return "Hoop"
func get_description() -> String:
	return "On score: hoops equal to rank cross this row. Talents they pass jump through and score."
func spawn_props() -> Array: return []   # Phase 3
