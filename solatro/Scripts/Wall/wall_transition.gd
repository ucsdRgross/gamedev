class_name WallTransition
extends RefCounted
#The camera's move between two pictures and its phase clock. `sample_at()` is the pure core; one
#Tween bound to the ALWAYS camera drives it and LATCHES each boundary one way. The destination must
#already be BUILT before `request()`, which never awaits. `Main._focus_picture()` owns the pictures.

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

#A `request()` while a move is running is ignored outright; `retarget()` is the one exception, and
#it changes only geometry, never `_dest_id` or the elapsed clock.
var is_active : bool = false
var _dest_id : StringName = &""
var _source_paused := false
var _dest_unpaused := false
var _input_unlocked := false
var _dest_live := false
## How far into the move the camera's last applied sample was, in seconds.
var _elapsed : float = 0.0

#Instance fields rather than closure-captured locals, so `retarget()` can swap them in place while
#the same Tween keeps reading them every frame.
var _source_rect : PictureRect
var _dest_rect : PictureRect
var _window_size : Vector2
var _settings : PlayerSettings
var _total : float

## The elapsed instant at which the destination goes live, `live_fraction()` of the move.
var _live_time : float = 0.0
#⚠ A PRECOMPUTED TIME, NOT A PER-FRAME RE-CHECK of `source_frame_in_view`: that condition opens and
#CLOSES again well before landing, so sparse frames can step over it; a time is always caught up.
var _source_pause_time : float = 0.0
## When input comes back: a time, for the same reason `_source_pause_time` is one.
var _input_unlock_time : float = 0.0
## Fired once, when the tween completes and lands on the requested picture.
signal landed(picture_id: StringName)
## Fired once, the instant input comes back. Callers listen rather than polling `is_active`.
signal input_unlocked
## Fired once, at `live_fraction()` of the move: the destination draws and runs live from here.
signal destination_live

#⚠ NEVER `Game.get_delay()`, which compresses to 0.0 on an act cancel.
static func total_duration(settings: PlayerSettings) -> float:
	return settings.base_delay * settings.wall_transition_delay

#The destination draws and runs live from the start of its zoom-in, when the camera shows the
#picture and closes on it (owner ruling). Every route into a picture reads this one fraction.
static func live_fraction(settings: PlayerSettings) -> float:
	var zoom_in_start : float = phase_bounds(settings)["zoom_in_start"]
	return zoom_in_start

#The zoom-out plateau fits the SOURCE's frame alone, plus a margin: fitting both frames zoomed a far
#jump out to most of the wall. The destination is reached by travel at this plateau, so a far jump
#reads as a longer slide, not a bigger zoom.
static func _wide_zoom(source_rect: PictureRect, window_size: Vector2,
		margin_fraction: float) -> float:
	var source_frame := WallPacker.frame_outer_rect(source_rect)
	var needed := source_frame.size + source_rect.size * margin_fraction
	return minf(window_size.x / needed.x, window_size.y / needed.y)

#The one home for "what is the camera showing right now". ⚠ `Camera2D.zoom` is DIRECT
#MAGNIFICATION: the visible span is `window_size / zoom`, never `window_size * zoom`.
static func visible_rect(position: Vector2, zoom: float, window_size: Vector2) -> Rect2:
	var size := window_size / zoom
	return Rect2(position - size * 0.5, size)

#The three authored fractions sum PAST 1.0 on purpose; the excess is split across the two
#boundaries so zoom-in always lands exactly at 1.0.
static func phase_bounds(settings: PlayerSettings) -> Dictionary:
	var overlap := (settings.wall_zoom_out_fraction + settings.wall_travel_fraction
			+ settings.wall_zoom_in_fraction - 1.0) * 0.5
	var zoom_out_end := settings.wall_zoom_out_fraction
	var travel_start := zoom_out_end - overlap
	var travel_end := travel_start + settings.wall_travel_fraction
	var zoom_in_start := travel_end - overlap
	return {"zoom_out_end": zoom_out_end, "travel_start": travel_start, "travel_end": travel_end,
			"zoom_in_start": zoom_in_start}

#⚠ A SCAN, NOT A BISECTION: the crossing opens and closes again, so it is no step function.
#BACKSTOP: with no crossing at all, pause by the end of the zoom-out -- "exactly one screen root is
#ALWAYS" outranks hitting the precise instant.
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

#⚠ The destination's whole frame fits only in the wide middle of the move -- a focused picture
#overfills the window at rest -- so a per-frame check can step over it. BACKSTOP `total`: input
#never stays locked longer than the move itself.
static func _find_input_unlock_time(total: float, source_rect: PictureRect, dest_rect: PictureRect,
		window_size: Vector2, settings: PlayerSettings) -> float:
	for i : int in (_CROSSING_SCAN_STEPS + 1):
		var elapsed := total * float(i) / float(_CROSSING_SCAN_STEPS)
		var s := sample_at(elapsed, total, source_rect, dest_rect, window_size, settings)
		if s.dest_frame_in_view:
			return elapsed
	return total

