class_name FxStyle
extends Resource
## Every STATIC lever of one visual effect, in one inspector-editable place (owner ruling 8:
## "a resource and shared location for all visual effect tuning"). A style is written to its
## ShaderMaterial ONCE — on creation and on style swap — never per frame; only the handful of
## live values in FxRequest.live are pushed each frame.
##
## Variants are .tres files, not code: fire_card / fire_prop / fire_ball / juggle_default today,
## frost or poison later with no new shader. Editing one retunes a running game.

@export_group("Pixels")
## Art units per FX pixel: the chunkiness knob. The grid is extent / pixel, so raising this
## coarsens the effect without touching its geometry. Density is an ART decision, so it lives
## here with the other levers rather than in player_settings.
@export_range(0.25, 8.0, 0.05) var pixel : float = 1.0
## Bayer dither strength on band edges — breaks the edge without softening it.
@export_range(0.0, 1.0, 0.01) var dither : float = 0.0

@export_group("Coverage")
## Slides the flame base from the host's TOP contour (0, fire sits on top) to its BOTTOM contour
## (1, the host is engulfed). Tips stay vertical at every value — this never tilts a flame.
@export_range(0.0, 1.0, 0.01) var wrap : float = 0.0
## Outward lean of the crown: tendrils fan away from centre in proportion to how far out they
## sit (owner ruling 1's "some angle skew as spread").
@export_range(0.0, 1.0, 0.01) var skew : float = 0.15
## Opacity where the effect overlays the host's body, so a burning card keeps its rank readable.
@export_range(0.0, 1.0, 0.01) var inner_alpha : float = 0.5

@export_group("Tendril shape")
## Flame length in art units, before the per-tendril variation.
@export var height : float = 14.0
## How ragged the crown is: 0 = every tendril the same length, 1 = wildly uneven.
@export_range(0.0, 1.0, 0.01) var height_var : float = 0.45
## Share of its comb cell each flame fills — gaps versus touching neighbours.
@export_range(0.1, 2.0, 0.01) var base_width : float = 1.0
## The flame's OGEE ARCH profile (owner 2026-07-27: pointed curved arches, never a dome).
## `point` sharpens the tip as it falls; `flare` pushes the shoulders further out before the
## outline inflects and turns in. Together they are the arch — see tendril() in fire.gdshader.
@export_range(0.2, 3.0, 0.01) var ogee_point : float = 1.0
@export_range(0.2, 3.0, 0.01) var ogee_flare : float = 0.35
## How far the flame base sinks INTO the body, which is what guarantees no seam at the contour.
@export var sink : float = 2.0
## 3-tap max so neighbouring tendrils fuse into a sheet instead of showing a V-notch between
## them. Off by default: it triples the tendril evaluations. Density turns it on automatically.
@export var merge : bool = false

@export_group("Motion")
## The tip drifts side to side.
@export var sway_amp : float = 0.35
@export var sway_speed : float = 4.0
## How fast tendril LENGTHS churn — distinct from sway, which moves them sideways.
@export var flicker_speed : float = 1.7
## The spine SNAKES: a travelling wave up the flame, again distinct from sway.
@export var wave_amp : float = 0.0
@export var wave_freq : float = 0.35
@export var wave_speed : float = 6.0
## 0 = every tendril moves in unison (one sheet), 1 = each on its own phase.
@export_range(0.0, 1.0, 0.01) var desync : float = 1.0
## Whole-effect breathing. Kept separate from flicker so photosensitivity can be reduced
## independently of overall brightness.
@export var pulse_amp : float = 0.0
@export var pulse_speed : float = 2.0
## How hard the flames trail the host's motion (the cape).
@export_range(0.0, 2.0, 0.01) var lag_amount : float = 1.0
## One vector biasing both lean and noise scroll.
@export var wind : Vector2 = Vector2.ZERO

@export_group("Texture")
## Turbulence strength, grain size, and how fast the grain scrolls up the flame.
@export_range(0.0, 1.0, 0.01) var noise_amp : float = 0.5
@export var noise_scale : float = 0.35
@export var noise_scroll : float = 18.0

@export_group("Colour")
## The whole palette: u = heat, v = stack level. Hard pixel columns are what read as pixel art,
## so it is sampled with filter_nearest; a cold ramp makes this same shader frost.
@export var ramp : Texture2D = null
## The stack count that reaches the TOP of the ramp. Normalization is logarithmic, so most of
## the ramp is spent on the first ~20 stacks — where the game actually lives — while still
## showing a difference all the way up (owner ruling 19: "a high number like 100+").
@export var level_ref : float = 120.0
## Pushes heat UP the ramp: more of the flame reaches the hotter bands. This is the lever
## surplus stacks feed, rather than sprouting more tendrils (owner ruling 4).
@export var intensity : float = 1.0
## Multiplies the ramp's RGB. Recolour versus relight, deliberately separate levers.
@export var brightness : float = 1.0
## Global fade. Used for spawn/despawn so the host's own modulate stays free.
@export_range(0.0, 1.0, 0.01) var opacity : float = 1.0

