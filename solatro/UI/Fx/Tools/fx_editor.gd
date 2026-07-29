@tool
class_name FxEditor
extends Node2D
## LIVE FX TUNING IN THE EDITOR — open `fx_editor.tscn`, edit an `FxStyle` in the inspector, watch
## the real shaders react (owner 2026-07-28: *"a way to visualize fire and juggling purely in editor
## for debugging purposes, similar to formation editor, so I can fine tune parameters"*).
##
## Every subject is on screen at once: a burning card, a juggling card, and the REAL prop visuals
## (hoop, knife, ball, fire) each carrying fire on their own silhouette — the hoop as an ellipse,
## the knife as its little box — because a style tuned on a card reads differently on a prop, whose
## art units are ~2.5x smaller (§4h).
##
## It renders through the SHIPPING path — `FxFire.request()` / `FxJuggle.requests()` into a real
## `FxAttachment`, and the props are the actual `PropVisual` subclasses — never a private copy of
## the maths. A tuning tool that draws its own version of the effect is a tool that lies, and this
## project already has the scar: two copies of the arc maths is what made flames trail their balls
## (ARCHITECTURE_REVIEW §4g).
##
## What it is NOT: a test. Nothing here asserts. The pixel assertions live in
## `Tests/Visual/test_pixels.gd`, and the reviewable captures in `Tests/Visual/fx_snapshot.tscn`.
##
## ⚠ EDITOR FACTS, each of which cost time to learn:
##  * **Every FX script it touches must be `@tool`.** A non-tool script loads in the editor as a
##    PLACEHOLDER: calling a method on it fails with *"Attempt to call a method on a placeholder
##    instance"*, so `FxStyle.apply()` never runs and every quad renders with default uniforms —
##    pure white. Worse, saving a `.tres` whose script is a placeholder writes back only the
##    properties the editor could see and SILENTLY DROPS THE REST; that is how `fire_card.tres` lost
##    its `pixel` and `dither` on 2026-07-28. FxStyle, FxRequest, FxFire, FxJuggle, ParticleSpec,
##    ParticleEngine and FxAttachment are all `@tool` for this reason. Do not remove it from any of
##    them.
##  * The editor instantiates NO autoloads, so `SettingsManager` / `CardEnvironment` are absent.
##    `FxAttachment.settings()` stands in with the shipped defaults; `pacing()` already returns 1.0
##    with no Game, so the clock here runs at the game's un-compressed speed.
##  * Every node this builds is OWNERLESS and rebuilt from scratch. An owned child would be SAVED
##    into fx_editor.tscn by the editor — the same trap that keeps CardVisual from building FX in
##    the editor at all.

## Rebuild whenever any knob moves. Every @export below shares this.
func _touch(_v : Variant = null) -> void:
	_dirty = true

var _dirty := true
var _hosts : Array[Node2D] = []
var _particles : ParticleEngine = null

@export_group("Fire")
## The card-hosted flame — the resource you actually tune. Edit it and the preview re-pushes.
@export var fire_style : FxStyle = preload("res://Shaders/Styles/fire_card.tres"):
	set(v): fire_style = v; _touch()
## The PROP-hosted flame, in prop art units. Every prop on the right uses this one.
@export var prop_fire_style : FxStyle = preload("res://Shaders/Styles/fire_prop.tres"):
	set(v): prop_fire_style = v; _touch()
## Burning stacks. The interesting values are 1 (a single flame), 12 (the crown is full —
## FxFire.FX_MAX_TENDRILS) and 40+ (past the auto-merge threshold, overflow > 1.5).
@export_range(0, 200, 1) var fire_stacks : int = 12:
	set(v): fire_stacks = v; _touch()

@export_group("Juggling")
@export var juggle_style : FxStyle = preload("res://Shaders/Styles/juggle_default.tres"):
	set(v): juggle_style = v; _touch()
## The fire that rides the balls — a different style from the card's, in PROP art units.
@export var ball_fire_style : FxStyle = preload("res://Shaders/Styles/fire_ball.tres"):
	set(v): ball_fire_style = v; _touch()
## Watch 2, 4 and 6 especially: those are the counts where the ball count equals the ARC count, and
## where a per-ball direction mirror would send every ball the same way (fixed 2026-07-28).
@export_range(0, 200, 1) var ball_count : int = 6:
	set(v): ball_count = v; _touch()
