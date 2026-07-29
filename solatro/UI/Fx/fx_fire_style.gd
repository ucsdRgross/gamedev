@tool
class_name FxFireStyle
extends FxStyle
## Every STATIC lever of the FIRE effect — the tendrils, the arch, the shells and the ramp they are
## coloured from. Read by `fire.gdshader` and by `FxFire`.
##
## Variants are .tres files, not code: `fire_card` / `fire_prop` / `fire_ball` today, frost or poison
## later with no new shader. Editing one retunes a running game.
##
## What is NOT here is the juggling pattern (`FxJuggleStyle`), and that separation is the point: a
## fire style has no use for `ball_radius`, and showing both halves made every resource read like the
## union of two unrelated things (owner 2026-07-31). See `FxStyle` for why this is a subclass rather
## than a flag.

@export_group("Pixels")
## Bayer dither strength on band edges — breaks the edge without softening it.
@export_range(0.0, 1.0, 0.01) var dither : float = 0.0

@export_group("Coverage")
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
##
## ⚠ A no-op on a BALL plume: a ball's arch is anchored to its ball, not to a cell of a comb, so it
## has no neighbouring cell to fuse with (fire.gdshader, FX_HANDOFF §2).
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
## The stack count that reaches the TOP of the ramp. Normalization is logarithmic, so most of
## the ramp is spent on the first ~20 stacks — where the game actually lives — while still
## showing a difference all the way up (owner ruling 19: "a high number like 100+").
@export var level_ref : float = 120.0
## Pushes heat UP the ramp: more of the flame reaches the hotter bands. This is the lever
## surplus stacks feed, rather than sprouting more tendrils (owner ruling 4).
@export var intensity : float = 1.0

## Cached build of `ramp_source`. Styles are shared preloads, so this is one texture per style for
## the whole run; every setter above drops it so an inspector edit rebuilds on the next apply().
var _ramp_tex : ImageTexture = null

## The heat/level ramp texture, built from `ramp_source` on first use and cached. Null ramp means the
## effect has no colours at all, which is a broken style rather than a supported state.
func ramp_texture() -> ImageTexture:
	if _ramp_tex: return _ramp_tex
	if not ramp_source: return null
	_ramp_tex = ramp_source.window_texture(ramp_window, 16, ramp_edges, ramp_cut)
	return _ramp_tex

## Write every fire lever onto a material, on top of the shared ones. Called on creation and on style
## swap, NEVER per frame.
func apply(mat: ShaderMaterial) -> void:
	super(mat)
	mat.set_shader_parameter(&"u_dither", dither)
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
