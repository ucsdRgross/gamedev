extends TestSuite
# res://Tests/Wall/test_wall_packer.gd
# ==============================================================================
# WALL PACKER (S4): WallPacker + PictureRect -- layout + unlocked ids + window aspect -> rects.
# PLAN.md §1.3 AS AMENDED BY GAP-009 (rings rejected -- continuous angular placement) AND GAP-010
# (authored angles are STARTING positions; a partial unlock rebalances to reduce lopsidedness).
# TEST_PLAN.md §1, P1, P5-P12 as written, P2'/P3' replacing the old ring-based P2/P3 per the S4
# brief, P13 added for the S4-fix (home_id takes the centre, Q9=a). P4' REWRITTEN under GAP-010 --
# it used to pin authored-angle preservation under partial unlock (Q13=b/G4, now withdrawn); it now
# pins the opposite: that a partial unlock rebalances into a measurably more even arrangement.
#
# Pure logic, no scene, no engine singletons (Q197=a) -- every fixture below builds its own
# PictureEntry/WallLayout in memory rather than loading a .tres, same idiom as test_wall_focus.gd's
# bare FocusStack.new().
#
# CATEGORY MAP: every row here is BEHAVIOR -- the packing CONTRACT a player's wall relies on
# (determinism, no overlap, authored angles, the frame-edge gap), not an internal storage pin.
# ==============================================================================

func suite_name() -> String:
	return "WALL PACKER"

func _ready() -> void:
	TestLog.line("============ WALL PACKER TEST PASS ============")
	behavior_section("PACKING CONTRACT")
	test_packing_is_deterministic()
	test_minimal_radius_is_shared_and_shrinks_with_size()
	test_oversized_picture_stops_further_out()
	test_rebalancing_reduces_lopsidedness_full_and_partial()
	test_locked_pictures_produce_no_rect()
	test_gap_measured_between_frame_outer_edges()
	test_ellipse_aspect_follows_window_clamped()
	test_picture_aspect_follows_window()
	test_keep_aspect_survives_wide_window()
	test_no_two_rects_overlap()
	test_one_picture_wall()
	test_floor_and_range()
	test_home_id_takes_the_centre()
	finish()

# ------------------------------------------------------------------ fixtures

## One authored PictureEntry. `slot_deg` is GAP-009's authored angle in degrees.
func _entry(id: StringName, slot_deg: int, size_multiplier: float = 1.0,
		frame_px: Vector4 = Vector4(24, 24, 24, 24), keep_aspect: bool = false,
		design_size: Vector2i = Vector2i(1152, 648)) -> PictureEntry:
	var e := PictureEntry.new()
	e.id = id
	e.slot = slot_deg
	e.size_multiplier = size_multiplier
	e.frame_px = frame_px
	e.keep_aspect = keep_aspect
	e.design_size = design_size
	return e

## Square, keep_aspect entry for the radius/angle tests (P2'/P3'/P4') -- isolates rule 3 (radius)
## and rule 4 (angle) from rule 1 (ellipse) and rule 2 (picture-aspect stretch), which are
## covered on their own by P7/P8/P9. Not a plan gap: a test isolating one rule at a time is
## ordinary fixture design, not an invented behaviour.
func _radial_entry(id: StringName, angle_deg: int, size_multiplier: float = 1.0) -> PictureEntry:
	return _entry(id, angle_deg, size_multiplier, Vector4(20, 20, 20, 20), true, Vector2i(200, 200))

func _layout(pictures: Array[PictureEntry], gap_px: float = 24.0, aspect_min: float = 1.2,
		aspect_max: float = 2.6) -> WallLayout:
	var l := WallLayout.new()
	l.pictures = pictures
	l.gap_px = gap_px
	l.ellipse_aspect_min = aspect_min
	l.ellipse_aspect_max = aspect_max
	return l

func _ids(entries: Array[PictureEntry]) -> Array[StringName]:
	var out : Array[StringName] = []
	for e : PictureEntry in entries: out.append(e.id)
	return out

func _by_id(rects: Array[PictureRect]) -> Dictionary[StringName, PictureRect]:
	var out : Dictionary[StringName, PictureRect] = {}
	for r : PictureRect in rects: out[r.id] = r
	return out

func _radii_by_id(rects: Array[PictureRect]) -> Dictionary[StringName, float]:
	var out : Dictionary[StringName, float] = {}
	for r : PictureRect in rects: out[r.id] = r.centre.length()
	return out

