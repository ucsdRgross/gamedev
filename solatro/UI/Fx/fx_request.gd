@tool
class_name FxRequest
extends RefCounted
## One visual effect a host is asked to render: which shader draws it, how far past the host's
## silhouette it reaches, and the live per-frame uniform values. Statuses build these in
## CardModifierStatus.fx_request(), mirroring the draw_icon idiom — so FxAttachment never learns
## which effects exist and adding a visual status is a new class, not an edit to the FX layer.

## Stable key for this effect on its host. FxAttachment keys its quads by it, so a request that
## keeps its id across a refresh RETUNES its quad instead of rebuilding it (and its material).
var id : StringName = &""

## The compiled shader that draws this effect, SHARED across every host. Never duplicated — a
## duplicated Shader recompiles per card; the per-node state is the ShaderMaterial, not the Shader.
var shader : Shader = null

## The static art levers, written to the material once on creation and on style swap.
var style : FxStyle = null

## Which SHAPE this effect's mask is, overriding the host's own: an FxAttachment.Shape value, or -1
## for "whatever the host is". Ball fire is the one user — its mask is the BALLS, not the card it
## rides on — which is what lets the fire shader have no emitter modes at all (owner 2026-07-30,
## *"no special ball case"*). Typed as int rather than as the enum so FxRequest and FxAttachment do
## not reference each other's class_names in a cycle.
var shape : int = -1

## How far the effect reaches BEYOND the host's silhouette, in art units. Sizes the quad together
## with the host's body, so a taller flame gets a taller quad instead of clipping at its edge.
var reach : float = 0.0

## ONE INSTANCE PER SUBJECT, or empty for a single quad over the whole effect. Each entry is that
## instance's INSTANCE_CUSTOM — for juggling, `r` is the ball index and `g` is its own fire level.
##
## ⚠ THIS IS WHAT MADE THE JUGGLING LAYER AFFORDABLE, AND IT IS A COST MODEL RATHER THAN A TIDINESS
## CHOICE (FX_HANDOFF §0d.6). A single quad has to cover everywhere its subject MIGHT be, so a
## juggling pattern got a quad ~33 x 64 art units across for ~28 art units of actual ball, and every
## one of those fragments ran a closed-form search of the arc ladder to find out which ball — if any —
## it belonged to. Fitting the published measurements put this layer's cost at *guard-box area x cost
## of one of those searches*, to within 4 % on both quads. One instance per ball shrinks the area to
## each ball's own box AND deletes the search, because the index simply arrives with the instance.
##
## ⚠ IT COSTS NOTHING PER FRAME, and that is the point of putting the index here rather than the
## POSITION. The motion is `u_phase` and the shader's vertex stage; this data changes only when the
## STACK COUNT or a ball's level does. Writing transforms per frame from GDScript — 78 hosts x 5 balls
## — would have handed back on the CPU what it saved on the GPU.
##
## ⚠ DRAW ORDER IS OVERLAP ORDER. Instances composite in the order they appear here, so a caller with
## overlapping subjects owns the tie-break: FxJuggle sorts by level so the highest-level ball draws
## last and wins (owner, 2026-07-29: *"if overlapping, ball with highest stacks win"*). This replaces
## the nearest-centre tie-break the search used to give for free.
var instances : PackedColorArray = PackedColorArray()

## Half-extent of ONE instance's quad, in art units — everything a single subject can draw, measured
## from the point `vertex()` places that instance at.
##
## ⚠ IT MUST BE A WHOLE NUMBER OF THE STYLE'S `pixel` CELLS, and that is not a rounding preference:
## the instance is placed on a cell BOUNDARY (fx_cell_round), so a whole-cell half-extent puts the
## quad's edges on boundaries too and every FX pixel it touches is covered in full. A fractional one
## cuts its edge cells and draws PARTIAL chunky pixels, which reads as a torn edge. `FxJuggle` rounds
## up and `test_fx_attachment` asserts it.
##
## ⚠ It must also cover the whole of the transition: `live` values are EASED, so a ball shrinking
## toward its target radius is briefly larger than the target, and the box is sized for the larger of
## the two ends (FxAttachment._size_quad).
var instance_half : Vector2 = Vector2.ZERO

