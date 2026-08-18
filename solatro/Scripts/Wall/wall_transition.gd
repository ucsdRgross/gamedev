class_name WallTransition
extends RefCounted
## The camera tween and its phase clock (NAMES.md) -- PLAN.md §1.10, S14 (implements C1-C15),
## S15 (C9, C11), S16 (C13), S17 (C16, resize/fullscreen retarget), S18 (K8-K10, reduced motion).
##
## sample_at() is the pure core: camera position/zoom plus the RAW (unlatched) geometric facts a
## caller uses to decide the pause/unpause/input-unlock boundaries -- no waiting, no Tween, callable
## at ANY elapsed time, which is what makes T1-T10 testable without real-time flakiness (per-frame
## sampling done as a synchronous scan over elapsed values, never `await`ed real frames). request()
## wires exactly ONE real Tween (D5: bound to the camera node, which is PROCESS_MODE_ALWAYS, so the
## tween keeps running under the wall's own global pause) that calls sample_at() every frame,
## applies the camera state, and LATCHES each boundary the instant its raw condition first holds
## (Q72/Q73/C13 all describe a MOMENT a screen crosses into a new state, never a moment it can cross
## back out of mid-transition).
##
## Q205/Q206: the destination screen must already be BUILT (WallPicture.build()) before calling
## request() -- this class owns only the camera's tween and phase clock (NAMES.md), never screen
## construction. request() itself performs no `await` before starting the tween, so calling it
## immediately after building the destination satisfies "built synchronously during the zoom-out
## phase" (which begins at t=0, the instant request() runs).
##
## Deliberately OUT OF SCOPE here (see ASSUMPTIONS.md): SubViewport render_target_update_mode and
## %Screen.texture_filter are §1.8/§1.7 concerns (S11/S13) this class does not touch, ever -- the
## instant a transition lands, THIS class leaves the destination mid-focus (screen_root ALWAYS,
## viewport untouched). `Main._focus_picture()` is the caller that does the full focus()/unfocus()
## handoff, immediately after `landed[0]` goes true -- not tested by any T-row here, since it is
## Main's own responsibility, not this class's.

## One frame's worth of camera state plus the raw geometric facts at that instant.
class Sample:
	var camera_position : Vector2
	var camera_zoom : float
	## Q72=a: the SOURCE's frame outer rect is ENTIRELY inside the camera's visible rect right now.
	var source_frame_in_view : bool
	## Q73=c: ANY part of the DESTINATION's own picture rect is inside the visible rect right now.
	var dest_visible : bool
	## C13: the DESTINATION's frame outer rect is ENTIRELY inside the visible rect right now.
	var dest_frame_in_view : bool

## True while a tween is running toward `_dest_id`. Q56=b: a request() while this is true is
## ignored outright by request() itself -- never retargeted, extended, or restarted BY A NEW
## request(). retarget() (S17) is the one exception, and it changes only geometry, never `_dest_id`
## or the tween's own elapsed clock.
var is_active : bool = false
var _dest_id : StringName = &""
var _source_paused := false
var _dest_unpaused := false
var _input_unlocked := false

## The live geometry/window sample_at() reads EVERY FRAME via the tween's own callback (S17) --
## instance fields rather than closure-captured request() locals, so retarget() can swap them in
## place while the same running Tween keeps going, never restarted. Only meaningful while
## `is_active`.
var _source_rect : PictureRect
var _dest_rect : PictureRect
var _window_size : Vector2
var _settings : PlayerSettings
var _total : float

## latch-fix: the elapsed instant (seconds) at which the source pauses, computed ANALYTICALLY once
## at request()/retarget() time rather than re-checked against the live `source_frame_in_view`
## condition every sampled frame. Necessary because that raw condition is TRANSIENT, not
## monotonic-to-completion (measured directly: `Tests/Visual/wall_transition_latch_timing_spike.gd`
## -- it opens then CLOSES again well before landing), so a real per-frame sampler can validly land
## entirely outside the window and never observe it true. Scheduling by a precomputed TIME
## threshold instead is frame-rate independent: ANY frame whose `elapsed` has caught up to this
## value latches the pause, and the tween is guaranteed to eventually reach `elapsed == _total` at
## landing regardless of how sparsely it got sampled along the way.
var _source_pause_time : float = 0.0

