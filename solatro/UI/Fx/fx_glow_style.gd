@tool
class_name FxGlowStyle
extends FxStyle
#Every STATIC lever of the GLOW, read by `Shaders/glow.gdshader` and the light layer. Three `.tres`
#only: glow_card, glow_circle, glow_beam. ⚠ No prop style: a prop is lit only by a beam crossing it.

#A SUBCLASS, never knobs on the `FxStyle` base (its header says why a `kind` flag was rejected): fire
#has no use for `circle_radius`, and a glow has none for `aperture`.

#⚠ NOT A COPY OF FIRE'S KNOBS. Fire's cover asks "how far above the surface below me", paid in
#`cover_taps` downward taps; a glow asks "how far from the mask, any direction" - one distance for a
#silhouette, one subtraction for a disc - so the spotlight circle is the CHEAP client.

#⚠ No fade knob: the glow snaps on and off both ways, deleted so nobody tunes a fade back in. No
#breathe knobs: it is steady, since a board of pulsing halos is a photosensitivity risk and noise.

#⚠ THE RAMP IS A `Gradient`, NOT A `PaletteRamp` - the owner's call ("gradient shouldnt be forced to
#be on fixed palette"). The one thing in the game not palette-bound, scoped to light: do not
#generalise it, and do not "restore" a `PaletteRamp` here.

#The array size on both sides of the seam: `apply()` pads to exactly this, because an array uniform
#whose size disagrees with the shader's declaration is silently dropped whole.
## The most layers the shader's uniform arrays hold (the owner's maximum of four).
const MAX_LAYERS := 4

#Here only because the glow's effect class does not exist yet. ⚠ When it does, MOVE this, never
#copy: two preloads are two `Shader`s, and a style applied through the wrong one misses every uniform.
## The shader every glow style drives.
const GLOW_SHADER := preload("res://Shaders/glow.gdshader")

@export_group("Pixels")
#⚠ REPLACES THE INHERITED `pixel` (hidden below): same `u_pixel`, but reaching screen resolution,
#which `FxStyle.pixel` (0.25 minimum) cannot. The owner: "MAKE THE GRID A KNOB", tuned by eye.

#⚠ Not a performance lever: `fx_local()` quantizes a COORDINATE, so the invocation count is unchanged.
## Art units per FX pixel, from the art's own grid down to screen resolution.
@export_range(0.02, 8.0, 0.01) var grid : float = 0.5
#Indexed on the FX PIXEL GRID, never `FRAGCOORD`, as fire's is. Ships at full: at any `grid` coarser
#than screen resolution there are still bands, and this stops them reading as contour rings.
## Bayer dither on the ramp's band edges: breaks the step without softening it.
@export_range(0.0, 1.0, 0.01) var dither : float = 1.0

@export_group("Field")
#A HARD bound, so also how far the quad hangs off the host (`FxRequest.reach`). ⚠ Shipped at 4, a
#rim not a halo (owner: "let me tune myself, start with 4"): fire reaches 7, held to half a card
#separation so the card behind stays visible, and a halo starts below it.

## THE REACH: how far past the host's silhouette the halo extends, in art units.
@export var reach : float = 4.0
#Fire's `sink`, for the same reason: the light is at full strength by the time it crosses the
#host's edge, so there is no seam where glow meets art.
## How far INSIDE the silhouette the falloff starts, in art units.
@export_range(0.0, 16.0, 0.25) var sink : float = 4.0
#The multi-exposure simulation: backlit animation exposed one frame through several diffusions
#(owner: "2 to 4, let me choose"). ⚠ Each layer is a full falloff pass over the quad - the cost
#knob, trimmed only against a measured `fx_cost.tscn` number, never pre-emptively.

## How many falloff layers are summed.
@export_range(1, MAX_LAYERS, 1) var layers : int = 2
#Shipped `[0.35, 1.0]`: a tight bright core plus a wide soft halo, where almost all the effect is.
## Each layer's falloff radius as a FRACTION of `reach`; past `layers` ignored, missing = 1.0.
@export var layer_radius : PackedFloat32Array = PackedFloat32Array([0.35, 1.0])
#Shipped `[1.0, 0.4]`: the wide layer is quiet, or the halo swamps its core. A missing entry is 0.0,
#so an untuned layer contributes nothing rather than a full-strength surprise.
## Each layer's gain.
@export var layer_gain : PackedFloat32Array = PackedFloat32Array([1.0, 0.4])
#The knob that decides LAMP or SMUDGE: real light drops hard, so the middle reads hot, not foggy.
## 0 = a smooth even fade, 1 = pure inverse-square.
@export_range(0.0, 1.0, 0.01) var inverse_square : float = 0.6

@export_group("Over the art")
#⚠ CONTRAST, NOT BRIGHTNESS: a canvas quad can only add, mix, sub or mul, and adding to dark ink and
#light paper alike keeps absolute contrast but not relative - the rank glyph vanishes first. The
#halo outside may be as bright as it likes; this half is held down.

