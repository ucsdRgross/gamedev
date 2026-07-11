@tool
class_name PipSuitKnife
extends PipSuit

func get_suit_index() -> int: return 1
func get_str() -> String: return "Knife"
func get_description() -> String:
	return "On score: knives equal to rank cross this row from the far side. Props they pass are scored; talents spin."
func spawn_props() -> Array: return []   # Phase 3
