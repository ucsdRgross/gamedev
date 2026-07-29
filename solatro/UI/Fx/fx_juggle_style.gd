@tool
class_name FxJuggleStyle
extends FxStyle
## Every STATIC lever of the JUGGLED BALLS — the loop they travel, how they scale with the count, and
## how a ball is shaded. Read by `juggle.gdshader` and by `FxJuggle`.
##
## What is NOT here is fire (`FxFireStyle`), and that separation is the point: a juggling style has no
## use for `aperture` (owner 2026-07-31). See `FxStyle` for why this is a subclass rather than a flag.
##
## ⚠ THE BALL PATH LIVES HERE AND ONLY HERE. A lit ball's PLUME is drawn by the fire shader from a
## `FxFireStyle`, and that style deliberately has no path knobs: `FxJuggle.geometry()` hands the same
## span, arc heights, hang-time bias, gravity and arc count to BOTH quads. When the plume read its own
## copy off the fire style, two resources were obliged to agree about one path with nothing checking
## that they did — and `05d_ball_gravity` was quietly drawing plumes at a different gravity from their
## balls.

@export_group("Balls")
## Ball radius at ONE ball, in art units. Balls shrink by 1/sqrt(n) from here as the count grows.
@export var ball_radius : float = 3.0
## Floor of that shrink: past it balls read as a stream, which is the honest way to show 200.
@export var ball_radius_min : float = 1.0
## Width of the juggling loop, and the height of its tall throw arc at ONE ball. The arc grows
## with log(n) so more balls fit without bunching.
@export var ball_span : float = 30.0
@export var ball_arc_height : float = 32.0
## CEILING on the TOPMOST BALL, measured from the host's centre — the ball's radius comes out of it,
## so this is where the drawn pixels stop, not where a centre does. On a card the budget is half a
## card plus half the default separation — `(50 + 14) * 0.5` = 32: the pattern still peaks above the
## card's top edge (ruling 13) but never far enough to cover the card behind (owner 2026-07-28).
## Growth with the count runs into this; the balls' 1/sqrt(n) shrink is what makes room past it.
## Bounds the BALLS only — a lit ball's plume is deliberately outside the budget (owner 2026-07-28).
@export var ball_arc_max : float = 32.0
## The shallow return arc — the "flat part", a small upward arc rather than a straight line.
@export var ball_return_height : float = 6.0
## The throw's HANG-TIME BIAS. Each arc's share of the cycle is proportional to sqrt of its own
## height — the flight time one gravity gives it — and this scales the throw's share about that
## physical baseline: 0.5 is purely physical, above it the throw lingers longer than physics alone,
## which is what real juggling looks like: the throw takes longer than the carry.
@export_range(0.2, 0.8, 0.01) var ball_top_fraction : float = 0.6
## Seconds for one full loop at ONE ball. REAL seconds, not a fraction of get_delay(): juggling
## speed is an ART decision, and `base_delay` is a player speed knob that goes down to 0.1 — where
## the old fraction made a whole cycle 0.12 s and the balls were a blur (owner report 2026-07-28).
## Act compression still quickens the pattern, because the clock feeding it is already pacing-scaled
## (FxAttachment.pacing) — this is only what one loop costs at rest. The pattern also quickens with
## the count on top of this (owner ruling 12).
@export var ball_period_secs : float = 1.2
## Deceleration into the top of the throw and acceleration out of it: 1 = constant speed around the
## loop, higher makes the ball linger at the apex. See fx_arc_ease in fx_common.gdshaderinc.
@export_range(1.0, 3.0, 0.05) var ball_gravity : float = 1.6
## The loop is a LADDER of arcs, not one throw and one carry: as the ball count rises, lanes appear
## between the top and bottom arcs at evenly spaced heights and the balls travel those too (owner
## 2026-07-28). `per_count` is how fast lanes are added (a lane per `log(n) * this`), `max` is the
## ceiling — which is also the shader's cost ceiling, since the nearest-ball lookup does a fixed
## amount of work PER ARC. Both are always rounded to an EVEN arc count, or the loop would not close
## in x. 2 = the original two-arc pattern.
@export_range(0.0, 4.0, 0.05) var ball_arcs_per_count : float = 1.2
@export_range(2, 8, 2) var ball_arcs_max : int = 8
## Ball spin rate, and how much the count raises it (owner ruling 25).
@export var ball_spin : float = 2.0
@export var ball_spin_per_count : float = 0.35

@export_group("Ball shading")
## Flat ball colours: balls do NOT ride the stack ramp (owner ruling 20) — their count already
## reads through size and speed, so a third channel would be redundant.
##
## The body tones are an ordered ramp, darkest first, and the sphere's bands SAMPLE it — one band per
## entry, every one an exact palette entry. Adding a tone is adding an index to the ramp; `ball_bands`
## follows its length, so the two cannot disagree.
@export var ball_tones : PaletteRamp = null:
	set(value):
		ball_tones = value
		_tones_tex = null
## The specular dot, as a palette role index (PaletteDB.ROLES.ball_gloss by default).
@export_range(0, 255, 1) var ball_gloss_role : int = 31
## SPHERE shading (owner 2026-07-27: "balls need to be spherical"). `light` is the direction the
## light comes from in ART space (-y is UP, as everywhere else in 2-D) and `light_z` how head-on it
## is; `spec` is the highlight threshold — higher is a tighter dot. The spin rotates this whole
## frame, so the bands and the highlight sweep round the ball as it rolls.
@export var ball_light : Vector2 = Vector2(-0.45, -0.6)
@export_range(0.05, 2.0, 0.01) var ball_light_z : float = 0.65
@export_range(0.5, 0.999, 0.001) var ball_spec : float = 0.965

var _tones_tex : ImageTexture = null

## The N x 1 strip of ball body tones, darkest first. Cached like the fire ramp.
func tones_texture() -> ImageTexture:
	if _tones_tex: return _tones_tex
	if not ball_tones: return null
	_tones_tex = ball_tones.tones_texture()
	return _tones_tex

## How many hard tones the sphere's curvature is quantized into — the LENGTH of `ball_tones`, so a
## band can never point past the tones that exist. 3 when no ramp is set (the shader's own floor).
func ball_bands() -> int:
	if not ball_tones: return 3
	return maxi(ball_tones.size(), 2)

## Write every ball lever onto a material, on top of the shared ones.
##
## ⚠ The PATH is not here — not `u_top_fraction`, not `u_ball_gravity`, not `u_ball_arcs`. All three
## ride in `FxJuggle.geometry()`, which is what guarantees the balls quad and the plume quad are
## handed the same numbers.
func apply(mat: ShaderMaterial) -> void:
	super(mat)
	mat.set_shader_parameter(&"u_ball_tones", tones_texture())
	mat.set_shader_parameter(&"u_gloss", PaletteDB.color(ball_gloss_role))
	mat.set_shader_parameter(&"u_ball_bands", ball_bands())
	mat.set_shader_parameter(&"u_ball_light", ball_light)
	mat.set_shader_parameter(&"u_ball_light_z", ball_light_z)
	mat.set_shader_parameter(&"u_ball_spec", ball_spec)
