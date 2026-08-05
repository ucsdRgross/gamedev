class_name SpotlightDirector
extends Node
## THE WIRE — the one thing that makes any of phase 2 visible in the running game. It listens for
## `CardEnvironment.spotlight_section_changed(cards)`, turns each card into a screen position, takes
## an origin per card from `SpotlightOrigins`, and hands the set to `LightLayer`.
##
## ⚠ **NOT `spotlight_cued` — that was GAP-005 and it made the feature invisible for a whole phase.**
## The cue is `Q246`-filtered to skills implementing `on_spotlight`, which no ordinary board card has,
## so the light set was permanently empty in the running game. See `bind()`.
##
## THREE OBJECTS, THREE QUESTIONS, AND KEEPING THEM APART IS THE POINT:
##
##   * `CardEnvironment` — **WHO is lit.** Pure game state, no pixels, headless-green since S10.
##   * `SpotlightOrigins` — **WHERE the lamp is.** Pure arithmetic over screen coordinates,
##     headless-testable, and where `Q117` (a beam never points upward) lives.
##   * `LightLayer` — **WHAT a lit pixel looks like.** One material, no knowledge of cards.
##
## This node is the only place all three meet, which is why it is the only one that needs a
## `PlayArea` — and why none of the other three had to know a card exists.
##
## ⚠ **THE DIM IS A FUNCTION OF WHAT IS LIT, NOT OF THE ACT** (`QR2`=d). There is no "start the dim"
## and no "stop the dim" here: `set_lights([])` retires it, because a second way to lower the dim is
## a second thing that can disagree with the light set. `Q149` made the spotlight a general
## "this card just became active" cue and scoring one caller of it — so this node never asks whether
## a submit is running, only whether the cue it just received belongs to one.

## ⚠ **THESE WERE `const`s AND SHOULD NEVER HAVE BEEN** — `DESIGN.md` §16 lists `circle_radius` and
## `beam_width_at_origin` as tunables on a style resource, and `Q85`'s own answer asks for the radius
## in the same breath as the number: *"16, make it adjustable so I can test slightly different
## radius"*. Baked here, the tuning tool had nothing to change and the owner reported exactly that.
## They now come from `FxSpotlightStyle` via the light layer, so there is ONE value rather than a
## constant and a knob that can disagree.
## ⚠ The FALLBACKS are the shipped defaults, used only when no layer or style is bound — a director
## with no light layer draws nothing anyway.
const CIRCLE_ART_UNITS_FALLBACK := 16.0
const ORIGIN_WIDTH_ART_UNITS_FALLBACK := 9.0

## The circle's radius in ART units, from the style. Screen pixels are this times the live
## `card_scale`, which the player can change.
func _circle_art_units() -> float:
	var s : FxSpotlightStyle = _layer.style if _layer else null
	return s.circle_radius if s else CIRCLE_ART_UNITS_FALLBACK

## The cone's half-width where it leaves its lamp, in art units. ⚠ Its width at the TARGET is not
## here and must not be: the shader derives that from the circle's radius, so the cone's mouth cannot
## disagree with the pool it opens onto.
func _origin_width_art_units() -> float:
	var s : FxSpotlightStyle = _layer.style if _layer else null
	return s.beam_width_at_origin if s else ORIGIN_WIDTH_ART_UNITS_FALLBACK

var _layer : LightLayer = null
var _play_area : PlayArea = null
var _origins := SpotlightOrigins.new()

