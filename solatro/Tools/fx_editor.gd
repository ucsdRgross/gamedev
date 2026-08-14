@tool
class_name FxEditor
extends Node2D
## LIVE FX TUNING IN THE EDITOR — open `fx_editor.tscn`, edit an `FxStyle` in the inspector, watch
## the real shaders react (owner: *"a way to visualize fire and juggling purely in editor
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
## its `pixel` and `dither` on 2026-07-28. FxStyle, FxRequest, FxFire, FxJuggle, ParticleSpec,
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
## ⚠ THIS EXISTS BECAUSE A CUSTOM RESOURCE DOES NOT TELL ANYONE IT CHANGED (owner:
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
@export var card_body : Vector2 = Vector2(40, 54):
	set(v): card_body = v; _touch()
## Zoom the whole preview. Art is authored at one pixel size; this only magnifies the view.
@export_range(1.0, 12.0, 0.5) var zoom : float = 4.0:
	set(v): zoom = v; _touch()
## Art units between subjects.
@export_range(30.0, 200.0, 1.0) var spacing : float = 70.0:
	set(v): spacing = v; _touch()
## TURN EVERY HOST, to see how each effect handles a rotated host (owner). Two different
## answers are correct here, and this is how you tell them apart:
##  * FIRE turns WITH its host — the mask is the art, and the march is world-down, so the flames stay
##    upright and their pixels stay square while the silhouette under them tilts (ruling 1).
## * JUGGLING does NOT turn at all: *"juggle effect doesn't rotate with card"* (owner).
##    The pattern is defined in the quad's own space and `juggle.gdshader` never reads `u_shape_rot`,
##    while `FxAttachment._push_live` counter-rotates the quad — so the balls hold their loop, upright
##    and centred on the card, at every angle. This slider is here to PROVE that, not to fix it.
## In both cases the FX pixel grid must stay world-aligned: diagonal pixels anywhere means someone
## rotated a UV before quantizing it (the universal rule, fx_common.gdshaderinc §0b).
@export_range(-180.0, 180.0, 1.0) var host_rotation : float = 0.0:
	set(v): host_rotation = v; _touch()
## WHERE IN THE CARD'S OWN ANIMATION THE RIG SITS, 0 to 1 across `new_animation_2` — which is how you
## see whether the fire follows a card that is no longer a rectangle (owner: *"I don't see
## fire effect warping with the card during playtesting"*).
##
## ⚠ IT REPLACED A `corner_warp` SLIDER, AND THAT SLIDER WAS THE TOOL'S LAST MOCK. It stretched the four
## corners of a hand-built 16-point star (`CardVisual.star_outline`) — the same family the rig deforms
## in, but never a pose the rig actually makes: the shipped animation also swings the four MID-EDGE arms
## and does not move opposite corners by the same amount, so the closest that slider could get to a real
## card was **2.3 to 3.3 art units out** (measured — `test_pixels.gd`'s
## `test_the_card_mask_is_the_card_the_player_sees`). The hosts are REAL `CardVisual`s now, so this
## seeks the REAL `AnimationPlayer` and every pose it shows is one the game can be in.
##
## ⚠ IT DOES NOT REACH THE PROPS, and that is not an oversight. A prop's mask IS its drawing's alpha
## (`Shape.SPRITE`), which has no outline to deform — and no prop deforms in the game, so a knob that
## bent one here would be the tool showing something that cannot happen.
@export_range(0.0, 1.0, 0.01) var rig_pose : float = 0.0:
	set(v): rig_pose = v; _touch()
## Body outlines, so you can see where a flame's base sits relative to its silhouette.
@export var show_outlines : bool = true:
	set(v): show_outlines = v; queue_redraw()
## Show the CARD hosts' own faces — the real `CardVisual`'s TypePaper polygon, skinned to its rig, the
## same drawing the game puts on the board. Without a face under them the flame bases are drawn over
## nothing and `inner_alpha` — the overlay opacity that keeps a burning card's rank readable —
## composites against the backdrop instead, which reads as grey mush. That is the tool lying, not the
## effect misbehaving.
##
## ⚠ IT USED TO BE A FLAT PALETTE-COLOURED POLYGON, and it was drawn from THE SAME ARRAY the mask was
## built from — so the tool could not show a face-versus-mask disagreement at all (owner:
## *"no placeholder art that isnt ever seen in game"*). The real face is not even a rectangle: the
## TypePaper frame clips one texel off each corner, which a flat polygon could never have shown.
@export var show_card_face : bool = true:
	set(v): show_card_face = v; _touch()
## Embers, through the real ParticleEngine. EVERY fire that carries an `FxStyle.ember` throws them —
## the card, the props and the lit balls (owner). Card fire uses `ember.tres`; props and
## balls use the prop-scaled `ember_prop.tres`.
@export var show_embers : bool = true:
	set(v): show_embers = v; _touch()
