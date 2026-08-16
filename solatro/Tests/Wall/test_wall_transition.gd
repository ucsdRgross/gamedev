extends TestSuite
# res://Tests/Wall/test_wall_transition.gd
# ==============================================================================
# WALL TRANSITION (S14-S18, phase3-close): WallTransition -- the camera tween and its phase clock.
# PLAN.md §1.10, §3 (Phase 3 acceptance gate); TEST_PLAN.md §5, T1-T13.
#
# T1/T2/T5/T9/T10 test PURE, INSTANT facts (durations, request()'s no-op/ignore bookkeeping) --
# no real waiting needed. T3/T4/T6/T7/T8/T12 sample WallTransition.sample_at() SYNCHRONOUSLY across
# a scan of elapsed values (never an `await`ed real frame) -- fast, deterministic, and immune to the
# exact trap this run has already hit twice (a sampler recording zero real frames passes silently):
# every scan asserts its own sample COUNT is nonzero before asserting anything about its contents.
# T11 mixes both: a pure sample_at() comparison for the discontinuity bound, plus a short real
# Tween (same shape as T9/T10) to prove the transition actually continues rather than restarting.
# T13 (the Phase 3 acceptance gate, PLAN.md §3) is 20 REAL, seeded-random transitions in sequence --
# real Tweens are unavoidable there (the property under test is what a whole chain of them leaves
# behind), so the seed is fixed and printed in every failure message so a red run is replayable.
# ==============================================================================

const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const WINDOW := Vector2(1280.0, 720.0)
const SCAN_STEPS := 200

func suite_name() -> String:
	return "WALL TRANSITION"

func _ready() -> void:
	TestLog.line("============ WALL TRANSITION TEST PASS ============")
	behavior_section("DURATION (T1, T2, T5)")
	test_duration_derives_from_base_delay()
	test_act_fast_forward_does_not_compress_it()
	test_travel_duration_is_distance_independent()
	behavior_section("PHASES AND FRAMING (T3, T4)")
	test_phases_overlap()
	test_zoom_out_shows_both_frames_plus_margin()
	test_zoom_out_shows_both_frames_plus_margin_asymmetric()
	behavior_section("PAUSE / UNPAUSE / INPUT-UNLOCK BOUNDARIES (T6, T7, T8)")
	test_source_pauses_when_frame_edge_enters_view()
	test_dest_unpauses_on_first_visibility()
	test_input_unlocks_before_finish_not_before_fully_in_view()
	behavior_section("REQUEST BOOKKEEPING (T9, T10)")
	await test_mid_flight_request_is_ignored()
	await test_requesting_current_picture_does_nothing()
	behavior_section("RESIZE RETARGET (T11)")
	await test_mid_flight_resize_retargets_without_a_visible_snap()
	behavior_section("REDUCED MOTION (T12)")
	test_reduced_motion_removes_all_zoom()
	behavior_section("20-TRANSITION SOAK (T13, PHASE 3 GATE)")
	await test_twenty_transition_soak_leaves_exactly_one_always_screen()
	behavior_section("SOURCE-PAUSE LATCH UNDER REAL SPARSE SAMPLING (regression, latch-fix)")
	await test_source_pauses_under_real_sparse_frame_sampling()
	finish()

# ------------------------------------------------------------------ fixtures

func _settings(base_delay: float = 1.0, transition_delay: float = 0.6) -> PlayerSettings:
	var s := PlayerSettings.new()
	s.base_delay = base_delay
	s.wall_transition_delay = transition_delay
	return s

func _rect(id: StringName, centre: Vector2, size: Vector2 = Vector2(400.0, 400.0),
		frame_px: Vector4 = Vector4(20, 20, 20, 20)) -> PictureRect:
	return PictureRect.new(id, centre, size, frame_px)

## A real WallPicture, added to the tree (so its own %Shadow/%Frame/%Screen onready vars resolve)
## but never build()'ed -- T9/T10 only exercise request()'s bookkeeping, and _apply() already
## null-checks `screen_root` (never set without build()), so an un-built picture is a safe, minimal
## fixture here.
func _wall_picture() -> WallPicture:
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	add_child(wp)
	return wp

## queue_free() is DEFERRED to the end of the current frame -- await one so it has actually
## happened before the caller moves on, rather than leaving it to whatever frame the suite exits
## on (T9/T10 are this suite's only tests that construct real nodes; a leak here is this file's
## own, not the production code's).
func _cleanup(pictures: Array) -> void:
	for wp : WallPicture in pictures:
		if is_instance_valid(wp): wp.queue_free()
	await get_tree().process_frame

