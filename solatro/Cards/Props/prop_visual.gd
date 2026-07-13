class_name PropVisual
extends Node2D
## The view-side twin of a PropData: pure draw + trajectory params, NO CardData/PropData
## retention (SUIT_PROPS_PLAN §4.3). PropLayer owns the interpolation state (from/target/t)
## and drives `position` every frame; this class only says how a prop LOOKS and the SHAPE of
## its path. Placeholder art draws to exactly `art_size`, so real textures later swap in by
## matching the same footprint.

@export var art_size : Vector2 = Vector2(16, 16)
## Kind-colored placeholder fill; subclasses override.
@export var color : Color = Color.WHITE
## Rotate the whole visual to point along its current travel direction (set by retarget). ON for
## directional art like the knife blade (its tip is drawn toward +x, so travelling left flips it);
## OFF for radially symmetric kinds (hoop/ball) that shouldn't spin as they change rows.
@export var face_travel : bool = false
## Peak of the parabolic hump travel_curve adds to a leg (ballistic ball/fire arcs). 0 = a
## straight line — ONE shared movement function for every kind; only this shape knob differs.
@export var arc_height : float = 0.0

var fire_tips : int = 0                  ## flame ticks overlaid on any kind (PropData.fire_stacks)

# --- interpolation state, OWNED by PropLayer._process (never locks in a duration) ---
var from : Vector2
var target : Vector2
var t : float = 1.0
## Data ticks the current from->target leg spans (the prop's ticks_per_slot): a slow prop
## crosses its slot CONTINUOUSLY over all of them instead of sprinting in one and freezing.
var span_ticks : float = 1.0
## The share of the leg this data tick expects covered (ratcheted +1/span per tick by
## PropLayer); the tick completes when t reaches it, so tick sync never waits a full leg.
var t_goal : float = 1.0
## Set at spawn: route travelers (rows/columns) exit past the board edge on despawn;
## ballistic single-target props poof IN PLACE at their target (continuing along their
## card->target diagonal read as flying off in a random direction).
var exits_into_void : bool = false
## The slot this visual's CURRENT geometry hangs off — its latest slot target, the route entry
## while staged, or the last slot during a void exit. PropLayer re-pins from/target/position
## to this slot's LIVE point every frame (_repin): container relayouts (score labels growing,
## focus resizing rows, rebuilds) move slot centers mid-flight, and geometry locked to stale
## pixels walks a diagonal off its row. MIN = nothing to follow (hold raw pixels).
var anchor_coord : Vector3i = Vector3i.MIN
## The anchor slot's last-known content-local point; _repin shifts the leg by the delta to
## the live point and refreshes this cache.
var anchor_point : Vector2
## This prop's personal offset from every slot point it travels through (a PropFormation pick,
## set once at spawn): a batch spreads into a staggered volley instead of a single-file line.
var lane_offset : Vector2 = Vector2.ZERO

## Begin a fresh travel from the current position to `point`, spread over `ticks` data ticks;
## t restarts so the live per-frame drive re-times it against the current tick duration.
## anchor_coord deliberately persists — a void exit keeps riding its last slot; callers that
## enter a NEW slot re-pin it right after.
func retarget(point: Vector2, ticks : float = 1.0) -> void:
	from = position
	target = point
	t = 0.0
	span_ticks = maxf(ticks, 1.0)
	t_goal = 1.0 / span_ticks
	if face_travel:
		var dir := target - from
		if dir.length() > 1.0:
			rotation = dir.angle()

## Instant reposition for teleports — never lerp across the board; flash to signal the jump.
func relocate_to(point: Vector2) -> void:
	position = point
	from = point
	target = point
	t = 1.0
	span_ticks = 1.0
	t_goal = 1.0
	_flash()

## Shape of the path (NOT its timing) — THE one movement function every kind shares: a
## straight line plus an optional parabolic hump (arc_height; peak at u = 0.5) for the
## ballistic kinds. Kinds differ ONLY by this knob, never by their own movement code.
## No hump on a zero-length leg: the stationary staged pose is retargeted to itself, and
## arcing it read as the ball hopping in place at its card before the real flight.
func travel_curve(a: Vector2, b: Vector2, u: float) -> Vector2:
	var p := a.lerp(b, u)
	if arc_height > 0.0 and not a.is_equal_approx(b):
		p.y -= arc_height * (4.0 * u * (1.0 - u))
	return p

func _flash() -> void:
	var tw := create_tween()
	modulate = Color(2, 2, 2, 1)
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)

func _process(_delta: float) -> void:
	queue_redraw()   # fire tips / motion; cheap for the handful of live props

func _draw() -> void:
	_draw_body()
	_draw_fire_tips()

## Placeholder body — subclasses override with a kind-distinct primitive at `art_size`.
func _draw_body() -> void:
	draw_circle(Vector2.ZERO, art_size.x * 0.5, color)

## Small flame ticks fanned above the body, one per stack (shared across all kinds).
func _draw_fire_tips() -> void:
	if fire_tips <= 0: return
	var flame := Color(1.0, 0.55, 0.1)
	var top := -art_size.y * 0.5
	for i in fire_tips:
		var x := (i - (fire_tips - 1) * 0.5) * 4.0
		var tip := Vector2(x, top - 5.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 2.0, top), Vector2(x + 2.0, top), tip]), flame)
