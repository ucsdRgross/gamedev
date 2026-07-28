class_name FxAttachment
extends Node2D
## One host's visual effects. This node IS the `Fx` node of the FX tree: a child of the host's
## Offset, added AFTER the host's art, so it draws above its own host while the whole host
## subtree is still occluded by whatever overlaps it (owner ruling 2) — pure parent/child
## nesting, no z_index, so LAYERING.md's all-structural rule holds.
##
## Built by the CardVisual / PropVisual itself, never by a board-level layer. That is what makes
## "fx should be shared across all views" free: a card in the deck viewer, the pack preview or
## the map builds its own identical attachment with zero context handling (owner rulings 7, 18).
##
## It does not know which effects exist. It renders FxRequests; statuses declare their own.

## Extra art units of quad beyond the host body plus the effect's reach, so an effect's outermost
## pixels are never clipped by the quad edge.
const FX_MARGIN := 4.0

## Emitter modes, mirroring the constants in fire.gdshader. GDScript and GLSL cannot share an
## enum, so the mapping exists twice and can drift silently — the FX ATTACHMENT suite asserts it.
enum Mode { SILHOUETTE = 0, BALLS = 1 }

## Silhouette kinds, mirroring fire.gdshader the same way. A card and a blade are BOTH boxes;
## only a deformed card needs the 32-tap radius table, so it is its own kind rather than every
## card paying for a silhouette lookup it does not use.
enum Shape { BOX = 0, RING = 1, RADII = 2 }

## Split-prop halves: which side of the silhouette this quad is allowed to emit from.
enum Half { WHOLE = 0, BACK = 1, FRONT = 2 }

## Art units per second of host travel below which the flames ignore the motion entirely. NOT
## optional: a board card is never still — delta_floating_anim bobs and drifts it every frame
## (card_visual.gd:311) — so an unfiltered velocity makes the flames jitter permanently.
const LAG_DEADZONE := 8.0
## How far the tips lag per unit of host speed, and the spring that carries them there. The spring
## is what sells it: a raw velocity snaps to zero the instant the card stops, which reads as the
## flames teleporting upright instead of whipping past and settling.
const LAG_GAIN := 0.02
const LAG_STIFFNESS := 90.0
const LAG_DAMPING := 9.0
## Ceiling on the trail, in art units, so a teleporting card cannot fling its flames off the quad.
const LAG_MAX := 12.0

## One rendered effect and its transition state. Stack changes are eased rather than applied, so
## adding a stack never makes the established flames jump (owner ruling 16).
class Effect:
	var req : FxRequest
	var quad : MeshInstance2D
	## The values the effect held when its target last changed — the FROM end of the ease.
	var from : Dictionary[StringName, float] = {}
	## Ease progress, 0 to 1. Starts at 1: the first sync applies its numbers immediately, since
	## there is nothing to ease from.
	var t : float = 1.0
	## Release progress, or -1 while the effect is live. Reaching zero stacks FADES the quad and
	## only then frees it — dropping it outright is exactly the jump ruling 16 forbids.
	var fade : float = -1.0
	## Fractional particles owed to the emitter, carried between frames so a rate below one per
	## frame still emits at the right average.
	var emit_debt : float = 0.0

## The host's AUTHORED body size (CardVisual.CARD_SIZE, PropVisual.body_size) — the silhouette the
## effects decorate. Never the host's live scale: that hits zero mid-flip (the basis3d squash) and
## pulses on anim_jump, and either would make the effect throb or vanish with it.
var body : Vector2 = Vector2.ZERO

## True when the host can turn to any angle. Rotating hosts pay the circumscribed (diagonal) quad
## bound; hosts whose rotation is pinned keep the cheaper box bound.
var rotates : bool = true

## Which silhouette the effects decorate, and (for a split prop) which half this attachment emits.
var shape : Shape = Shape.BOX
var half : Half = Half.WHOLE

## Whether this host runs the MOTION effects — embers and the cape. Both exist for a board where
## cards travel and are dropped; in a static grid like the deck viewer neither earns its cost, and
## the viewer is the densest screen in the game (50+ cards, all showing their statuses). The
## flames and balls themselves stay identical everywhere, which is what ruling 7 asks for.
var ambient : bool = true

