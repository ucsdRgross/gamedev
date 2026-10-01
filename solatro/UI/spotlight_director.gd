class_name SpotlightDirector
extends Node
# THE WIRE between three objects that each answer one question: `CardEnvironment` says WHO is lit,
# `SpotlightOrigins` WHERE the lamp is, `LightLayer` WHAT a lit pixel looks like. Only this node
# knows a card exists, which is why it is the only one that needs a `PlayArea`.

# ⚠ THE DIM IS A FUNCTION OF WHAT IS LIT, NOT OF THE ACT: there is no "start the dim" here, and an
# empty light set retires it. The spotlight is a general "this card just became active" cue and
# scoring is one caller of it, so this node never asks whether a submit is running.

var _layer : LightLayer = null
var _play_area : PlayArea = null
var _origins := SpotlightOrigins.new()

## ONE LIVE LIGHT. It outlives the section that created it, so lights travel instead of respawning.
class _Beam extends RefCounted:
	## The card it is lighting, or the last one it lit while retiring.
	var card : CardData = null
	## ⚠ AN INDEX, not a point: `SpotlightOrigins.advance()` moves the off-screen lamps every frame.
	var origin_idx : int = -1
	## Where the travel started. Meaningless once `t` reaches 1.
	var from : Vector2 = Vector2.ZERO
	## Travel progress, 0..1; 1 means settled on its card, so there is no separate "settled" state.
	var t : float = 1.0
	## Spawn-in / retire-out, 0..1. Scales the light's INTENSITY, never its size.
	var fade : float = 1.0
	var retiring : bool = false
	## A momentary cue rather than the scoring beam: self-timed, ungated, invisible to the section path.
	var cue : bool = false
	## Seconds of hold left before a cue starts retiring. Meaningless on a section beam.
	var hold_left : float = 0.0
	## Last position drawn: where a beam holds when its card's visual is gone (a discard, a rebuild frame).
	var last_pos : Vector2 = Vector2.ZERO
	## Last scale drawn at, held for the same reason as `last_pos`.
	var last_scale : float = 1.0

var _beams : Array[_Beam] = []
## Has the allocator been laid out for the act in progress? `begin()` may run only when nothing is lit.
var _band_ready : bool = false
## The environment whose cue this director draws. Held rather than re-looked-up: see `bind`.
var _env : CardEnvironment = null

# ⚠ THE ENVIRONMENT IS PASSED IN, NOT LOOKED UP: `get_current_game()` is set by `Game._enter_tree`
# and `GameView._ready` binds its `Game` BEFORE adding it to the tree, so a lookup returns null and
# nothing connects while every other piece stays green.

# ⚠ THE BEAM READS `spotlight_section_changed`, NEVER `spotlight_cued`. The cue is filtered to skills
# implementing `on_spotlight`, which no ordinary board card has; the section signal carries the
# scored row or column unfiltered. `spotlight_cued` drives the momentary cue only.

# `spotlight_reveal_ended` makes the reveal a BEAT: the section signal says where the light is, this
# says whether the show is up.
func bind(layer: LightLayer, play_area: PlayArea, env: CardEnvironment) -> void:
	_layer = layer
	_play_area = play_area
	_env = env
	if _env and not _env.spotlight_section_changed.is_connected(_on_section_changed):
		_env.spotlight_section_changed.connect(_on_section_changed)
	if _env and not _env.spotlight_reveal_ended.is_connected(_on_reveal_ended):
		_env.spotlight_reveal_ended.connect(_on_reveal_ended)
	if _env and not _env.spotlight_cued.is_connected(_on_cued):
		_env.spotlight_cued.connect(_on_cued)

# THE SECTION TOOK THE LIGHT: `cards` is every card in the row or column being scored, EMPTY when
# the act releases it. The set REPLACES: a scored section is no longer lit and its lights move on.
# A board compacted this frame queued a deferred rebuild, so it is flushed before any visual is read.

# A card in two consecutive sections KEEPS its light. The leftover lights and the unlit targets are
# both sorted by x and paired in order, which cannot cross. ⚠ CUE BEAMS ARE INVISIBLE TO THIS: never
# a leftover, never a claim, so a card both cued and scored carries two lights for the cue's life.

# ⚠ WHICH leftovers survive, and which targets receive a travelling light, are both chosen by
# PROXIMITY (`nearest_window`, a contiguous run, so nothing crosses): keeping the leftmost made the
# survivors cross the board while the beams already on the targets vanished.

# ⚠ A SURPLUS LIGHT IS RELEASED OUTRIGHT. The show falls to zero between sections, so it has already
# faded; left retiring, its `fade` times the next section's rising show re-lit it. `retire()` still
# fades, having no incoming section.

