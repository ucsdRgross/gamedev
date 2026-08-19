extends TestSuite
# res://Tests/Visual/wall_transition_fuzz_soak.gd
# ==============================================================================
# COORDINATOR-REQUESTED FUZZ SOAK (picture-wall, latch-fix follow-up) -- well beyond T13's own
# 20-transition gate (TEST_PLAN.md T13, PLAN.md §3 Phase-3 acceptance). Seeded, replayable, real
# (unforced) transitions -- no plateau sample is forced, unlike T13, because the whole point is to
# exercise the source-pause latch fix under the SAME real, sparse per-frame sampling that broke it
# (GAP-012, ASSUMPTIONS.md "latch-fix").
#
# Per iteration: a real WallTransition between two real (T13-style minimal, un-built()'ed)
# WallPicture fixtures, `wall_transition_delay` drawn per-iteration from a distribution that
# deliberately includes the <=0.02s zone GAP-012 reproduced 3/3 in. Window aspect is drawn once
# PER BATCH (not per iteration) across the full supported range (4:3 .. 32:9, G13) and the picture
# set is re-packed with the REAL `WallPacker` for that aspect -- so the no-overlap invariant is
# checked against real packer output at real extreme aspects, not a hand-placed circle like T13's.
#
# After EVERY landing: exactly one ALWAYS screen root, a valid/growing FocusStack, and no two
# packed frame-outer rects overlap (independent re-check, not just trusting WallPacker's own
# internal rule-6 guard). A combined per-round check is this suite's own proxy for "the errors log
# stayed empty this round" -- GDScript cannot hook push_error (ASSUMPTIONS.md GAP-007), so the
# only per-ROUND signal obtainable from inside the engine is this
# suite's own check() failing, which is exactly what would make test_output_errors.log non-empty.
# A genuine engine-level push_error scan (WallPacker.pack()'s own rule-6 guard included) is caught
# separately, in aggregate over the whole run, by Tools/run_tests.py's exit-time wrapper around
# THIS scene -- see the run command in the class-level report, not per-iteration, which is a real
# engine limitation, not a gap in this suite.
#
# NOT in all_tests.tscn: 200+ real transitions is far too slow for the standing gate, and this is
# explicitly a one-off stress soak, not a phase-acceptance gate. Self-terminating (calls
# get_tree().quit() after finish()), windowed run, WITH AN EXTERNAL KILLING TIMEOUT:
#     <console exe> --path solatro res://Tests/Visual/wall_transition_fuzz_soak.tscn
# ==============================================================================

const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")

## Overridable via FUZZ_SEED so a reported failure can be replayed exactly; default is fixed so an
## un-parameterised run is ALSO replayable.
const DEFAULT_SEED := 20260816
## "at least 200 random transitions" -- the coordinator's own floor. Never reduced to dodge a
## finding; only ever raised.
const ITERATIONS := 240
const BATCH_SIZE := 40   # aspect (and the whole packed set) re-rolled every 40 iterations
const PICTURE_COUNT := 14
const ASPECT_MIN := 4.0 / 3.0     # G13's floor
const ASPECT_MAX := 32.0 / 9.0    # G13's ceiling -- the extreme the ellipse clamp exists to save
## `total_duration = base_delay * wall_transition_delay` (WallTransition.total_duration) -- base
## fixed at 1.0 so `wall_transition_delay` IS the transition's real duration in seconds, matching
## the regression test's own convention (test_wall_transition.gd,
## test_source_pauses_under_real_sparse_frame_sampling).
const BASE_DELAY := 1.0
## GAP-012's own measured failure zone (ASSUMPTIONS.md "latch-fix"): 0.02s failed 3/3, 0.033s
## failed 2/3. A quarter of all iterations are forced into this zone; the rest spread wider so the
## soak also exercises ordinary durations, not only the pathological one.
const SHORT_DELAY_CHANCE := 0.25
const SHORT_DELAY_MIN := 0.005
const SHORT_DELAY_MAX := 0.02
const NORMAL_DELAY_MIN := 0.02
const NORMAL_DELAY_MAX := 0.5

func suite_name() -> String:
	return "WALL TRANSITION FUZZ SOAK"

var _seed : int = DEFAULT_SEED

func _ready() -> void:
	var env_seed := OS.get_environment("FUZZ_SEED")
	if not env_seed.is_empty(): _seed = int(env_seed)
	TestLog.line("============ WALL TRANSITION FUZZ SOAK ============")
	TestLog.line("FUZZ_SOAK seed=%d iterations=%d batch_size=%d pictures=%d" \
			% [_seed, ITERATIONS, BATCH_SIZE, PICTURE_COUNT])
	await _run_soak()
	finish()
	get_tree().quit()

