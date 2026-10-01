@tool
class_name SpotlightTool
extends Node
## Poses real cards, the real LightLayer and the real glow on the board's geometry to tune the spotlight's look; `--trace` runs a real act.

# ⚠ EVERYTHING RENDERS INSIDE A SubViewport: light.gdshader is SCREEN-SPACE, and the editor's 2D
# view pans and zooms. Every node built here is OWNERLESS (an owned child would be saved into the
# .tscn), and the editor instantiates no autoloads, so one shared settings stand-in drives it all.

const SCENARIOS_PATH := "res://tools/spotlight_scenarios.json"
const SHOT_DIR := "user://logs/events/spotlight_tool/"
## The shared run-save park, preloaded by PATH: the `SolatroTest` global name does not resolve from this @tool script's parse.
const _SAVE_GUARD := preload("res://Tests/Support/test_base.gd")

## The fully-open extra a revealed row adds, by `PlayArea`'s own formula, so the tool obeys `spotlight_separation_mode`.
func _open_span() -> float:
	return PlayArea.row_open_span(settings, PlayArea.board_separation_px(settings))

func _touch(_v : Variant = null) -> void:
	_dirty = true

var _dirty := true
var _scenarios : Array = []
var _root : SubViewport = null
var _board : Node2D = null
var _layer : LightLayer = null
## Every built card, keyed by its slot so a section can name slots rather than indices.
var _slot_card : Dictionary[Vector2i, CardVisual] = {}
var _origins := SpotlightOrigins.new()

## One live light with a life of its own, mirroring `SpotlightDirector._Beam`: it travels, spawns and retires rather than snapping.
class _TBeam extends RefCounted:
	## The board slot it lights, or the last one it lit while retiring.
	var slot : Vector2i = Vector2i.ZERO
	## ⚠ AN INDEX, not a point — `SpotlightOrigins.advance()` moves off-screen lamps every frame.
	var origin_idx : int = -1
	## Where the travel started; meaningless once `t` is 1.
	var from : Vector2 = Vector2.ZERO
	## Travel progress 0..1; 1 means settled, with no separate arrived state to fall out of step with.
	var t : float = 1.0
	## Spawn-in / retire-out, 0..1. Scales INTENSITY only, never size.
	var fade : float = 1.0
	var retiring : bool = false

## Board teardowns so far: a rebuild is meant to be RARE, and one per frame reads as the effect running sped up.
var _rebuild_count : int = 0
var _beams : Array[_TBeam] = []
## The slots the beams were last matched against; a CHANGE here stands in for `spotlight_section_changed`.
var _last_wanted : Array[Vector2i] = []

## The sections this scenario walks, each a list of `Vector2i(col, depth)` slots; a single `lit` is a cascade of one.
var _sections : Array[Array] = []
var _section : int = 0
var _phase_t : float = 0.0
## Is the current section's show up? Driven by the cascade clock, or held by `revealed`.
var _up : bool = true

@export_group("Scenario")
## The preset, from `spotlight_scenarios.json` so adding one is editing that file; `_get_property_list` builds the dropdown.
var scenario : int = 0:
	set(v):
		scenario = v
		_section = 0
		_phase_t = 0.0
		_apply_scenario_knobs()
		_touch()

# PUSHES THE SELECTED SCENARIO'S OWN KNOBS ONTO THE TOOL, ALWAYS ASSIGNED: a knob set only when
# present keeps whatever the last preset left, so the presets showed each other's worlds. Every
# scenario declares `row_separation`, and `--verify` marks one that does not as SUSPECT.
func _apply_scenario_knobs() -> void:
	var s := _current_scenario()
	if s.is_empty(): return
	var sep : bool = s.get("row_separation", false)
	row_separation = sep
	if settings:
		var fx : float = s.get("fx_intensity", 1.0)
		settings.fx_intensity = fx
		if is_instance_valid(_layer): _layer.restyle()

@export_group("Playback")
## Loops the scenario's sections as the game would run them; a still frame cannot show a pulse, a travel or a retire.
@export var play : bool = true:
	set(v): play = v; _phase_t = 0.0; _retiring = false; _touch()
## With `play` off, hold this section (0-based) so a still frame can be judged.
@export var section : int = 0:
	set(v): section = v; _section = v; _touch()
## With `play` off, whether the show is up: `LightLayer.set_revealed` by hand.
@export var revealed : bool = true:
	set(v): revealed = v; _touch()
## The deep scoring dim, or the shallower casual one; a scenario may override it.
@export var scoring : bool = true:
	set(v): scoring = v; _touch()

@export_group("Board")
## Simulates the row reveal: the lit row's strip opens toward a full card and everything below it moves down.
@export var row_separation : bool = true:
	set(v): row_separation = v; _touch()