## **ONE LIVE LIGHT — chart E's unit.** A light OUTLIVES the section that created it: that is the
## whole of the brief's *"no instant movements or spawning in and out"*, and it is why the director
## holds records rather than rebuilding an array of `LightLayer.Light` every section.
class _Beam extends RefCounted:
	## The card it is lighting, or the last one it lit while retiring.
	var card : CardData = null
	## ⚠ AN INDEX, not a point: `SpotlightOrigins.advance()` moves the off-screen lamps every frame,
	## so a stored point stops identifying its lamp after one frame.
	var origin_idx : int = -1
	## Where the travel started. Meaningless once `t` reaches 1.
	var from : Vector2 = Vector2.ZERO
	## Travel progress, 0..1. **1 means settled on its card** — a light that is not moving is simply
	## one whose `t` is already 1, so there is no separate "settled" state to fall out of step.
	var t : float = 1.0
	## Spawn-in / retire-out, 0..1. Scales the light's INTENSITY, never its size (`Q63`=a).
	var fade : float = 1.0
	var retiring : bool = false
	## **IS THIS CHART T'S MOMENTARY CUE RATHER THAN THE SCORING BEAM?** A cue is self-timed — it
	## spawns, holds and retires on its own — and is INVISIBLE to `_on_section_changed`: it never
	## travels, is never stolen as a section's leftover, and never blocks a section from lighting the
	## same card. It is also ungated, so it does not ride the per-section reveal (`LightLayer.Light`).
	var cue : bool = false
	## Seconds of hold left before a cue starts retiring. Meaningless on a section beam, which holds
	## until the section moves on or the act releases it.
	var hold_left : float = 0.0

var _beams : Array[_Beam] = []
## Has the allocator been laid out for the act in progress? ⚠ **`begin()` REBUILDS `_origins` AND
## CLEARS `_taken`, which invalidates every index a live beam is holding** — so it may run only when
## nothing is lit. Calling it per section (which the pre-travel build did) is harmless only because
## that build also threw every light away each section; with travel it would re-point live lamps.
var _band_ready : bool = false
## The environment whose cue this director draws. Held rather than re-looked-up: see `bind`.
var _env : CardEnvironment = null

## ⚠ **THE ENVIRONMENT IS PASSED IN, NOT LOOKED UP, AND THE FIRST BUILD GOT THIS WRONG.** It called
## `CardEnvironment.get_current_game()` — which is set by `Game._enter_tree`, and `GameView._ready`
## deliberately builds and binds its `Game` BEFORE adding it to the tree (its own comment says so).
## So the lookup returned null, nothing was connected, and every piece of phase 2 stayed green while
## the feature did nothing at all. That is the exact failure `test_the_spotlight_wire_lights_the_layer`
## exists for, and it is why the caller hands over the game it already holds.
func bind(layer: LightLayer, play_area: PlayArea, env: CardEnvironment) -> void:
	_layer = layer
	_play_area = play_area
	_env = env
	# ⚠ **`spotlight_section_changed`, NOT `spotlight_cued` — GAP-005.** The cue is filtered by
	# `Q246`=(a) to skills implementing `on_spotlight`, and the shipped game has exactly ONE (a rules
	# card, with no `CardVisual`), so binding the beam to it made the light set permanently empty and
	# no beam ever appeared in the running game. The section signal carries the scored row or column
	# unfiltered, which is what the beam lights. S15 is what will draw the cue, separately.
	if _env and not _env.spotlight_section_changed.is_connected(_on_section_changed):
		_env.spotlight_section_changed.connect(_on_section_changed)
	# GAP-006: the reveal is a BEAT, not the whole act. The section signal says where the light is;
	# this says whether the show is up.
	if _env and not _env.spotlight_reveal_ended.is_connected(_on_reveal_ended):
		_env.spotlight_reveal_ended.connect(_on_reveal_ended)
	# **S15 — AND THIS IS THE OTHER HALF OF GAP-005, NOT A RELAPSE INTO IT.** Both signals reach this
	# node, and the ruling was that they must not be CONFLATED: `spotlight_section_changed` drives the
	# scoring beam above, `spotlight_cued` drives chart T's momentary cue below, and neither reads the
	# other's. Binding the BEAM to the cue is what GAP-005 forbids.
	if _env and not _env.spotlight_cued.is_connected(_on_cued):
		_env.spotlight_cued.connect(_on_cued)

