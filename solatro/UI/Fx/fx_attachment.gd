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

## The settings the FX read. `@tool` because Tools/fx_editor.tscn previews real effects in the
## editor — and the editor instantiates NO autoloads, so `SettingsManager` is not there. The shipped
## defaults stand in, which is also what a tuning tool should be showing.
##
## ⚠ **ONE INSTANCE, SHARED BY THE EDITOR AND THE GAME — owner:** *"if playersettings is
## ever in an editor then it should be shared globally and be the one used in actual games, so i never
## need to duplicate settings across different contexts."* This used to return a fresh
## `PlayerSettings.new()` in the editor, so the FX editor, the spotlight tool and the running game
## each held a DIFFERENT settings object and tuning one changed nothing anywhere else. It now loads
## **the same `user://settings.tres` the autoload does** — `user://` resolves to the same folder in
## both — and saves edits back, so a knob turned in a tool is the knob the game runs with.
## ⚠ `ResourceLoader.load` is cached, so every editor caller gets the SAME object rather than a copy.
static var _editor_settings : PlayerSettings = null
static func settings() -> PlayerSettings:
	if not Engine.is_editor_hint(): return SettingsManager.settings
	if _editor_settings: return _editor_settings
	if ResourceLoader.exists(SettingsManagerClass.SAVE_PATH):
		_editor_settings = ResourceLoader.load(SettingsManagerClass.SAVE_PATH)
	if not _editor_settings:
		# First run in a fresh profile: create the shared file rather than an in-memory orphan, or the
		# next context to ask would make its own and we are back to two.
		_editor_settings = PlayerSettings.new()
		ResourceSaver.save(_editor_settings, SettingsManagerClass.SAVE_PATH)
	# Persist edits the same way `SettingsManagerClass.on_settings_changed` does at runtime — without
	# this, tuning in a tool would live only until the editor closed.
	if not _editor_settings.settings_changed.is_connected(_save_editor_settings):
		_editor_settings.settings_changed.connect(_save_editor_settings)
	return _editor_settings

## Write the shared settings back. Editor-side twin of `SettingsManagerClass.save_settings()`.
static func _save_editor_settings() -> void:
	if _editor_settings:
		ResourceSaver.save(_editor_settings, SettingsManagerClass.SAVE_PATH)

## Shape kinds, mirroring the constants in fire.gdshader. GDScript and GLSL cannot share an enum,
## so the mapping exists twice and can drift silently — the FX ATTACHMENT suite asserts it.
##
## A card is a BOX and a deformed one carries its own outline (RADII), so that is its own kind rather
## than every card paying for a lookup it does not use. Every TEXTURED kind is a SPRITE and answers
## with its own alpha — which is the only representation that knows a hoop has a hole in it. BALLS
## is a shape too, not a mode: the fire shader treats a juggled ball exactly like a card
## (owner, *"no special ball case"*).
enum Shape { BOX = 0, RADII = 1, SPRITE = 2, BALLS = 3 }

## Split-prop halves: which side of the silhouette this quad is allowed to emit from.
enum Half { WHOLE = 0, BACK = 1, FRONT = 2 }

## Art units per second of host travel below which the flames ignore the motion entirely. NOT
## optional: a board card is never still — delta_floating_anim bobs and drifts it every frame
## (`CardVisual.delta_floating_anim`) — so an unfiltered velocity makes the flames jitter permanently.
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
	## The drawn node: a MeshInstance2D for a single quad, a MultiMeshInstance2D for an instanced
	## effect. Typed as the common base, and the two things every caller actually wants are held
	## beside it — a MultiMeshInstance2D has no `mesh` or `material` of the shape the sites below
	## expect, and re-deriving them per site is how the two paths would drift.
	var quad : Node2D
	var mesh : QuadMesh
	var mat : ShaderMaterial
	## The instance buffer, or null for a single quad. Its `instance_count` is the live subject count.
	var multi : MultiMesh
	## The instance box the effect is easing OUT of, or zero. `live` values are eased, so a ball
	## shrinking toward a higher count is briefly bigger than its target and would clip against a box
	## built for the target alone. The box is the componentwise MAX of the two ends for the duration —
	## which is exactly their union, because the box grows monotonically with the radius and its centre
	## bias does not ease at all (`u_height` and `u_sink` are static style values on a plume) — and it
	## drops back to the target when the ease lands, so repeated stack changes cannot ratchet it up.
	var box_from : Vector2 = Vector2.ZERO
	## The quad size this effect currently HAS, so re-sizing it is a no-op when nothing moved. See the
	## note in `_size_quad`: a deforming card runs that function every frame.
	var extent : Vector2 = Vector2.ZERO
	## This effect's eased values as of the last frame that computed them. Held rather than recomputed
	## because the EMBER emitter needs them every frame while the shader only needs them while they are
	## actually changing (see _push_live).
	var vals : Dictionary[StringName, float] = {}
	## Whether the settled (t == 1) values have been pushed. Turns the eased set from a per-frame upload
	## into a one-per-transition one.
	var pushed : bool = false
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

# --- per-HOST randomness (owner: effects must not sync up across cards) --------------
## This host's random seed, pushed to EVERY quad it owns rather than rolled per quad: the balls and
## the flames riding them have to agree on it, and two hosts must not share it. Every phase in both
## shaders — the fire's noise offset, the whole-effect pulse, ball spin — is keyed on it.
var _seed : float = randf() * 100.0
## Which way this host's juggling pattern runs — the WHOLE pattern, as one direction, and it is a coin
## flip per host. The crossing comes from the arc ladder alternating its sweep, not from a per-ball
## mirror of this (`fx_ball_pos_ladder` records why a per-ball mirror cancels the ladder's own).
var _ball_dir : float = 1.0 if randf() < 0.5 else -1.0