# A travelling light keeps its origin, so the beam pivots on its own lamp. A new light fades in
# ALREADY AIMED. ⚠ New lights take `assign()` for the whole batch, never `take()` in a loop: greedy
# nearest is order-dependent and lit the rightmost card of a five-card row from the leftmost lamp.

# ⚠ `requested` against `placed` is the log's diagnostic: a card with no live visual is skipped, so
# 5 requested and 2 placed is a BOARD problem. `_band_ready` gates `begin()`, which re-points every
# live origin index. The show is raised AFTER the set is in place, and by SECTION beams only.
func _on_section_changed(cards: Array[CardData]) -> void:
	if not _layer or not _play_area: return
	_play_area.flush_rebuild()
	if EventLog.is_on(EventLog.CH_SPOTLIGHT):
		EventLog.event(EventLog.CH_SPOTLIGHT, "section_changed",
				"cards=%d scoring=%s" % [cards.size(), str(_is_scoring())])
	var viewport := _layer.get_viewport_rect()
	if not _band_ready or _beams.is_empty():
		_origins.begin(cards.size(), viewport.size.x, viewport.position.y)
		_band_ready = true

	var wanted : Array[CardData] = []
	for data : CardData in cards:
		if _visual_of(data): wanted.append(data)

	var still : Dictionary[CardData, bool] = {}
	for data : CardData in wanted: still[data] = true
	var leftover : Array[_Beam] = []
	for b : _Beam in _beams:
		if b.retiring or b.cue: continue
		if b.card != null and still.has(b.card): continue
		leftover.append(b)
	var claimed : Dictionary[CardData, bool] = {}
	for b : _Beam in _beams:
		if not b.retiring and not b.cue and b.card != null: claimed[b.card] = true
	var targets : Array[CardData] = []
	for data : CardData in wanted:
		if not claimed.has(data): targets.append(data)

	leftover.sort_custom(func(a: _Beam, b: _Beam) -> bool:
		return _beam_centre(a).x < _beam_centre(b).x)
	targets.sort_custom(func(a: CardData, b: CardData) -> bool:
		return _centre_of(a).x < _centre_of(b).x)

	var pairs : int = mini(leftover.size(), targets.size())
	var src_x := PackedFloat32Array()
	for b : _Beam in leftover: src_x.append(_beam_centre(b).x)
	var tgt_x := PackedFloat32Array()
	for data : CardData in targets: tgt_x.append(_centre_of(data).x)
	var window := 0
	var tgt_window := 0
	if leftover.size() >= targets.size():
		window = SpotlightOrigins.nearest_window(src_x, tgt_x)
	else:
		tgt_window = SpotlightOrigins.nearest_window(tgt_x, src_x)
	for i : int in leftover.size():
		if i >= window and i < window + pairs: continue
		var dead : _Beam = leftover[i]
		if dead.origin_idx >= 0: _origins.release(dead.origin_idx)
		_beams.erase(dead)
	for i : int in pairs:
		var b : _Beam = leftover[window + i]
		b.from = _beam_centre(b)
		b.card = targets[tgt_window + i]
		b.t = 0.0
		b.retiring = false
		if EventLog.is_on(EventLog.CH_SPOTLIGHT):
			EventLog.event(EventLog.CH_SPOTLIGHT, "light_travel",
					"to=%s from=(%.0f,%.0f) origin_idx=%d" % [b.card.log_str(), b.from.x, b.from.y,
						b.origin_idx])
	if EventLog.is_on(EventLog.CH_SPOTLIGHT) and leftover.size() > pairs:
		EventLog.event(EventLog.CH_SPOTLIGHT, "light_retiring",
				"surplus=%d window=%d" % [leftover.size() - pairs, window])
	var new_targets : Array[CardData] = []
	var new_centres : Array[Vector2] = []
	for i : int in targets.size():
		if i >= tgt_window and i < tgt_window + pairs: continue
		new_targets.append(targets[i])
		new_centres.append(_centre_of(targets[i]))
	var assigned := _origins.assign(new_centres)
	for i : int in new_targets.size():
		var data : CardData = new_targets[i]
		var nb := _Beam.new()
		nb.card = data
		nb.t = 1.0
		nb.fade = 0.0
		nb.origin_idx = assigned[i] if i < assigned.size() else -1
		_beams.append(nb)
		if EventLog.is_on(EventLog.CH_SPOTLIGHT):
			EventLog.event(EventLog.CH_SPOTLIGHT, "light_spawn",
					"card=%s origin_idx=%d" % [data.log_str(), nb.origin_idx])

	if EventLog.is_on(EventLog.CH_SPOTLIGHT):
		EventLog.event(EventLog.CH_SPOTLIGHT, "lights_set",
				"requested=%d placed=%d travelled=%d spawned=%d retiring=%d"
				% [cards.size(), wanted.size(), pairs, maxi(targets.size() - pairs, 0),
					maxi(leftover.size() - pairs, 0)])
	_push()
	_layer.set_revealed(_section_beams() > 0)