## The section took the light: `cards` is every card in the row or column being scored right now,
## or EMPTY when the act releases it. **Unfiltered** — a scored row is mostly plain numeral cards
## with no skill, and the beam lights all of them (GAP-005).
##
## ⚠ **THE SET REPLACES, IT DOES NOT ACCUMULATE.** That is `Q16`=(c)'s travelling light restated at
## the presentation layer: a section that has already scored is no longer lit, and the beam moves
## rather than the board filling up with lamps.
func _on_section_changed(cards: Array[CardData]) -> void:
	if not _layer or not _play_area: return
	if EventLog.is_on(EventLog.CH_SPOTLIGHT):
		EventLog.event(EventLog.CH_SPOTLIGHT, "section_changed",
				"cards=%d scoring=%s" % [cards.size(), str(_is_scoring())])
	var viewport := _layer.get_viewport_rect()
	# ⚠ ONLY when nothing is lit — see `_band_ready`. Re-laying the band mid-act would re-point every
	# live beam's origin index at somebody else's lamp.
	if not _band_ready or _beams.is_empty():
		_origins.begin(cards.size(), viewport.size.x, viewport.position.y)
		_band_ready = true

	# THE NEXT SET N: every card that actually has a visual to light.
	var wanted : Array[CardData] = []
	for data : CardData in cards:
		if _visual_of(data): wanted.append(data)

	# **E2 — P ∩ N KEEPS ITS LIGHT AND DOES NOT MOVE** (`Q61`=a: *"a card spotlit in two consecutive
	# lines keeps its own light"*). This is the case that makes a cascade read as one rig following the
	# scoring rather than as a new rig per line.
	var still : Dictionary[CardData, bool] = {}
	for data : CardData in wanted: still[data] = true
	# ⚠ **CUE BEAMS ARE INVISIBLE TO ALL OF THIS.** A momentary cue is not a section light: it must not
	# be reassigned as a leftover (chart E's travel is `Q16`=(c)'s SCORING light moving section to
	# section), and it must not `claim` its card either — claiming would deny the section a light on a
	# card that happens to be cued, and then the cue's own retire would leave that card dark for the
	# rest of the section. A card both cued and scored therefore carries two lights for the cue's
	# lifetime, which is the harmless side of the two choices.
	var leftover : Array[_Beam] = []          # E4: lights whose card left the set
	for b : _Beam in _beams:
		if b.retiring or b.cue: continue
		if b.card != null and still.has(b.card): continue
		leftover.append(b)
	var claimed : Dictionary[CardData, bool] = {}
	for b : _Beam in _beams:
		if not b.retiring and not b.cue and b.card != null: claimed[b.card] = true
	var targets : Array[CardData] = []        # E4: targets with no light yet
	for data : CardData in wanted:
		if not claimed.has(data): targets.append(data)

	# **E2's ASSIGNMENT — sort both by x, pair in order** (chart E2 option A; GAP-008 is the open
	# ruling on it). Two pairs cross only if their order is inverted, and pairing two sorted sequences
	# inverts nothing — which is the property `Q111`=(a) names as its own reason.
	leftover.sort_custom(func(a: _Beam, b: _Beam) -> bool:
		return _beam_centre(a).x < _beam_centre(b).x)
	targets.sort_custom(func(a: CardData, b: CardData) -> bool:
		return _centre_of(a).x < _centre_of(b).x)

	var pairs : int = mini(leftover.size(), targets.size())
	for i : int in pairs:
		# **E9 — THE LIGHT TRAVELS.** Its origin is kept, so the beam pivots on its own lamp rather
		# than the lamp teleporting with it (E10: *"origin fixed, wide end tracks the circle"*).
		var b : _Beam = leftover[i]
		b.from = _beam_centre(b)
		b.card = targets[i]
		b.t = 0.0
		b.retiring = false
		if EventLog.is_on(EventLog.CH_SPOTLIGHT):
			EventLog.event(EventLog.CH_SPOTLIGHT, "light_travel",
					"to=%s from=(%.0f,%.0f) origin_idx=%d" % [b.card.log_str(), b.from.x, b.from.y,
						b.origin_idx])
	# **E3 — SURPLUS LIGHTS RETIRE**, fading in place on the card they were already on.
	for i : int in range(pairs, leftover.size()):
		leftover[i].retiring = true
		if EventLog.is_on(EventLog.CH_SPOTLIGHT):
			EventLog.event(EventLog.CH_SPOTLIGHT, "light_retiring", "surplus")
	# **E4 — SURPLUS TARGETS GET NEW LIGHTS.** `Q65`=(a): a new light FADES IN ALREADY AIMED at its
	# target (`t = 1`), rather than travelling in along its beam from the origin — the searchlight
	# sweep was the declined reading.
	for i : int in range(pairs, targets.size()):
		var data : CardData = targets[i]
		var nb := _Beam.new()
		nb.card = data
		nb.t = 1.0
		nb.fade = 0.0
		# One light, so the single-light rule applies: the free origin NEAREST it (`Q111`=a, I7).
		nb.origin_idx = _origins.take(_centre_of(data))
		_beams.append(nb)
		if EventLog.is_on(EventLog.CH_SPOTLIGHT):
			EventLog.event(EventLog.CH_SPOTLIGHT, "light_spawn",
					"card=%s origin_idx=%d" % [data.log_str(), nb.origin_idx])

	if EventLog.is_on(EventLog.CH_SPOTLIGHT):
		# ⚠ `requested` vs `placed` is the diagnostic that matters: a card with no live `CardVisual` is
		# silently skipped, so a section of 5 that places 2 is a BOARD problem, not a light problem.
		EventLog.event(EventLog.CH_SPOTLIGHT, "lights_set",
				"requested=%d placed=%d travelled=%d spawned=%d retiring=%d"
				% [cards.size(), wanted.size(), pairs, maxi(targets.size() - pairs, 0),
					maxi(leftover.size() - pairs, 0)])
	_push()
	# ⚠ A NEW SECTION RAISES THE SHOW AGAIN (GAP-006) — *"When next section is revealed, spotlight and
	# dim effect are visible again"*. Raised AFTER the set is in place, so the fade-in already points
	# at the right cards.
	# ⚠ SECTION beams only: a live cue must not hold the section gate up, or a cue arriving in the gap
	# between two sections would re-raise the previous section's faded beams along with itself.
	_layer.set_revealed(_section_beams() > 0)

