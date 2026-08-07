class_name StatusTestAlert extends CardModifierStatus
## Test-only status that DECLARES an outline alert. No shipping status alerts yet — the alert is the
## mechanism, and what should trigger it is content the owner has not written — so `test_outline`
## instantiates this rather than waiting for one, exactly as the status tests use `StatusTestA`.
##
## ⚠ It declares no FX, which under the standing rule on `CardModifierStatus.fx_request` means it has
## no card-side presence OTHER than the alert. That is the point: it isolates the alert path.
func get_str() -> String: return "TestAlert"
func get_description() -> String: return "test status: declares a GLARE alert"
func get_frame() -> int: return 0

func alert_request() -> Array[CardAlert]:
	return [CardAlert.glare()] as Array[CardAlert]
