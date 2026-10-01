@tool
class_name LightLayer
extends ColorRect
# THE LIGHT LAYER: one full-screen surface carrying every live spotlight's dim, circle and beam.
# The arithmetic is `Shaders/light.gdshader`; this decides WHAT IS LIVE and hands it over.

# ⚠ IT SITS ABOVE EVERYTHING AND EXEMPTS NOTHING, so it is the LAST child of `SceneRoot`: props,
# popups, the focus panel, the HUD and the card glow all dim. Moving it earlier silently un-dims
# whatever then draws after it; its position is a contract recorded in `LAYERING.md`.

# ⚠ SCREEN SPACE, AND IT DOES NOT SCROLL WITH THE BOARD. Every position it is handed is a GLOBAL
# canvas position, which with one canvas layer and no camera offset is the viewport pixel
# `SCREEN_UV` resolves to, so the board's scroll arrives already folded in.

# ⚠ THE DIM IS DRIVEN BY LIGHT COUNT, NOT BY ACT STATE. This node does not know what a submit is:
# the spotlight is a general "this card just became active" cue, and scoring is one caller of it.

const LIGHT_SHADER := preload("res://Shaders/light.gdshader")

# ⚠ If a knob is not in `FxSpotlightStyle.apply()`, it does not exist: a uniform left at its shader
# default cannot be reached from GDScript.

## The look, as a resource.
@export var style : FxSpotlightStyle = preload("res://Shaders/Styles/spotlight_default.tres"):
	set(value):
		style = value
		_restyle()

# A style is written ONCE on creation and on swap, never per frame. A tuning tool calls this when it
# detects an edit, because a custom resource does not announce its own property changes.
func restyle() -> void:
	_restyle()

# `_push_static` follows the style so `fx_intensity` folds into the brightness the style just wrote:
# one multiplier lets a "reduce effects" setting reach every effect without editing a resource.
func _restyle() -> void:
	if not _mat or not style: return
	style.apply(_mat)
	_push_static()

# ⚠ NOT A POLICY: there is no cap. It is sized to the widest board that fits on screen, and a light
# past the end is a BUG, which is why `set_lights` raises rather than trimming quietly.

## Must equal `MAX_LIGHTS` in `light.gdshader`.
const MAX_LIGHTS := 64

# ⚠ THE ORIGIN'S RULES ARE THE CALLER'S (a beam never points upward; the lamp sits ~600 px above its
# target): enforcing them here too would be a second copy that can disagree with the allocator.

# ⚠ `gated` IS FALSE FOR A MOMENTARY CUE, whose life is its own beam: outside a submit `_revealed`
# is false, so a gated cue would be multiplied by `_show = 0`, and raising `_revealed` for it would
# drag the previous section's faded beams back up. Its whole envelope is in `intensity`.

## One live spotlight, in the layer's own terms. Positions are GLOBAL canvas coordinates.
class Light extends RefCounted:
	## Where the pool sits: the drawn card's centre (`CardVisual.spotlight_center()`), global.
	var centre : Vector2 = Vector2.ZERO
	## The pool's radius in SCREEN pixels: the caller's art-unit radius times the card's drawn scale.
	var radius : float = 46.0
	## Where the beam comes from.
	var origin : Vector2 = Vector2.ZERO
	## The beam's width at its origin. ⚠ At the TARGET the shader derives it from `radius`.
	var origin_width : float = 26.0
	## Extra half-width beyond the circle at the target end; 0 means the mouth is exactly the circle.
	var flare : float = 0.0
	## This light's own strength, multiplying both its beam and its circle.
	var intensity : float = 1.0
	## Does this light ride the per-section reveal gate (`_show`)? True for the scoring beam.
	var gated : bool = true

## Live lights, replaced wholesale on every re-derive. ⚠ Re-read, never cached across a hook.
var _lights : Array[Light] = []
## Whether the current cue belongs to a scoring act: a flag the caller sets, never inferred here.
var _scoring : bool = false
## The dim's live value, eased rather than snapped because a spotlight arriving is not an instant.
var _dim : float = 0.0