## Fired once, when the tween completes and lands on the requested picture.
signal landed(picture_id: StringName)
## Fired once, the instant C13's boundary is first crossed (S16) -- the caller listens for this
## rather than polling `is_active`/sampling itself.
signal input_unlocked

## Q46=b (§1.10 as amended -- see ASSUMPTIONS.md): total duration is base_delay times the wall's
## OWN multiplier, `wall_transition_delay` (S8; §1.10's literal `wall_transition_delay_scale` names
## a knob that was never built and NAMES.md does not fix -- a stale name, not a second knob).
## NEVER `Game.get_delay()`, which compresses to 0.0 on an act cancel (T2's own trap).
static func total_duration(settings: PlayerSettings) -> float:
	return settings.base_delay * settings.wall_transition_delay

## Q48=b: the "fit" zoom -- MIN of the two axis ratios, the mirror of `WallPicture.focused_scale()`'s
## "fill" MAX -- that lets a window CENTRED ON THE STRAIGHT-LINE MIDPOINT of source and dest (Q51=a;
## sample_at()'s own travel position at this plateau instant, TRANS_SINE/EASE_IN_OUT at progress 0.5,
## equals that midpoint exactly) contain both frame outer rects plus a margin sized as a fraction of
## the LARGER of the two PICTURES' own sizes (`DESIGN.md` §5: "extra share of the picture's size" --
## the overseer's ruling: larger-of guarantees at least the configured share of each; ASSUMPTIONS.md).
## The needed half-extent per axis is the largest ONE-SIDED reach from that fixed midpoint to either
## frame's near or far edge, not half of the union's raw width/height -- the two coincide only when
## the union happens to be centred on the midpoint (the symmetric case); an asymmetric pair (differing
## `size_multiplier` and/or `frame_px`) can put the union's true centre elsewhere, and using raw
## union.size there would let the far frame's edge fall outside the fitted window (ASSUMPTIONS.md).
static func _wide_zoom(source_rect: PictureRect, dest_rect: PictureRect, window_size: Vector2,
		margin_fraction: float) -> float:
	var source_frame := WallPacker.frame_outer_rect(source_rect)
	var dest_frame := WallPacker.frame_outer_rect(dest_rect)
	var centre := (source_rect.centre + dest_rect.centre) * 0.5
	var half_x := maxf(centre.x - minf(source_frame.position.x, dest_frame.position.x),
			maxf(source_frame.end.x, dest_frame.end.x) - centre.x)
	var half_y := maxf(centre.y - minf(source_frame.position.y, dest_frame.position.y),
			maxf(source_frame.end.y, dest_frame.end.y) - centre.y)
	var larger_picture_size := Vector2(maxf(source_rect.size.x, dest_rect.size.x),
			maxf(source_rect.size.y, dest_rect.size.y))
	var needed := Vector2(half_x, half_y) * 2.0 + larger_picture_size * margin_fraction
	return minf(window_size.x / needed.x, window_size.y / needed.y)

## The camera's visible rect (wall-space units) at a given position/zoom. Camera2D.zoom here is
## DIRECT MAGNIFICATION, measured in S37/S13 (ASSUMPTIONS.md) -- the visible span is
## `window_size / zoom`, never `window_size * zoom`.
static func _visible_rect(position: Vector2, zoom: float, window_size: Vector2) -> Rect2:
	var size := window_size / zoom
	return Rect2(position - size * 0.5, size)

## The four phase-boundary fractions (of the total duration, 0..1), §1.10's table plus GAP-010-
## style overlap splitting (see the class doc comment and ASSUMPTIONS.md): three authored fractions
## that sum PAST 1.0 on purpose (Q47=b), with the excess split evenly at each of the two boundaries
## so zoom-in always lands exactly at 1.0. Exposed (not `_`-prefixed) because callers/tests that
## need to know WHEN a phase starts or ends -- not just camera state at one instant -- read it
## directly rather than re-deriving it.
static func phase_bounds(settings: PlayerSettings) -> Dictionary:
	var overlap := (settings.wall_zoom_out_fraction + settings.wall_travel_fraction
			+ settings.wall_zoom_in_fraction - 1.0) * 0.5
	var zoom_out_end := settings.wall_zoom_out_fraction
	var travel_start := zoom_out_end - overlap
	var travel_end := travel_start + settings.wall_travel_fraction
	var zoom_in_start := travel_end - overlap
	return {"zoom_out_end": zoom_out_end, "travel_start": travel_start, "travel_end": travel_end,
			"zoom_in_start": zoom_in_start}