var _fx : Dictionary[StringName, Effect] = {}
## ONE phase clock for the whole host, shared by every effect that declares a period — which is
## what welds a ball's flame to its ball rather than letting the two drift apart. Starts at a RANDOM
## point in the cycle: from zero, every card that started juggling with the same count moved as one.
var _phase : float = randf()
## That clock's period, resolved in `sync` from the longest any live effect declares — see
## `_resolve_phase_period`. 0 while nothing has a phase.
var _phase_period : float = 0.0
var _lag : Vector2 = Vector2.ZERO
var _lag_vel : Vector2 = Vector2.ZERO
var _last_pos : Vector2 = Vector2.ZERO
## The host pose the quads were last TOLD about, so a still host stops re-sending it (_push_live).
## NAN so the first push always happens, whatever the host's real rotation is.
var _sent_rot : float = NAN
var _sent_lag : Vector2 = Vector2(NAN, NAN)
## Whether the host is square enough to the world for its quads to take their AABB instead of the
## circumscribed diagonal (_size_quad's lever B). Re-evaluated only when the pose changes.
var _rot_tight : bool = true
## How far from upright still counts as upright, in radians. Small enough that what a turned silhouette
## pokes past its own axis-aligned bound stays inside FX_MARGIN.
const TIGHT_ROT := 0.017
## The largest quad this host owns, for the off-screen test — cached because that test ran a loop over
## every effect every frame to recompute a number only `_size_quad` can change.
var _cull_reach : float = 0.0

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

## The host silhouette's own VERTICES, walked once around the shape in the art's frame, or empty while
## the host is a plain box. Pushed as `u_poly`.
var _poly := PackedVector2Array()
## Per WEDGES-th of a turn, the vertex whose wedge spans that slot's start — what lets the shader find
## the right edge with no search. Pushed as `u_wedge`. See `_fill_poly_from_outline`.
var _wedge := PackedFloat32Array()
## SHAPE_SPRITE: the sheet the mask is read out of, the frame inside it in NORMALIZED uv, and the
## size that frame is drawn at (centred on the host's origin). Set by measure_sprite_silhouette.
var _art : Texture2D = null
var _art_rect : Vector4 = Vector4(0.0, 0.0, 1.0, 1.0)
var _art_size : Vector2 = Vector2.ONE

## How many silhouette vertices reach the shader. 24 is what a real card has: the star rig's 16 arms,
## plus two more at each corner because the type art BITES a corner out of its frame and the rig does not
## know that (`CardVisual._rig_outline`). Storing the vertices means the mask is the shape rather than a
## sampling of it. An outline with MORE points than this is resampled at POLY uniform angles, which is the
## old approximation and loses vertices again — the FX ATTACHMENT suite asserts a card's outline fits.
## Must match POLY in fire.gdshader.
const POLY := 24
## Angular slots in the wedge index, and how many consecutive wedges the shader tests per slot. Both must
## match `WEDGES` / `WEDGE_CANDIDATES` in fire.gdshader: a slot is 1/32 of a turn and a corner's three
## BITE points sit inside ~1.5 degrees of each other, so covering one slot can take four wedges. See
## `_fill_poly_from_outline`, and `test_fx_attachment` asserts the bound.
const WEDGES := 32
const WEDGE_CANDIDATES := 4

## The longest vertex, in art units — half the CIRCUMSCRIBED extent of the silhouette as it is RIGHT
## NOW. `_size_quad` bounds a rotating host's quad with it, so a deformed card's stretched corner
## cannot push its flames past the quad edge.
var _poly_max : float = 0.0
## The deformed outline's tight half-extents. Pushed as `u_body` on the RADII quads, because that is
## what the outward fan is measured across and what `body_near` rejects against — a corner stretched 5
## units out of the nominal 40x54 would otherwise sit outside the bound its own flames are built in.
var _poly_half : Vector2 = Vector2.ZERO
## The largest origin-centred box that fits INSIDE the silhouette. Pushed as `u_inner`, where it is the
## mask's early ACCEPT — see `_inner_box`.
var _poly_inner : Vector2 = Vector2.ZERO
## Scratch for `_fill_poly_from_outline`, allocated once: this runs per frame on every card on the
## board, and a fresh table per card per frame is exactly the churn it must not add.
var _next := PackedVector2Array()
var _ring := PackedVector2Array()
var _angles := PackedFloat32Array()
## The incoming outline's angles, in ITS order — `_angles` holds the same values re-wound into `_ring`'s
## order, so this is what makes that a permutation rather than a second round of `atan2`.
var _angles_src := PackedFloat32Array()
## `_poly` padded to the uniform's own length. `_push_poly` runs per quad per frame for any host whose
## rig is shorter than POLY, where a `duplicate()` + `resize()` was TWO buffers per call.
##
## ⚠ IT IS NOT ALLOCATION-FREE AND THE FIRST VERSION OF THIS NOTE CLAIMED IT WAS. `Packed*` arrays are
## copy-on-write, and `set_shader_parameter` stores the Variant — so the material holds a reference and
## the next frame's write into this buffer forks it anyway. What the pad actually saves is the SECOND
## buffer and the re-`resize`, not the allocation itself. Keeping the claim honest matters here because
## it is the kind of thing a later reader would "optimize" again on the strength of a comment.
var _poly_padded := PackedVector2Array()