## How many live lights belong to the SCORING beam rather than to a cue. The reveal gate is theirs.
func _section_beams() -> int:
	var n := 0
	for b : _Beam in _beams:
		if not b.cue: n += 1
	return n

## **S15 — CHART T'S MOMENTARY CUE.** `cards` is every card that just transitioned into spotlit AND
## has something to announce (`Q246`=(a) filters it to skills implementing `on_spotlight`; the filter
## is `CardEnvironment`'s and this node does not repeat it).
##
## ⚠ **T12/T13 — ONE CUE, N SPOTLIGHTS, SPAWNING TOGETHER.** `Q247`=(a): a `Next` that drops four
## stacks is *"N spotlights, ONE dim that covers all of them"*, not four cues in a row. They are built
## on one frame with one hold, so they rise and fall as a single announcement — the dim is `LightLayer`'s
## single value and needs nothing here to make that true.
## ⚠ **T15/T16 — NOTHING IS BLOCKED AND NOTHING IS CANCELLED** (`Q249`=a). A second cue while the
## first is still retiring simply adds lights; the earlier ones keep their own timers and are not
## touched, which is why this APPENDS rather than replacing the way `_on_section_changed` does.
func _on_cued(cards: Array[CardData]) -> void:
	if not _layer or not _play_area: return
	# THE CARDS THAT ACTUALLY HAVE A VISUAL TO LIGHT — same filter, same reason, as the section path.
	var wanted : Array[CardData] = []
	for data : CardData in cards:
		if _visual_of(data): wanted.append(data)
	if EventLog.is_on(EventLog.CH_SPOTLIGHT):
		EventLog.event(EventLog.CH_SPOTLIGHT, "cued",
				"cards=%d placed=%d scoring=%s" % [cards.size(), wanted.size(), str(_is_scoring())])
	if wanted.is_empty(): return
	var viewport := _layer.get_viewport_rect()
	# ⚠ Same `_band_ready` rule as the section path, and for the same reason — `begin()` clears the
	# taken-set, so it may run only when no light is holding an index.
	if not _band_ready or _beams.is_empty():
		_origins.begin(wanted.size(), viewport.size.x, viewport.position.y)
		_band_ready = true
	var hold := maxf(_delay() * SettingsManager.settings.spotlight_hold_fraction, 0.0)
	for data : CardData in wanted:
		var nb := _Beam.new()
		nb.card = data
		nb.cue = true
		# `Q65`=(a)'s spawn shape, shared with the section path: ALREADY AIMED, faded in rather than
		# swept in along the beam.
		nb.t = 1.0
		nb.fade = 0.0
		nb.hold_left = hold
		# ⚠ `take()`, NOT `assign()` — `SpotlightOrigins` says so in as many words: the one-at-a-time
		# form is *"kept for callers that genuinely place a single light (chart T's momentary cue, where
		# there is no set to sort)"*. A cue is a set of INDEPENDENT announcements, not a scored section
		# whose fan has to read as one rig, so GAP-008's column fan does not apply to it.
		nb.origin_idx = _origins.take(_centre_of(data))
		_beams.append(nb)
		if EventLog.is_on(EventLog.CH_SPOTLIGHT):
			EventLog.event(EventLog.CH_SPOTLIGHT, "cue_spawn",
					"card=%s origin_idx=%d hold=%.3fs" % [data.log_str(), nb.origin_idx, hold])
	_push()

