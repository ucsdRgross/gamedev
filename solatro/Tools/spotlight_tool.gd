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

const SCENARIOS_PATH := "res://Tools/spotlight_scenarios.json"
const SHOT_DIR := "user://logs/events/spotlight_tool/"

## ⚠ **THE CIRCLE'S RADIUS AND THE BEAM'S MOUTH COME FROM `FxSpotlightStyle`, NOT FROM A CONSTANT.**
## They were `const`s on `SpotlightDirector` until 2026-08-04, which is why the owner's *"tool not
## capturing some values when I change them, such as circle radius"* was correct: there was no knob,
## only a baked number in two places. `DESIGN.md` §16 lists both as style knobs and `Q85`'s answer
## asks for the radius to be adjustable in the same breath as giving the number.

## `PlayArea.separation`'s shipped value — the one number the board formula needs that lives on the
## node rather than on `CardVisual`.
const BOARD_SEPARATION := 4.0

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
	set(v): scenario = v; _section = 0; _phase_t = 0.0; _touch()

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
@export var settings : PlayerSettings = null:
	set(v): settings = v; _touch()
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
	# ⚠ RE-PUSHED EVERY FRAME, exactly as `SpotlightDirector._process` does it: a card that moves must
	# take its beam with it, and re-deriving is what makes that true by construction.
	_push_lights()

