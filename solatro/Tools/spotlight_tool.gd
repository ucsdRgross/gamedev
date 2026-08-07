@tool
class_name SpotlightTool
extends Node
## **THE SPOTLIGHT TUNING TOOL** — `PLAN.md` §5 / S18, design chart N, `Q173`–`Q182`.
##
## Open `Tools/spotlight_tool.tscn`, pick a **Scenario** in the inspector, drag the knobs, watch the
## real light shader react. The tool the owner asked for: *"add new editor similar to fx editor as
## effect in next column with parameters for tuning, with dummy card stack simulating exactly how it
## looks in game, and dummy screen size to dictate beam origins"* — and then, decisively:
## *"I would rather do all testing via the planned editor so dont ask me to check until it exists"*.
##
## ⚠ **SCOPE, OWNER 2026-08-04.** *"Just play area simulating effects is enough, dont need full
## game_view with hud"*, *"trigger different preset scenarios using editor tool options"*, and
## *"simulation should include realistic stacking system from play area and cascade scenario and
## mocked solo on active triggers and row separation"*. So: **no `Game`, no `GameView`, no HUD** —
## real `CardVisual`s on the real board geometry, the real `LightLayer`, the real shader, and the
## four things above simulated. That **supersedes `Q174`=(a) and `Q175`=(a)** (a real `PlayArea` and
## a real headless `Game`) — see `gaps/GAP-007.md`, resolved.
##
## ⚠ **WHAT THAT COSTS, STATED PLAINLY: THE CASCADE HERE IS POSED, NOT RUN.** Section membership, the
## activation sweep, hand re-evaluation and the real hold beat are all `Game`'s. This tool plays the
## SEQUENCE so the look can be judged; it does not derive it. **A behaviour question — "did the light
## travel when it should have", "was that the right section" — belongs to
## `Tools/spotlight_tool.tscn -- --trace` or the suite, both of which run the real act.** This tool answers
## "does it look right", and that is the only question it can answer.
##
## ⚠ **THE STACKING IS THE REAL FORMULA, NOT AN APPROXIMATION.** `PlayArea.slot_center_global` is
## pure uniform-pitch math, and this tool uses the same two constants it does: column pitch is
## `CardVisual.card_size_play.x + separation`, and ROW pitch is
## `CardVisual.card_separation_play_custom + separation` — the thin STRIP, which is why a covered card
## shows only its top sliver while its art hangs a full card below. That gap between strip and card is
## the whole reason a spotlight circle on a buried card cannot read, and it is what row separation
## exists to open.
##
## ⚠ **EVERYTHING RENDERS INSIDE A `SubViewport`, AND THAT IS NOT A DETAIL.** `light.gdshader` is
## SCREEN-SPACE: it resolves `SCREEN_UV` against whatever viewport it draws into, and a card's
## position is only "the screen pixel" because the game has one canvas layer and no camera offset.
## **The editor's own 2D view has a pan and a zoom**, so a light layer parented straight into an
## edited scene slides against its cards the moment anyone scrolls. The `SubViewport` restores the
## game's assumption exactly — and its size IS the brief's *"dummy screen size to dictate beam
## origins"* (`Q177`=a), for free rather than as a separate control.
##
## ⚠ **NO MOCKS WHERE IT COUNTS** (project rule 5): the real `CardVisual` scene with real `CardData`,
## the real `LightLayer`, the real `SpotlightOrigins` allocator, the real shader, the real board
## pitch. What IS simulated is named on the tin — the cascade's ORDER, the solo activation cue, and
## row separation — because the code that would produce them is `Game`'s (cascade), S15's (the cue)
## and unbuilt (S16, separation).
##
## ⚠ **THE GLOW IS IN, AND `Q83` MAKES IT THE MAIN EVENT** (*"the glow is most important. Beam and
## circle and dim are helper"*). It is hung on the cards the current section lights, through a real
## `FxAttachment` carrying the real `glow.gdshader`. ⚠ **There is still no `FxGlow` EFFECT CLASS** —
## `FxGlowStyle.GLOW_SHADER` is a stopgap preload, the way `FxFire` holds `FIRE_SHADER` — so this file
## builds the request itself. **When a class is written, MOVE this call site to it rather than copying
## it**: two preloads of one shader are two `Shader` resources, and a style applied through the wrong
## one silently misses every uniform the other declares.
##
## ⚠ Editor facts, each of which cost time elsewhere in this repo:
##  * **`LightLayer` is `@tool`, but its `_ready()` deliberately does nothing in the editor.**
##    Otherwise opening `game_view.tscn` would attach a `ShaderMaterial` to a node that scene OWNS,
##    and saving would write it in. This tool builds its own instance and calls `ensure_built()`.
##  * **The editor instantiates no autoloads**, so `SettingsManager` is absent. `CardVisual` and
##    `LightLayer` both fall back to an editor stand-in; this tool drives ONE shared instance so the
##    card geometry and the light cannot disagree about `card_scale`.
##  * **Every node built here is OWNERLESS and rebuilt from scratch.** An owned child would be SAVED
##    into `spotlight_tool.tscn` by the editor.
##  * **Pose a card only AFTER `add_child`.** `CardVisual._ready` turns its own `_process` back on,
##    and `delta_self_moving_logic` frees any non-play-area card with no `control_anchor` — so a card
##    parked before parenting deletes itself, leaving a blank frame at exit 0.

const SCENARIOS_PATH := "res://tools/spotlight_scenarios.json"
const SHOT_DIR := "user://logs/events/spotlight_tool/"
## The shared run-save park (`backup_real_save`/`restore_real_save`). Preloaded by PATH — the
## `SolatroTest` global name does not resolve from this @tool script's parse.
const _SAVE_GUARD := preload("res://Tests/Support/test_base.gd")

## ⚠ **THE CIRCLE'S RADIUS AND THE BEAM'S MOUTH COME FROM `FxSpotlightStyle`, NOT FROM A CONSTANT.**
## They were `const`s on `SpotlightDirector` until 2026-08-04, which is why the owner's *"tool not
## capturing some values when I change them, such as circle radius"* was correct: there was no knob,
## only a baked number in two places. `DESIGN.md` §16 lists both as style knobs and `Q85`'s answer
## asks for the radius to be adjustable in the same breath as giving the number.

## `PlayArea.separation`'s shipped BASE value — the one number the board formula needs that lives
## on the node rather than on `CardVisual`. ⚠ The node's getter multiplies it by `card_scale`, so
## every use here goes through `_board_sep()` or the tool's pitch is wrong at any other scale.
const BOARD_SEPARATION := 4.0

func _board_sep() -> float:
	return BOARD_SEPARATION * settings.card_scale

## The fully-open extra a revealed row adds — `PlayArea`'s own formula, so the tool obeys
## `spotlight_separation_mode` and cannot drift from the game's opening again.
func _open_span() -> float:
	return PlayArea.row_open_span(settings, _board_sep())

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

## **ONE LIVE LIGHT, WITH A LIFE OF ITS OWN — chart E's unit, mirroring `SpotlightDirector._Beam`.**
##
## ⚠ **THE TOOL USED TO REBUILD THE WHOLE LIGHT SET EVERY SECTION**, which is precisely the behaviour
## chart E was written to replace (*"no instant movements or spawning in and out"*). It therefore
## showed a SNAP where the game travels, and `spotlight_travel_fraction`, `spotlight_spawn_fraction`
## and `spotlight_retire_fraction` had no effect on screen at all — three knobs the owner could turn
## forever with nothing happening. Owner, 2026-08-05: *"I still want to see a scenario where forced
## spotlights move from one section to another, adding or losing spotlights if sections are mismatched
## in total cards"* — that is this class.
class _TBeam extends RefCounted:
	## The board slot it lights, or the last one it lit while retiring.
	var slot : Vector2i = Vector2i.ZERO
	## ⚠ AN INDEX, not a point — `SpotlightOrigins.advance()` moves off-screen lamps every frame.
	var origin_idx : int = -1
	## Where the travel started; meaningless once `t` is 1.
	var from : Vector2 = Vector2.ZERO
	## Travel progress 0..1. **1 means settled** — there is no separate "arrived" state to fall out of
	## step with.
	var t : float = 1.0
	## Spawn-in / retire-out, 0..1. Scales INTENSITY only, never size (`Q63`=a).
	var fade : float = 1.0
	var retiring : bool = false

