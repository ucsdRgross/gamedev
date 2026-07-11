class_name PipSuitTest
extends PipSuit
## Test-only suit: one parameterized class standing in for unlimited distinct suits.
## `id` drives get_str() so PipComparator.is_suit_same treats distinct ids as distinct
## suits (the nominal-identity rule), letting scoring tests avoid accidental flushes.
## Real suit-behaviour tests (Phase 3) use the real Hoop/Knife/Ball/Fire classes instead.

var id : int = 0

func get_suit_index() -> int: return id % 4          # art slot only; never rendered in tests
func get_str() -> String: return "TestSuit%d" % id   # distinct id => distinct suit
func get_description() -> String: return "test suit"
func spawn_props() -> Array: return []               # inert in scoring tests

static func with_id(i:int) -> PipSuitTest:
	var s := PipSuitTest.new()
	s.id = i
	return s
