@tool
class_name FxGlowStyle
extends FxStyle
## Every STATIC lever of the GLOW — the multi-layer falloff field, how far it reaches past its host,
## how far inside the host it starts, and how much of it is allowed over the host's own art. Read by
## `Shaders/glow.gdshader` (S12) and by the light layer (S13).
##
## THREE `.tres`, and no more (`Q221`, `Q257`): `Shaders/Styles/glow_card.tres`,
## `glow_circle.tres`, `glow_beam.tres`. ⚠ **There is no prop style** — props do not glow at all;
## a prop is lit only incidentally, by a beam crossing it (`Q219` as narrowed by `Q221`).
##
## A SUBCLASS, never knobs on the `FxStyle` base (2026-07-31 ruling — see that file's header for
## why a `kind` flag was tried and rejected). A fire style has no use for `circle_radius`, and a
## glow has none for `aperture`.
##
## ⚠ **IT IS NOT A SECOND COPY OF THE FIRE SHADER'S KNOBS**, and the difference is in the question
## each field asks. Fire's cover field asks *"how far above the nearest surface below me am I"* —
## directional, and paid for with `cover_taps` downward taps. A glow asks *"how far from the mask am
## I, in any direction"*, which for a silhouette is one distance and for a disc is one subtraction
## (design §14b.1, O5/O6). That is why the spotlight circle is the CHEAP client of this style, not
## the expensive one.
##
## ⚠ **NO `glow_fade_fraction`** (`Q264`=a): the glow snaps on and snaps off, in both directions.
## The knob is DELETED rather than shipped at zero, so nobody tunes a fade back in by accident.
## ⚠ **NO `breathe_amp` / `breathe_speed`** (`Q126`=a, steady): §16's table listed them as *"if the
## glow animates at all"*, and the answer was that it does not. A board of pulsing halos is both a
## photosensitivity risk and visual noise.
##
## ⚠ **THE COLOUR RAMP IS A `Gradient`, NOT A `PaletteRamp` — GAP-003, ANSWERED 2026-08-04.** Chart
## O11 and §16 typed it as a `PaletteRamp` on the argument that *"the palette contract forbids
## lerping colours"*; `Q134`=(b), `Q135`=(b) and `Q214`'s note (*"gradient shouldnt be forced to be
## on fixed palette"*) are three separate answers overturning exactly that argument for light. The
## owner chose the off-palette ramp. **This is the one thing in the game that is not palette-bound**,
## and that is deliberate, granted once, and scoped to light — do not generalise it, and do not
## "restore" a `PaletteRamp` here.

## The most layers the shader's uniform arrays hold. Four is `Q207`'s stated maximum, so it is the
## array size on both sides of the seam — `apply()` pads to exactly this, because a Godot array
## uniform whose size disagrees with the shader's declaration is silently dropped whole.
const MAX_LAYERS := 4

## The shader every glow style drives. It lives here rather than on an effect class because the
## effect class does not exist yet — `FxFire` owns `FIRE_SHADER` and the glow's equivalent arrives
## with the light layer (S13). ⚠ When it does, MOVE this rather than copying it: two preloads of one
## shader is two `Shader` resources, and a style applied through the wrong one silently misses every
## uniform the other declares.
const GLOW_SHADER := preload("res://Shaders/glow.gdshader")

@export_group("Pixels")
## ⚠ **THIS REPLACES THE INHERITED `pixel`, WHICH IS HIDDEN IN THE INSPECTOR BELOW.** Same meaning —
## art units per FX pixel, written to the same `u_pixel` uniform — but a range that reaches all the
## way down to screen resolution, which `FxStyle.pixel` (0.25 minimum) cannot express.
##
## `Q213`=(d) is exactly that demand: *"MAKE THE GRID A KNOB — one tunable running from the art's own
## grid all the way down to screen resolution, shipped at something finer than the art so the
## gradient is smooth, and tuned by eye."* A glow is almost entirely gradient, so the chunky grid the
## rest of the FX layer draws on is the one place this effect is allowed to differ — and the owner
## picks where on that range it sits.
##
## ⚠ NOT a performance lever, for the same reason `FxStyle.pixel` is not: `fx_local()` quantizes a
## COORDINATE inside the fragment shader, so the quad's footprint and the shader's invocation count
## are unchanged at every setting. Only the look changes.
@export_range(0.02, 8.0, 0.01) var grid : float = 0.5
## Bayer dither strength on the ramp's band edges — breaks the step without softening it
## (`Q214`=a, the same pattern `fire.gdshader` uses, indexed on the FX PIXEL GRID and never on
## `FRAGCOORD`). Ships at full: at any `grid` coarser than screen resolution there are still bands,
## and this is what stops them reading as contour rings around every lit card.
@export_range(0.0, 1.0, 0.01) var dither : float = 1.0

