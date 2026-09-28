@tool
class_name FxAttachment
extends Node2D

# One host's visual effects, and this node IS its `Fx` node: added to the host's Offset AFTER its
# art, so it draws above its host while the subtree stays occluded by what overlaps it (no z_index).
# Built by the host, so every view gets identical effects; it renders FxRequests and names none.

## Extra art units of quad beyond the host body plus the effect's reach, so edge pixels never clip.
const FX_MARGIN := 4.0

# `@tool`: the FX editor previews real effects and the editor has no autoloads. ⚠ ONE INSTANCE,
# SHARED BY THE EDITOR AND THE GAME (owner): it loads and saves the same `user://settings.tres` the
# autoload does, and ResourceLoader's cache hands every editor caller the same object.

## The editor's copy of the shared settings, loaded once.
static var _editor_settings : PlayerSettings = null

# A fresh profile gets the shared file created rather than an in-memory orphan, and edits persist the
# way SettingsManagerClass.on_settings_changed does at runtime.

## The settings the FX read.
static func settings() -> PlayerSettings:
	if not Engine.is_editor_hint(): return SettingsManager.settings
	if _editor_settings: return _editor_settings
	if ResourceLoader.exists(SettingsManagerClass.SAVE_PATH):
		_editor_settings = ResourceLoader.load(SettingsManagerClass.SAVE_PATH)
	if not _editor_settings:
		_editor_settings = PlayerSettings.new()
		ResourceSaver.save(_editor_settings, SettingsManagerClass.SAVE_PATH)
	if not _editor_settings.settings_changed.is_connected(_save_editor_settings):
		_editor_settings.settings_changed.connect(_save_editor_settings)
	return _editor_settings

## Write the shared settings back. Editor-side twin of `SettingsManagerClass.save_settings()`.
static func _save_editor_settings() -> void:
	if _editor_settings:
		ResourceSaver.save(_editor_settings, SettingsManagerClass.SAVE_PATH)

# Mirrors fire.gdshader's constants; GDScript and GLSL cannot share an enum, so the FX ATTACHMENT suite
# asserts the mapping. A deformed card is RADII, a textured host a SPRITE answering with its own alpha
# (the only way a hoop has a hole), and a juggled ball is a shape too (owner: "no special ball case").

## The host silhouette kinds the mask knows.
enum Shape { BOX = 0, RADII = 1, SPRITE = 2, BALLS = 3 }

## Split-prop halves: which side of the silhouette this quad is allowed to emit from.
enum Half { WHOLE = 0, BACK = 1, FRONT = 2 }

# NOT optional: a board card is never still (`CardVisual.delta_floating_anim` bobs it every frame), so
# an unfiltered velocity makes the flames jitter permanently.

## Art units per second of host travel below which the flames ignore the motion.
const LAG_DEADZONE := 8.0

# The spring is what sells it: a raw velocity snaps to zero the instant the card stops, which reads as
# the flames teleporting upright instead of whipping past and settling.

## How far the tips lag per unit of host speed.
const LAG_GAIN := 0.02

## The lag spring's stiffness.
const LAG_STIFFNESS := 90.0

## The lag spring's damping.
const LAG_DAMPING := 9.0

## Ceiling on the trail, in art units, so a teleporting card cannot fling its flames off the quad.
const LAG_MAX := 12.0

# Stack changes are eased rather than applied, so adding a stack never makes the established flames
# jump (owner).

## One rendered effect and its transition state.
class Effect:
	var req : FxRequest
	## The drawn node: a MeshInstance2D for one quad, a MultiMeshInstance2D for an instanced effect.
	var quad : Node2D
	## The quad's mesh, held beside `quad` so no site re-derives it.
	var mesh : QuadMesh
	## The quad's material.
	var mat : ShaderMaterial
	## The instance buffer, or null for a single quad; `instance_count` is the live subject count.
	var multi : MultiMesh
	## The instance box being eased OUT of, or zero; the quad spans both ends until the ease lands.
	var box_from : Vector2 = Vector2.ZERO
	## The quad size this effect HAS, so re-sizing to it is a no-op (a deforming card sizes per frame).
	var extent : Vector2 = Vector2.ZERO
	## The eased values as of the last frame that computed them; the ember emitter reads them.
	var vals : Dictionary[StringName, float] = {}
	## Whether the settled (t == 1) values were pushed: one upload per transition, not per frame.
	var pushed : bool = false
	## The values held when the target last changed - the FROM end of the ease.
	var from : Dictionary[StringName, float] = {}
	## Ease progress, 0 to 1; starts at 1 so the first sync applies its numbers immediately.
	var t : float = 1.0
	## Release progress, or -1 while live; the quad FADES out before it is freed.
	var fade : float = -1.0
	## Fractional particles owed, so a rate below one per frame still emits at the right average.
	var emit_debt : float = 0.0

# Never the host's live scale: that hits zero mid-flip (the basis3d squash) and pulses on anim_jump,
# and either would make the effect throb or vanish with it.

