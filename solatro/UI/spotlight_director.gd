class_name SpotlightDirector
extends Node
## THE WIRE — the one thing that makes any of phase 2 visible in the running game. It listens for
## `CardEnvironment.spotlight_cued(cards)` (S10 emits it), turns each cued card into a screen
## position, takes an origin per card from `SpotlightOrigins`, and hands the set to `LightLayer`.
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

## `Q85`: the circle is 16 ART units, centred on the card's art square. In SCREEN pixels that is
## scaled by the live `card_scale`, which the player can change — hence a function of the setting
## rather than a baked number.
const CIRCLE_ART_UNITS := 16.0

## How wide the cone is where it leaves its lamp, in art units. ⚠ Its width at the TARGET is not
## here and must not be: the shader derives that from the circle's radius, so the cone's mouth
## cannot disagree with the pool it opens onto.
const ORIGIN_WIDTH_ART_UNITS := 9.0

var _layer : LightLayer = null
var _play_area : PlayArea = null
var _origins := SpotlightOrigins.new()
## The origin index each lit card holds, so it can be released when the cue retires. ⚠ INDICES, not
## points: `SpotlightOrigins.advance()` moves the off-screen ones every frame, so a stored point
## stops identifying its lamp after one frame.
var _held : Dictionary[CardData, int] = {}
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
	_release_all()
	var lights : Array[LightLayer.Light] = []
	var scale := SettingsManager.settings.card_scale
	var viewport := _layer.get_viewport_rect()
	_origins.begin(cards.size(), viewport.size.x, viewport.position.y)
	for data : CardData in cards:
		var visual := _visual_of(data)
		if not visual: continue
		# ⚠ **`global_position` IS ALREADY THE SCREEN PIXEL** the shader's `SCREEN_UV` resolves to —
		# one canvas layer, no camera offset, and the board's scroll is inside the transform.
		# Converting again here would be a second copy of the scroll that can disagree with the real
		# one, which is the drift bug this whole layer is arranged to avoid.
		var centre := visual.global_position
		var light := LightLayer.Light.new()
		light.centre = centre
		light.radius = CIRCLE_ART_UNITS * scale
		light.origin_width = ORIGIN_WIDTH_ART_UNITS * scale
		var idx := _origins.take(centre)
		_held[data] = idx
		# ⚠ `Q117` IS APPLIED HERE, AT THE ONLY PLACE THAT KNOWS BOTH ENDS. A target below the
		# viewport is lit from the screen edge rather than by tilting a rig lamp up to reach it —
		# the beam can never point upward.
		light.origin = SpotlightOrigins.edge_origin_for(centre, viewport.position.y,
				viewport.position.y + viewport.size.y, _origins.origin_of(idx))
		lights.append(light)
		if EventLog.is_on(EventLog.CH_SPOTLIGHT):
			# The CARD's identity, its screen position and which lamp it took — the three things a
			# "why is that beam there" question ever needs.
			EventLog.event(EventLog.CH_SPOTLIGHT, "light_placed",
					"card=%s centre=(%.0f,%.0f) origin_idx=%d origin=(%.0f,%.0f) r=%.1f"
					% [data.log_str(), centre.x, centre.y, idx,
						light.origin.x, light.origin.y, light.radius])
	if EventLog.is_on(EventLog.CH_SPOTLIGHT):
		# ⚠ `requested` vs `placed` is the diagnostic that matters: a card with no live `CardVisual`
		# is silently skipped by `_visual_of`, so a section of 5 that places 2 lights is a board
		# problem, not a light problem, and the two numbers are the only way to tell them apart.
		EventLog.event(EventLog.CH_SPOTLIGHT, "lights_set",
				"requested=%d placed=%d" % [cards.size(), lights.size()])
	# Scoring or not decides the dim's depth (`Q245`=c — a much shallower dim outside scoring, since
	# otherwise the screen pulses dark on every single card you place).
	_layer.set_lights(lights, _is_scoring())
	# ⚠ A NEW SECTION RAISES THE SHOW AGAIN (GAP-006) — *"When next section is revealed, spotlight and
	# dim effect are visible again"*. Raised AFTER the set is in place, so the fade-in is already
	# pointing at the right cards.
	_layer.set_revealed(not lights.is_empty())

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
func retire() -> void:
	EventLog.event(EventLog.CH_SPOTLIGHT, "retire", "held=%d" % _held.size())
	_release_all()
	if _layer: _layer.set_lights([] as Array[LightLayer.Light], false)

func _release_all() -> void:
	for idx : int in _held.values(): _origins.release(idx)
	_held = {}

## Per frame: the off-screen lamps re-spread, the on-screen ones are pinned (I10–I12). ⚠ The lit
## cards' POSITIONS are re-read here too — a card moves while it is lit (the compact-and-follow
## slide of S7, a jump, a scroll), and a beam that kept its first position would slide off its
## target. `Q252`=(b)'s re-read discipline, at the presentation layer.
func _process(_delta: float) -> void:
	if not _layer or not _layer.is_lit() or _held.is_empty(): return
	_origins.advance(_layer.get_viewport_rect().position.y)
	var lights : Array[LightLayer.Light] = []
	var scale := SettingsManager.settings.card_scale
	var viewport := _layer.get_viewport_rect()
	for data : CardData in _held:
		var visual := _visual_of(data)
		if not visual: continue
		var centre := visual.global_position
		var light := LightLayer.Light.new()
		light.centre = centre
		light.radius = CIRCLE_ART_UNITS * scale
		light.origin_width = ORIGIN_WIDTH_ART_UNITS * scale
		light.origin = SpotlightOrigins.edge_origin_for(centre, viewport.position.y,
				viewport.position.y + viewport.size.y, _origins.origin_of(_held[data]))
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