# ⚠ VISIBILITY IS A SEPARATE AXIS FROM THE LIGHT SET. `set_lights()` answers which cards are lit and
# where; `_revealed` answers whether the show is up, so the dim can fall between sections while the
# set stays lit (the set is never emptied mid-act).

# ⚠ FADING, NOT CLEARING: the lights survive the fade at their positions, so the next section
# TRAVELS from them rather than respawning.

## Is the section being revealed right now: the per-section pulse.
var _revealed : bool = false
## The eased 0-1 the reveal drives; multiplies BOTH the dim and every light's intensity.
var _show : float = 0.0
## The game's own clock, for the beam's scrolling grain. ⚠ NEVER GLSL `TIME`: it ignores pacing.
var _time : float = 0.0
## The material, typed: `CanvasItem.material` is a `Material`, and a push through it is untyped.
var _mat : ShaderMaterial = null

# ⚠ `@tool`, BUT `_ready()` DOES NOTHING IN THE EDITOR. Assigning `material` there would attach a
# `ShaderMaterial` to a node `game_view.tscn` OWNS, and saving the scene would write it in.
# `Tools/spotlight_tool.tscn` builds its own instance in code and calls `ensure_built()` on it.
func _ready() -> void:
	if Engine.is_editor_hint(): return
	ensure_built()

# Split out of `_ready()` so an editor-side tool can build an instance it owns.

# ⚠ `color` IS TRANSPARENT IN `game_view.tscn`, AND THAT IS LOAD-BEARING. The shader WRITES `COLOR`,
# so at runtime the value is inert; in the editor no material is assigned, and a `ColorRect` with
# no `color` is OPAQUE WHITE over the whole screen. `test_palette.gd`'s ALLOW_LINES carries it.

# It covers the screen and must never eat input: every button under it stays clickable.
func ensure_built() -> void:
	if _mat: return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = LIGHT_SHADER
	material = _mat
	_restyle()
	_push_lights()

# Passing an empty array is what RETIRES the dim: there is no separate "stop" call, because the dim
# is a function of what is lit and a second way to lower it is a second thing that can disagree.
# `scoring` selects the deep dim or the shallower casual one.

# ⚠ OVER `MAX_LIGHTS` IS LOUD, NOT TRIMMED QUIETLY: a silently dropped light looks exactly like a
# card that was not lit. ⚠ Logged as a TRANSITION (was -> now): "0 -> 3" is a beam appearing and
# "3 -> 3" is the per-frame re-push that follows a moving card.

## Replace the live set.
func set_lights(lights: Array[Light], scoring: bool = true) -> void:
	if lights.size() > MAX_LIGHTS:
		push_error(("LightLayer: %d lights exceeds MAX_LIGHTS %d — raise it on BOTH sides " +
				"(this file and light.gdshader), or the board has outgrown the shader's array")
				% [lights.size(), MAX_LIGHTS])
		lights = lights.slice(0, MAX_LIGHTS)
	if EventLog.is_on(EventLog.CH_LIGHT):
		EventLog.event(EventLog.CH_LIGHT, "set_lights",
				"%d -> %d scoring=%s dim=%.3f target=%.3f"
				% [_lights.size(), lights.size(), str(scoring), _dim, _dim_target()])
	_lights = lights
	_scoring = scoring
	if _mat: _push_lights()

## Raise the show on a section's reveal, fade it as its scoring begins. ⚠ Never touches `_lights`.
func set_revealed(revealed: bool) -> void:
	if _revealed == revealed: return
	_revealed = revealed
	EventLog.event(EventLog.CH_LIGHT, "revealed" if revealed else "reveal_faded",
			"show=%.3f lights=%d" % [_show, _lights.size()])