## The host's AUTHORED body size (CardVisual.CARD_SIZE, PropVisual.body_size).
var body : Vector2 = Vector2.ZERO

## True when the host can turn to any angle: it pays the circumscribed quad bound.
var rotates : bool = true

## Which silhouette the effects decorate.
var shape : Shape = Shape.BOX

## For a split prop, which half this attachment emits from.
var half : Half = Half.WHOLE

# The mask IS the art, so it mirrors with it or a blade heading right emits off the outline it no
# longer has. Re-pushed only when it changes.

## Whether the host's art is MIRRORED (PropVisual.face_travel).
var flipped : bool = false:
	set(value):
		if flipped == value: return
		flipped = value
		_restyle()

# They exist for a board where cards travel; the deck viewer (50+ cards) is the densest screen and
# gets neither. The flames and balls themselves stay identical everywhere.

## Whether this host runs the MOTION effects - embers and the cape.
var ambient : bool = true

# Not the shader's TIME: that is wall-clock, ignores the act-compression ramp and keeps running
# through a paused SceneTree.

## Effect clock, in pacing-scaled seconds.
var _time : float = 0.0

# Per HOST, not per quad (owner: effects must not sync up across cards): a ball and the flame riding
# it must agree and two hosts must not. Every phase in both shaders is keyed on it.

## This host's random seed, pushed to every quad it owns.
var _seed : float = randf() * 100.0

# The crossing comes from the arc ladder alternating its sweep, not from a per-ball mirror
# (`fx_ball_pos_ladder` records why a per-ball mirror cancels it).

## Which way this host's whole juggling pattern runs, a coin flip per host.
var _ball_dir : float = 1.0 if randf() < 0.5 else -1.0

## The live effects, keyed by request id.
var _fx : Dictionary[StringName, Effect] = {}

# One clock shared by every effect that declares a period welds a ball's flame to its ball. It starts
# at a RANDOM point: from zero, every card that started juggling the same count moved as one.

## The host's phase clock, 0 to 1.
var _phase : float = randf()

## That clock's period, resolved in `sync`; 0 while nothing has a phase.
var _phase_period : float = 0.0
var _lag : Vector2 = Vector2.ZERO
var _lag_vel : Vector2 = Vector2.ZERO
var _last_pos : Vector2 = Vector2.ZERO

## The host pose the quads were last told about; NAN so the first push always happens.
var _sent_rot : float = NAN
var _sent_lag : Vector2 = Vector2(NAN, NAN)

## Whether the host is upright enough for its quads to take their AABB bound (see _size_quad).
var _rot_tight : bool = true

## How far from upright still counts as upright, in radians; the residue stays inside FX_MARGIN.
const TIGHT_ROT := 0.017

## The largest quad this host owns, for the off-screen test; only `_size_quad` changes it.
var _cull_reach : float = 0.0

# Idle until something asks for an effect: every host runs one of these and most carry no statuses.
# No autoloads exist in the editor, where the FX editor hosts these nodes.
func _ready() -> void:
	set_process(false)
	_last_pos = global_position
	if not Engine.is_editor_hint():
		SettingsManager.settings_changed.connect(_restyle)

## Point this attachment at its host's silhouette; called once by the host right after adding it.
func configure(body_size: Vector2, host_rotates := true, host_shape := Shape.BOX,
		host_half := Half.WHOLE, host_ambient := true) -> void:
	body = body_size
	rotates = host_rotates
	shape = host_shape
	half = host_half
	ambient = host_ambient

## The host silhouette's own VERTICES, once around in the art's frame, or empty for a box; `u_poly`.
var _poly := PackedVector2Array()

## Per WEDGES-th of a turn, the vertex whose wedge spans that slot's start; `u_wedge`.
var _wedge := PackedFloat32Array()

## SHAPE_SPRITE: the sheet the mask is read out of (measure_sprite_silhouette).
var _art : Texture2D = null

## The frame inside that sheet, in normalized uv.
var _art_rect : Vector4 = Vector4(0.0, 0.0, 1.0, 1.0)

## The size that frame is drawn at, centred on the host's origin.
var _art_size : Vector2 = Vector2.ONE

# 40 = the star rig's 16 arms plus six more at each corner, the most staircase any shipped type
# draws there (`CardVisual._rig_outline`). A longer outline is resampled at POLY uniform angles,
# which loses vertices; OUTLINE asserts every shipped type's outline fits.

## How many silhouette vertices reach the shader; must match POLY in fire.gdshader and glow.gdshader.
const POLY := 40

# A slot is 1/32 of a turn and a corner's staircase points (up to seven) sit within a few degrees
# of each other, so covering one slot can take eight wedges. `test_fx_attachment` asserts the bound, and both
# must match fire.gdshader and glow.gdshader.

## Angular slots in the wedge index.
const WEDGES := 32