## How many times the board has been torn down — a rebuild is meant to be RARE (a scenario or knob
## change), and one per frame is a whole class of bug that reads as the effect running sped up.
var _rebuild_count : int = 0
var _beams : Array[_TBeam] = []
## The slot set the beams were last matched against — the tool has no signal, so a CHANGE in this is
## what stands in for `spotlight_section_changed`.
var _last_wanted : Array[Vector2i] = []

## The sections this scenario walks, each a list of `Vector2i(col, depth)` slots. A single-section
## scenario is just a cascade of length one, so there is one code path rather than two.
var _sections : Array[Array] = []
var _section : int = 0
var _phase_t : float = 0.0
## Is the current section's show up? Driven by the cascade clock, or held by `revealed`.
var _up : bool = true

@export_group("Scenario")
## **THE PRESET SELECTOR** — owner: *"trigger different preset scenarios using editor tool options"*.
## The list is DATA (`Q182`), loaded from `spotlight_scenarios.json`, so adding a preset is editing
## that file. The dropdown is built from it by `_get_property_list`.
var scenario : int = 0:
	set(v):
		scenario = v
		_section = 0
		_phase_t = 0.0
		_apply_scenario_knobs()
		_touch()

## **PUSH THE SELECTED SCENARIO'S OWN KNOBS ONTO THE TOOL.**
##
## ⚠ **WITHOUT THIS THE PRESETS LIE, AND THEY DID.** `_rebuild()` reads `cols`, `depth`, `lit` and
## `sections` from the scenario, but `row_separation` was read from the INSPECTOR property alone — so
## picking a preset in the editor never changed it. `S2` is named *"STACKED — a buried row lit,
## separation OFF"* and showed it ON (the export defaults to `true`), and `S2b`'s *"compare directly
## against S2 — this is the before/after"* compared two identical boards. Eleven of thirteen presets
## were in that state, and which one you saw depended on what you had clicked before. Owner,
## 2026-08-05: *"half the scenarios dont do anything or dont do what they claim"*.
##
## ⚠ **EVERY SCENARIO NOW DECLARES `row_separation` EXPLICITLY** and `--verify` marks any that does
## not as SUSPECT. Absent-means-inherit was the previous attempt at this and it is what produced the
## lie; a preset has to state its own world or the tool cannot show it.
func _apply_scenario_knobs() -> void:
	var s := _current_scenario()
	if s.is_empty(): return
	# ⚠ Typed local first: `bool(Variant)` is a warning-treated-as-error in this project.
	var sep : bool = s.get("row_separation", false)
	row_separation = sep
	# ⚠ **`fx_intensity` IS A SCENARIO KNOB TOO, AND WITHOUT THIS `S14` WAS A DUPLICATE OF `S1`.** It
	# claims to be gate G2.4's accessibility floor — *"take fx_intensity to 0 and THE DIM MUST STILL
	# STAND"* — but the value lives on the settings resource, so the preset was byte-identical to `S1`
	# and did nothing until you went and moved a slider yourself. Measured 2026-08-05: same `cols`,
	# `depth`, `lit` and separation as `S1`.
	# ⚠ **ALWAYS ASSIGNED, never only-when-present** — the same stickiness that made `row_separation`
	# lie would otherwise leave the screen dark after you clicked away from `S14`.
	if settings:
		var fx : float = s.get("fx_intensity", 1.0)
		settings.fx_intensity = fx
		if is_instance_valid(_layer): _layer.restyle()

@export_group("Playback")
## Walk the scenario's sections in order, pulsing the show once per section — **the cascade, and the
## GAP-006 per-section beat, which is the first thing to judge.** ⚠ In a real act this beat is 1–3
## frames because `get_delay()` is already compressed; here it runs at `base_delay` uncompressed,
## which is `Q167`=(a)'s honest shape.
## ⚠ **DEFAULTS ON AND SHOULD USUALLY STAY ON** — owner 2026-08-04: *"should constantly loop the
## animation of the scenario happening like a snapshot of it happening in game. should not be static
## since we need to see end to end."* A still frame cannot show a pulse, a travel or a retire, which
## between them are most of what there is to judge. Turn it off only to hold one frame.
@export var play : bool = true:
	set(v): play = v; _phase_t = 0.0; _retiring = false; _touch()
## With `play` off, hold this section (0-based) so a still frame can be judged.
@export var section : int = 0:
	set(v): section = v; _section = v; _touch()
## With `play` off, is the show up? This is GAP-006's axis by hand — `LightLayer.set_revealed`.
@export var revealed : bool = true:
	set(v): revealed = v; _touch()
## Deep scoring dim, or `Q245`=(c)'s shallower casual one. A scenario may override it.
@export var scoring : bool = true:
	set(v): scoring = v; _touch()

@export_group("Board")
## **ROW SEPARATION — the S16 reveal, SIMULATED so it can be judged before it is built.** The lit
## row's strip opens to a full card height and everything below it moves down, which is what uncovers
## a buried card enough for a circle to land on its art square at all. ⚠ **This is the tool drawing
## the ANSWER, not the shipped behaviour**: `PlayArea` cannot do this yet (S16), and
## `slot_center_global` is pure uniform-pitch math that a per-row expansion breaks — which is exactly
## the problem S17 of the plan (gutters and prop anchors) has to solve.
## ⚠ **DEFAULTS ON, at the owner's direction 2026-08-04**: *"hard to judge current spotlight effect
## without row separation combined with it, since hard to tell which card circle it is on
## currently"*. Judging the light on a stack the reveal has not opened is judging the wrong picture.
@export var row_separation : bool = true:
	set(v): row_separation = v; _touch()
## How far the separated row opens, 0 = closed (the shipped strip) and 1 = a full card.
@export_range(0.0, 1.0, 0.05) var separation_amount : float = 1.0:
	set(v): separation_amount = v; _touch()

@export_group("Screen")
## The brief's *"dummy screen size to dictate beam origins"* (`Q177`=a). ⚠ **Origin spread is a
## function of viewport WIDTH and a beam only enters from the edge when its target is below the
## viewport BOTTOM (`Q117`), so both axes change the picture.**
@export var screen_size : Vector2i = Vector2i(1152, 648):
	set(v): screen_size = v; _touch()

@export_group("Glow")
## **THE GLOW ON AN ACTIVE CARD** — owner 2026-08-04: *"editor should include glowing effect on card
## as well for cards currently active. I believe previous part of plan had it implemented but havent
## seen it in action yet for adjustment."* They are right that it was built: S11 shipped `FxGlowStyle`
## and the three `.tres`, S12 shipped `Shaders/glow.gdshader`, and both were rendered and looked at in
## `fx_snapshot`. **What never existed is the request path putting it on a card in a real board
## context** — there is no `FxGlow` effect class yet, only `FxGlowStyle.GLOW_SHADER` as a stopgap
## preload. This tool builds the request directly, which is the first time the glow and the light
## layer have been on screen together.
## ⚠ **`Q83` MAKES THIS THE MAIN EVENT**: *"the glow is most important. Beam and circle and dim are
## helper"*. Gate **G2.2** is judged against glow + circle together, never the circle alone.
@export var glow : bool = true:
	set(v): glow = v; _touch()