## Every WallTransition.Sample for `SCAN_STEPS + 1` elapsed values evenly spread across [0, total],
## paired with the elapsed value that produced it -- the "per-frame sampling" T3/T6/T7/T8 need,
## done as a synchronous scan rather than real `await`ed frames.
func _scan(total: float, source: PictureRect, dest: PictureRect, window: Vector2,
		settings: PlayerSettings) -> Array:
	var out : Array = []
	for i : int in (SCAN_STEPS + 1):
		var elapsed := total * float(i) / float(SCAN_STEPS)
		out.append({"elapsed": elapsed,
				"sample": WallTransition.sample_at(elapsed, total, source, dest, window, settings)})
	return out

# ------------------------------------------------------------------ T1, T2, T5 (duration)

## T1 (C15, Q46=b): total duration derives from base_delay -- doubling it doubles the duration.
func test_duration_derives_from_base_delay() -> void:
	var slow := WallTransition.total_duration(_settings(1.0, 0.6))
	var fast := WallTransition.total_duration(_settings(2.0, 0.6))
	check(is_equal_approx(fast, slow * 2.0), "doubling base_delay doubles the total duration",
			"%.4f vs %.4f" % [slow, fast])

## T2 (C15, Q46=b): an act fast-forward does NOT compress the transition -- the specific trap
## Q46=(c) would have caused. Contrasted directly against Game.get_delay(), which DOES compress,
## proving WallTransition.total_duration() takes a different, uncompressed path rather than merely
## coinciding with it by accident.
func test_act_fast_forward_does_not_compress_it() -> void:
	var settings := _settings(1.0, 0.6)
	# Game extends CardEnvironment extends Node -- NOT RefCounted, so this needs an explicit free()
	# below; it is never added to a tree (queue_free's deferred path is not needed either).
	var game := Game.new()
	game.act_cancelled = true
	check(is_equal_approx(game.get_delay(), 0.0),
			"Game.get_delay() DOES compress to 0 on an act cancel -- the trap this test defends "
			+ "against, confirmed real")
	var actual := WallTransition.total_duration(settings)
	check(is_equal_approx(actual, 0.6),
			"WallTransition.total_duration() is unaffected by Game.act_cancelled -- it never reads "
			+ "Game at all", "%.4f" % actual)
	game.free()

## T5 (C10, Q50=a): travel duration is distance-independent -- an adjacent pair and an opposite
## (far) pair reach the SAME travel window length, since it derives from settings fractions alone,
## never from source/dest positions.
func test_travel_duration_is_distance_independent() -> void:
	var settings := _settings(1.0, 0.6)
	var total := WallTransition.total_duration(settings)
	var bounds := WallTransition.phase_bounds(settings)
	var travel_secs : float = (bounds["travel_end"] - bounds["travel_start"]) * total

	var adjacent := [_rect(&"a", Vector2(0, 0)), _rect(&"b", Vector2(200, 0))]
	var opposite := [_rect(&"a", Vector2(-4000, 0)), _rect(&"b", Vector2(4000, 0))]
	for pair : Array in [adjacent, opposite]:
		var source : PictureRect = pair[0]
		var dest : PictureRect = pair[1]
		# Sample right at travel_start and travel_end -- position must have fully crossed from
		# source to dest across exactly `travel_secs`, regardless of how far apart they are.
		var travel_start_elapsed : float = bounds["travel_start"] * total
		var travel_end_elapsed : float = bounds["travel_end"] * total
		var at_start := WallTransition.sample_at(travel_start_elapsed, total, source, dest, WINDOW,
				settings)
		var at_end := WallTransition.sample_at(travel_end_elapsed, total, source, dest, WINDOW,
				settings)
		check(at_start.camera_position.is_equal_approx(source.centre),
				"at travel_start the camera is still at the source", str(at_start.camera_position))
		check(at_end.camera_position.is_equal_approx(dest.centre),
				"at travel_end the camera has fully arrived at the dest", str(at_end.camera_position))
	check(travel_secs > 0.0, "the travel window itself is a fixed, positive, distance-INDEPENDENT "
			+ "duration in seconds -- the same %.4fs regardless of which pair was sampled above"
			% travel_secs)

# ------------------------------------------------------------------ T3, T4 (phases, framing)