## How many consecutive wedges the shader tests per slot.
const WEDGE_CANDIDATES := 8

# `_size_quad` bounds a rotating host's quad with it, so a deformed card's stretched corner cannot push
# its flames past the quad edge.

## The longest vertex, in art units - half the silhouette's circumscribed extent right now.
var _poly_max : float = 0.0

# Pushed as `u_body` on the RADII quads: the outward fan is measured across it and `body_near` rejects
# against it, so a stretched corner must not sit outside its own bound.

## The deformed outline's tight half-extents.
var _poly_half : Vector2 = Vector2.ZERO

## The largest origin-centred box inside the silhouette: the mask's early ACCEPT (`_inner_box`).
var _poly_inner : Vector2 = Vector2.ZERO

# Scratch for `_fill_poly_from_outline`, allocated once: it runs on every frame a card's rig moves.
var _next := PackedVector2Array()
var _ring := PackedVector2Array()
var _angles := PackedFloat32Array()

## The incoming outline's angles in ITS order; `_angles` holds them re-wound, a permutation.
var _angles_src := PackedFloat32Array()

# ⚠ NOT ALLOCATION-FREE: Packed arrays are copy-on-write and the material keeps a reference, so the
# next write forks it anyway. What the pad saves is the second buffer and the re-`resize`.

## `_poly` padded to POLY, reused per push for a host whose rig is shorter than POLY.
var _poly_padded := PackedVector2Array()

## The outline last resolved into `_poly`: `track_outline` compares against it before resolving.
var _poly_source := PackedVector2Array()

# ⚠ AN APPROXIMATION, THE FALLBACK FOR A HOST WITH NO RIG: unordered points are bucketed into POLY
# angular slots (from straight up, empty buckets filled from their neighbours), which puts vertices at
# fixed angles instead of the shape's corners. An ordered outline must use `measure_outline`.

## Measure the host's outline into the mask; a simple quad stays Shape.BOX.
func measure_silhouette(points: PackedVector2Array) -> void:
	if points.size() <= 8:
		shape = Shape.BOX
		_poly = PackedVector2Array()
		_wedge = PackedFloat32Array()
		_poly_max = 0.0
		_poly_inner = Vector2.ZERO
		_restyle()
		return
	var radius := PackedFloat32Array()
	radius.resize(POLY)
	radius.fill(0.0)
	for p : Vector2 in points:
		var a := atan2(p.x, -p.y)
		var slot := int(floorf((a / TAU + 1.0) * float(POLY))) % POLY
		radius[slot] = maxf(radius[slot], p.length())
	for _pass : int in 2:
		for i : int in POLY:
			if radius[i] > 0.0: continue
			radius[i] = maxf(radius[(i + POLY - 1) % POLY], radius[(i + 1) % POLY])
	var ring := PackedVector2Array()
	ring.resize(POLY)
	for i : int in POLY:
		var a := float(i) * TAU / float(POLY)
		ring[i] = Vector2(sin(a), -cos(a)) * radius[i]
	_fill_poly_from_outline(ring)
	shape = Shape.RADII
	_restyle()

# ⚠ `outline` must run ONCE around the silhouette so its angles increase monotonically - what a rig
# walked edge by edge gives. That builds the wedge index in one merged walk, cheap enough per frame
# per card. Unordered points belong in `measure_silhouette`.

## Bind the mask to an ORDERED outline (the setup call; `track_outline` is the per-frame one).
func measure_outline(outline: PackedVector2Array) -> void:
	if outline.size() < 3:
		shape = Shape.BOX
		_poly = PackedVector2Array()
		_wedge = PackedFloat32Array()
		_poly_max = 0.0
		_poly_inner = Vector2.ZERO
		_restyle()
		return
	_fill_poly_from_outline(outline)
	shape = Shape.RADII
	_restyle()

# ⚠ DO NOT SHORT-CIRCUIT THIS ON `_fx.is_empty()`: `_poly` is a published property test_pixels reads
# off an UNLIT card. Only an unmoved INPUT skips the resolve, since `_poly` already is that input's
# (measured: VFX.md, "Cleanups left on the table"). Instanced and shape-overriding quads: no upload.

## Re-read the deformed outline and push it to the live quads; a no-op when nothing moved.
func track_outline(outline: PackedVector2Array) -> void:
	if shape != Shape.RADII or outline.size() < 3: return
	if not _moved_from(_poly_source, outline): return
	if not _fill_poly_from_outline(outline): return
	for id : StringName in _fx:
		var fx : Effect = _fx[id]
		if fx.req.shape >= 0 and fx.req.shape != int(Shape.RADII): continue
		if not fx.req.instances.is_empty(): continue
		_push_poly(fx.mat)
		_size_quad(fx)

# PADDED to the uniform's length, since a rig may be shorter than POLY; `u_poly_count` keeps the shader
# off the padding. ⚠ Packing two vertices per vec4 was measured SLOWER (6.808 ms against 6.344 on the
# owner's Intel UHD): the array's size costs, but the unpack per fetch cost more.

