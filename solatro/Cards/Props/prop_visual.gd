@tool   # editor-instantiable: the formation editor previews real prop art over its points
class_name PropVisual
extends Node2D
## The view-side twin of a PropData: pure draw + trajectory params, NO CardData/PropData
## retention (SUIT_PROPS_PLAN §4.3). PropLayer owns the interpolation state (from/target/t)
## and drives `position` every frame; this class only says how a prop LOOKS and the SHAPE of
## its path. Art draws to exactly `art_size`, which every textured kind derives from its sheet's
## frame size times ART_PIXEL_SCALE — never a raw pixel number (see that constant).

@export var art_size : Vector2 = Vector2(16, 16)
## The prop's on-screen BODY footprint in unscaled pixels — filled in MANUALLY per kind next to
## its art (the same way CardVisual.CARD_SIZE is hardcoded), NOT derived from drawing code.
## PropLayer's split/bracket logic rect-tests this against card footprints: a prop is "over"
## whatever its body COVERS, never just the point under its center (a ring hanging between two
## cards covers both). Every kind currently sets it equal to its `art_size` — the drawn footprint IS
## the body — but they stay separate knobs so a kind with lots of empty margin can claim less.
@export var body_size : Vector2 = Vector2(16, 16)
## Kind-colored fill for the kinds still drawn as a primitive (firework); textured kinds ignore it.
@export var color : Color = Color.WHITE
## MIRROR the art left↔right to face its travel direction (set by retarget). Every directional prop
## sheet is authored pointing LEFT, and a prop heading right is that art FLIPPED — never rotated: a
## turn would carry its top and bottom around with it, and the art's top must stay its top (owner
## 2026-07-27). OFF for the kinds with no heading — ball/fire (radially symmetric) and the hoop,
## whose two halves are a DEPTH split (far/near side of the ring), not a direction.
@export var face_travel : bool = false
## Peak of the parabolic hump travel_curve adds to a leg (ballistic ball/fire arcs). 0 = a
## straight line — ONE shared movement function for every kind; only this shape knob differs.
@export var arc_height : float = 0.0

## Fire carried by this prop (PropData.fire_stacks), drawn by the shader FX below. The setter
## resyncs the effect, so a prop catching fire mid-flight lights up without waiting for a respawn.
var fire_stacks : int = 0:
	set(value):
		if fire_stacks == value: return
		fire_stacks = value
		_sync_fx()

## Shader effects for this prop — built at runtime, never authored into a scene. Split props get
## one attachment per HALF instead of one on the body, so the ring's back-arc flames sit behind
## the occupied card exactly as its back arc does.
var fx : FxAttachment
var fx_back : FxAttachment
var fx_front : FxAttachment

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
## This prop's personal offset from every slot point it travels through, in PIXELS — derived
## LIVE every frame by PropLayer._refresh_lane_offset from formation_point + the current
## card_scale / card_separation_scale settings (owner report 2026-07-15: capture-at-spawn made
## props ignore mid-run setting changes the cards respond to). ZERO when the kind has no
## authored formation. A batch reads as a condensed formation instead of a single-file line.
var lane_offset : Vector2 = Vector2.ZERO
## The assigned PropFormationData point in STORED space (full-card normalized when
## formation_spread; raw card space otherwise), set once at spawn. The live pixel offset above
## is re-projected from this.
var formation_point : Vector2 = Vector2.ZERO
## The drawn formation's spread_by_separation flag (whether formation_point.y re-projects into
## the live separation strip).
var formation_spread : bool = false
## Whether this prop was assigned a formation point at all (no set authored = false = offset ZERO).
var has_formation_point : bool = false

## Prop art was authored against the DEFAULT card_scale — the live prop scale is
## card_scale / this, so props grow and shrink WITH the cards (owner report 2026-07-15) while
## keeping their authored size at default settings. PropLayer writes `scale` every frame; the
## formation editor applies the same rule to its preview (preview_scale stands in for card_scale).
const AUTHORED_CARD_SCALE := 2.5

## Drawn size per SOURCE TEXEL of prop art. A card draws its own pixel art one texel per UNSCALED
## unit and is then scaled by `card_scale`; a prop is scaled by `card_scale /
## AUTHORED_CARD_SCALE` — so a prop texel is the same size on screen as a card texel only when the
## prop draws its frame at `frame_px * AUTHORED_CARD_SCALE`. Every kind sizes its art through this
## constant and never with raw pixel numbers, so all of the game's pixel art stays ONE pixel size
## at every card_scale setting (owner 2026-07-27).
const ART_PIXEL_SCALE := AUTHORED_CARD_SCALE