## Measure the host's real outline into the radius table, so flames hug a deformed card instead of
## its nominal rectangle. Behind a dirty flag by contract: the caller decides when the silhouette
## changed, because sampling a polygon every frame for a shape that almost never moves is exactly
## the kind of per-frame work this design avoids elsewhere.
##
## A simple quad stays Shape.BOX: the box branch is two comparisons, where a polygon costs an `atan`
## and an index. Only a genuinely deformed outline is worth the mask.
##
## ⚠ THIS PATH IS AN APPROXIMATION AND `measure_outline` IS NOT. Unordered points cannot be walked, so
## the silhouette is bucketed into POLY angular slots and one vertex is emitted per slot — which puts
## the vertices at fixed angles rather than where the shape's corners actually are, exactly the
## sampling the exact path exists to avoid. It is the fallback for a host with no rig (a stripped card
## in a test, or art with no skeleton); anything with an ordered outline must use `measure_outline`.
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
		# Angle measured from straight up, the convention every mask path here shares.
		var a := atan2(p.x, -p.y)
		var slot := int(floorf((a / TAU + 1.0) * float(POLY))) % POLY
		radius[slot] = maxf(radius[slot], p.length())
	# An empty angular bucket would read as a radius of zero and tear a notch in the outline, so
	# fill each from its neighbours; two passes settle any run of gaps this table can have.
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

# --- THE DEFORMING SILHOUETTE (owner) --------------------------------------------------
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

## Bind the silhouette to an ORDERED outline and switch the mask to the polygon. The setup call:
## `track_outline` is the per-frame one.
##
## ⚠ `outline` must run ONCE around the silhouette so its points' angles increase monotonically —
## which is what a rig walked edge by edge gives. That contract is what lets the wedge index be built
## in one merged walk (WEDGES + n steps, not WEDGES * n), and it is the whole reason this is cheap
## enough to run every frame on every card on the board. Unordered points — a triangulated
## `Polygon2D`, say — belong in `measure_silhouette`, which buckets instead and is approximate.
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

## Re-read the deformed outline and push it to the live quads. Called every frame by a host whose rig
## moves; a no-op on the frames where it did not, which is most of them once the card settles.
##
## Only the silhouette and `u_body` reach the GPU — never the ~35 static style levers `_restyle`
## pushes. The quads are re-sized too, because a stretched corner reaches further than the rest bound
## they were built for and would clip against their own edge.
func track_outline(outline: PackedVector2Array) -> void:
	if shape != Shape.RADII or outline.size() < 3: return
	# ⚠ DO NOT SHORT-CIRCUIT THIS ON `_fx.is_empty()`, however tempting it looks — an unlit card walks its
	# whole rig here and pushes the result nowhere, which reads like pure waste and was measured at ~24
	# `atan2` plus the wedge index per card per frame across a 78-card board and a 50-card deck viewer.
	# `_poly` IS A PUBLISHED PROPERTY, NOT A CACHE FOR THE QUADS: `test_the_card_mask_is_the_card_the
	# _player_sees` reads it off an UNLIT card, and it has to be unlit, because that check samples the
	# card's own face pixels and flames drawn over them would decide the comparison instead. Skipping the
	# resolve leaves `_poly` at the rest pose while the rig deforms, which the suite reports as the card's
	# own edge left unlit. If this cost has to come down, make the RESOLVE cheaper — it already skips its
	# upload when nothing moved — or have the host stop calling it, which is where the knowledge lives.
	if not _fill_poly_from_outline(outline): return
	for id : StringName in _fx:
		var fx : Effect = _fx[id]
		# A request may override the host's shape (ball fire rides the BALLS, not the card it is on),
		# and those quads read no silhouette at all.
		if fx.req.shape >= 0 and fx.req.shape != int(Shape.RADII): continue
		# ⚠ NOR DOES AN INSTANCED ONE, AND THE SHAPE TEST ABOVE DOES NOT CATCH IT. The juggling BALLS
		# quad leaves `shape` at -1 (it inherits the card's RADII) while drawing one disc per instance
		# in the quad's own space — `juggle.gdshader` declares none of `u_poly`, `u_wedge`,
		# `u_poly_count`, `u_inner` or `u_body`. So every juggling card was uploading a 24-vertex
		# polygon plus four more uniforms into a shader that reads none of them, every frame its rig
		# moved, which is every frame (the animation is on autoplay). That is five wasted
		# `set_shader_parameter` calls per juggling host per frame inside the function §0d.7 exists to
		# keep empty.
		if not fx.req.instances.is_empty(): continue
		_push_poly(fx.mat)
		_size_quad(fx)

## The silhouette a RADII quad's mask reads: the vertices, the wedge index and the live count, plus the
## tight body the fan and `body_near` are measured against. One function, because the four are ONE fact
## and a quad that got three of them would mask against a shape that does not exist.
func _push_poly(mat: ShaderMaterial) -> void:
	# PADDED to the uniform's own length, since a host may have fewer vertices than the shader holds
	# (a card's outline is exactly POLY, but `edge_subdivisions` can bake a shorter rig). `u_poly_count`
	# is what keeps the shader off the padding — no wedge is ever built from it.
	#
	# ⚠ PACKING TWO VERTICES PER `vec4` WAS TRIED AND IS SLOWER, which is worth recording because the
	# reasoning for it was sound: the array's SIZE is what costs (isolated on the owner's Intel UHD —
	# 16 vertices 5.459 ms on a burning screen, 24 as `vec2` 6.344, and only 0.2 of that gap was the
	# extra wedge candidates), so halving the slots looked free. Measured 6.808 instead: the shift, mask
	# and select per fetch cost more than the padding saved.
	var verts := _poly
	if verts.size() < POLY:
		# Into the persistent pad, in place — see `_poly_padded`. The tail past `_poly.size()` is never
		# read (`u_poly_count` keeps the shader off it), so stale values there cannot reach a fragment.
		_poly_padded.resize(POLY)
		for i : int in _poly.size(): _poly_padded[i] = _poly[i]
		verts = _poly_padded
	mat.set_shader_parameter(&"u_poly", verts)
	mat.set_shader_parameter(&"u_wedge", _wedge)
	mat.set_shader_parameter(&"u_poly_count", _poly.size())
	mat.set_shader_parameter(&"u_inner", _poly_inner)
	mat.set_shader_parameter(&"u_body", _poly_half * 2.0)