## latch-fix (Q72=a): finds the FIRST elapsed instant at which `source_frame_in_view` goes true, by
## a linear scan of the pure `sample_at()` (cheap, run once per request()/retarget(), never per
## frame -- unrelated to how many real frames the Tween ends up rendering). A scan rather than a
## bisection because the raw condition is TRANSIENT (opens then closes again, ASSUMPTIONS.md), not
## a simple false->true step function a bisection could assume.
## (b) BACKSTOP: if no crossing exists for this geometry at all, pauses by the END OF THE ZOOM-OUT
## PHASE regardless -- §1.6's "exactly one screen root is ALWAYS" is absolute and outranks hitting
## the precise Q72=a instant.
const _CROSSING_SCAN_STEPS := 500

static func _find_source_pause_time(total: float, source_rect: PictureRect, dest_rect: PictureRect,
		window_size: Vector2, settings: PlayerSettings) -> float:
	for i : int in (_CROSSING_SCAN_STEPS + 1):
		var elapsed := total * float(i) / float(_CROSSING_SCAN_STEPS)
		var s := sample_at(elapsed, total, source_rect, dest_rect, window_size, settings)
		if s.source_frame_in_view:
			return elapsed
	var bounds := phase_bounds(settings)
	var zoom_out_end : float = bounds["zoom_out_end"]
	return zoom_out_end * total