## How far the separated row opens, 0 = closed (the shipped strip) and 1 = a full card.
@export_range(0.0, 1.0, 0.05) var separation_amount : float = 1.0:
	set(v): separation_amount = v; _touch()

@export_group("Screen")
## The dummy screen the beam origins spread across: its width spreads the lamps and its bottom is where beams enter.
@export var screen_size : Vector2i = Vector2i(1152, 648):
	set(v): screen_size = v; _touch()

@export_group("Glow")
## The glow on each active card, built the way a host builds one; judge it together with the circle.
@export var glow : bool = true:
	set(v): glow = v; _touch()
## The card glow's style, the shipped `.tres` edited live.
@export var glow_style : FxGlowStyle = preload("res://Shaders/Styles/glow_card.tres"):
	set(v): glow_style = v; _touch()

@export_group("Tunables")
## Empty uses the ONE shared `PlayerSettings` the game runs on: the tunables here are the shipped resources, edited in place.
@export var settings : PlayerSettings = null:
	set(v): settings = v; _touch()
	get:
		if settings: return settings
		return FxAttachment.settings()
@export var spotlight_style : FxSpotlightStyle = preload("res://Shaders/Styles/spotlight_default.tres"):
	set(v): spotlight_style = v; _touch()

# The settings go in BEFORE any rebuild, which reads them. Trace first: it tears the preview down
# and stands up a real `GameView`, so the two modes never both proceed.
func _ready() -> void:
	_load_scenarios()
	_apply_settings()
	set_process(true)
	if Engine.is_editor_hint(): return
	if "--trace" in OS.get_cmdline_user_args(): _maybe_trace()
	elif "--verify" in OS.get_cmdline_user_args(): _maybe_verify()
	else: _maybe_shoot_all()

## Points every consumer at the ONE `PlayerSettings` instance, so card geometry and beams agree on `card_scale`.
func _apply_settings() -> void:
	if settings == null: settings = FxAttachment.settings()
	LightLayer.editor_settings = settings

## The light's style, never null: read back from the layer, which holds the authoritative reference.
func _style() -> FxSpotlightStyle:
	if is_instance_valid(_layer) and _layer.style: return _layer.style
	return spotlight_style

## How often the previewed resources are re-read: a script resource's `@export` edit emits no `changed`, so it is polled.
const WATCH_SECS := 0.25

var _watch_wait := 0.0
## Every inspector-visible value of every previewed resource, as of the last push.
var _watched : Array = []

# Polls the resources before the rebuild check, so an edit lands this frame; then, in one order so
# nothing reads last frame's positions: the reveal (it MOVES cards), the rig, the outline, the
# beams' travel and fade, and the lights re-pushed from where the cards now are.
func _process(delta : float) -> void:
	_apply_settings()
	_watch_wait += delta
	if _watch_wait >= WATCH_SECS:
		_watch_wait = 0.0
		var now := _fingerprint()
		if now != _watched:
			_watched = now
			if is_instance_valid(_layer): _layer.restyle()
			_dirty = true
	if _dirty:
		_dirty = false
		_rebuild()
	if not is_instance_valid(_layer): return
	if play and _sections.size() > 0:
		_advance_cascade(delta)
	else:
		_up = revealed
	_layer.set_revealed(_up)
	_ease_separation(delta)
	_advance_cards(delta)
	_track_glow_outlines()
	_advance_beams(delta)
	_push_lights()

# ONE SECTION'S VISIBLE BEAT, the longest of every arrival and the show's own ramp, so no instance
# is cut short: a new light fades in and a mover rides in at full intensity, both as long. Read
# through the accessor the game's reveal beat uses, so the tool shows no hold the game lacks.
func _beat() -> float:
	var unit : float = settings.base_delay
	return maxf(unit * settings.spotlight_reveal_beat_fraction(), 0.05)

# THE WHOLE ACT LOOPS, a dark RETIRE beat after the last section. The phase advances BEFORE the
# show is decided: gating the clock on `_retiring` left the loop in the retire beat for ever. A
# section change re-points only the glow; a rebuild would restart the show.
func _advance_cascade(delta : float) -> void:
	_phase_t += delta
	var beat := _beat()
	if _phase_t >= beat * 2.0:
		_phase_t = 0.0
		if _retiring:
			_retiring = false
			_section = 0
		elif _section + 1 >= _sections.size():
			_retiring = true
		else:
			_section += 1
		_refresh_glows()
	_up = (not _retiring) and _phase_t < beat

## Between the last section and the first: every light retired and the dim down, the act's own ending.
var _retiring : bool = false

