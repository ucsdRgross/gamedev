class_name SpotlightTestSkill
extends CardModifierSkill
## Spy skill for the SPOTLIGHT suite. A FILE-BACKED class on purpose: the save-migration gate
## (G1.3) round-trips a state through `ResourceSaver`, and an inner class declared in a test
## script has no `res://` path to write, so it cannot survive the trip.
##
## `behaviour` is the hook body under test and is deliberately NOT `@export_storage` — a
## Callable does not serialize, and the migration gate only cares about the `spotlit` flag.

## Total `on_spotlight` bodies entered by ANY instance. Reset it at the top of a test that reads
## it; the per-instance counters below are what most checks want.
static var total_spotlight_calls : int = 0
## Every tag that entered `on_spotlight`, in fire order — the mod-fire log for gate G1.7.
static var fire_log : Array[String] = []

@export_storage var tag : String = ""

var spotlight_calls : int = 0
var unspotlight_calls : int = 0
## Runs inside `on_spotlight`, after the counters. Receives this skill. May mutate the board:
## `Q25`=(b) says a handler may do so IMMEDIATELY, and the sweep re-derives around it.
var behaviour : Callable = Callable()

func get_str() -> String: return "SpotlightSpy:" + tag
func get_description() -> String: return ""
func get_frame() -> int: return 0

## Engine test machinery: never a combo class —
## both would make the suite's assertions depend on unrelated act bookkeeping.
func combo_key(_hook: StringName = &"") -> String: return ""

func on_spotlight() -> void:
	spotlight_calls += 1
	total_spotlight_calls += 1
	fire_log.append(tag)
	if behaviour.is_valid():
		await behaviour.call(self)

func on_unspotlight() -> void:
	unspotlight_calls += 1

static func reset_statics() -> void:
	total_spotlight_calls = 0
	fire_log = []

static func make(tag_value: String, body: Callable = Callable()) -> SpotlightTestSkill:
	var s := SpotlightTestSkill.new()
	s.tag = tag_value
	s.behaviour = body
	return s