## Effect clock, in pacing-scaled seconds. Accumulated here rather than read from the shader's
## built-in TIME: TIME is wall-clock, ignores the act-compression ramp, and keeps running through
## a paused SceneTree — the classic "paused game with a still-flickering fire" bug.
var _time : float = 0.0

# --- per-HOST randomness (owner 2026-07-28: effects must not sync up across cards) --------------
## This host's random seed, pushed to EVERY quad it owns rather than rolled per quad: the balls and
## the flames riding them have to agree on it, and two hosts must not share it. Every phase in both
## shaders — tendril sway, flicker, the whole-effect pulse, ball spin — is keyed on it.
var _seed : float = randf() * 100.0
## Which way this host's juggling pattern runs. Balls ALTERNATE around this (`fx_ball_dir`), so this
## is really "which way does ball 0 set off", and it is a coin flip per host.
var _ball_dir : float = 1.0 if randf() < 0.5 else -1.0

var _fx : Dictionary[StringName, Effect] = {}
## ONE phase clock for the whole host, shared by every effect that declares a period — which is
## what welds a ball's flame to its ball rather than letting the two drift apart. Starts at a RANDOM
## point in the cycle: from zero, every card that started juggling with the same count moved as one.
var _phase : float = randf()
var _lag : Vector2 = Vector2.ZERO
var _lag_vel : Vector2 = Vector2.ZERO
var _last_pos : Vector2 = Vector2.ZERO

func _ready() -> void:
	# Idle until something asks for an effect: every host runs one of these, and most carry no
	# statuses at all.
	set_process(false)
	_last_pos = global_position
	SettingsManager.settings_changed.connect(_restyle)

## Point this attachment at its host's silhouette. Called once by the host right after it adds the
## node — the values are authored constants for a given host, so they never change afterwards.
func configure(body_size: Vector2, host_rotates := true, host_shape := Shape.BOX,
		host_half := Half.WHOLE, host_ambient := true) -> void:
	body = body_size
	rotates = host_rotates
	shape = host_shape
	half = host_half
	ambient = host_ambient

## The card silhouette's reach at each of RADII angles, or empty while the host is a plain box.
var _radii := PackedFloat32Array()

## Entries in the radius table. 32, NOT 16: the star rig deforming a card goes up to 16 arms, and
## 16 samples cannot represent 16 alternating features (Nyquist) — at 16 the arms either smooth
## into a blob or beat against the grid depending on phase. Must match RADII in fire.gdshader.
const RADII := 32

## Measure the host's real outline into the radius table, so flames hug a deformed card instead of
## its nominal rectangle. Behind a dirty flag by contract: the caller decides when the silhouette
## changed, because sampling a polygon every frame for a shape that almost never moves is exactly
## the kind of per-frame work this design avoids elsewhere.
##
## A simple quad stays Shape.BOX: the box branch is an exact ray/rect exit and costs one tap,
## where the table costs a lookup plus a lerp on every contour sample. Only a genuinely deformed
## outline is worth the table.
func measure_silhouette(points: PackedVector2Array) -> void:
	if points.size() <= 8:
		shape = Shape.BOX
		_radii = PackedFloat32Array()
		_restyle()
		return
	_radii.resize(RADII)
	_radii.fill(0.0)
	for p : Vector2 in points:
		# Angle measured from straight up, matching shape_radius's convention exactly.
		var a := atan2(p.x, -p.y)
		var slot := int(floorf((a / TAU + 1.0) * float(RADII))) % RADII
		_radii[slot] = maxf(_radii[slot], p.length())
	# An empty angular bucket would read as a radius of zero and tear a notch in the outline, so
	# fill each from its neighbours; two passes settle any run of gaps this table can have.
	for _pass : int in 2:
		for i : int in RADII:
			if _radii[i] > 0.0: continue
			_radii[i] = maxf(_radii[(i + RADII - 1) % RADII], _radii[(i + 1) % RADII])
	shape = Shape.RADII
	_restyle()

