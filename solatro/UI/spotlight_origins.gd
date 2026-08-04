class_name SpotlightOrigins
extends RefCounted
## WHERE EVERY BEAM COMES FROM — the origin allocator of design chart I (I1–I12), and nothing else.
## It is deliberately separate from `LightLayer`: the layer answers *"what does a lit pixel look
## like"* and this answers *"where is the lamp"*, and the second is pure arithmetic over screen
## coordinates with no material, no node and no frame. That is what makes it testable HEADLESS,
## which matters because none of its rules are things an eye can check — *"no two origins share a
## y"* and *"a beam never points upward"* are assertions, not looks.
##
## THE MODEL, AS CHART I STATES IT:
##
##     k0 origins spread evenly across the band, min 4                 (I2, Q109=a)
##     each gets a deterministic y scatter — no two share a y          (I3, Q113=d, Q250=a)
##     a request takes the FREE origin NEAREST its target              (I7, Q111=a)
##     pool empty -> SUBDIVIDE at midpoints, pick at random            (I8, I9)
##     an origin above the viewport re-spreads its x every frame       (I12, Q251=b, Q262=a)
##     an origin on screen is PINNED                                   (I11, Q164)
##
## ⚠ **DETERMINISTIC BY CONSTRUCTION, AND THAT IS A REQUIREMENT RATHER THAN A CONVENIENCE.** The y
## scatter and the subdivision draw from a seeded stream owned by this object, never from the global
## RNG: `test_pixels` and the snapshot harness both depend on two runs of an unchanged build
## producing the same frame, and a lamp that moves between runs makes every beam panel a false diff.

## The minimum number of origins the band starts with (`Q109`=a). Below this the spread reads as one
## or two lamps rather than a rig, and the common case — a section of four or five cards — then
## lands perfectly even.
const MIN_ORIGINS := 4

## How far above its target an origin sits, in screen pixels (`Q114`=a, and the owner's note says
## **tunable** — `LightLayer`'s caller passes its own if the board is scaled differently).
const DEFAULT_RISE := 600.0

## The y scatter's span, as a fraction of `rise`. ⚠ **ITS ONLY JOB IS THAT NO TWO ORIGINS SHARE A
## Y** (`Q113`=d — *"no beam origins should have identical y level even if target cards have
## identical y level on same row"*), so what matters is that the offsets are DISTINCT, not that they
## are large. A few lamp-heights of spread is enough to read as a rig rather than a curtain rail.
const SCATTER_SPAN := 0.18

## The seeded stream. ⚠ NOT `randf()` — see the header.
var _rng := RandomNumberGenerator.new()
## Every origin this allocator has placed, in x order. Screen coordinates.
var _origins : PackedVector2Array = PackedVector2Array()
## Which origins are currently handed out, by index into `_origins`.
var _taken : Dictionary[int, bool] = {}
## The band the origins spread across — the visible width, and the y they rise above.
var _width : float = 1280.0
var _rise : float = DEFAULT_RISE

func _init(seed_value: int = 20260804) -> void:
	_rng.seed = seed_value

## Start a cue: size the band and lay out `count` origins, minimum `MIN_ORIGINS` (I2, I3).
##
## `top_y` is the y every origin rises ABOVE — the top of the board in screen coordinates, so the
## lamps sit off-screen above it by `rise`.
func begin(count: int, width: float, top_y: float, rise: float = DEFAULT_RISE) -> void:
	_width = maxf(width, 1.0)
	_rise = maxf(rise, 1.0)
	_origins = PackedVector2Array()
	_taken = {}
	var k0 := maxi(count, MIN_ORIGINS)
	for i : int in k0:
		_origins.append(Vector2(_even_x(i, k0), top_y - _rise - _scatter(i)))

## Evenly across the band, each origin at the centre of its own share of the width — so the outer
## two are inset by half a share rather than pinned to the screen edges, which is what keeps the
## spread even rather than merely spanning.
func _even_x(i: int, count: int) -> float:
	return _width * (float(i) + 0.5) / float(maxi(count, 1))

## This origin's own y offset. ⚠ **DISTINCT PER INDEX, NOT RANDOM PER CALL** — it is derived from the
## index through the seeded stream once, so re-deriving the same origin gives the same y. Two
## origins sharing a y is the one thing `Q113`=(d) forbids, and a re-roll on every read would break
## it silently on the frame two indices happened to collide.
func _scatter(i: int) -> float:
	# A deterministic hash of the index into [0,1), then spread across the span. The multiply keeps
	# adjacent indices far apart in the output, so a rig of four does not come out nearly level.
	var h := fmod(float(i) * 0.6180339887 + float(_rng.seed % 1024) * 0.0009765625, 1.0)
	return h * SCATTER_SPAN * _rise

