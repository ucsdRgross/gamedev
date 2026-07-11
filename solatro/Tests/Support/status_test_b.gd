class_name StatusTestB extends CardModifierStatus
## Second mergeable test status, a distinct class from StatusTestA — used to prove
## heterogeneous statuses coexist as separate entries.
func get_str() -> String: return "TestB"
func get_description() -> String: return "test status B"
func get_frame() -> int: return 1