@export_group("Balls")
## Ball radius at ONE ball, in art units. Balls shrink by 1/sqrt(n) from here as the count grows.
@export var ball_radius : float = 3.0
## Floor of that shrink: past it balls read as a stream, which is the honest way to show 200.
@export var ball_radius_min : float = 1.0
## Width of the juggling loop, and the height of its tall throw arc at ONE ball. The arc grows
## with log(n) so more balls fit without bunching.
@export var ball_span : float = 30.0
@export var ball_arc_height : float = 37.5
## The shallow return arc — the "flat part", a small upward arc rather than a straight line.
@export var ball_return_height : float = 6.0
## Share of the cycle spent on the tall arc. > 0.5 means longer hang time, which is what real
## juggling looks like: the throw takes longer than the carry.
@export_range(0.2, 0.8, 0.01) var ball_top_fraction : float = 0.6
## Seconds for one full loop at ONE ball, as a fraction of the live get_delay(). The pattern
## quickens with the count on top of this (owner ruling 12).
@export var ball_period_fraction : float = 1.2
## Ball spin rate, and how much the count raises it (owner ruling 25).
@export var ball_spin : float = 2.0
@export var ball_spin_per_count : float = 0.35
## Flat ball colours: balls do NOT ride the stack ramp (owner ruling 20) — their count already
## reads through size and speed, so a third channel would be redundant.
@export var ball_lit : Color = Color(1.0, 0.82, 0.35)
@export var ball_shade : Color = Color(0.72, 0.45, 0.12)
@export var ball_gloss : Color = Color(1.0, 0.98, 0.85)

@export_group("Embers")
## Embers per second from a SINGLE host, however many stacks it carries — a per-source ceiling so
## one blazing card cannot consume the engine's global particle cap.
@export var ember_rate_max : float = 24.0
## The particle kind embers spawn. Null disables them, which is what viewer styles use.
@export var ember : ParticleSpec = null

## Write every static lever onto a material. Called on creation and on style swap, NEVER per
## frame — pushing ~35 uniforms every frame for every host is the cost this split exists to avoid.
func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"u_pixel", pixel)
	mat.set_shader_parameter(&"u_dither", dither)
	mat.set_shader_parameter(&"u_wrap", wrap)
	mat.set_shader_parameter(&"u_skew", skew)
	mat.set_shader_parameter(&"u_inner_alpha", inner_alpha)
	mat.set_shader_parameter(&"u_height", height)
	mat.set_shader_parameter(&"u_height_var", height_var)
	mat.set_shader_parameter(&"u_base_width", base_width)
	mat.set_shader_parameter(&"u_ogee_point", ogee_point)
	mat.set_shader_parameter(&"u_ogee_flare", ogee_flare)
	mat.set_shader_parameter(&"u_sink", sink)
	mat.set_shader_parameter(&"u_merge", 1 if merge else 0)
	mat.set_shader_parameter(&"u_sway_amp", sway_amp)
	mat.set_shader_parameter(&"u_sway_speed", sway_speed)
	mat.set_shader_parameter(&"u_flicker_speed", flicker_speed)
	mat.set_shader_parameter(&"u_wave_amp", wave_amp)
	mat.set_shader_parameter(&"u_wave_freq", wave_freq)
	mat.set_shader_parameter(&"u_wave_speed", wave_speed)
	mat.set_shader_parameter(&"u_desync", desync)
	mat.set_shader_parameter(&"u_pulse_amp", pulse_amp)
	mat.set_shader_parameter(&"u_pulse_speed", pulse_speed)
	mat.set_shader_parameter(&"u_lag_amount", lag_amount)
	mat.set_shader_parameter(&"u_wind", wind)
	mat.set_shader_parameter(&"u_noise_amp", noise_amp)
	mat.set_shader_parameter(&"u_noise_scale", noise_scale)
	mat.set_shader_parameter(&"u_noise_scroll", noise_scroll)
	mat.set_shader_parameter(&"u_ramp", ramp)
	mat.set_shader_parameter(&"u_brightness", brightness)
	mat.set_shader_parameter(&"u_opacity", opacity)
	# Ball geometry the juggle shader reads statically; the count-dependent halves of these
	# (radius, arc height, spin) are recomputed live and pushed with the rest of FxRequest.live.
	mat.set_shader_parameter(&"u_top_fraction", ball_top_fraction)
	mat.set_shader_parameter(&"u_lit", ball_lit)
	mat.set_shader_parameter(&"u_shade", ball_shade)
	mat.set_shader_parameter(&"u_gloss", ball_gloss)