#⚠ 0.35 IS A STARTING POINT: tuned by eye on the circle at full over the busiest card face.
## Opacity where the glow covers the HOST'S OWN ART; `FxFireStyle` ships it transparent.
@export_range(0.0, 1.0, 0.01) var inner_alpha : float = 0.35

@export_group("Colour")
#Sampled on INTENSITY like fire's ramp: u = 0 is the halo's faint limit, 1 the hot centre, so it is
#authored EDGE FIRST. ⚠ OFF-PALETTE on purpose: it interpolates, and the shader samples it LINEAR -
#light is the owner's one exception to "blending palette entries can create bad looking colors".

#⚠ One HUE, light to dark, not three colours - circle, beam and glow are one lamp. The stops are a
#starting point for the owner's eye.
## THE CORE-MID-EDGE SHIFT: white-hot core, warm middle, cooler edge.
@export var glow_ramp : Gradient = null:
	set(value):
		if glow_ramp and glow_ramp.changed.is_connected(_drop_ramp_cache):
			glow_ramp.changed.disconnect(_drop_ramp_cache)
		glow_ramp = value
		if glow_ramp: glow_ramp.changed.connect(_drop_ramp_cache)
		_ramp_tex = null

@export_group("Circle")
#HALF THE ART SQUARE, so the disc covers the picture and nothing else. ⚠ 17, not 16: 32x32 of art
#plus the 1-unit rim each side is 34, and 16 clips the picture's outline into a rimless arc.
## The disc mask's radius in ART units (glow_circle.tres only); the owner wants it adjustable.
@export var circle_radius : float = 17.0
#Its own knob: a halo barely covers art, the circle covers the whole art square. Judged beside
#`inner_alpha`, expected to end lower than this default.
## The circle's OWN over-art alpha.
@export_range(0.0, 1.0, 0.01) var circle_inner_alpha : float = 0.5

#64 as `PaletteRamp.window_texture` uses; the shader's dither is scaled by it, and a dither that
#does not know the texture's resolution does nothing or smears whole bands.
## How wide the baked ramp texture is.
const RAMP_WIDTH := 64

#One texture per style for the run (styles are shared preloads). The setter and the gradient's
#`changed` both drop it, so an inspector edit rebuilds on the next `apply()`.
## Cached bake of `glow_ramp`.
var _ramp_tex : GradientTexture1D = null

func _drop_ramp_cache() -> void:
	_ramp_tex = null

#LINEAR, unlike every palette ramp (`filter_nearest` reads as pixel art): this is the off-palette
#exception; the chunkiness comes from `grid` quantizing the sample POSITION. A null ramp is a broken
#style, and the shader then draws nothing rather than white.
func ramp_texture() -> GradientTexture1D:
	if _ramp_tex: return _ramp_tex
	if not glow_ramp: return null
	_ramp_tex = GradientTexture1D.new()
	_ramp_tex.gradient = glow_ramp
	_ramp_tex.width = RAMP_WIDTH
	return _ramp_tex

#`grid` is this style's version of `pixel`; two rows quantizing one coordinate is the confusion the
#subclass split prevents. It is still saved, and `apply()` ignores it.
## Hide the inherited `pixel`.
func _validate_property(property : Dictionary) -> void:
	if property.name == &"pixel":
		property.usage = PROPERTY_USAGE_STORAGE

#⚠ `u_pixel` is written TWICE, by `super(mat)` then from `grid`, which wins: that is how `grid`
#replaces it. The arrays are padded to `MAX_LAYERS`: a size mismatch is rejected whole, leaving a
#black glow and no error.

## Write every glow lever onto a material. On creation and style swap, NEVER per frame.
func apply(mat: ShaderMaterial) -> void:
	super(mat)
	mat.set_shader_parameter(&"u_pixel", maxf(grid, 1e-3))
	mat.set_shader_parameter(&"u_dither", dither)
	mat.set_shader_parameter(&"u_reach", reach)
	mat.set_shader_parameter(&"u_sink", sink)
	mat.set_shader_parameter(&"u_layers", clampi(layers, 1, MAX_LAYERS))
	mat.set_shader_parameter(&"u_layer_radius", _padded(layer_radius, 1.0))
	mat.set_shader_parameter(&"u_layer_gain", _padded(layer_gain, 0.0))
	mat.set_shader_parameter(&"u_inverse_square", inverse_square)
	mat.set_shader_parameter(&"u_inner_alpha", inner_alpha)
	mat.set_shader_parameter(&"u_circle_radius", circle_radius)
	mat.set_shader_parameter(&"u_circle_inner_alpha", circle_inner_alpha)
	mat.set_shader_parameter(&"u_ramp", ramp_texture())
	mat.set_shader_parameter(&"u_ramp_width", float(RAMP_WIDTH))

#A radius falls back to 1.0 (covers the whole reach), a gain to 0.0 (contributes nothing), so an
#under-filled array is inert rather than wrong.
func _padded(src : PackedFloat32Array, fallback : float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(MAX_LAYERS)
	for i : int in range(MAX_LAYERS):
		out[i] = src[i] if i < src.size() else fallback
	return out
