@tool
class_name ParticleSpec
extends Resource
## One KIND of particle, as data. Every particle in the game is described by one of these and
## simulated by ParticleEngine; kinds are .tres files (ember.tres, dust.tres), never code — the
## same rule FxStyle follows, so all visual-effect tuning stays in one place.

## Seconds a particle lives, and how much that varies per particle (0 = every one identical).
@export var lifetime : float = 1.2
@export_range(0.0, 1.0, 0.01) var lifetime_var : float = 0.4

## Launch speed along the emit direction, its variation, and how wide the cone spreads.
@export var speed : float = 18.0
@export_range(0.0, 1.0, 0.01) var speed_var : float = 0.5
@export_range(0.0, PI, 0.01) var spread : float = 0.6

## Art units per second squared. Negative y rises, which is what embers do.
@export var gravity : Vector2 = Vector2(0.0, -14.0)
## Fraction of velocity shed per second — what makes a rising ember slow and hang.
@export_range(0.0, 8.0, 0.05) var drag : float = 1.6

## Size in art units at birth and at death. Particles carry NO rotation: a rotating sprite is a
## rotating pixel grid, which the project's universal VFX rule forbids.
@export var size_start : float = 2.0
@export var size_end : float = 0.5

## Colour over life, as an ORDERED LIST OF PALETTE ENTRIES (T21) plus a parallel alpha per entry.
## Sampled by normalized age. The Gradient it is compiled into uses CONSTANT interpolation, so a
## particle STEPS from one exact palette entry to the next and never sits on an in-between colour —
## an interpolating gradient is exactly what put off-palette colours on the embers.
##
## Alpha still varies continuously (it is a fade, not a colour), so the RGB stays on-palette while
## the particle disappears.
@export var ramp_source : PaletteRamp = null:
	set(value):
		ramp_source = value
		_gradient = null
## One alpha per ramp entry. Shorter than the ramp means the missing tail is opaque.
@export var ramp_alphas : PackedFloat32Array = PackedFloat32Array():
	set(value):
		ramp_alphas = value if value != null else PackedFloat32Array()
		_gradient = null

## Compiled from `ramp_source` on first use — specs are shared preloads, so this is built once.
var _gradient : Gradient = null

## The colour at normalized age `t`. Hard steps between palette entries.
func color_at(t : float) -> Color:
	var g := _build_gradient()
	if not g: return Color.WHITE
	return g.sample(clampf(t, 0.0, 1.0))

func _build_gradient() -> Gradient:
	if _gradient: return _gradient
	if not ramp_source or ramp_source.size() == 0: return null
	var cols := ramp_source.colors()
	var g := Gradient.new()
	# GRADIENT_INTERPOLATE_CONSTANT is the whole point: a colour holds until the next stop, so every
	# rendered particle carries an exact palette entry.
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for i : int in range(cols.size()):
		var c := cols[i]
		c.a = ramp_alphas[i] if i < ramp_alphas.size() else 1.0
		g.add_point(float(i) / float(maxi(cols.size() - 1, 1)), c)
	_gradient = g
	return _gradient
