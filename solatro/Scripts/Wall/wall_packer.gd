class_name WallPacker
extends RefCounted
## The pure packer: layout + unlocked ids + window aspect -> rects. Deterministic, and free of
## node access and engine singletons, so it runs headless.

## Packing rules:
##  1. Ellipse aspect = clamp(window_aspect, layout.ellipse_aspect_min, layout.ellipse_aspect_max).
##  2. Each picture's base size = design_size * size_multiplier, stretched to the RAW window
##     aspect unless `keep_aspect` — never the clamped ellipse aspect from rule 1.
##  3. Each picture sits at the SMALLEST radius along its resolved angle at which its FRAME OUTER
##     RECT clears every already-placed frame outer rect by gap_px. Overflow is emergent: there is
##     no ring, no capacity, no band.
##  3a. Angles are always rebalanced, so a wall stays even when the window switches between
##     landscape and portrait — see `_rebalanced_angles()`. `slot` is therefore a placement-ORDER
##     key whose numeric value never survives into the resolved angle. A pure function of the
##     unlocked SET, never of arrival order or Dictionary iteration.
##  4. Placement order is `layout.home_id` first — home takes the centre — then every other
##     picture by ascending `slot`. Fixed, because greedy packing is order-dependent. Independent
##     of rule 3a's angle resolution.
##  5. Locked ids produce no rect at all.
##  6. Assert no two rects overlap: push_error and return the un-overlapped prefix.
static func pack(layout: WallLayout, unlocked: Array[StringName],
		window_aspect: float) -> Array[PictureRect]:
	var aspect := clampf(window_aspect, layout.ellipse_aspect_min, layout.ellipse_aspect_max)
	var entries : Array[PictureEntry] = []
	for entry : PictureEntry in layout.pictures:
		if entry.id in unlocked: entries.append(entry)
	# Rule 3a — resolved BEFORE the home-first reorder below; placement order is orthogonal to
	# angle resolution.
	var resolved_angles := _rebalanced_angles(entries, layout.home_id)
	entries.sort_custom(func(a: PictureEntry, b: PictureEntry) -> bool: return a.slot < b.slot)
	# Rule 4: home takes the centre, so it is placed FIRST and lands at radius 0 the way any
	# first-placed picture does (rule 3 has nothing to clear yet). No-op when home_id is locked or
	# absent, which falls back to plain slot order.
	for i : int in entries.size():
		if entries[i].id == layout.home_id:
			var home : PictureEntry = entries[i]
			entries.remove_at(i)
			entries.insert(0, home)
			break

	var out : Array[PictureRect] = []
	var placed_frames : Array[Rect2] = []
	for entry : PictureEntry in entries:
		var size := _picture_size(entry, window_aspect)
		# home_id has no resolved angle; it is placed first and lands at radius 0 either way.
		var angle_deg : float = resolved_angles.get(entry.id, float(entry.slot))
		var unit_dir := _direction(angle_deg, aspect)
		var radius := _find_radius(unit_dir, size, entry.frame_px, placed_frames, layout.gap_px)
		var centre := unit_dir * radius
		var frame_rect := _outer_rect(centre, size, entry.frame_px)
		var overlaps_existing := false
		for other : Rect2 in placed_frames:
			if frame_rect.intersects(other): overlaps_existing = true
		if overlaps_existing:
			push_error("WallPacker.pack: %s's frame overlaps an already-placed frame -- "
					% entry.id + "returning the un-overlapped prefix")
			return out
		placed_frames.append(frame_rect)
		out.append(PictureRect.new(entry.id, centre, size, entry.frame_px))
	return out

## Frame OUTER rect for a packed result — the same rect `pack()` measures gap_px against and
## checks for overlap. Exposed so callers never duplicate this math.
static func frame_outer_rect(rect: PictureRect) -> Rect2:
	return _outer_rect(rect.centre, rect.size, rect.frame_px)

## Rule 2: design_size * size_multiplier, then stretched to the window's raw aspect by holding
## the HEIGHT fixed and deriving the width. `keep_aspect` skips the stretch entirely.
static func _picture_size(entry: PictureEntry, window_aspect: float) -> Vector2:
	var base := Vector2(entry.design_size) * entry.size_multiplier
	if entry.keep_aspect: return base
	return Vector2(base.y * window_aspect, base.y)