## T3 (C7, Q47=b): phases overlap -- position starts changing (travel begins) BEFORE zoom finishes
## zooming out (reaches its widest/flattest point). Detected black-box from the scan alone: the
## first sample whose position differs from the source, versus the first sample whose zoom equals
## the scan's own observed minimum (the widest point zoom-out reaches).
func test_phases_overlap() -> void:
	var settings := _settings()
	var total := WallTransition.total_duration(settings)
	var source := _rect(&"a", Vector2(-800, 0))
	var dest := _rect(&"b", Vector2(800, 0))
	var scan := _scan(total, source, dest, WINDOW, settings)
	check(scan.size() > 0, "the scan recorded a nonzero number of samples", str(scan.size()))

	var min_zoom := INF
	for entry : Dictionary in scan:
		var sample : WallTransition.Sample = entry["sample"]
		min_zoom = minf(min_zoom, sample.camera_zoom)

	var position_start_elapsed := -1.0
	var zoom_flat_elapsed := -1.0
	for entry : Dictionary in scan:
		var sample : WallTransition.Sample = entry["sample"]
		var elapsed : float = entry["elapsed"]
		if position_start_elapsed < 0.0 and not sample.camera_position.is_equal_approx(source.centre):
			position_start_elapsed = elapsed
		if zoom_flat_elapsed < 0.0 and is_equal_approx(sample.camera_zoom, min_zoom):
			zoom_flat_elapsed = elapsed
	check(position_start_elapsed >= 0.0 and zoom_flat_elapsed >= 0.0,
			"both position-starts-changing and zoom-reaches-its-widest were observed in the scan",
			"position_start=%.4f zoom_flat=%.4f" % [position_start_elapsed, zoom_flat_elapsed])
	check(position_start_elapsed < zoom_flat_elapsed,
			"position starts changing (travel begins) BEFORE zoom finishes zooming out",
			"%.4f vs %.4f" % [position_start_elapsed, zoom_flat_elapsed])

## T4 (C8, Q48=b): the zoom-out target shows BOTH frames plus the reveal margin. Symmetric "opposite
## rings" fixture (ASSUMPTIONS.md) so the union bounding box's own centre coincides with the
## midpoint of the two picture centres -- exactly where the camera sits at the wide-zoom plateau.
func test_zoom_out_shows_both_frames_plus_margin() -> void:
	var settings := _settings()
	var total := WallTransition.total_duration(settings)
	var source := _rect(&"a", Vector2(-600, 0), Vector2(400, 400), Vector4(20, 20, 20, 20))
	var dest := _rect(&"b", Vector2(600, 0), Vector2(400, 400), Vector4(20, 20, 20, 20))
	var bounds := WallTransition.phase_bounds(settings)
	var plateau_elapsed : float = (bounds["zoom_out_end"] + bounds["zoom_in_start"]) * 0.5 * total
	var sample := WallTransition.sample_at(plateau_elapsed, total, source, dest, WINDOW, settings)

	var visible_size := WINDOW / sample.camera_zoom
	var visible := Rect2(sample.camera_position - visible_size * 0.5, visible_size)
	var source_frame := WallPacker.frame_outer_rect(source)
	var dest_frame := WallPacker.frame_outer_rect(dest)
	check(visible.encloses(source_frame), "the peak-zoom visible rect contains the SOURCE frame",
			"visible=%s source_frame=%s" % [visible, source_frame])
	check(visible.encloses(dest_frame), "the peak-zoom visible rect contains the DEST frame",
			"visible=%s dest_frame=%s" % [visible, dest_frame])
	var union := source_frame.merge(dest_frame)
	check(visible.size.x > union.size.x and visible.size.y > union.size.y,
			"the visible rect is strictly larger than the union of both frames on BOTH axes -- "
			+ "there IS a reveal margin, not just exact containment",
			"visible=%s union=%s" % [visible.size, union.size])