## THE EMBER TUNABLES, one click away (owner: *"only see show embers in editor and not the
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
	# ⚠ THE ATTACHMENTS ARE DRIVEN FROM HERE, NOT NUDGED. This used to let them run themselves and then
	# add `delta * (time_scale - 1.0)` on top — the DIFFERENCE between real time and tuning time — which
	# is NEGATIVE for every `time_scale` below 1, and this scene ships at 0.5. A negative delta reaches
	# `_push_live` as a negative `step`, so `Effect.t` walks backwards out of its ease and `Effect.fade`
	# can never reach 1: a released effect simply never goes away in the preview. `_time` happened to
	# net out correctly, which is why it looked fine.
	#
	# Letting the tool own the clock outright costs one call and cannot go backwards. `process_mode`
	# only stops the ENGINE from calling `_process`; a direct call still works, and nothing else about
	# the node changes (it still draws).
	_stop_engine_clock()
	# 0 FREEZES, and now falls out: with the engine clock off, simply not driving them holds every
	# effect on its current frame, which is what the knob promises.
	if is_zero_approx(time_scale): return
	for fx : FxAttachment in _attachments():
		fx._process(delta * time_scale)

## Take the attachments off the ENGINE's process pass, so `_process` above is the only thing that
## advances them. Re-applied every frame because `_rebuild` hands back fresh nodes at the default mode.
func _stop_engine_clock() -> void:
	for fx : FxAttachment in _attachments():
		fx.process_mode = Node.PROCESS_MODE_DISABLED

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

## A REAL CardVisual carrying the card fire style — its TypePaper face, its star rig, its own
## animation. The card equivalent of `_add_prop`, and for the same reason (owner: *"no
## useless mocks when you can just use actual original scene"*).
func _add_card_fire(slot : int) -> int:
	var reqs : Array[FxRequest] = []
	if fire_stacks > 0 and fire_style:
		reqs.append(FxFire.request(&"fire", fire_stacks, fire_style))
	_spawn_host(_x(slot), card_body, FxAttachment.Shape.BOX, reqs, _new_card())
	return slot + 1

## A real card, posed and parked: the scene the game instantiates, with real data behind it so the face
## is the one the player sees rather than the placeholder the .tscn ships with.
##
## ⚠ `CardVisual._ready` SKIPS ITS OWN `FxAttachment` IN THE EDITOR — deliberately, since the tool owns
## the effects it is previewing — so `_spawn_host` builds one exactly as the card would. Everything else
## about the card is real: the rig, the skinning, the TypePaper frame, the pips.
func _new_card() -> CardVisual:
	var card := CardVisual.CARD_VISUAL.instantiate() as CardVisual
	# NOT PLAY_AREA: `delta_self_moving_logic` chases a `control_anchor` a tool has none of, and frees
	# any non-play-area card that loses one — which the editor guard already spares us.
	card.current_context = CardVisual.DisplayContext.PREVIEW
	# Real data, built the way `Deck._card` builds every card in the game.
	card.data = CardData.new().with_type(TypePaper.new()) \
			.with_suit(PipSuitHoop.new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(7))
	return card

## Park a real card at `rig_pose` of its own animation and hand the FX its live outline.
##
## ⚠ THE ANIMATION NEVER PLAYS BY ITSELF — editor-inert before, and since 2026-08-07 not autoplayed at
## runtime either (`CardVisual.RIG_ANIM` is now the only home for its name) — which is what makes
## `rig_pose` the honest knob: every pose it seeks is one the shipped animation actually passes through,
## and it holds still while a style is tuned.
func _pose_card(card : CardVisual, fx : FxAttachment) -> void:
	# Art units, like every other host here: the card root carries `card_scale` from its own _ready, and
	# the tool does its own zooming.
	card.scale = Vector2.ONE
	# ⚠ PARKED, OR IT DELETES ITSELF THE MOMENT THIS SCENE IS *RUN* rather than edited.
	# `delta_self_moving_logic` frees any non-play-area card that cannot find its `control_anchor`, and a
	# tool has none — measured: every card host came back with its FX and no card under it. Its `_process`
	# does nothing else the preview wants either (anchor chasing, the bob, and re-reading a rig this
	# function poses by hand).
	card.set_process(false)
	# FRONT-FACING and STILL: `floating` drives the bob and the basis3d flip, and `show_front` is what
	# puts the face on screen at all.
	card.floating = false
	card.visual.visible = show_card_face
	# ⚠ ONE ATTACHMENT PER HOST, and a card builds its own as soon as it is NOT in the editor — so
	# RUNNING this scene (which is how the preview gets checked without opening the editor) would
	# otherwise put two fire quads on every card. The tool's is the one carrying the styles being tuned.
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
	# The card's OWN rig, the same array `_track_fx_outline` hands over on the board every frame.
	if not card._rig_arms.is_empty(): fx.measure_outline(card._rig_outline())