# ⚠ REQUIRES THE SHOW TO BE UP: a faded light set is not lit, whatever it still holds. Callers that
# mean "do I still hold a set" want `_lights.size()`.

# ⚠ `_revealed or _show > 0.0`, not `_show` alone: on the frame a reveal is raised the ease has not
# run, so `_show` is still 0 and the layer would report itself dark as the section lit up.

# ⚠ PRESENCE, not intensity, for an ungated light, for the same one-frame reason: a cue light spawns
# at `intensity = 0` and is FREED the moment its retire reaches 0, so it exists only while its show
# is up.

## Is anything lit right now, which is the same question as "is the dim up".
func is_lit() -> bool:
	if not _lights.is_empty() and _has_ungated(): return true
	return not _lights.is_empty() and (_revealed or _show > 0.0)

# HIDDEN WHILE NOTHING IS LIT and the dim has eased out, which is most of a session: the full-screen
# pass is then a no-op composite. Processing continues, so the clock and the eases never stall.

# THE SHOW EASES AHEAD OF THE DIM: `_dim_target()` reads `_show`, so the dim follows in the same
# frame. Every ease is a fraction of `Game.get_delay()`, so it compresses with the act speed-up; a
# wall-clock fade would still be going when the next section had started.

# ⚠ THE SHOW HAS ITS OWN FRACTIONS, separate from the dim's: set `spotlight_dim_in_fraction` below
# `spotlight_show_in_fraction` and the room darkens before the beams finish. Every light's intensity
# is scaled by `_show`, so beams and circles fade WITH the dim.

# The dim logs only its ARRIVAL and DEPARTURE, never the frames between.
func _process(delta: float) -> void:
	if not _mat: return
	visible = not _lights.is_empty() or _dim > 0.0
	_time += delta * _pacing()
	_mat.set_shader_parameter(&"u_time", _time)
	var show_target := 1.0 if _revealed else 0.0
	if not is_equal_approx(_show, show_target):
		var show_fraction : float = _settings().spotlight_show_in_fraction if show_target > _show \
				else _settings().spotlight_show_out_fraction
		_show = move_toward(_show, show_target,
				delta / maxf(_delay() * show_fraction, 0.0001))
		_push_lights()
	var target := _dim_target()
	if not is_equal_approx(_dim, target):
		var fraction : float = _settings().spotlight_dim_in_fraction if target > _dim \
				else _settings().spotlight_dim_out_fraction
		var span := maxf(_delay() * fraction, 0.0001)
		var before := _dim
		_dim = move_toward(_dim, target, delta / span)
		_mat.set_shader_parameter(&"u_dim", _dim)
		if EventLog.is_on(EventLog.CH_LIGHT):
			if is_equal_approx(before, 0.0) and _dim > 0.0:
				EventLog.event(EventLog.CH_LIGHT, "dim_rising", "target=%.3f span=%.3fs"
						% [target, span])
			elif is_equal_approx(_dim, target):
				EventLog.event(EventLog.CH_LIGHT, "dim_settled", "at=%.3f" % _dim)

# ⚠ SCALED BY `_show`, which is what makes the dim pulse per section instead of standing for the
# whole act.

# ⚠ AN UNGATED LIGHT CARRIES ITS OWN SHOW: the dim rises with a cue's beam and falls when it
# retires. The MAX, not a second term, keeps one dim for the whole board, so N cues do not stack
# darker than one and a cue in a faded section gap does not re-raise that section's beams.

## Where the dim is heading: up while anything is lit, shallower outside scoring, else down.
func _dim_target() -> float:
	if _lights.is_empty(): return 0.0
	var s := _settings()
	return s.spotlight_dim_target * (1.0 if _scoring else s.spotlight_dim_casual_scale) \
			* maxf(_show, _ungated_show())

## The strongest ungated light's envelope, 0 with none: the cue's equivalent of `_show`.
func _ungated_show() -> float:
	var strongest := 0.0
	for l : Light in _lights:
		if not l.gated: strongest = maxf(strongest, l.intensity)
	return strongest

