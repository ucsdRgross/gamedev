@tool
class_name FxStyle
extends Resource
## What EVERY visual effect has, whatever it draws (owner ruling 8: "a resource and shared location
## for all visual effect tuning"). A style is written to its ShaderMaterial ONCE — on creation and on
## style swap — never per frame; only the handful of live values in FxRequest.live are pushed each
## frame.
##
## ⚠ THIS CLASS IS THE SHARED HALF ONLY. The knobs of an actual effect live in a SUBCLASS —
## `FxFireStyle` for the tendrils, `FxJuggleStyle` for the balls — and a `.tres` is one of those, never
## a bare `FxStyle`.
##
## WHY SUBCLASSES AND NOT ONE CLASS WITH A `kind` FLAG (owner 2026-07-31: *"both fire and ball effects
## existing in same location for editing is confusing. Why does fire effects allow tuning ball and
## ball effects allow tuning fire? it should be separate"*). A flag was tried for a day and does work
## at two kinds — `_validate_property` hid the half that did not apply — but it does not scale, and
## the reasons are worth writing down because the next effect is what triggers them:
##
##  * **The inspector filter needs a rule.** With two kinds the rule was the `ball_` prefix, which
##    maintains itself. With five it is a hand-written name table per kind, and that goes stale the
##    first time a knob is added — the exact failure this project keeps having.
##  * **`apply()` writes uniforms the shader does not have.** One shared `apply()` pushes every kind's
##    parameters at every material. Measured on a GTX 1070: a `ShaderMaterial` is 841 bytes bare and
##    an unused parameter costs ~140 bytes — per MATERIAL, which is per quad per host, so the waste is
##    `kinds x knobs x hosts`, not `kinds x knobs`. A virtual `apply()` writes only what its own shader
##    declares, by construction.
##  * **You cannot build the wrong thing.** "New Resource" asks for the class, so a fire style with
##    ball knobs is not expressible.
##
## Memory was never the argument: a style instance is ~5.6 KB and there are six in the game. The
## argument is that one class stops being honest about what it configures.
##
## ⚠ Composition (a style holding per-aspect sub-resources) is the NEXT step, not this one — take it
## when two different effects want to share an ASPECT (the whole Motion group, say), because Godot has
## no multiple inheritance. It costs an indirection at every read site, so it is not worth paying
## before there is sharing to justify it.

@export_group("Pixels")
## Art units per FX pixel: the chunkiness knob. The grid is extent / pixel, so raising this
## coarsens the effect without touching its geometry. Density is an ART decision, so it lives
## here with the other levers rather than in player_settings.
##
## ⚠ NOT a performance lever. `fx_local()` quantizes a COORDINATE inside the fragment shader; the
## quad's screen footprint is unchanged and the shader still runs once per screen pixel.
@export_range(0.25, 8.0, 0.05) var pixel : float = 1.0

@export_group("Colour")
## Multiplies the effect's RGB. Recolour versus relight, deliberately separate levers.
##
## `FxAttachment` re-pushes this with the player's `fx_intensity` folded in, which is what lets a
## "reduce effects" setting reach every effect without editing a single `.tres`.
@export var brightness : float = 1.0
## Global fade. Used for spawn/despawn so the host's own modulate stays free — `FxAttachment` drives
## it down over a release rather than dropping the quad, which is ruling 16.
@export_range(0.0, 1.0, 0.01) var opacity : float = 1.0

@export_group("Embers")
## Embers per second from a SINGLE host, however many stacks it carries — a per-source ceiling so
## one blazing card cannot consume the engine's global particle cap.
@export var ember_rate_max : float = 24.0
## The particle kind embers spawn. Null disables them, which is what viewer styles use — and what a
## juggling style uses, since it is the ball's FIRE that throws embers, not the ball.
##
## SPLIT PER HOST SCALE, exactly as the fire styles are: `ember.tres` is card-sized, `ember_prop.tres`
## is the same ember for props and for balls. ParticleEngine is a board-level node, so a spec's sizes
## and speeds are SCREEN units — but a prop draws at `card_scale / PropVisual.AUTHORED_CARD_SCALE`, so
## the card's ember is ~2.5x too big beside a knife. That is data, not a code path: there is no
## per-host scaling anywhere in the emitter.
@export var ember : ParticleSpec = null

## Write the shared levers onto a material. **Subclasses override this and call `super(mat)` first.**
## Called on creation and on style swap, NEVER per frame — pushing a style's ~35 uniforms every frame
## for every host is the cost the static/live split exists to avoid.
func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"u_pixel", pixel)
	mat.set_shader_parameter(&"u_brightness", brightness)
	mat.set_shader_parameter(&"u_opacity", opacity)
