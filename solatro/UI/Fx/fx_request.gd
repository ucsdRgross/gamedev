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
## (fx_pixel_snap), and the two quads have different reaches and different `pixel`, so their lattices
## differ. Without these the plume would sit up to half a pixel off its ball and jitter as the ball
## travelled — the drift class §4g exists to prevent. Negative reach = no partner, the normal case.
var partner_reach : float = -1.0
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