# DRIVES THE CARD RIG BY HAND: the idle rig does not autoplay, and every card here has its process
# off (its self-moving logic frees a card with no anchor). A frozen rig would also hide the glow's
# warp, which tracks the deformed silhouette.
func _advance_cards(delta : float) -> void:
	for cv : CardVisual in _slot_card.values():
		if not is_instance_valid(cv): continue
		var ap := cv.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap == null or not ap.has_animation(CardVisual.RIG_ANIM): continue
		if not ap.is_playing(): ap.play(CardVisual.RIG_ANIM)
		ap.advance(delta)

# --- the preview ----------------------------------------------------------------------------------

# ⚠ THE LIGHTLAYER DIES WITH ITS SUBVIEWPORT, so the eased show is carried across or a knob drag
# blinks it from black. Container and viewport sample NEAREST (a SubViewport defaults to LINEAR
# for all inside it and smeared the art), and it updates ALWAYS so the shader animates.
func _rebuild() -> void:
	_dirty = false
	_rebuild_count += 1
	var carry_show := -1.0
	var carry_dim := -1.0
	if is_instance_valid(_layer):
		carry_show = _layer._show
		carry_dim = _layer._dim
	for child : Node in get_children(): child.queue_free()
	_slot_card.clear()
	_glows.clear()
	var current := _current_scenario()
	_read_sections(current)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(screen_size)
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(container)

	_root = SubViewport.new()
	_root.size = screen_size
	_root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_root.transparent_bg = false
	container.add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = PaletteDB.color(_BACKDROP_ROLE)
	_root.add_child(backdrop)

	_board = Node2D.new()
	_root.add_child(_board)
	_build_board(current)

	_layer = LightLayer.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.style = spotlight_style
	_root.add_child(_layer)
	_layer.ensure_built()
	if carry_show >= 0.0:
		_layer._show = carry_show
		_layer._dim = carry_dim
		_layer.set_revealed(_up)
	_push_lights()

## Lays real `CardVisual`s out on the real board pitch, stacked as a column stacks in play; `_reposition` places them.
func _build_board(current : Dictionary) -> void:
	var cols : int = current.get("cols", 5)
	var depth : int = current.get("depth", 3)
	for c : int in cols:
		for d : int in depth:
			var cv := _new_card(c * 7 + d * 3)
			_board.add_child(cv)
			_pose(cv)
			_slot_card[Vector2i(c, d)] = cv
	_reposition()
	if glow: _attach_glows()

# THE GLOW IS BUILT THE WAY A HOST BUILDS ONE, an FxRequest into a real FxAttachment under `offset`,
# which carries the card's jump and bob. There is no FxGlow class yet; when one is written this call
# site moves to it, never a copy: two preloads of one shader are two Shader resources.
func _attach_glows() -> void:
	if glow_style == null: return
	for slot : Vector2i in _current_section():
		var cv : CardVisual = _slot_card.get(slot)
		if not is_instance_valid(cv): continue
		var fx := FxAttachment.new()
		fx.name = "Glow"
		fx.configure(CardVisual.CARD_SIZE, false, FxAttachment.Shape.RADII,
				FxAttachment.Half.WHOLE, true)
		cv.offset.add_child(fx)
		if not cv._rig_arms.is_empty(): fx.measure_outline(cv._rig_outline())
		var reqs : Array[FxRequest] = [
			FxRequest.make(&"glow", FxGlowStyle.GLOW_SHADER, glow_style, glow_style.reach),
		]
		fx.sync(reqs)
		_glows.append(cv)

# Re-points the glow at the current section without touching the board. `free()`, not
# `queue_free()`: a dying "Glow" child would collide with the new one's name for a frame.
func _refresh_glows() -> void:
	for cv : CardVisual in _glows:
		if not is_instance_valid(cv): continue
		var fx := cv.offset.get_node_or_null("Glow") as FxAttachment
		if fx: fx.free()
	_glows.clear()
	if glow: _attach_glows()

## Cards carrying a live glow, so their outlines can be re-tracked each frame.
var _glows : Array[CardVisual] = []

## How far each DEPTH has opened, 0..1. Eased, never assigned — see `_ease_separation`.
var _open : Dictionary[int, float] = {}

## Total extra height the open depths currently contribute, so the board stays centred while it grows.
func _open_total(depth : int, span : float) -> float:
	var total := 0.0
	for d : int in depth:
		var v : float = _open[d] if _open.has(d) else 0.0
		total += v * span
	return total

