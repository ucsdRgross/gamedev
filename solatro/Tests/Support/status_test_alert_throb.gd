class_name StatusTestAlertThrob extends CardModifierStatus
## The SECOND test-only alerting status, and it exists to be the second one. Two statuses alerting at
## once is the case a bool or a pushed on/off flag gets wrong — clearing one switches off the other —
## so the test needs two DIFFERENT classes (statuses of the same class merge instead of coexisting,
## `can_merge_with`), and it needs them to declare distinguishable alerts.
func get_str() -> String: return "TestAlertThrob"
func get_description() -> String: return "test status: declares a THROB alert"
func get_frame() -> int: return 0

func alert_request() -> Array[CardAlert]:
	return [CardAlert.throb(PaletteDB.ROLES.suit_fire)] as Array[CardAlert]