## The card glow's style — the shipped `.tres`, edited live. ⚠ Its `circle_inner_alpha` is the knob
## `QR9`=(c) puts the disc's over-art alpha on, and `inner_alpha` is ask 2's knob (`Q216`).
@export var glow_style : FxGlowStyle = preload("res://Shaders/Styles/glow_card.tres"):
	set(v): glow_style = v; _touch()

@export_group("Tunables")
## **THE REAL RESOURCES, EDITED IN PLACE — NOT A COPY OF THEIR KNOBS.**
##
## ⚠ **THE TOOL USED TO MIRROR THESE AS ITS OWN `@export` FLOATS AND THAT WAS WRONG**, for the exact
## reason the owner asked about (2026-08-04: *"why is tunables not its own resource... it not being
## resource makes me question that"*). A mirrored knob list is a SECOND copy that goes stale the first
## time someone adds a knob — this repo's most repeated failure — and it made it impossible to tell
## whether tuning here changed anything anywhere else. **It does now, because these ARE the shipped
## resources**: edit them and the running game is what you edited.
##
##  * `settings` — TIMING and the accessibility floor. `DESIGN.md` §16's timing table, in
##    `PlayerSettings` because every duration is a fraction of `Game.get_delay()` (`Q167`=a) and
##    `dim_target` is player-facing (`Q168`=a).
##  * `spotlight_style` — the LIGHT's look. §16's *"Look"* group, on a resource *"beside the other FX
##    styles"* (§4g ruling 8). **`circle_radius` is in here**, which is why changing it does something
##    now and did nothing before.
##  * `glow_style` — the CARD GLOW's look, which `Q83` calls the most important part of the effect.
##
## ⚠ **POLLED, NOT LISTENED TO** — see `WATCH_SECS`. A custom resource does not announce its own edits.
## ⚠ **LEAVE THIS EMPTY AND IT USES THE SHARED, GLOBAL `PlayerSettings` — WHICH IS THE POINT.**
## Owner 2026-08-05: *"if playersettings is ever in an editor then it should be shared globally and be
## the one used in actual games, so i never need to duplicate settings across different contexts."*
## `spotlight_tool.tscn` used to carry its own embedded `SubResource` — a private duplicate that could
## not agree with the game, and whose stored values were partly **`null`** (`spotlight_reveal_fraction`,
## `travel`, `spawn`, `retire`) with `spotlight_separation_mode` pinned to 1. It has been deleted; the
## accessor below returns `FxAttachment.settings()`, which in the editor loads the same
## `user://settings.tres` the autoload loads at runtime and saves edits back to it.
## ⚠ Assigning something here is still allowed, but it re-creates exactly the divergence that made the
## played tool run on a different clock from its own preview.
@export var settings : PlayerSettings = null:
	set(v): settings = v; _touch()
	get:
		if settings: return settings
		return FxAttachment.settings()
@export var spotlight_style : FxSpotlightStyle = preload("res://Shaders/Styles/spotlight_default.tres"):
	set(v): spotlight_style = v; _touch()

func _ready() -> void:
	_load_scenarios()
	# ⚠ BEFORE any rebuild: `_build_board` and `_push_lights` both read the settings, and
	# `_maybe_shoot_all()` rebuilds from `_ready`, earlier than the first `_process`.
	_apply_settings()
	set_process(true)
	if Engine.is_editor_hint(): return
	# ⚠ TRACE FIRST: it tears the preview down and stands up a real `GameView`, so the two modes must
	# never both proceed.
	if "--trace" in OS.get_cmdline_user_args(): _maybe_trace()
	elif "--verify" in OS.get_cmdline_user_args(): _maybe_verify()
	else: _maybe_shoot_all()

## Point every consumer at the ONE `PlayerSettings` instance.
##
## ⚠ **`FxAttachment.settings()` IS THE EXISTING EDITOR STAND-IN and `CardVisual.settings()` already
## delegates to it**, so adopting that instance is what keeps `card_scale` consistent between the
## board's geometry and the beams. A separate settings object here would let the two drift, and the
## drift would look like every beam aiming slightly off its card.
func _apply_settings() -> void:
	if settings == null: settings = FxAttachment.settings()
	LightLayer.editor_settings = settings

## The light's style, never null — the layer holds the authoritative reference, so the tool reads it
## back rather than keeping a second one that could be assigned separately.
func _style() -> FxSpotlightStyle:
	if is_instance_valid(_layer) and _layer.style: return _layer.style
	return spotlight_style

## How often the tool re-reads the resources it is previewing, in seconds.
##
## ⚠ **THIS EXISTS BECAUSE A CUSTOM RESOURCE DOES NOT TELL ANYONE IT CHANGED**, and it is the direct
## cause of the owner's report *"tool not capturing some values when I change them, such as circle
## radius"*. `Resource.changed` is only emitted by `emit_changed()`, which built-in resources call
## from their setters and a script's `@export var` does NOT — so editing `circle_radius` on
## `spotlight_default.tres` moved nothing on screen. The `_touch()` setters above only fire when the
## export is ASSIGNED A DIFFERENT RESOURCE, which is not what tuning looks like.
##
## Polling rather than hand-written `emit_changed()` setters across three resources: one place, and it
## cannot go stale when a knob is added. `fx_editor` solves the same problem the same way and for the
## same reason.
const WATCH_SECS := 0.25

var _watch_wait := 0.0
## Every inspector-visible value of every previewed resource, as of the last push.
var _watched : Array = []

func _process(delta : float) -> void:
	_apply_settings()
	# Polled BEFORE the rebuild check, so an inspector edit lands on THIS frame rather than the next.
	_watch_wait += delta
	if _watch_wait >= WATCH_SECS:
		_watch_wait = 0.0
		var now := _fingerprint()
		if now != _watched:
			_watched = now
			# The light's look is a STYLE re-push, not a rebuild — the board has not changed.
			if is_instance_valid(_layer): _layer.restyle()
			# The glow lives on attachments hung off cards, so it does need the board back.
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
	# The reveal first (it MOVES cards), then the rig, then the outline that follows it, then the
	# lights that follow the cards — one order, so nothing in the frame reads last frame's positions.
	_ease_separation(delta)
	_advance_cards(delta)
	_track_glow_outlines()
	# ⚠ TRAVEL AND FADE FIRST, then push — the same order `SpotlightDirector._process` uses, so a
	# beam's position and its envelope come from the same frame rather than one behind.
	_advance_beams(delta)
	# ⚠ RE-PUSHED EVERY FRAME, exactly as `SpotlightDirector._process` does it: a card that moves must
	# take its beam with it, and re-deriving is what makes that true by construction.
	_push_lights()