## True while the art is mirrored (the prop is heading right). Only meaningful with face_travel on;
## _process redraws every frame, so setting it needs no explicit invalidation.
var flipped : bool = false

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
		# Only the horizontal sense matters: the art mirrors, it never turns, so a leg with no x
		# travel (a ballistic drop, a stationary staged pose) keeps the facing it already had.
		if absf(dir.x) > 1.0:
			flipped = dir.x > 0.0

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
	# Flash decay respects the live pacing (fraction of get_delay, PlayerSettings) — never a
	# fixed wall-clock length. Editor preview (@tool, no autoloads) keeps a small default.
	var secs := 0.15
	if not Engine.is_editor_hint():
		var game := CardEnvironment.get_current_game()
		secs = (game.get_delay() if game else SettingsManager.settings.base_delay) \
				* SettingsManager.settings.prop_flash_fraction
	var tw := create_tween()
	modulate = Color(2, 2, 2, 1)
	tw.tween_property(self, "modulate", Color.WHITE, secs)

func _process(_delta: float) -> void:
	queue_redraw()   # fire tips / motion; cheap for the handful of live props

func _draw() -> void:
	# A split prop draws its two arcs on dedicated CardLayer nodes that bracket the occupied card
	# ONLY while it is actually over a card (_split_active, set by PropLayer). When it is NOT over a
	# card (row edge, empty slot, between slots, fading/exiting) the half nodes are hidden and the
	# WHOLE body draws here on the PropVisual (PropLayer, above all cards) like a normal prop — so
	# the ring never floats on top from stale half-node ordering. Editor preview (@tool) has no half
	# nodes, so it always draws the whole body. Non-split props always draw their whole body here.
	if not has_back_half() or Engine.is_editor_hint() or not _split_active:
		_draw_body()

## Full-shape body — subclasses override with their sprite (or a kind-distinct primitive) at
## `art_size`. For split props this is used for the editor preview (and the non-split default
## draw); the runtime split is drawn by _draw_back()/_draw_front() onto the two half nodes.
func _draw_body() -> void:
	draw_circle(Vector2.ZERO, art_size.x * 0.5, color)

## Draw one sprite frame, mirrored when the art faces the other way (face_travel). `into` is the
## canvas ISSUING the command — self for a whole body, the half node for a split half (the same
## rule as _draw_back). `dest` is in prop-local units, so callers size it off `art_size`.
##
## The mirror is a DRAW transform, never a negative node scale: FxAttachment is a child of this
## node, so scaling the node would mirror its shader quads too — and the FX pixel grid is not
## allowed to move (FX_SHADER_PLAN §0b, universal rule).
func _draw_art(into: CanvasItem, sheet: Texture2D, src: Rect2, dest: Rect2) -> void:
	if flipped:
		# Mirror about the prop's own origin, which every kind centres its art on, so the art's
		# top and bottom stay exactly where they were.
		into.draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
	into.draw_texture_rect_region(sheet, dest, src)
	if flipped:
		into.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Source rect of one frame of a uniform sprite sheet — the draw_texture_rect_region twin of
## CardModifier.update_polygon_uv_frame's UV window, so a prop frames a shared sheet (the suit pips)
## exactly the way a card does.
static func sheet_frame(sheet: Texture2D, h_frames: int, v_frames: int, frame: int) -> Rect2:
	var frame_px := sheet.get_size() / Vector2(float(h_frames), float(v_frames))
	return Rect2(Vector2(float(frame % h_frames), float(frame / h_frames)) * frame_px, frame_px)

# --- front/back split (structural layering, LAYERING.md) ----------------------
## A split prop (e.g. the hoop) renders as TWO nodes that BRACKET the card it currently occupies in
## CardLayer — the back half just below the card, the front half just above it — so the card passes
## THROUGH the ring: back arc behind the card (but above the row above), front arc in front of the
## card (but BELOW the row below). Default: no split — the whole body draws on the PropVisual (on
## PropLayer, above all cards), exactly today's behavior. The half nodes live in the STABLE
## CardLayer (never parented to a card, or they would inherit its jump/drag/float); PropLayer
## writes their transform from the prop each frame.
var back_node : Node2D
var front_node : Node2D
## True only while PropLayer is bracketing this prop's halves around an occupied card. Drives
## _draw (whole body when false) so the ring is never blank AND never floats on top off-card.
var _split_active : bool = false

