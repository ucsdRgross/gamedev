@tool
class_name FxEditor
extends Node2D
## LIVE FX TUNING IN THE EDITOR — open `fx_editor.tscn`, edit an `FxStyle` in the inspector, watch
## the real shaders react (owner 2026-07-28: *"a way to visualize fire and juggling purely in editor
## for debugging purposes, similar to formation editor, so I can fine tune parameters"*).
##
## "React" means WITHIN A QUARTER SECOND, without reopening the scene: the tool polls every resource
## it previews and rebuilds when one has moved (see `WATCH_SECS` — a custom resource does not announce
## its own edits, and the export setters below only fire when a resource is ASSIGNED).
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

# --- LIVE RESOURCE WATCH -------------------------------------------------------------------------
## How often the tool re-reads the resources it is previewing, in seconds.
##
## ⚠ THIS EXISTS BECAUSE A CUSTOM RESOURCE DOES NOT TELL ANYONE IT CHANGED (owner 2026-07-31:
## *"changing vfx parameters in editor does not update in real time, requiring closing scene and
## reopening each time"*). `Resource.changed` is only emitted by `emit_changed()`, which built-in
## resources call from their setters and a script's `@export var` does NOT — so editing `height` on
## `fire_card.tres`, or an entry inside its `PaletteRamp`, moved nothing on screen. The `_touch()`
## setters above only fire when the export is ASSIGNED a different resource, which is not what
## tuning looks like.
##
## Polling rather than 35 hand-written `emit_changed()` setters across FxStyle, ParticleSpec and
## PaletteRamp: one place, and it cannot go stale when a knob is added. A quarter second reads as
## instant while dragging a slider, and the scan is a few dozen `Object.get()` calls over six
## resources — free next to the shaders it is previewing.
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
## Burning stacks — AND THE KNOB THAT PROVES THE STACK RATIOS (FxFireStyle's "Stack scaling"
## group). Every fire parameter ramps continuously from here, so drag it and watch: nothing may
## jump, and every knob must be visibly doing something by 40.
##
## The interesting values are 1 (every ratio is inert — `log(1) = 0`, so this is the base style
## exactly), 12 and 40 (where the game lives) and 200 (the ceiling the ramps must still look
## sane at). There is no tendril budget any more and no auto-merge threshold; those were the
## interesting numbers of the retired comb model.
@export_range(0, 200, 1) var fire_stacks : int = 12:
	set(v): fire_stacks = v; _touch()

@export_group("Juggling")
@export var juggle_style : FxJuggleStyle = preload("res://Shaders/Styles/juggle_default.tres"):
	set(v): juggle_style = v; _touch()
## The fire that rides the balls — a different style from the card's, in PROP art units.
@export var ball_fire_style : FxFireStyle = preload("res://Shaders/Styles/fire_ball.tres"):
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
## TURN EVERY HOST, to see how each effect handles a rotated host (owner 2026-07-30). Two different
## answers are correct here, and this is how you tell them apart:
##  * FIRE turns WITH its host — the mask is the art, and the march is world-down, so the flames stay
##    upright and their pixels stay square while the silhouette under them tilts (ruling 1).
##  * JUGGLING does NOT turn at all: *"juggle effect doesn't rotate with card"* (owner 2026-07-30).
##    The pattern is defined in the quad's own space and `juggle.gdshader` never reads `u_shape_rot`,
##    while `FxAttachment._push_live` counter-rotates the quad — so the balls hold their loop, upright
##    and centred on the card, at every angle. This slider is here to PROVE that, not to fix it.
## In both cases the FX pixel grid must stay world-aligned: diagonal pixels anywhere means someone
## rotated a UV before quantizing it (the universal rule, fx_common.gdshaderinc §0b).
@export_range(-180.0, 180.0, 1.0) var host_rotation : float = 0.0:
	set(v): host_rotation = v; _touch()