@export_group("Field")
## THE REACH: how far past the host's silhouette the halo extends, in art units. It is a HARD bound
## — the falloff is evaluated over exactly this and no further — so it is also exactly how far the
## quad has to hang off the host, and it is what `FxRequest.reach` is set from.
##
## ⚠ **SHIPPED AT 4, WHICH IS `Q210`'S "TIGHTER, A RIM RATHER THAN A HALO"** — owner: *"let me tune
## myself, start with 4"*. For scale: a card is 40x54 art units and the fire on it reaches 7, held to
## half a card separation so the card behind stays visible. A halo is the effect most likely to break
## that budget, so it starts below fire rather than beside it, and the owner raises it by eye.
@export var reach : float = 4.0
## How far INSIDE the silhouette the falloff starts, in art units — the same erosion `fire.gdshader`
## calls `sink`, and `Q209`=(a) asks for it for the same reason: the light is already at full
## strength by the time it crosses the host's edge, so there is no seam where glow meets art.
@export_range(0.0, 16.0, 0.25) var sink : float = 4.0
## How many falloff layers are summed — the multi-exposure simulation. Real backlit animation got its
## glow by exposing one frame several times through different diffusions; this is that, and `Q207` is
## the owner's *"2 to 4, let me choose"*.
##
## ⚠ **EACH LAYER IS A FULL PASS OF THE FALLOFF OVER THE QUAD**, and this is the cost knob. `Q220`=(c)
## accepted whatever it costs for now and `Q254`=(a)/`Q255`=(d) say the cut is chosen once there is a
## measured number — so gate G2.3 reports `fx_cost.tscn` before and after, and nothing is trimmed
## pre-emptively.
@export_range(1, MAX_LAYERS, 1) var layers : int = 2
## Each layer's falloff radius, as a FRACTION of `reach`. Shipped `[0.35, 1.0]`: a tight bright core
## plus a wide soft halo, which `Q207`=(b)'s own wording says is where almost all of the effect is.
## Entries past `layers` are ignored; missing entries fall back to 1.0.
@export var layer_radius : PackedFloat32Array = PackedFloat32Array([0.35, 1.0])
## Each layer's gain. Shipped `[1.0, 0.4]` — the wide layer is the quiet one, or the halo swamps the
## core it exists to surround. Entries past `layers` are ignored; missing entries fall back to 0.0,
## so a layer nobody tuned contributes nothing rather than a full-strength surprise.
@export var layer_gain : PackedFloat32Array = PackedFloat32Array([1.0, 0.4])
## 0 = a smooth even fade, 1 = pure inverse-square. `Q208`=(a) made it a knob rather than baking one
## shape, and it is the single knob that decides whether the glow reads as A LAMP or as A SMUDGE:
## real light drops hard, which is what makes the middle read hot instead of foggy.
@export_range(0.0, 1.0, 0.01) var inverse_square : float = 0.6

@export_group("Over the art")
## Opacity where the glow covers the HOST'S OWN ART — ask 2's knob, and the one this whole effect
## exists to use. `FxFireStyle` ships this at the transparent end so flame never covers art; the glow
## is the effect written for the middle of the range.
##
## ⚠ **THE CONSTRAINT IS CONTRAST, NOT BRIGHTNESS** (design §14b.3). A canvas quad cannot brighten
## what is under it — with no screen read there is only add, mix, sub and mul — and adding the same
## value to the card's dark ink and to its light paper moves BOTH toward the light colour. Absolute
## contrast survives; relative contrast does not, and perception is relative. The first thing to
## disappear under a bright glow is the rank glyph, because it is the smallest dark feature on the
## card. The halo outside the silhouette may be as bright as it likes; this is the half that has to
## be held down.
##
## ⚠ **0.35 IS A STARTING POINT, NOT A DECISION.** `Q216`=(d): start low and tune it by eye against
## scenario S15 — the circle at full intensity over the busiest card face the game can build — before
## shipping. Gate **G2.2** is exactly that judgement and it cannot be made from a description.
@export_range(0.0, 1.0, 0.01) var inner_alpha : float = 0.35

@export_group("Colour")
## THE CORE→MID→EDGE SHIFT (`Q211`=a): white-hot at the core, warm in the middle, cooler at the
## edge. Sampled on INTENSITY, exactly where fire samples its own ramp — u = 0 is the faint outer
## limit of the halo and u = 1 is the hot centre, so the gradient is authored **edge first**.
##
## ⚠ **OFF-PALETTE, AND THAT IS THE POINT (GAP-003, `Q134`=b, `Q135`=b, `Q214`).** Every other
## gradient in this project is a `PaletteRamp` — an `Array[int]` of palette indices that never
## interpolates — because blending palette entries *"can create unpredictable and bad looking
## colors"*. Light is the exception the owner granted, and a `Gradient` is what expresses it: it
## interpolates, it is not bound to the palette image, and the shader samples it with a LINEAR
## filter rather than `filter_nearest`.
##
## ⚠ `Q212`=(a) still applies: the three stops are a ramp OF ONE HUE, light to dark, not three
## different colours — circle, beam and glow are one lamp (`Q136`=a). The shipped stops are a
## STARTING POINT for the owner's eye, like `inner_alpha` and `reach`, not a decision.
@export var glow_ramp : Gradient = null:
	set(value):
		if glow_ramp and glow_ramp.changed.is_connected(_drop_ramp_cache):
			glow_ramp.changed.disconnect(_drop_ramp_cache)
		glow_ramp = value
		if glow_ramp: glow_ramp.changed.connect(_drop_ramp_cache)
		_ramp_tex = null

