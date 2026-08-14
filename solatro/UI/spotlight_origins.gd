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

## How close in x two targets must be to count as the same board COLUMN. A card is ~95 px wide at the
## shipped `card_scale`, so half of that groups a column without merging two.
const COLUMN_BUCKET_PX := 48.0

## **ASSIGN A WHOLE SET AT ONCE — A SECTION OF THE BAR PER COLUMN, AND A FAN BY DEPTH INSIDE IT.**
##
## The owner's rule, (GAP-008):
##
## > *"given column position, beam right above it would point straight down to topmost card. Then
## > alternating left and right from that center beam, go down column. However we need it to scale to
## > any set... we first divide top bar into sections, getting wider by row. middle of top gets first
## > `-1-`, 2nd row gets lamp area surrounding first row `-212-`, and so on with `-32123-`, with each
## > lamp within a row section choosing its closest."*
##
## **Two levels, and getting the order of them wrong is what broke it the first time:**
##
##   1. **The bar is divided into SECTIONS BY COLUMN, left to right.** A column with three lit cards
##      gets three adjacent lamps; the next column to its right gets the next three. Sections are
##      disjoint and in x order, so **no beam from one column can cross a beam from another.**
##   2. **Inside a section, the fan is by DEPTH**: the topmost card takes the lamp nearest its own
##      column (*"points straight down"*), and each deeper card takes the next lamp outward.
##
## ⚠ **THE FIRST IMPLEMENTATION PARTITIONED BY ROW ACROSS THE WHOLE BAR AND THAT IS WRONG.** It gave
## the shallowest ROW the centre of the entire bar and deeper rows the outer bands — which is correct
## for ONE column and wrong for everything else. The owner caught it on the six-card preset (three at
## depth 0, three at depth 1, interleaved across six columns): shallow cards were pulled to the middle
## and deep cards pushed to the edges, **inverting the x order and producing three crossings**. The
## picture was *"beam separation looks wrong here"*, and the arithmetic agreed — `col0 -> lamp2` while
## `col1 -> lamp0`. **A rule stated for one column had to be read as a rule about columns, not rows.**
##
## ⚠ **WHY IT CANNOT CROSS.** Between columns: sections are disjoint x ranges taken in x order, so
## the lamp order matches the column order by construction. Within a column: a deeper card's lamp is
## always further from that column and a lamp further out lands lower, so two beams on the same side
## converge without meeting, and two on opposite sides meet only at the column's x — which they reach
## at different heights.
##
## ⚠ **IT DEGRADES TO THE RIGHT THING FOR A ROW.** Every card is its own column, so every section is
## one lamp and the sections run left to right — the even spread a row has always had.
##
## Returns one origin index per target, in the CALLER'S order.
func assign(targets: Array[Vector2]) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(targets.size())
	if targets.is_empty(): return out
	while _origins.size() - _taken.size() < targets.size():
		var before := _origins.size()
		_subdivide()
		if _origins.size() == before: break   # cannot grow — bail rather than spin
	# Free lamps, left to right. ⚠ A SORTED VIEW, never a sorted store — `_origins` is append-only and
	# its indices are permanent handles the caller holds across frames.
	var free : Array[int] = []
	for i : int in _origins.size():
		if not _taken.has(i): free.append(i)
	free.sort_custom(func(a: int, b: int) -> bool: return _origins[a].x < _origins[b].x)
	if free.is_empty(): return out

	# GROUP BY COLUMN. Cards in one board column share an x within a pixel or two, so the key is
	# quantised — an unquantised key would make every card its own column and lose the fan entirely.
	var columns : Dictionary[int, Array] = {}
	for i : int in targets.size():
		var key := roundi(targets[i].x / COLUMN_BUCKET_PX)
		if not columns.has(key): columns[key] = ([] as Array[int])
		var bucket : Array = columns[key]
		bucket.append(i)
	var keys : Array[int] = []
	for k : int in columns: keys.append(k)
	keys.sort()

	var next_lamp := 0
	for k : int in keys:
		var members : Array = columns[k]
		# This column's SECTION of the bar: the next `members.size()` lamps, left to right.
		var section : Array[int] = []
		for _n : int in members.size():
			if next_lamp >= free.size(): break
			section.append(free[next_lamp])
			next_lamp += 1
		if section.is_empty(): continue
		# THE FAN: shallowest card first, and it takes the lamp NEAREST its own column — *"points
		# straight down"*. Each deeper card takes the next lamp outward.
		# ⚠ Ordered by DISTANCE, not by alternating left/right: strict alternation stops being
		# monotone the moment the column is not centred in its own section (a column at the screen
		# edge, or a ragged board), and monotone distance is the whole reason the fan cannot cross.
		var column_x : float = targets[members[0]].x
		section.sort_custom(func(a: int, b: int) -> bool:
			return absf(_origins[a].x - column_x) < absf(_origins[b].x - column_x))
		var by_depth : Array[int] = members.duplicate()
		by_depth.sort_custom(func(a: int, b: int) -> bool: return targets[a].y < targets[b].y)
		for n : int in by_depth.size():
			var slot : int = by_depth[n]
			if n >= section.size():
				out[slot] = -1
				continue
			var idx : int = section[n]
			_taken[idx] = true
			out[slot] = idx
	return out