## True if any two returned rects' FRAME OUTER rects intersect (touching does not count -- rule 6
## is about overlap, not about maintaining gap_px, which is the stronger thing rule 3 already
## enforces during the search).
func _has_any_overlap(rects: Array[PictureRect]) -> bool:
	for i : int in rects.size():
		for j : int in range(i + 1, rects.size()):
			var ri : PictureRect = rects[i]
			var rj : PictureRect = rects[j]
			if WallPacker.frame_outer_rect(ri).intersects(WallPacker.frame_outer_rect(rj)):
				return true
	return false

# ------------------------------------------------------------------ P1

## P1 (G-chart, Q18=a): packing is deterministic -- the same inputs, packed twice, agree on every
## rect field.
func test_packing_is_deterministic() -> void:
	var pics : Array[PictureEntry] = [
		_entry(&"a", 0), _entry(&"b", 90, 1.4), _entry(&"c", 200, 0.7, Vector4(8, 8, 40, 8)),
	]
	var layout := _layout(pics)
	var unlocked := _ids(pics)
	var first := WallPacker.pack(layout, unlocked, 1.6)
	var second := WallPacker.pack(layout, unlocked, 1.6)
	check(first.size() == second.size(), "two packs of the same inputs return the same count",
			"%d vs %d" % [first.size(), second.size()])
	for i : int in mini(first.size(), second.size()):
		var a : PictureRect = first[i]
		var b : PictureRect = second[i]
		check(a.id == b.id and a.centre.is_equal_approx(b.centre)
				and a.size.is_equal_approx(b.size) and a.frame_px == b.frame_px,
				"rect %d is identical across two packs of identical inputs" % i,
				"%s vs %s" % [a.centre, b.centre])

# ------------------------------------------------------------------ P2' / P3' (GAP-009 replacements)

## P2' (replaces the ring-based P2): the minimal radius is COMPUTED per picture and MINIMISED, not
## authored or banded. Three identical pictures 120 degrees apart, placed slot-ascending: the
## FIRST placed (&"a") has nothing yet to clear, so its minimal radius is 0 by rule 3 itself --
## the same "collides with nothing -> centred" fact P11 pins for a lone picture, just observed
## here on the first of several. The two pictures placed AFTER it (&"b", &"c") both negotiate
## against that same central obstacle at the same angular offset (120 degrees either way) and
## converge on the SAME nonzero radius by symmetry -- see ASSUMPTIONS.md for why "all three" in
## the S4 brief's wording cannot include the first-placed one under a sequential packer, and why
## that is the algorithm working as specified rather than a bug.
## Shrinking the LAST-PLACED picture (slot order) strictly shrinks only its own radius -- the
## earlier two were already placed before it (and its new size) existed, so a sequential packer
## structurally cannot let them see it.
func test_minimal_radius_is_shared_and_shrinks_with_size() -> void:
	var base : Array[PictureEntry] = [
		_radial_entry(&"a", 0), _radial_entry(&"b", 120), _radial_entry(&"c", 240),
	]
	var layout := _layout(base, 24.0, 1.0, 1.0)
	var rects := WallPacker.pack(layout, _ids(base), 1.0)
	check(rects.size() == 3, "all three pictures produced a rect", str(rects.size()))
	var r := _radii_by_id(rects)
	check(is_equal_approx(r[&"a"], 0.0),
			"the first-placed picture collides with nothing and sits at radius 0 (same rule P11 "
			+ "pins for a lone picture)", "a=%.3f" % r[&"a"])
	check(is_equal_approx(r[&"b"], r[&"c"]),
			"the two pictures placed after it, both 120 degrees from it, converge on the same radius",
			"b=%.3f c=%.3f" % [r[&"b"], r[&"c"]])
	check(r[&"b"] > 0.01, "that shared radius is genuinely nonzero -- they DO negotiate", "%.3f"
			% r[&"b"])

	var shrunk : Array[PictureEntry] = [
		_radial_entry(&"a", 0), _radial_entry(&"b", 120), _radial_entry(&"c", 240, 0.4),
	]
	var shrunk_layout := _layout(shrunk, 24.0, 1.0, 1.0)
	var shrunk_rects := WallPacker.pack(shrunk_layout, _ids(shrunk), 1.0)
	var sr := _radii_by_id(shrunk_rects)
	check(sr[&"c"] < r[&"c"], "shrinking c's size_multiplier strictly decreases c's own radius",
			"%.3f -> %.3f" % [r[&"c"], sr[&"c"]])
	check(is_equal_approx(sr[&"a"], r[&"a"]) and is_equal_approx(sr[&"b"], r[&"b"]),
			"a and b are unaffected -- both were already placed before c (and its new size) existed",
			"a %.3f->%.3f  b %.3f->%.3f" % [r[&"a"], sr[&"a"], r[&"b"], sr[&"b"]])