## Resolve `outline` into the mask's own vertices plus the wedge index that finds them. Returns whether
## anything actually moved — the early-out that keeps a still card free.
##
## ⚠ THE VERTICES ARE STORED, NOT SAMPLED, AND THAT IS THE WHOLE POINT (FX_HANDOFF §0c.1). This used to
## resample the outline into 32 rays of radial SCALE, and no interpolation between two rays can
## reproduce a VERTEX — so a corner the rig had pulled out was chamfered off the mask. Measured on a
## REAL `CardVisual` (`test_the_card_mask_is_the_card_the_player_sees`): at one point of the
## card's own autoplay animation the stretched corner stood **26.9 art units of a column outside its own
## mask**, carrying no flame at all, and the mask hung ~2 units past the art on the other side. The
## polygon is exact at rest AND deformed, and it costs the same `atan` the table cost.
##
## THE WEDGE INDEX, which is what keeps the shader O(1): for each of WEDGES angular slots, the vertex
## whose wedge (origin, V[i], V[i+1]) spans that slot's START. The shader tests that wedge and the next
## one, so the pair must cover the slot — true while no two vertices share a slot, which the FX
## ATTACHMENT suite asserts for the rig and for `star_outline` past the warp the rig can reach.
func _fill_poly_from_outline(outline: PackedVector2Array) -> bool:
	var n := outline.size()
	_angles_src.resize(n)
	# The walk has to START at the lowest angle, or the two sequences cannot advance together: an
	# outline ordered around the shape is monotonic in angle only up to ONE wrap, and this is where
	# that wrap is cut.
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
	# ⚠ THE RING IS NORMALIZED TO ONE WINDING, and that is not tidiness — the wedge index below and the
	# shader's `wedge_has` both read the walk as ANGLE-INCREASING, so an outline handed over the other
	# way round would index the wrong edge and mask as EMPTY everywhere: a card with no fire on it at
	# all, from a caller that did nothing wrong. Walking BACKWARD from the lowest angle turns a
	# decreasing sequence into an increasing one, which costs a sign and no allocation.
	#
	# ⚠ THE RE-WOUND ANGLES ARE PERMUTED, NOT RECOMPUTED. `_ring` is a reordering of `outline` and
	# nothing about it moves a point, so each vertex's angle is the one already measured above — a float
	# copy instead of a second `atan2` per vertex, which on a 24-point rig is 24 transcendentals saved
	# per host per frame on exactly the hosts whose rigs move every frame.
	var step := 1 if area >= 0.0 else -1
	_ring.resize(n)
	_angles.resize(n)
	for i : int in n:
		var src := posmod(start + i * step, n)
		_ring[i] = outline[src]
		_angles[i] = _angles_src[src]
	# ⚠ AN OUTLINE WITH MORE POINTS THAN THE SHADER HOLDS IS RESAMPLED, and that is the approximation
	# this function exists to avoid — it is here only so a host with a denser rig degrades instead of
	# breaking. The card's rig is 16 arms and fits exactly.
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
		# The index is built over whatever the shader will actually hold, so a resampled ring re-reads
		# its own angles rather than the outline's.
		_angles.resize(m)
		for i : int in m: _angles[i] = fposmod(atan2(_next[i].x, -_next[i].y), TAU)
	_wedge.resize(WEDGES)
	var j := 0
	for k : int in WEDGES:
		var a := float(k) * TAU / float(WEDGES)
		while j < m - 1 and _angles[j + 1] <= a: j += 1
		# Before the first vertex's angle is the CLOSING wedge, from the last point back to the first.
		_wedge[k] = float(m - 1) if a < _angles[0] else float(j)
	var moved := _poly.size() != m or not is_equal_approx(top, _poly_max) \
			or not half.is_equal_approx(_poly_half)
	if not moved:
		for k : int in m:
			# A twentieth of an art unit is well under one FX pixel, so anything below it cannot move
			# a rendered flame and is not worth an upload.
			if (_next[k] - _poly[k]).length() > 0.05:
				moved = true
				break
	if not moved: return false
	_poly = _next.duplicate()
	_poly_max = top
	_poly_half = half
	_poly_inner = _inner_box(_poly, half)
	return true

## The largest box of `half`'s own aspect that fits INSIDE the silhouette — the shader's early ACCEPT,
## and the reason an exact polygon mask is affordable at all (see `mask_level`'s RADII branch).
##
## Every edge of a star-shaped outline has the origin on its inside, so intersecting all of their
## half-planes gives a convex region inside the polygon — conservative where the shape is not convex,
## which is the safe direction: it can only send more points to the exact test. A box of half-extent
## `t * half` fits inside `n . p <= d` exactly when `t * (half.x |n.x| + half.y |n.y|) <= d`, so `t` is
## one min over the edges.
##
## ⚠ AT REST THIS EQUALS THE OUTER BOUND, which is the whole point: an undeformed card's rig IS the
## authored rectangle, so the two boxes coincide and no fragment on the board ever builds a wedge.
func _inner_box(poly: PackedVector2Array, half: Vector2) -> Vector2:
	var n := poly.size()
	if n < 3 or half == Vector2.ZERO: return Vector2.ZERO
	var t := 1.0
	for i : int in n:
		var a := poly[i]
		var e := poly[(i + 1) % n] - a
		# The inward normal of the edge, and how far the line sits from the origin along it.
		var nrm := Vector2(-e.y, e.x)
		var d := nrm.dot(a)
		if d < 0.0:
			nrm = -nrm
			d = -d
		var span := half.x * absf(nrm.x) + half.y * absf(nrm.y)
		if span > 1e-6: t = minf(t, d / span)
	return half * clampf(t, 0.0, 1.0)

