@tool
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

## The settings the FX read. `@tool` because UI/Fx/Tools/fx_editor.tscn previews real effects in the
## editor — and the editor instantiates NO autoloads, so `SettingsManager` is not there. The shipped
## defaults stand in, which is also what a tuning tool should be showing.
static var _editor_settings : PlayerSettings = null
static func settings() -> PlayerSettings:
	if not Engine.is_editor_hint(): return SettingsManager.settings
	if not _editor_settings: _editor_settings = PlayerSettings.new()
	return _editor_settings

## Shape kinds, mirroring the constants in fire.gdshader. GDScript and GLSL cannot share an enum,
## so the mapping exists twice and can drift silently — the FX ATTACHMENT suite asserts it.
##
## A card is a BOX and a deformed one needs the 32-tap radius table, so that is its own kind rather
## than every card paying for a lookup it does not use. Every TEXTURED kind is a SPRITE and answers
## with its own alpha — which is the only representation that knows a hoop has a hole in it. BALLS
## is a shape too, not a mode: the fire shader treats a juggled ball exactly like a card
## (owner 2026-07-30, *"no special ball case"*).
enum Shape { BOX = 0, RADII = 1, SPRITE = 2, BALLS = 3 }

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

## Whether the host's ART is currently MIRRORED (PropVisual.face_travel mirrors a blade to face its
## travel). The mask IS the art now, so it has to mirror with it or a blade heading right emits off
## the outline it no longer has. One sign, re-pushed only when it actually changes.
var flipped : bool = false:
	set(value):
		if flipped == value: return
		flipped = value
		_restyle()

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
## shaders — the fire's noise offset, the whole-effect pulse, ball spin — is keyed on it.
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
	# No autoloads exist in the editor, where the FX EDITOR tool hosts these nodes (§4g).
	if not Engine.is_editor_hint():
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
## SHAPE_SPRITE: the sheet the mask is read out of, the frame inside it in NORMALIZED uv, and the
## size that frame is drawn at (centred on the host's origin). Set by measure_sprite_silhouette.
var _art : Texture2D = null
var _art_rect : Vector4 = Vector4(0.0, 0.0, 1.0, 1.0)
var _art_size : Vector2 = Vector2.ONE

## Entries in the radius table. 32, NOT 16: the star rig deforming a card goes up to 16 arms, and
## 16 samples cannot represent 16 alternating features (Nyquist) — at 16 the arms either smooth
## into a blob or beat against the grid depending on phase. Must match RADII in fire.gdshader.
const RADII := 32

## The widest entry in `_radii`, in art units — half the CIRCUMSCRIBED extent of the silhouette as it
## is RIGHT NOW. `_size_quad` bounds a rotating host's quad with it, so a deformed card's stretched
## corner cannot push its flames past the quad edge.
var _radii_max : float = 0.0
## The deformed outline's tight half-extents. Pushed as `u_body` on the RADII quads, because that is
## what the comb divides — a corner stretched 5 units out of the nominal 38x50 has no cell over it
## otherwise, and the fire stops short of the very corner that moved.
var _radii_half : Vector2 = Vector2.ZERO
## Scratch for `_fill_radii_from_outline`, allocated once: this runs per frame on every card on the
## board, and a fresh table per card per frame is exactly the churn it must not add.
var _next := PackedFloat32Array()
var _angles := PackedFloat32Array()

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
		_radii_max = 0.0
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
	_radii_max = 0.0
	for r : float in _radii: _radii_max = maxf(_radii_max, r)
	_radii_half = body * 0.5
	# ⚠ THE TABLE IS A RADIAL SCALE, NOT A RADIUS — the same contract `_fill_radii_from_outline`
	# writes, and it has to be converted HERE too or this path feeds the shader radii it will read as
	# scales. See that function for why the shader wants scales at all (the corner chamfer).
	for i : int in RADII:
		_radii[i] /= maxf(_rect_radius(float(i) * TAU / float(RADII), _radii_half), 1e-4)
	shape = Shape.RADII
	_restyle()