## The cascade clock. Each section gets: show UP for a hold beat, then DOWN for a beat, then the next
## section takes the light.
##
## ⚠ **THE LIGHTS ARE NOT FREED BETWEEN SECTIONS** — the set is REPLACED while the show is down, which
## is GAP-006's rule and what chart E's travel needs (*"no instant movements or spawning in and out"*).
## Watching this is the point of the cascade preset.
## **ONE SECTION'S VISIBLE BEAT — LONG ENOUGH THAT NO ENVELOPE IS EVER CUT SHORT.**
##
## ⚠ **THE HOLD ALONE IS NOT ENOUGH, AND THAT IS WHY INSTANCES LOOKED INCONSISTENT.** Owner,
## 2026-08-05: *"I want to keep all instances of spawning spotlight effect to last same time
## regardless of movement or not."* The beat used to be `hold_fraction` alone, while a light's arrival
## takes `spawn_fraction` (a NEW light) or `travel_fraction` (a MOVING one) — three independent
## fractions of the same unit with no ordering between them. At the shipped defaults `travel` (0.5)
## already EQUALS `hold` (0.5), so a travelling light landed exactly as the show began to fade while a
## spawning one had been full since 0.3 — the same section reading differently depending on whether
## anything moved.
##
## Taking the MAX means every instance gets the same total on-screen time and none is truncated.
## ⚠ It does not equalise the RAMPS, and it must not: chart E forbids a travelling light from
## re-fading (*"no instant movements or spawning in and out"*), so a mover rides in at full intensity
## while a new light fades up. What is now equal is the DURATION, which is what was asked for.
func _beat() -> float:
	var unit : float = settings.base_delay
	# THE RISE: everything that must finish before the spotlight is fully up — the light's own arrival
	# (a NEW light fades over `spawn`, a MOVER slides over `travel`) and the show's ramp, which scales
	# every light's intensity and the dim with it.
	# ⚠ Through `PlayerSettings.spotlight_reveal_beat_fraction()` — the SAME accessor `Game`'s reveal
	# beat uses, so the tool cannot show a hold the game does not have.
	return maxf(unit * settings.spotlight_reveal_beat_fraction(), 0.05)

func _advance_cascade(delta : float) -> void:
	_phase_t += delta
	var beat := _beat()
	# ⚠ **THE LOOP RUNS THE WHOLE ACT AND THEN RESETS, NOT JUST SECTION-TO-SECTION** (owner
	# 2026-08-04: *"should constantly loop the animation of the scenario happening like a snapshot of
	# it happening in game. should not be static since we need to see end to end"*). So after the LAST
	# section there is a RETIRE beat — every light released, the dim all the way down — before the
	# first section takes the light again. **That beat is part of the act** (`_release_spotlight`, S9)
	# and leaving it out made the loop read as an endless middle with no beginning or end.
	# ⚠ **ADVANCE THE PHASE FIRST, THEN DECIDE THE SHOW — AND THE ORDER IS LOAD-BEARING.** A previous
	# fix put `if _retiring: _up = false` at the TOP of this chain, which made the `else` that CLEARS
	# `_retiring` unreachable: the loop entered the retire beat and stayed there forever (owner,
	# 2026-08-05: *"play no longer loops in editor"*). Gating the show is not the same as gating the
	# clock, and folding both into one if/elif chain conflated them.
	if _phase_t >= beat * 2.0:
		_phase_t = 0.0
		if _retiring:
			# The act is over; start the next pass.
			_retiring = false
			_section = 0
		elif _section + 1 >= _sections.size():
			_retiring = true
		else:
			_section += 1
		# ⚠ The GLOW moves with the section — but only the glow. This used to set `_dirty`, tearing
		# the whole SubViewport down every beat just to re-hang the attachments, which is what
		# restarted the show ("a blinked spotlight effect") until the eased values were carried
		# across. `_dirty` is for scenario/knob edits; a section change re-points the glow in place.
		_refresh_glows()
	# ⚠ **THE RETIRE BEAT STAYS DARK.** It used to fall through to `_phase_t < beat` and raise the show
	# a SECOND time while every beam was already fading out over `spotlight_retire_fraction` — a 0.5 s
	# ramp against a 0.3 s retire, which reads as a complete effect at double speed (owner: *"it
	# specifically looks like a sped up version, not a cut"*). The retire beat is the act ENDING (S9's
	# `_release_spotlight`); nothing lights during it.
	_up = (not _retiring) and _phase_t < beat

## Between the last section and the first: every light retired and the dim down, which is the act's
## own ending (S9's `_release_spotlight`) and the thing that makes the loop legible as a loop.
var _retiring : bool = false

## **DRIVE THE CARD RIG BY HAND — AUTOPLAY DOES NOT RUN IN THE EDITOR.**
##
## ⚠ Two separate reasons the cards would otherwise be frozen, and both had to be fixed for the loop
## to show anything: **autoplay is a runtime thing** (`fx_editor`'s header records the same finding),
## and this tool sets `set_process(false)` on every card because `delta_self_moving_logic` frees any
## non-play-area card with no `control_anchor`. So the rig is advanced here, per frame, per card.
## ⚠ **This is also what makes the glow's warp visible**: the halo tracks the DEFORMED silhouette, and
## with a frozen rig there is no deformation to track.
func _advance_cards(delta : float) -> void:
	for cv : CardVisual in _slot_card.values():
		if not is_instance_valid(cv): continue
		var ap := cv.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap == null or ap.autoplay.is_empty(): continue
		if not ap.is_playing(): ap.play(ap.autoplay)
		# `advance` ticks the animation without depending on the engine calling the player, which the
		# editor does not do for an instanced scene.
		ap.advance(delta)

# --- the preview ----------------------------------------------------------------------------------

func _rebuild() -> void:
	# ⚠ Cleared here, not only in `_process` — the shoot path calls `_rebuild()` directly, and a
	# `_dirty` left standing made `_process` rebuild the board again next frame, discarding the one
	# that had just been posed.
	_dirty = false
	_rebuild_count += 1
	# ⚠ **CARRY THE SHOW ACROSS THE TEARDOWN — THIS SWEEP FREES THE `LightLayer` ITSELF.** The layer
	# lives inside the `SubViewport` built below, so a rebuild destroys it and the replacement
	# starts at `_show = 0`, `_dim = 0`. Rebuilds are now RARE (scenario/knob edits — a section
	# change only calls `_refresh_glows()`), but a knob dragged mid-play would still blink the show
	# from black without this.
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
	# ⚠ **NEAREST, OR THE WHOLE PREVIEW IS BILINEAR-SMEARED WHEN THE CONTAINER DRAWS IT.** This is
	# half of the owner's report *"pixel art is not nearest so everything is blurry"*: the container
	# samples the viewport's texture like any other texture, so at any zoom other than exactly 1:1 the
	# finished frame is filtered.
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(container)

	_root = SubViewport.new()
	_root.size = screen_size
	# ⚠ **THE OTHER HALF, AND IT IS THE ANSWER TO "why is card_visual affected by this".** A
	# `SubViewport` carries its OWN `canvas_item_default_texture_filter`, which **defaults to LINEAR
	# and overrides the project's `rendering/textures/canvas_textures/default_texture_filter` for
	# every canvas item drawn inside it.** So the real `CardVisual`s — which are nearest-filtered
	# everywhere else in the game — were being smeared purely by virtue of living in this tool's
	# viewport. Nothing about the card was wrong; the container it was put in was.
	# ⚠ **It also explains the glow reading as a 1-pixel line**: `glow.gdshader` quantizes onto an FX
	# pixel grid, and bilinear sampling of a quantized field collapses the thin bright rim.
	_root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# ⚠ ALWAYS, not `UPDATE_WHEN_VISIBLE`: the shader animates (the beam's grain scrolls) and the dim
	# eases, and a viewport that only redraws on visibility change shows neither moving.
	_root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_root.transparent_bg = false
	container.add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A palette role, not a literal, so the tool cannot itself drift off-palette (§4i) — the one thing
	# in this feature allowed off-palette is the LIGHT.
	backdrop.color = PaletteDB.color(_BACKDROP_ROLE)
	_root.add_child(backdrop)

	_board = Node2D.new()
	_root.add_child(_board)
	_build_board(current)

	_layer = LightLayer.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The style BEFORE `ensure_built`, so the first material push already carries it.
	_layer.style = spotlight_style
	_root.add_child(_layer)
	# ⚠ EXPLICIT, because `_ready()` deliberately does nothing in the editor — see the header.
	_layer.ensure_built()
	# ⚠ **RESTORE THE EASED SHOW so a rebuild does not restart the animation** — see the note by the
	# teardown. Assigned before the first push, so the replacement layer's very first frame is the one
	# the old layer would have drawn.
	if carry_show >= 0.0:
		_layer._show = carry_show
		_layer._dim = carry_dim
		_layer.set_revealed(_up)
	_push_lights()