## The pure core (see the class doc comment). `total` is `total_duration()`'s own return value,
## passed in rather than re-derived so a caller/test can hold it fixed across many samples.
##
## S18 (K8, Q172=a): with `wall_reduced_motion` on, the whole zoom-out/travel/zoom-in dance is
## replaced by a cross-fade AT A FIXED ZOOM -- held at the SAME "show both frames" framing
## `_wide_zoom()` already computes for the ordinary transition's own peak, for the ENTIRE duration,
## camera position included, so nothing about the camera moves at all (T12: zoom is constant
## throughout). Whatever actually draws the cross-fade (blending the two SCREENS' opacity) remains
## UNBUILT -- NAMES.md scopes this class to the camera tween and clock alone, the same "out of
## scope" boundary the class doc comment already draws for the landing handoff (ASSUMPTIONS.md),
## and nothing in Phase 7's wire-up built it either; still owed. Both frames are guaranteed in view
## by `_wide_zoom()`'s own construction, so the
## pause/unpause/input-unlock booleans below all latch on the very first sample -- correct for a
## cross-fade, which has no real "travel" to wait through.
static func sample_at(elapsed: float, total: float, source_rect: PictureRect,
		dest_rect: PictureRect, window_size: Vector2, settings: PlayerSettings) -> Sample:
	var s := Sample.new()

	if settings.wall_reduced_motion:
		s.camera_position = (source_rect.centre + dest_rect.centre) * 0.5
		s.camera_zoom = _wide_zoom(source_rect, dest_rect, window_size,
				settings.wall_frame_reveal_margin)
		var visible := _visible_rect(s.camera_position, s.camera_zoom, window_size)
		s.source_frame_in_view = visible.encloses(WallPacker.frame_outer_rect(source_rect))
		s.dest_visible = visible.intersects(
				Rect2(dest_rect.centre - dest_rect.size * 0.5, dest_rect.size))
		s.dest_frame_in_view = visible.encloses(WallPacker.frame_outer_rect(dest_rect))
		return s

	# S28 (J10=Q137 override, "with Info mode on a transition is a pure TRAVEL -- the camera never
	# leaves the info zoom"): zoom is CONSTANT throughout, held at the SOURCE's own info-zoom scale
	# (never re-derived per frame, never blended toward the destination's own scale, which could
	# differ if the two pictures are different sizes -- "never leaves" reads as "one fixed value
	# for the whole transition", not "smoothly interpolated between two"). Position still travels
	# (straight line, same as the ordinary case) between each picture's own info-zoom POSITION, so
	# the destination's own bottom-frame reveal is what the camera arrives at.
	if settings.wall_info_mode:
		var source_info := WallPicture.info_zoom_state(source_rect, window_size, settings)
		var dest_info := WallPicture.info_zoom_state(dest_rect, window_size, settings)
		var info_t := 0.0 if total <= 0.0 else clampf(elapsed / total, 0.0, 1.0)
		s.camera_position = (source_info["position"] as Vector2).lerp(
				dest_info["position"] as Vector2, info_t)
		s.camera_zoom = source_info["zoom"] as float
		var info_visible := _visible_rect(s.camera_position, s.camera_zoom, window_size)
		s.source_frame_in_view = info_visible.encloses(WallPacker.frame_outer_rect(source_rect))
		s.dest_visible = info_visible.intersects(
				Rect2(dest_rect.centre - dest_rect.size * 0.5, dest_rect.size))
		s.dest_frame_in_view = info_visible.encloses(WallPacker.frame_outer_rect(dest_rect))
		return s

	var bounds := phase_bounds(settings)
	var zoom_out_end : float = bounds["zoom_out_end"]
	var travel_start : float = bounds["travel_start"]
	var travel_end : float = bounds["travel_end"]
	var zoom_in_start : float = bounds["zoom_in_start"]

	var t := 0.0 if total <= 0.0 else clampf(elapsed / total, 0.0, 1.0)

	# Position: travel is the ONLY phase that moves it (§1.10's phase table assigns position to
	# travel alone). Straight line (Q51=a, overriding DESIGN.md's own stated chart default),
	# TRANS_SINE / EASE_IN_OUT (Q53=b).
	if t <= travel_start:
		s.camera_position = source_rect.centre
	elif t >= travel_end:
		s.camera_position = dest_rect.centre
	else:
		var travel_t := (t - travel_start) / (travel_end - travel_start)
		var eased : float = Tween.interpolate_value(0.0, 1.0, travel_t, 1.0,
				Tween.TRANS_SINE, Tween.EASE_IN_OUT)
		s.camera_position = source_rect.centre.lerp(dest_rect.centre, eased)

	# Zoom: zoom-out and zoom-in are the only phases that move it, composed in sequence -- the
	# zoom-out leg lerps start_zoom -> wide_zoom (TRANS_EXPO/EASE_OUT), then the zoom-in leg lerps
	# THAT result -> dest_zoom (TRANS_EXPO/EASE_IN). Flat at wide_zoom for the whole pure-travel
	# window between the two, since both progresses clamp to their resting value outside their own
	# window.
	var start_zoom := WallPicture.focused_scale(source_rect.size, window_size,
			settings.wall_overfill_margin)
	var dest_zoom := WallPicture.focused_scale(dest_rect.size, window_size,
			settings.wall_overfill_margin)
	var wide_zoom := _wide_zoom(source_rect, dest_rect, window_size,
			settings.wall_frame_reveal_margin)
	var out_progress := 0.0 if zoom_out_end <= 0.0 else clampf(t / zoom_out_end, 0.0, 1.0)
	out_progress = Tween.interpolate_value(0.0, 1.0, out_progress, 1.0,
			Tween.TRANS_EXPO, Tween.EASE_OUT)
	var after_out := lerpf(start_zoom, wide_zoom, out_progress)
	var in_span := 1.0 - zoom_in_start
	var in_progress := 0.0 if in_span <= 0.0 else clampf((t - zoom_in_start) / in_span, 0.0, 1.0)
	in_progress = Tween.interpolate_value(0.0, 1.0, in_progress, 1.0,
			Tween.TRANS_EXPO, Tween.EASE_IN)
	s.camera_zoom = lerpf(after_out, dest_zoom, in_progress)

	var visible := _visible_rect(s.camera_position, s.camera_zoom, window_size)
	s.source_frame_in_view = visible.encloses(WallPacker.frame_outer_rect(source_rect))
	s.dest_visible = visible.intersects(
			Rect2(dest_rect.centre - dest_rect.size * 0.5, dest_rect.size))
	s.dest_frame_in_view = visible.encloses(WallPacker.frame_outer_rect(dest_rect))
	return s

