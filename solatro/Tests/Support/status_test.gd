class_name StatusTestA extends CardModifierStatus
## Test-only mergeable status. Phase 2 has no shipping gameplay statuses yet
## (StatusJuggling / StatusBurning arrive in Phase 3), so the status tests and the
## persistence fuzz instantiate these test statuses instead.
func get_str() -> String: return "TestA"
func get_description() -> String: return "test status A"
func get_frame() -> int: return 0