## How many balls are ALIGHT. Ball fire is per ball and is never read from the card's StatusBurning
## (rulings 3 / 21) — this is the knob that puts flames on BALLS rather than on the card.
@export_range(0, 200, 1) var lit_balls : int = 2:
	set(v): lit_balls = v; _touch()
@export_range(1, 50, 1) var lit_level : int = 6:
	set(v): lit_level = v; _touch()

@export_group("Stage")
## Card-sized host (CardVisual.CARD_SIZE). The props size themselves from their own sheets.
@export var card_body : Vector2 = Vector2(38, 50):
	set(v): card_body = v; _touch()
## Zoom the whole preview. Art is authored at one pixel size; this only magnifies the view.
@export_range(1.0, 12.0, 0.5) var zoom : float = 4.0:
	set(v): zoom = v; _touch()
## Art units between subjects.
@export_range(30.0, 200.0, 1.0) var spacing : float = 70.0:
	set(v): spacing = v; _touch()
## Body outlines, so you can see where a flame's base sits relative to its silhouette.
@export var show_outlines : bool = true:
	set(v): show_outlines = v; queue_redraw()
## Fill the CARD hosts with a solid face (the props draw their own art). Without it the flame's base
## is drawn over nothing, and `inner_alpha` — the overlay opacity that keeps a burning card's rank
## readable — composites against the backdrop instead, which reads as grey mush at the base of every
## flame. That is the tool lying, not the effect misbehaving.
@export var show_card_face : bool = true:
	set(v): show_card_face = v; queue_redraw()
@export_range(0, 255, 1) var card_face_index : int = 19:
	set(v): card_face_index = v; queue_redraw()
## Embers are spawned by the card fire only (`FxStyle.ember`), through the real ParticleEngine.
@export var show_embers : bool = true:
	set(v): show_embers = v; _touch()

@export_group("Clock")
## Speed the effect clock up or down. 0 FREEZES the animation on the current frame, which is how you
## judge a silhouette; every other knob still responds while it is frozen.
@export_range(0.0, 4.0, 0.05) var time_scale : float = 1.0
## The backdrop, as a palette role index so the tool cannot itself drift off-palette (§4i).
@export_range(0, 255, 1) var backdrop_index : int = 17:
	set(v): backdrop_index = v; queue_redraw()

func _ready() -> void:
	set_process(true)