## THE FREE ORIGIN NEAREST `target` (I7) — the one-at-a-time form, kept for callers that genuinely
## place a single light (chart T's momentary cue, where there is no set to sort).
## ⚠ **DO NOT USE IT FOR A SECTION.** Calling it in a loop is what produced the column crossings —
## see `assign()` above, and `gaps/GAP-008.md` for the ruling this is waiting on.
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
	# Re-spread only the invisible ones, across the same band, keeping their X ORDER. ⚠ Sorted by x,
	# never walked by index: `_subdivide()` appends midpoints at the END of the append-only store, so
	# after any subdivision index order no longer matches x order — an index-order walk permuted the
	# band, teleporting lamps that live beams were holding and re-crossing what `assign()` had just
	# untangled. The on-screen ones keep their x exactly, so a pinned lamp is untouched.
	above.sort_custom(func(a: int, b: int) -> bool: return _origins[a].x < _origins[b].x)
	for slot : int in above.size():
		var i : int = above[slot]
		_origins[i] = Vector2(_even_x(slot, above.size()), _origins[i].y)

## **WHICH LIGHTS SURVIVE WHEN THE NEXT SECTION IS SMALLER — the start index of the contiguous run of
## `sources` that should travel to `targets`. Both arrays are x-SORTED; both are screen x only.**
##
## ⚠ **TAKING THE FIRST N WAS A REAL BUG AND THE OWNER CAUGHT IT ON SCREEN:** *"when spotlight chooses
## new targets and there are less cards, it doesnt choose nearest spotlights but leftmost ones, so left
## beams cross all the way to right while right beams disappear."* Pairing two x-sorted lists cannot
## CROSS, which is why chart E2 does it — but with unequal counts the old code paired
## `leftover[0..pairs)` against the targets, so the survivors were always the LEFTMOST beams whatever
## the targets' position, and the beams already sitting on the targets were the ones retired.
##
## ⚠ **A CONTIGUOUS WINDOW, NOT A NEAREST-EACH MATCH.** Picking each target's nearest source
## independently re-introduces crossings the moment two targets want the same neighbourhood. A window
## keeps both lists in order, so pairing inside it still inverts nothing — the choice is only WHICH
## run, and the cheapest run by total travel is the one that leaves the beams closest to their work.
## ⚠ Pure arithmetic over x, so it is headless-testable — which is the point of it living here rather
## than inside either caller's frame loop.
static func nearest_window(sources: PackedFloat32Array, targets: PackedFloat32Array) -> int:
	var n := targets.size()
	if n <= 0 or sources.size() <= n: return 0
	var best := 0
	var best_cost := INF
	for start : int in range(sources.size() - n + 1):
		var cost := 0.0
		for i : int in n: cost += absf(sources[start + i] - targets[i])
		if cost < best_cost:
			best_cost = cost
			best = start
	return best

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