## Lay real `CardVisual`s out on the REAL board pitch, stacked exactly as a column stacks in play.
##
## The two constants are `PlayArea.slot_center_global`'s own:
##   column x = col * (card width + separation) + half a card
##   slot   y = separation + depth * (STRIP height + separation) + half a card
## The strip is `CardVisual.card_separation_play_custom` and is much shorter than a card, which is
## precisely why a covered card shows a sliver and its art hangs hidden below.
func _build_board(current : Dictionary) -> void:
	var cols : int = current.get("cols", 5)
	var depth : int = current.get("depth", 3)
	for c : int in cols:
		for d : int in depth:
			var cv := _new_card(c * 7 + d * 3)
			_board.add_child(cv)
			_pose(cv)
			_slot_card[Vector2i(c, d)] = cv
	# ONE copy of the layout formula — `_reposition` places what was just built, so a fresh board
	# and an easing one cannot disagree about where a slot is.
	_reposition()
	# The glow marks which cards are ACTIVE, so it is attached after every slot exists and only to
	# the ones this section lights.
	if glow: _attach_glows()

## Hang a real `FxAttachment` carrying the real glow shader on every card this section lights.
##
## ⚠ **BUILT THE WAY A HOST BUILDS ONE, not a private copy of the maths** — `FxRequest.make` with
## `FxGlowStyle.GLOW_SHADER`, into a real `FxAttachment`, pushed with `sync()`. That is the same path
## `FxFire.request` takes; the only difference is that fire has an effect CLASS to hold its preload
## and the glow does not yet. **When one is written, this call site should move to it rather than
## being duplicated** — two preloads of one shader are two `Shader` resources, and a style applied
## through the wrong one silently misses every uniform the other declares.
## ⚠ **`CardVisual` skips its own attachment in the editor** (deliberately — a tool owns the effects
## it previews), so there is no second glow to double up with here.
func _attach_glows() -> void:
	if glow_style == null: return
	for slot : Vector2i in _current_section():
		var cv : CardVisual = _slot_card.get(slot)
		if not is_instance_valid(cv): continue
		var fx := FxAttachment.new()
		fx.name = "Glow"
		# A card is a BOX whose silhouette carries its own outline; it does not rotate here.
		fx.configure(CardVisual.CARD_SIZE, false, FxAttachment.Shape.RADII,
				FxAttachment.Half.WHOLE, true)
		# ⚠ **UNDER `offset`, WHICH IS WHERE THE REAL CARD PUTS IT** (`card_visual.gd`:
		# `offset.add_child(fx)`). `Offset` carries the scoring jump and the bob, so an attachment
		# parented to the card ROOT instead would sit still while the card moved under it.
		cv.offset.add_child(fx)
		if not cv._rig_arms.is_empty(): fx.measure_outline(cv._rig_outline())
		var reqs : Array[FxRequest] = [
			FxRequest.make(&"glow", FxGlowStyle.GLOW_SHADER, glow_style, glow_style.reach),
		]
		fx.sync(reqs)
		_glows.append(cv)

## Move the glow to the CURRENT section without touching the board — a section change moves which
## cards are ACTIVE, nothing else (positions ease via `_reposition`), so this is all it costs.
## ⚠ `free()`, not `queue_free()`: a dying child still named "Glow" would collide with the new
## attachment's name and break `_track_glow_outlines`'s lookup for a frame.
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

## **EASE THE REVEAL, DO NOT SNAP IT** — chart D6 tweens the expansion over `reveal_fraction`, and
## `Q167`=(a) makes that a fraction of `get_delay()` rather than wall-clock.
##
## ⚠ **AND EASE IT EVERY FRAME, WHICH IS WHY THE BOARD IS REPOSITIONED RATHER THAN REBUILT.** The
## first build recomputed positions only inside `_rebuild()`, so a depth that "opened" did so in one
## step the instant the section changed — the owner's *"cards jump to their new spot instantly"*.
## Rebuilding per frame is not an option either: it re-instantiates every `CardVisual` and restarts
## the rig, so the reveal would stutter. Positions are moved in place instead.
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

## Every depth the current board has, so a row that is CLOSING still eases rather than snapping shut
## the moment it stops being lit.
func _all_depths() -> Array[int]:
	var out : Array[int] = []
	for slot : Vector2i in _slot_card:
		if not slot.y in out: out.append(slot.y)
	return out

## Move the existing cards to match `_open`, without rebuilding them.
## ⚠ **THE OPEN AMOUNT IS EASED, NOT SET** — owner 2026-08-04: *"row separation is not smooth. cards
## jump to their new spot instantly."* A per-depth `_open` value eases toward its target every frame
## (chart D6's tween over `reveal_fraction`) and this layout reads that.
func _reposition() -> void:
	var current := _current_scenario()
	var cols : int = current.get("cols", 5)
	var depth : int = current.get("depth", 3)
	var card := CardVisual.card_size_play
	var strip := float(CardVisual.card_separation_play_custom)
	var span := _open_span()
	var col_pitch := card.x + _board_sep()
	var row_pitch := strip + _board_sep()
	var board_w := float(cols) * col_pitch
	var board_h := float(depth) * row_pitch + _open_total(depth, span)
	var origin := Vector2(screen_size) * 0.5 - Vector2(board_w, board_h) * 0.5
	for slot : Vector2i in _slot_card:
		var cv : CardVisual = _slot_card[slot]
		if not is_instance_valid(cv): continue
		# Everything BELOW an opened depth moves down by however far it has opened so far.
		var extra := 0.0
		for above : int in slot.y:
			var v : float = _open[above] if _open.has(above) else 0.0
			extra += v * span
		cv.position = origin + Vector2(
				float(slot.x) * col_pitch + card.x * 0.5,
				_board_sep() + float(slot.y) * row_pitch + card.y * 0.5 + extra)

## **RE-READ THE DEFORMED OUTLINE EVERY FRAME, EXACTLY AS THE BOARD DOES** — `CardVisual`'s own
## `_track_fx_outline()`, which its comment describes as *"Every frame, because the rig's animation is
## on autoplay and a card is never actually at rest"*.
##
## ⚠ **THIS IS THE OWNER'S *"glow not following card animation warping"*, AND THE CAUSE IS THIS
## TOOL'S OWN.** A card here has `set_process(false)` — mandatory, or `delta_self_moving_logic` frees
## it for having no `control_anchor` — and `_track_fx_outline()` is what that disables. So the rig
## kept animating while the glow stood on the silhouette the card had at build time. Driving the same
## call from here restores the tracking without re-enabling the self-deleting process.
## ⚠ The attachment early-outs when nothing moved, so a settled card costs the walk and no upload.
func _track_glow_outlines() -> void:
	for cv : CardVisual in _glows:
		if not is_instance_valid(cv) or cv._rig_arms.is_empty(): continue
		var fx := cv.offset.get_node_or_null("Glow") as FxAttachment
		if fx: fx.track_outline(cv._rig_outline())