## Each non-home unlocked picture's ANGLE for this pack. `entries` is the unlocked, home-included
## subset.
##
## ALWAYS re-sequences the non-home survivors by ascending `slot` — never by `unlocked`'s own
## order or Dictionary iteration — and spreads them evenly around the full 360 degrees, anchored
## at the smallest-slot survivor's authored value. Unconditional, for every unlock set: authored
## angles alone leave even a fully-unlocked wall visibly lopsided. Equal gaps between consecutive
## pictures is what "balanced" means here.
##
## Keyed by picture id; `home_id` never appears — it is placed first and lands at radius 0.
static func _rebalanced_angles(entries: Array[PictureEntry],
		home_id: StringName) -> Dictionary[StringName, float]:
	var ring : Array[PictureEntry] = []
	for entry : PictureEntry in entries:
		if entry.id != home_id: ring.append(entry)
	var out : Dictionary[StringName, float] = {}
	if ring.is_empty(): return out
	ring.sort_custom(func(a: PictureEntry, b: PictureEntry) -> bool: return a.slot < b.slot)
	var anchor := float(ring[0].slot)
	var step := 360.0 / float(ring.size())
	for i : int in ring.size():
		out[ring[i].id] = anchor + step * float(i)
	return out

## Rule 1's anisotropic scale, applied to the RAY the radius search travels along rather than as
## a post-hoc stretch of finished positions. Baking it into the direction lets rule 3 check
## clearance in real final coordinates, which makes rule 6 true by construction.
static func _direction(angle_degrees: float, aspect: float) -> Vector2:
	var rad := deg_to_rad(angle_degrees)
	var raw := Vector2(cos(rad) * aspect, sin(rad))
	if raw.length_squared() < 0.0000001: return Vector2.RIGHT
	return raw.normalized()

## The picture rect grown per side by `frame_px` (L, T, R, B) — asymmetric, since a frame's four
## sides can differ.
static func _outer_rect(centre: Vector2, size: Vector2, frame_px: Vector4) -> Rect2:
	var half := size * 0.5
	var left := centre.x - half.x - frame_px.x
	var top := centre.y - half.y - frame_px.y
	var right := centre.x + half.x + frame_px.z
	var bottom := centre.y + half.y + frame_px.w
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))

## True Euclidean separation between two axis-aligned rects' nearest edges -- 0 when they touch or
## overlap, otherwise the straight-line gap between their closest corners/edges.
static func _clearance(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return Vector2(dx, dy).length()

## ⚠ The `intersects()` check is INDEPENDENT of `gap_px` and cannot be folded into the clearance
## test. `_clearance` is never negative, so at `gap_px == 0` that test reads `0 < -_EPS` — false
## for every candidate however deeply it overlaps, and every picture would "clear" at radius 0.
## Checking intersection separately rejects a real overlap at any gap, while `gap_px = 0` still
## lets frames touch (`include_borders` defaults to false).
static func _clears_all(rect: Rect2, placed: Array[Rect2], gap_px: float) -> bool:
	for other : Rect2 in placed:
		if rect.intersects(other): return false
		if _clearance(rect, other) < gap_px - _EPS: return false
	return true

## Feasibility slack for the bisection below. Must stay well under `is_equal_approx`'s tolerance:
## at 0.001 the converged radius came back up to 0.001 short of gap_px, which reads as unequal.
const _EPS := 0.000001
const _BISECT_ITERATIONS := 48

## The smallest radius along `unit_dir` that clears everything already placed: expand outward
## until some radius clears, then bisect down. Deterministic — no randomness.
static func _find_radius(unit_dir: Vector2, size: Vector2, frame_px: Vector4,
		placed: Array[Rect2], gap_px: float) -> float:
	if _clears_all(_outer_rect(Vector2.ZERO, size, frame_px), placed, gap_px):
		return 0.0
	var hi := maxf(size.x, size.y) + gap_px + 1.0
	while not _clears_all(_outer_rect(unit_dir * hi, size, frame_px), placed, gap_px):
		hi *= 2.0
	var lo := 0.0
	for _i : int in _BISECT_ITERATIONS:
		var mid := (lo + hi) * 0.5
		if _clears_all(_outer_rect(unit_dir * mid, size, frame_px), placed, gap_px):
			hi = mid
		else:
			lo = mid
	return hi