#Pure and engine-free, so it can be scanned synchronously. ⚠ Under `wall_reduced_motion` the camera
#holds the SOURCE's pose while the screens cross-fade (`_apply()`), and `Main._focus_picture()` cuts
#to the destination at the end: the arrival is NOT in this function.
static func sample_at(elapsed: float, total: float, source_rect: PictureRect,
		dest_rect: PictureRect, window_size: Vector2, settings: PlayerSettings) -> Sample:
	var s := Sample.new()

	if settings.wall_reduced_motion:
		s.camera_position = source_rect.centre
		s.camera_zoom = WallPicture.focused_scale(source_rect.size, window_size,
				settings.wall_overfill_margin)
		s.source_frame_in_view = true
		s.dest_visible = true
		s.dest_frame_in_view = true
		return s

	var bounds := phase_bounds(settings)
	var zoom_out_end : float = bounds["zoom_out_end"]
	var travel_start : float = bounds["travel_start"]
	var travel_end : float = bounds["travel_end"]
	var zoom_in_start : float = bounds["zoom_in_start"]

	var t := 0.0 if total <= 0.0 else clampf(elapsed / total, 0.0, 1.0)

	if t <= travel_start:
		s.camera_position = source_rect.centre
	elif t >= travel_end:
		s.camera_position = dest_rect.centre
	else:
		var travel_t := (t - travel_start) / (travel_end - travel_start)
		var eased : float = Tween.interpolate_value(0.0, 1.0, travel_t, 1.0,
				settings.wall_travel_trans, settings.wall_travel_ease)
		s.camera_position = source_rect.centre.lerp(dest_rect.centre, eased)

	var start_zoom := WallPicture.focused_scale(source_rect.size, window_size,
			settings.wall_overfill_margin)
	var dest_zoom := WallPicture.focused_scale(dest_rect.size, window_size,
			settings.wall_overfill_margin)
	var wide_zoom := _wide_zoom(source_rect, window_size, settings.wall_frame_reveal_margin)
	var out_progress := 0.0 if zoom_out_end <= 0.0 else clampf(t / zoom_out_end, 0.0, 1.0)
	out_progress = Tween.interpolate_value(0.0, 1.0, out_progress, 1.0,
			settings.wall_zoom_trans, settings.wall_zoom_out_ease)
	var after_out := lerpf(start_zoom, wide_zoom, out_progress)
	var in_span := 1.0 - zoom_in_start
	var in_progress := 0.0 if in_span <= 0.0 else clampf((t - zoom_in_start) / in_span, 0.0, 1.0)
	in_progress = Tween.interpolate_value(0.0, 1.0, in_progress, 1.0,
			settings.wall_zoom_trans, settings.wall_zoom_in_ease)
	s.camera_zoom = lerpf(after_out, dest_zoom, in_progress)

	var visible := visible_rect(s.camera_position, s.camera_zoom, window_size)
	s.source_frame_in_view = visible.encloses(WallPacker.frame_outer_rect(source_rect))
	s.dest_visible = visible.intersects(
			Rect2(dest_rect.centre - dest_rect.size * 0.5, dest_rect.size))
	s.dest_frame_in_view = visible.encloses(WallPacker.frame_outer_rect(dest_rect))
	return s

## Starts a move from `source` to `dest`; a no-op onto the current picture or while one is active.
func request(camera: Camera2D, source: WallPicture, source_rect: PictureRect, dest: WallPicture,
		dest_rect: PictureRect, window_size: Vector2, settings: PlayerSettings) -> void:
	if dest_rect.id == source_rect.id: return
	if is_active: return
	is_active = true
	_dest_id = dest_rect.id
	_source_paused = false
	_dest_unpaused = false
	_input_unlocked = false
	_dest_live = false
	_source_rect = source_rect
	_dest_rect = dest_rect
	_window_size = window_size
	_settings = settings.duplicate()
	_total = total_duration(settings)
	_live_time = live_fraction(_settings) * _total
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

#Points a move in flight at new geometry and carries on: never restarts, never touches `_dest_id`,
#`_total` or a latch. The crossing times are recomputed, since a time against the OLD rects is
#meaningless; harmless once a latch has fired.
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

#Every latch is one-way. Under `wall_reduced_motion` this is also the cross-fade, linear in
#`elapsed/_total` and reaching exactly (0, 1) as the tween lands; `focus()`/`unfocus()` reset both
#screens to opaque regardless.
func _apply(camera: Camera2D, source: WallPicture, dest: WallPicture, s: Sample,
		elapsed: float) -> void:
	_elapsed = elapsed
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
	if elapsed >= _live_time and not _dest_live:
		_dest_live = true
		destination_live.emit()
	if elapsed >= _input_unlock_time and not _input_unlocked:
		_input_unlocked = true
		input_unlocked.emit()