# --- THE DEFORMING SILHOUETTE (owner 2026-07-29) --------------------------------------------------
#
# A card is NOT the 38x50 rectangle it is authored as: its face polygons are skinned to a star rig
# whose arms stretch the corners out and pull them back every frame, and the shipped animation is on
# AUTOPLAY. `measure_silhouette` above bakes the REST outline once, so the flames stood on a shape
# the card no longer had — the fire held still while the card's top edge moved under it, which is
# exactly the report ("fire effect doesn't warp with the card").
#
# The fix is to re-read the rig, not to make the shader guess: the rig IS the deformation, and the
# radius table the mask already uses is exactly the right shape to carry it. Pixels distort and leave
# the grid where a corner stretches, which the owner ruled acceptable here — the card's own art
# already does the same thing under the same rig.

## Bind the silhouette to an ORDERED outline and switch the mask to the radius table. The setup call:
## `track_outline` is the per-frame one.
##
## ⚠ `outline` must run ONCE around the silhouette so its points' angles increase monotonically —
## which is what a rig walked edge by edge gives. That contract is what lets each of the 32 rays be
## resolved by one segment intersection in a single merged walk (32 + n steps, not 32 * n), and it is
## the whole reason this is cheap enough to run every frame on every card on the board. Unordered
## points — a triangulated `Polygon2D`, say — belong in `measure_silhouette`, which buckets instead.
func measure_outline(outline: PackedVector2Array) -> void:
	if outline.size() < 3:
		shape = Shape.BOX
		_radii = PackedFloat32Array()
		_radii_max = 0.0
		_restyle()
		return
	_fill_radii_from_outline(outline)
	shape = Shape.RADII
	_restyle()

## Re-read the deformed outline and push it to the live quads. Called every frame by a host whose rig
## moves; a no-op on the frames where it did not, which is most of them once the card settles.
##
## Only `u_radii` and `u_body` reach the GPU — never the ~35 static style levers `_restyle` pushes.
## The quads are re-sized too, because a stretched corner reaches further than the rest bound they
## were built for and would clip against their own edge.
func track_outline(outline: PackedVector2Array) -> void:
	if shape != Shape.RADII or outline.size() < 3: return
	if not _fill_radii_from_outline(outline): return
	for id : StringName in _fx:
		var fx : Effect = _fx[id]
		# A request may override the host's shape (ball fire rides the BALLS, not the card it is on),
		# and those quads read neither table.
		if fx.req.shape >= 0 and fx.req.shape != int(Shape.RADII): continue
		var mat := fx.quad.material as ShaderMaterial
		mat.set_shader_parameter(&"u_radii", _radii)
		mat.set_shader_parameter(&"u_body", _radii_half * 2.0)
		_size_quad(fx.quad, fx.req)

## Resolve `outline` into the radius table. Returns whether anything actually moved — the early-out
## that keeps a still card free.
##
## Each ray is intersected with the ONE outline segment that spans its angle, so the table is the
## exact star rather than an angular histogram of it: bucketing 16 arms into 32 slots and filling the
## gaps with a neighbour's maximum inflates the shape by up to ~5 art units between a corner and the
## edge sample beside it, which reads as a lump of flame standing off the card.
func _fill_radii_from_outline(outline: PackedVector2Array) -> bool:
	var n := outline.size()
	_angles.resize(n)
	# The walk has to START at the lowest angle, or the two sequences cannot advance together: an
	# outline ordered around the shape is monotonic in angle only up to ONE wrap, and this is where
	# that wrap is cut.
	var start := 0
	for i : int in n:
		_angles[i] = fposmod(atan2(outline[i].x, -outline[i].y), TAU)
		if _angles[i] < _angles[start]: start = i
	_next.resize(RADII)
	var half := Vector2.ZERO
	for p : Vector2 in outline:
		half = Vector2(maxf(half.x, absf(p.x)), maxf(half.y, absf(p.y)))
	var j := 0
	var top := 0.0
	for k : int in RADII:
		var a := float(k) * TAU / float(RADII)
		while j < n - 1 and _angles[(start + j + 1) % n] <= a: j += 1
		var i0 := (start + j) % n
		var i1 := (start + j + 1) % n
		# Outside the monotonic run at either end is the CLOSING segment, from the last point back to
		# the first — the one the wrap cut in half.
		if a < _angles[i0] or (j >= n - 1 and a >= _angles[i1]):
			i0 = (start + n - 1) % n
			i1 = start
		# ⚠ THE TABLE HOLDS A RADIAL SCALE, NOT A RADIUS — this is the fix for "fire licks DOWN the
		# side of a card from each top corner" (owner, twice). Storing `r(a)` means the shader has to
		# interpolate a function with a CORNER in it, and no interpolation between two rays can
		# reproduce a vertex: at 32 rays a 38x50 card's corner (37.23 deg, sampled at multiples of
		# 11.25) came out chamfered by 2.32 art units, and a chamfer is a real upward-facing slope, so
		# fire stood on it — correctly, which is why more rays only ever made it smaller.
		#
		# Dividing by the REST rectangle's radius at the same angle turns the table into `1.0`
		# everywhere on an undeformed card, so the shader's test becomes the EXACT box and the corner
		# is exact too. A deformation shows up as a smooth field near 1 with no vertex in it, which is
		# the one thing that interpolates well. (FX_HANDOFF §10 E, taken.)
		var hit := _ray_hit(a, outline[i0], outline[i1])
		_next[k] = hit / maxf(_rect_radius(a, half), 1e-4)
		# `top` stays a real RADIUS: it sizes the quad, which knows nothing about scales.
		top = maxf(top, hit)
	var moved := _radii.size() != RADII or not is_equal_approx(top, _radii_max) \
			or not half.is_equal_approx(_radii_half)
	if not moved:
		for k : int in RADII:
			# A twentieth of an art unit is well under one FX pixel, so anything below it cannot move
			# a rendered flame and is not worth an upload.
			if absf(_next[k] - _radii[k]) > 0.05:
				moved = true
				break
	if not moved: return false
	_radii = _next.duplicate()
	_radii_max = top
	_radii_half = half
	return true