## T4 variant (C8, Q48=b) -- a genuinely ASYMMETRIC pair: different `size` AND different `frame_px`
## on the two pictures, so the union bounding box's true centre does NOT coincide with the
## straight-line midpoint of the two centres (the camera's own fixed position at this plateau
## instant, per Q51=a). Same property as the symmetric test above -- containment plus a strict
## margin on both axes -- proving `_wide_zoom()` accounts for the one-sided offset rather than
## assuming the union is centred where the camera sits (ASSUMPTIONS.md, the flagged limitation this
## variant closes).
func test_zoom_out_shows_both_frames_plus_margin_asymmetric() -> void:
	var settings := _settings()
	var total := WallTransition.total_duration(settings)
	var source := _rect(&"a", Vector2(-600, 0), Vector2(200, 200), Vector4(10, 10, 10, 10))
	var dest := _rect(&"b", Vector2(600, 0), Vector2(800, 400), Vector4(60, 60, 60, 60))
	var bounds := WallTransition.phase_bounds(settings)
	var plateau_elapsed : float = (bounds["zoom_out_end"] + bounds["zoom_in_start"]) * 0.5 * total
	var sample := WallTransition.sample_at(plateau_elapsed, total, source, dest, WINDOW, settings)

	var visible_size := WINDOW / sample.camera_zoom
	var visible := Rect2(sample.camera_position - visible_size * 0.5, visible_size)
	var source_frame := WallPacker.frame_outer_rect(source)
	var dest_frame := WallPacker.frame_outer_rect(dest)
	check(visible.encloses(source_frame),
			"the peak-zoom visible rect contains the SOURCE frame, the smaller/thinner-framed one",
			"visible=%s source_frame=%s" % [visible, source_frame])
	check(visible.encloses(dest_frame),
			"the peak-zoom visible rect contains the DEST frame, the larger/thicker-framed one -- "
			+ "the one whose far edge a midpoint-symmetric window would clip",
			"visible=%s dest_frame=%s" % [visible, dest_frame])
	var union := source_frame.merge(dest_frame)
	check(visible.size.x > union.size.x and visible.size.y > union.size.y,
			"the visible rect is strictly larger than the union of both frames on BOTH axes even "
			+ "though the union is off-centre from the camera",
			"visible=%s union=%s" % [visible.size, union.size])

# ------------------------------------------------------------------ T6, T7 (S15 pause boundaries)

## T6 (C9, Q72=a): the SOURCE pauses (its frame outer rect first becomes entirely visible) at some
## point strictly after the transition starts, and the sample right before that one does NOT yet
## satisfy it -- proving this is the FIRST crossing, not a stale true carried from t=0.
func test_source_pauses_when_frame_edge_enters_view() -> void:
	var settings := _settings()
	var total := WallTransition.total_duration(settings)
	var source := _rect(&"a", Vector2(-800, 0))
	var dest := _rect(&"b", Vector2(800, 0))
	var scan := _scan(total, source, dest, WINDOW, settings)
	check(scan.size() > 0, "the scan recorded a nonzero number of samples", str(scan.size()))

	var pause_index := -1
	for i : int in scan.size():
		var sample : WallTransition.Sample = scan[i]["sample"]
		if sample.source_frame_in_view:
			pause_index = i
			break
	check(pause_index > 0, "the source's frame DID enter view somewhere after t=0", str(pause_index))
	if pause_index > 0:
		var prev : WallTransition.Sample = scan[pause_index - 1]["sample"]
		check(not prev.source_frame_in_view,
				"the sample just before the detected pause moment was NOT yet in view -- this IS "
				+ "the first crossing")

## T7 (C11, Q73=c): the DESTINATION unpauses (first becomes visible AT ALL) strictly DURING the
## transition, not at the very end -- and specifically during travel, before zoom-in even starts.
func test_dest_unpauses_on_first_visibility() -> void:
	var settings := _settings()
	var total := WallTransition.total_duration(settings)
	var source := _rect(&"a", Vector2(-800, 0))
	var dest := _rect(&"b", Vector2(800, 0))
	var scan := _scan(total, source, dest, WINDOW, settings)
	check(scan.size() > 0, "the scan recorded a nonzero number of samples", str(scan.size()))
	var bounds := WallTransition.phase_bounds(settings)
	var zoom_in_start_elapsed : float = bounds["zoom_in_start"] * total

	var unpause_index := -1
	for i : int in scan.size():
		var sample : WallTransition.Sample = scan[i]["sample"]
		if sample.dest_visible:
			unpause_index = i
			break
	check(unpause_index > 0, "the destination DID become visible somewhere after t=0",
			str(unpause_index))
	var finish_index := scan.size() - 1
	check(unpause_index < finish_index, "the unpause frame is strictly before the finish frame",
			"%d vs %d" % [unpause_index, finish_index])
	if unpause_index >= 0:
		var unpause_elapsed : float = scan[unpause_index]["elapsed"]
		check(unpause_elapsed < zoom_in_start_elapsed,
				"the destination unpauses BEFORE zoom-in even starts -- early, during travel, per "
				+ "Q73=c's own note",
				"unpause=%.4f zoom_in_start=%.4f" % [unpause_elapsed, zoom_in_start_elapsed])

# ------------------------------------------------------------------ T8 (S16 input unlock)