## **EVERY DEPTH THE CURRENT SECTION LIGHTS — a COLUMN OPENS THEM ALL.**
##
## ⚠ **THIS RETURNED -1 FOR A COLUMN AND THAT WAS MY INVENTION, NOT THE DESIGN'S** (owner 2026-08-04:
## *"not seeing any row separation when scoring columns"*). Chart D4 defines the reveal set as
## *"which board rows must expand to make every member of the spotlight set fully visible"* — for a
## column that is every row it passes through, not none. `Q46` gives expand-for-ROW and
## expand-for-COLUMN as separate booleans (`spotlight_expand_cols` exists precisely because columns
## expand), and `Q52` states the consequence outright: *"Column scoring on the longest column expands
## nearly every row at once"*. I had written the opposite.
func _separated_depths() -> Dictionary[int, bool]:
	var out : Dictionary[int, bool] = {}
	if not row_separation: return out
	# ⚠ **A ROW THAT COVERS NOTHING DOES NOT OPEN** — `PlayArea.row_open_extra`'s own guard, mirrored
	# here or the tool shows an opening the game refuses. The tool board is a full grid, so only the
	# deepest row can cover nothing.
	var depth : int = _current_scenario().get("depth", 3)
	var deepest : int = depth - 1
	for s : Vector2i in _current_section():
		if s.y < deepest: out[s.y] = true
	return out

## A real card, with real data behind it so the face under the circle is the one the player has to
## read (which is the whole of gate G2.2).
func _new_card(seed_ : int) -> CardVisual:
	var cv := CardVisual.CARD_VISUAL.instantiate() as CardVisual
	cv.current_context = CardVisual.DisplayContext.PREVIEW
	# Built the way `Deck._card` builds every card — a TYPE modifier included, because every real card
	# has one and a card without one is the fixture bug that hid five broken tests.
	var suits : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
	var suit : PipSuit = suits[seed_ % suits.size()].new()
	cv.data = CardData.new().with_type(TypePaper.new()) \
			.with_suit(suit) \
			.with_rank(PipRankNumeral.new().with_value((seed_ % 9) + 1))
	return cv

## Pose a card AFTER it has been parented. ⚠ **EVERY LINE HERE MUST RUN POST-`add_child`, AND DOING
## IT BEFORE IS WHAT PRODUCED ELEVEN BLANK PNGS AT EXIT 0.**
##  * **`set_process(false)` MUST COME AFTER `_ready`, WHICH TURNS PROCESSING BACK ON.**
##    `delta_self_moving_logic` then frees any non-play-area card that cannot find a `control_anchor`,
##    and a tool has none — so every card silently deleted itself, `_push_lights` found only freed
##    instances, no light was placed, and the frame showed nothing but the backdrop, at exit 0.
##  * **`visual` is `@onready`** and does not resolve until the card is in the tree.
##  * **`show_front` defaults to `false`**, normally driven by `basis3d` during the flip.
func _pose(cv : CardVisual) -> void:
	cv.set_process(false)
	cv.floating = false
	cv.show_front = true
	if cv.visual: cv.visual.visible = true

# --- sections and lights --------------------------------------------------------------------------

## Read the scenario's sections. A scenario may give `sections` (a cascade) or a single `lit`; the
## single case is stored as a cascade of length one so there is one code path.
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
			# Typed locals, never `int(...)` on a `Variant` — JSON hands back `Variant` and this
			# project treats the "constructor requires a subtype" warning as an ERROR.
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

## Build the light set the same way `SpotlightDirector` does, from the same allocator, and hand it to
## the same layer. ⚠ **This is the one piece a tool is tempted to re-implement and must not** — the
## origin rules (`Q113`, `Q250`, `Q251`) and `Q117`'s "a beam never points upward" live in
## `SpotlightOrigins`, and a second copy here could disagree with the shipped one invisibly.
func _push_lights() -> void:
	if not is_instance_valid(_layer): return
	_sync_beams()
	var scale := settings.card_scale
	var viewport := Rect2(Vector2.ZERO, Vector2(screen_size))
	var lights : Array[LightLayer.Light] = []
	for b : _TBeam in _beams:
		var centre := _beam_centre(b)
		var light := LightLayer.Light.new()
		light.centre = centre
		# From the STYLE, so the tool and the shipped director read one value.
		light.radius = _style().circle_radius * scale
		light.origin_width = _style().beam_width_at_origin * scale
		light.flare = _style().flare
		# ⚠ **`Q63`=(a): FULL SIZE IN TRANSIT.** The fade is the spawn/retire envelope ONLY — a
		# travelling light does not dim, because a real followspot does not.
		light.intensity = b.fade
		light.origin = SpotlightOrigins.edge_origin_for(centre, viewport.position.y,
				viewport.position.y + viewport.size.y, _origins.origin_of(b.origin_idx))
		lights.append(light)
	_layer.set_lights(lights, _scoring_now())

## Where a beam's circle is RIGHT NOW — its slot's art square, or a point along its travel.
func _beam_centre(b: _TBeam) -> Vector2:
	var target := _slot_centre(b.slot)
	if b.t >= 1.0: return target
	# Smoothstep so the light accelerates off its old card and settles onto the new one, which is what
	# "no instant movements" is asking for.
	return b.from.lerp(target, smoothstep(0.0, 1.0, b.t))

## A slot's art-square centre (`Q85`), or ZERO if that slot has no card built.
func _slot_centre(slot: Vector2i) -> Vector2:
	var cv : CardVisual = _slot_card.get(slot)
	return cv.spotlight_center() if is_instance_valid(cv) else Vector2.ZERO

## **CHART E, RUN RATHER THAN POSED.** Re-match the live beams against the section that is lit now:
## a slot in both keeps its light and does not move (E2), a light whose slot left TRAVELS to a slot
## that gained one (E9), surplus lights RETIRE in place (E3) and surplus slots get NEW lights that
## fade in already aimed (E4, `Q65`=a).
##
## ⚠ **THIS IS WHAT MAKES A MISMATCHED CASCADE LEGIBLE**: sections of 3 → 5 → 2 travel three, spawn
## two, then retire three, which is exactly the case the owner asked to see.
func _sync_beams() -> void:
	var wanted : Array[Vector2i] = ([] as Array[Vector2i]) if _retiring else _current_section()
	if wanted == _last_wanted: return
	_last_wanted = wanted.duplicate()
	# ⚠ **`begin()` ONLY WHEN NOTHING IS LIT** — it rebuilds the origin array and clears the taken-set,
	# so calling it per section would re-point every live beam at somebody else's lamp. The old rebuild
	# could call it every section only because it threw all the lights away each time.
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

	# E2's assignment — sort both by x and pair in order; pairing two sorted sequences inverts nothing,
	# which is the property that stops the travels crossing.
	leftover.sort_custom(func(a: _TBeam, b: _TBeam) -> bool:
		return _beam_centre(a).x < _beam_centre(b).x)
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _slot_centre(a).x < _slot_centre(b).x)

	var pairs : int = mini(leftover.size(), targets.size())
	# ⚠ Same rule as the director: with fewer targets, WHICH lights survive is chosen by proximity via
	# `SpotlightOrigins.nearest_window`, not by keeping the leftmost `pairs`.
	var src_x := PackedFloat32Array()
	for b : _TBeam in leftover: src_x.append(_beam_centre(b).x)
	var tgt_x := PackedFloat32Array()
	for slot : Vector2i in targets: tgt_x.append(_slot_centre(slot).x)
	# ⚠ Same both-sided rule as the director — see its note.
	var window := 0
	var tgt_window := 0
	if leftover.size() >= targets.size():
		window = SpotlightOrigins.nearest_window(src_x, tgt_x)
	else:
		tgt_window = SpotlightOrigins.nearest_window(tgt_x, src_x)
	# ⚠ **SURPLUS LIGHTS ARE RELEASED, NOT LEFT FADING** — a retiring beam rides `_show`, so the next
	# section's rise re-lights it before its own fade finishes. See the director's note.
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
		# ⚠ **NEVER TRAVEL FROM (0,0) — THAT IS THE TOP-LEFT OF THE SCREEN, NOT A BOARD POSITION.**
		# `_slot_centre()` returns ZERO while a card is missing — a SCENARIO change rebuilds the
		# board, leaving live beams pointing at slots the new board may not have — so a beam
		# re-matched on that frame took ZERO as its start and slid in from off-board. Owner,
		# 2026-08-05: *"seeing some spotlights flying into place from outside board now which should
		# never happen vs spawning in place"*. With no known origin the honest move is `Q65`=(a)'s:
		# appear ALREADY AIMED rather than invent a path.
		if from == Vector2.ZERO:
			b.t = 1.0
		else:
			b.from = from
			b.t = 0.0
	# E4 — surplus targets get NEW lights. ⚠ `assign()` for the batch, never `take()` in a loop:
	# GAP-008, and the same defect that made the GAME cross its beams until 2026-08-05.
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