## Ratio of the base delay to the LIVE delay: 1.0 at rest, above 1 as act compression speeds
## everything up, so ambient FX quicken in lockstep with card and prop animation. Null-safe: an
## FX host in a viewer or in a test has no game and simply runs at rest pace.
static func pacing() -> float:
	var game := CardEnvironment.get_current_game()
	if not game: return 1.0
	return SettingsManager.settings.base_delay / maxf(game.get_delay(), 0.001)

## How long a stack change takes. The owner's metric is "fast enough before the next status effect
## gets applied", and statuses land on PROP TICKS — so this is a fraction of one prop tick,
## re-derived live like every other timing here, never a wall-clock number and never a guess.
##
## Read from the Game rather than through play_area.prop_layer: a card in the deck viewer has no
## play area, and it must ease exactly like a board card (ruling 18) rather than snapping.
## Under heavy compression the delay approaches its floor and transitions snap — which is already
## how prop motion behaves there, so the whole board degrades consistently.
static func transition_secs() -> float:
	var s := SettingsManager.settings
	var game := CardEnvironment.get_current_game()
	var delay : float = game.get_delay() if game else s.base_delay
	return delay * s.prop_tick_fraction * s.fx_transition_fraction

## Force every FX shader through its first compile NOW, on a one-pixel offscreen quad, then throw
## the quads away. On gl_compatibility a shader's first USE is when it compiles, and that is a
## visible hitch — the first fire in a run is exactly when you do not want one. Cheap and
## fire-and-forget: call it once from a screen that can host cards.
static func warm(parent: Node) -> void:
	if Engine.is_editor_hint(): return
	for shader : Shader in [FxFire.FIRE_SHADER, FxJuggle.JUGGLE_SHADER]:
		var quad := MeshInstance2D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		quad.mesh = mesh
		var mat := ShaderMaterial.new()
		mat.shader = shader
		quad.material = mat
		quad.modulate = Color(1.0, 1.0, 1.0, 0.0)   # drawn, and therefore compiled, but invisible
		parent.add_child(quad)
		quad.get_tree().create_timer(0.5).timeout.connect(quad.queue_free)

## Rebuild the quad set from whatever the host's statuses ask for. Idempotent and GENERIC: it
## reads FxRequests and never names an effect. Quads are keyed by request id, so a refresh
## RETUNES an existing quad (and keeps its material, and therefore its compiled state) instead of
## rebuilding it, and draw order follows request order — later requests draw on top.
func sync(requests: Array[FxRequest]) -> void:
	var seen : Dictionary[StringName, bool] = {}
	for i : int in requests.size():
		var req : FxRequest = requests[i]
		seen[req.id] = true
		var fx : Effect = null
		if _fx.has(req.id): fx = _fx[req.id]
		if not fx:
			fx = Effect.new()
			fx.quad = _make_quad(req)
			_fx[req.id] = fx
			add_child(fx.quad)
		else:
			# A status that comes back mid-fade simply stops fading — no flash, no rebuild.
			fx.fade = -1.0
			fx.from = _eased(fx)
			fx.t = 0.0
		fx.req = req
		_size_quad(fx.quad, req)
		_apply_static(fx.quad, req)
		move_child(fx.quad, i)
	for id : StringName in _fx:
		# Reaching zero stacks FADES the effect out and only then releases its quad.
		if not seen.has(id) and _fx[id].fade < 0.0:
			_fx[id].from = _eased(_fx[id])
			_fx[id].fade = 0.0
	set_process(not _fx.is_empty())
	if not _fx.is_empty(): _push_live(0.0)

## The quad for one effect. A MeshInstance2D + QuadMesh, never a ColorRect: a Control dropped
## into the host's Node2D subtree joins the GUI input pass and eats the mouse events card
## grabbing needs. QuadMesh is Node2D-native, is centred on its origin, takes its size directly,
## and cannot swallow input.
func _make_quad(req: FxRequest) -> MeshInstance2D:
	var quad := MeshInstance2D.new()
	quad.name = String(req.id)
	quad.mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	# The SHARED Shader resource, never a duplicate: duplicating it recompiles the program for
	# every card. The per-node state is the ShaderMaterial's uniform set, not the Shader.
	mat.shader = req.shader
	quad.material = mat
	# The HOST's seed and direction, not this quad's: two burning cards side by side must not flicker
	# in lockstep, and the two quads of ONE juggling host must agree exactly (a ball and its flame).
	mat.set_shader_parameter(&"u_seed", _seed)
	mat.set_shader_parameter(&"u_ball_dir", _ball_dir)
	return quad

