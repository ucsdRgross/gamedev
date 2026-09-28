@tool
class_name FxEditor
extends Node2D
#LIVE FX TUNING IN THE EDITOR: edit an `FxStyle` in the inspector and the real shaders react within
#a quarter second (owner: "a way to visualize fire and juggling purely in editor"). Not a test:
#pixel assertions live in `test_pixels.gd`, reviewable captures in `fx_snapshot.tscn`.

#Every subject at once - a burning card, a juggling card, and the REAL hoop, knife, ball and fire
#props each burning on their own silhouette - because a style reads differently on a prop, whose art
#units are ~2.5x smaller.

#It renders through the SHIPPING path (`FxFire.request()` / `FxJuggle.requests()` into a real
#`FxAttachment`, real `PropVisual`s), never a private copy of the maths: two copies of the arc maths
#is what once made flames trail their balls.

#⚠ Every FX script it touches must be `@tool`: a non-tool script is a PLACEHOLDER in the editor, so
#`FxStyle.apply()` never runs (pure white quads), and saving a `.tres` through it SILENTLY DROPS every
#property the editor could not see. Do not remove `@tool` from any FX class.

#⚠ The editor runs NO autoloads: `FxAttachment.settings()` stands in with shipped defaults and
#`pacing()` is 1.0 with no Game. Every node here is OWNERLESS and rebuilt, or the editor would SAVE
#it into fx_editor.tscn.

## Rebuild whenever any knob moves. Every @export below shares this.
func _touch(_v : Variant = null) -> void:
	_dirty = true

var _dirty := true
var _hosts : Array[Node2D] = []
var _particles : ParticleEngine = null

#⚠ A custom resource never announces its edits: `Resource.changed` needs `emit_changed()`, which a
#script's `@export var` never calls, and the setters below fire only on ASSIGNMENT. So the tool polls,
#one place instead of 35 setters; a quarter second reads as instant, and the scan is nearly free.

## How often the tool re-reads the resources it is previewing, in seconds.
const WATCH_SECS := 0.25

var _watch_wait := 0.0
## Every inspector-visible value of every previewed resource, as of the last rebuild.
var _watched : Array = []

@export_group("Fire")
## The card-hosted flame — the resource you actually tune. Edit it and the preview re-pushes.
@export var fire_style : FxFireStyle = preload("res://Shaders/Styles/fire_card.tres"):
	set(v): fire_style = v; _touch()
## The PROP-hosted flame, in prop art units. Every prop on the right uses this one.
@export var prop_fire_style : FxFireStyle = preload("res://Shaders/Styles/fire_prop.tres"):
	set(v): prop_fire_style = v; _touch()
#The knob that proves the stack ratios: nothing may jump while dragging, and every knob must visibly
#act by 40. Watch 1 (every ratio inert, `log(1) = 0`), 12 and 40 (where the game lives), and 200
#(the ceiling the ramps must still look sane at).

## Burning stacks.
@export_range(0, 200, 1) var fire_stacks : int = 12:
	set(v): fire_stacks = v; _touch()

@export_group("Juggling")
@export var juggle_style : FxJuggleStyle = preload("res://Shaders/Styles/juggle_default.tres"):
	set(v): juggle_style = v; _touch()
## The fire that rides the balls — a different style from the card's, in PROP art units.
@export var ball_fire_style : FxFireStyle = preload("res://Shaders/Styles/fire_ball.tres"):
	set(v): ball_fire_style = v; _touch()
#Watch 2, 4 and 6: there the ball count equals the ARC count, where a per-ball direction mirror
#would send every ball the same way.
## How many balls are juggled.
@export_range(0, 200, 1) var ball_count : int = 6:
	set(v): ball_count = v; _touch()
#Ball fire is per ball and never read from the card's StatusBurning.
## How many balls are ALIGHT - the knob that puts flames on the balls, not the card.
@export_range(0, 200, 1) var lit_balls : int = 2:
	set(v): lit_balls = v; _touch()
@export_range(1, 50, 1) var lit_level : int = 6:
	set(v): lit_level = v; _touch()

