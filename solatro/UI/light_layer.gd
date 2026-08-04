class_name LightLayer
extends ColorRect
## THE LIGHT LAYER — one full-screen surface carrying every live spotlight's dim, circle and beam
## (design §9, chart H; `Q240`=b). The arithmetic is `Shaders/light.gdshader`; this is the half that
## decides WHAT IS LIVE and hands it over.
##
## ⚠ **IT SITS ABOVE EVERYTHING AND EXEMPTS NOTHING** — `DESIGN.md` v9, GAP-004, owner: *"dim doesnt
## last long enough to matter for readability, dim everything without worrying about certain visuals
## being exempt"*. It is therefore the LAST child of `SceneRoot`: the props dim, the score popups
## dim, the focus panel dims, the HUD dims (`Q73`=a) and the card glow dims (`Q77`=a — which is the
## whole mechanism by which a glow reads only inside its circle or beam, chart G13). **Moving this
## node earlier in the tree silently un-dims whatever now draws after it**, so its position is a
## contract, recorded in `LAYERING.md`.
##
## ⚠ **SCREEN SPACE, AND IT DOES NOT SCROLL WITH THE BOARD** (§9 consequence 4). Every position it
## is handed is a GLOBAL canvas position — which, with one canvas layer and no camera offset, is
## already the viewport pixel the shader's `SCREEN_UV` resolves to. A card's `global_position`
## therefore arrives correct with the board's scroll already folded in, and there is no second copy
## of the scroll here to fall out of step with the real one.
##
## ⚠ **THE DIM IS DRIVEN BY LIGHT COUNT, NOT BY ACT STATE** (`QR2`=d). This node has no idea what a
## submit is and must not learn: `Q149` made the spotlight a general "this card just became active"
## cue, and scoring is one caller of it among several.

const LIGHT_SHADER := preload("res://Shaders/light.gdshader")

## Must equal `MAX_LIGHTS` in `light.gdshader`. ⚠ **NOT A POLICY — `Q107`:** *"No cap. soft cap at
## how many cards can fit on screen."* It is sized to the widest board that fits on screen, and a
## light past the end is a BUG rather than a designed limit, which is why `set_lights` raises rather
## than trimming quietly.
const MAX_LIGHTS := 64

## One live spotlight, in the layer's own terms. Positions are GLOBAL canvas coordinates.
class Light extends RefCounted:
	## Where the pool sits — the centre of the card's art square in global coordinates.
	var centre : Vector2 = Vector2.ZERO
	## The pool's radius in SCREEN pixels. `Q85` is 16 ART units, so the caller multiplies by the
	## live card scale rather than this node assuming one.
	var radius : float = 46.0
	## Where the beam comes from. ⚠ `Q117`: a beam never points upward; `Q114`: the origin sits
	## ~600 px above its target. Both are the CALLER's rules (S14 owns the allocator) — enforcing
	## them here as well would be a second copy that can disagree with the first.
	var origin : Vector2 = Vector2.ZERO
	## The beam's width where it leaves its origin. ⚠ Its width at the TARGET is not here: the
	## shader derives that from `radius`, so the cone's mouth cannot disagree with the pool it opens
	## onto (owner, 2026-08-04).
	var origin_width : float = 26.0
	## Extra half-width beyond the circle at the target end. 0 is the owner's answer — the cone's
	## mouth is exactly the circle.
	var flare : float = 0.0
	## This light's own strength, multiplying both its beam and its circle.
	var intensity : float = 1.0

## Live lights, replaced wholesale every time the caller re-derives them. ⚠ Re-read, never cached
## across a hook — the same `Q252`=(b) discipline the activation sweep runs under.
var _lights : Array[Light] = []
## Whether the current cue belongs to a scoring act. Drives `Q245`=(c)'s shallower casual dim, and
## it is the ONLY thing here that knows scoring exists — a flag the caller sets, not a state this
## node infers.
var _scoring : bool = false
## The dim's live value and where it is heading. Eased rather than snapped, because `QR2`=(d) ties
## the dim to the spotlight's presence and a spotlight arriving is not an instant.
var _dim : float = 0.0
## The game's own clock, for the beam's scrolling grain (`Q99`=a). ⚠ NEVER GLSL `TIME`: the built-in
## ignores the game's pacing, which is the standing rule across the whole FX layer.
var _time : float = 0.0
## The material, typed. ⚠ `CanvasItem.material` is a `Material`, so every push through it is an
## untyped call — and this project treats warnings as errors, so it does not even compile. One
## typed handle, set in `_ready`, is also one place a null would surface.
var _mat : ShaderMaterial = null

