class_name StatusTestSeal extends CardModifierStatus
## Non-merging test status: overrides can_merge_with so two applications stay two entries.
func get_str() -> String: return "TestSeal"
func get_description() -> String: return "test status seal (non-merging)"
func get_frame() -> int: return 2
func can_merge_with(_other: CardModifierStatus) -> bool: return false