## The index in `_ring` of the vertex whose segment spans angle `a` — the resample path's lookup, and
## the one place the closing segment (last point back to first) has to be named.
func _span_of(a: float, n: int) -> int:
	for j : int in n - 1:
		if _angles[j + 1] > a: return j
	return n - 1

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
## the frame put flames in empty space beside the drawing (owner report).
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
		Pacing.wait(0.5).timeout.connect(quad.queue_free)

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
			_make_quad(fx, req)
			_fx[req.id] = fx
			add_child(fx.quad)
		else:
			# A status that comes back mid-fade simply stops fading — no flash, no rebuild.
			fx.fade = -1.0
			fx.from = _eased(fx)
			fx.t = 0.0
			# The box has to cover the ease it is about to start (Effect.box_from).
			fx.box_from = fx.req.instance_half
		fx.req = req
		_size_quad(fx)
		_apply_static(fx, req)
		move_child(fx.quad, i)
	for id : StringName in _fx:
		# Reaching zero stacks FADES the effect out and only then releases its quad.
		if not seen.has(id) and _fx[id].fade < 0.0:
			_fx[id].from = _eased(_fx[id])
			_fx[id].fade = 0.0
	_resolve_phase_period()
	set_process(not _fx.is_empty())
	if not _fx.is_empty(): _push_live(0.0)

## The shared phase clock's period: the longest any live effect declares, INCLUDING one that is fading
## out — it is still drawn, so its balls must keep moving with the rest. Re-resolved whenever the quad
## set changes and never per frame (see `_push_live`).
func _resolve_phase_period() -> void:
	_phase_period = 0.0
	for id : StringName in _fx:
		_phase_period = maxf(_phase_period, _fx[id].req.phase_period)

## The drawn node for one effect. A QuadMesh either way, never a ColorRect: a Control dropped
## into the host's Node2D subtree joins the GUI input pass and eats the mouse events card
## grabbing needs. QuadMesh is Node2D-native, is centred on its origin, takes its size directly,
## and cannot swallow input.
##
## ⚠ AN INSTANCED REQUEST GETS A MultiMeshInstance2D, and the mesh then describes ONE SUBJECT rather
## than the whole effect — one ball, not the pattern (FxRequest.instances). The shader's `vertex()`
## places each instance; nothing here writes a transform, per frame or otherwise.
func _make_quad(fx: Effect, req: FxRequest) -> void:
	fx.mesh = QuadMesh.new()
	fx.mat = ShaderMaterial.new()
	# The SHARED Shader resource, never a duplicate: duplicating it recompiles the program for
	# every card. The per-node state is the ShaderMaterial's uniform set, not the Shader.
	fx.mat.shader = req.shader
	if req.instances.is_empty():
		var quad := MeshInstance2D.new()
		quad.mesh = fx.mesh
		fx.quad = quad
	else:
		fx.multi = MultiMesh.new()
		fx.multi.transform_format = MultiMesh.TRANSFORM_2D
		# The index and the level ride here. There is deliberately no per-instance TRANSFORM: writing
		# one per frame from GDScript for every ball on every host is the CPU cost this design exists
		# to avoid, and the shader can place a ball from its index far more cheaply.
		fx.multi.use_custom_data = true
		fx.multi.mesh = fx.mesh
		var multi := MultiMeshInstance2D.new()
		multi.multimesh = fx.multi
		# ⚠ NO ENGINE-SIDE PHYSICS INTERPOLATION. Godot warns *"MultiMesh interpolation is being triggered
		# from outside physics process"* the moment an instance transform is written from `sync`, and
		# interpolating these is meaningless anyway: every transform is IDENTITY for this effect's whole
		# life, because the SHADER places each instance from the clock.
		multi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		fx.quad = multi
	fx.quad.name = String(req.id)
	fx.quad.material = fx.mat
	# The HOST's seed and direction, not this quad's: two burning cards side by side must not flicker
	# in lockstep, and the two quads of ONE juggling host must agree exactly (a ball and its flame).
	fx.mat.set_shader_parameter(&"u_seed", _seed)
	fx.mat.set_shader_parameter(&"u_ball_dir", _ball_dir)