@export_group("Stage")
## Card-sized host (CardVisual.CARD_SIZE). The props size themselves from their own sheets.
@export var card_body : Vector2 = CardVisual.CARD_SIZE:
	set(v): card_body = v; _touch()
## Zoom the whole preview. Art is authored at one pixel size; this only magnifies the view.
@export_range(1.0, 12.0, 0.5) var zoom : float = 4.0:
	set(v): zoom = v; _touch()
## Art units between subjects.
@export_range(30.0, 200.0, 1.0) var spacing : float = 70.0:
	set(v): spacing = v; _touch()
#FIRE turns WITH its host: the flames stay upright on a tilted silhouette. JUGGLING never turns (owner:
#"juggle effect doesn't rotate with card"): `_push_live` counter-rotates the quad. Either way the FX
#pixel grid stays world-aligned; diagonal pixels mean a UV was rotated before quantizing.

## Turn every host, to see how each effect handles a rotated host.
@export_range(-180.0, 180.0, 1.0) var host_rotation : float = 0.0:
	set(v): host_rotation = v; _touch()
#Seeks the REAL `AnimationPlayer` of a real `CardVisual`, so every pose is one the game can be in (a
#hand-built star got no closer than 2.3 to 3.3 art units). It does not reach the props: a prop's mask
#is its drawing's alpha, and no prop deforms in the game.

## Where in the card's own animation the rig sits, 0 to 1 across `new_animation_2`.
@export_range(0.0, 1.0, 0.01) var rig_pose : float = 0.0:
	set(v): rig_pose = v; _touch()
## Body outlines, so you can see where a flame's base sits relative to its silhouette.
@export var show_outlines : bool = true:
	set(v): show_outlines = v; queue_redraw()
#Without a face `inner_alpha` composites against the backdrop and reads as grey mush. It is the real
#TypePaper face, never a flat polygon from the mask's own array, which could not show a face-versus-
#mask disagreement (owner: "no placeholder art that isnt ever seen in game").

## Show the CARD hosts' own faces, the real `CardVisual`'s TypePaper polygon skinned to its rig.
@export var show_card_face : bool = true:
	set(v): show_card_face = v; _touch()
## Embers, through the real ParticleEngine, from every fire with an `FxStyle.ember`.
@export var show_embers : bool = true:
	set(v): show_embers = v; _touch()
#The same `ParticleSpec`s `FxStyle.ember` points at: editing one retunes the game. Split per host
#scale like the fire styles, as a prop draws ~2.5x smaller. The RATE is `FxStyle.ember_rate_max`.

#⚠ A MIRROR, not an override (`_mirror_ember_specs`): assigning another spec here snaps back on the
#next rebuild; point a fire at a different ember on its fire style.
## The card fire's ember tunables (owner: "only see show embers in editor and not the tunables").
@export var card_ember_spec : ParticleSpec = preload("res://Shaders/Styles/ember.tres"):
	set(v): card_ember_spec = v; _touch()
## Props AND balls: `ember_prop.tres` is the one both use, and the PROP style is the one shown here.
@export var prop_ember_spec : ParticleSpec = preload("res://Shaders/Styles/ember_prop.tres"):
	set(v): prop_ember_spec = v; _touch()

@export_group("Clock")
#0 FREEZES the animation on its current frame, which is how you judge a silhouette.
## Speed the effect clock up or down; every other knob still responds while frozen.
@export_range(0.0, 4.0, 0.05) var time_scale : float = 1.0
## The backdrop, as a palette role index so the tool cannot itself drift off-palette (§4i).
@export_range(0, 255, 1) var backdrop_index : int = 17:
	set(v): backdrop_index = v; queue_redraw()

func _ready() -> void:
	set_process(true)

#Polls BEFORE the rebuild check, so an inspector edit lands this frame. ⚠ The tool OWNS the clock,
#never nudging it: a `delta * (time_scale - 1)` top-up goes negative below 1, and a negative step
#walks `Effect.t` backwards so a released effect never fades out. Not driving them is the freeze.
func _process(delta : float) -> void:
	_watch_wait += delta
	if _watch_wait >= WATCH_SECS:
		_watch_wait = 0.0
		if _fingerprint() != _watched: _touch()
	if _dirty:
		_dirty = false
		_rebuild()
	_stop_engine_clock()
	if is_zero_approx(time_scale): return
	for fx : FxAttachment in _attachments():
		fx._process(delta * time_scale)