## Push the silhouette a RADII quad reads: vertices, wedge index, live count and tight body, as one fact.
func _push_poly(mat: ShaderMaterial) -> void:
	var verts := _poly
	if verts.size() < POLY:
		_poly_padded.resize(POLY)
		for i : int in _poly.size(): _poly_padded[i] = _poly[i]
		verts = _poly_padded
	mat.set_shader_parameter(&"u_poly", verts)
	mat.set_shader_parameter(&"u_wedge", _wedge)
	mat.set_shader_parameter(&"u_poly_count", _poly.size())
	mat.set_shader_parameter(&"u_inner", _poly_inner)
	mat.set_shader_parameter(&"u_body", _poly_half * 2.0)

# ⚠ THE VERTICES ARE STORED, NOT SAMPLED: no interpolation between rays reproduces a vertex, and a
# 32-ray table left a real card's stretched corner 26.9 art units outside its mask. The wedge index,
# per slot the vertex whose wedge spans its start, keeps the shader O(1).

# ⚠ THE RING IS RE-WOUND TO ONE WINDING from its lowest angle, because the wedge index and the
# shader's `wedge_has` read the walk as ANGLE-INCREASING; the angles are permuted, not recomputed. An
# outline longer than POLY is resampled, the approximation this exists to avoid.

## Resolve `outline` into the mask's vertices and wedge index; returns whether anything moved.
func _fill_poly_from_outline(outline: PackedVector2Array) -> bool:
	var n := outline.size()
	_angles_src.resize(n)
	var start := 0
	var area := 0.0
	var half := Vector2.ZERO
	var top := 0.0
	for i : int in n:
		var p := outline[i]
		_angles_src[i] = fposmod(atan2(p.x, -p.y), TAU)
		if _angles_src[i] < _angles_src[start]: start = i
		area += p.cross(outline[(i + 1) % n])
		half = Vector2(maxf(half.x, absf(p.x)), maxf(half.y, absf(p.y)))
		top = maxf(top, p.length())
	var step := 1 if area >= 0.0 else -1
	_ring.resize(n)
	_angles.resize(n)
	for i : int in n:
		var src := posmod(start + i * step, n)
		_ring[i] = outline[src]
		_angles[i] = _angles_src[src]
	_next.resize(mini(n, POLY))
	if n <= POLY:
		for i : int in n: _next[i] = _ring[i]
	else:
		for k : int in POLY:
			var a := float(k) * TAU / float(POLY)
			var seg := _span_of(a, n)
			_next[k] = Vector2(sin(a), -cos(a)) * _ray_hit(a, _ring[seg], _ring[(seg + 1) % n])
	var m := _next.size()
	if m < n:
		_angles.resize(m)
		for i : int in m: _angles[i] = fposmod(atan2(_next[i].x, -_next[i].y), TAU)
	_wedge.resize(WEDGES)
	var j := 0
	for k : int in WEDGES:
		var a := float(k) * TAU / float(WEDGES)
		while j < m - 1 and _angles[j + 1] <= a: j += 1
		_wedge[k] = float(m - 1) if a < _angles[0] else float(j)
	var moved := not is_equal_approx(top, _poly_max) or not half.is_equal_approx(_poly_half) \
			or _moved_from(_poly, _next)
	_poly_source = outline.duplicate()
	if not moved: return false
	_poly = _next.duplicate()
	_poly_max = top
	_poly_half = half
	_poly_inner = _inner_box(_poly, half)
	return true

## Whether `now` differs from `was` in length or by more than 0.05 art units at any point.
func _moved_from(was: PackedVector2Array, now: PackedVector2Array) -> bool:
	if was.size() != now.size(): return true
	for k : int in now.size():
		if now[k].distance_to(was[k]) > 0.05: return true
	return false

# Intersecting every edge's half-plane gives a convex region inside a star-shaped outline -
# conservative where the shape is not convex, the safe direction. A corner staircase's short step
# edges pull it inside the outer bound even at rest, so a resting card's corner bands build wedges.

## The largest box of `half`'s aspect inside the silhouette - the shader's early ACCEPT.
func _inner_box(poly: PackedVector2Array, half: Vector2) -> Vector2:
	var n := poly.size()
	if n < 3 or half == Vector2.ZERO: return Vector2.ZERO
	var t := 1.0
	for i : int in n:
		var a := poly[i]
		var e := poly[(i + 1) % n] - a
		var nrm := Vector2(-e.y, e.x)
		var d := nrm.dot(a)
		if d < 0.0:
			nrm = -nrm
			d = -d
		var span := half.x * absf(nrm.x) + half.y * absf(nrm.y)
		if span > 1e-6: t = minf(t, d / span)
	return half * clampf(t, 0.0, 1.0)

## The index in `_ring` of the vertex whose segment spans angle `a` (the resample path's lookup).
func _span_of(a: float, n: int) -> int:
	for j : int in n - 1:
		if _angles[j + 1] > a: return j
	return n - 1