# EASES THE REVEAL EVERY FRAME over its fraction of the show's unit, moving the cards in place: a
# rebuild per frame would re-instantiate every card and restart the rig.
func _ease_separation(delta : float) -> void:
	var targets := _separated_depths()
	var span := maxf(settings.base_delay * maxf(settings.spotlight_reveal_fraction, 0.01), 0.01)
	var moved := false
	for d : int in _all_depths():
		var want : float = separation_amount if targets.has(d) else 0.0
		var now : float = _open[d] if _open.has(d) else 0.0
		if is_equal_approx(now, want): continue
		_open[d] = move_toward(now, want, delta / span)
		moved = true
	if moved: _reposition()

## Every depth the board has, so a row that is CLOSING eases rather than snapping shut.
func _all_depths() -> Array[int]:
	var out : Array[int] = []
	for slot : Vector2i in _slot_card:
		if not slot.y in out: out.append(slot.y)
	return out

## Moves the existing cards to match the eased `_open`, without rebuilding them.
func _reposition() -> void:
	var current := _current_scenario()
	var cols : int = current.get("cols", 5)
	var depth : int = current.get("depth", 3)
	var card := CardVisual.card_size_play
	var strip := float(CardVisual.card_separation_play_custom)
	var span := _open_span()
	var gap := PlayArea.board_separation_px(settings)
	var col_pitch := card.x + gap
	var row_pitch := strip + gap
	var board_w := float(cols) * col_pitch
	var board_h := float(depth) * row_pitch + _open_total(depth, span)
	var origin := Vector2(screen_size) * 0.5 - Vector2(board_w, board_h) * 0.5
	for slot : Vector2i in _slot_card:
		var cv : CardVisual = _slot_card[slot]
		if not is_instance_valid(cv): continue
		var extra := 0.0
		for above : int in slot.y:
			var v : float = _open[above] if _open.has(above) else 0.0
			extra += v * span
		cv.position = origin + Vector2(
				float(slot.x) * col_pitch + card.x * 0.5,
				gap + float(slot.y) * row_pitch + card.y * 0.5 + extra)

# RE-READS THE DEFORMED OUTLINE EVERY FRAME, as `CardVisual._track_fx_outline()` does: every card
# here has its process off, which disables that call, so the glow would stay on the build-time
# silhouette. The attachment early-outs when nothing moved.
func _track_glow_outlines() -> void:
	for cv : CardVisual in _glows:
		if not is_instance_valid(cv) or cv._rig_arms.is_empty(): continue
		var fx := cv.offset.get_node_or_null("Glow") as FxAttachment
		if fx: fx.track_outline(cv._rig_outline())

# EVERY DEPTH THE CURRENT SECTION LIGHTS - a column opens every row it passes through. A row that
# covers nothing does not open, as `PlayArea.row_open_extra` refuses it; on this full grid that is
# only the deepest.
func _separated_depths() -> Dictionary[int, bool]:
	var out : Dictionary[int, bool] = {}
	if not row_separation: return out
	var depth : int = _current_scenario().get("depth", 3)
	var deepest : int = depth - 1
	for s : Vector2i in _current_section():
		if s.y < deepest: out[s.y] = true
	return out

## A real card with real data, a TYPE modifier included as every dealt card has one, so the face under the circle is real.
func _new_card(seed_ : int) -> CardVisual:
	var cv := CardVisual.CARD_VISUAL.instantiate() as CardVisual
	cv.current_context = CardVisual.DisplayContext.PREVIEW
	var suits : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
	var suit : PipSuit = suits[seed_ % suits.size()].new()
	cv.data = CardData.new().with_type(TypePaper.new()) \
			.with_suit(suit) \
			.with_rank(PipRankNumeral.new().with_value((seed_ % 9) + 1))
	return cv

# POSED ONLY AFTER `add_child`: `_ready` turns processing back on, and the self-moving logic then
# frees any card with no anchor, leaving blank shots at exit 0. `visual` is @onready and
# `show_front` defaults off.
func _pose(cv : CardVisual) -> void:
	cv.set_process(false)
	cv.floating = false
	cv.show_front = true
	if cv.visual: cv.visual.visible = true

# --- sections and lights --------------------------------------------------------------------------

## Reads the scenario's sections; a single `lit` is stored as a cascade of one, so there is one code path.
func _read_sections(current : Dictionary) -> void:
	_sections = []
	var raw : Array = current.get("sections", [])
	if raw.is_empty():
		var lit : Array = current.get("lit", [])
		if not lit.is_empty(): raw = [lit]
	for entry : Variant in raw:
		var group : Array = entry
		var slots : Array[Vector2i] = []
		for pair_v : Variant in group:
			var pair : Array = pair_v
			var col : int = pair[0]
			var d : int = pair[1]
			slots.append(Vector2i(col, d))
		_sections.append(slots)
	if _section >= _sections.size(): _section = 0