## How many live lights belong to the SCORING beam rather than to a cue. The reveal gate is theirs.
func _section_beams() -> int:
	var n := 0
	for b : _Beam in _beams:
		if not b.cue: n += 1
	return n

# THE MOMENTARY CUE: `cards` is every card that just became spotlit AND has something to announce
# (`CardEnvironment` filters it). One cue is N lights built on one frame with one hold, so they rise
# and fall as a single announcement under the layer's one dim.

# ⚠ NOTHING IS BLOCKED AND NOTHING IS CANCELLED: a second cue APPENDS, and the earlier lights keep
# their own timers. The same stale-bindings flush, visual filter and `_band_ready` rule as the
# section path, and the same spawn shape: already aimed, faded in.

# ⚠ `take()`, NOT `assign()`: a cue is a set of INDEPENDENT announcements, not a scored section whose
# fan has to read as one rig.
func _on_cued(cards: Array[CardData]) -> void:
	if not _layer or not _play_area: return
	_play_area.flush_rebuild()
	var wanted : Array[CardData] = []
	for data : CardData in cards:
		if _visual_of(data): wanted.append(data)
	if EventLog.is_on(EventLog.CH_SPOTLIGHT):
		EventLog.event(EventLog.CH_SPOTLIGHT, "cued",
				"cards=%d placed=%d scoring=%s" % [cards.size(), wanted.size(), str(_is_scoring())])
	if wanted.is_empty(): return
	var viewport := _layer.get_viewport_rect()
	if not _band_ready or _beams.is_empty():
		_origins.begin(wanted.size(), viewport.size.x, viewport.position.y)
		_band_ready = true
	var hold := maxf(_delay() * FxAttachment.settings().spotlight_hold_fraction, 0.0)
	for data : CardData in wanted:
		var nb := _Beam.new()
		nb.card = data
		nb.cue = true
		nb.t = 1.0
		nb.fade = 0.0
		nb.hold_left = hold
		nb.origin_idx = _origins.take(_centre_of(data))
		_beams.append(nb)
		if EventLog.is_on(EventLog.CH_SPOTLIGHT):
			EventLog.event(EventLog.CH_SPOTLIGHT, "cue_spawn",
					"card=%s origin_idx=%d hold=%.3fs" % [data.log_str(), nb.origin_idx, hold])
	_push()

# WHERE A BEAM'S CIRCLE IS RIGHT NOW: its target's centre, a point along its travel, or its last
# drawn position when the card's visual is gone. The travel is a smoothstep on POSITION only:
# full size the whole way, because a real followspot neither shrinks nor dims in transit.

# ⚠ ALSO RECORDS THE CARD'S DRAWN SCALE in `last_scale`, held like the position when the visual is
# gone: at a board zoom of 1.82 a radius scaled by card_scale alone drew 17.6 art units wide, not 32.
func _beam_centre(b: _Beam) -> Vector2:
	var visual := _visual_of(b.card) if b.card else null
	if visual: b.last_scale = visual.spotlight_scale()
	var target := visual.spotlight_center() if visual else b.last_pos
	if b.t < 1.0 and b.card != null:
		target = b.from.lerp(target, smoothstep(0.0, 1.0, b.t))
	b.last_pos = target
	return target

## A card's centre in screen pixels. ⚠ (0,0) when it has no live visual: filter by `_visual_of` first.
func _centre_of(data: CardData) -> Vector2:
	var visual := _visual_of(data) if data else null
	return visual.spotlight_center() if visual else Vector2.ZERO

# The section's reveal is over and its scoring is starting: FADE the show, KEEP the set. The lights
# stay at their positions through the fade so the next section can travel FROM them.
func _on_reveal_ended() -> void:
	if _layer: _layer.set_revealed(false)

# Retire every light, which is also what lowers the dim. ⚠ THE LIGHTS FADE, THEY DO NOT VANISH:
# each is marked retiring and `_process` frees it and releases its origin when it reaches zero.
func retire() -> void:
	EventLog.event(EventLog.CH_SPOTLIGHT, "retire", "live=%d" % _beams.size())
	for b : _Beam in _beams: b.retiring = true