## P3' (replaces the ring-based P3): overflow is EMERGENT, not a ring/band. An oversized picture,
## placed LAST in slot order (same reasoning as P2'), stops further out than the others, and its
## own excess radius never leaks backward onto pictures already placed -- checked against P2's
## own baseline (same fixture, ordinary-sized &"c"), not against each other: &"a" and &"b" were
## never equal to EACH OTHER even at ordinary size (&"a" is first-placed and trivially 0, see
## P2'), so the property this row actually proves is "unchanged by c", not "equal to each other".
func test_oversized_picture_stops_further_out() -> void:
	var baseline_pics : Array[PictureEntry] = [
		_radial_entry(&"a", 0), _radial_entry(&"b", 120), _radial_entry(&"c", 240),
	]
	var baseline_layout := _layout(baseline_pics, 24.0, 1.0, 1.0)
	var baseline := _radii_by_id(WallPacker.pack(baseline_layout, _ids(baseline_pics), 1.0))

	var pics : Array[PictureEntry] = [
		_radial_entry(&"a", 0), _radial_entry(&"b", 120), _radial_entry(&"c", 240, 2.5),
	]
	var layout := _layout(pics, 24.0, 1.0, 1.0)
	var rects := WallPacker.pack(layout, _ids(pics), 1.0)
	check(rects.size() == 3, "all three pictures produced a rect", str(rects.size()))
	var r := _radii_by_id(rects)
	check(r[&"c"] > baseline[&"c"] + 0.01,
			"the oversized picture's radius is strictly greater than its own ordinary-size baseline",
			"oversized=%.3f baseline=%.3f" % [r[&"c"], baseline[&"c"]])
	check(is_equal_approx(r[&"a"], baseline[&"a"]) and is_equal_approx(r[&"b"], baseline[&"b"]),
			"the two ordinary pictures are unaffected by the oversized one placed after them -- "
			+ "both match their own ordinary-size baseline",
			"a %.3f (baseline %.3f)  b %.3f (baseline %.3f)"
					% [r[&"a"], baseline[&"a"], r[&"b"], baseline[&"b"]])

## P4' (REWRITTEN AGAIN under GAP-010's amendment -- rebalancing is now UNCONDITIONAL, "walls
## should always rebalance to deal with switching between landscape and portrait modes"). The
## previous version of this row asserted rebalancing ONLY under partial unlock and asserted the
## OPPOSITE for full unlock (angles preserved verbatim); that full-unlock half is now wrong by
## construction -- the snapshot showed a fully-unlocked wall can still read as visibly lopsided
## under authored angles alone. This row now asserts balance for BOTH: a clustered FULL set and a
## clustered PARTIAL set.
##
## `home` is an always-unlocked picture (not one of the ring pictures, any angle -- Q9=a means its
## own angle is moot, it is always centred) so every ring picture negotiates a genuinely nonzero
## radius against it, the same way P2' isolates rule 3 -- without it, whichever ring picture sorts
## first would itself land at radius 0 (rule 3, "nothing yet to clear") and have no well-defined
## `.angle()`, which would make an angle-based imbalance measurement meaningless for that picture.
##
## Imbalance measure (concrete and defensible): the spread between the largest and smallest of the
## consecutive angular gaps around the ring, asserted to collapse to near-zero (evenly spread) in
## both cases; at least one ring picture is also asserted to have moved off its literal authored
## angle, as concrete proof rebalancing actually happened rather than a coincidental average.
func test_rebalancing_reduces_lopsidedness_full_and_partial() -> void:
	_assert_rebalanced(
			"FULL unlock, all 6 ring pictures CLUSTERED into two groups (0/10/20 and 200/210/220, "
			+ "not evenly spread -- the exact shape GAP-010's amendment exists to fix)",
			[0, 10, 20, 200, 210, 220], [&"p0", &"p1", &"p2", &"p3", &"p4", &"p5"], &"p1", 10.0)
	_assert_rebalanced(
			"PARTIAL unlock, 3 of 6 ring pictures (p0/p1/p3 of an authored 0/60/120/180/240/300 "
			+ "ring, at 0/60/180 -- NOT an even 3-way spread, which would be 0/120/240)",
			[0, 60, 120, 180, 240, 300], [&"p0", &"p1", &"p3"], &"p1", 60.0)