## How far the ray at angle `a` (from straight up) reaches before it leaves the REST rectangle of
## half-extent `half` — the denominator that turns the measured radius into a scale. Exactly the
## closed form `mask_level`'s box branch tests against, so an undeformed outline divides out to 1.0
## at every ray and the two branches agree to the bit.
func _rect_radius(a: float, half: Vector2) -> float:
	var d := Vector2(sin(a), -cos(a))
	return minf(half.x / maxf(absf(d.x), 1e-9), half.y / maxf(absf(d.y), 1e-9))

## How far the ray at angle `a` (from straight up) reaches before it crosses segment p->q, in art
## units. Zero where the segment is edge-on to the ray, which leaves the previous entry standing.
func _ray_hit(a: float, p: Vector2, q: Vector2) -> float:
	var d := Vector2(sin(a), -cos(a))
	var s := q - p
	var den := d.cross(s)
	if absf(den) < 1e-6: return p.length()
	return maxf(p.cross(s) / den, 0.0)

## Point this attachment at a SPRITE's own sheet, so the fire shader reads the drawing's ALPHA as its
## mask, and tighten `body` to the art.
##
## The mask itself is sampled LIVE in the shader — nothing about the outline is baked here, which is
## what lets a host turn without going stale, and what lets a shape with a HOLE in it (the hoop) be
## represented at all. What is measured here is only the art's tight bounding box, and only because a
## frame is mostly transparent padding: the ball pip is a small blob in an 8x8 cell, so a comb spanning
## the frame put flames in empty space beside the drawing (owner report 2026-07-29).
##
## `src` is the frame's rect in sheet pixels; `size` is the art units that frame is drawn at.
##
## ⚠ CACHED PER FRAME RECT, and that is not an optimization — it is a HITCH FIX. The scan is
## `Image.get_pixel` over the frame (2304 calls for one hoop frame) on top of a `Texture2D.get_image`
## decode, and it runs once per ATTACHMENT: a split prop has three (whole, back, front), so every
## hoop that spawned paid for the same 32x72 frame three times, on the frame it appeared. That was
## enough to make `test_ui_props`'s per-arrival pulse poll miss its peak. A sheet never changes at
## runtime, so one entry per frame rect serves the whole run.
static var _sprite_cache : Dictionary[String, Array] = {}

