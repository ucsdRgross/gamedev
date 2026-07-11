@tool
class_name PipSuitBall
extends PipSuit

func get_suit_index() -> int: return 2
func get_str() -> String: return "Ball"
func get_description() -> String:
	return "On score: balls equal to rank fly to talents down the column (mancala), leaving Juggling."
func spawn_props() -> Array: return []   # Phase 3