## Size the quad to bound the host AT EVERY ROTATION plus the effect's reach, or its edge clips.
## The quad stays world-aligned while the host turns INSIDE it, so a rotating host's bound is its
## CIRCUMSCRIBED extent — its diagonal — not its box: a 38x50 card is 62x62 at 45 degrees, and
## anim_spin_start turns it through every angle. Pinned hosts skip that ~1.6x fill cost.
func _size_quad(quad: MeshInstance2D, req: FxRequest) -> void:
	var bound := Vector2.ONE * body.length() if rotates else body
	var extent := bound + Vector2.ONE * (req.reach + FX_MARGIN) * 2.0
	(quad.mesh as QuadMesh).size = extent
	# UV maps across exactly the quad, so the shader needs the same number to recover art units.
	(quad.material as ShaderMaterial).set_shader_parameter(&"u_extent", extent)

## Write the STATIC half of an effect's uniforms: its style's ~35 art levers plus the host facts
## that never change. Called on creation and on style swap, never per frame — pushing the whole
## set every frame for every host is the cost the static/live split exists to avoid.
func _apply_static(quad: MeshInstance2D, req: FxRequest) -> void:
	var mat := quad.material as ShaderMaterial
	if req.style: req.style.apply(mat)
	mat.set_shader_parameter(&"u_mode", req.mode)
	mat.set_shader_parameter(&"u_shape", int(shape))
	mat.set_shader_parameter(&"u_half", int(half))
	mat.set_shader_parameter(&"u_body", body)
	if not _radii.is_empty(): mat.set_shader_parameter(&"u_radii", _radii)
	# The player's master effect strength, on top of the style's own brightness — so a "reduce
	# effects" setting reaches every effect without editing a single .tres, and reaching zero
	# turns the board's FX off entirely (a genuine photosensitivity control, not a taste one).
	var lit : float = req.style.brightness if req.style else 1.0
	mat.set_shader_parameter(&"u_brightness", lit * SettingsManager.settings.fx_intensity)
	for key : StringName in req.snap:
		mat.set_shader_parameter(key, req.snap[key])

## How many embers a second one effect throws off. Scales with the count, under a PER-SOURCE
## ceiling from the style so one blazing card cannot consume the engine's global cap.
const EMBER_PER_STACK := 3.0

## Hand this effect's embers to ParticleEngine and forget them. The attachment owns NO particles:
## there is nothing to detach or free when the host despawns, and a freed card cannot take its
## embers with it — which is ruling 9 satisfied by construction.
##
## Spawn position is a random point along the host's top edge, scattered upward by the flame
## height. That is an APPROXIMATION of "from the flame tips" and deliberately so: real tip
## positions are computed in the shader, and mirroring tendril() in GDScript to find them would be
## exactly the duplicated-motion bug the shared include exists to prevent.
func _emit_embers(fx: Effect, scaled_delta: float) -> void:
	var style := fx.req.style
	if not ambient or not style or not style.ember or fx.fade >= 0.0: return
	var count : float = fx.req.live.get(&"u_count", 0.0)
	var rate := minf(count * EMBER_PER_STACK, style.ember_rate_max)
	if rate <= 0.0: return
	fx.emit_debt += rate * scaled_delta
	while fx.emit_debt >= 1.0:
		fx.emit_debt -= 1.0
		var height : float = fx.req.live.get(&"u_height", 0.0)
		var local := Vector2(randf_range(-body.x, body.x) * 0.5,
				-body.y * 0.5 - randf() * height)
		ParticleEngine.spawn(style.ember, to_global(local), 1)

## Re-apply every live effect's static uniforms. Connected to settings_changed, because the
## fx_intensity master knob is a PLAYER setting and must reach effects already on screen.
func _restyle() -> void:
	for id : StringName in _fx:
		_apply_static(_fx[id].quad, _fx[id].req)