func measure_sprite_silhouette(sheet: Texture2D, src: Rect2, size: Vector2) -> void:
	if not sheet: return
	var key := "%s|%s|%s" % [sheet.resource_path, src, size]
	if _sprite_cache.has(key):
		var hit : Array = _sprite_cache[key]
		if hit.is_empty():
			shape = Shape.BOX                              # nothing drawn: leave it a box
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
	# Tight bounds of the opaque texels, in TEXELS first.
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
		shape = Shape.BOX                              # nothing drawn: leave it a box
		return
	# The art's tight box becomes the BODY, so the comb width and the quad bound are measured against
	# the drawing rather than the padding around it.
	var texel := size / Vector2(float(w), float(h))
	body = Vector2(float(max_x - min_x + 1), float(max_y - min_y + 1)) * texel
	# The FRAME, in normalized sheet uv, plus the size it is drawn at. Deliberately the whole frame
	# and not the tight box: the art is drawn centred on the host's origin, and the tight box is not
	# centred on it, so mapping through the tight box would slide the whole mask sideways.
	var sheet_size := Vector2(float(img.get_width()), float(img.get_height()))
	_art = sheet
	_art_rect = Vector4(src.position.x / sheet_size.x, src.position.y / sheet_size.y,
			src.size.x / sheet_size.x, src.size.y / sheet_size.y)
	_art_size = size
	_sprite_cache[key] = [body, _art_rect]
	shape = Shape.SPRITE
	_restyle()

## Ratio of the base delay to the LIVE delay: 1.0 at rest, above 1 as act compression speeds
## everything up, so ambient FX quicken in lockstep with card and prop animation. Null-safe: an
## FX host in a viewer or in a test has no game and simply runs at rest pace.
static func pacing() -> float:
	var game := CardEnvironment.get_current_game()
	if not game: return 1.0
	return settings().base_delay / maxf(game.get_delay(), 0.001)

## How long a stack change takes. The owner's metric is "fast enough before the next status effect
## gets applied", and statuses land on PROP TICKS — so this is a fraction of one prop tick,
## re-derived live like every other timing here, never a wall-clock number and never a guess.
##
## Read from the Game rather than through play_area.prop_layer: a card in the deck viewer has no
## play area, and it must ease exactly like a board card (ruling 18) rather than snapping.
## Under heavy compression the delay approaches its floor and transitions snap — which is already
## how prop motion behaves there, so the whole board degrades consistently.
static func transition_secs() -> float:
	var s := settings()
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
##
## ⚠ It takes BOTH a turning host and an effect that turns with it (`FxRequest.rotates_with_host`).
## A juggling pattern does not turn with its card, so it keeps the box bound even on a card that
## spins through every angle — ~22 % of that quad's fill, for free (FX_HANDOFF §1b.3).
## ⚠ A DEFORMED host is bounded by its LIVE reach, not by its authored box. The star rig stretches a
## card's corners ~5 art units past the 38x50 it is authored as, and a quad built for the rest pose
## clips the flames standing on the part that moved.
func _size_quad(quad: MeshInstance2D, req: FxRequest) -> void:
	var bound := body
	if rotates and req.rotates_with_host:
		bound = Vector2.ONE * maxf(body.length(), _radii_max * 2.0)
	var extent := bound + Vector2.ONE * (req.reach + FX_MARGIN) * 2.0
	(quad.mesh as QuadMesh).size = extent
	# UV maps across exactly the quad, so the shader needs the same number to recover art units.
	var mat := quad.material as ShaderMaterial
	mat.set_shader_parameter(&"u_extent", extent)
	# An effect that draws ON another effect is handed the PARTNER's PIXEL, so the ball-fire plume
	# snaps on the lattice its ball was drawn on (FxRequest.partner_id).
	#
	# ⚠ The partner's EXTENT is no longer part of this, and that is a simplification the pixel-grid
	# fix bought: the lattice is anchored on the host's ORIGIN now, so two quads of different sizes
	# centred on the same host share it exactly and only `pixel` can differ. It used to need the
	# partner's live quad size, which is also why resizing a quad moved the grid.
	# ⚠ Pushed UNCONDITIONALLY, and not gated on the partner's quad existing. It used to read the
	# partner's live size out of `_fx`, which made this depend on BUILD ORDER — and the ball-fire quad
	# is built BEFORE the balls quad now, so that gate would have silently skipped it (FxJuggle
	# .requests puts the plumes in first so the balls draw over them).
	if req.partner_id != &"":
		mat.set_shader_parameter(&"u_partner_pixel", req.partner_pixel)