## Half-extent of everywhere ALL the instances can go, in art units — the whole pattern, not one ball.
##
## ⚠ THIS IS A CULL BOUND AND NOT A FILL BOUND, AND FORGETTING IT DELETED MOST OF THE BALLS. Godot
## derives a MultiMeshInstance2D's cull rect from the instance TRANSFORMS, and an effect that places
## its instances in `vertex()` leaves every transform at identity — so the engine believes the whole
## effect is one mesh-sized box at the host's origin and culls every instance outside it. Measured the
## first time this ran: of 8 balls, the 2 passing near the card's centre rendered and 6 vanished; of
## 50, four. ⚠ **It also made the effect look 10x faster than it is**, which is the trap — the cost
## bench cannot tell "cheap" from "not drawn", and only the PIXELS suite's ball checks caught it.
##
## It costs no fill: it is written once into `MultiMesh.custom_aabb` and only decides whether the whole
## item is submitted. Being generous here is free; being tight is a missing ball.
var instance_bound : Vector2 = Vector2.ZERO

## Whether THIS effect's content turns when its host does — which is the only reason a quad ever pays
## the CIRCUMSCRIBED (diagonal) bound instead of the host's box (FxAttachment._size_quad). Fire needs
## it: its mask IS the host's art, so a card turned 45 degrees presents its diagonal and a box-bound
## quad would clip the flames off the corners.
##
## The JUGGLING quads provably do not: `juggle.gdshader` never reads `u_shape_rot`, the pattern is
## defined in the quad's own space, and the attachment counter-rotates the quad — so the balls hold
## still in world space at every host angle (owner 2026-07-30: *"juggle effect doesn't rotate with
## card"*). They were paying `body.length()` = 62.4 for a 38x50 card, ~22 % of their fill, for a bound
## that bought them nothing (FX_HANDOFF §1b.3).
##
## So this is a per-REQUEST property, not a per-host one: on ONE rotating card the fire quad needs the
## diagonal and the ball quads do not.
##
## ⚠ Both quads of a partner pair must agree on it, or their lattices differ and a plume anchors off
## its ball (see `partner_id`).
var rotates_with_host : bool = true

## Data-derived FLOAT uniforms (u_count, u_level, u_intensity, u_height, ...). These are EASED:
## when the data changes, the effect slides from its old values to the new ones over one
## transition, so a stack change never makes the visuals jump (owner ruling 16). Everything here
## must therefore be continuously meaningful — the stack count included, which is why the shader
## takes it as a float.
var live : Dictionary[StringName, float] = {}

## Seconds for one cycle of this effect's phase clock, or 0 for effects that have no phase. The
## ATTACHMENT owns the clock, not the request: a card's balls and the fire riding those balls must
## read the SAME phase, and two independently advanced phases would drift apart within seconds.
var phase_period : float = 0.0

## Data-derived uniforms that must be applied WHOLE (ints, textures, vectors) — anything a lerp
## would make meaningless. Written when the data changes and not eased.
var snap : Dictionary[StringName, Variant] = {}

## BALLS mode: which ball indices are actually alight. The shader learns the same fact from
## `instances` — one per lit ball, carrying its level — but EMBERS are particles spawned from GDScript
## into ParticleEngine's world space, so the emitter needs the indices in a form it can walk.
var lit : PackedInt32Array = PackedInt32Array()

## The PARTNER effect's pixel lattice, for an effect drawn ON another effect's output rather than on
## the host: the ball-fire plume anchors to a ball centre that the BALL quad snapped to ITS grid
## (fx_pixel_snap), and the two quads have different extents and different `pixel`, so their lattices
## differ. Without these the plume would sit up to half a pixel off its ball and jitter as the ball
## travelled — the drift class §4g exists to prevent. Empty id = no partner, the normal case.
##
## ⚠ The partner is named, not re-derived. This used to carry the partner's `reach` and rebuild its
## extent from the same formula — a second copy of a computation, which is the exact shape of every
## drift bug this layer has had. The attachment reads the partner quad's ACTUAL size instead, so the
## two cannot disagree however either one is sized. The partner must be declared FIRST in the request
## list (FxAttachment.sync builds them in order).
var partner_id : StringName = &""
var partner_pixel : float = 1.0

## Build a request inline. Keeps status fx_request() overrides to a single expression.
static func make(effect_id: StringName, effect_shader: Shader, effect_style: FxStyle,
		effect_reach: float) -> FxRequest:
	var req := FxRequest.new()
	req.id = effect_id
	req.shader = effect_shader
	req.style = effect_style
	req.reach = effect_reach
	return req