## THE FREE ORIGIN NEAREST `target` (I7, `Q111`=a) — which is what keeps beams mostly vertical and
## mostly non-crossing without any explicit rule about either. Subdivides when the pool is empty.
##
## ⚠ Returns the origin's INDEX, not the point: the caller needs the index to release it, and a
## point can no longer identify its origin once `advance` has re-spread the ones off screen.
func take(target: Vector2) -> int:
	if _taken.size() >= _origins.size():
		_subdivide()
	var best := -1
	var best_d := INF
	for i : int in _origins.size():
		if _taken.has(i): continue
		var d := absf(_origins[i].x - target.x)
		if d < best_d:
			best_d = d
			best = i
	if best < 0: return -1
	_taken[best] = true
	return best

## SUBDIVIDE (I8, I9): every midpoint between adjacent origins becomes a candidate, and candidates
## are taken at random until the request is satisfied — the rest join the pool. Since the caller
## asks for one at a time, "satisfied" is one, and the rest of the midpoints stay available, which
## is exactly the pool the chart describes.
##
## ⚠ Each new origin gets its own scatter from the same stream, so the no-shared-y rule survives
## subdivision — the case where it is most likely to be violated, because a midpoint's neighbours
## are by construction close together.
func _subdivide() -> void:
	if _origins.size() < 2:
		_origins.append(Vector2(_even_x(_origins.size(), _origins.size() + 1),
				_origins[0].y if _origins.size() > 0 else -_rise))
		return
	# ⚠ **A SORTED VIEW, NEVER A SORTED STORE.** `_origins` is APPEND-ONLY and its indices are
	# permanent handles the caller holds across frames — re-ordering it re-points every live handle
	# at somebody else's lamp. The first build sorted the store and rebuilt the taken-set to match,
	# which fixed the set and not the CALLER's copies: measured, two beams came back sharing one
	# origin index after the first subdivision. Adjacency is a property of the x order, so the order
	# is computed here and thrown away.
	var order : Array[float] = []
	for p : Vector2 in _origins: order.append(p.x)
	order.sort()
	var mids : Array[float] = []
	for i : int in order.size() - 1:
		mids.append((order[i] + order[i + 1]) * 0.5)
	# Randomised order — "picked at random" (I9) is about WHICH midpoint is used first when not all
	# are needed, not about where any of them ends up.
	for i : int in mids.size():
		var j := _rng.randi_range(0, mids.size() - 1)
		var tmp := mids[i]
		mids[i] = mids[j]
		mids[j] = tmp
	var base := _origins.size()
	var band_y : float = _origins[0].y
	for i : int in mids.size():
		_origins.append(Vector2(mids[i], band_y - _scatter(base + i)))

## Give an origin back to the pool.
func release(index: int) -> void:
	_taken.erase(index)

func origin_of(index: int) -> Vector2:
	return _origins[index] if index >= 0 and index < _origins.size() else Vector2.ZERO

func count() -> int:
	return _origins.size()

## PER FRAME (I10–I12): an origin ABOVE the viewport re-spreads its x to fill the visible width
## (`Q251`=b, `Q262`=a); one that is on screen is PINNED (`Q164`).
##
## ⚠ **THE TWO HALVES ARE ONE ANSWER, NOT A CONTRADICTION.** `Q164` promises an origin does not move
## once assigned; `Q251` re-spreads it every frame. Both hold because the re-spread only ever
## touches origins you cannot see — *"an origin you cannot see costs nothing to move"* — and the
## moment one enters the viewport it stops moving for good. What `Q164` actually protects is a
## VISIBLE lamp sliding, and that never happens.
func advance(viewport_top: float) -> void:
	var above : Array[int] = []
	for i : int in _origins.size():
		if _origins[i].y < viewport_top: above.append(i)
	if above.is_empty(): return
	# Re-spread only the invisible ones, across the same band, keeping their order. The on-screen
	# ones keep their x exactly, so a pinned lamp is untouched by a neighbour's re-spread.
	for slot : int in above.size():
		var i : int = above[slot]
		_origins[i] = Vector2(_even_x(slot, above.size()), _origins[i].y)

## ⚠ **A BEAM NEVER POINTS UPWARD** (`Q117`, the owner's own words: *"beam still draws from screen
## edge, but only if target is below viewport bottom. beam can never point upwards"*). An origin
## always sits above its target, so the only way to violate it is a target BELOW the viewport — and
## the answer there is not to tilt the beam up, it is to bring the origin in from the screen edge.
## This is the check that says whether that case is live; the origin it returns enters at the top
## edge of the viewport rather than from the rig above it.
static func edge_origin_for(target: Vector2, viewport_top: float, viewport_bottom: float,
		fallback: Vector2) -> Vector2:
	if target.y <= viewport_bottom: return fallback
	# Below the viewport: come in from the top edge, straight down, so the cone still points down.
	return Vector2(target.x, viewport_top - 1.0)

## Is this pairing legal — the assertion `Q117` is, stated so a test can hold the whole rule rather
## than a sample of it. An origin must be strictly ABOVE its target; equal is not allowed either,
## because a zero-length axis has no direction and the shader would divide by it.
static func points_down(origin: Vector2, target: Vector2) -> bool:
	return origin.y < target.y
