class_name WallTransition
extends RefCounted
## The camera tween and its phase clock.
##
## `sample_at()` is the pure core: camera position/zoom plus the RAW, unlatched geometric facts a
## caller uses to decide the pause/unpause/input-unlock boundaries. No waiting, no Tween, callable
## at ANY elapsed time — so it can be sampled as a synchronous scan rather than over real frames.
##
## `request()` wires exactly ONE real Tween, bound to the camera node (`PROCESS_MODE_ALWAYS`, so it
## keeps running under the wall's global pause), which calls `sample_at()` every frame, applies the
## camera state, and LATCHES each boundary the instant its condition first holds. Every boundary is
## a one-way crossing: none un-latches mid-transition.
##
## ⚠ The destination screen must already be BUILT before `request()` is called — this class owns
## the camera's tween and clock, never screen construction. `request()` performs no `await` before
## starting the tween, so building the destination immediately before calling it lands that build
## inside the zoom-out phase.
##
## OUT OF SCOPE here: `SubViewport.render_target_update_mode` and `%Screen.texture_filter`. On
## landing this class leaves the destination mid-focus (screen_root ALWAYS, viewport untouched);
## `Main._focus_picture()` does the full focus()/unfocus() handoff.

## One frame's worth of camera state plus the raw geometric facts at that instant.
class Sample:
	var camera_position : Vector2
	var camera_zoom : float
	## The SOURCE's frame outer rect is ENTIRELY inside the camera's visible rect right now.
	var source_frame_in_view : bool
	## ANY part of the DESTINATION's picture rect is inside the visible rect right now.
	var dest_visible : bool
	## The DESTINATION's frame outer rect is ENTIRELY inside the visible rect right now.
	var dest_frame_in_view : bool

## True while a tween is running toward `_dest_id`. A `request()` while this is true is ignored
## outright — never retargeted, extended or restarted. `retarget()` is the one exception, and it
## changes only geometry, never `_dest_id` or the elapsed clock.
var is_active : bool = false
var _dest_id : StringName = &""
var _source_paused := false
var _dest_unpaused := false
var _input_unlocked := false

## The live geometry `sample_at()` reads EVERY FRAME via the tween callback. Instance fields
## rather than closure-captured locals, so `retarget()` can swap them in place while the same Tween
## keeps running. Only meaningful while `is_active`.
var _source_rect : PictureRect
var _dest_rect : PictureRect
var _window_size : Vector2
var _settings : PlayerSettings
var _total : float

## The elapsed instant (seconds) at which the source pauses, computed once per
## `request()`/`retarget()`.
## ⚠ Must NOT be a per-frame re-check of `source_frame_in_view`: that condition is TRANSIENT, not
## monotonic — it opens and CLOSES again well before landing — so sparse real frames can step over
## the window entirely and never see it true. A precomputed TIME is frame-rate independent: any
## frame whose `elapsed` has caught up latches the pause, and the tween always reaches `_total`.
var _source_pause_time : float = 0.0
## The precomputed elapsed instant at which input comes back. A TIME rather than a per-frame
## geometric re-check, for the same reason `_source_pause_time` is one.
var _input_unlock_time : float = 0.0

## Fired once, when the tween completes and lands on the requested picture.
signal landed(picture_id: StringName)
## Fired once, the instant input comes back. Callers listen rather than polling `is_active`.
signal input_unlocked

## `base_delay` times the wall's own `wall_transition_delay`.
## ⚠ NEVER `Game.get_delay()`, which compresses to 0.0 on an act cancel.
static func total_duration(settings: PlayerSettings) -> float:
	return settings.base_delay * settings.wall_transition_delay

## The "fit" zoom — MIN of the two axis ratios, mirroring `WallPicture.focused_scale()`'s "fill"
## MAX — at which a window centred on the straight-line midpoint of source and dest contains both
## frame outer rects plus a margin, sized as a fraction of the LARGER of the two picture sizes so
## each gets at least the configured share.
## ⚠ The needed half-extent per axis is the largest ONE-SIDED reach from that midpoint to either
## frame's near or far edge, NOT half the union's width/height. Those coincide only when the union
## is centred on the midpoint; an asymmetric pair (differing `size_multiplier` or `frame_px`) puts
## the union's centre elsewhere, and raw `union.size` would leave the far frame's edge outside.
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

## The camera's visible rect in wall space at a given position/zoom.
## ⚠ `Camera2D.zoom` is DIRECT MAGNIFICATION: the visible span is `window_size / zoom`, never
## `window_size * zoom`.
static func _visible_rect(position: Vector2, zoom: float, window_size: Vector2) -> Rect2:
	var size := window_size / zoom
	return Rect2(position - size * 0.5, size)