func _process(delta : float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()
	if is_zero_approx(time_scale):
		_set_clock(false)
		return
	_set_clock(true)
	# The attachments run their own _process; this only adds (or removes) the difference between
	# real time and tuning time, rather than duplicating their easing here.
	if not is_equal_approx(time_scale, 1.0):
		for fx : FxAttachment in _attachments():
			fx._process(delta * (time_scale - 1.0))

func _set_clock(running : bool) -> void:
	for fx : FxAttachment in _attachments():
		fx.process_mode = Node.PROCESS_MODE_INHERIT if running else Node.PROCESS_MODE_DISABLED

func _attachments() -> Array[FxAttachment]:
	var out : Array[FxAttachment] = []
	for host : Node2D in _hosts:
		if not is_instance_valid(host): continue
		for child : Node in host.get_children():
			var fx := child as FxAttachment
			if fx: out.append(fx)
	return out

# --- construction ---------------------------------------------------------------------------------

## Tear the preview down and build it again. Cheap, and it keeps the tool honest: there is no
## incremental state to go stale against an inspector edit.
func _rebuild() -> void:
	for host : Node2D in _hosts:
		if is_instance_valid(host): host.queue_free()
	_hosts.clear()
	if is_instance_valid(_particles): _particles.queue_free()
	_particles = null
	scale = Vector2.ONE * zoom

	if show_embers:
		# The real engine, so embers here are the embers the game spawns. Added FIRST so particles
		# draw under the effects.
		_particles = ParticleEngine.new()
		_particles.name = "Particles"
		add_child(_particles)

	var slot := 0
	slot = _add_card_fire(slot)
	slot = _add_juggler(slot)
	for kind : GDScript in [HoopVisual, KnifeVisual, BallVisual, FireVisual]:
		slot = _add_prop(slot, kind)
	queue_redraw()

## A card-sized box carrying the card fire style.
func _add_card_fire(slot : int) -> int:
	var reqs : Array[FxRequest] = []
	if fire_stacks > 0 and fire_style:
		reqs.append(FxFire.request(&"fire", fire_stacks, fire_style))
	_spawn_host(_x(slot), card_body, FxAttachment.Shape.BOX, reqs).set_meta(&"card", true)
	return slot + 1

## A card-sized box carrying the juggling pair, exactly as StatusJuggling declares them: the balls,
## and the fire riding whichever balls are alight.
func _add_juggler(slot : int) -> int:
	var reqs : Array[FxRequest] = []
	if ball_count > 0 and juggle_style and ball_fire_style:
		var levels := PackedInt32Array()
		for i : int in ball_count:
			levels.append(lit_level if i < lit_balls else 0)
		reqs = FxJuggle.requests(ball_count, levels, juggle_style, ball_fire_style)
	_spawn_host(_x(slot), card_body, FxAttachment.Shape.BOX, reqs).set_meta(&"card", true)
	return slot + 1

## A REAL PropVisual, drawing its real art, with fire on its own silhouette (the hoop's is an
## ellipse, not a box). PropVisual._ready early-returns in the editor, so the attachment is built
## here instead — with the prop's own `body_size` and `fx_shape()`, the same values it would use.
func _add_prop(slot : int, kind : GDScript) -> int:
	var prop := kind.new() as PropVisual
	if not prop: return slot
	var reqs : Array[FxRequest] = []
	if fire_stacks > 0 and prop_fire_style:
		reqs.append(FxFire.request(&"fire", fire_stacks, prop_fire_style))
	var host := _spawn_host(_x(slot), prop.body_size, prop.fx_shape(), reqs)
	# ⚠ The tool MUST measure the silhouette itself. PropVisual does it in _ready(), which early-
	# returns in the editor, so without this the props emit off their FRAME BOX and the flames sit in
	# a flat line above the art — which is exactly what the tool showed on 2026-07-29 while the
	# snapshot (a running scene, so _ready ran) looked correct.
	for child : Node in host.get_children():
		var fx := child as FxAttachment
		if fx: prop.measure_fx_silhouette(fx)
	host.add_child(prop)
	host.move_child(prop, 0)          # art under the effects, as on a real prop
	return slot + 1

## One preview host: a Node2D standing in for a CardVisual / PropVisual's Offset, carrying a real
## FxAttachment configured the way its host would configure it.
func _spawn_host(at_x : float, body : Vector2, shape : FxAttachment.Shape,
		reqs : Array[FxRequest]) -> Node2D:
	var host := Node2D.new()
	host.position = Vector2(at_x, 0.0)
	add_child(host)                     # NO owner — see the header
	var fx := FxAttachment.new()
	fx.name = "Fx"
	# host_rotates false: nothing spins in here, so the quads keep the cheaper box bound — the same
	# bound every prop gets, since no prop rotates any more (§4g).
	fx.configure(body, false, shape, FxAttachment.Half.WHOLE, true)
	host.add_child(fx)
	fx.sync(reqs)
	host.set_meta(&"body", body)
	_hosts.append(host)
	return host

## Slot centres, laid out symmetrically about the origin.
func _x(slot : int) -> float:
	return (float(slot) - 2.5) * spacing

## Backdrop and body outlines, drawn under everything. No captions: the subjects are recognisable
## from their art and the labels were just clutter (owner 2026-07-29).
func _draw() -> void:
	var half := spacing * 3.5
	draw_rect(Rect2(-half, -spacing * 1.6, half * 2.0, spacing * 3.2),
			PaletteDB.color(backdrop_index), true)
	var px := 1.0 / maxf(zoom, 0.01)
	if show_card_face:
		var face := PaletteDB.color(card_face_index)
		for host : Node2D in _hosts:
			if not is_instance_valid(host) or not host.get_meta(&"card", false): continue
			var body : Vector2 = host.get_meta(&"body", Vector2.ZERO)
			draw_rect(Rect2(host.position - body * 0.5, body), face, true)
	if show_outlines:
		var line := PaletteDB.color(PaletteDB.ROLES.suit_knife)
		for host : Node2D in _hosts:
			if not is_instance_valid(host): continue
			var body : Vector2 = host.get_meta(&"body", Vector2.ZERO)
			draw_rect(Rect2(host.position - body * 0.5, body), line, false, px)