## How far the ray at angle `a` reaches before crossing segment p->q; zero where it is edge-on.
func _ray_hit(a: float, p: Vector2, q: Vector2) -> float:
	var d := Vector2(sin(a), -cos(a))
	var s := q - p
	var den := d.cross(s)
	if absf(den) < 1e-6: return p.length()
	return maxf(p.cross(s) / den, 0.0)

# ⚠ CACHED PER FRAME RECT AS A HITCH FIX: the scan is an Image.get_pixel per texel on top of a
# get_image decode, once per attachment, and a split prop has three. A sheet never changes at runtime.

## Measured sprite frames: the art's tight body and its frame rect, or empty for a frame with no art.
static var _sprite_cache : Dictionary[String, Array] = {}

# The mask is sampled LIVE in the shader, which keeps a turning host current and a hoop its hole. Only
# the art's tight box is measured, as the BODY; the frame rect stays whole, because the art is drawn
# centred on the host's origin and the tight box is not.

## Point this attachment at a SPRITE's sheet, so the fire reads the drawing's ALPHA as its mask.
func measure_sprite_silhouette(sheet: Texture2D, src: Rect2, size: Vector2) -> void:
	if not sheet: return
	var key := "%s|%s|%s" % [sheet.resource_path, src, size]
	if _sprite_cache.has(key):
		var hit : Array = _sprite_cache[key]
		if hit.is_empty():
			shape = Shape.BOX
			return
		body = hit[0]
		_art = sheet
		_art_rect = hit[1]
		_art_size = size
		shape = Shape.SPRITE
		_restyle()
		return
	var img := sheet.get_image()
	if not img: return
	var x0 := int(src.position.x)
	var y0 := int(src.position.y)
	var w := int(src.size.x)
	var h := int(src.size.y)
	var min_x := w
	var max_x := -1
	var min_y := h
	var max_y := -1
	for x : int in w:
		for y : int in h:
			if img.get_pixel(x0 + x, y0 + y).a <= 0.0: continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	if max_x < 0:
		_sprite_cache[key] = []
		shape = Shape.BOX
		return
	var texel := size / Vector2(float(w), float(h))
	body = Vector2(float(max_x - min_x + 1), float(max_y - min_y + 1)) * texel
	var sheet_size := Vector2(float(img.get_width()), float(img.get_height()))
	_art = sheet
	_art_rect = Vector4(src.position.x / sheet_size.x, src.position.y / sheet_size.y,
			src.size.x / sheet_size.x, src.size.y / sheet_size.y)
	_art_size = size
	_sprite_cache[key] = [body, _art_rect]
	shape = Shape.SPRITE
	_restyle()

## Base delay over the LIVE delay: ambient FX quicken with act compression; 1.0 with no game.
static func pacing() -> float:
	var game := CardEnvironment.get_current_game()
	if not game: return 1.0
	return settings().base_delay / maxf(game.get_delay(), 0.001)

# A fraction of one prop tick, because statuses land on prop ticks (owner: "fast enough before the next
# status effect gets applied"). Read from the Game, not the play area, so a viewer card eases like a
# board card; under heavy compression it snaps, as prop motion already does.

## How long a stack change takes.
static func transition_secs() -> float:
	var s := settings()
	var game := CardEnvironment.get_current_game()
	var delay : float = game.get_delay() if game else s.base_delay
	return delay * s.prop_tick_fraction * s.fx_transition_fraction

# On gl_compatibility a shader compiles at its first USE, a visible hitch on the first fire of a run.
# The quad is drawn at zero alpha, so it compiles and shows nothing.

## Compile every FX shader now on a throwaway quad; call once from a screen that hosts cards.
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
		quad.modulate = Color(1.0, 1.0, 1.0, 0.0)
		parent.add_child(quad)
		Pacing.wait(quad, 0.5).timeout.connect(quad.queue_free)

# Quads are keyed by request id, so a refresh RETUNES an existing quad (keeping its compiled material),
# a status back mid-fade stops fading, and draw order follows request order. Reaching zero stacks
# FADES an effect out before its quad is released.

## Rebuild the quad set from the host's FxRequests; idempotent, and it never names an effect.
func sync(requests: Array[FxRequest]) -> void:
	var seen : Dictionary[StringName, bool] = {}
	for i : int in requests.size():
		var req : FxRequest = requests[i]
		seen[req.id] = true
		var fx : Effect = null
		if _fx.has(req.id): fx = _fx[req.id]
		if not fx:
			fx = Effect.new()
			_make_quad(fx, req)
			_fx[req.id] = fx
			add_child(fx.quad)
		else:
			fx.fade = -1.0
			fx.from = _eased(fx)
			fx.t = 0.0
			fx.box_from = fx.req.instance_half
		fx.req = req
		_size_quad(fx)
		_apply_static(fx, req)
		move_child(fx.quad, i)
	for id : StringName in _fx:
		if not seen.has(id) and _fx[id].fade < 0.0:
			_fx[id].from = _eased(_fx[id])
			_fx[id].fade = 0.0
	_resolve_phase_period()
	set_process(not _fx.is_empty())
	if not _fx.is_empty(): _push_live(0.0)