## Shared body for both P4' cases: an authored 6-picture ring (angles `all_angles`) plus `home`,
## unlock only `unlocked_ring_ids`, pack, and assert the resolved angles of the UNLOCKED ring
## pictures are evenly spaced (max-min gap within 1 degree) and that `moved_id` (authored at
## `moved_from_deg`) is no longer at that literal angle.
func _assert_rebalanced(label: String, all_angles: Array[int], unlocked_ring_ids: Array[StringName],
		moved_id: StringName, moved_from_deg: float) -> void:
	var all_pics : Array[PictureEntry] = []
	for i : int in all_angles.size():
		all_pics.append(_radial_entry(StringName("p%d" % i), all_angles[i]))
	all_pics.append(_radial_entry(&"home", 0))
	var layout := _layout(all_pics, 24.0, 1.0, 1.0)
	layout.home_id = &"home"
	var unlocked : Array[StringName] = [&"home"]
	unlocked.append_array(unlocked_ring_ids)
	var rects := WallPacker.pack(layout, unlocked, 1.0)
	check(rects.size() == unlocked.size(),
			"%s: home plus every unlocked ring picture produced a rect" % label,
			"%d of %d" % [rects.size(), unlocked.size()])
	var by_id := _by_id(rects)
	check(by_id[&"home"].centre.is_equal_approx(Vector2.ZERO),
			"%s: home is centred as always (Q9=a)" % label, str(by_id[&"home"].centre))

	var ring_angles : Array[float] = []
	for id : StringName in unlocked_ring_ids:
		ring_angles.append(wrapf(rad_to_deg(by_id[id].centre.angle()), 0.0, 360.0))
	ring_angles.sort()
	var gaps : Array[float] = []
	for i : int in ring_angles.size():
		var next : float = ring_angles[(i + 1) % ring_angles.size()]
		var gap : float = next - ring_angles[i]
		if gap <= 0.0: gap += 360.0
		gaps.append(gap)
	var max_gap : float = gaps.max()
	var min_gap : float = gaps.min()
	check(max_gap - min_gap < 1.0,
			"%s: the unlocked ring pictures are evenly spaced (gaps within 1 degree of each other)"
			% label, "gaps=%s" % [gaps])

	var moved_angle : float = wrapf(rad_to_deg(by_id[moved_id].centre.angle()), 0.0, 360.0)
	check(not is_equal_approx(moved_angle, moved_from_deg),
			"%s: %s moved off its literal authored angle (%.0f deg) -- concrete proof rebalancing "
			% [label, moved_id, moved_from_deg] + "happened, not just a coincidental average",
			"%.3f deg" % moved_angle)

# ------------------------------------------------------------------ P5-P12 (stand as written)

## P5 (Q158=a): locked ids are absent entirely, never a placeholder rect.
func test_locked_pictures_produce_no_rect() -> void:
	var pics : Array[PictureEntry] = [
		_entry(&"a", 0), _entry(&"b", 90), _entry(&"c", 180), _entry(&"d", 270),
	]
	var layout := _layout(pics)
	var unlocked : Array[StringName] = [&"a", &"c"]
	var rects := WallPacker.pack(layout, unlocked, 1.6)
	check(rects.size() == 2, "only the 2 unlocked pictures produced a rect", str(rects.size()))
	var ids : Array[StringName] = []
	for r : PictureRect in rects: ids.append(r.id)
	check(ids == ([&"a", &"c"] as Array[StringName]),
			"the returned ids are exactly the unlocked set", str(ids))

## P6 (G5, Q14=a, Q36): the gap is measured between FRAME OUTER edges, never picture edges. Two
## pictures at DIFFERENT uniform frame thicknesses (8 px vs 48 px) both end up exactly gap_px (24)
## apart at the FRAME -- which forces a different centre-to-centre distance between the two runs,
## proof the measurement point is the frame's outer edge and not the picture rect or the centres.
func test_gap_measured_between_frame_outer_edges() -> void:
	var thin_radius := _second_picture_radius(Vector4(8, 8, 8, 8))
	var thick_radius := _second_picture_radius(Vector4(48, 48, 48, 48))
	check(thick_radius > thin_radius, "a thicker frame pushes the second picture further out",
			"thin=%.3f thick=%.3f" % [thin_radius, thick_radius])