## The cascade clock. Each section gets: show UP for a hold beat, then DOWN for a beat, then the next
## section takes the light.
##
## ⚠ **THE LIGHTS ARE NOT FREED BETWEEN SECTIONS** — the set is REPLACED while the show is down, which
## is GAP-006's rule and what chart E's travel needs (*"no instant movements or spawning in and out"*).
## Watching this is the point of the cascade preset.
func _advance_cascade(delta : float) -> void:
	_phase_t += delta
	var beat := maxf(settings.base_delay * maxf(settings.spotlight_hold_fraction, 0.05), 0.05)
	# ⚠ **THE LOOP RUNS THE WHOLE ACT AND THEN RESETS, NOT JUST SECTION-TO-SECTION** (owner
	# 2026-08-04: *"should constantly loop the animation of the scenario happening like a snapshot of
	# it happening in game. should not be static since we need to see end to end"*). So after the LAST
	# section there is a RETIRE beat — every light released, the dim all the way down — before the
	# first section takes the light again. **That beat is part of the act** (`_release_spotlight`, S9)
	# and leaving it out made the loop read as an endless middle with no beginning or end.
	if _phase_t < beat:
		_up = true
	elif _phase_t < beat * 2.0:
		_up = false
	else:
		_phase_t = 0.0
		if _retiring:
			# The act is over; start the next pass.
			_retiring = false
			_section = 0
		elif _section + 1 >= _sections.size():
			_retiring = true
		else:
			_section += 1
		_up = not _retiring
		# ⚠ ALWAYS rebuilt on a section change, not only when separation is on: the GLOW marks the
		# ACTIVE cards, so it has to move with the section too. An earlier version rebuilt only for
		# separation and left the glow behind on the first section for the whole cascade.
		_dirty = true

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
	var card := CardVisual.card_size_play
	var strip := float(CardVisual.card_separation_play_custom)
	var col_pitch := card.x + BOARD_SEPARATION
	var row_pitch := strip + BOARD_SEPARATION
	# ⚠ **THE OPEN AMOUNT IS EASED, NOT SET** — owner 2026-08-04: *"row separation is not smooth. cards
	# jump to their new spot instantly."* The reveal is a TWEEN in the design (chart D6: *"PlayArea
	# grows each reveal row's gap to a full card, tweened over reveal_fraction"*), so a per-depth
	# `_open` value eases toward its target every frame and the LAYOUT reads that, rather than the
	# board being rebuilt at the final position.
	var board_w := float(cols) * col_pitch
	var board_h := float(depth) * row_pitch + _open_total(depth, card.y - strip)
	var origin := Vector2(screen_size) * 0.5 - Vector2(board_w, board_h) * 0.5

	for c : int in cols:
		for d : int in depth:
			# Everything BELOW an opened depth moves down by however far it has opened so far.
			var extra := 0.0
			for above : int in d:
				var v : float = _open[above] if _open.has(above) else 0.0
				extra += v * (card.y - strip)
			var pos := origin + Vector2(
					float(c) * col_pitch + card.x * 0.5,
					BOARD_SEPARATION + float(d) * row_pitch + card.y * 0.5 + extra)
			var cv := _new_card(c * 7 + d * 3)
			cv.position = pos
			_board.add_child(cv)
			_pose(cv)
			_slot_card[Vector2i(c, d)] = cv
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
func _reposition() -> void:
	var current := _current_scenario()
	var cols : int = current.get("cols", 5)
	var depth : int = current.get("depth", 3)
	var card := CardVisual.card_size_play
	var strip := float(CardVisual.card_separation_play_custom)
	var col_pitch := card.x + BOARD_SEPARATION
	var row_pitch := strip + BOARD_SEPARATION
	var board_w := float(cols) * col_pitch
	var board_h := float(depth) * row_pitch + _open_total(depth, card.y - strip)
	var origin := Vector2(screen_size) * 0.5 - Vector2(board_w, board_h) * 0.5
	for slot : Vector2i in _slot_card:
		var cv : CardVisual = _slot_card[slot]
		if not is_instance_valid(cv): continue
		var extra := 0.0
		for above : int in slot.y:
			var v : float = _open[above] if _open.has(above) else 0.0
			extra += v * (card.y - strip)
		cv.position = origin + Vector2(
				float(slot.x) * col_pitch + card.x * 0.5,
				BOARD_SEPARATION + float(slot.y) * row_pitch + card.y * 0.5 + extra)

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
	for s : Vector2i in _current_section(): out[s.y] = true
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
	var scale := settings.card_scale
	var viewport := Rect2(Vector2.ZERO, Vector2(screen_size))
	# The retire beat lights nothing — that is the act ending, and the dim falls with it.
	# ⚠ A typed empty, not `[]`: an untyped literal cannot be assigned to `Array[Vector2i]` and threw
	# every frame of the retire beat — invisible in a still, which is exactly why `--verify` exists.
	var slots : Array[Vector2i] = ([] as Array[Vector2i]) if _retiring else _current_section()
	var lights : Array[LightLayer.Light] = []
	_origins.begin(slots.size(), viewport.size.x, viewport.position.y)
	# ⚠ `assign()`, not `take()` in a loop — `Q111`=(a), chart E2 option A. The tool must use the
	# same rule as the director or it would show a beam layout the game never produces.
	var cards : Array[CardVisual] = []
	var centres : Array[Vector2] = []
	for slot : Vector2i in slots:
		var cv : CardVisual = _slot_card.get(slot)
		if not is_instance_valid(cv): continue
		cards.append(cv)
		# ⚠ `CardVisual.spotlight_center()` — the ART SQUARE (`Q85`). Using `cv.position` put the pool
		# high on the card and made it ambiguous which card in a stack was lit.
		centres.append(cv.spotlight_center())
	var assigned := _origins.assign(centres)
	for n : int in cards.size():
		var centre : Vector2 = centres[n]
		var light := LightLayer.Light.new()
		light.centre = centre
		# From the STYLE, so the tool and the shipped director read one value.
		light.radius = _style().circle_radius * scale
		light.origin_width = _style().beam_width_at_origin * scale
		light.flare = _style().flare
		light.origin = SpotlightOrigins.edge_origin_for(centre, viewport.position.y,
				viewport.position.y + viewport.size.y, _origins.origin_of(assigned[n]))
		lights.append(light)
	_layer.set_lights(lights, _scoring_now())

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
##     <godot> --path solatro res://Tools/spotlight_tool.tscn -- --shoot-all
##
## ⚠ **Shoots the SubViewport's own texture, not the window** — the viewport is the thing whose
## dimensions the beams were spread against.
## **THE TRACE MODE — the second half of ONE tool** (owner 2026-08-04: *"was expecting spotlight tool
## and trace to be one tool, not two"*).
##
##     <godot> --path solatro res://Tools/spotlight_tool.tscn -- --trace
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
	if not "--trace" in OS.get_cmdline_user_args(): return
	add_child(_Watchdog.new())
	# Tear the preview down: the trace stands up a whole real `GameView` and the two must not both
	# be on screen, nor both driving `LightLayer.editor_settings`.
	for child : Node in get_children():
		if not child is _Watchdog: child.queue_free()
	_layer = null
	await get_tree().process_frame
	set_process(false)
	EventLog.begin()
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
##     <godot> --path solatro res://Tools/spotlight_tool.tscn -- --verify
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
	if not "--verify" in OS.get_cmdline_user_args(): return
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
		var last_up := _up
		var max_dim := 0.0
		var max_open := 0.0
		var retired := false
		# Long enough for the whole loop plus a margin: every section gets two beats and the act adds
		# a retire beat, so the pass is (sections + 1) * 2 beats.
		var beats : int = (_sections.size() + 1) * 2
		var frames : int = int(ceilf(beats * settings.base_delay
				* maxf(settings.spotlight_hold_fraction, 0.05) * 60.0)) + 90
		for _f : int in mini(frames, 1800):
			await get_tree().process_frame
			seen_sections[_section] = true
			if _up != last_up:
				show_flips += 1
				last_up = _up
			if _retiring: retired = true
			max_dim = maxf(max_dim, _layer._dim)
			for d : float in _open.values(): max_open = maxf(max_open, d)
		var sid : String = s.get("id", "?")
		var lit_now := _current_section().size()
		var suspect : Array[String] = []
		if _sections.size() > 1 and seen_sections.size() < _sections.size():
			suspect.append("only %d of %d sections took the light" % [seen_sections.size(), _sections.size()])
		if show_flips == 0: suspect.append("the show never changed state — no pulse at all")
		if max_dim <= 0.0: suspect.append("THE DIM NEVER ROSE")
		if lit_now == 0 and not _retiring: suspect.append("nothing is lit")
		var sep : bool = s.get("row_separation", false)
		if sep and max_open <= 0.0: suspect.append("row_separation is on but nothing opened")
		if _sections.size() > 1 and not retired:
			suspect.append("the act never reached its retire beat — the loop has no end")
		report.append("%-5s sections=%d/%d  show_flips=%d  max_dim=%.2f  max_open=%.2f  %s"
				% [sid, seen_sections.size(), _sections.size(), show_flips, max_dim, max_open,
					("SUSPECT: " + "; ".join(suspect)) if suspect else "ok"])
		print("  " + report[report.size() - 1])
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
		# ⚠ **THE JSON FLAG IS AN OVERRIDE, NOT A DEFAULT.** It used to read `get("row_separation",
		# false)`, which forced separation OFF for every preset that did not mention it — so the S4
		# column shot showed an unseparated board while `--verify` reported `max_open=1.00`, and the two
		# instruments disagreed about the same scenario. Absent key now means "use the tool's setting",
		# which defaults ON.
		if s.has("row_separation"):
			var sep : bool = s["row_separation"]
			row_separation = sep
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
