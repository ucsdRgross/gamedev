@tool
class_name PropFormationSet
extends Resource
## All formations one prop KIND can spawn in (owner spec 2026-07-13). Saved per kind as
## res://Cards/Props/Formations/<kind_name>.tres by the formation editor tool; a MISSING file
## means the kind has NO formation and its props fly the exact slot line (the default for
## every kind until the owner authors one). Each batch picks ONE formation (seeded random
## across `formations`) and maps its props onto that formation's points — never onto random
## free positions. Offsets are VIEW-ONLY (PropVisual.lane_offset); data/replay never see them.

@export var formations : Array[PropFormationData] = []

const KIND_NAMES : Array[String] = ["hoop", "knife", "ball", "fire", "firework"]
const DIR := "res://Cards/Props/Formations"

static func path_for_kind(kind: int) -> String:
	var name := KIND_NAMES[kind] if kind >= 0 and kind < KIND_NAMES.size() else str(kind)
	return "%s/%s.tres" % [DIR, name]

## The kind's saved set, or null when none exists (= no formation, slot-line flight).
static func load_for_kind(kind: int) -> PropFormationSet:
	var path := path_for_kind(kind)
	if not ResourceLoader.exists(path): return null
	return load(path) as PropFormationSet

## The formation a batch seeded with `seed_value` will draw — the FIRST rng draw, identical
## to offsets_for's, so the editor previewer can chunk overflow exactly like the game would.
func pick_formation(seed_value: int) -> PropFormationData:
	if formations.is_empty(): return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return formations[rng.randi() % formations.size()]

## UNSCALED per-prop offsets for a batch of `count` props, seeded so the same batch replays
## identically. One formation is drawn from the set, then its `mode` decides the point walk:
## DETERMINISTIC = exact list order (prop i -> point i), RANDOM = a seeded SHUFFLE of the
## list (points only, no repeats until all are used). Either way extras wrap back onto the
## points — overflow never leaves the card footprint (trains separate overflow in TIME via
## countdown stagger) — and a full batch fills every point.
func offsets_for(count: int, seed_value: int) -> Array[Vector2]:
	var out : Array[Vector2] = []
	out.resize(count)
	out.fill(Vector2.ZERO)
	if count <= 0 or formations.is_empty(): return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var formation : PropFormationData = formations[rng.randi() % formations.size()]
	var pts := formation.points
	if pts.is_empty(): return out
	var order : Array[int] = []
	for i : int in pts.size():
		order.append(i)
	if formation.mode == PropFormationData.Mode.RANDOM:
		# Fisher-Yates with OUR rng (Array.shuffle uses the global one — not seedable per batch)
		for i : int in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := order[i]
			order[i] = order[j]
			order[j] = tmp
	for i : int in count:
		out[i] = pts[order[i % order.size()]]
	return out
