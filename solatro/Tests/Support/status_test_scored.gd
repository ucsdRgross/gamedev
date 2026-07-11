class_name StatusTestScored extends CardModifierStatus
## Self-scoped, self-consuming test status: on its OWN card being scored it records the
## hit and spends a stack (exercising self-scope guarding AND removal mid-dispatch).
func get_str() -> String: return "TestScored"
func get_description() -> String: return "test status: consumes a stack on score"
func get_frame() -> int: return 3

## Set by the test to observe how many times on_score fired for THIS card.
var hits : int = 0

func on_score(target: CardData) -> void:
	if target != data: return   # self-scope: ignore other cards' scoring
	hits += 1
	stacks -= 1                 # setter removes this status from the card at 0