## Write the STATIC half of an effect's uniforms: its style's ~35 art levers plus the host facts
## that never change. Called on creation and on style swap, never per frame — pushing the whole
## set every frame for every host is the cost the static/live split exists to avoid.
func _apply_static(quad: MeshInstance2D, req: FxRequest) -> void:
	var mat := quad.material as ShaderMaterial
	if req.style: req.style.apply(mat)
	# A request may override the host's shape — that is how ball fire says "my mask is the balls, not
	# the card I am riding on" without the shader needing a mode (owner 2026-07-30).
	mat.set_shader_parameter(&"u_shape", req.shape if req.shape >= 0 else int(shape))
	mat.set_shader_parameter(&"u_half", int(half))
	# The DEFORMED width where the rig holds one: `u_body` is what the comb divides, so a restyle
	# must not stamp the authored rectangle back over the shape the card currently has.
	mat.set_shader_parameter(&"u_body",
			_radii_half * 2.0 if shape == Shape.RADII and _radii_half != Vector2.ZERO else body)
	if not _radii.is_empty(): mat.set_shader_parameter(&"u_radii", _radii)
	if _art:
		mat.set_shader_parameter(&"u_art", _art)
		mat.set_shader_parameter(&"u_art_rect", _art_rect)
		mat.set_shader_parameter(&"u_art_size", _art_size)
		mat.set_shader_parameter(&"u_art_flip", -1.0 if flipped else 1.0)
	# The player's master effect strength, on top of the style's own brightness — so a "reduce
	# effects" setting reaches every effect without editing a single .tres, and reaching zero
	# turns the board's FX off entirely (a genuine photosensitivity control, not a taste one).
	var lit : float = req.style.brightness if req.style else 1.0
	mat.set_shader_parameter(&"u_brightness", lit * settings().fx_intensity)
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
## tips are carved by noise in the shader, and mirroring that in GDScript to find them would be
## exactly the duplicated-motion bug the shared include exists to prevent.
##
## BALL fire is the exception, and it has to be: the host is the CARD, so the host's top edge would
## pour embers off the card while the flames are out on the balls (owner 2026-07-29 wanted embers on
## *props and balls* too). Those spawn on a randomly chosen ALIGHT ball, whose position comes from
## FxJuggle.ball_pos — the one script-side copy of the path, and the one this may call.
func _emit_embers(fx: Effect, scaled_delta: float, vals: Dictionary[StringName, float]) -> void:
	var style := fx.req.style
	if not ambient or not style or not style.ember or fx.fade >= 0.0: return
	# A ball effect's sources are the LIT balls, not the ball count: an unlit ball is not on fire and
	# has nothing to throw (ruling 3 — each individual ball burns or does not).
	var balls := fx.req.shape == Shape.BALLS
	var sources : float = float(fx.req.lit.size()) if balls else vals.get(&"u_count", 0.0)
	var rate := minf(sources * EMBER_PER_STACK, style.ember_rate_max)
	if rate <= 0.0: return
	fx.emit_debt += rate * scaled_delta
	while fx.emit_debt >= 1.0:
		fx.emit_debt -= 1.0
		ParticleEngine.spawn(style.ember, to_global(_ember_origin(fx, vals, balls)), 1)

## Where one ember is born, in the host's local art units.
func _ember_origin(fx: Effect, vals: Dictionary[StringName, float], balls: bool) -> Vector2:
	var height : float = vals.get(&"u_height", 0.0)
	if not balls:
		return Vector2(randf_range(-body.x, body.x) * 0.5, -body.y * 0.5 - randf() * height)
	var radius : float = vals.get(&"u_ball_radius", 0.0)
	var count : float = vals.get(&"u_ball_count", 1.0)
	var span : float = vals.get(&"u_span", 0.0)
	var top : float = vals.get(&"u_arc_height", 0.0)
	var bottom : float = vals.get(&"u_return_height", 0.0)
	var arcs : float = vals.get(&"u_ball_arcs", 2.0)
	# The path's timing, out of the SAME eased values the shader was handed this frame
	# (FxJuggle.geometry). It used to come off `fx.req.style` — but the style of a BALL-FIRE request is
	# a FIRE style, so the embers were placed with the fire style's idea of the path while the balls
	# flew on the juggle style's. Two copies again; there is one now.
	var f : float = vals.get(&"u_top_fraction", 0.6)
	var g : float = vals.get(&"u_ball_gravity", 1.0)
	var i : int = fx.req.lit[randi() % fx.req.lit.size()]
	# The EASED geometry and the host's own phase and direction — the same numbers the shader was
	# handed this frame, so the ember leaves the ball where the ball was actually drawn.
	var at := FxJuggle.ball_pos(float(i), maxf(count, 1.0), _phase, span, top, bottom,
			f, g, _ball_dir, arcs)
	# Off the TOP of the ball, where its plume sits — never its centre, which is inside the ball.
	return at + Vector2(0.0, -radius - randf() * height)

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