## Where a beam's circle is RIGHT NOW — its target's art square, or a point along its travel.
## ⚠ `Q63`=(a): full size the whole way. The ease is on POSITION only; nothing shrinks or dims in
## transit, because a real followspot does not.
func _beam_centre(b: _Beam) -> Vector2:
	var target := _centre_of(b.card)
	if b.t >= 1.0 or b.card == null: return target
	# Smoothstep: the light accelerates off its old card and settles onto the new one rather than
	# starting and stopping abruptly, which is what "no instant movements" is asking for.
	return b.from.lerp(target, smoothstep(0.0, 1.0, b.t))

## A card's art-square centre in screen pixels, or the beam's last position if the card is gone.
func _centre_of(data: CardData) -> Vector2:
	var visual := _visual_of(data) if data else null
	return visual.spotlight_center() if visual else Vector2.ZERO

## The section's reveal is over and its scoring is starting: FADE the show, keep the set (GAP-006).
##
## ⚠ **KEEPING THE SET IS THE POINT, NOT AN OVERSIGHT.** The lights stay at their positions through
## the fade so the next section can travel FROM them (chart E, *"no instant movements or spawning in
## and out"*). Freeing them here would make the beams respawn at new positions every section — which
## is what the brief forbids, and what the pre-GAP-006 `_release_all()`-and-rebuild already did.
func _on_reveal_ended() -> void:
	if _layer: _layer.set_revealed(false)

## Retire every light — which is also what lowers the dim, since the dim is a function of what is
## lit. Called when the act releases its spotlight (`_release_spotlight`, S9) or the board clears.
##
## ⚠ **THE LIGHTS FADE, THEY DO NOT VANISH** (chart E3, and the brief's *"no instant movements or
## spawning in and out"* applies to the END of an act as much as to the middle of one). Each beam is
## marked retiring and fades over `spotlight_retire_fraction`; `_advance` frees them and releases
## their origins when they reach zero.
func retire() -> void:
	EventLog.event(EventLog.CH_SPOTLIGHT, "retire", "live=%d" % _beams.size())
	for b : _Beam in _beams: b.retiring = true

## Free everything immediately, with no fade — the board is gone, so there is nothing to fade ON.
func _release_all() -> void:
	for b : _Beam in _beams:
		if b.origin_idx >= 0: _origins.release(b.origin_idx)
	_beams.clear()
	_band_ready = false

## One unit of show time. Every duration here is a FRACTION of it (`Q167`=a), never wall-clock, so
## the whole travel compresses with the act speed-up exactly like the dim and the hold beat.
func _delay() -> float:
	var game := _env as Game
	return game.get_delay() if game else SettingsManager.settings.base_delay