## The effect's data-derived values at its current ease position. Every one of them is a float and
## rides the SAME ease as the count — including the count itself, which is why it is a float in
## the shader: it drives a comb that partitions the emitting width into n cells, so an integer
## step from 3 to 4 re-partitions the whole width and teleports every existing flame. Tweening the
## stack count is not enough; the count ITSELF has to be continuous.
func _eased(fx: Effect) -> Dictionary[StringName, float]:
	var out : Dictionary[StringName, float] = {}
	var t := clampf(fx.t, 0.0, 1.0)
	for key : StringName in fx.req.live:
		var to : float = fx.req.live[key]
		var f : float = fx.from[key] if fx.from.has(key) else to
		out[key] = lerpf(f, to, t)
	return out

## Per frame: advance the clock and the transitions, cancel the rotation inherited from the host
## (so the quad — and with it the FX pixel grid — holds still in world space while the host turns),
## and let the flames trail the host's motion.
##
## Nothing here freezes for a game state — grabbed, held, hovered, mid-move or mid-flip all keep
## advancing (owner ruling 24). The pacing ratio only ever SCALES the clock, never zeroes it.
func _process(delta: float) -> void:
	var scaled := delta * pacing()
	_time += scaled
	_update_lag(delta)
	_push_live(scaled)

## Flames trail the host like a cape: the tips lag its motion and OVERSHOOT when it stops. Driven
## from global_position ONLY — the host's rotation and basis3d must not reach the flames (ruling
## 1), so feeding them in would tilt the tips off vertical.
func _update_lag(delta: float) -> void:
	if not ambient: return
	var pos := global_position
	var vel := (pos - _last_pos) / maxf(delta, 1e-4)
	_last_pos = pos
	if vel.length() < LAG_DEADZONE: vel = Vector2.ZERO
	# A spring toward the trail the current speed calls for, not the raw velocity: the restoring
	# term is what brings the flames back upright, and the damping is what lets them overshoot on
	# the way — that overshoot is the cape snapping.
	var target := (-vel * LAG_GAIN).limit_length(LAG_MAX)
	_lag_vel += ((target - _lag) * LAG_STIFFNESS - _lag_vel * LAG_DAMPING) * delta
	_lag = (_lag + _lag_vel * delta).limit_length(LAG_MAX)

## Push the handful of genuinely per-frame uniforms, advance each effect's ease, and release any
## effect whose fade has finished.
func _push_live(scaled_delta: float) -> void:
	var parent := get_parent() as Node2D
	if not parent: return
	var rot := parent.global_rotation
	rotation = -rot
	var secs := transition_secs()
	var step : float = 1.0 if secs <= 0.0 else scaled_delta / secs
	var lag_norm := _lag / maxf(body.x, 1.0)
	# Advance the shared phase ONCE, from the longest period any effect declares — the balls quad
	# and the ball-fire quad declare the same one, and reading a single value is what guarantees
	# they agree on every frame rather than merely starting together.
	var period := 0.0
	for id : StringName in _fx:
		period = maxf(period, _fx[id].req.phase_period)
	if period > 0.0: _phase = fmod(_phase + scaled_delta / period, 1.0)
	var done : Array[StringName] = []
	for id : StringName in _fx:
		var fx : Effect = _fx[id]
		fx.t = minf(fx.t + step, 1.0)
		var mat := fx.quad.material as ShaderMaterial
		mat.set_shader_parameter(&"u_time", _time)
		mat.set_shader_parameter(&"u_shape_rot", rot)
		mat.set_shader_parameter(&"u_lag", lag_norm)
		if fx.req.phase_period > 0.0: mat.set_shader_parameter(&"u_phase", _phase)
		_emit_embers(fx, scaled_delta)
		var vals := _eased(fx)
		for key : StringName in vals:
			mat.set_shader_parameter(key, vals[key])
		if fx.fade >= 0.0:
			fx.fade = minf(fx.fade + step, 1.0)
			var base : float = fx.req.style.opacity if fx.req.style else 1.0
			mat.set_shader_parameter(&"u_opacity", base * (1.0 - fx.fade))
			if fx.fade >= 1.0: done.append(id)
	for id : StringName in done:
		_fx[id].quad.queue_free()
		_fx.erase(id)
	set_process(not _fx.is_empty())