## One frame of travel and fade. Mirrors `SpotlightDirector._process` — every duration is a FRACTION
## of the show's unit (`Q167`=a), which is what makes `spotlight_travel_fraction`,
## `spotlight_spawn_fraction` and `spotlight_retire_fraction` mean something in this tool at last.
func _advance_beams(delta: float) -> void:
	if _beams.is_empty(): return
	_origins.advance(0.0)
	var unit : float = settings.base_delay
	var travel := maxf(unit * settings.spotlight_travel_fraction, 0.0001)
	var spawn := maxf(unit * settings.spotlight_spawn_fraction, 0.0001)
	var leave := maxf(unit * settings.spotlight_retire_fraction, 0.0001)
	var done : Array[_TBeam] = []
	for b : _TBeam in _beams:
		# `Q64`=(a): every travelling light advances on the SAME frame, not staggered.
		if b.t < 1.0: b.t = minf(b.t + delta / travel, 1.0)
		if b.retiring:
			b.fade = maxf(b.fade - delta / leave, 0.0)
			if b.fade <= 0.0: done.append(b)
		elif b.fade < 1.0:
			b.fade = minf(b.fade + delta / spawn, 1.0)
	for b : _TBeam in done:
		if b.origin_idx >= 0: _origins.release(b.origin_idx)
		_beams.erase(b)

## Scoring depth or `Q245`=(c)'s casual one. ⚠ **A SOLO ACTIVATION CUE IS NOT SCORING** — chart T's
## momentary spotlight fires whenever a card becomes active in ordinary play, and `Q245`'s own
## scrutiny note is that a full-depth dim there *"means the screen pulses dark on every single card
## you place"*. A scenario marks itself with `"casual": true`; this is the mocked solo trigger the
## owner asked for, and the shallower dim is the whole thing it is there to show.
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

## ⚠ **THE DROPDOWN IS BUILT FROM THE JSON, NOT FROM AN `@export_enum`.** An `@export_enum` needs its
## members at parse time, which would put the scenario list back into code and break `Q182` — the
## list is data precisely so the owner can add to it without an agent.
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

## `Q176`=(a)'s *"runnable so an agent can screenshot it without opening the editor"*, and `Q181`=(a)'s
## *"the tool is also the source of reviewable snapshots"*.
##
##     <godot> --path solatro res://tools/spotlight_tool.tscn -- --shoot-all
##
## ⚠ **Shoots the SubViewport's own texture, not the window** — the viewport is the thing whose
## dimensions the beams were spread against.
## **THE TRACE MODE — the second half of ONE tool** (owner 2026-08-04: *"was expecting spotlight tool
## and trace to be one tool, not two"*).
##
##     <godot> --path solatro res://tools/spotlight_tool.tscn -- --trace
##
## Runs a REAL act on a REAL `GameView` with `EventLog` recording, then writes the log, the by-frame
## view, and a PNG at every transition. This is what `Tools/spotlight_tool.tscn -- --trace` used to be, folded
## in — same seeded deck, same three scenarios, same output.
##
## ⚠ **THE TWO MODES ANSWER DIFFERENT QUESTIONS AND THAT IS WHY BOTH EXIST IN ONE FILE.**
##   * **preview** (the `@tool` inspector, and `--shoot-all`) — *does it LOOK right.* Posed, no
##     `Game`, every knob live.
##   * **trace** (`--trace`) — *did it BEHAVE right.* A real cascade, real section membership, the
##     real hold beat, and a log to read afterwards. **Nothing here is posed, so nothing here can
##     flatter the implementation.**
## ⚠ **A behaviour question must never be answered from the preview**, which draws what it is told.
## The trace is the instrument that can disagree with the code.
func _maybe_trace() -> void:
	add_child(_Watchdog.new())
	# Tear the preview down: the trace stands up a whole real `GameView` and the two must not both
	# be on screen, nor both driving `LightLayer.editor_settings`.
	for child : Node in get_children():
		if not child is _Watchdog: child.queue_free()
	_layer = null
	await get_tree().process_frame
	set_process(false)
	EventLog.begin()
	# ⚠ PARK THE PLAYER'S SAVE FIRST — `new_run()` clears and rewrites `user://run_save/run.tres`,
	# and the trace's Game keeps saving over it on every submit. Restored before quit below.
	_SAVE_GUARD.backup_real_save()
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
	# ⚠ **SCENARIO 1 IS THE EMPTY BOARD AND IT IS A REAL SCENARIO, NOT A BLOCKER.** Submit fires
	# whenever the button is pressed regardless of what is on the board, so "submit with nothing
	# placed" is a case the spotlight has to survive: an act that scores nothing must light nothing
	# and must leave the dim down.
	for step : Array in [[0, 0], [3, 1], [6, 3]]:
		var count : int = step[0]
		var per_col : int = step[1]
		EventLog.event(EventLog.CH_ACT, "SCENARIO", "place=%d per_col=%d" % [count, per_col])
		if count > 0:
			await _trace_place(view, count, per_col)
		EventLog.event(EventLog.CH_ACT, "submit_begin")
		await g.submit()
		EventLog.event(EventLog.CH_ACT, "submit_end")
		await get_tree().process_frame
		await g.next()
	EventLog.event(EventLog.CH_ACT, "SCENARIOS done")
	var dir := EventLog.save("spotlight_trace")
	EventLog.end()
	_SAVE_GUARD.restore_real_save()
	print("=== SPOTLIGHT TRACE: %d events, %d shots ===" % [EventLog.count(), _shots])
	print("logs:  " + dir)
	print(EventLog.summary())
	get_tree().quit(0)

## Move cards from the upper zone onto the lower board through `Game.move_data_to_coord` — the same
## path a drag takes, so the board that results is one the game could actually reach.
## ⚠ A refused move is INFORMATION, not a failure: it is logged and the run continues.
func _trace_place(view : GameView, count : int, per_col : int) -> void:
	var g : Game = view.game
	var placed := 0
	var col := 0
	for _i : int in count:
		var card : CardData = null
		# ⚠ THERE IS NO `GameData.hand` — the "hand" is the UPPER zone, and playing a card means
		# moving it from an upper column to a lower one.
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

## Shoot a frame at each capture-worthy transition WHILE the act runs.
## ⚠ `submit()` is one long `await`, so nothing else gets a turn unless something watches from a
## PARALLEL coroutine. `Callable.call()` starts this detached; `await` would block until it finished
## (it never does) and a bare call will not compile.
func _trace_capture(view : GameView) -> void:
	var from := 0
	while EventLog.enabled:
		await get_tree().process_frame
		var events : Array[EventLog.Event] = EventLog._events
		while from < events.size():
			var e : EventLog.Event = events[from]
			from += 1
			if StringName(e.what) in CAPTURE_ON:
				# Three frames after the event, never on it: the event marks the START of an ease, so
				# a shot on that frame catches the dim at zero.
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

