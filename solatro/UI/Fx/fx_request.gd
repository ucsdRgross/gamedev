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

## ⚠ THE QUAD IS SIZED FROM `reach` ON EVERY SIDE, AND FOR THE JUGGLING PATTERN THAT IS FAR TOO BIG —
## a loop 33 art units wide and 32 tall gets a 112x125 quad, because `reach` is a decorator's rule
## that assumes the effect hugs the whole silhouette. Letting a request declare its own half-extent
## and shrinking the quad to it was TRIED and REVERTED on 2026-07-31: it is worth ~25 % of the
## juggling layer's GPU time, and it MOVED THE RENDERED BALLS on a rotated host — `05f_ball_rotation`
## went from sub-unit probe offsets at every angle to +6.1 art units at 90 degrees and +2.3 at 45,
## with the whole pattern displaced along +x, on a quad whose uniforms and transform were byte for
## byte the same at every angle. Shrinking only the X axis reproduced it; not shrinking reproduced
## nothing. No mechanism was found, so it did not ship (FX_HANDOFF §1b.3).
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

## BALLS mode: which ball indices are actually alight. The shader reads the same fact per fragment out
## of `u_ball_fire`, but a TEXTURE cannot be sampled from GDScript cheaply and embers are spawned from
## GDScript — so the indices ride along in the form the emitter needs, built where the texture is.
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