func _current_section() -> Array[Vector2i]:
	if _sections.is_empty(): return [] as Array[Vector2i]
	var idx : int = clampi(_section, 0, _sections.size() - 1)
	var out : Array[Vector2i] = _sections[idx]
	return out

# Builds the light set as `SpotlightDirector` does, from the same `SpotlightOrigins` allocator and
# into the same layer: the origin rules live there, and a copy here could disagree invisibly. A
# light is full size in transit; its fade is the spawn/retire envelope only.
func _push_lights() -> void:
	if not is_instance_valid(_layer): return
	_sync_beams()
	var viewport := Rect2(Vector2.ZERO, Vector2(screen_size))
	var lights : Array[LightLayer.Light] = []
	for b : _TBeam in _beams:
		var centre := _beam_centre(b)
		var cv : CardVisual = _slot_card.get(b.slot)
		var scale := cv.spotlight_scale() if is_instance_valid(cv) else settings.card_scale
		var light := LightLayer.Light.new()
		light.centre = centre
		light.radius = _style().circle_radius * scale
		light.origin_width = _style().beam_width_at_origin * scale
		light.flare = _style().flare
		light.intensity = b.fade
		light.origin = SpotlightOrigins.edge_origin_for(centre, viewport.position.y,
				viewport.position.y + viewport.size.y, _origins.origin_of(b.origin_idx))
		lights.append(light)
	_layer.set_lights(lights, _scoring_now())

## Where a beam's circle is RIGHT NOW — its slot's card centre, or a point along its travel.
func _beam_centre(b: _TBeam) -> Vector2:
	var target := _slot_centre(b.slot)
	if b.t >= 1.0: return target
	return b.from.lerp(target, smoothstep(0.0, 1.0, b.t))

## A slot's card centre, or ZERO if that slot has no card built.
func _slot_centre(slot: Vector2i) -> Vector2:
	var cv : CardVisual = _slot_card.get(slot)
	return cv.spotlight_center() if is_instance_valid(cv) else Vector2.ZERO

# RE-MATCHES THE LIVE BEAMS to the lit section: a kept slot keeps its light, a light whose slot left
# travels to one that gained a slot (paired in x order, so travels never cross, and never from ZERO,
# a missing card), surplus lights go and surplus slots get new lights already aimed.
func _sync_beams() -> void:
	var wanted : Array[Vector2i] = ([] as Array[Vector2i]) if _retiring else _current_section()
	if wanted == _last_wanted: return
	_last_wanted = wanted.duplicate()
	if _beams.is_empty():
		_origins.begin(wanted.size(), float(screen_size.x), 0.0)

	var still : Dictionary[Vector2i, bool] = {}
	for s : Vector2i in wanted: still[s] = true
	var leftover : Array[_TBeam] = []
	var claimed : Dictionary[Vector2i, bool] = {}
	for b : _TBeam in _beams:
		if b.retiring: continue
		if still.has(b.slot):
			claimed[b.slot] = true
			continue
		leftover.append(b)
	var targets : Array[Vector2i] = []
	for s : Vector2i in wanted:
		if not claimed.has(s): targets.append(s)

	leftover.sort_custom(func(a: _TBeam, b: _TBeam) -> bool:
		return _beam_centre(a).x < _beam_centre(b).x)
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _slot_centre(a).x < _slot_centre(b).x)

	var pairs : int = mini(leftover.size(), targets.size())
	var src_x := PackedFloat32Array()
	for b : _TBeam in leftover: src_x.append(_beam_centre(b).x)
	var tgt_x := PackedFloat32Array()
	for slot : Vector2i in targets: tgt_x.append(_slot_centre(slot).x)
	var window := 0
	var tgt_window := 0
	if leftover.size() >= targets.size():
		window = SpotlightOrigins.nearest_window(src_x, tgt_x)
	else:
		tgt_window = SpotlightOrigins.nearest_window(tgt_x, src_x)
	for i : int in leftover.size():
		if i >= window and i < window + pairs: continue
		var dead : _TBeam = leftover[i]
		if dead.origin_idx >= 0: _origins.release(dead.origin_idx)
		_beams.erase(dead)
	for i : int in pairs:
		var b : _TBeam = leftover[window + i]
		var from := _beam_centre(b)
		b.slot = targets[tgt_window + i]
		b.retiring = false
		if from == Vector2.ZERO:
			b.t = 1.0
		else:
			b.from = from
			b.t = 0.0
	var fresh : Array[Vector2i] = []
	var centres : Array[Vector2] = []
	for i : int in targets.size():
		if i >= tgt_window and i < tgt_window + pairs: continue
		fresh.append(targets[i])
		centres.append(_slot_centre(targets[i]))
	var assigned := _origins.assign(centres)
	for i : int in fresh.size():
		var nb := _TBeam.new()
		nb.slot = fresh[i]
		nb.t = 1.0
		nb.fade = 0.0
		nb.origin_idx = assigned[i] if i < assigned.size() else -1
		_beams.append(nb)