@export_group("Circle")
## The disc mask's radius, in ART units — used only by `glow_circle.tres`, where the mask kind is the
## disc rather than the host's silhouette. It is HALF THE ART SQUARE, so the disc covers the whole
## picture and nothing else, which is why the circle and not the card glow is the worst case for
## readability. Owner: *"16, make it adjustable so I can test slightly different radius"* (`Q85`), so
## it is an export rather than a constant.
##
## ⚠ **16 -> 17 WITH THE OUTLINE.** The art square is 32x32 of drawing plus the shader's 1-unit rim on
## every side — 34 across — so a radius of 16 now stops one unit short and clips the picture's own
## outline, leaving a lit card with a rimless arc. The number was never "16"; it was "half the art
## square", and the art square grew.
@export var circle_radius : float = 17.0
## The circle's OWN over-art alpha (`Q217`=a — its own knob, not the glow's). The circle is doing a
## different job and covers a different thing: a halo around a silhouette barely covers art at all,
## while the circle covers the entire art square. Judged in the same S15 shot as `inner_alpha`, and
## expected to end up lower than this default rather than higher.
@export_range(0.0, 1.0, 0.01) var circle_inner_alpha : float = 0.5

## How wide the baked ramp texture is. 64 is what `PaletteRamp.window_texture` uses for the same
## axis, and it is also the step the shader's dither is scaled by — a dither that does not know the
## texture's resolution either does nothing or smears whole bands.
const RAMP_WIDTH := 64

## Cached bake of `glow_ramp`. Styles are shared preloads, so this is one texture per style for the
## whole run; the setter above and the gradient's own `changed` signal both drop it, so an inspector
## edit rebuilds on the next `apply()`.
var _ramp_tex : GradientTexture1D = null

func _drop_ramp_cache() -> void:
	_ramp_tex = null

## The glow's colour ramp as a texture: u = intensity, 0 at the halo's faint outer limit and 1 at
## the core. **LINEAR filtering, unlike every other ramp in the project** — the palette ramps are
## `filter_nearest` because hard columns are what read as pixel art, and this one is the granted
## off-palette exception, so it is allowed to be smooth. The chunkiness still arrives, from `grid`
## quantizing the POSITION this is sampled at.
##
## Null ramp means the style has no colours at all, which is a broken style rather than a supported
## state — the shader then draws nothing rather than white.
func ramp_texture() -> GradientTexture1D:
	if _ramp_tex: return _ramp_tex
	if not glow_ramp: return null
	_ramp_tex = GradientTexture1D.new()
	_ramp_tex.gradient = glow_ramp
	_ramp_tex.width = RAMP_WIDTH
	return _ramp_tex

## Hide the inherited `pixel`: `grid` above is this style's version of it, at a range that reaches
## screen resolution, and two inspector rows quantizing the same coordinate is the confusion the
## subclass split exists to prevent. The property still EXISTS and is still saved — it is simply not
## the one to edit here, and `apply()` ignores it.
func _validate_property(property : Dictionary) -> void:
	if property.name == &"pixel":
		property.usage = PROPERTY_USAGE_STORAGE

## Write every glow lever onto a material, on top of the shared ones. Called on creation and on style
## swap, NEVER per frame.
##
## ⚠ `u_pixel` is written TWICE — once by `super(mat)` from the inherited `pixel`, then again here
## from `grid`, which wins. That is the whole mechanism by which `grid` replaces it.
##
## ⚠ The layer arrays are padded to `MAX_LAYERS` before they are pushed. Godot matches an array
## uniform by declared size; a `PackedFloat32Array` of 2 against a `float[4]` does not partially fill
## it, it is rejected, and the shader then runs on whatever the uniform held before — which is a
## black glow with no error message.
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

## `src` at exactly `MAX_LAYERS` entries: truncated if it is longer, filled with `fallback` if it is
## shorter. A radius falls back to 1.0 (the layer covers the whole reach) and a gain to 0.0 (the
## layer contributes nothing), so an under-filled array is inert rather than wrong.
func _padded(src : PackedFloat32Array, fallback : float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(MAX_LAYERS)
	for i : int in range(MAX_LAYERS):
		out[i] = src[i] if i < src.size() else fallback
	return out