## Size the quad to bound the host AT EVERY ROTATION plus the effect's reach, or its edge clips.
## The quad stays world-aligned while the host turns INSIDE it, so a rotating host's bound is its
## CIRCUMSCRIBED extent — its diagonal — not its box: a 40x54 card is 67.2x67.2 at 45 degrees, and
## anim_spin_start turns it through every angle. Pinned hosts skip that ~1.6x fill cost.
##
## ⚠ It takes BOTH a turning host and an effect that turns with it (`FxRequest.rotates_with_host`).
## A juggling pattern does not turn with its card, so it keeps the box bound even on a card that
## spins through every angle — ~22 % of that quad's fill, for free (FX_HANDOFF §1b.3).
## ⚠ A DEFORMED host is bounded by its LIVE reach, not by its authored box. The star rig stretches a
## card's corners ~5 art units past the 40x54 it is authored as, and a quad built for the rest pose
## clips the flames standing on the part that moved.
## ⚠ AN INSTANCED EFFECT IS SIZED TO ONE SUBJECT AND NOT TO THE HOST AT ALL — no body, no rotation
## bound, no `FX_MARGIN`. The mesh is one ball's box, the shader places a copy of it at each ball, and
## the host's bound is irrelevant because no instance is anywhere near the quad edge that used to
## exist. That is the fill half of FX_HANDOFF §0d.6; `FxRequest.instance_half` is the contract.
func _size_quad(fx: Effect) -> void:
	var req := fx.req
	var half := Vector2(maxf(req.instance_half.x, fx.box_from.x),
			maxf(req.instance_half.y, fx.box_from.y))
	var extent := half * 2.0
	if req.instances.is_empty():
		var bound := _poly_half * 2.0 if not _poly.is_empty() else body
		# THE CIRCUMSCRIBED BOUND ONLY WHILE THE HOST IS ACTUALLY TURNED (FX_HANDOFF §10's lever B). A
		# card CAN spin, but `anim_spin` is rare and `u_shape_rot` is ~0 the rest of the time — and the
		# diagonal costs a card ~89.2² of quad against ~58x72 of real bound, i.e. nearly twice the
		# fill, on every burning card that is merely sitting there. Measured ceiling: 0.455 ms of the
		# worst window.
		#
		# ⚠ THE OBJECTION THIS USED TO CARRY IS VOID. §6a rejected it because "resizing a live quad moves
		# the FX pixel lattice" — true when the lattice was anchored on the quad's EDGE, and not true
		# since it was anchored on the host's ORIGIN (fx_common's pixel-grid note). Nothing about the
		# quad's size can move a cell now.
		# ⚠ AND IT FALLS BACK THE INSTANT THE HOST TURNS, which is what keeps it exact rather than
		# approximate: `_rot_tight` is re-evaluated whenever the pose changes, and a card mid-spin gets
		# the same diagonal it always had. The threshold is small enough that the residue a barely-turned
		# silhouette pokes past its own AABB (~0.4 art units at 1 degree) is inside `FX_MARGIN`.
		if rotates and req.rotates_with_host and not _rot_tight:
			bound = Vector2.ONE * maxf(body.length(), _poly_max * 2.0)
		extent = bound + Vector2.ONE * (req.reach + FX_MARGIN) * 2.0
		# ⚠ ROUNDED UP TO WHOLE ART UNITS, and only on THIS branch. `track_outline` calls this EVERY
		# FRAME for a card whose rig is moving, and lever B above made the extent depend on the live
		# silhouette — so without this, every deforming burning card rebuilt its QuadMesh and re-pushed
		# `u_extent` every frame, which is exactly the per-frame CPU §0d.7 went and removed. ⚠ It is
		# invisible in `fx_cost`, whose hosts call `measure_outline` once and never deform: the bench
		# cannot show this regression, only the game can. Whole units also mean a rig's sub-unit wobble
		# does not churn the mesh at all.
		#
		# ⚠ AN INSTANCED EXTENT IS NOT ROUNDED HERE, and rounding it would break the contract it already
		# satisfies: `FxJuggle._cell_box` sizes `instance_half` to a whole number of the style's `pixel`
		# CELLS, which is what puts the quad's edges on cell boundaries (FxRequest.instance_half).
		# Whole ART UNITS are a different lattice — they agree only when `2 * k * pixel` happens to be an
		# integer, which it is at today's `pixel = 1.0` and is not at, say, 0.3 — and the disagreement
		# slices the outer ring of every ball and plume into partial chunky pixels. There is no churn to
		# suppress on this branch either: an instance box changes only when the STACK count does.
	if not extent.is_equal_approx(fx.extent):
		fx.extent = extent
		fx.mesh.size = extent
		# UV maps across exactly the quad, so the shader needs the same number to recover art units.
		fx.mat.set_shader_parameter(&"u_extent", extent)
	# The off-screen margin, kept up to date HERE because this is the only place it can change.
	# ⚠ AN INSTANCED EFFECT'S MESH IS ONE SUBJECT, NOT ITS FOOTPRINT — its instances reach the whole
	# pattern — so its bound is the mesh plus the effect's reach. The margin only has to be generous.
	var span := extent.length() if req.instances.is_empty() \
			else extent.length() + req.reach * 2.0
	_cull_reach = maxf(_cull_reach, span)
	if fx.multi:
		# WHERE THE INSTANCES CAN GO, for CULLING only (FxRequest.instance_bound). Without it Godot
		# culls the whole item against a single mesh-sized box at the host's origin, because every
		# instance transform is identity — which silently deletes most of the balls.
		var bound := req.instance_bound + half
		fx.multi.custom_aabb = AABB(Vector3(-bound.x, -bound.y, -1.0),
				Vector3(bound.x * 2.0, bound.y * 2.0, 2.0))
	var mat := fx.mat
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
func _apply_static(fx: Effect, req: FxRequest) -> void:
	var mat := fx.mat
	# THE INSTANCE SET, written here and never per frame: it holds each subject's INDEX and level, not
	# its position, so it changes when the stack count does and not when the balls move.
	if fx.multi:
		fx.multi.instance_count = req.instances.size()
		for i : int in req.instances.size():
			# An identity transform on purpose — `vertex()` does the placing (see _make_quad).
			fx.multi.set_instance_transform_2d(i, Transform2D.IDENTITY)
			fx.multi.set_instance_custom_data(i, req.instances[i])
	if req.style: req.style.apply(mat)
	# A request may override the host's shape — that is how ball fire says "my mask is the balls, not
	# the card I am riding on" without the shader needing a mode (owner).
	mat.set_shader_parameter(&"u_shape", req.shape if req.shape >= 0 else int(shape))
	mat.set_shader_parameter(&"u_half", int(half))
	# ⚠ THE HOST'S POSE IS SEEDED HERE, because `_push_live` only sends it when it CHANGES and a
	# material born mid-life would otherwise never be told. A fresh quad starts at the shader's own
	# defaults (`u_shape_rot = 0`, `u_lag = vec2(0)`), so an effect added to a host that is already
	# turned — and not turning any further that frame — masked against an angle the host does not have.
	# `_sent_rot` is NAN until the first push, and the shader's defaults are already what that means.
	if not is_nan(_sent_rot):
		mat.set_shader_parameter(&"u_shape_rot", _sent_rot)
		mat.set_shader_parameter(&"u_lag", _sent_lag)
	# The DEFORMED width where the rig holds one: `u_body` is what the fan is measured across and what
	# `body_near` rejects against, so a restyle must not stamp the authored rectangle back over the
	# shape the card currently has. The silhouette goes with it, as one fact (see `_push_poly`), and
	# `_push_poly` writes `u_body` ITSELF from the polygon's own half-extent — so the authored
	# rectangle is only ever pushed when there is no silhouette to override it.
	if _poly.is_empty(): mat.set_shader_parameter(&"u_body", body)
	else: _push_poly(mat)
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
	# ⚠ THE EASED SET HAS TO BE RE-SENT AFTER THIS, and forgetting it would be a quiet bug rather than a
	# loud one. `style.apply()` above writes the style's BASE value for names the live set also owns
	# (`u_height` on a card's fire is both a style lever and a stack-scaled live value), so a restyle
	# stamps the base over the eased value — and _push_live only re-sends the eased set while it is
	# changing. Clearing this is what makes the next frame put the live values back.
	fx.pushed = false

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
## pour embers off the card while the flames are out on the balls (owner wanted embers on
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
	# ⚠ `u_height` IS EASED FOR A CARD'S FIRE AND STATIC FOR A PLUME, so the fallback is not defensive —
	# it is where a ball effect's height actually lives. FxJuggle keeps height out of the plume's `live`
	# so an easing value cannot disagree with the instance box built from it (FX_HANDOFF §0d.6), and
	# reading only `vals` here silently gave every ball ember a height of ZERO: they were born ON the
	# ball instead of scattered up its flame. Nothing catches that — embers are randomised, so
	# `09_embers` differs run to run by design.
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
		_apply_static(_fx[id], _fx[id].req)

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
## this direction costs a few uploads; being wrong in the other freezes an effect in view. ⚠ `_cull_reach`
## only ever GROWS for that reason — a host whose quads shrink keeps the older, larger margin, which is
## the harmless direction and saves recomputing it.
func _on_screen() -> bool:
	# ⚠ NEVER CULL IN THE EDITOR — it FROZE THE TUNING TOOL (owner report: *"card fire not
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
	# ⚠ **A NODE OUTSIDE THE TREE HAS NO VIEWPORT AND NO CANVAS, AND ASKING ANYWAY IS AN ERROR PER
	# CALL PER FRAME.** `PropVisual._ready()` builds its half attachments on the `_PropHalf` nodes
	# that `ensure_back()` / `ensure_front()` construct — and those are deliberately ORPHANS at that
	# moment, because `PropLayer` parents them to `CardLayer` rather than to the prop (see
	# `PropVisual`'s CardLayer parenting). So the first `sync()` reaches here with the attachment outside the tree
	# and `get_viewport_rect()` pushes `Condition "!is_inside_tree()" is true`, once per split-capable
	# prop per act — the flood the owner saw during submit.
	# "Not on screen" is the TRUE answer, not a workaround: nothing outside the tree is drawn. It is
	# also self-healing, which is the reason this belongs here rather than at the call site — the
	# skipped uploads resume on the frame the half is parented, exactly as they do for a host that
	# scrolls back into view, because `_push_live` records a pose as sent only once it really was.
	if not is_inside_tree(): return false
	var scaled := _cull_reach * maxf(global_scale.x, global_scale.y) * 0.5
	var at := get_global_transform_with_canvas().origin
	return get_viewport_rect().grow(scaled).has_point(at)