## One frame of travel and fade, mirroring `SpotlightDirector._process`: every duration is a fraction of the show's unit.
func _advance_beams(delta: float) -> void:
	if _beams.is_empty(): return
	_origins.advance(0.0)
	var unit : float = settings.base_delay
	var travel := maxf(unit * settings.spotlight_travel_fraction, 0.0001)
	var spawn := maxf(unit * settings.spotlight_spawn_fraction, 0.0001)
	var leave := maxf(unit * settings.spotlight_retire_fraction, 0.0001)
	var done : Array[_TBeam] = []
	for b : _TBeam in _beams:
		if b.t < 1.0: b.t = minf(b.t + delta / travel, 1.0)
		if b.retiring:
			b.fade = maxf(b.fade - delta / leave, 0.0)
			if b.fade <= 0.0: done.append(b)
		elif b.fade < 1.0:
			b.fade = minf(b.fade + delta / spawn, 1.0)
	for b : _TBeam in done:
		if b.origin_idx >= 0: _origins.release(b.origin_idx)
		_beams.erase(b)

## The scoring dim, or the casual one for a solo activation cue: a full dim there would pulse dark on every card placed.
func _scoring_now() -> bool:
	var current := _current_scenario()
	if current.get("casual", false): return false
	return scoring

# --- scenarios as data ----------------------------------------------------------------------------

func _load_scenarios() -> void:
	var text := FileAccess.get_file_as_string(SCENARIOS_PATH)
	if text.is_empty():
		push_error("spotlight_tool: cannot read " + SCENARIOS_PATH)
		return
	var parsed : Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("spotlight_tool: %s is not a JSON object" % SCENARIOS_PATH)
		return
	var dict : Dictionary = parsed
	_scenarios = dict.get("scenarios", [])

func _current_scenario() -> Dictionary:
	if scenario < 0 or scenario >= _scenarios.size(): return {}
	var out : Dictionary = _scenarios[scenario]
	return out

## The scenario dropdown, built from the JSON so the list stays data the owner edits without code.
func _get_property_list() -> Array[Dictionary]:
	var names : Array[String] = []
	for s : Dictionary in _scenarios:
		names.append("%s %s" % [s.get("id", "?"), s.get("name", "")])
	if names.is_empty(): names.append("<none loaded>")
	return [{
		"name": "scenario",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(names),
	}]

# --- the agent's path in --------------------------------------------------------------------------