## Quits no matter what, so the window cannot outlive an unattended run. Independent of the scenario
## coroutine precisely so a wedged `await` in there still ends the process.
## ⚠ **Neither this nor the self-quit saves a PARSE ERROR** — then nothing runs at all and the window
## sits blank forever. That can only be bounded from OUTSIDE: always launch with `WaitForExit(<ms>)`
## and kill the process if it outlives it.
class _Watchdog extends Node:
	var seconds : float = 300.0
	var _start : int = 0
	func _ready() -> void:
		_start = Time.get_ticks_msec()
	func _process(_delta : float) -> void:
		if Time.get_ticks_msec() - _start >= int(seconds * 1000.0):
			push_error("spotlight_tool: watchdog fired after %.0fs — quitting" % seconds)
			get_tree().quit(2)

## **VERIFY EVERY SCENARIO BY WATCHING IT RUN, NOT BY LOOKING AT ONE FRAME OF IT.**
##
##     <godot> --path solatro res://tools/spotlight_tool.tscn -- --verify
##
## ⚠ **THIS EXISTS BECAUSE `--shoot-all` COULD NOT SEE A BROKEN SCENARIO** (owner 2026-08-04: *"some
## of the scenarios appear to be broken, such as solo activation, where nothing happens"*, *"cascade
## scoring scenarios has not actual cascade scoring"*). A still frame with `play = false` shows one
## posed section, so a cascade that never advances and a cascade that advances correctly produce the
## SAME picture — and every preset "passed". This runs each one with `play` ON for several seconds
## and reports what actually moved: how many distinct sections took the light, how many show
## transitions happened, whether the dim ever rose, and whether any depth separated.
##
## **A scenario that changes nothing over its whole loop is reported as SUSPECT**, which is the check
## `--shoot-all` structurally could not make.
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
		# Long enough for the whole loop plus a margin: every section gets two beats and the act adds
		# a retire beat, so the pass is (sections + 1) * 2 beats.
		var beats : int = (_sections.size() + 1) * 2
		# ⚠ Through `_beat()`, so the sampler covers the SAME beat the cascade runs — a shorter
		# estimate would stop mid-act and report sections that never took the light.
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
			# ⚠ **DID A LIGHT ACTUALLY MOVE, AND DID ANY FADE?** Section counts and dim depth cannot
			# tell a TRAVEL from a SNAP — both end with the right lights in the right places, and that
			# blindness is exactly how the tool shipped rebuilding its set every section while
			# `--verify` reported every scenario `ok`. A beam mid-travel has `0 < t < 1`; a beam mid
			# envelope has `0 < fade < 1`. Sampling for either is the seam check that was missing.
			for b : _TBeam in _beams:
				if b.t > 0.0 and b.t < 1.0: travelled = true
				if b.fade > 0.0 and b.fade < 1.0: faded = true
			# ⚠ **WAS A LIGHT STILL MOVING WHEN ITS SECTION ENDED?** Owner, 2026-08-05: *"timing of
			# spotlights is not always consistent like its ending early"*. The cascade's beat and the
			# envelopes are INDEPENDENT fractions of the same unit and nothing enforces an ordering —
			# at the shipped defaults `spotlight_travel_fraction` (0.5) EQUALS `spotlight_hold_fraction`
			# (0.5), so a travelling light lands exactly as the show begins to fade, and any travel
			# longer than the hold is cut off in flight. That is a real tuning cliff, not a wobble.
			# ⚠ **WHAT DID THE SHOW ACTUALLY REACH BEFORE ITS BEAT ENDED?** Owner: *"next one always
			# ends halfway into spawning, so dimness and brightness only reaches halfway"*. `max_dim`
			# over the whole run hides this — the FIRST section has slack and later ones may not.
			if _up:
				peak_show = maxf(peak_show, _layer._show)
				# ⚠ **FRAMES AT FULL is the number that was silently zero.** A peak of 0.97 and a peak
				# held for half a second look identical in `show_peaks`; only dwell time tells them
				# apart, and dwell is what the owner was missing.
				if _layer._show >= 0.99: full_frames += 1
			if _section != last_section or _retiring != last_retiring:
				peaks.append("%.2f" % peak_show)
				peak_show = 0.0
				# ⚠ **`> 0.0` MATTERS: a beam created on THIS very frame has `t`/`fade` at exactly 0
				# and has not been truncated — it has not started.** Counting those made the first
				# version report all 14 presets SUSPECT including single-section ones, where nothing
				# can be cut off. Only a beam that had STARTED and not finished is a truncation.
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
		# ⚠ A MULTI-SECTION preset that never travels is a REBUILD wearing a cascade's clothes.
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
		# ⚠ **A SCENARIO THAT DOES NOT DECLARE ITS SEPARATION IS SUSPECT — that omission is what made
		# half the presets lie.** Absent used to mean "keep the tool's current setting", which defaults
		# ON, so `S2` (named *"separation OFF"*) showed it ON and `S2b`'s *"compare directly against
		# S2"* compared two identical boards. Eleven of thirteen presets were in that state and what
		# you saw depended on which preset you had clicked before. Owner, 2026-08-05: *"half the
		# scenarios dont do anything or dont do what they claim"*.
		if not s.has("row_separation"):
			suspect.append("does not declare row_separation — it inherits, so it shows whatever the "
					+ "previously selected preset left behind")
		var sep : bool = s.get("row_separation", false)
		if sep and max_open <= 0.0: suspect.append("row_separation is on but nothing opened")
		# ⚠ And the other direction, which nothing checked: a preset that declares separation OFF but
		# opens anyway is the same disagreement seen from the other side.
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
	# ⚠ **THE SEAM THAT BROKE WHEN THE TOOL WAS PLAYED RATHER THAN PREVIEWED.** `LightLayer` used to
	# consult `editor_settings` ONLY under `Engine.is_editor_hint()`, so a played tool scene read the
	# player's saved `settings.tres` while the tool's own clock read its embedded `SubResource` — two
	# instances, two clocks, and the show was cut off part-way up. Values alone cannot catch it (both
	# resources hold the same defaults until one is tuned), so this asserts IDENTITY.
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

func _maybe_shoot_all() -> void:
	if not "--shoot-all" in OS.get_cmdline_user_args(): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	for i : int in _scenarios.size():
		scenario = i
		var s := _current_scenario()
		# Held, not played: a still of a cascade mid-fade is a picture of nothing in particular.
		play = false
		revealed = true
		# ⚠ ONE PATH for the scenario's knobs — the shoot loop and the inspector must not apply them
		# differently, which is how the shot and `--verify` came to disagree about the same preset.
		_apply_scenario_knobs()
		_rebuild()
		# Let the dim and the show finish easing before the shutter: both are `move_toward` over a
		# fraction of `base_delay`, so a shot on the rebuild frame catches them at zero.
		for _f : int in 90: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		# ⚠ The counts, every time. A blank frame at exit 0 is this tool's characteristic failure —
		# it happened twice while building it — and `cards=N lit=M` tells a blank picture ("nothing
		# was built") apart from a dark one ("built, but nothing is lit").
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

## The backdrop's palette role — a constant rather than a knob, because it cannot teach anyone
## anything about the spotlight.
const _BACKDROP_ROLE := 17

## Every inspector-visible value of every resource this preview reads, flattened into one array. Two
## of these compare unequal exactly when something the owner edited would change what is on screen.
##
## `PROPERTY_USAGE_EDITOR` is the filter, which is the same thing as "is in the inspector": it keeps
## plain script vars out, and those include cache fields a poll would otherwise see change every time.
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
			# ⚠ COPY THE REFERENCE TYPES. `Array` and `Dictionary` are references in GDScript, so
			# storing one stores a WINDOW onto the live value — an entry edited in place then compares
			# equal to itself for ever. `fx_editor` learned this the hard way: the fire ramp was the one
			# thing its watch could not see.
			if value is Array: value = (value as Array).duplicate(true)
			elif value is Dictionary: value = (value as Dictionary).duplicate(true)
			out.append(value)
	return out