## Push the handful of genuinely per-frame uniforms, advance each effect's ease, and release any
## effect whose fade has finished.
##
## ⚠ "THE HANDFUL" USED TO BE ~15 UPLOADS PER QUAD PER FRAME, AND THAT WAS THE BOARD'S BIGGEST FX COST
## ONCE THE SHADERS STOPPED BEING THE BOTTLENECK. Measured on the owner's Intel UHD by `fx_cost`'s
## `_push_live, FULL SCREEN` row: **4.21 ms per frame for 78 hosts / 234 quads** — more than double the
## whole juggling layer's GPU time after FX_HANDOFF §0d.6. The GPU timer cannot see any of it.
##
## Only TWO of those uploads are genuinely per-frame — the clock and the phase. Everything else
## describes a host pose or an eased transition, and on a settled board neither changes at all, so both
## are sent on CHANGE instead: `_sent_rot` / `_sent_lag` for the pose, `Effect.pushed` for the eased set.
## ⚠ The values are still COMPUTED where the emitter needs them (`Effect.vals`); what stops is the
## upload, and `_apply_static` clears `pushed` because it can overwrite what the ease owns.
func _push_live(scaled_delta: float) -> void:
	var parent := get_parent() as Node2D
	if not parent: return
	var rot := parent.global_rotation
	rotation = -rot
	var secs := transition_secs()
	var step : float = 1.0 if secs <= 0.0 else scaled_delta / secs
	var lag_norm := _lag / maxf(body.x, 1.0)
	# HAS THE HOST'S POSE CHANGED AT ALL? `u_shape_rot` and `u_lag` are per-frame pushes that describe
	# the HOST, and a host that is not turning and not moving hands the shader the same two numbers
	# every frame for its whole life. Comparing them is two floats against ~4 uniform uploads per quad.
	# ⚠ A card is never PERFECTLY still — delta_floating_anim bobs it — but `_update_lag`'s deadzone
	# already snaps small velocities to zero, so `_lag` really does sit at exactly zero while it bobs.
	var moved := not is_equal_approx(rot, _sent_rot) or not lag_norm.is_equal_approx(_sent_lag)
	# ⚠ AN OFF-SCREEN HOST SKIPS ITS UPLOADS AND NOTHING ELSE — see the note before the loop below.
	# The pose is only RECORDED as sent once it actually has been, so a host that turned while off
	# screen re-sends `u_shape_rot` on the frame it comes back instead of coming back masked against
	# the angle it left at.
	var on_screen := _on_screen()
	if moved and on_screen:
		_sent_rot = rot
		_sent_lag = lag_norm
		# Crossing into or out of "upright" changes what bound the quads are entitled to (lever B in
		# _size_quad). Only the CROSSING re-sizes anything, so a spinning card pays two resizes for the
		# whole spin rather than one per frame.
		var tight := absf(rot) < TIGHT_ROT
		if tight != _rot_tight:
			_rot_tight = tight
			for id : StringName in _fx: _size_quad(_fx[id])
	# Advance the shared phase ONCE, from the longest period any effect declares — the balls quad
	# and the ball-fire quad declare the same one, and reading a single value is what guarantees
	# they agree on every frame rather than merely starting together. Resolved in `sync`, because a
	# `FxRequest.phase_period` can only change when the request SET does, and walking the dictionary
	# for it every frame put a per-effect `maxf` inside the board's single biggest FX cost.
	if _phase_period > 0.0: _phase = fmod(_phase + scaled_delta / _phase_period, 1.0)
	# ⚠ AN OFF-SCREEN HOST STILL PAYS FOR ITS UNIFORMS, and that is the one way an invisible card is
	# NOT free. Godot culls the QUADS — measured 2026-07-29, 312 hosts with 78 on screen cost the same
	# GPU time as the 78 alone — but nothing culls this function, and it is ~15 `set_shader_parameter`
	# calls per quad per frame. On that run the 234 invisible hosts added ~7 ms of pure CPU: more than
	# the whole visible board's GPU cost.
	#
	# The CLOCKS above are advanced first and unconditionally — they are a few floats, and freezing
	# them would teleport every ball the moment a scroll brought its card back into view. What is
	# skipped is only the UPLOAD, which nobody can see the result of.
	#
	# ⚠ AND THAT MEANS THE LOOP BELOW STILL RUNS. It used to be an early `return` here, which also
	# froze `Effect.t` and `Effect.fade` and never reached the release at the bottom — so a card that
	# lost its Burning while scrolled out of the play area kept its quad, kept `set_process` on, and
	# came back at FULL opacity to start fading only then.
	#
	# What still runs is the STATE: two float advances per effect and the release at the bottom. What
	# `on_screen` gates is every `set_shader_parameter`, the ember emitter, and the eased-value
	# evaluation those two feed on — so an invisible host is still within a few floats of free, which
	# is the claim `fx_cost`'s OFF-SCREEN control row exists to hold this code to.
	var done : Array[StringName] = []
	for id : StringName in _fx:
		var fx : Effect = _fx[id]
		fx.t = minf(fx.t + step, 1.0)
		# The ease has landed, so the box no longer has to span both of its ends. Done here rather than
		# left alone because holding the larger box would ratchet it up across repeated stack changes.
		if fx.t >= 1.0 and fx.box_from != Vector2.ZERO:
			fx.box_from = Vector2.ZERO
			_size_quad(fx)
		var mat := fx.mat
		# THE ONLY TRULY PER-FRAME UNIFORMS. Everything else below is pushed when it CHANGES, which on a
		# settled board is never — see the note above _push_live.
		if on_screen:
			mat.set_shader_parameter(&"u_time", _time)
			if fx.req.phase_period > 0.0: mat.set_shader_parameter(&"u_phase", _phase)
			if moved:
				mat.set_shader_parameter(&"u_shape_rot", rot)
				mat.set_shader_parameter(&"u_lag", lag_norm)
		# Eased FIRST, then emitted from: a ball ember has to be born on the ball this frame DRAWS,
		# and mid-transition the eased geometry is not the request's target geometry.
		#
		# ⚠ THE EASED SET IS COMPUTED AND PUSHED ONLY WHILE THE EASE IS RUNNING, and `fx.vals` is what
		# makes that safe: the emitter below needs this frame's geometry every frame, so the values are
		# CACHED rather than skipped. `fx.t` lands on exactly 1.0 on the frame the transition ends, and
		# `pushed` is what makes that final frame push before the pushing stops.
		# ⚠ THE EASED SET IS NOT EVALUATED OFF SCREEN EITHER, and that is not the same call as leaving the
		# EASE to run. `fx.t` above is two floats; `_eased` builds a Dictionary per effect per frame, and
		# `pushed` can only be set once the values have actually been uploaded — so gating the upload
		# alone would leave `pushed` false for ever on an invisible host and rebuild that Dictionary every
		# frame, which is the opposite of what this whole guard is for (`fx_cost`'s OFF-SCREEN control row
		# is what would report it). Nothing reads `fx.vals` while it is skipped: the emitter below is the
		# only consumer and it is gated on the same flag.
		if on_screen and (fx.t < 1.0 or not fx.pushed):
			fx.vals = _eased(fx)
			fx.pushed = fx.t >= 1.0
			for key : StringName in fx.vals:
				mat.set_shader_parameter(key, fx.vals[key])
		# Embers are pixels, not state, so an invisible host throws none — and the engine's global cap
		# is exactly what a board of off-screen hosts would otherwise spend on nothing.
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