## The shared clock's period: the longest any live effect declares, a fading one included.
func _resolve_phase_period() -> void:
	_phase_period = 0.0
	for id : StringName in _fx:
		_phase_period = maxf(_phase_period, _fx[id].req.phase_period)

# A QuadMesh, never a ColorRect: a Control joins the GUI input pass and eats card grabbing. The Shader
# is SHARED (a duplicate recompiles per card). ⚠ An instanced request gets a MultiMeshInstance2D whose
# mesh is ONE subject: `vertex()` places each from its index, so no transform is ever written.

# ⚠ Physics interpolation is OFF on the MultiMeshInstance2D: Godot warns when an instance transform
# is written outside physics process, and every transform here is identity for the effect's life.

## The drawn node for one effect, carrying the HOST's seed and direction.
func _make_quad(fx: Effect, req: FxRequest) -> void:
	fx.mesh = QuadMesh.new()
	fx.mat = ShaderMaterial.new()
	fx.mat.shader = req.shader
	if req.instances.is_empty():
		var quad := MeshInstance2D.new()
		quad.mesh = fx.mesh
		fx.quad = quad
	else:
		fx.multi = MultiMesh.new()
		fx.multi.transform_format = MultiMesh.TRANSFORM_2D
		fx.multi.use_custom_data = true
		fx.multi.mesh = fx.mesh
		var multi := MultiMeshInstance2D.new()
		multi.multimesh = fx.multi
		multi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		fx.quad = multi
	fx.quad.name = String(req.id)
	fx.quad.material = fx.mat
	fx.mat.set_shader_parameter(&"u_seed", _seed)
	fx.mat.set_shader_parameter(&"u_ball_dir", _ball_dir)

# A world-aligned quad must bound the host AT EVERY ROTATION plus the effect's reach, so a turned host
# takes its circumscribed extent, but only while ACTUALLY turned (`_rot_tight`; up to 0.455 ms of the
# worst window). A deformed host is bounded by its LIVE reach.

# ⚠ The non-instanced extent is ROUNDED to whole art units: `track_outline` sizes every frame and the
# mesh must not churn. An instanced extent is NOT: it is sized to one subject on the pixel-cell
# lattice (`FxRequest.instance_half`), and whole art units would slice its outer ring.

# A MultiMesh's custom_aabb spans where its instances CAN go, or Godot culls every identity-transform
# instance against one mesh-sized box. The partner's pixel is pushed unconditionally, so a plume snaps
# on its ball's lattice whatever the build order.

## Size an effect's quad, and its culling bounds, to what it can draw.
func _size_quad(fx: Effect) -> void:
	var req := fx.req
	var half := Vector2(maxf(req.instance_half.x, fx.box_from.x),
			maxf(req.instance_half.y, fx.box_from.y))
	var extent := half * 2.0
	if req.instances.is_empty():
		var bound := _poly_half * 2.0 if not _poly.is_empty() else body
		if rotates and req.rotates_with_host and not _rot_tight:
			bound = Vector2.ONE * maxf(body.length(), _poly_max * 2.0)
		extent = bound + Vector2.ONE * (req.reach + FX_MARGIN) * 2.0
	if not extent.is_equal_approx(fx.extent):
		fx.extent = extent
		fx.mesh.size = extent
		fx.mat.set_shader_parameter(&"u_extent", extent)
	var span := extent.length() if req.instances.is_empty() \
			else extent.length() + req.reach * 2.0
	_cull_reach = maxf(_cull_reach, span)
	if fx.multi:
		var bound := req.instance_bound + half
		fx.multi.custom_aabb = AABB(Vector3(-bound.x, -bound.y, -1.0),
				Vector3(bound.x * 2.0, bound.y * 2.0, 2.0))
	var mat := fx.mat
	if req.partner_id != &"":
		mat.set_shader_parameter(&"u_partner_pixel", req.partner_pixel)

# Called on creation and restyle, never per frame. The host's POSE is seeded here because `_push_live`
# sends it only on change; a deformed silhouette is pushed instead of the authored body; and the
# player's fx_intensity multiplies every effect (zero turns the board's FX off).

# ⚠ `pushed` is CLEARED because style.apply() writes BASE values for names the eased set also owns,
# so the next frame must put the live values back.

