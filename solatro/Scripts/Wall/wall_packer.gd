class_name WallPacker
extends RefCounted
## The pure packer: layout + unlocked ids + window aspect -> rects (PLAN.md §1.3, AS AMENDED BY
## GAP-009 -- rings are rejected; see ASSUMPTIONS.md for the placement model and the two numeric
## choices GAP-009 left to this step). Deterministic (Q18=a). No randomness, no node access, no
## engine singletons -- so it is testable headless (Q197=a).

## Rules, in GAP-009's order:
##  1. Ellipse aspect = clamp(window_aspect, layout.ellipse_aspect_min, layout.ellipse_aspect_max).
##  2. Each picture's base size = design_size * size_multiplier, stretched to the RAW window aspect
##     unless keep_aspect (Q22=b, Q32=b) -- never the clamped ellipse aspect from rule 1.
##  3. Each picture sits at the SMALLEST radius along its authored angle (slot, in degrees) at
##     which its FRAME OUTER RECT clears every already-placed frame outer rect by gap_px. Overflow
##     is emergent: there is no ring, no capacity, no band.
##  4. Placement order is `layout.home_id` FIRST (Q9=a -- home is always the centre; falls back to
##     plain slot ascending if home_id is locked/absent from this pack, never centring a picture
##     that produced no rect), then every other picture slot ascending -- fixed and deterministic,
##     since greedy packing is order-dependent (Q18=a).
##  5. Locked ids (absent from `unlocked`) produce no rect at all (Q158=a).
##  6. Assert no two rects overlap -- push_error and return the un-overlapped prefix.
static func pack(layout: WallLayout, unlocked: Array[StringName],
		window_aspect: float) -> Array[PictureRect]:
	var aspect := clampf(window_aspect, layout.ellipse_aspect_min, layout.ellipse_aspect_max)
	var entries : Array[PictureEntry] = []
	for entry : PictureEntry in layout.pictures:
		if entry.id in unlocked: entries.append(entry)
	entries.sort_custom(func(a: PictureEntry, b: PictureEntry) -> bool: return a.slot < b.slot)
	# Q9=a: the home picture takes the centre. Ring 0 (deleted, GAP-009) used to document this as
	# "the home ring" -- home was always the innermost thing, so it is placed FIRST, ahead of slot
	# order, and gets radius 0 the same way any first-placed picture does (rule 3: nothing yet to
	# clear). No-op if home_id is locked/absent from this pack -- falls back to slot ascending.
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
		var unit_dir := _direction(entry.slot, aspect)
		var radius := _find_radius(unit_dir, size, entry.frame_px, placed_frames, layout.gap_px)
		var centre := unit_dir * radius
		var frame_rect := _outer_rect(centre, size, entry.frame_px)
		var overlaps_existing := false
		for other : Rect2 in placed_frames:
			if frame_rect.intersects(other): overlaps_existing = true
		if overlaps_existing:
			push_error("WallPacker.pack: %s's frame overlaps an already-placed frame -- "
					% entry.id + "returning the un-overlapped prefix (rule 6)")
			return out
		placed_frames.append(frame_rect)
		out.append(PictureRect.new(entry.id, centre, size, entry.frame_px))
	return out

## Frame OUTER rect for a packed result -- the same rect pack() itself measures gap_px against
## (rule 3) and checks for overlap (rule 6). Exposed so callers (S10's WallPicture, the test
## suite's P10/P12) never duplicate this math.
static func frame_outer_rect(rect: PictureRect) -> Rect2:
	return _outer_rect(rect.centre, rect.size, rect.frame_px)

## Rule 2: design_size * size_multiplier, then stretched to the window's raw aspect by holding
## the HEIGHT fixed and deriving the width -- the same "height is the anchor, width follows"
## convention `wall_design_height` documents on PlayerSettings. `keep_aspect` skips the stretch
## entirely.
static func _picture_size(entry: PictureEntry, window_aspect: float) -> Vector2:
	var base := Vector2(entry.design_size) * entry.size_multiplier
	if entry.keep_aspect: return base
	return Vector2(base.y * window_aspect, base.y)

## Rule 1's anisotropic scale, applied to the RAY a picture's radius search travels along, not as
## a post-hoc stretch of finished positions -- baking it into the direction is what lets rule 3's
## gap_px clearance be checked in real final coordinates, which is what keeps rule 6 (no overlap)
## true by construction rather than by a second pass (see ASSUMPTIONS.md, GAP-009).
static func _direction(slot_degrees: int, aspect: float) -> Vector2:
	var rad := deg_to_rad(float(slot_degrees))
	var raw := Vector2(cos(rad) * aspect, sin(rad))
	if raw.length_squared() < 0.0000001: return Vector2.RIGHT
	return raw.normalized()

## The picture rect (centred on `centre`, sized `size`) grown per side by `frame_px` (L, T, R, B)
## -- asymmetric on purpose, since a frame's four sides can differ (Q36, Q37=a).
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

static func _clears_all(rect: Rect2, placed: Array[Rect2], gap_px: float) -> bool:
	for other : Rect2 in placed:
		if _clearance(rect, other) < gap_px - _EPS: return false
	return true

## Feasibility slack for the bisection below. Small enough that the converged radius's true
## clearance lands well inside is_equal_approx's tolerance of gap_px -- measured: 0.001 here left
## the returned radius up to 0.001 short of gap_px, which failed is_equal_approx(clearance, gap_px)
## in TestWallPacker's P6 (23.999 vs 24.0).
const _EPS := 0.000001
const _BISECT_ITERATIONS := 48

## "Spawns far out and is pulled inward until it collides" (GAP-009): expand outward until a
## radius clears everything, then bisect down to the smallest one that still does. Deterministic,
## no randomness -- Q18=a and Q197=a both depend on that.
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