## Subclasses opt in; default keeps the whole body on the PropVisual (no half nodes are made).
func has_back_half() -> bool:
	return false

## PropLayer sets this each frame from occupancy; the redraw switches between split arcs (on the
## half nodes) and the whole body (here) so the two views never both show.
func set_split_active(active: bool) -> void:
	if _split_active == active: return
	_split_active = active
	queue_redraw()
	_sync_fx()   # the flames follow the body: whole-prop quad off, bracketed halves on

## The arc drawn BEHIND the occupied card. Called from a half node's _draw, so it must issue its
## draw_* commands on `into` (the half node), NOT on self — drawing on a node outside its own
## _draw() is illegal in Godot. Default nothing.
func _draw_back(_into: CanvasItem) -> void:
	pass

## The arc drawn IN FRONT of the occupied card (but below the row below). Same `into` rule as
## _draw_back. Default nothing (split subclasses override).
func _draw_front(_into: CanvasItem) -> void:
	pass

## Lazily build the back/front half nodes. PropLayer owns their parent + transform.
func ensure_back() -> Node2D:
	if not has_back_half():
		return null
	if not back_node:
		back_node = _PropHalf.new()
		(back_node as _PropHalf).prop = self
		(back_node as _PropHalf).is_front = false
	return back_node

func ensure_front() -> Node2D:
	if not has_back_half():
		return null
	if not front_node:
		front_node = _PropHalf.new()
		(front_node as _PropHalf).prop = self
		(front_node as _PropHalf).is_front = true
	return front_node

## Renders one half of its owning PropVisual. Parented to CardLayer (not the prop), so PropLayer
## writes its global_position/rotation/scale each frame — it must not inherit the prop's transform.
class _PropHalf extends Node2D:
	var prop : PropVisual
	var is_front : bool = false
	func _draw() -> void:
		if not is_instance_valid(prop): return
		if is_front: prop._draw_front(self)
		else: prop._draw_back(self)
	func _process(_d: float) -> void:
		queue_redraw()

# --- shader FX ----------------------------------------------------------------
## Which silhouette this kind's effects decorate. A blade and a card are both boxes; the hoop
## overrides to a ring. Adding a kind is one override here and one branch in the shader.
func fx_shape() -> FxAttachment.Shape:
	return FxAttachment.Shape.BOX

## Build this prop's FX attachments. Runtime only and OWNERLESS: this script is @tool and the
## formation editor instantiates PropVisuals live, where there is no game to read a pacing from
## and any owned child would be written into a scene on disk.
func _ready() -> void:
	if Engine.is_editor_hint(): return
	fx = _make_fx(self, FxAttachment.Half.WHOLE)
	if has_back_half():
		# The halves hang off the BRACKET nodes, so each half's flames inherit that half's place
		# in CardLayer's order — which is the whole point of the bracket.
		fx_back = _make_fx(ensure_back(), FxAttachment.Half.BACK)
		fx_front = _make_fx(ensure_front(), FxAttachment.Half.FRONT)
	_sync_fx()

## One attachment, added LAST under `host` so it draws above that host's own art.
func _make_fx(host: Node2D, half: FxAttachment.Half) -> FxAttachment:
	var att := FxAttachment.new()
	att.name = "Fx"
	# host_rotates = false for EVERY prop: directional art mirrors instead of turning (face_travel),
	# so no prop silhouette ever leaves its box and none of them pays the circumscribed quad bound.
	att.configure(body_size, false, fx_shape(), half)
	host.add_child(att)
	return att

## Point every attachment at this prop's current fire, and show whichever set matches the split
## state — the same rule _draw uses, so the flames are never on a body that is not drawn.
func _sync_fx() -> void:
	if not fx: return
	var whole : Array[FxRequest] = []
	if fire_stacks > 0: whole.append(FxFire.request(&"fire", fire_stacks, PROP_FIRE_STYLE))
	var split := has_back_half() and _split_active
	fx.visible = not split
	fx.sync(whole)
	for half : FxAttachment in [fx_back, fx_front]:
		if not half: continue
		half.visible = split
		half.sync(whole)

const PROP_FIRE_STYLE := preload("res://Shaders/Styles/fire_prop.tres")