## The full run: builds ONE authored layout (unchanged across batches), then re-packs it at a
## fresh random aspect every BATCH_SIZE iterations and runs BATCH_SIZE real transitions against
## that batch's packed geometry before moving to the next.
func _run_soak() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var layout := _make_layout()
	var all_ids : Array[StringName] = []
	for e : PictureEntry in layout.pictures: all_ids.append(e.id)

	var camera := Camera2D.new()
	add_child(camera)
	var fs := FocusStack.new()
	var current_id : StringName = layout.home_id
	var any_landed := false
	var iterations_run := 0

	var pictures : Dictionary[StringName, WallPicture] = {}
	var rects : Dictionary[StringName, PictureRect] = {}
	var window := Vector2(1280, 720)

	var batch := 0
	while iterations_run < ITERATIONS:
		var aspect := rng.randf_range(ASPECT_MIN, ASPECT_MAX)
		window = Vector2(720.0 * aspect, 720.0)
		var packed := WallPacker.pack(layout, all_ids, aspect)
		check(packed.size() == all_ids.size(),
				"batch %d (aspect %.4f): WallPacker packed all %d entries with no overlap-truncation "
				% [batch, aspect, all_ids.size()],
				"packed=%d expected=%d" % [packed.size(), all_ids.size()])

		var no_overlap := _no_two_rects_overlap(packed)
		check(no_overlap,
				"batch %d (aspect %.4f, seed %d): no two packed frame-outer rects overlap"
				% [batch, aspect, _seed])

		# Tear down the previous batch's pictures, build this batch's. `screen_root` is a plain
		# script-variable reference, NEVER added as a child anywhere (same T13-style minimal
		# fixture, test_wall_transition.gd) -- queue_free()ing the WallPicture alone does NOT reach
		# it, so it needs its own explicit queue_free() or it leaks every batch (measured: missing
		# this the first time round leaked 70 ObjectDB instances -- 5 old batches x 14 pictures).
		for old : WallPicture in pictures.values():
			if old.screen_root and is_instance_valid(old.screen_root): old.screen_root.queue_free()
			if is_instance_valid(old): old.queue_free()
		pictures.clear()
		rects.clear()
		for rect : PictureRect in packed:
			rects[rect.id] = rect
			var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
			add_child(wp)
			# T13-style minimal fixture (test_wall_transition.gd) -- a real throwaway screen_root,
			# never build()'ed (WallTransition only ever reads screen_root/PictureRect, not
			# %Screen/viewport machinery), so no real Wall/SubViewport tree is needed for this soak.
			var template := Node.new()
			var scene := PackedScene.new()
			scene.pack(template)
			template.free()
			wp.screen_root = scene.instantiate()
			wp.screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
			pictures[rect.id] = wp
		if pictures.has(current_id):
			pictures[current_id].screen_root.process_mode = Node.PROCESS_MODE_ALWAYS
		else:
			# Should not happen (all_ids are fully unlocked every batch), but fail loudly rather
			# than silently picking a different picture if it ever does.
			check(false, "batch %d: the picture the soak was ON before this repack is still packed"
					% batch, "current_id=%s" % current_id)
			return

		await get_tree().process_frame   # let the freed pictures actually go before this batch runs

		var this_batch_size := mini(BATCH_SIZE, ITERATIONS - iterations_run)
		for _j : int in this_batch_size:
			var candidates : Array[StringName] = []
			for id : StringName in all_ids:
				if id != current_id: candidates.append(id)
			var dest_id : StringName = candidates[rng.randi() % candidates.size()]

			var delay : float
			if rng.randf() < SHORT_DELAY_CHANCE:
				delay = rng.randf_range(SHORT_DELAY_MIN, SHORT_DELAY_MAX)
			else:
				delay = rng.randf_range(NORMAL_DELAY_MIN, NORMAL_DELAY_MAX)
			var settings := PlayerSettings.new()
			settings.base_delay = BASE_DELAY
			settings.wall_transition_delay = delay

			var transition := WallTransition.new()
			var landed_id : Array[StringName] = [&""]   # boxed -- lambdas capture locals BY VALUE
			transition.landed.connect(func(id: StringName) -> void: landed_id[0] = id)
			var source_wp : WallPicture = pictures[current_id]
			var source_rect : PictureRect = rects[current_id]
			var dest_wp : WallPicture = pictures[dest_id]
			var dest_rect : PictureRect = rects[dest_id]
			transition.request(camera, source_wp, source_rect, dest_wp, dest_rect, window, settings)
			# NO forced sample (unlike T13) -- real, unforced timing is the entire point: this is
			# exactly the condition GAP-012's latch defect needed to reproduce.
			await transition.landed

			var round_ok := (landed_id[0] == dest_id)
			check(round_ok,
					"iter %d/%d (seed %d, batch %d, aspect %.4f, delay %.4fs): landed on the "
					% [iterations_run, ITERATIONS, _seed, batch, aspect, delay]
					+ "requested destination %s" % dest_id, "landed=%s" % landed_id[0])

			var always_count := 0
			for id : StringName in pictures:
				if pictures[id].screen_root.process_mode == Node.PROCESS_MODE_ALWAYS:
					always_count += 1
			var ok_always := (always_count == 1)
			check(ok_always,
					"iter %d/%d (seed %d, batch %d, delay %.4fs): EXACTLY one ALWAYS screen after "
					% [iterations_run, ITERATIONS, _seed, batch, delay]
					+ "landing on %s" % dest_id, "always_count=%d" % always_count)
			round_ok = round_ok and ok_always

			fs.visit(dest_id)
			current_id = dest_id
			var ok_stack := (not any_landed) or fs.can_back()
			check(ok_stack,
					"iter %d/%d (seed %d, batch %d): the focus stack still reports a valid, growing "
					% [iterations_run, ITERATIONS, _seed, batch] + "history")
			round_ok = round_ok and ok_stack
			any_landed = true

			var ok_overlap := _no_two_rects_overlap(packed)
			check(ok_overlap,
					"iter %d/%d (seed %d, batch %d): no two packed rects overlap (re-checked after "
					% [iterations_run, ITERATIONS, _seed, batch] + "landing, same batch geometry)")
			round_ok = round_ok and ok_overlap

			check(round_ok,
					"iter %d/%d (seed %d, batch %d, aspect %.4f, delay %.4fs): no invariant broke "
					% [iterations_run, ITERATIONS, _seed, batch, aspect, delay]
					+ "this round -- this suite's own error-log-stayed-empty proxy (GDScript cannot "
					+ "hook push_error; see the file header)")

			iterations_run += 1
		batch += 1

	check(iterations_run == ITERATIONS,
			"the soak actually ran all %d iterations (seed %d) before any of the above was asserted"
			% [ITERATIONS, _seed], "ran=%d" % iterations_run)

	camera.queue_free()
	for wp : WallPicture in pictures.values():
		if wp.screen_root and is_instance_valid(wp.screen_root): wp.screen_root.queue_free()
	for wp : WallPicture in pictures.values():
		if is_instance_valid(wp): wp.queue_free()
	await get_tree().process_frame

