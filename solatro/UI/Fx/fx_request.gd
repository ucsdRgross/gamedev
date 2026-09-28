@tool
class_name FxRequest
extends RefCounted
#One visual effect a host is asked to render. Statuses build these in fx_request(), like the
#draw_icon idiom, so FxAttachment never learns which effects exist: a new visual status is a new
#class, not an edit to the FX layer.

#FxAttachment keys its quads by it, so a request that keeps its id across a refresh RETUNES its quad
#instead of rebuilding it and its material.
## Stable key for this effect on its host.
var id : StringName = &""

#Never duplicated: a duplicated Shader recompiles per card; the per-node state is the material.
## The compiled shader that draws this effect, SHARED across every host.
var shader : Shader = null

## The static art levers, written to the material once on creation and on style swap.
var style : FxStyle = null

#An int, not the enum, so FxRequest and FxAttachment do not reference each other's class_names.

#Ball fire is the one user - its mask is the BALLS, not the card they ride on - which is what lets
#the fire shader have no emitter modes (owner: *"no special ball case"*).
## This effect's mask shape (an FxAttachment.Shape), or -1 for the host's own.
var shape : int = -1

#Sizes the quad together with the host's body, so a taller flame gets a taller quad, not a clip.
## How far the effect reaches BEYOND the host's silhouette, in art units.
var reach : float = 0.0

#⚠ A COST MODEL, NOT TIDINESS. A single juggling quad was ~33 x 64 art units for ~28 of ball, every
#fragment searching the arc ladder for its ball; cost fit *guard-box area x one search* within 4 %.
#One instance per ball shrinks the area to each ball's box AND deletes the search.

#⚠ It costs nothing per frame: the motion is `u_phase` in the vertex stage, and this data changes
#only with the stack count or a ball's level. Per-frame transforms from GDScript (78 hosts x 5 balls)
#would hand back on the CPU what it saved on the GPU.

#⚠ DRAW ORDER IS OVERLAP ORDER: a caller with overlapping subjects owns the tie-break. FxJuggle
#sorts by level so the highest ball draws last (owner: *"if overlapping, ball with highest stacks win"*).
## One INSTANCE_CUSTOM per subject (juggling: r = ball index, g = its fire level), or empty for one quad.
var instances : PackedColorArray = PackedColorArray()

#⚠ A WHOLE NUMBER OF THE STYLE'S `pixel` CELLS: the instance sits on a cell boundary, so whole cells
#put the quad's edges on boundaries too; a fraction draws partial chunky pixels, a torn edge.
#`FxJuggle` rounds up and `test_fx_attachment` asserts it.

#⚠ It must cover the whole transition: `live` values are EASED, so a shrinking ball is briefly larger
#than its target, and the box takes the larger end (FxAttachment._size_quad).
## Half-extent of ONE instance's quad in art units, from the point `vertex()` places it at.
var instance_half : Vector2 = Vector2.ZERO

#⚠ A CULL BOUND, NOT A FILL BOUND. Godot culls a MultiMeshInstance2D by its instance TRANSFORMS, all
#identity here, so without it 6 of 8 balls vanished (46 of 50) - and the bench read 10x faster, since
#it cannot tell "cheap" from "not drawn".

#Written once to `MultiMesh.custom_aabb`, so being generous is free.
## Half-extent of everywhere ALL the instances can go, in art units.
var instance_bound : Vector2 = Vector2.ZERO

#The only reason a quad pays the CIRCUMSCRIBED bound (FxAttachment._size_quad). Fire's mask IS the
#host's art, so a card at 45 degrees shows its diagonal. Juggling does not: its quad counter-rotates
#(owner: *"juggle effect doesn't rotate with card"*), and the diagonal cost it ~22 % of its fill.

#Per REQUEST, not per host: on one rotating card the fire needs the diagonal, the balls do not.
#⚠ Both quads of a partner pair must agree on it, or their lattices differ (see `partner_id`).
## Whether THIS effect's content turns when its host does.
var rotates_with_host : bool = true

#EASED over one transition, so a stack change never makes the visuals jump (owner ruling). Each must
#be continuously meaningful - the stack count too, which is why the shader takes it as a float.
## Data-derived FLOAT uniforms (u_count, u_level, u_intensity, u_height, ...).
var live : Dictionary[StringName, float] = {}

#The ATTACHMENT owns the clock: a card's balls and the fire riding them must read the SAME phase,
#and two independently advanced phases drift apart within seconds.
## Seconds for one cycle of this effect's phase clock, or 0 for none.
var phase_period : float = 0.0

## Uniforms applied WHOLE (ints, textures, vectors) where a lerp means nothing; never eased.
var snap : Dictionary[StringName, Variant] = {}

#The shader learns the same from `instances`, but EMBERS are particles spawned from GDScript into
#ParticleEngine's world space, so the emitter needs indices it can walk.
## BALLS mode: which ball indices are alight.
var lit : PackedInt32Array = PackedInt32Array()

#The ball-fire plume anchors to a ball centre snapped to the BALL quad's grid, a different lattice;
#without this it sits up to half a pixel off and jitters as the ball travels. Empty id = no partner.

#⚠ NAMED, NOT RE-DERIVED: the attachment reads the partner quad's ACTUAL size, so the two cannot
#disagree. The partner must come FIRST in the request list (FxAttachment.sync builds in order).
## The PARTNER effect whose pixel lattice this one is drawn on.
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
