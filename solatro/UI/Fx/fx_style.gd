@tool
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
## Opacity where the effect overlays the host's body. **Every shipped style sets this to 1.0**: fire
## BLOCKS what it covers (owner 2026-07-29 — seeing the card through the flame "looks very bad").
## Use `sink` to decide how much art the flames come down over; this stays only because a future
## effect (a ghost, a frost bloom) may genuinely want to be see-through.
@export_range(0.0, 1.0, 0.01) var inner_alpha : float = 1.0

@export_group("Tendril shape")
## Flame length in art units, before the per-tendril variation (which only ever SHORTENS a tendril,
## so this is a true ceiling). For a CARD-hosted effect the budget is half the default card
## separation — `CardVisual.CARD_SEPARATION * 0.5` = 7 — so the flames never reach the card behind
## and cover it (owner 2026-07-28). Prop-hosted styles are in PROP art units (screen pixels at the
## default card_scale, ~2.5x smaller), so their number is not the same number.
@export var height : float = 7.0
## How ragged the crown is: 0 = every tendril the same length, 1 = wildly uneven.
@export_range(0.0, 1.0, 0.01) var height_var : float = 0.45
## Share of its comb cell each flame fills — gaps versus touching neighbours.
@export_range(0.1, 2.0, 0.01) var base_width : float = 1.0
## The flame's OGEE ARCH profile (owner 2026-07-27: pointed curved arches, never a dome).
## `point` sharpens the tip as it falls; `flare` pushes the shoulders further out before the
## outline inflects and turns in. Together they are the arch — see tendril() in fire.gdshader.
@export_range(0.2, 3.0, 0.01) var ogee_point : float = 1.0
@export_range(0.2, 3.0, 0.01) var ogee_flare : float = 0.35
## The ONION SHELLS (owner 2026-07-27: "each layer wraps around the other, like actual candle
## lights"). Heat is distance ACROSS the flame relative to its own half-width at that height, so
## every colour band is a scaled copy of the outline. `power` shapes the shells — below 1 fattens
## the hot core, above 1 thins it to a filament — and `rise` is the WEAK height term that cools the
## tip. Height must stay the secondary term: leading with it is what stacked the colours in rows.
@export_range(0.25, 4.0, 0.01) var onion_power : float = 1.0
@export_range(0.0, 1.0, 0.01) var onion_rise : float = 0.35
## HOW FAR THE FIRE IS ALLOWED DOWN INTO THE HOST'S ART, in art units — the encroachment knob
## (owner 2026-07-29). Positive sinks the base below the contour, which is what guarantees no seam
## where flame meets host; 0 plants it exactly on the contour; NEGATIVE lifts it clear so the flames
## sit above the art and cover nothing at all.
##
## This is the lever for "the fire is hiding my card", NOT `inner_alpha`. Fire is opaque now — every
## shipped style sets `inner_alpha = 1.0`, because seeing the art through the flame reads badly — so
## the only thing that decides how much art a flame covers is how far down its base starts.
@export_range(-16.0, 16.0, 0.25) var sink : float = 2.0
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
## The effect's whole palette, as an ORDERED LIST OF PALETTE ENTRIES (T21). u = heat, v = stack
## level; hard pixel columns are what read as pixel art, so it is sampled with filter_nearest, and a
## cold ramp makes this same shader frost.
##
## The texture is BUILT from this ramp at load — it used to be a PNG baked by tools/make_fx_ramp.py
## from two band tables interpolated per row, which is why the shipped fire ramp had 64 colours and
## not one of them was in the palette. Retuning fire is now editing an Array[int] in the inspector.
@export var ramp_source : PaletteRamp = null:
	set(value):
		ramp_source = value
		_ramp_tex = null
## How many of the ramp's entries one flame shows at once. The window SLIDES toward the hot end as
## the stack level rises (owner 2026-07-28: *"ramp could have 10 colors, and fire ramp can focus on
## window of 3 and move through the ramp when intensity increases"*), so more stacks means hotter
## bands rather than the same bands brightened.
@export_range(1, 12, 1) var ramp_window : int = 4:
	set(value):
		ramp_window = value
		_ramp_tex = null