## A card-sized box carrying the juggling pair, exactly as StatusJuggling declares them: the balls,
## and the fire riding whichever balls are alight.
func _add_juggler(slot : int) -> int:
	var reqs : Array[FxRequest] = []
	if ball_count > 0 and juggle_style and ball_fire_style:
		var levels := PackedInt32Array()
		for i : int in ball_count:
			levels.append(lit_level if i < lit_balls else 0)
		reqs = FxJuggle.requests(ball_count, levels, juggle_style, ball_fire_style)
	_spawn_host(_x(slot), card_body, FxAttachment.Shape.BOX, reqs, _new_card())
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
	_spawn_host(_x(slot), prop.body_size, FxAttachment.Shape.BOX, reqs, prop)
	return slot + 1

## One preview host: a Node2D standing in for a CardVisual / PropVisual's Offset, carrying THE REAL
## VISUAL and a real FxAttachment configured the way that visual would configure it.
##
## `art` is the host's own scene — a `CardVisual` or a `PropVisual`, never a stand-in for one (owner
## 2026-07-29: *"no useless mocks when you can just use actual original scene, just like how hoop knife
## use actual art"*). It is added FIRST, so it draws UNDER the effects exactly as it does on the board.
##
## ⚠ BOTH KINDS SKIP THEIR OWN FX SETUP IN THE EDITOR and the tool has to finish the job: `PropVisual
## ._ready` early-returns whole, and `CardVisual._ready` builds no attachment. Without that the props
## emit off their FRAME BOX and the flames sit in a flat line above the art — which is exactly what this
## tool showed on 2026-07-29 while the snapshot (a running scene, so `_ready` ran) looked correct.
func _spawn_host(at_x : float, body : Vector2, shape : FxAttachment.Shape,
		reqs : Array[FxRequest], art : Node2D = null) -> Node2D:
	var host := Node2D.new()
	host.position = Vector2(at_x, 0.0)
	# The whole host turns, art and all — the attachment reads `parent.global_rotation` every frame
	# and cancels it, which is the thing the knob is here to show.
	host.rotation = deg_to_rad(host_rotation)
	add_child(host)                     # NO owner — see the header
	# The art goes in BEFORE the attachment, which is what puts it underneath: draw order here is tree
	# order, exactly as it is on a real host (no z_index anywhere — LAYERING.md).
	if art:
		host.add_child(art)
		host.set_meta(&"card", art is CardVisual)
	var fx := FxAttachment.new()
	fx.name = "Fx"
	# `host_rotates` decides the QUAD BOUND, not whether anything turns: a turning host needs the
	# circumscribed (diagonal) bound or its fire clips at the quad edge. Nothing spins while the knob
	# is at zero, so the preview keeps the cheaper box bound there — the same bound every prop gets,
	# since no prop rotates any more (§4g).
	fx.configure(body, not is_zero_approx(host_rotation), shape, FxAttachment.Half.WHOLE, true)
	host.add_child(fx)
	# BEFORE `sync`: the silhouette decides the shape the quads are built for, and the quad bound a
	# stretched corner needs. Each host measures its own — a card from its rig, a prop from its sheet.
	var card := art as CardVisual
	if card: _pose_card(card, fx)
	var prop := art as PropVisual
	if prop: prop.measure_fx_silhouette(fx)
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
## from their art and the labels were just clutter (owner).
func _draw() -> void:
	var half := spacing * 3.5
	draw_rect(Rect2(-half, -spacing * 1.6, half * 2.0, spacing * 3.2),
			PaletteDB.color(backdrop_index), true)
	var px := 1.0 / maxf(zoom, 0.01)
	# The reference geometry TURNS WITH ITS HOST, or the rotation knob would show every flame leaning
	# off a card face that stayed square — the tool lying about the very thing it was added to show.
	var rot := deg_to_rad(host_rotation)
	# ⚠ NO CARD FACE IS DRAWN HERE ANY MORE. The card hosts are real `CardVisual`s and draw their own
	# TypePaper faces (`show_card_face` toggles the real one, in `_pose_card`) — this used to fill a flat
	# palette-coloured polygon built from THE SAME array the mask was built from, so the tool could not
	# show a face-versus-mask disagreement at all. Deleted, not moved.
	if show_outlines:
		var line := PaletteDB.color(PaletteDB.ROLES.suit_knife)
		for host : Node2D in _hosts:
			if not is_instance_valid(host): continue
			var body : Vector2 = host.get_meta(&"body", Vector2.ZERO)
			draw_set_transform(host.position, rot, Vector2.ONE)
			# A card outlines its LIVE RIG — the silhouette the fire was handed, so a flame base that
			# does not sit on it is a real disagreement. A prop outlines its body box; its own art is the
			# reference that matters and it is already on screen.
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
