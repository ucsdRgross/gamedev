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
## **IS THE SECTION BEING REVEALED RIGHT NOW** — the owner's per-section pulse (GAP-006):
##
## > *"spotlight + dim occurs as cards of section get revealed, with both spotlight and dim effect
## > fading away as scoring starts to happen. When next section is revealed, spotlight and dim effect
## > are visible again, moving to new location, then fade away again."*
##
## ⚠ **VISIBILITY IS A SEPARATE AXIS FROM THE LIGHT SET, AND THAT SEPARATION IS THE WHOLE FIX.**
## `set_lights()` answers *which cards are lit and where*; this answers *is the show up*. Before
## GAP-006 there was only the first, so the dim could not fall while anything was lit — and since
## `Q16`=(c) never empties the set between sections, it could never fall mid-act at all. Measured on
## the owner's playtest: one rise, one fall, EIGHT sections.
## ⚠ Fading rather than clearing is also what keeps chart E buildable: the lights survive the fade at
## their positions, so the next section can TRAVEL from them rather than respawning (*"no instant
## movements or spawning in and out"*).
var _revealed : bool = false
## The eased 0-1 the reveal drives. Multiplies BOTH the dim and every light's intensity, so the two
## fade together as one show rather than as two effects that can drift apart.
var _show : float = 0.0
## The game's own clock, for the beam's scrolling grain (`Q99`=a). ⚠ NEVER GLSL `TIME`: the built-in
## ignores the game's pacing, which is the standing rule across the whole FX layer.
var _time : float = 0.0
## The material, typed. ⚠ `CanvasItem.material` is a `Material`, so every push through it is an
## untyped call — and this project treats warnings as errors, so it does not even compile. One
## typed handle, set in `_ready`, is also one place a null would surface.
var _mat : ShaderMaterial = null

func _ready() -> void:
	# ⚠ **`color` IS TRANSPARENT IN `game_view.tscn`, AND THAT IS LOAD-BEARING — DO NOT "TIDY" IT
	# AWAY.** `light.gdshader` WRITES `COLOR` outright rather than multiplying what arrives (unlike
	# `glow.gdshader`, which folds its host's modulate back in, chart O18), so at RUNTIME the value is
	# genuinely inert — which is why an earlier version of this comment argued for leaving it unset.
	# That argument was wrong, and the owner found it: this script is not `@tool` (PLAN.md §1.8 —
	# `@tool` silently drops properties, VFX.md §6.2b), so in the EDITOR `_ready()` never runs, no
	# material is ever assigned, and a `ColorRect` with no `color` is OPAQUE WHITE covering the whole
	# screen. `game_view.tscn` was unopenable. The transparent literal is the node's honest resting
	# state for every context where the shader is not running; `test_palette.gd`'s ALLOW_LINES carries
	# it, because a fully transparent colour is not a colour choice.
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
	if EventLog.is_on(EventLog.CH_LIGHT):
		# ⚠ Logged as a TRANSITION (was -> now), not as a state. "3 lights" tells you nothing; "0 -> 3"
		# is a beam appearing and "3 -> 3" is the per-frame re-push that follows a moving card, and
		# those look identical in a state dump.
		EventLog.event(EventLog.CH_LIGHT, "set_lights",
				"%d -> %d scoring=%s dim=%.3f target=%.3f"
				% [_lights.size(), lights.size(), str(scoring), _dim, _dim_target()])
	_lights = lights
	_scoring = scoring
	if _mat: _push_lights()

## Raise or fade the show. `true` on each section's reveal, `false` as its scoring begins (GAP-006).
## ⚠ Does NOT touch `_lights` — see `_revealed`.
func set_revealed(revealed: bool) -> void:
	if _revealed == revealed: return
	_revealed = revealed
	EventLog.event(EventLog.CH_LIGHT, "revealed" if revealed else "reveal_faded",
			"show=%.3f lights=%d" % [_show, _lights.size()])