## Heat thresholds where the window's bands change, one per band. Empty spaces them evenly.
@export var ramp_edges : PackedFloat32Array = PackedFloat32Array():
	set(value):
		# Coerced: the editor wrote `ramp_edges = null` into fire_card.tres once, while this script
		# was still a PLACEHOLDER there (it was not @tool), and a null would then crash the ramp
		# build on load. Cheap insurance against a corrupt .tres reaching the shader.
		ramp_edges = value if value != null else PackedFloat32Array()
		_ramp_tex = null
## Below this heat the flame is TRANSPARENT — the cut that gives tendrils their ragged outline, so
## it belongs to the ramp rather than being a constant buried in the shader.
@export_range(0.0, 0.9, 0.01) var ramp_cut : float = 0.18:
	set(value):
		ramp_cut = value
		_ramp_tex = null

## Cached build of `ramp_source`. Styles are shared preloads, so this is one texture per style for
## the whole run; every setter above drops it so an inspector edit rebuilds on the next apply().
var _ramp_tex : ImageTexture = null
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
## which is what real
## juggling looks like: the throw takes longer than the carry.
@export_range(0.2, 0.8, 0.01) var ball_top_fraction : float = 0.6
## Seconds for one full loop at ONE ball. REAL seconds, not a fraction of get_delay(): juggling
## speed is an ART decision, and `base_delay` is a player speed knob that goes down to 0.1 — where
## the old fraction made a whole cycle 0.12 s and the balls were a blur (owner report 2026-07-28).
## Act compression still quickens the pattern, because the clock feeding it is already pacing-scaled
## (FxAttachment.pacing) — this is only what one loop costs at rest. The pattern also quickens with
## the count on top of this (owner ruling 12).
@export var ball_period_secs : float = 1.2
## Deceleration into the top of the throw and acceleration out of it: 1 = constant speed around the
## loop, higher makes the ball linger at the apex. The carry (the lowest arc) is never warped —
## nothing is falling there. See fx_arc_ease in fx_common.gdshaderinc.
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
var _tones_tex : ImageTexture = null
@export var ball_light : Vector2 = Vector2(-0.45, -0.6)
@export_range(0.05, 2.0, 0.01) var ball_light_z : float = 0.65
@export_range(0.5, 0.999, 0.001) var ball_spec : float = 0.965

@export_group("Embers")
## Embers per second from a SINGLE host, however many stacks it carries — a per-source ceiling so
## one blazing card cannot consume the engine's global particle cap.
@export var ember_rate_max : float = 24.0
## The particle kind embers spawn. Null disables them, which is what viewer styles use.
@export var ember : ParticleSpec = null

## The heat/level ramp texture, built from `ramp_source` on first use and cached. Null ramp means the
## effect has no colours at all, which is a broken style rather than a supported state.
func ramp_texture() -> ImageTexture:
	if _ramp_tex: return _ramp_tex
	if not ramp_source: return null
	_ramp_tex = ramp_source.window_texture(ramp_window, 16, ramp_edges, ramp_cut)
	return _ramp_tex

## The N x 1 strip of ball body tones, darkest first. Cached the same way.
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
	mat.set_shader_parameter(&"u_onion_power", onion_power)
	mat.set_shader_parameter(&"u_onion_rise", onion_rise)
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
	mat.set_shader_parameter(&"u_ramp", ramp_texture())
	mat.set_shader_parameter(&"u_brightness", brightness)
	mat.set_shader_parameter(&"u_opacity", opacity)
	# Ball geometry the juggle shader reads statically; the count-dependent halves of these
	# (radius, arc height, spin) are recomputed live and pushed with the rest of FxRequest.live.
	mat.set_shader_parameter(&"u_top_fraction", ball_top_fraction)
	# Pushed to the BALL and the BALL-FIRE materials alike (both shaders declare it): the plume's
	# timing has to match its ball's exactly, or the flame slides off.
	mat.set_shader_parameter(&"u_ball_gravity", ball_gravity)
	# u_ball_arcs is NOT here: it depends on the ball COUNT, so it rides in FxJuggle.geometry with the
	# other count-derived values, which is also what guarantees both quads are handed the same one.
	mat.set_shader_parameter(&"u_ball_tones", tones_texture())
	mat.set_shader_parameter(&"u_gloss", PaletteDB.color(ball_gloss_role))
	mat.set_shader_parameter(&"u_ball_bands", ball_bands())
	mat.set_shader_parameter(&"u_ball_light", ball_light)
	mat.set_shader_parameter(&"u_ball_light_z", ball_light_z)
	mat.set_shader_parameter(&"u_ball_spec", ball_spec)