## Whether any of this host's quads can reach the screen this frame.
##
## Measured in VIEWPORT space (`get_global_transform_with_canvas`), which is the only space that
## already accounts for the play area's scroll, the camera and every parent transform — a card
## scrolled out of the play area is off screen even though its global position never moved.
##
## ⚠ GENEROUS BY DESIGN. The margin is the largest quad this host owns, at this host's own scale, so
## a quad whose centre is off screen while its flames are not still gets its uniforms. Being wrong in
## this direction costs a few uploads; being wrong in the other freezes an effect in view.
func _on_screen() -> bool:
	# ⚠ NEVER CULL IN THE EDITOR — it FROZE THE TUNING TOOL (owner report 2026-07-29: *"card fire not
	# animating in fx editor... juggling balls not animating either, just static"*). Both spaces this
	# reads belong to the running game: `get_viewport_rect()` is the editor WINDOW rather than the 2D
	# view, and `get_global_transform_with_canvas()` carries the editor's own pan and zoom — so a host
	# the user has scrolled or zoomed lands "off screen", its uploads stop, and every effect on it
	# sticks on the last frame it was told about. ⚠ The CLOCKS keep running (they are advanced above
	# this call, unconditionally), which is exactly why it reads as FROZEN rather than as stopped, and
	# why nothing about it looks like a clock bug.
	#
	# There is nothing to save here either: this cull exists for a board of 78 hosts, and
	# `fx_editor.tscn` has six.
	if Engine.is_editor_hint(): return true
	var reach := 0.0
	for id : StringName in _fx:
		reach = maxf(reach, (_fx[id].quad.mesh as QuadMesh).size.length())
	var scaled := reach * maxf(global_scale.x, global_scale.y) * 0.5
	var at := get_global_transform_with_canvas().origin
	return get_viewport_rect().grow(scaled).has_point(at)

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
	# ⚠ AN OFF-SCREEN HOST STILL PAYS FOR ITS UNIFORMS, and that is the one way an invisible card is
	# NOT free. Godot culls the QUADS — measured 2026-07-29, 312 hosts with 78 on screen cost the same
	# GPU time as the 78 alone — but nothing culls this function, and it is ~15 `set_shader_parameter`
	# calls per quad per frame. On that run the 234 invisible hosts added ~7 ms of pure CPU: more than
	# the whole visible board's GPU cost.
	#
	# The CLOCKS above are advanced first and unconditionally — they are a few floats, and freezing
	# them would teleport every ball the moment a scroll brought its card back into view. What is
	# skipped is only the UPLOAD, which nobody can see the result of.
	if not _on_screen(): return
	var done : Array[StringName] = []
	for id : StringName in _fx:
		var fx : Effect = _fx[id]
		fx.t = minf(fx.t + step, 1.0)
		var mat := fx.quad.material as ShaderMaterial
		mat.set_shader_parameter(&"u_time", _time)
		mat.set_shader_parameter(&"u_shape_rot", rot)
		mat.set_shader_parameter(&"u_lag", lag_norm)
		if fx.req.phase_period > 0.0: mat.set_shader_parameter(&"u_phase", _phase)
		# Eased FIRST, then emitted from: a ball ember has to be born on the ball this frame DRAWS,
		# and mid-transition the eased geometry is not the request's target geometry.
		var vals := _eased(fx)
		for key : StringName in vals:
			mat.set_shader_parameter(key, vals[key])
		_emit_embers(fx, scaled_delta, vals)
		if fx.fade >= 0.0:
			fx.fade = minf(fx.fade + step, 1.0)
			var base : float = fx.req.style.opacity if fx.req.style else 1.0
			mat.set_shader_parameter(&"u_opacity", base * (1.0 - fx.fade))
			if fx.fade >= 1.0: done.append(id)
	for id : StringName in done:
		_fx[id].quad.queue_free()
		_fx.erase(id)
	set_process(not _fx.is_empty())