## Per frame: advance every travel and fade, drop the finished retirements, re-spread the off-screen
## lamps (I10–I12), and re-push.
##
## ⚠ **THE LIT CARDS' POSITIONS ARE RE-READ EVERY FRAME** — a card moves while it is lit (the
## compact-and-follow slide of S7, a jump, a scroll), and a beam that kept its first position would
## slide off its target. `Q252`=(b)'s re-read discipline, at the presentation layer.
func _process(delta: float) -> void:
	if not _layer or _beams.is_empty(): return
	_origins.advance(_layer.get_viewport_rect().position.y)
	var s := SettingsManager.settings
	var unit := _delay()
	var travel := maxf(unit * s.spotlight_travel_fraction, 0.0001)
	var spawn := maxf(unit * s.spotlight_spawn_fraction, 0.0001)
	var leave := maxf(unit * s.spotlight_retire_fraction, 0.0001)
	var done : Array[_Beam] = []
	for b : _Beam in _beams:
		# **E9 / `Q64`=(a): every travelling light advances on the SAME frame** — simultaneous, not
		# staggered, which is one loop rather than a per-light delay.
		if b.t < 1.0: b.t = minf(b.t + delta / travel, 1.0)
		if b.retiring:
			b.fade = maxf(b.fade - delta / leave, 0.0)
			if b.fade <= 0.0: done.append(b)
		elif b.fade < 1.0:
			b.fade = minf(b.fade + delta / spawn, 1.0)
		elif b.cue:
			# **T6 — THE CUE IS SPAWN, HOLD, RETIRE, AND ONLY IT HAS AN END OF ITS OWN.** A section
			# beam holds until the section moves on or the act releases it; a cue answers to nothing
			# outside itself, so its hold is counted here and it retires without anyone telling it to.
			# ⚠ The hold starts only once the spawn has finished, so a speed-up that shortens the
			# fade-in cannot eat the beat the player is meant to see.
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

## Hand the live set to the layer. ⚠ ONE PLACE builds `LightLayer.Light`, so a travelling beam and a
## settled one cannot be described differently by two code paths.
func _push() -> void:
	if not _layer: return
	var scale := SettingsManager.settings.card_scale
	var viewport := _layer.get_viewport_rect()
	var lights : Array[LightLayer.Light] = []
	for b : _Beam in _beams:
		var centre := _beam_centre(b)
		var light := LightLayer.Light.new()
		light.centre = centre
		light.radius = _circle_art_units() * scale
		light.origin_width = _origin_width_art_units() * scale
		light.flare = _layer.style.flare if _layer.style else 0.0
		# **`Q63`=(a): FULL SIZE IN TRANSIT.** The fade is the SPAWN and RETIRE envelope only — a
		# travelling light does not dim, because a real followspot does not.
		light.intensity = b.fade
		# ⚠ A CUE DOES NOT RIDE THE PER-SECTION REVEAL — see `LightLayer.Light.gated`. Its whole
		# envelope is `fade`, which is why it can be shown outside a submit at all.
		light.gated = not b.cue
		# ⚠ `Q117` IS APPLIED HERE, AT THE ONLY PLACE THAT KNOWS BOTH ENDS. A target below the viewport
		# is lit from the screen EDGE rather than by tilting a rig lamp up to reach it.
		# ⚠ **E10: the origin is FIXED while the wide end tracks the circle** — the beam pivots on its
		# own lamp through the whole travel, which is what makes it read as one light moving rather
		# than as the whole rig sliding.
		light.origin = SpotlightOrigins.edge_origin_for(centre, viewport.position.y,
				viewport.position.y + viewport.size.y, _origins.origin_of(b.origin_idx))
		lights.append(light)
	_layer.set_lights(lights, _is_scoring())

## The card's live visual, or null if it has none on the board right now — a cued card can be in a
## viewer, mid-deferred-add (`CardVisual` adds itself with `call_deferred`), or already gone.
##
## ⚠ TYPED, NOT `Variant`. Returning "a position or null" reads well and does not compile: every
## caller then holds a `Variant` and every use of it is an unsafe call, which this project treats as
## an error. The nullable OBJECT is the typed way to say the same thing.
func _visual_of(data: CardData) -> CardVisual:
	var visual : CardVisual = _play_area.data_card.get(data)
	if not is_instance_valid(visual) or not visual.is_inside_tree(): return null
	return visual

## Is the current cue part of a scoring act? The ONLY thing here that knows scoring exists, and it
## is a READ of the game's own state rather than a flag this node maintains — a second copy of "are
## we scoring" is a second thing that can be wrong.
##
## ⚠ `processing` is the game's own input lock across an async action, which is exactly the span a
## scoring cascade occupies and exactly what a card PLACED in ordinary play is outside of. That is
## the distinction `Q245`=(c) needs — deep dim inside scoring, shallow outside — and there is no
## narrower flag: `act_cancellable` is scoped to the unwind window, not the show.
func _is_scoring() -> bool:
	var game := _env as Game
	return game != null and game.processing