## Starts a transition from `source` to `dest`, animating `camera`. Q55=a (T10): a no-op, no tween
## at all, if `dest` is already the current picture. Q56=b (T9): ignored outright if a transition
## is already active.
func request(camera: Camera2D, source: WallPicture, source_rect: PictureRect, dest: WallPicture,
		dest_rect: PictureRect, window_size: Vector2, settings: PlayerSettings) -> void:
	if dest_rect.id == source_rect.id: return
	if is_active: return
	is_active = true
	_dest_id = dest_rect.id
	_source_paused = false
	_dest_unpaused = false
	_input_unlocked = false
	_source_rect = source_rect
	_dest_rect = dest_rect
	_window_size = window_size
	_settings = settings
	_total = total_duration(settings)
	_source_pause_time = _find_source_pause_time(_total, _source_rect, _dest_rect, _window_size,
			_settings)
	var tween := camera.create_tween()
	tween.tween_method(
			func(elapsed: float) -> void:
				_apply(camera, source, dest, sample_at(elapsed, _total, _source_rect, _dest_rect,
						_window_size, _settings), elapsed),
			0.0, _total, _total).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(
			func() -> void:
				is_active = false
				landed.emit(_dest_id))

## S17 (C16, Q26=a): a mid-flight resize/re-pack RETARGETS this transition to new geometry and
## continues -- never restarts, never cuts the tween short, never touches `_dest_id`, `_total`, or
## any latched pause/unpause/input-unlock boundary. A no-op while no transition is active (nothing
## to retarget). Because request()'s tween callback reads `_source_rect`/`_dest_rect`/`_window_size`
## fresh every frame rather than closure-captured locals, swapping these fields here means the very
## next `_apply()` call already samples the new geometry -- no separate "settle" step, and (T11) the
## resulting position/zoom discontinuity is bounded by the resize's own geometry shift, never a
## restart-driven snap back to the source.
##
## latch-fix: also RECOMPUTES `_source_pause_time` against the new geometry -- a precomputed
## crossing time from the OLD rects is meaningless once they change. Harmless to recompute even
## after the source has already latched (the new value is simply never read again in that case,
## since `_apply()`'s check is skipped once `_source_paused` is true).
func retarget(new_source_rect: PictureRect, new_dest_rect: PictureRect,
		new_window_size: Vector2) -> void:
	if not is_active: return
	_source_rect = new_source_rect
	_dest_rect = new_dest_rect
	_window_size = new_window_size
	_source_pause_time = _find_source_pause_time(_total, _source_rect, _dest_rect, _window_size,
			_settings)

## Applies one Sample to the camera and latches each pause/unpause/input-unlock boundary the
## instant its raw condition first holds (never un-latches, C9/C11/C13 all describe a one-way
## crossing). The source's own latch is scheduled by `elapsed >= _source_pause_time` (latch-fix) --
## a precomputed TIME, not a re-check of `s.source_frame_in_view` -- so it cannot be skipped by
## sparse real-frame sampling: the tween is guaranteed to reach `elapsed == _total` at landing, and
## `_source_pause_time <= _total` always (the backstop in `_find_source_pause_time` guarantees it).
func _apply(camera: Camera2D, source: WallPicture, dest: WallPicture, s: Sample,
		elapsed: float) -> void:
	camera.position = s.camera_position
	camera.zoom = Vector2.ONE * s.camera_zoom
	if elapsed >= _source_pause_time and not _source_paused:
		_source_paused = true
		if source.screen_root: source.screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	if s.dest_visible and not _dest_unpaused:
		_dest_unpaused = true
		if dest.screen_root: dest.screen_root.process_mode = Node.PROCESS_MODE_ALWAYS
	if s.dest_frame_in_view and not _input_unlocked:
		_input_unlocked = true
		input_unlocked.emit()