## WARP EVERY CARD HOST, to see whether the fire follows a card that is no longer a rectangle (owner
## 2026-07-29: *"I don't see fire effect warping with the card during playtesting"*).
##
## The number is how far the four CORNERS stretch outward, as a fraction of their rest reach; the
## edge points stay where they are, which is what turns the box into a star. That is the deformation
## the shipped card rig actually makes — `card_visual.tscn`'s autoplay animation peaks around 0.25 —
## and the outline this builds has the same 16 points in the same order the rig hands over, so what
## the slider shows is the shipped path and not a preview of its own.
##
## ⚠ IT DOES NOT REACH THE PROPS, and that is not an oversight. A prop's mask IS its drawing's alpha
## (`Shape.SPRITE`), which has no outline to stretch — and no prop deforms in the game, so a knob that
## bent one here would be the tool showing something that cannot happen. Warping a sprite mask would
## take a warp term in `fire.gdshader`'s SPRITE branch; that is a shader change, not a tool one.
@export_range(0.0, 0.5, 0.01) var corner_warp : float = 0.0:
	set(v): corner_warp = v; _touch()
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
## Embers, through the real ParticleEngine. EVERY fire that carries an `FxStyle.ember` throws them —
## the card, the props and the lit balls (owner 2026-07-29). Card fire uses `ember.tres`; props and
## balls use the prop-scaled `ember_prop.tres`.
@export var show_embers : bool = true:
	set(v): show_embers = v; _touch()
## THE EMBER TUNABLES, one click away (owner 2026-07-30: *"only see show embers in editor and not the
## tunables"*). These are the same `ParticleSpec` resources `FxStyle.ember` points at — expand one and
## every ember knob (lifetime, speed, spread, gravity, drag, sizes, `ramp_source`, `ramp_alphas`) is
## editable while the preview is on screen. Editing the resource retunes the running game, because the
## style points at this same object.
##
## Two of them because embers are SPLIT PER HOST SCALE exactly as the fire styles are: a prop draws at
## ~2.5x smaller art units, so the card's ember is far too big beside a knife.
##
## ⚠ HOW MANY embers per second is NOT here — that is `FxStyle.ember_rate_max` on the fire style
## above (fire_card / fire_prop / fire_ball), because a rate belongs to the fire that throws them, not
## to the particle. Setting a spec to null disables that fire's embers entirely.
##
## ⚠ These MIRROR `FxStyle.ember` (`_mirror_ember_specs`) — they are a window onto the resource each
## fire is really throwing, not an override. Assigning a different spec HERE is snapped back on the
## next rebuild; point a fire at a different ember on the fire style, where that decision lives.
@export var card_ember_spec : ParticleSpec = preload("res://Shaders/Styles/ember.tres"):
	set(v): card_ember_spec = v; _touch()
## Props AND balls: `ember_prop.tres` is the one both use, and the PROP style is the one shown here.
@export var prop_ember_spec : ParticleSpec = preload("res://Shaders/Styles/ember_prop.tres"):
	set(v): prop_ember_spec = v; _touch()

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
	# The resources are polled BEFORE the rebuild check, so an inspector edit lands on this frame
	# rather than on the next tick.
	_watch_wait += delta
	if _watch_wait >= WATCH_SECS:
		_watch_wait = 0.0
		if _fingerprint() != _watched: _touch()
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

## Every inspector-visible value of every resource this preview reads, flattened into one array. Two
## of these compare unequal exactly when something the owner edited would change what is on screen.
##
## Nested resources are followed (an `FxStyle` holds a `PaletteRamp` and a `ParticleSpec`, and a
## `ParticleSpec` holds another ramp), because the VALUE of a resource property is the object
## identity — it does not change when the entries inside it do, and editing a ramp's entries is
## exactly the case that used to need a scene reload.
##
## `PROPERTY_USAGE_EDITOR` is the filter, which is the same thing as "is in the inspector": it keeps
## the plain script vars out, and those include `FxStyle._ramp_tex` — a cache this function itself
## invalidates, which would otherwise make every poll look like a change and rebuild forever.
func _fingerprint() -> Array:
	var out : Array = []
	for res : Resource in [fire_style, prop_fire_style, juggle_style, ball_fire_style,
			card_ember_spec, prop_ember_spec]:
		_read_into(res, out, 2)
	return out