## T8 (C13): input unlocks strictly before the finish frame, AND never earlier than the first
## frame both picture and frame are fully in view (dest_frame_in_view) -- both halves, since an
## unlock that is merely early is a bug, not a pass. Proven against the LAXER "visible at all"
## condition too: the stricter full-containment unlock cannot fire before the laxer one does.
func test_input_unlocks_before_finish_not_before_fully_in_view() -> void:
	var settings := _settings()
	var total := WallTransition.total_duration(settings)
	var source := _rect(&"a", Vector2(-800, 0))
	var dest := _rect(&"b", Vector2(800, 0))
	var scan := _scan(total, source, dest, WINDOW, settings)
	check(scan.size() > 0, "the scan recorded a nonzero number of samples", str(scan.size()))

	var unlock_index := -1
	var first_visible_index := -1
	for i : int in scan.size():
		var sample : WallTransition.Sample = scan[i]["sample"]
		if first_visible_index < 0 and sample.dest_visible:
			first_visible_index = i
		if unlock_index < 0 and sample.dest_frame_in_view:
			unlock_index = i
	var finish_index := scan.size() - 1

	check(unlock_index >= 0, "dest's frame DID become fully in view somewhere in the scan")
	check(unlock_index < finish_index, "the unlock frame is strictly BEFORE the finish frame",
			"%d vs %d" % [unlock_index, finish_index])
	check(first_visible_index >= 0 and first_visible_index <= unlock_index,
			"dest becomes merely visible no LATER than it becomes fully in view -- the stricter "
			+ "containment check cannot fire before the laxer visibility one",
			"visible=%d unlock=%d" % [first_visible_index, unlock_index])

# ------------------------------------------------------------------ T9, T10 (request bookkeeping)

## T9 (C5, Q56=b): a new destination requested mid-flight is IGNORED outright -- the in-flight
## transition keeps running toward its ORIGINAL target (b) and lands there, never on the
## mid-flight request (c). Uses a short duration so the real wait below is bounded and fast.
func test_mid_flight_request_is_ignored() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	var settings := _settings(0.05, 1.0)   # total_duration = 0.05s -- fast, bounded real wait
	var source_rect := _rect(&"a", Vector2(0, 0))
	var dest_b_rect := _rect(&"b", Vector2(400, 0))
	var dest_c_rect := _rect(&"c", Vector2(-400, 0))
	var pictures := [_wall_picture(), _wall_picture(), _wall_picture()]
	var source_wp : WallPicture = pictures[0]
	var dest_b_wp : WallPicture = pictures[1]
	var dest_c_wp : WallPicture = pictures[2]

	var transition := WallTransition.new()
	var landed_id : Array[StringName] = [&""]   # boxed -- lambdas capture locals BY VALUE
	transition.landed.connect(func(id: StringName) -> void: landed_id[0] = id)

	transition.request(camera, source_wp, source_rect, dest_b_wp, dest_b_rect, WINDOW, settings)
	check(transition.is_active, "the first request() starts a transition")
	transition.request(camera, source_wp, source_rect, dest_c_wp, dest_c_rect, WINDOW, settings)
	check(transition.is_active,
			"still active after the second request() -- it did not cancel or restart anything")

	await transition.landed
	check(landed_id[0] == &"b",
			"it lands on b, the ORIGINAL target -- c's mid-flight request was ignored, not queued "
			+ "or retargeted", str(landed_id[0]))

	camera.queue_free()
	await _cleanup(pictures)

## T10 (C3, Q55=a): requesting the picture that is ALREADY the source creates no tween at all.
func test_requesting_current_picture_does_nothing() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	var settings := _settings()
	var source_rect := _rect(&"a", Vector2(0, 0))
	var source_wp := _wall_picture()

	var transition := WallTransition.new()
	transition.request(camera, source_wp, source_rect, source_wp, source_rect, WINDOW, settings)
	check(not transition.is_active,
			"requesting the CURRENT picture creates no tween at all -- is_active stays false")

	camera.queue_free()
	await _cleanup([source_wp])

# ------------------------------------------------------------------ T11 (S17 resize retarget)