## The four phase-boundary fractions of the total duration, 0..1. The three authored fractions sum
## PAST 1.0 on purpose; the excess is split evenly across the two boundaries so zoom-in always lands
## exactly at 1.0. Public so callers that need to know WHEN a phase starts or ends read it rather
## than re-deriving it.
static func phase_bounds(settings: PlayerSettings) -> Dictionary:
	var overlap := (settings.wall_zoom_out_fraction + settings.wall_travel_fraction
			+ settings.wall_zoom_in_fraction - 1.0) * 0.5
	var zoom_out_end := settings.wall_zoom_out_fraction
	var travel_start := zoom_out_end - overlap
	var travel_end := travel_start + settings.wall_travel_fraction
	var zoom_in_start := travel_end - overlap
	return {"zoom_out_end": zoom_out_end, "travel_start": travel_start, "travel_end": travel_end,
			"zoom_in_start": zoom_in_start}

## The FIRST elapsed instant at which `source_frame_in_view` goes true, found by a linear scan of
## the pure `sample_at()`. Run once per `request()`/`retarget()`, never per frame.
## ⚠ A SCAN, not a bisection: the condition is transient, opening then closing again, so it is not
## the false->true step function a bisection would assume.
## BACKSTOP: with no crossing at all for this geometry, pause by the end of the zoom-out phase
## anyway — "exactly one screen root is ALWAYS" outranks hitting the precise instant.
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

## The FIRST elapsed instant at which the DESTINATION's frame is fully in view, precomputed once
## per `request()`/`retarget()` — same shape and same reason as `_find_source_pause_time()`.
## ⚠ Must NOT be a per-frame `s.dest_frame_in_view` check: the window in which the destination's
## whole frame fits opens in the wide middle of the transition and CLOSES again before landing,
## because a focused picture OVERFILLS the window at rest and its frame is off-screen by
## construction. Sparse frames, or a short transition, step over it and never unlock.
## BACKSTOP: `total`. Input must never stay locked longer than the move itself.
static func _find_input_unlock_time(total: float, source_rect: PictureRect, dest_rect: PictureRect,
		window_size: Vector2, settings: PlayerSettings) -> float:
	for i : int in (_CROSSING_SCAN_STEPS + 1):
		var elapsed := total * float(i) / float(_CROSSING_SCAN_STEPS)
		var s := sample_at(elapsed, total, source_rect, dest_rect, window_size, settings)
		if s.dest_frame_in_view:
			return elapsed
	return total

## The pure core (see the class doc comment). `total` is `total_duration()`'s own return value,
## passed in rather than re-derived so a caller/test can hold it fixed across many samples.
##
## ⚠ Under `wall_reduced_motion` there is NO CAMERA MOVE AT ALL: the camera holds the SOURCE's
## resting pose for the whole duration while the two screens cross-fade in place, and
## `Main._focus_picture()` CUTS it to the destination's resting pose once the fade completes. A
## fixed zoom and "no frame is ever visible at rest" cannot both hold across a move between
## differently-sized pictures, so the discontinuity is spent on one cut at the end.
## The arrival is therefore NOT in this function. The cross-fade itself is driven by `_apply()`
## from the same `elapsed`/`total` pair — `sample_at()` stays pure and engine-free.
static func sample_at(elapsed: float, total: float, source_rect: PictureRect,
		dest_rect: PictureRect, window_size: Vector2, settings: PlayerSettings) -> Sample:
	var s := Sample.new()

	if settings.wall_reduced_motion:
		# The camera does not move: the source's resting pose for every `elapsed`, and Main cuts
		# it to the destination on landing.
		s.camera_position = source_rect.centre
		s.camera_zoom = WallPicture.focused_scale(source_rect.size, window_size,
				settings.wall_overfill_margin)
		# ⚠ NOT derived from a visible-rect test. The source overfills the window at rest, so a
		# geometric test would call the destination never visible and never unlock input or unpause
		# its screen. A cross-fade has no travel to wait through and the destination is visibly
		# fading in, so all three are true by construction from the first frame.
		s.source_frame_in_view = true
		s.dest_visible = true
		s.dest_frame_in_view = true
		return s

	# With Info mode on a transition is a pure TRAVEL: zoom is CONSTANT throughout, held at the
	# SOURCE's info-zoom scale — one fixed value, never blended toward the destination's, which
	# would differ for differently-sized pictures. Position still travels in a straight line
	# between each picture's own info-zoom POSITION, so the camera arrives at the destination's
	# bottom-frame reveal.
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

	# Position: travel is the ONLY phase that moves it. Straight line, on the authored travel
	# curve (`wall_travel_trans`/`_ease`).
	if t <= travel_start:
		s.camera_position = source_rect.centre
	elif t >= travel_end:
		s.camera_position = dest_rect.centre
	else:
		var travel_t := (t - travel_start) / (travel_end - travel_start)
		var eased : float = Tween.interpolate_value(0.0, 1.0, travel_t, 1.0,
				settings.wall_travel_trans, settings.wall_travel_ease)
		s.camera_position = source_rect.centre.lerp(dest_rect.centre, eased)

	# Zoom: zoom-out and zoom-in are the only phases that move it, composed in sequence -- the
	# zoom-out leg lerps start_zoom -> wide_zoom on `wall_zoom_trans`/`wall_zoom_out_ease`, then the
	# zoom-in leg lerps THAT result -> dest_zoom on `wall_zoom_in_ease`. Flat at wide_zoom for the pure-travel
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
			settings.wall_zoom_trans, settings.wall_zoom_out_ease)
	var after_out := lerpf(start_zoom, wide_zoom, out_progress)
	var in_span := 1.0 - zoom_in_start
	var in_progress := 0.0 if in_span <= 0.0 else clampf((t - zoom_in_start) / in_span, 0.0, 1.0)
	in_progress = Tween.interpolate_value(0.0, 1.0, in_progress, 1.0,
			settings.wall_zoom_trans, settings.wall_zoom_in_ease)
	s.camera_zoom = lerpf(after_out, dest_zoom, in_progress)

	var visible := _visible_rect(s.camera_position, s.camera_zoom, window_size)
	s.source_frame_in_view = visible.encloses(WallPacker.frame_outer_rect(source_rect))
	s.dest_visible = visible.intersects(
			Rect2(dest_rect.centre - dest_rect.size * 0.5, dest_rect.size))
	s.dest_frame_in_view = visible.encloses(WallPacker.frame_outer_rect(dest_rect))
	return s