## Packs picture &"a" (slot 0, radius 0, sits at the origin) then &"b" (slot 90) with the given
## uniform frame thickness on both, asserts b's actual frame-to-frame clearance from a is exactly
## gap_px regardless of thickness, and returns b's centre distance (radius) for the caller to
## compare across two thicknesses.
func _second_picture_radius(frame_px: Vector4) -> float:
	var pics : Array[PictureEntry] = [_entry(&"a", 0, 1.0, frame_px), _entry(&"b", 90, 1.0, frame_px)]
	var layout := _layout(pics, 24.0, 1.0, 1.0)
	var rects := WallPacker.pack(layout, _ids(pics), 1.0)
	var by_id := _by_id(rects)
	var a_frame := WallPacker.frame_outer_rect(by_id[&"a"])
	var b_frame := WallPacker.frame_outer_rect(by_id[&"b"])
	var dx := maxf(maxf(a_frame.position.x - b_frame.end.x, b_frame.position.x - a_frame.end.x), 0.0)
	var dy := maxf(maxf(a_frame.position.y - b_frame.end.y, b_frame.position.y - a_frame.end.y), 0.0)
	var clearance := Vector2(dx, dy).length()
	check(is_equal_approx(clearance, 24.0),
			"b's frame clears a's frame by exactly gap_px (24), frame_px=%s" % frame_px,
			"clearance=%.3f" % clearance)
	return by_id[&"b"].centre.length()

## P7 (G1, Q10=c): the ellipse aspect is clamp(window_aspect, ellipse_aspect_min, ellipse_aspect_max).
## Picture &"b" sits at slot 45 -- at 45 degrees WallPacker's anisotropic ray direction reduces to
## direction.x / direction.y == the resolved aspect EXACTLY (ASSUMPTIONS.md), so &"b"'s centre
## ratio reads the resolved aspect straight off the packed geometry. `&"a"` is HOME (GAP-010
## amended: rebalancing is now unconditional, and a ring of more than one entry redistributes --
## making &"a" home leaves &"b" the ONLY ring entry, whose resolved angle is always its own
## literal `slot` regardless (a ring of size 1 is its own anchor, step 360/1), so this row keeps
## testing rule 1 in isolation from rule 3a rather than becoming a rebalancing test by accident).
func test_ellipse_aspect_follows_window_clamped() -> void:
	var pics : Array[PictureEntry] = [_entry(&"a", 0), _entry(&"b", 45)]
	var layout := _layout(pics, 24.0, 1.2, 2.6)
	layout.home_id = &"a"
	var cases : Array[Vector2] = [Vector2(1.0, 1.2), Vector2(1.78, 1.78), Vector2(5.0, 2.6)]
	for c : Vector2 in cases:
		var window_aspect := c.x
		var expected := c.y
		var rects := WallPacker.pack(layout, _ids(pics), window_aspect)
		var by_id := _by_id(rects)
		var b : PictureRect = by_id[&"b"]
		var resolved := b.centre.x / b.centre.y
		check(is_equal_approx(resolved, expected),
				"window aspect %.2f clamps to ellipse aspect %.2f" % [window_aspect, expected],
				"resolved %.4f" % resolved)

## P8 (G7, Q22=b): a picture's own aspect follows the RAW window aspect (never the clamped ellipse
## aspect), unless keep_aspect.
func test_picture_aspect_follows_window() -> void:
	var pics : Array[PictureEntry] = [_entry(&"a", 0, 1.0, Vector4(24, 24, 24, 24), false)]
	var layout := _layout(pics)
	var rects := WallPacker.pack(layout, _ids(pics), 2.33)
	check(rects.size() == 1, "the one picture produced a rect", str(rects.size()))
	var size : Vector2 = rects[0].size
	check(is_equal_approx(size.x / size.y, 2.33),
			"the picture's rect aspect follows the window aspect exactly",
			"%.4f" % (size.x / size.y))