#Re-applied every frame because `_rebuild` hands back fresh nodes at the default mode; a disabled
#node still draws, and a direct `_process` call still works.
## Take the attachments off the ENGINE's process pass, so `_process` above alone advances them.
func _stop_engine_clock() -> void:
	for fx : FxAttachment in _attachments():
		fx.process_mode = Node.PROCESS_MODE_DISABLED

#Nested resources are followed, their identity too: a ramp's entries change without its identity.
#Filtered on `PROPERTY_USAGE_EDITOR`, which keeps out caches like `FxStyle._ramp_tex` that this
#function invalidates - else every poll is a change.

## Every inspector-visible value of every previewed resource, flattened; unequal exactly on an edit.
func _fingerprint() -> Array:
	var out : Array = []
	for res : Resource in [fire_style, prop_fire_style, juggle_style, ball_fire_style,
			card_ember_spec, prop_ember_spec]:
		_read_into(res, out, 2)
	return out

#⚠ Arrays and Dictionaries are COPIED: stored by reference, an in-place edit (a retuned
#`PaletteRamp.indices`) compares equal to itself for ever - measured, the fire ramp was invisible to
#the watch. `Packed*` arrays copy on assignment already.
func _read_into(res : Resource, out : Array, depth : int) -> void:
	if not res or depth <= 0:
		out.append(null)
		return
	for prop : Dictionary in res.get_property_list():
		var usage : int = prop["usage"]
		if not (usage & PROPERTY_USAGE_EDITOR): continue
		var key : StringName = prop["name"]
		var value : Variant = res.get(key)
		if value is Array: value = (value as Array).duplicate()
		elif value is Dictionary: value = (value as Dictionary).duplicate()
		out.append(value)
		if value is Resource: _read_into(value as Resource, out, depth - 1)

func _attachments() -> Array[FxAttachment]:
	var out : Array[FxAttachment] = []
	for host : Node2D in _hosts:
		if not is_instance_valid(host): continue
		for child : Node in host.get_children():
			var fx := child as FxAttachment
			if fx: out.append(fx)
	return out

#No incremental state to go stale. The CLOCKS AND SEEDS SURVIVE (`_keep_time`, `_keep_phase`,
#`_seed_for`): a fresh attachment re-rolls both, which at four rebuilds a second while dragging read
#as flicker. Embers are added first to draw under the effects; `_watched` is taken last.

## Tear the preview down and build it again.
func _rebuild() -> void:
	_keep_time.clear()
	_keep_phase.clear()
	for host : Node2D in _hosts:
		if not is_instance_valid(host): continue
		for child : Node in host.get_children():
			var fx := child as FxAttachment
			if not fx: continue
			_keep_time.append(fx._time)
			_keep_phase.append(fx._phase)
			break
		host.queue_free()
	_hosts.clear()
	if is_instance_valid(_particles): _particles.queue_free()
	_particles = null
	scale = Vector2.ONE * zoom

	if show_embers:
		_particles = ParticleEngine.new()
		_particles.name = "Particles"
		add_child(_particles)

	_mirror_ember_specs()
	_drop_ramp_caches()
	var slot := 0
	slot = _add_card_fire(slot)
	slot = _add_juggler(slot)
	for kind : GDScript in [HoopVisual, KnifeVisual, BallVisual, FireVisual]:
		slot = _add_prop(slot, kind)
	_watched = _fingerprint()
	queue_redraw()

#⚠ Never write-through: rebuilding four times a second, the tool would stamp its value over an edit
#to `FxStyle.ember` on the `.tres` and the editor might SAVE it. Assigned only on a difference, each
#setter calling `_touch()`; props and balls share the prop-scaled spec, shown via the PROP style.

