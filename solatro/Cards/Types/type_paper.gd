@tool
class_name TypePaper
extends CardModifierType

func get_str() -> String: return TRANSLATION.find('TYPE_PAPER')
func get_description() -> String: return TRANSLATION.find('TYPE_PAPER_DESCRIPTION')
func has_effect() -> bool: return false
func get_frame() -> int: return 1
