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

## SEPARATION-AGNOSTIC point storage (owner spec 2026-07-15): spread_by_separation points are
## STORED in FULL-CARD normalized space — "ratio 1 when separation == card height", i.e. a point
## authored while the visible strip equals the whole card is stored 1:1; authored in a smaller
## strip it is stored scaled UP into full-card space. Consumers project stored points into the
## CURRENT visible strip with norm_to_strip; editors convert edited positions back with
## strip_to_norm. Authoring the same visual pattern at ANY separation stores the SAME normalized
## points, and changing separation afterwards re-projects automatically (the store never changes).
## `factor` = current separation / CARD_SEPARATION everywhere: card_separation_scale in game,
## stack_separation / CARD_SEPARATION in the editor. The strip is factor * CARD_SEPARATION tall,
## anchored at the card TOP (spread grows downward); points are unscaled card space (center
## origin), so the top is -CARD_SIZE.y/2.

## Visible-strip height as a fraction of the full card at this separation factor (1.0 = the strip
## IS the whole card — the normalization's "ratio 1" reference).
static func strip_ratio(factor: float) -> float:
	return clampf(factor * float(CardVisual.CARD_SEPARATION) / CardVisual.CARD_SIZE.y, 0.0, 1.0)

## Project a STORED full-card y into the current visible strip (top-anchored, scaled down).
## Input is clamped to the card footprint first — a formation must stay inside ONE card, and a
## point authored BELOW a small strip once stored past the card bottom (knife.tres 2026-07-15:
## y up to 73 on a 50-tall card sent knives 1.5 cards under their row); clamping on consume
## heals any such .tres.
static func norm_to_strip(y: float, factor: float) -> float:
	var top := -CardVisual.CARD_SIZE.y * 0.5
	var yc := clampf(y, top, top + CardVisual.CARD_SIZE.y)
	return top + (yc - top) * strip_ratio(factor)

## Inverse of norm_to_strip: a y placed/edited in the current strip, scaled UP into full-card
## storage space so it fills the same fraction of the strip at every separation level. Output is
## clamped to the card footprint — placing a point below the visible strip stores the card
## bottom, never a point outside the card (same rule the clamp above enforces on read).
static func strip_to_norm(y: float, factor: float) -> float:
	var top := -CardVisual.CARD_SIZE.y * 0.5
	var r := strip_ratio(factor)
	var y_norm := top + (y - top) / r if r > 0.0 else top
	return clampf(y_norm, top, top + CardVisual.CARD_SIZE.y)

## One batch's point ASSIGNMENT with NO projection applied — the STORED points in draw order plus
## the drawn formation's spread flag: {"points": Array[Vector2], "spread": bool}. For consumers
## that re-project LIVE as settings change (PropLayer derives every prop's pixel offset per frame
## from these). Seeded identically to offsets_for. One formation is drawn from the set, then its
## `mode` decides the point walk: ORDERED = exact list order (prop i -> point i), RANDOM = a
## seeded SHUFFLE of the list (points only, no repeats until all are used). Either way extras
## wrap back onto the points — overflow never leaves the card footprint (trains separate overflow
## in TIME via countdown stagger) — and a full batch fills every point.
func assignment_for(count: int, seed_value: int) -> Dictionary:
	var out : Array[Vector2] = []
	out.resize(count)
	out.fill(Vector2.ZERO)
	var result := {"points": out, "spread": false}
	if count <= 0 or formations.is_empty(): return result
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var formation : PropFormationData = formations[rng.randi() % formations.size()]
	var pts := formation.points
	if pts.is_empty(): return result
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
		var pt := pts[order[i % order.size()]]
		out[i] = Vector2(pt.x, pt.y)
	result["spread"] = formation.spread_by_separation
	return result

## UNSCALED per-prop offsets for a batch of `count` props, PROJECTED into the strip the given
## `separation_factor` implies (norm_to_strip) when the drawn formation's spread_by_separation is
## ON; fixed card-space y when off. The editor previewer consumes this snapshot form; the game
## (PropLayer) uses assignment_for instead and re-projects live every frame.
func offsets_for(count: int, seed_value: int, separation_factor : float = 1.0) -> Array[Vector2]:
	var assign := assignment_for(count, seed_value)
	var pts : Array[Vector2] = assign["points"]
	var stretch : bool = assign["spread"]
	var out : Array[Vector2] = []
	for pt : Vector2 in pts:
		out.append(Vector2(pt.x, norm_to_strip(pt.y, separation_factor) if stretch else pt.y))
	return out