## Show the ember spec each fire is ACTUALLY throwing.
func _mirror_ember_specs() -> void:
	if fire_style and card_ember_spec != fire_style.ember:
		card_ember_spec = fire_style.ember
	if prop_fire_style and prop_ember_spec != prop_fire_style.ember:
		prop_ember_spec = prop_fire_style.ember

#⚠ Without this a colour edit changes nothing: `FxStyle` drops its compiled ramp only from its OWN
#setters, so an edit INSIDE the `PaletteRamp` keeps the stale texture. Re-assigning each ramp to
#itself runs the setter, the only invalidation there is; `ParticleSpec._gradient` likewise.

## Force every cached ramp texture to be rebuilt.
func _drop_ramp_caches() -> void:
	for style : FxFireStyle in [fire_style, prop_fire_style, ball_fire_style]:
		if style: style.ramp_source = style.ramp_source
	if juggle_style: juggle_style.ball_tones = juggle_style.ball_tones
	for spec : ParticleSpec in [card_ember_spec, prop_ember_spec]:
		if spec: spec.ramp_source = spec.ramp_source

## A REAL CardVisual carrying the card fire style (owner: "no useless mocks").
func _add_card_fire(slot : int) -> int:
	var reqs : Array[FxRequest] = []
	if fire_stacks > 0 and fire_style:
		reqs.append(FxFire.request(&"fire", fire_stacks, fire_style))
	_spawn_host(_x(slot), card_body, FxAttachment.Shape.BOX, reqs, _new_card())
	return slot + 1

#Real data, built the way `Deck._card` builds a card. PREVIEW, not PLAY_AREA: that context chases a
#`control_anchor` a tool has none of. `CardVisual._ready` skips its own `FxAttachment` in the editor,
#so `_spawn_host` builds one as the card would.

## A real card: the scene the game instantiates, with real data behind it.
func _new_card() -> CardVisual:
	var card := CardVisual.CARD_VISUAL.instantiate() as CardVisual
	card.current_context = CardVisual.DisplayContext.PREVIEW
	card.data = CardData.new().with_type(TypePaper.new()) \
			.with_suit(PipSuitHoop.new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(7))
	return card

#Art units, so card_scale is reset. ⚠ `_process` OFF, or a RUN scene frees the card: it cannot find a
#`control_anchor` (measured: FX with no card under it). Its own attachment is freed: RUNNING the scene
#otherwise puts two fire quads on every card. The animation never autoplays, so the pose holds still.

## Park a real card at `rig_pose` of its own animation and hand the FX its live outline.
func _pose_card(card : CardVisual, fx : FxAttachment) -> void:
	card.scale = Vector2.ONE
	card.set_process(false)
	card.floating = false
	card.visual.visible = show_card_face
	if card.fx:
		card.fx.queue_free()
		card.fx = null
	var ap := card.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(CardVisual.RIG_ANIM):
		var anim := ap.get_animation(CardVisual.RIG_ANIM)
		if anim:
			ap.play(CardVisual.RIG_ANIM)
			ap.seek(rig_pose * anim.length, true)
			ap.pause()
	if not card._rig_arms.is_empty(): fx.measure_outline(card._rig_outline())

## A card carrying the juggling pair as StatusJuggling declares them: the balls and their fire.
func _add_juggler(slot : int) -> int:
	var reqs : Array[FxRequest] = []
	if ball_count > 0 and juggle_style and ball_fire_style:
		var levels := PackedInt32Array()
		for i : int in ball_count:
			levels.append(lit_level if i < lit_balls else 0)
		reqs = FxJuggle.requests(ball_count, levels, juggle_style, ball_fire_style)
	_spawn_host(_x(slot), card_body, FxAttachment.Shape.BOX, reqs, _new_card())
	return slot + 1