## Free everything immediately, with no fade: the board is gone, so there is nothing to fade ON.
func _release_all() -> void:
	for b : _Beam in _beams:
		if b.origin_idx >= 0: _origins.release(b.origin_idx)
	_beams.clear()
	_band_ready = false

## One unit of show time. Every duration here is a FRACTION of it, so it compresses with the act speed-up.
func _delay() -> float:
	var game := _env as Game
	return game.get_delay() if game else FxAttachment.settings().base_delay

# PER FRAME: advance every travel and fade, drop the finished retirements, re-spread the off-screen
# lamps and re-push. ⚠ The lit cards' positions are RE-READ every frame: a card moves while it is
# lit (a slide, a jump, a scroll) and a beam that kept its first position would slide off it.

# Every travelling light advances on the SAME frame. ⚠ A CUE is spawn, hold, retire, and only it has
# an end of its own; its hold starts once the spawn has finished, so a speed-up that shortens the
# fade-in cannot eat the beat the player is meant to see.
func _process(delta: float) -> void:
	if not _layer or _beams.is_empty(): return
	_origins.advance(_layer.get_viewport_rect().position.y)
	var s := FxAttachment.settings()
	var unit := _delay()
	var travel := maxf(unit * s.spotlight_travel_fraction, 0.0001)
	var spawn := maxf(unit * s.spotlight_spawn_fraction, 0.0001)
	var leave := maxf(unit * s.spotlight_retire_fraction, 0.0001)
	var done : Array[_Beam] = []
	for b : _Beam in _beams:
		if b.t < 1.0: b.t = minf(b.t + delta / travel, 1.0)
		if b.retiring:
			b.fade = maxf(b.fade - delta / leave, 0.0)
			if b.fade <= 0.0: done.append(b)
		elif b.fade < 1.0:
			b.fade = minf(b.fade + delta / spawn, 1.0)
		elif b.cue:
			b.hold_left -= delta
			if b.hold_left <= 0.0:
				b.retiring = true
				if EventLog.is_on(EventLog.CH_SPOTLIGHT):
					EventLog.event(EventLog.CH_SPOTLIGHT, "cue_retiring",
							"card=%s" % [b.card.log_str() if b.card else "<none>"])
	for b : _Beam in done:
		if b.origin_idx >= 0: _origins.release(b.origin_idx)
		_beams.erase(b)
	if _beams.is_empty(): _band_ready = false
	_push()

# HAND THE LIVE SET TO THE LAYER. ⚠ ONE PLACE builds `LightLayer.Light`, so a travelling beam and a
# settled one cannot be described differently. The radius and the lamp's width are the style's art
# units times the card's drawn scale; the cone's mouth is derived from the radius by the shader.

# The fade is the SPAWN and RETIRE envelope only. ⚠ A CUE does not ride the per-section reveal
# (`LightLayer.Light.gated`): its whole envelope is `fade`, so it can show outside a submit.

# ⚠ A BEAM NEVER POINTS UPWARD, applied here at the only place that knows both ends: a target below
# the viewport is lit from the screen EDGE. The origin is FIXED while the wide end tracks the circle.
func _push() -> void:
	if not _layer: return
	var style := _layer.style
	var viewport := _layer.get_viewport_rect()
	var lights : Array[LightLayer.Light] = []
	for b : _Beam in _beams:
		var centre := _beam_centre(b)
		var light := LightLayer.Light.new()
		light.centre = centre
		light.radius = style.circle_radius * b.last_scale
		light.origin_width = style.beam_width_at_origin * b.last_scale
		light.flare = style.flare
		light.intensity = b.fade
		light.gated = not b.cue
		light.origin = SpotlightOrigins.edge_origin_for(centre, viewport.position.y,
				viewport.position.y + viewport.size.y, _origins.origin_of(b.origin_idx))
		lights.append(light)
	_layer.set_lights(lights, _is_scoring())

# The card's live visual, or null if it has none on the board right now: a cued card can be in a
# viewer, mid-deferred-add, or already gone. ⚠ A nullable OBJECT, not a `Variant` position: every
# use of a Variant is an unsafe call, which this project treats as an error.
func _visual_of(data: CardData) -> CardVisual:
	var visual : CardVisual = _play_area.data_card.get(data)
	if not is_instance_valid(visual) or not visual.is_inside_tree(): return null
	return visual

# Is the current cue part of a scoring act? A READ of the game's own state, never a flag kept here.
# ⚠ `processing` is the game's input lock across an async action: exactly the span a scoring cascade
# occupies and a card placed in ordinary play is outside of, which picks the deep or shallow dim.
func _is_scoring() -> bool:
	var game := _env as Game
	return game != null and game.processing