# THE TRACE runs a REAL act on a real `GameView` with `EventLog` recording, writing the log and a
# PNG at every transition: a behaviour question is never answered from the posed preview. The
# player's run save is parked first, since `new_run()` rewrites it, and restored before quit.
func _maybe_trace() -> void:
	add_child(_Watchdog.new())
	for child : Node in get_children():
		if not child is _Watchdog: child.queue_free()
	_layer = null
	await get_tree().process_frame
	set_process(false)
	EventLog.begin()
	_SAVE_GUARD.backup_real_save("spotlight_tool")
	var run := RunManager.new_run(TestDecks.seeded_deck(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	var view : GameView = preload("res://Levels/game_view.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	EventLog.event(EventLog.CH_ACT, "view_ready")
	var g : Game = view.game
	_trace_capture.call(view)
	await g.next()
	view.play_area.flush_rebuild()
	await get_tree().process_frame
	for step : Array in [[0, 0], [3, 1], [6, 3]]:
		var count : int = step[0]
		var per_col : int = step[1]
		EventLog.event(EventLog.CH_ACT, "SCENARIO", "place=%d per_col=%d" % [count, per_col])
		if count > 0:
			await _trace_place(view, count, per_col)
		await get_tree().process_frame
		await g.next()
	EventLog.event(EventLog.CH_ACT, "SCENARIOS done")
	var dir := EventLog.save("spotlight_trace")
	EventLog.end()
	_SAVE_GUARD.restore_real_save("spotlight_tool")
	print("=== SPOTLIGHT TRACE: %d events, %d shots ===" % [EventLog.count(), _shots])
	print("logs:  " + dir)
	print(EventLog.summary())
	get_tree().quit(0)

## Moves upper-zone cards onto the board through `Game.move_data_to_coord`, the drag's own path; a refused move is logged.
func _trace_place(view : GameView, count : int, per_col : int) -> void:
	var g : Game = view.game
	var placed := 0
	var col := 0
	for _i : int in count:
		var card : CardData = null
		for uc : ArrayCardData in g.state.upper_zone:
			if uc and not uc.datas.is_empty():
				card = uc.datas[uc.datas.size() - 1]
				break
		if card == null: break
		await g.move_data_to_coord(card, Vector3i(1, col, -1), 1, true)
		placed += 1
		if per_col > 0 and placed % per_col == 0: col += 1
	view.play_area.flush_rebuild()
	await get_tree().process_frame
	EventLog.event(EventLog.CH_BOARD, "placed",
			"placed=%d board=%d" % [placed, view.play_area.data_card.size()])

# SHOOTS EACH CAPTURE-WORTHY TRANSITION WHILE THE ACT RUNS, from a detached coroutine, the act
# being one long await; three frames after the event, which marks the START of an ease.
func _trace_capture(view : GameView) -> void:
	var from := 0
	while EventLog.enabled:
		await get_tree().process_frame
		var events : Array[EventLog.Event] = EventLog._events
		while from < events.size():
			var e : EventLog.Event = events[from]
			from += 1
			if StringName(e.what) in CAPTURE_ON:
				await _wait_frames(3)
				await _shoot_viewport(view.get_viewport(), e.what)

func _wait_frames(n : int) -> void:
	for _i : int in n: await get_tree().process_frame

func _shoot_viewport(vp : Viewport, tag : String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null: return
	_shots += 1
	img.save_png("%s%02d_trace_%s.png" % [SHOT_DIR, _shots, tag])

var _shots := 0

## The events worth a picture — the peak of each section's show.
const CAPTURE_ON : Array[StringName] = [&"dim_rising", &"reveal_faded", &"score_line"]

# Quits no matter what, independent of the scenario coroutine so a wedged await still ends the run.
# A PARSE ERROR runs nothing at all: bound that from outside with a timeout and a kill.
class _Watchdog extends Node:
	var seconds : float = 300.0
	var _start : int = 0
	func _ready() -> void:
		_start = Time.get_ticks_msec()
	func _process(_delta : float) -> void:
		if Time.get_ticks_msec() - _start >= int(seconds * 1000.0):
			push_error("spotlight_tool: watchdog fired after %.0fs — quitting" % seconds)
			get_tree().quit(2)

# VERIFIES EVERY SCENARIO BY WATCHING IT RUN, reporting what moved: sections lit, show flips, the
# dim, separation, travels, fades and cut-short envelopes. A still frame cannot tell a stuck
# cascade from a working one, so a scenario that changes nothing is SUSPECT.
func _maybe_verify() -> void:
	add_child(_Watchdog.new())
	var report : Array[String] = []
	for i : int in _scenarios.size():
		scenario = i
		var s := _current_scenario()
		play = true
		_retiring = false
		_section = 0
		_phase_t = 0.0
		_open.clear()
		_rebuild()
		var seen_sections : Dictionary[int, bool] = {}
		var show_flips := 0
		var travelled := false
		var faded := false
		var cut_travel := 0
		var cut_spawn := 0
		var peak_show := 0.0
		var full_frames := 0
		var rebuilds_at_start := _rebuild_count
		var peaks : Array[String] = []
		var last_section := _section
		var last_retiring := _retiring
		var last_up := _up
		var max_dim := 0.0
		var max_open := 0.0
		var retired := false
		var beats : int = (_sections.size() + 1) * 2
		var frames : int = int(ceilf(beats * _beat() * 60.0)) + 90
		for _f : int in mini(frames, 1800):
			await get_tree().process_frame
			seen_sections[_section] = true
			if _up != last_up:
				show_flips += 1
				last_up = _up
			if _retiring: retired = true
			max_dim = maxf(max_dim, _layer._dim)
			for d : float in _open.values(): max_open = maxf(max_open, d)
			for b : _TBeam in _beams:
				if b.t > 0.0 and b.t < 1.0: travelled = true
				if b.fade > 0.0 and b.fade < 1.0: faded = true
			if _up:
				peak_show = maxf(peak_show, _layer._show)
				if _layer._show >= 0.99: full_frames += 1
			if _section != last_section or _retiring != last_retiring:
				peaks.append("%.2f" % peak_show)
				peak_show = 0.0
				for b : _TBeam in _beams:
					if b.t > 0.0 and b.t < 1.0: cut_travel += 1
					elif not b.retiring and b.fade > 0.0 and b.fade < 1.0: cut_spawn += 1
				last_section = _section
				last_retiring = _retiring
		var sid : String = s.get("id", "?")
		var lit_now := _current_section().size()
		var suspect : Array[String] = []
		if _sections.size() > 1 and seen_sections.size() < _sections.size():
			suspect.append("only %d of %d sections took the light" % [seen_sections.size(), _sections.size()])
		if show_flips == 0: suspect.append("the show never changed state — no pulse at all")
		if _sections.size() > 1 and not travelled:
			suspect.append("no light ever TRAVELLED — the set is snapping between sections (chart E)")
		if not faded:
			suspect.append("no light ever faded — the spawn/retire envelopes are not running")
		if cut_travel > 0:
			suspect.append(("%d light(s) were STILL TRAVELLING when the section changed — " % cut_travel)
					+ "spotlight_travel_fraction (%.2f) is too long for the beat, which is "
					% settings.spotlight_travel_fraction
					+ "base_delay x spotlight_hold_fraction (%.2f)" % settings.spotlight_hold_fraction)
		if cut_spawn > 0:
			suspect.append("%d light(s) were still FADING IN when the section changed" % cut_spawn)
		if max_dim <= 0.0: suspect.append("THE DIM NEVER ROSE")
		if lit_now == 0 and not _retiring: suspect.append("nothing is lit")
		if not s.has("row_separation"):
			suspect.append("does not declare row_separation — it inherits, so it shows whatever the "
					+ "previously selected preset left behind")
		var sep : bool = s.get("row_separation", false)
		if sep and max_open <= 0.0: suspect.append("row_separation is on but nothing opened")
		if not sep and max_open > 0.0:
			suspect.append("row_separation is OFF but the board opened %.2f — the preset is not in "
					% max_open + "the state it claims")
		if _sections.size() > 1 and not retired:
			suspect.append("the act never reached its retire beat — the loop has no end")
		report.append("%-5s sections=%d/%d  flips=%d  dim=%.2f  open=%.2f  travel=%s fade=%s cut=%d/%d show_peaks=[%s] full=%d rebuilds=%d/%dframes  %s"
				% [sid, seen_sections.size(), _sections.size(), show_flips, max_dim, max_open,
					"Y" if travelled else "-", "Y" if faded else "-", cut_travel, cut_spawn,
					", ".join(peaks.slice(0, 6)), full_frames,
					_rebuild_count - rebuilds_at_start, mini(frames, 1800),
					("SUSPECT: " + "; ".join(suspect)) if suspect else "ok"])
		print("  " + report[report.size() - 1])
	var same_settings : bool = is_instance_valid(_layer) and _layer._settings() == settings
	print("
  settings seam: LightLayer reads the tool's own resource = %s%s"
			% [str(same_settings),
				"" if same_settings else "   <-- BUG: the layer is on a DIFFERENT clock"])
	print("\n======== SPOTLIGHT TOOL — SCENARIO VERIFY ========")
	var bad := 0
	for line : String in report:
		if "SUSPECT" in line: bad += 1
	print("  %d scenario(s), %d SUSPECT" % [report.size(), bad])
	for line : String in report: print("  " + line)
	get_tree().quit(bad)

# Holds each preset still and lets the dim and show finish easing before the shutter; the printed
# counts tell a blank frame (nothing built) from a dark one (built, nothing lit).
func _maybe_shoot_all() -> void:
	if not "--shoot-all" in OS.get_cmdline_user_args(): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	for i : int in _scenarios.size():
		scenario = i
		var s := _current_scenario()
		play = false
		revealed = true
		_apply_scenario_knobs()
		_rebuild()
		for _f : int in 90: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		print("  [%s] cards=%d lit=%d sections=%d viewport=%s"
				% [s.get("id", "?"), _slot_card.size(), _current_section().size(),
					_sections.size(), str(_root.size)])
		var img := _root.get_texture().get_image()
		if img == null: continue
		var path := "%s%02d_%s.png" % [SHOT_DIR, i, s.get("id", "?")]
		img.save_png(path)
	print("======== SPOTLIGHT TOOL: %d preset(s) shot ========" % _scenarios.size())
	print("  " + ProjectSettings.globalize_path(SHOT_DIR))
	get_tree().quit(0)

## The backdrop's palette role: a constant, as it teaches nothing about the spotlight.
const _BACKDROP_ROLE := 17

## Every inspector-visible value of every previewed resource, flattened, arrays and dictionaries copied.
func _fingerprint() -> Array:
	var out : Array = []
	for res : Resource in [settings, spotlight_style, glow_style]:
		if res == null:
			out.append(null)
			continue
		for prop : Dictionary in res.get_property_list():
			var usage : int = prop["usage"]
			if not (usage & PROPERTY_USAGE_EDITOR): continue
			var key : StringName = prop["name"]
			var value : Variant = res.get(key)
			if value is Array: value = (value as Array).duplicate(true)
			elif value is Dictionary: value = (value as Dictionary).duplicate(true)
			out.append(value)
	return out