## T11 (C16, Q26=a): a mid-flight resize RETARGETS the transition to new geometry and continues --
## two halves.
## (1) Geometry continuity, via sample_at() directly (no real Tween needed, same reasoning T3/T4/
## T6-T8 give): at a FIXED elapsed instant, swapping in a modest resize's worth of new rects/window
## cannot move the camera position by more than the convex bound a lerp guarantees --
## lerp(a+da, b+db, t) - lerp(a, b, t) has magnitude <= max(|da|, |db|) for ANY t in [0, 1] -- so the
## discontinuity retarget() introduces is provably bounded by the resize's OWN geometry shift, never
## an extra snap from resetting position or elapsed time.
## (2) Continuation, via a REAL short Tween (same shape as T9/T10): request(), retarget() mid-flight,
## then await landed -- proving the SAME tween instance keeps running (never cancelled or restarted)
## and still lands on the original destination id using the retargeted geometry.
func test_mid_flight_resize_retargets_without_a_visible_snap() -> void:
	var settings := _settings(4.0, 1.0)
	var total := WallTransition.total_duration(settings)
	var halfway := total * 0.5
	var old_source_rect := _rect(&"a", Vector2(-800, 0))
	var old_dest_rect := _rect(&"b", Vector2(800, 0))
	var before := WallTransition.sample_at(halfway, total, old_source_rect, old_dest_rect, WINDOW,
			settings)

	# A modest resize-driven re-pack: both pictures' centres shift by a small, realistic amount,
	# and the window itself grows a little too -- never a wild jump.
	var new_source_rect := _rect(&"a", Vector2(-820, 20))
	var new_dest_rect := _rect(&"b", Vector2(824, -16))
	var new_window := WINDOW + Vector2(64, 36)
	var after := WallTransition.sample_at(halfway, total, new_source_rect, new_dest_rect,
			new_window, settings)

	var max_shift := maxf((new_source_rect.centre - old_source_rect.centre).length(),
			(new_dest_rect.centre - old_dest_rect.centre).length())
	var jump := before.camera_position.distance_to(after.camera_position)
	check(jump <= max_shift + 0.01,
			"the position discontinuity a geometry swap introduces is bounded by the resize's own "
			+ "shift -- a straight-line lerp of two points that each moved by at most max_shift "
			+ "cannot itself move by more than max_shift, for any travel progress",
			"jump=%.4f max_shift=%.4f" % [jump, max_shift])

	var camera := Camera2D.new()
	add_child(camera)
	var fast_settings := _settings(0.05, 1.0)   # total_duration = 0.05s -- fast, bounded real wait
	var pictures := [_wall_picture(), _wall_picture()]
	var source_wp : WallPicture = pictures[0]
	var dest_wp : WallPicture = pictures[1]
	var transition := WallTransition.new()
	var landed_id : Array[StringName] = [&""]   # boxed -- lambdas capture locals BY VALUE
	transition.landed.connect(func(id: StringName) -> void: landed_id[0] = id)

	transition.request(camera, source_wp, old_source_rect, dest_wp, old_dest_rect, WINDOW,
			fast_settings)
	check(transition.is_active, "the transition is active before the resize")
	transition.retarget(new_source_rect, new_dest_rect, new_window)
	check(transition.is_active, "retarget() mid-flight does not cancel or restart the transition")

	await transition.landed
	check(landed_id[0] == &"b",
			"it still lands on the ORIGINAL destination id after a retarget -- geometry changed, "
			+ "the target did not", str(landed_id[0]))

	camera.queue_free()
	await _cleanup(pictures)

# ------------------------------------------------------------------ T12 (S18 reduced motion)

## T12 (K8, Q172=a): with wall_reduced_motion on, camera zoom is CONSTANT across the whole scan --
## no zoom-out/zoom-in dance at all, matching S18's own done-when ("every transition is a cross-fade
## and no zoom occurs").
func test_reduced_motion_removes_all_zoom() -> void:
	var settings := _settings()
	settings.wall_reduced_motion = true
	var total := WallTransition.total_duration(settings)
	var source := _rect(&"a", Vector2(-800, 0))
	var dest := _rect(&"b", Vector2(800, 0))
	var scan := _scan(total, source, dest, WINDOW, settings)
	check(scan.size() > 0, "the scan recorded a nonzero number of samples", str(scan.size()))

	var first_sample : WallTransition.Sample = scan[0]["sample"]
	var first_zoom := first_sample.camera_zoom
	var all_constant := true
	for entry : Dictionary in scan:
		var sample : WallTransition.Sample = entry["sample"]
		if not is_equal_approx(sample.camera_zoom, first_zoom):
			all_constant = false
			break
	check(all_constant,
			"camera zoom never changes across the whole scan under reduced motion -- no zoom-out/"
			+ "zoom-in dance occurs", "first=%.4f" % first_zoom)

# ------------------------------------------------------------------ T13 (Phase 3 soak)

## Fixed and printed in every failure message below -- Q18=a binds the packer/this class to
## determinism, and an unreplayable soak that fails once and never again tells you nothing.
const _SOAK_SEED := 20260815
const _SOAK_ITERATIONS := 20

