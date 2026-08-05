@tool
class_name FxSpotlightStyle
extends FxStyle
## **THE LIGHT LAYER'S LOOK, AS A RESOURCE** — `DESIGN.md` §16's *"Look"* group, which says outright:
## *"these belong on a `FxSpotlightStyle` resource beside the other FX styles, not in settings —
## §4g owner ruling 8: one shared location for all effect tuning"*.
##
## ⚠ **THIS SHOULD HAVE EXISTED SINCE S13 AND DID NOT, AND THAT IS WHY KNOBS DID NOTHING.** Audited
## 2026-08-04 after the owner asked *"why is tunables not its own resource"* and reported that
## changing the circle radius had no effect: `light.gdshader` declares **13 look uniforms** and
## `LightLayer` was pushing **six** (`u_time`, `u_dim`, `u_lights`, `u_beams`, `u_light_count`,
## `u_brightness`). Every other one sat at its SHADER DEFAULT, unreachable from GDScript —
## `u_circle_intensity`, `u_beam_intensity`, `u_beam_softness`, `u_circle_softness`, `u_light_color`,
## `u_dim_color`, `u_dim_noise`, `u_pixel` and the noise trio. `u_dim_scale` was declared and never
## pushed at all. Meanwhile `circle_radius` and `beam_width_at_origin` — both §16 knobs — had become
## `const`s in `SpotlightDirector`.
##
## ⚠ **THE SPLIT WITH `PlayerSettings` IS NOT ARBITRARY AND IS THE DESIGN'S OWN:**
##   * **TIMING lives in `PlayerSettings`** — every duration is a fraction of `Game.get_delay()`
##     (`Q167`=a) and `dim_target` is a player-facing accessibility knob (`Q168`=a, and `= 0` is the
##     dim's off switch). Those stay where they are.
##   * **LOOK lives HERE** — §16, ruling 8. A style is written to its `ShaderMaterial` ONCE on
##     creation and on style swap, never per frame.
##
## ⚠ **NOT AN `FxAttachment` EFFECT.** The other styles configure a quad hung off a host; this one
## configures ONE full-screen `ColorRect`. It subclasses `FxStyle` for the shared contract
## (`brightness`/`opacity`/`apply()`, and `fx_intensity` folding into `brightness`) because ruling 8
## wants one shared location for effect tuning — not because the light layer is an attachment.
## ⚠ `pixel` is INHERITED and reaches `u_pixel`, which the light shader uses to quantize its own
## coordinates. The same trap `FxGlowStyle` documents applies: the base range stops at 8.

@export_group("Circle")
## The spotlight pool's radius, in ART units — scaled by `card_scale` at the point of use.
## ⚠ **`Q85`: *"16, make it adjustable so I can test slightly different radius"*.** The answer asked
## for a knob in the same breath as the number, and it shipped as a `const`. It is a knob now.
## ⚠ **The circle is centred on the card's ART SQUARE, not its origin** — that is
## `CardVisual.spotlight_center()`, not this file, because the offset is authored in the card scene.
@export_range(4.0, 48.0, 0.5) var circle_radius : float = 16.0
## How much light the circle ADDS over its coverage. ⚠ Shipped at 0.3 rather than §16's 1.0 and the
## reason is load-bearing: `QR9`=(c) makes the GLOW draw the disc, so the layer contributing a full
## pool as well is a DOUBLE COUNT — it blew the card out, and `ASSUMPTIONS.md` records the fix.
## Expect this to fall FURTHER once the glow is routinely on the card, not rise.
@export_range(0.0, 2.0, 0.05) var circle_intensity : float = 0.3
## The pool's penumbra. ⚠ Settled at 0.4 by eye after 0.25 (read as an arc) and 0.75 (too soft).
## **The lesson outlived the number: blurring a boundary is not how you remove a discontinuity across
## it** — converging the beam's coverage on the circle's is what removed the seam, which is what let
## this edge go back to being crisp.
@export_range(0.0, 1.0, 0.01) var circle_softness : float = 0.4

@export_group("Beam")
@export_range(0.0, 2.0, 0.05) var beam_intensity : float = 0.45
## The cone's half-width where it leaves the lamp, in ART units.
## ⚠ **ITS WIDTH AT THE TARGET IS DELIBERATELY NOT HERE.** The shader derives that from the circle's
## radius, so the mouth cannot disagree with the pool it opens onto. §16's `beam_width_at_target` is
## retired as a free number for exactly that reason; what survived is `flare` below.
@export_range(0.0, 40.0, 0.5) var beam_width_at_origin : float = 9.0
## Extra half-width beyond the circle at the target. 0 means the cone lands exactly on the pool.
@export_range(0.0, 20.0, 0.5) var flare : float = 0.0
@export_range(0.0, 1.0, 0.01) var beam_softness : float = 0.35

@export_group("Volumetric noise")
## The beam's grain — `Q98`=(b) *"from the start"*, `Q99`=(a) scrolling.
## ⚠ **Retuned by eye once already**: the first defaults put the base cell at ~50 screen pixels, so
## the "volumetric noise" read as flat blocks the size of a card's art square. Isolated by rendering
## with this at 0, which ruled out the dim's own dither.
@export_range(0.0, 1.0, 0.01) var beam_noise : float = 0.25
@export var beam_noise_scale : float = 0.06
@export var beam_noise_scroll : float = 12.0

@export_group("Dim")
## ⚠ **`Q79`=(a): a dark palette entry, NOT black.** The dim is a flat multiply toward this colour.
## ⚠ **This is inside the light layer's off-palette exception** (`Q134`/`Q135`, granted once in v8 and
## scoped to light) — it is not a `PaletteRamp` and it is not required to be on-palette.
@export var dim_color : Color = Color(0.05, 0.04, 0.09, 1.0)
## `Q80`=(c): subtle noise rather than a flat field or a vignette.
@export_range(0.0, 0.25, 0.005) var dim_noise : float = 0.03

@export_group("Colour")
## The light's own colour. ⚠ **Off-palette, and light is the ONLY thing in this game outside the
## palette contract** (v8 / GAP-003 — granted once, scoped here, does not travel).
@export var light_color : Color = Color(1.0, 0.85, 0.55, 1.0)

## Write every uniform this shader declares. ⚠ **THE POINT OF THE CLASS: if a knob is not pushed
## here it does not exist**, which is precisely how thirteen of them came to sit at their shader
## defaults with no way to reach them. `FX ATTACHMENT`'s uniform-seam test asserts that every name
## written here is declared by `light.gdshader`.
## ⚠ **DELIBERATELY DOES NOT CALL `super()`, AND THIS IS NOT AN OVERSIGHT.** `FxStyle.apply()` writes
## `u_pixel` **and `u_opacity`**, and `light.gdshader` declares no `u_opacity` — it is one full-screen
## surface whose visibility is the DIM and the show's ease, not a quad that fades out. Writing a
## uniform the shader does not declare is silently ignored by Godot, which is exactly the class of
## drift this resource exists to end, so `u_pixel` is pushed here by name instead.
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