## Is anything lit right now — which is the same question as "is the dim up" (`QR2`=d).
## ⚠ Now also requires the show to be UP: a light set that is faded out is not lit, whatever it
## still holds. Callers that mean "do I still hold a set" want `_lights.size()`.
func is_lit() -> bool:
	# ⚠ `_revealed or _show > 0.0`, not `_show > 0.0` alone: the instant a reveal is raised the ease
	# has not run yet, so `_show` is still exactly 0 for one frame. Asking only about `_show` would
	# make the layer report itself dark on the very frame the section lit up — true of the eased
	# value, false about the show, and a race for every caller.
	return not _lights.is_empty() and (_revealed or _show > 0.0)

func _process(delta: float) -> void:
	if not _mat: return
	_time += delta * _pacing()
	_mat.set_shader_parameter(&"u_time", _time)
	# THE SHOW'S OWN EASE, ahead of the dim's — `_dim_target()` reads `_show`, so easing it first
	# means the dim follows within the same frame rather than one behind.
	# ⚠ It rides the SAME two fractions as the dim (`Q167`=a, fractions of `Game.get_delay()`), so the
	# fade compresses with the act speed-up. A wall-clock fade would still be going when the next
	# section had already started.
	var show_target := 1.0 if _revealed else 0.0
	if not is_equal_approx(_show, show_target):
		var show_fraction : float = _settings().spotlight_dim_in_fraction if show_target > _show \
				else _settings().spotlight_dim_out_fraction
		_show = move_toward(_show, show_target,
				delta / maxf(_delay() * show_fraction, 0.0001))
		# Every light's intensity is scaled by `_show`, so the beams and circles fade WITH the dim
		# rather than snapping off while it eases.
		_push_lights()
	var target := _dim_target()
	if not is_equal_approx(_dim, target):
		# The rise and the fall are separate fractions of `Game.get_delay()` (`Q167`=a), so the dim
		# compresses with the act speed-up along with everything else rather than running to a
		# wall-clock schedule the rest of the show has left behind.
		var fraction : float = _settings().spotlight_dim_in_fraction if target > _dim \
				else _settings().spotlight_dim_out_fraction
		var span := maxf(_delay() * fraction, 0.0001)
		var before := _dim
		_dim = move_toward(_dim, target, delta / span)
		_mat.set_shader_parameter(&"u_dim", _dim)
		# Only the ARRIVAL and the DEPARTURE, never the frames between — a dim easing over 20 frames
		# would otherwise be 20 lines saying the same thing, and burying the events that matter under
		# the ones that do not is how a log stops being read.
		if EventLog.is_on(EventLog.CH_LIGHT):
			if is_equal_approx(before, 0.0) and _dim > 0.0:
				EventLog.event(EventLog.CH_LIGHT, "dim_rising", "target=%.3f span=%.3fs"
						% [target, span])
			elif is_equal_approx(_dim, target):
				EventLog.event(EventLog.CH_LIGHT, "dim_settled", "at=%.3f" % _dim)

## Where the dim is heading: up while anything is lit, down when nothing is (`QR2`=d), scaled to
## `Q245`=(c)'s shallower value outside scoring.
func _dim_target() -> float:
	if _lights.is_empty(): return 0.0
	var s := _settings()
	# ⚠ SCALED BY `_show`, which is what makes the dim pulse per section instead of standing for the
	# whole act (GAP-006). With `_show` at 1 this is exactly the pre-GAP-006 value, so the reveal beat
	# itself is unchanged — only what happens between beats is new.
	return s.spotlight_dim_target * (1.0 if _scoring else s.spotlight_dim_casual_scale) * _show

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
		# ⚠ `_show` SCALES THE INTENSITY rather than the count: fading a light to nothing must not
		# change how many lights the shader is told about, or a fade would look like beams popping out
		# of existence one at a time.
		lights[i] = Vector4(l.centre.x, l.centre.y, l.radius, l.intensity * _show)
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