## Write an effect's STATIC uniforms: its style's levers plus the host facts that never change.
func _apply_static(fx: Effect, req: FxRequest) -> void:
	var mat := fx.mat
	if fx.multi:
		fx.multi.instance_count = req.instances.size()
		for i : int in req.instances.size():
			fx.multi.set_instance_transform_2d(i, Transform2D.IDENTITY)
			fx.multi.set_instance_custom_data(i, req.instances[i])
	if req.style: req.style.apply(mat)
	mat.set_shader_parameter(&"u_shape", req.shape if req.shape >= 0 else int(shape))
	mat.set_shader_parameter(&"u_half", int(half))
	if not is_nan(_sent_rot):
		mat.set_shader_parameter(&"u_shape_rot", _sent_rot)
		mat.set_shader_parameter(&"u_lag", _sent_lag)
	if _poly.is_empty(): mat.set_shader_parameter(&"u_body", body)
	else: _push_poly(mat)
	if _art:
		mat.set_shader_parameter(&"u_art", _art)
		mat.set_shader_parameter(&"u_art_rect", _art_rect)
		mat.set_shader_parameter(&"u_art_size", _art_size)
		mat.set_shader_parameter(&"u_art_flip", -1.0 if flipped else 1.0)
	var lit : float = req.style.brightness if req.style else 1.0
	mat.set_shader_parameter(&"u_brightness", lit * settings().fx_intensity)
	for key : StringName in req.snap:
		mat.set_shader_parameter(key, req.snap[key])
	fx.pushed = false

## Embers a second per stack, under the style's per-source ceiling.
const EMBER_PER_STACK := 3.0

# The attachment owns NO particles, so a freed host cannot take its embers with it. They spawn along
# the top edge scattered by the flame height, an approximation on purpose, or for ball fire on a
# random LIT ball (owner wanted embers on balls too; an unlit ball throws none).

## Hand this effect's embers to ParticleEngine and forget them.
func _emit_embers(fx: Effect, scaled_delta: float, vals: Dictionary[StringName, float]) -> void:
	var style := fx.req.style
	if not ambient or not style or not style.ember or fx.fade >= 0.0: return
	var balls := fx.req.shape == Shape.BALLS
	var sources : float = float(fx.req.lit.size()) if balls else vals.get(&"u_count", 0.0)
	var rate := minf(sources * EMBER_PER_STACK, style.ember_rate_max)
	if rate <= 0.0: return
	fx.emit_debt += rate * scaled_delta
	while fx.emit_debt >= 1.0:
		fx.emit_debt -= 1.0
		ParticleEngine.spawn(style.ember, to_global(_ember_origin(fx, vals, balls)), 1)

# ⚠ `u_height` is EASED for a card's fire and STATIC for a plume, so the style fallback is where a
# ball's height lives, not a defence. The path comes from the same eased values the shader got this
# frame, and the ember leaves off the ball's TOP, where its plume sits.

## Where one ember is born, in the host's local art units.
func _ember_origin(fx: Effect, vals: Dictionary[StringName, float], balls: bool) -> Vector2:
	var fire := fx.req.style as FxFireStyle
	var height : float = vals.get(&"u_height", fire.height if fire else 0.0)
	if not balls:
		return Vector2(randf_range(-body.x, body.x) * 0.5, -body.y * 0.5 - randf() * height)
	var radius : float = vals.get(&"u_ball_radius", 0.0)
	var count : float = vals.get(&"u_ball_count", 1.0)
	var span : float = vals.get(&"u_span", 0.0)
	var top : float = vals.get(&"u_arc_height", 0.0)
	var bottom : float = vals.get(&"u_return_height", 0.0)
	var arcs : float = vals.get(&"u_ball_arcs", 2.0)
	var f : float = vals.get(&"u_top_fraction", 0.6)
	var g : float = vals.get(&"u_ball_gravity", 1.0)
	var i : int = fx.req.lit[randi() % fx.req.lit.size()]
	var at := FxJuggle.ball_pos(float(i), maxf(count, 1.0), _phase, span, top, bottom,
			f, g, _ball_dir, arcs)
	return at + Vector2(0.0, -radius - randf() * height)

## Re-apply every live effect's static uniforms, so a settings change reaches effects on screen.
func _restyle() -> void:
	for id : StringName in _fx:
		_apply_static(_fx[id], _fx[id].req)

# Every value rides the same ease, the COUNT included: it drives a comb that partitions the emitting
# width into n cells, so an integer step would re-partition the width and teleport every flame.

## The effect's data-derived values at its current ease position.
func _eased(fx: Effect) -> Dictionary[StringName, float]:
	var out : Dictionary[StringName, float] = {}
	var t := clampf(fx.t, 0.0, 1.0)
	for key : StringName in fx.req.live:
		var to : float = fx.req.live[key]
		var f : float = fx.from[key] if fx.from.has(key) else to
		out[key] = lerpf(f, to, t)
	return out

# The quad cancels the host's rotation so the FX pixel grid holds still in world space. Nothing here
# freezes for a game state (owner): pacing only ever SCALES the clock.

## Advance the clock and the transitions, and let the flames trail the host's motion.
func _process(delta: float) -> void:
	var scaled := delta * pacing()
	_time += scaled
	_update_lag(delta)
	_push_live(scaled)