func _read_into(res : Resource, out : Array, depth : int) -> void:
	if not res or depth <= 0:
		out.append(null)
		return
	for prop : Dictionary in res.get_property_list():
		var usage : int = prop["usage"]
		if not (usage & PROPERTY_USAGE_EDITOR): continue
		var key : StringName = prop["name"]
		var value : Variant = res.get(key)
		# ⚠ COPY THE REFERENCE TYPES. `Array` and `Dictionary` are references in GDScript, so storing
		# one stores a window onto the live value — and an entry edited IN PLACE (which is what
		# `PaletteRamp.indices` gets when a colour is retuned) then compares equal to itself for ever.
		# Measured: the fire ramp was the one thing the watch could not see. `Packed*` arrays are value
		# types and copy on assignment, so they need nothing.
		if value is Array: value = (value as Array).duplicate()
		elif value is Dictionary: value = (value as Dictionary).duplicate()
		out.append(value)                # the identity too, so SWAPPING a nested ramp registers
		if value is Resource: _read_into(value as Resource, out, depth - 1)

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
##
## The CLOCKS AND THE SEEDS SURVIVE (`_keep_time` / `_keep_phase` / `_seed_for`), which matters now
## that this runs four times a second while a slider is dragged: a fresh `FxAttachment` rolls a random
## seed and a random phase, so an un-preserved rebuild teleported every ball and re-rolled the
## fire noise on each edit — the effect flickering rather than the parameter changing. Held steady, a
## drag reads as the one thing that actually moved.
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
		# The real engine, so embers here are the embers the game spawns. Added FIRST so particles
		# draw under the effects.
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
	# AFTER the build, and from the resources as they now are: a rebuild must not look like another
	# change, or the poll would rebuild on every tick for ever.
	_watched = _fingerprint()
	queue_redraw()

## Show the ember spec each fire is ACTUALLY throwing — a mirror of `FxStyle.ember`, not an override.
##
## ⚠ It used to write the other way (`fire_style.ember = card_ember_spec`), and that was fine only
## while nothing else moved. Now that the tool rebuilds four times a second, a write-through means the
## tool would stamp its own value back over any edit the owner made to `FxStyle.ember` on the `.tres`
## itself, within a quarter second, silently — and the editor might then SAVE that. The exports are a
## window onto the resource: expand one and every ember knob is there, which is what they were added
## for. To point a fire at a DIFFERENT ember, set it on the fire style, where that decision lives.
func _mirror_ember_specs() -> void:
	# Assigned only when it actually differs: every one of these setters calls _touch().
	if fire_style and card_ember_spec != fire_style.ember:
		card_ember_spec = fire_style.ember
	# Props and balls share one prop-scaled spec by convention; the PROP style is the one shown.
	if prop_fire_style and prop_ember_spec != prop_fire_style.ember:
		prop_ember_spec = prop_fire_style.ember

## Force every cached ramp texture to be rebuilt.
##
## ⚠ WITHOUT THIS, EDITING A COLOUR CHANGES NOTHING ON SCREEN. `FxStyle` compiles `ramp_source` into
## one `ImageTexture` on first use and drops that cache only from its OWN setters — so retuning the
## style re-reads it, but editing an entry INSIDE the `PaletteRamp` (which is where fire's colours
## actually live) leaves the stale texture in place for the rest of the session. Re-assigning each
## ramp property to itself runs the setter, which is the only invalidation these resources have.
## `ParticleSpec._gradient` is the same story for embers.
func _drop_ramp_caches() -> void:
	for style : FxFireStyle in [fire_style, prop_fire_style, ball_fire_style]:
		if style: style.ramp_source = style.ramp_source
	if juggle_style: juggle_style.ball_tones = juggle_style.ball_tones
	for spec : ParticleSpec in [card_ember_spec, prop_ember_spec]:
		if spec: spec.ramp_source = spec.ramp_source

## A card-sized box carrying the card fire style.
func _add_card_fire(slot : int) -> int:
	var reqs : Array[FxRequest] = []
	if fire_stacks > 0 and fire_style:
		reqs.append(FxFire.request(&"fire", fire_stacks, fire_style))
	_spawn_host(_x(slot), card_body, FxAttachment.Shape.BOX, reqs,
			_card_outline(card_body)).set_meta(&"card", true)
	return slot + 1

## The card silhouette at the current `corner_warp` — CardVisual's own rig shape, never a copy of it,
## so the tool cannot show a deformation the cards do not have.
func _card_outline(body : Vector2) -> PackedVector2Array:
	return CardVisual.star_outline(body, corner_warp)