## T13 (PLAN.md §3's own Phase-3 acceptance gate, verbatim: "a scripted 20-transition soak leaves
## exactly one ALWAYS screen every time"; TEST_PLAN.md T13): 20 real transitions in a chain across
## 5 real `WallPicture`s, each with a real, throwaway `screen_root` (`PackedScene.new()`+`.pack()`
## on a bare `Node` -- the same fixture shape S12's `TestWallPause` already uses, ASSUMPTIONS.md --
## so `process_mode` is something to actually count, not a null no-op). The destination each round
## is chosen by a SEEDED `RandomNumberGenerator`.
##
## ⚠ Each round ALSO forces one extra `_apply()` call at the wide-zoom PLATEAU's own elapsed
## instant (computed from `phase_bounds()`, the same formula T4's own plateau sample uses)
## immediately after `request()`, before awaiting `landed`. Originally added because relying on the
## real Tween's own per-frame cadence to land a sample inside the source's TRANSIENT true-window
## turned out to be exactly the kind of timing-dependent flakiness this file's header already warns
## about -- measured directly: without it, `always_count` drifted to 2 and 3 across a run's 20
## rounds as individual `source_frame_in_view` checks occasionally missed every real frame the
## short Tween happened to render. The latch-fix below made the SOURCE half of that no longer
## depend on this forced sample (it is now scheduled by precomputed elapsed time, immune to
## sampling sparsity by construction) -- but the call stays anyway: it is still a genuine extra,
## deterministic sample for `dest_visible`/`dest_frame_in_view`, and a deterministic gate is right
## regardless of which specific boundary needed it.
##
## After EACH landing: count `screen_root`s at `PROCESS_MODE_ALWAYS` across ALL FIVE pictures and
## assert the count is EXACTLY 1 (never "at least"), and that the focus stack's own `can_back()`
## invariant (monotonic true once 2+ distinct pictures have been visited -- non-destructive, unlike
## `back()`/`forward()`, so it can be read every round without corrupting the ongoing history)
## still holds. A final check that the loop actually ran all 20 iterations guards against the "loop
## body never executes" shape of vacuous test this run has already hit four times in other forms.
func test_twenty_transition_soak_leaves_exactly_one_always_screen() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	var settings := _settings(0.1, 1.0)   # total_duration = 0.1s per transition -- real, but bounded
	var ids : Array[StringName] = [&"a", &"b", &"c", &"d", &"e"]
	var rects : Dictionary[StringName, PictureRect] = {}
	var pictures : Dictionary[StringName, WallPicture] = {}
	var picture_list : Array[WallPicture] = []
	var angle_step := TAU / float(ids.size())
	for i : int in ids.size():
		var id : StringName = ids[i]
		rects[id] = _rect(id, Vector2(600, 0).rotated(angle_step * float(i)))
		var wp := _wall_picture()
		var packed := PackedScene.new()
		# pack() COPIES this template's structure; the template Node itself is NOT RefCounted and is
		# never added to a tree, so it needs an explicit .free() -- the exact trap ASSUMPTIONS.md's
		# T2 entry already documents for Game.new() in this same file.
		var template := Node.new()
		packed.pack(template)
		template.free()
		wp.screen_root = packed.instantiate()
		wp.screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
		pictures[id] = wp
		picture_list.append(wp)
	check(picture_list.size() == ids.size(),
			"all %d real pictures were constructed for the soak before it starts" % ids.size(),
			str(picture_list.size()))

	var rng := RandomNumberGenerator.new()
	rng.seed = _SOAK_SEED
	var fs := FocusStack.new()
	var current_id : StringName = ids[0]
	fs.visit(current_id)
	pictures[current_id].screen_root.process_mode = Node.PROCESS_MODE_ALWAYS

	var iterations_run := 0
	for i : int in _SOAK_ITERATIONS:
		var candidates : Array[StringName] = []
		for id : StringName in ids:
			if id != current_id: candidates.append(id)
		var dest_id : StringName = candidates[rng.randi() % candidates.size()]

		var transition := WallTransition.new()
		var landed_id : Array[StringName] = [&""]   # boxed -- lambdas capture locals BY VALUE
		transition.landed.connect(func(id: StringName) -> void: landed_id[0] = id)
		var source_wp : WallPicture = pictures[current_id]
		var source_rect : PictureRect = rects[current_id]
		var dest_wp : WallPicture = pictures[dest_id]
		var dest_rect : PictureRect = rects[dest_id]
		transition.request(camera, source_wp, source_rect, dest_wp, dest_rect, WINDOW, settings)

		# Force the plateau sample deterministically (see the doc comment above) -- guarantees the
		# dest-unpause/input-unlock latches fire regardless of how many real frames the short Tween
		# happens to render. The source-pause latch itself no longer depends on this (latch-fix:
		# it is scheduled by precomputed elapsed time, not re-checked geometry), but this call stays
		# -- a deterministic gate is still right, and it still keeps dest_visible/dest_frame_in_view
		# honest under the same sparse sampling this soak's short duration invites.
		var total := WallTransition.total_duration(settings)
		var bounds := WallTransition.phase_bounds(settings)
		var plateau_elapsed : float = (bounds["zoom_out_end"] + bounds["zoom_in_start"]) * 0.5 * total
		transition._apply(camera, source_wp, dest_wp,
				WallTransition.sample_at(plateau_elapsed, total, source_rect, dest_rect, WINDOW,
						settings), plateau_elapsed)

		await transition.landed
		check(landed_id[0] == dest_id,
				"soak iteration %d (seed %d): the transition landed on the requested destination %s"
				% [i, _SOAK_SEED, dest_id], str(landed_id[0]))

		fs.visit(dest_id)
		current_id = dest_id
		iterations_run += 1

		var always_count := 0
		for id : StringName in ids:
			if pictures[id].screen_root.process_mode == Node.PROCESS_MODE_ALWAYS:
				always_count += 1
		check(always_count == 1,
				"soak iteration %d (seed %d): EXACTLY one ALWAYS screen after landing on %s"
				% [i, _SOAK_SEED, dest_id], "always_count=%d" % always_count)
		if i > 0:
			check(fs.can_back(),
					("soak iteration %d (seed %d): the focus stack still reports a valid, "
					+ "growing history") % [i, _SOAK_SEED])

	check(iterations_run == _SOAK_ITERATIONS,
			"the soak loop actually ran all %d iterations before any of the above was asserted "
			% _SOAK_ITERATIONS + "(seed %d)" % _SOAK_SEED, "ran=%d" % iterations_run)

	camera.queue_free()
	for wp : WallPicture in picture_list:
		if wp.screen_root and is_instance_valid(wp.screen_root): wp.screen_root.queue_free()
	await _cleanup(picture_list)

