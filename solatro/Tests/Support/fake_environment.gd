class_name FakeEnvironment
extends CardEnvironment
## Test harness environment (UNIT_TESTS_PLAN.md T-ENV).
## Add as a child node so _enter_tree sets CardEnvironment.CURRENT; remove/free to restore.
## Collections are plain vars the test fills before dispatching.

var card_collections : Array[Variant] = []
var rules : Array[CardData] = []

func get_card_collections() -> Array[Variant]:
	return card_collections

func get_rules_collections() -> Array[CardData]:
	return rules

## No SettingsManager dependency in tests.
func get_delay() -> float:
	return 0.0

## Convenience: register a 1D collection of the given cards and return it.
func add_cards(cards: Array[CardData]) -> Array[CardData]:
	card_collections.append(cards)
	return cards
