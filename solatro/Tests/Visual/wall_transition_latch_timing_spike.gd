extends Node
# res://Tests/Visual/wall_transition_latch_timing_spike.gd
# ==============================================================================
# INVESTIGATION (coordinator's phase3-close follow-up, NOT a PLAN.md step): is T13's original
# real-Tween flakiness a TEST ARTIFACT (the harness samples more sparsely than the real game would)
# or a PRODUCTION DEFECT (the Q72=a source_frame_in_view latch can genuinely be missed by real
# per-frame sampling)? Uses ONLY the real, unmodified WallTransition -- no production code touched,
# no forced sample. `_source_paused`/`_dest_unpaused` are read directly (GDScript's leading
# underscore is convention, not access control) purely to OBSERVE, never to drive anything.
#
# Three probes, in sequence, each printing one PROBE line:
#   PROBE1 -- at T13's own settings (wall_transition_delay=0.1s), how many real process frames does
#             one transition actually produce, and at which frame index (if any) the source's own
#             latch first goes true.
#   PROBE2 -- a fine (5000-step) synchronous sample_at() scan of the SAME fixture: is the raw
#             source_frame_in_view condition MONOTONIC once true (stays true) or TRANSIENT (goes
#             false again later, e.g. once travel moves the camera away)?
#   PROBE3 -- sweeps wall_transition_delay down, no forced sample, and reports the latched state at
#             landing at each duration -- the smallest duration (if any) where more than one
#             screen ends up ALWAYS, reproducible on demand.
#
# Run WINDOWED (matches how run_tests.py actually runs; no rendering is otherwise needed here, but
# frame cadence itself is exactly the thing under test, so headless's own different frame timing
# would not answer the question asked):
#     <console exe> --path solatro res://Tests/Visual/wall_transition_latch_timing_spike.tscn
# Self-quits. Not a repeatable regression test -- a one-off diagnostic, never added to all_tests.tscn.
# ==============================================================================

const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const WINDOW := Vector2(1280.0, 720.0)
const WATCHDOG_SECS := 15.0

func _settings(base_delay: float, transition_delay: float) -> PlayerSettings:
	var s := PlayerSettings.new()
	s.base_delay = base_delay
	s.wall_transition_delay = transition_delay
	return s

func _wall_picture() -> WallPicture:
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	add_child(wp)
	return wp

## A typed bundle -- a plain Dictionary made every field come back as Variant, which the strict
## typed WallTransition.request() signature (warnings-as-errors) then rejected outright.
class Rig:
	var camera : Camera2D
	var source_rect : PictureRect
	var dest_rect : PictureRect
	var source_wp : WallPicture
	var dest_wp : WallPicture
	var transition : WallTransition

func _rig() -> Rig:
	var r := Rig.new()
	r.camera = Camera2D.new()
	add_child(r.camera)
	r.source_rect = PictureRect.new(&"a", Vector2(-800, 0), Vector2(400, 400),
			Vector4(20, 20, 20, 20))
	r.dest_rect = PictureRect.new(&"b", Vector2(800, 0), Vector2(400, 400),
			Vector4(20, 20, 20, 20))
	r.source_wp = _wall_picture()
	r.dest_wp = _wall_picture()
	r.source_wp.screen_root = Node.new()
	r.dest_wp.screen_root = Node.new()
	add_child(r.source_wp.screen_root)
	add_child(r.dest_wp.screen_root)
	r.source_wp.screen_root.process_mode = Node.PROCESS_MODE_ALWAYS
	r.dest_wp.screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	r.transition = WallTransition.new()
	return r

func _teardown(rig: Rig) -> void:
	rig.camera.queue_free()
	if rig.source_wp.screen_root: rig.source_wp.screen_root.queue_free()
	if rig.dest_wp.screen_root: rig.dest_wp.screen_root.queue_free()
	rig.source_wp.queue_free()
	rig.dest_wp.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	await _probe1_real_frame_count_and_latch_timing()
	_probe2_monotonicity()
	await _probe3_repro_sweep()
	print("SPIKE_DONE")
	get_tree().quit()

# ------------------------------------------------------------------ PROBE1