# ------------------------------------------------------------------ latch-fix regression

## THE POINT OF THIS TEST (coordinator, latch-fix): T13 forces a sample at the wide-zoom plateau,
## so it is blind BY CONSTRUCTION to whether the source-pause latch can be missed by real frame
## sampling. This test forces NOTHING -- a real, unforced transition, at wall_transition_delay
## 0.02s, the exact duration `Tests/Visual/wall_transition_latch_timing_spike.gd`'s own sweep
## measured failing 3/3 real trials before the fix (the raw `source_frame_in_view` condition is
## TRANSIENT -- true only across roughly [5%, 50%] of a transition's own duration, then false again
## all the way to landing -- so a real per-frame sampler can validly never observe it). Must be RED
## against the pre-fix code and GREEN after; both directions verified by hand, not assumed.
func test_source_pauses_under_real_sparse_frame_sampling() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	var settings := _settings(1.0, 0.02)   # total_duration = 0.02s -- the measured failure point
	var source_rect := _rect(&"a", Vector2(-800, 0))
	var dest_rect := _rect(&"b", Vector2(800, 0))
	var source_wp := _wall_picture()
	var dest_wp := _wall_picture()
	source_wp.screen_root = Node.new()
	dest_wp.screen_root = Node.new()
	add_child(source_wp.screen_root)
	add_child(dest_wp.screen_root)
	source_wp.screen_root.process_mode = Node.PROCESS_MODE_ALWAYS
	dest_wp.screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE

	var transition := WallTransition.new()
	transition.request(camera, source_wp, source_rect, dest_wp, dest_rect, WINDOW, settings)
	await transition.landed   # NO forced sample -- purely the real Tween's own per-frame cadence

	check(source_wp.screen_root.process_mode == Node.PROCESS_MODE_PAUSABLE,
			"the SOURCE screen actually paused (Q72=a) -- not merely that SOME picture stayed put",
			"source process_mode=%d" % source_wp.screen_root.process_mode)
	var always_count := 0
	if source_wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS: always_count += 1
	if dest_wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS: always_count += 1
	check(always_count == 1,
			"exactly one ALWAYS screen after a real (unforced) transition at the duration where "
			+ "sparse real-frame sampling previously missed the source's pause window entirely",
			"always_count=%d" % always_count)

	camera.queue_free()
	source_wp.screen_root.queue_free()
	dest_wp.screen_root.queue_free()
	await _cleanup([source_wp, dest_wp])