## Starts a transition from `source` to `dest`, animating `camera`. A no-op — no tween at all — if
## `dest` is already the current picture, or if a transition is already active.
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
	# ⚠ A FROZEN COPY, not the live resource. `sample_at()` branches on `wall_reduced_motion` and
	# `wall_info_mode` and the tween callback re-enters it every frame, so with the live object
	# here, toggling either knob MID-MOVE switches the camera's whole model inside the running
	# tween and it jumps for the rest of the move. A move's CHARACTER is fixed when it is
	# requested, the same way its destination and its clock are.
	# Safe to `duplicate()`: `PlayerSettings` setters only emit `settings_changed`, and signal
	# connections are not copied, so the copy cannot reach `SettingsManager`'s save-to-disk.
	_settings = settings.duplicate()
	_total = total_duration(settings)
	_source_pause_time = _find_source_pause_time(_total, _source_rect, _dest_rect, _window_size,
			_settings)
	_input_unlock_time = _find_input_unlock_time(_total, _source_rect, _dest_rect, _window_size,
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

## Points a mid-flight transition at new geometry and continues — never restarts, never cuts the
## tween short, never touches `_dest_id`, `_total` or any latched boundary. A no-op while inactive.
## Because the tween callback reads the geometry fields fresh every frame, swapping them here means
## the next `_apply()` already samples the new geometry; the resulting discontinuity is bounded by
## the resize's own shift, never a snap back to the source.
##
## Also RECOMPUTES both crossing times: a time computed against the OLD rects is meaningless once
## they change. Harmless after a latch has already fired, since that check is then skipped.
func retarget(new_source_rect: PictureRect, new_dest_rect: PictureRect,
		new_window_size: Vector2) -> void:
	if not is_active: return
	_source_rect = new_source_rect
	_dest_rect = new_dest_rect
	_window_size = new_window_size
	_source_pause_time = _find_source_pause_time(_total, _source_rect, _dest_rect, _window_size,
			_settings)
	_input_unlock_time = _find_input_unlock_time(_total, _source_rect, _dest_rect, _window_size,
			_settings)

## Applies one Sample to the camera and latches each pause/unpause/input-unlock boundary the
## instant its condition first holds. Every latch is one-way.
## The source latch fires on `elapsed >= _source_pause_time` — a precomputed TIME, not a re-check
## of `s.source_frame_in_view` — so sparse real-frame sampling cannot skip it: the tween always
## reaches `_total`, and `_source_pause_time <= _total` by that function's backstop.
##
## Under `wall_reduced_motion` this is also where the cross-fade lives: `source`/`dest` are already
## in scope for the pause/unpause handoff, so screen opacity needs no second path in `Main`. Linear
## in `elapsed/_total`, reaching exactly (0, 1) as the tween lands. `focus()`/`unfocus()` reset both
## screens to fully opaque regardless, so a run with or without reduced motion leaves the same
## resting alpha.
func _apply(camera: Camera2D, source: WallPicture, dest: WallPicture, s: Sample,
		elapsed: float) -> void:
	camera.position = s.camera_position
	camera.zoom = Vector2.ONE * s.camera_zoom
	if _settings.wall_reduced_motion:
		var t := 0.0 if _total <= 0.0 else clampf(elapsed / _total, 0.0, 1.0)
		source.set_screen_alpha(1.0 - t)
		dest.set_screen_alpha(t)
	if elapsed >= _source_pause_time and not _source_paused:
		_source_paused = true
		if source.screen_root: source.screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	if s.dest_visible and not _dest_unpaused:
		_dest_unpaused = true
		if dest.screen_root: dest.screen_root.process_mode = Node.PROCESS_MODE_ALWAYS
	if elapsed >= _input_unlock_time and not _input_unlocked:
		_input_unlocked = true
		input_unlocked.emit()