func _probe1_real_frame_count_and_latch_timing() -> void:
	var settings := _settings(0.1, 1.0)   # total_duration = 0.1s -- matches T13's own settings
	var rig := _rig()
	var transition := rig.transition

	var start_frame := Engine.get_process_frames()
	transition.request(rig.camera, rig.source_wp, rig.source_rect, rig.dest_wp, rig.dest_rect,
			WINDOW, settings)

	var latch_frame := -1
	var watchdog := 0.0
	while transition.is_active and watchdog < WATCHDOG_SECS:
		await get_tree().process_frame
		watchdog += get_process_delta_time()
		if latch_frame < 0 and transition._source_paused:
			latch_frame = Engine.get_process_frames() - start_frame
	var end_frame := Engine.get_process_frames() - start_frame
	if latch_frame < 0 and transition._source_paused:
		latch_frame = end_frame

	print("PROBE1 total_duration=%.4f total_real_frames=%d latch_frame=%d source_paused_at_end=%s "
			% [WallTransition.total_duration(settings), end_frame, latch_frame,
					transition._source_paused]
			+ "dest_unpaused_at_end=%s timed_out=%s"
			% [transition._dest_unpaused, watchdog >= WATCHDOG_SECS])
	await _teardown(rig)

# ------------------------------------------------------------------ PROBE2

func _probe2_monotonicity() -> void:
	var settings := _settings(0.1, 1.0)
	var total := WallTransition.total_duration(settings)
	var source_rect := PictureRect.new(&"a", Vector2(-800, 0), Vector2(400, 400),
			Vector4(20, 20, 20, 20))
	var dest_rect := PictureRect.new(&"b", Vector2(800, 0), Vector2(400, 400),
			Vector4(20, 20, 20, 20))
	var steps := 5000

	# Full contiguous TRUE-window list for both raw conditions -- not just "does it ever go false
	# again" but exactly WHERE, so a transient pattern is characterized, not just detected. Two
	# independent inline scans (no Callable indirection -- an earlier version routed the condition
	# through a Callable and silently produced a wrong result under warnings-as-errors; direct code
	# is what T3/T4/T6-T8 already use and trust).
	var source_windows : Array = []
	var dest_windows : Array = []
	var source_run_start := -1
	var dest_run_start := -1
	for i : int in (steps + 1):
		var elapsed := total * float(i) / float(steps)
		var s := WallTransition.sample_at(elapsed, total, source_rect, dest_rect, WINDOW, settings)
		if s.source_frame_in_view and source_run_start < 0:
			source_run_start = i
		elif not s.source_frame_in_view and source_run_start >= 0:
			source_windows.append([source_run_start, i - 1])
			source_run_start = -1
		if s.dest_visible and dest_run_start < 0:
			dest_run_start = i
		elif not s.dest_visible and dest_run_start >= 0:
			dest_windows.append([dest_run_start, i - 1])
			dest_run_start = -1
	if source_run_start >= 0: source_windows.append([source_run_start, steps])
	if dest_run_start >= 0: dest_windows.append([dest_run_start, steps])

	print("PROBE2 source_frame_in_view TRUE windows (of %d steps, total=%.4fs):" % [steps, total])
	for w : Array in source_windows:
		var w_start : int = w[0]
		var w_end : int = w[1]
		print("  [%d..%d] = %.4fs..%.4fs (width %.4fs)" % [w_start, w_end,
				total * float(w_start) / steps, total * float(w_end) / steps,
				total * float(w_end - w_start) / steps])
	print("PROBE2 dest_visible TRUE windows:")
	for w : Array in dest_windows:
		var w_start : int = w[0]
		var w_end : int = w[1]
		print("  [%d..%d] = %.4fs..%.4fs (width %.4fs)" % [w_start, w_end,
				total * float(w_start) / steps, total * float(w_end) / steps,
				total * float(w_end - w_start) / steps])
	print("PROBE2 source_windows_count=%d dest_windows_count=%d monotonic_source=%s"
			% [source_windows.size(), dest_windows.size(), source_windows.size() <= 1])

# ------------------------------------------------------------------ PROBE3

func _probe3_repro_sweep() -> void:
	var candidate_delays := [0.6, 0.3, 0.1, 0.05, 0.033, 0.02, 0.016, 0.01, 0.005, 0.002, 0.001]
	for delay : float in candidate_delays:
		for trial : int in 3:   # a few trials per duration -- real-frame timing can vary run to run
			var settings := _settings(1.0, delay)
			var rig := _rig()
			var transition := rig.transition
			transition.request(rig.camera, rig.source_wp, rig.source_rect, rig.dest_wp,
					rig.dest_rect, WINDOW, settings)
			var watchdog := 0.0
			while transition.is_active and watchdog < WATCHDOG_SECS:
				await get_tree().process_frame
				watchdog += get_process_delta_time()

			var always_count := 0
			if rig.source_wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS: always_count += 1
			if rig.dest_wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS: always_count += 1
			print(("PROBE3 delay=%.4f trial=%d total_duration=%.4f source_paused=%s "
					+ "dest_unpaused=%s always_count=%d timed_out=%s")
					% [delay, trial, WallTransition.total_duration(settings),
							transition._source_paused, transition._dest_unpaused, always_count,
							watchdog >= WATCHDOG_SECS])
			await _teardown(rig)