#The fire sits on the sheet's own alpha, so the hoop burns inside its hole too. PropVisual._ready
#early-returns in the editor, so the attachment is built here with that host's values.
## A REAL PropVisual drawing its real art, with fire on its own MASK.
func _add_prop(slot : int, kind : GDScript) -> int:
	var prop := kind.new() as PropVisual
	if not prop: return slot
	var reqs : Array[FxRequest] = []
	if fire_stacks > 0 and prop_fire_style:
		reqs.append(FxFire.request(&"fire", fire_stacks, prop_fire_style))
	_spawn_host(_x(slot), prop.body_size, FxAttachment.Shape.BOX, reqs, prop)
	return slot + 1

#The art goes in FIRST so it draws under the effects (tree order; no z_index). ⚠ Both host kinds skip
#their FX setup in the editor, or props emit off their FRAME BOX. A turning host needs the diagonal
#bound. The silhouette and the seed go in BEFORE `sync`, which reads them; the clocks after.

## One preview host carrying THE REAL VISUAL and a real FxAttachment configured as it would be.
func _spawn_host(at_x : float, body : Vector2, shape : FxAttachment.Shape,
		reqs : Array[FxRequest], art : Node2D = null) -> Node2D:
	var host := Node2D.new()
	host.position = Vector2(at_x, 0.0)
	host.rotation = deg_to_rad(host_rotation)
	add_child(host)
	if art:
		host.add_child(art)
		host.set_meta(&"card", art is CardVisual)
	var fx := FxAttachment.new()
	fx.name = "Fx"
	fx.configure(body, not is_zero_approx(host_rotation), shape, FxAttachment.Half.WHOLE, true)
	host.add_child(fx)
	var card := art as CardVisual
	if card: _pose_card(card, fx)
	var prop := art as PropVisual
	if prop: prop.measure_fx_silhouette(fx)
	var slot := _hosts.size()
	fx._seed = _seed_for(slot)
	fx.sync(reqs)
	if slot < _keep_time.size():
		fx._time = _keep_time[slot]
		fx._phase = _keep_phase[slot]
		fx._push_live(0.0)
	host.set_meta(&"body", body)
	_hosts.append(host)
	return host

## This slot's seed, rolled once: what keeps two cards out of lockstep must not change on a slider.
func _seed_for(slot : int) -> float:
	while _seeds.size() <= slot:
		_seeds.append(randf() * 100.0)
	return _seeds[slot]

## Preserved across a rebuild: one entry per host slot, in build order.
var _seeds : PackedFloat32Array = PackedFloat32Array()
var _keep_time : PackedFloat32Array = PackedFloat32Array()
var _keep_phase : PackedFloat32Array = PackedFloat32Array()

## Slot centres, laid out symmetrically about the origin.
func _x(slot : int) -> float:
	return (float(slot) - 2.5) * spacing

#The reference geometry TURNS WITH ITS HOST, or flames would lean off a face that stayed square. A
#card outlines its LIVE RIG, the silhouette the fire was handed; a prop its body box. No card face is
#drawn here: the hosts are real `CardVisual`s.

## Backdrop and body outlines, drawn under everything; no captions (owner).
func _draw() -> void:
	var half := spacing * 3.5
	draw_rect(Rect2(-half, -spacing * 1.6, half * 2.0, spacing * 3.2),
			PaletteDB.color(backdrop_index), true)
	var px := 1.0 / maxf(zoom, 0.01)
	var rot := deg_to_rad(host_rotation)
	if show_outlines:
		var line := PaletteDB.color(PaletteDB.ROLES.suit_knife)
		for host : Node2D in _hosts:
			if not is_instance_valid(host): continue
			var body : Vector2 = host.get_meta(&"body", Vector2.ZERO)
			draw_set_transform(host.position, rot, Vector2.ONE)
			var loop := _rig_loop(host)
			if not loop.is_empty(): draw_polyline(loop, line, px)
			else: draw_rect(Rect2(-body * 0.5, body), line, false, px)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The closed rig outline of a host's card, in the card's own space, or empty for a host without one.
func _rig_loop(host : Node2D) -> PackedVector2Array:
	for child : Node in host.get_children():
		var card := child as CardVisual
		if not card or card._rig_arms.is_empty(): continue
		var loop := (card._rig_outline() as PackedVector2Array).duplicate()
		loop.append(loop[0])
		return loop
	return PackedVector2Array()
