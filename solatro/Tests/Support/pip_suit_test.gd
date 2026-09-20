class_name PipSuitTest
extends PipSuit
## Test-only suit: one parameterized class standing in for unlimited distinct suits.

var id : int = 0

# Art slot and palette role are never drawn in these tests; any valid value will do.
func get_suit_index() -> int: return id % 4
func palette_role() -> int: return PaletteDB.ROLES.suit_hoop

# A distinct id must print as a distinct suit -- nominal identity is what PipComparator.printed_same
# compares, so scoring tests stay clear of accidental flushes. Suit-behaviour tests use the real
# Hoop/Knife/Ball/Fire classes instead.
func get_str() -> String: return "TestSuit%d" % id
func get_plural_str() -> String: return "TestSuit%ds" % id
func get_description() -> String: return "test suit"

# Inert in scoring tests: no props to spawn.
func spawn_props() -> Array[PropSpawner]: return []

static func with_id(i:int) -> PipSuitTest:
	var s := PipSuitTest.new()
	s.id = i
	return s