func _ready() -> void:
	# ⚠ `color` IS DELIBERATELY LEFT ALONE. `ColorRect` defaults to white, and `light.gdshader`
	# WRITES `COLOR` outright rather than multiplying what arrives — unlike `glow.gdshader`, which
	# folds its host's modulate back in (chart O18). Setting it here would be a literal the palette
	# suite is right to flag, standing for a value nothing reads.
	# It covers the screen and must never eat input — every button under it stays clickable.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = LIGHT_SHADER
	material = _mat
	_push_static()
	_push_lights()

## Replace the live set. Passing an empty array is what RETIRES the dim — there is no separate
## "stop" call, because the dim is a function of what is lit (`QR2`=d) and a second way to lower it
## is a second thing that can disagree.
##
## `scoring` selects the deep dim or `Q245`=(c)'s shallower casual one.
func set_lights(lights: Array[Light], scoring: bool = true) -> void:
	if lights.size() > MAX_LIGHTS:
		# ⚠ LOUD, NOT TRIMMED. `Q107` refuses a cap, so silently dropping the 65th light would be
		# this node inventing one — and it would be invisible, because the missing beam looks
		# exactly like a card that was not lit.
		push_error(("LightLayer: %d lights exceeds MAX_LIGHTS %d — raise it on BOTH sides " +
				"(this file and light.gdshader), or the board has outgrown the shader's array")
				% [lights.size(), MAX_LIGHTS])
		lights = lights.slice(0, MAX_LIGHTS)
	_lights = lights
	_scoring = scoring
	if _mat: _push_lights()

## Is anything lit right now — which is the same question as "is the dim up" (`QR2`=d).
func is_lit() -> bool:
	return not _lights.is_empty()

func _process(delta: float) -> void:
	if not _mat: return
	_time += delta * _pacing()
	_mat.set_shader_parameter(&"u_time", _time)
	var target := _dim_target()
	if not is_equal_approx(_dim, target):
		# The rise and the fall are separate fractions of `Game.get_delay()` (`Q167`=a), so the dim
		# compresses with the act speed-up along with everything else rather than running to a
		# wall-clock schedule the rest of the show has left behind.
		var fraction : float = _settings().spotlight_dim_in_fraction if target > _dim \
				else _settings().spotlight_dim_out_fraction
		var span := maxf(_delay() * fraction, 0.0001)
		_dim = move_toward(_dim, target, delta / span)
		_mat.set_shader_parameter(&"u_dim", _dim)

## Where the dim is heading: up while anything is lit, down when nothing is (`QR2`=d), scaled to
## `Q245`=(c)'s shallower value outside scoring.
func _dim_target() -> float:
	if _lights.is_empty(): return 0.0
	var s := _settings()
	return s.spotlight_dim_target * (1.0 if _scoring else s.spotlight_dim_casual_scale)

## The two arrays the shader reads, padded to `MAX_LIGHTS`. ⚠ Godot matches an array uniform by
## DECLARED SIZE — a shorter array is rejected whole rather than partially filled, and the shader
## then runs on whatever it held before, with no error. The same trap `FxGlowStyle` pads around.
func _push_lights() -> void:
	var lights := PackedVector4Array()
	var beams := PackedVector4Array()
	lights.resize(MAX_LIGHTS)
	beams.resize(MAX_LIGHTS)
	for i : int in _lights.size():
		var l : Light = _lights[i]
		lights[i] = Vector4(l.centre.x, l.centre.y, l.radius, l.intensity)
		beams[i] = Vector4(l.origin.x, l.origin.y, l.origin_width, l.flare)
	_mat.set_shader_parameter(&"u_lights", lights)
	_mat.set_shader_parameter(&"u_beams", beams)
	_mat.set_shader_parameter(&"u_light_count", _lights.size())

## The values that only change when the player changes a setting.
##
## ⚠ **`fx_intensity` IS FOLDED IN HERE, EXACTLY AS `FxAttachment` DOES IT** — one multiplier is what
## lets a "reduce effects" setting reach every effect without editing a resource. `Q83` is explicit
## about what it may NOT remove: *"keeps beams glow and dim"*, so it scales the LIGHTS and the dim
## stands (gate **G2.4**). The shader is where that split lives; this only supplies the number.
func _push_static() -> void:
	_mat.set_shader_parameter(&"u_brightness", _settings().fx_intensity)
	_mat.set_shader_parameter(&"u_dim", _dim)

func _settings() -> PlayerSettings:
	return SettingsManager.settings

## One unit of show time, the same number every other flourish is a fraction of.
func _delay() -> float:
	var game := CardEnvironment.get_current_game()
	return game.get_delay() if game else _settings().base_delay

## The act speed-up's live compression, so the beam's grain scrolls at the pace the rest of the show
## is running at rather than drifting out of step during a long cascade.
func _pacing() -> float:
	var base := _settings().base_delay
	return base / maxf(_delay(), 0.0001) if base > 0.0 else 1.0