## Is any light exempt from the reveal gate, that is, is a momentary cue live?
func _has_ungated() -> bool:
	for l : Light in _lights:
		if not l.gated: return true
	return false

# The director re-pushes every frame to follow moving cards and the show ease pushes again; most
# frames nothing changed, so comparing here saves two redundant GPU uploads per frame.

## Last-pushed uniform state.
var _pushed_lights := PackedVector4Array()
var _pushed_beams := PackedVector4Array()
var _pushed_count : int = -1

# ⚠ PADDED TO `MAX_LIGHTS`: Godot matches an array uniform by DECLARED SIZE, so a shorter array is
# rejected whole and the shader runs on whatever it held before, with no error.

# ⚠ `_show` SCALES THE INTENSITY, never the count, or a fade would look like beams popping out one
# at a time. An UNGATED light skips `_show`: its envelope is already in `intensity`.

## Pushes the two arrays the shader reads.
func _push_lights() -> void:
	var lights := PackedVector4Array()
	var beams := PackedVector4Array()
	lights.resize(MAX_LIGHTS)
	beams.resize(MAX_LIGHTS)
	for i : int in _lights.size():
		var l : Light = _lights[i]
		var show : float = _show if l.gated else 1.0
		lights[i] = Vector4(l.centre.x, l.centre.y, l.radius, l.intensity * show)
		beams[i] = Vector4(l.origin.x, l.origin.y, l.origin_width, l.flare)
	if _lights.size() == _pushed_count and lights == _pushed_lights and beams == _pushed_beams:
		return
	_pushed_lights = lights
	_pushed_beams = beams
	_pushed_count = _lights.size()
	_mat.set_shader_parameter(&"u_lights", lights)
	_mat.set_shader_parameter(&"u_beams", beams)
	_mat.set_shader_parameter(&"u_light_count", _lights.size())

# ⚠ THE STYLE'S BRIGHTNESS TIMES `fx_intensity`: the setting is the player's accessibility
# multiplier, the style's is the art decision, and dropping either leaves a knob that does nothing.
# It scales the LIGHTS only; the dim stands, and the shader is where that split lives.

## The values that only change when the player changes a setting.
func _push_static() -> void:
	var art_brightness : float = style.brightness if style else 1.0
	_mat.set_shader_parameter(&"u_brightness", art_brightness * _settings().fx_intensity)
	_mat.set_shader_parameter(&"u_dim", _dim)

# ⚠ THE EDITOR INSTANTIATES NO AUTOLOADS, so a bare read of `SettingsManager` fails the moment an
# editor-side tool drives this layer. Only the tool assigns this; the game leaves it null.

## An editor-side tool's own tunable settings, so every knob it drags reaches the real layer.
static var editor_settings : PlayerSettings = null

# ⚠ THE OVERRIDE WINS IN BOTH CONTEXTS: were it editor-only, a PLAYED `Tools/spotlight_tool.tscn`
# would read the player's saved settings here while its own cascade clock used the tool's, and two
# clocks cut the show off part-way up.

# ⚠ DELEGATES TO `FxAttachment.settings()`, the ONE place that answers "which PlayerSettings".
func _settings() -> PlayerSettings:
	if editor_settings: return editor_settings
	return FxAttachment.settings()

# No `Game` in the editor: `get_current_game()` is set from `Game._enter_tree`, which never runs
# there, so the setting's own `base_delay` stands in and is what the tool makes tunable.

## One unit of show time, the same number every other flourish is a fraction of.
func _delay() -> float:
	var game := CardEnvironment.get_current_game() if not Engine.is_editor_hint() else null
	return game.get_delay() if game else _settings().base_delay

## The act speed-up's live compression, so the beam's grain scrolls at the show's pace.
func _pacing() -> float:
	var base := _settings().base_delay
	return base / maxf(_delay(), 0.0001) if base > 0.0 else 1.0