## P9 (H2, Q32=b): keep_aspect survives a wide window -- the picture's own authored aspect is
## kept untouched, the window aspect never reaches it.
func test_keep_aspect_survives_wide_window() -> void:
	var pics : Array[PictureEntry] = [
		_entry(&"map", 0, 1.0, Vector4(24, 24, 24, 24), true, Vector2i(400, 400)),
	]
	var layout := _layout(pics)
	var rects := WallPacker.pack(layout, _ids(pics), 2.33)
	check(rects.size() == 1, "the one picture produced a rect", str(rects.size()))
	var size : Vector2 = rects[0].size
	check(is_equal_approx(size.x, size.y),
			"a keep_aspect picture stays square at a wide window aspect",
			"%.1f x %.1f" % [size.x, size.y])
	check(is_equal_approx(size.x, 400.0), "its size is untouched by the window aspect",
			"%.1f" % size.x)

## P10 -- THE LOAD-BEARING ROW: no two FRAME rects ever overlap, at any of the four window aspects.
func test_no_two_rects_overlap() -> void:
	var pics : Array[PictureEntry] = [
		_entry(&"a", 0), _entry(&"b", 60, 1.3), _entry(&"c", 130, 0.8, Vector4(8, 8, 40, 8)),
		_entry(&"d", 190), _entry(&"e", 250, 1.6), _entry(&"f", 310, 0.6),
	]
	var layout := _layout(pics)
	var unlocked := _ids(pics)
	for window_aspect : float in [1.33, 1.78, 2.33, 3.55]:
		var rects := WallPacker.pack(layout, unlocked, window_aspect)
		check(rects.size() == pics.size(),
				"every picture produced a rect at aspect %.2f" % window_aspect, str(rects.size()))
		check(not _has_any_overlap(rects), "no two frame rects overlap at window aspect %.2f"
				% window_aspect)

## P11 (Q19=b): a single unlocked picture collides with nothing, so its minimal radius is 0 --
## centred, falling out of rule 3 for free (GAP-009).
func test_one_picture_wall() -> void:
	var pics : Array[PictureEntry] = [_entry(&"only", 137)]
	var layout := _layout(pics)
	var rects := WallPacker.pack(layout, _ids(pics), 1.6)
	check(rects.size() == 1, "exactly one rect", str(rects.size()))
	check(rects[0].centre.is_equal_approx(Vector2.ZERO), "the sole picture is centred",
			str(rects[0].centre))

## P12 (G13, Q23, Q24=b): the floor and the range -- 1280x720 and 32:9 both pack without error and
## without overlap.
func test_floor_and_range() -> void:
	var pics : Array[PictureEntry] = [
		_entry(&"a", 0), _entry(&"b", 60, 1.3), _entry(&"c", 130, 0.8, Vector4(8, 8, 40, 8)),
		_entry(&"d", 190), _entry(&"e", 250, 1.6), _entry(&"f", 310, 0.6),
	]
	var layout := _layout(pics)
	var unlocked := _ids(pics)
	for window_aspect : float in [1280.0 / 720.0, 32.0 / 9.0]:
		var rects := WallPacker.pack(layout, unlocked, window_aspect)
		check(rects.size() == pics.size(),
				"no error at window aspect %.4f -- every picture produced a rect" % window_aspect,
				str(rects.size()))
		check(not _has_any_overlap(rects), "no overlap at window aspect %.4f" % window_aspect)

## P13 (S4-fix, Q9=a, GAP-009): `layout.home_id` takes the centre regardless of slot order. Home
## is authored with a slot angle that does NOT sort first -- if home_id were not special-cased,
## the LOWEST-slot picture would be the one placed (and centred) first instead.
func test_home_id_takes_the_centre() -> void:
	var pics : Array[PictureEntry] = [
		_radial_entry(&"low_slot", 10), _radial_entry(&"home", 200), _radial_entry(&"high_slot", 300),
	]
	var layout := _layout(pics, 24.0, 1.0, 1.0)
	layout.home_id = &"home"
	var rects := WallPacker.pack(layout, _ids(pics), 1.0)
	check(rects.size() == 3, "all three pictures produced a rect", str(rects.size()))
	var by_id := _by_id(rects)
	check(by_id[&"home"].centre.is_equal_approx(Vector2.ZERO),
			"the home picture sits at the centre (radius 0) despite not having the lowest slot",
			str(by_id[&"home"].centre))
	check(not by_id[&"low_slot"].centre.is_equal_approx(Vector2.ZERO),
			"the lowest-slot picture is NOT centred -- home_id displaced it from going first",
			str(by_id[&"low_slot"].centre))