## Independent re-check (never trusts WallPacker's own internal rule-6 guard alone): every pair of
## packed pictures' frame OUTER rects, checked pairwise for intersection.
func _no_two_rects_overlap(rects: Array[PictureRect]) -> bool:
	for i : int in rects.size():
		var frame_i := WallPacker.frame_outer_rect(rects[i])
		for j : int in range(i + 1, rects.size()):
			var frame_j := WallPacker.frame_outer_rect(rects[j])
			if frame_i.intersects(frame_j): return false
	return true

## A synthetic "full picture set" -- no real catalog exists yet (the layout tool's own saved
## output, PLAN.md S34, Phase 8, out of scope; ASSUMPTIONS.md already forbids test code from
## reading it).
## PICTURE_COUNT entries spread evenly around the authored circle, varied size/frame/aspect-keeping
## so the packer's real geometry (not a uniform ring) is what gets stress-tested.
func _make_layout() -> WallLayout:
	var l := WallLayout.new()
	l.gap_px = 24.0
	l.ellipse_aspect_min = 1.2
	l.ellipse_aspect_max = 2.6
	l.home_id = &"fuzz_home"
	var pics : Array[PictureEntry] = []
	var step := 360.0 / float(PICTURE_COUNT)
	for i : int in PICTURE_COUNT:
		var id := &"fuzz_home" if i == 0 else StringName("fuzz_p%d" % i)
		var e := PictureEntry.new()
		e.id = id
		e.slot = int(step * float(i))
		e.size_multiplier = 0.6 + 0.9 * (float(i % 5) / 4.0)   # spread 0.6..1.5
		var side := 6.0 + 4.0 * float(i % 4)
		e.frame_px = Vector4(side, side, side * (1.0 if i % 3 != 0 else 3.0), side)
		e.keep_aspect = (i % 4 == 0)
		e.design_size = Vector2i(700, 700) if e.keep_aspect else Vector2i(1152, 648)
		pics.append(e)
	l.pictures = pics
	return l