# From global_position ONLY - the host's rotation and basis3d must not tilt the flames (owner). A
# spring toward the trail the speed calls for: the damping lets the tips overshoot, the cape snap.

## Flames trail the host like a cape: the tips lag its motion and overshoot when it stops.
func _update_lag(delta: float) -> void:
	if not ambient: return
	var pos := global_position
	var vel := (pos - _last_pos) / maxf(delta, 1e-4)
	_last_pos = pos
	if vel.length() < LAG_DEADZONE: vel = Vector2.ZERO
	var target := (-vel * LAG_GAIN).limit_length(LAG_MAX)
	_lag_vel += ((target - _lag) * LAG_STIFFNESS - _lag_vel * LAG_DAMPING) * delta
	_lag = (_lag + _lag_vel * delta).limit_length(LAG_MAX)

# In VIEWPORT space, the only one that includes the play area's scroll and the camera; generous on
# purpose (`_cull_reach` only grows). ⚠ Never culls in the editor, where both spaces belong to the
# editor window and culling froze the FX editor's effects (owner report).

# ⚠ Outside the tree is "not on screen", the true answer: a split prop's halves are orphans at their
# first `sync`, asking the viewport there errors every frame, and uploads resume once parented.

## Whether any of this host's quads can reach the screen this frame.
func _on_screen() -> bool:
	if Engine.is_editor_hint(): return true
	if not is_inside_tree(): return false
	var scaled := _cull_reach * maxf(global_scale.x, global_scale.y) * 0.5
	var at := get_global_transform_with_canvas().origin
	return get_viewport_rect().grow(scaled).has_point(at)

# ⚠ ~15 uploads per quad per frame were the board's biggest FX cost (4.21 ms, 78 hosts, Intel UHD).
# Only the clock and the phase are per frame; the pose and the eased set are sent on CHANGE, and the
# phase advances once from the period `sync` resolved.

# ⚠ AN OFF-SCREEN HOST SKIPS ITS UPLOADS AND NOTHING ELSE: the clocks, eases and fades still run, or a
# card would come back teleported or at full opacity; the pose is recorded as sent only once it was.
# Crossing upright re-sizes the quads, so a spinning card pays two resizes a spin.

# ⚠ The eased set is evaluated and pushed only while its ease runs, on screen, and cached in `fx.vals`
# for the ember emitter, which is gated on the same flag and so sees this frame's geometry.

## Push the per-frame uniforms, advance each ease, and release effects whose fade finished.
func _push_live(scaled_delta: float) -> void:
	var parent := get_parent() as Node2D
	if not parent: return
	var rot := parent.global_rotation
	rotation = -rot
	var secs := transition_secs()
	var step : float = 1.0 if secs <= 0.0 else scaled_delta / secs
	var lag_norm := _lag / maxf(body.x, 1.0)
	var moved := not is_equal_approx(rot, _sent_rot) or not lag_norm.is_equal_approx(_sent_lag)
	var on_screen := _on_screen()
	if moved and on_screen:
		_sent_rot = rot
		_sent_lag = lag_norm
		var tight := absf(rot) < TIGHT_ROT
		if tight != _rot_tight:
			_rot_tight = tight
			for id : StringName in _fx: _size_quad(_fx[id])
	if _phase_period > 0.0: _phase = fmod(_phase + scaled_delta / _phase_period, 1.0)
	var done : Array[StringName] = []
	for id : StringName in _fx:
		var fx : Effect = _fx[id]
		fx.t = minf(fx.t + step, 1.0)
		if fx.t >= 1.0 and fx.box_from != Vector2.ZERO:
			fx.box_from = Vector2.ZERO
			_size_quad(fx)
		var mat := fx.mat
		if on_screen:
			mat.set_shader_parameter(&"u_time", _time)
			if fx.req.phase_period > 0.0: mat.set_shader_parameter(&"u_phase", _phase)
			if moved:
				mat.set_shader_parameter(&"u_shape_rot", rot)
				mat.set_shader_parameter(&"u_lag", lag_norm)
		if on_screen and (fx.t < 1.0 or not fx.pushed):
			fx.vals = _eased(fx)
			fx.pushed = fx.t >= 1.0
			for key : StringName in fx.vals:
				mat.set_shader_parameter(key, fx.vals[key])
		if on_screen: _emit_embers(fx, scaled_delta, fx.vals)
		if fx.fade >= 0.0:
			fx.fade = minf(fx.fade + step, 1.0)
			if on_screen:
				var base : float = fx.req.style.opacity if fx.req.style else 1.0
				mat.set_shader_parameter(&"u_opacity", base * (1.0 - fx.fade))
			if fx.fade >= 1.0: done.append(id)
	for id : StringName in done:
		_fx[id].quad.queue_free()
		_fx.erase(id)
	if not done.is_empty(): _resolve_phase_period()
	set_process(not _fx.is_empty())
