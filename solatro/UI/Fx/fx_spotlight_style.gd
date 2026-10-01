@tool
class_name FxSpotlightStyle
extends FxStyle
# THE LIGHT LAYER'S LOOK, AS A RESOURCE. ⚠ If a knob is not pushed by `apply()` or read by the
# director it does not exist: a uniform left at its shader default cannot be reached from GDScript.

# THE SPLIT WITH `PlayerSettings`: TIMING lives there (every duration is a fraction of
# `Game.get_delay()`, and the dim target is a player-facing accessibility knob); LOOK lives here,
# written to the material ONCE on creation and on style swap, never per frame.

# ⚠ NOT AN `FxAttachment` EFFECT: it configures ONE full-screen `ColorRect` and subclasses `FxStyle`
# only for the shared contract. The inherited `pixel` reaches `u_pixel`, which the light shader uses
# to quantize its own coordinates.

@export_group("Circle")
# HALF THE CARD ART'S WIDTH, so the pool sits inside the square card and touches all four edges
# (owner). Derived, so it follows the card; scaled by the lit card's drawn scale at the point of
# use and centred by `CardVisual.spotlight_center()`. Adjustable because the owner asked for a knob.

## The spotlight pool's radius, in ART units.
@export_range(4.0, 48.0, 0.5) var circle_radius : float = CardVisual.CARD_ART_SIZE.x / 2.0
# ⚠ 0.3, NOT 1.0: the pool mostly opens the dim, and a full pool of added light on top washed the
# rank glyph off the card.

## How much light the circle ADDS over its coverage.
@export_range(0.0, 2.0, 0.05) var circle_intensity : float = 0.3
# 0.4 by eye, between 0.25 (read as an arc) and 0.75 (too soft). ⚠ Blurring a boundary does not
# remove a discontinuity across it: the beam's coverage converging on the circle's removed the seam.

## The pool's penumbra.
@export_range(0.0, 1.0, 0.01) var circle_softness : float = 0.4

@export_group("Beam")
@export_range(0.0, 2.0, 0.05) var beam_intensity : float = 0.45
# ⚠ ITS WIDTH AT THE TARGET IS DELIBERATELY NOT HERE: the shader derives that from the circle's
# radius, so the mouth cannot disagree with the pool it opens onto. `flare` is what is left of it.

## The cone's half-width where it leaves the lamp, in ART units.
@export_range(0.0, 40.0, 0.5) var beam_width_at_origin : float = 9.0
## Extra half-width beyond the circle at the target. 0 means the cone lands exactly on the pool.
@export_range(0.0, 20.0, 0.5) var flare : float = 0.0
@export_range(0.0, 1.0, 0.01) var beam_softness : float = 0.35

@export_group("Volumetric noise")
# ⚠ THE SCALE SETS THE GRAIN'S SIZE: at a base cell of ~50 screen pixels the noise read as flat
# blocks the size of a card's art square. Isolated by rendering with `beam_noise` at 0.

## The beam's scrolling grain.
@export_range(0.0, 1.0, 0.01) var beam_noise : float = 0.25
@export var beam_noise_scale : float = 0.06
@export var beam_noise_scroll : float = 12.0

@export_group("Dim")
# ⚠ Inside the light layer's off-palette exception, which is scoped to light: not a `PaletteRamp`
# and not required to be on-palette.

## The colour the dim multiplies toward: a dark palette entry, NOT black.
@export var dim_color : Color = Color(0.05, 0.04, 0.09, 1.0)
## Subtle noise on the dim, rather than a flat field or a vignette.
@export_range(0.0, 0.25, 0.005) var dim_noise : float = 0.03

@export_group("Colour")
## The light's own colour. ⚠ Off-palette: light is the ONLY thing outside the palette contract.
@export var light_color : Color = Color(1.0, 0.85, 0.55, 1.0)

# WRITES EVERY LOOK UNIFORM `light.gdshader` DECLARES; `FX ATTACHMENT`'s uniform-seam test asserts
# every name written here is declared there.

# ⚠ DELIBERATELY DOES NOT CALL `super()`: `FxStyle.apply()` also writes `u_opacity`, which the light
# shader does not declare (its visibility is the dim and the show's ease), and Godot silently
# ignores an undeclared uniform. `u_pixel` is pushed here by name instead.
func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"u_pixel", pixel)
	mat.set_shader_parameter(&"u_circle_intensity", circle_intensity)
	mat.set_shader_parameter(&"u_circle_softness", circle_softness)
	mat.set_shader_parameter(&"u_beam_intensity", beam_intensity)
	mat.set_shader_parameter(&"u_beam_softness", beam_softness)
	mat.set_shader_parameter(&"u_beam_noise", beam_noise)
	mat.set_shader_parameter(&"u_beam_noise_scale", beam_noise_scale)
	mat.set_shader_parameter(&"u_beam_noise_scroll", beam_noise_scroll)
	mat.set_shader_parameter(&"u_dim_color", dim_color)
	mat.set_shader_parameter(&"u_dim_noise", dim_noise)
	mat.set_shader_parameter(&"u_light_color", light_color)