## A card-sized box carrying the juggling pair, exactly as StatusJuggling declares them: the balls,
## and the fire riding whichever balls are alight.
func _add_juggler(slot : int) -> int:
	var reqs : Array[FxRequest] = []
	if ball_count > 0 and juggle_style and ball_fire_style:
		var levels := PackedInt32Array()
		for i : int in ball_count:
			levels.append(lit_level if i < lit_balls else 0)
		reqs = FxJuggle.requests(ball_count, levels, juggle_style, ball_fire_style)
	_spawn_host(_x(slot), card_body, FxAttachment.Shape.BOX, reqs,
			_card_outline(card_body)).set_meta(&"card", true)
	return slot + 1

## A REAL PropVisual, drawing its real art, with fire on its own MASK — the sheet's own alpha, so
## the hoop burns inside its hole as well as on top. PropVisual._ready early-returns in the editor,
## so the attachment is built here instead, with the same values that host would use.
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
##
## `outline` is the host's DEFORMED silhouette, if it has one — the card hosts hand over the same
## 16-point walk a CardVisual's rig does, which is what makes the warp knob exercise the shipped path.
func _spawn_host(at_x : float, body : Vector2, shape : FxAttachment.Shape,
		reqs : Array[FxRequest], outline : PackedVector2Array = PackedVector2Array()) -> Node2D:
	var host := Node2D.new()
	host.position = Vector2(at_x, 0.0)
	# The whole host turns, art and all — the attachment reads `parent.global_rotation` every frame
	# and cancels it, which is the thing the knob is here to show.
	host.rotation = deg_to_rad(host_rotation)
	add_child(host)                     # NO owner — see the header
	var fx := FxAttachment.new()
	fx.name = "Fx"
	# `host_rotates` decides the QUAD BOUND, not whether anything turns: a turning host needs the
	# circumscribed (diagonal) bound or its fire clips at the quad edge. Nothing spins while the knob
	# is at zero, so the preview keeps the cheaper box bound there — the same bound every prop gets,
	# since no prop rotates any more (§4g).
	fx.configure(body, not is_zero_approx(host_rotation), shape, FxAttachment.Half.WHOLE, true)
	host.add_child(fx)
	# BEFORE `sync`: the outline decides the shape the quads are built for, and the quad bound a
	# stretched corner needs.
	if not outline.is_empty(): fx.measure_outline(outline)
	# THE SEED BEFORE `sync`, THE CLOCKS AFTER — per-host randomness is read when the quads are BUILT
	# (§4.4), while the clock is only ever pushed. This slot's seed is rolled once for the whole
	# session, so a rebuild does not re-scatter the crown that is being tuned.
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

## This slot's random seed, rolled once and reused for every rebuild — the per-host random that keeps
## two cards from flickering in lockstep is exactly what must NOT change when a slider moves.
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

## Backdrop and body outlines, drawn under everything. No captions: the subjects are recognisable
## from their art and the labels were just clutter (owner 2026-07-29).
func _draw() -> void:
	var half := spacing * 3.5
	draw_rect(Rect2(-half, -spacing * 1.6, half * 2.0, spacing * 3.2),
			PaletteDB.color(backdrop_index), true)
	var px := 1.0 / maxf(zoom, 0.01)
	# The reference geometry TURNS WITH ITS HOST, or the rotation knob would show every flame leaning
	# off a card face that stayed square — the tool lying about the very thing it was added to show.
	var rot := deg_to_rad(host_rotation)
	if show_card_face:
		var face := PaletteDB.color(card_face_index)
		for host : Node2D in _hosts:
			if not is_instance_valid(host) or not host.get_meta(&"card", false): continue
			var body : Vector2 = host.get_meta(&"body", Vector2.ZERO)
			draw_set_transform(host.position, rot, Vector2.ONE)
			# The WARPED face, for the same reason the reference geometry turns with its host: a
			# square face under a star-shaped flame base would read as the effect misbehaving.
			draw_colored_polygon(_card_outline(body), face)
	if show_outlines:
		var line := PaletteDB.color(PaletteDB.ROLES.suit_knife)
		for host : Node2D in _hosts:
			if not is_instance_valid(host): continue
			var body : Vector2 = host.get_meta(&"body", Vector2.ZERO)
			draw_set_transform(host.position, rot, Vector2.ONE)
			if host.get_meta(&"card", false):
				var loop := _card_outline(body)
				loop.append(loop[0])
				draw_polyline(loop, line, px)
			else:
				draw_rect(Rect2(-body * 0.5, body), line, false, px)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
