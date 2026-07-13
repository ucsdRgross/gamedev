class_name PropLayer
extends Node2D
## Phase 4 prop-animation surface (SUIT_PROPS_PLAN §4.2). Lives inside the scrolled content
## (SmoothScrollContainer/TopLevelVBox) so prop local coordinates are scroll-invariant — the
## scroll transform carries cards AND props together, so mid-flight scrolling just works and
## container layout ignores Node2D children.
##
## The Game runs the prop SIMULATION (data, one tick ahead); this layer only animates. Each
## data tick the Game calls begin_prop_tick(...) and awaits `tick_done`, which fires once every
## live visual has reached its target. Interpolation is driven PER FRAME against the LIVE tick
## duration (game.get_delay() re-read every frame) so changing the animation speed — or
## compression kicking in — retimes props already mid-slot. Nothing locks in at start.

## Prop-speed knob = SettingsManager.settings.prop_tick_fraction (a shared tuning knob, so it lives
## in player_settings.gd, not here). Seconds crossing ONE slot = game.get_delay() * that, read LIVE
## every frame. get_delay() is the global delay (settings.base_delay) shrunk under compression — see
## game.gd get_delay + the COMPRESS_RATIO / STEP_MS / SOFT_MS / MIN_FACTOR constants for the ramp-up.

signal tick_done                          ## all visuals reached target AND spawns landed

## Whether the current visual tick is still animating. `tick_done` is a persistent signal, so
## an emission that fires BEFORE the Game reaches its `await` (possible once an events-phase
## hook spans frames) would otherwise be missed and hang the await forever. The Game checks
## this through the view seam and only awaits while the tick is genuinely pending — the
## check-then-await is atomic (single-threaded), so no emission can slip between them.
func tick_pending() -> bool:
	return _tick_active

var _visuals : Dictionary[PropData, PropVisual] = {}
## Cards currently HELD RAISED by a prop's JUMP reaction — reset to rest when the last
## jump-holding prop leaves. Only cards a reaction actually animated are ever tracked here:
## props crossing a card with NO reaction must never anim_reset a pose they don't own (that
## stomped the meld-score jump of cards knives merely passed over).
var _reacting : Dictionary[CardData, bool] = {}
## Visuals travelling their void-exit leg: no longer in _visuals (their prop is done) but
## still driven — and re-pinned — every frame by _drive_exiting until they arrive and fade.
var _exiting : Array[PropVisual] = []
var _tick_active : bool = false
## Running spawn count — indexes the formation's points in DETERMINISTIC mode.
var _spawn_index : int = 0

## Debug stepping (GameView's prop-debug buttons): when ON, a finished visual tick HOLDS —
## motion freezes at the tick boundary and `tick_done` is not emitted, which pauses the whole
## run_props loop at its SYNC step — until step() releases exactly one tick. The data layer
## stays one tick ahead as always; this only gates the view/sync side. Turning it OFF
## releases any held tick on the next frame.
var manual_step : bool = false
var _step_queued : bool = false

## Release one held tick (pressing mid-animation queues the release for when the tick lands).
func step() -> void:
	_step_queued = true

var play_area : PlayArea
var formation : PropFormation

func _ready() -> void:
	play_area = owner as PlayArea   # the play_area.tscn root
	top_level = false               # ride the scroll container's transform
	formation = get_node_or_null("PropFormation") as PropFormation

func _game() -> Game:
	return CardEnvironment.get_current_game()

## The tick duration, RE-DERIVED every frame — never locked in (see class doc).
func current_tick_seconds() -> float:
	var game := _game()
	return game.get_delay() * SettingsManager.settings.prop_tick_fraction if game else 0.0

func _process(delta: float) -> void:
	# EVERY visual follows the live board every frame — staged trains and mid-leg waits
	# included, whether or not a tick is running — and void exits keep travelling.
	for vis : PropVisual in _visuals.values():
		_repin(vis)
	_drive_exiting(delta)
	if not _tick_active: return
	var secs := current_tick_seconds()
	var all_done := true
	for prop : PropData in _visuals:
		var vis : PropVisual = _visuals[prop]
		# A leg spans span_ticks data ticks (ticks_per_slot) — slow props move continuously
		# across all of them; the tick is over once t reaches THIS tick's ratcheted t_goal.
		var span := secs * vis.span_ticks
		vis.t += (delta / span) if span > 0.0 else 1.0   # secs == 0 -> snap (compression floor)
		if manual_step:
			vis.t = minf(vis.t, vis.t_goal)   # freeze exactly at the tick boundary while held
		vis.position = vis.travel_curve(vis.from, vis.target, minf(vis.t, 1.0))
		if vis.t < vis.t_goal: all_done = false
	if all_done:
		if manual_step and not _step_queued:
			return                       # hold the finished tick open until step()
		_step_queued = false
		_tick_active = false
		tick_done.emit()                 # a visual tick is never shorter than one frame

## Follow the live board: shift this visual's whole leg (from/target/position) by however much
## its anchor slot's point moved since last frame. Container relayouts — score labels growing
## as lines bank points, focus resizing rows, rebuilds — move slot centers mid-flight, and
## geometry locked to stale pixels walks a diagonal off its row (owner reports 2026-07-12,
## worst visibly OFF-BOARD where staged/void points had no live slot to follow).
func _repin(vis: PropVisual) -> void:
	if vis.anchor_coord == Vector3i.MIN or not play_area: return
	var live_global := play_area.slot_center_global(vis.anchor_coord)
	if live_global == Vector2.ZERO: return   # slot vanished mid-flight; hold last pixels
	var live := to_local(live_global)
	if live.is_equal_approx(vis.anchor_point): return
	var shift := live - vis.anchor_point
	vis.from += shift
	vis.target += shift
	vis.position += shift
	vis.anchor_point = live

## Void exits travel through the SAME leg drive as every other move (same travel_curve, same
## live-tick timing, re-pinned to their last slot each frame) — independent of _tick_active so
## a run-final exit still completes. They used to be fixed-pixel tweens, which drifted
## diagonally whenever the board re-laid out mid-exit. Arrival hands off to a short fade+free.
func _drive_exiting(delta: float) -> void:
	for i : int in range(_exiting.size() - 1, -1, -1):
		var vis := _exiting[i]
		if not is_instance_valid(vis):
			_exiting.remove_at(i)
			continue
		_repin(vis)
		var span := current_tick_seconds() * vis.span_ticks
		vis.t += (delta / span) if span > 0.0 else 1.0
		vis.position = vis.travel_curve(vis.from, vis.target, minf(vis.t, 1.0))
		if vis.t >= 1.0:
			_exiting.remove_at(i)
			var tw := vis.create_tween()
			tw.tween_property(vis, "modulate:a", 0.0, 0.15)
			tw.tween_callback(vis.queue_free)

## Start ONE data tick's animation and return immediately; the Game runs the events phase in
## parallel and awaits `tick_done` afterwards (§1.3 SYNC). `live` = all live props (post-move),
## `spawned` = props emitted this tick, `movers` = props that entered a new slot, `relocated` =
## [prop, from, to] teleport records (blink, never lerp).
func begin_prop_tick(live: Array, spawned: Array, movers: Array, relocated: Array) -> Signal:
	if play_area: play_area.flush_rebuild()
	# Mid-leg props (ticks_per_slot > 1) keep travelling through ticks that bring no new slot:
	# each tick unlocks the next 1/span share of the leg, so motion is continuous instead of
	# sprint-one-tick-then-freeze. The retargets below overwrite this for props that DID move.
	for vis : PropVisual in _visuals.values():
		vis.t_goal = minf(vis.t_goal + 1.0 / vis.span_ticks, 1.0)
	for prop : PropData in spawned:
		var origin : Vector3i = prop.at if prop.at != Vector3i.MIN else _spawn_origin_of(prop)
		var vis := _make_visual(prop, Vector2.ZERO)
		# Personal spread offset (PropFormation points), applied to every slot point this prop
		# travels through — a batch fans into a staggered volley, not a single-file line.
		vis.lane_offset = formation.offset_for(_spawn_index) if formation else Vector2.ZERO
		_spawn_index += 1
		# Appear directly AT the staged spot — no pop-out-of-the-card flight. The earlier
		# card->staging leg made row props visibly shoot to one end and REVERSE (owner report
		# 2026-07-12); a burst now just materializes as a train behind its row entry.
		var staged := _staged_point(prop, origin) + vis.lane_offset
		vis.position = staged
		vis.exits_into_void = prop.route.size() >= 2   # capture NOW; the route pops as it moves
		vis.retarget(staged)
		# Staged pixels hang off the route entry (or the origin card) so _repin keeps the
		# whole off-board train riding the board through relayouts.
		var anchor : Vector3i = prop.route[0] if prop.route.size() >= 2 else origin
		if anchor != Vector3i.MIN:
			vis.anchor_coord = anchor
			vis.anchor_point = _slot_point(anchor)
		if vis.face_travel and prop.route.size() >= 2:
			# Point directional art down the travel axis from the start (retarget only
			# rotates on a real move, and the staged pose is stationary).
			var dir := _slot_point(prop.route[1]) - _slot_point(prop.route[0])
			if dir.length() > 1.0: vis.rotation = dir.angle()
	for entry: Array in relocated:
		var moved : PropData = entry[0]
		if moved in _visuals:
			var vis : PropVisual = _visuals[moved]
			vis.relocate_to(_slot_point(moved.at) + vis.lane_offset)
			vis.anchor_coord = moved.at   # keep pinned to the slot through relayouts
			vis.anchor_point = _slot_point(moved.at)
	for prop: PropData in movers:
		if prop in _visuals:
			var vis : PropVisual = _visuals[prop]
			vis.retarget(_slot_point(prop.at) + vis.lane_offset, float(prop.ticks_per_slot))
			vis.anchor_coord = prop.at    # the leg follows the LIVE slot, not stale pixels
			vis.anchor_point = _slot_point(prop.at)
	# Done props leave THIS tick — void exits move to the _exiting drive (runs independently of
	# `_tick_active`, so a prop finishing on the run's LAST tick still completes its exit;
	# unhandled, that used to strand knives at the board edge), ballistic poofs tween in place.
	for prop: PropData in live:
		if prop.done and prop in _visuals:
			_despawn_visual(prop)
	_update_reactions(live, movers)
	_prune_done(live)
	_tick_active = true
	return tick_done

## Despawn by kind of journey: route travelers exit one slot past the board edge along their
## travel line — as a NORMAL leg through _drive_exiting (same movement code, still re-pinned
## to their last slot; a fixed-pixel tween here drifted diagonally when the board re-laid out
## mid-exit) — then fade; ballistic props POOF in place at their target (continuing along the
## card->target diagonal sent them flying off in seemingly random directions).
func _despawn_visual(prop: PropData) -> void:
	var vis : PropVisual = _visuals[prop]
	_visuals.erase(prop)
	if not is_instance_valid(vis): return
	if vis.exits_into_void:
		# Exit at the prop's own travel speed (span_ticks = its ticks_per_slot), not the base
		# tick — a 2-ticks-per-slot knife despawning at double speed read as blinking out early.
		vis.retarget(_void_point_of(vis), maxf(vis.span_ticks, 1.0))
		_exiting.append(vis)
	else:
		var tw := vis.create_tween()
		tw.tween_property(vis, "scale", Vector2.ONE * 1.5, 0.12)
		tw.parallel().tween_property(vis, "modulate:a", 0.0, 0.12)
		tw.tween_callback(vis.queue_free)

# --- visual lifecycle ---------------------------------------------------------

func _make_visual(prop: PropData, at: Vector2) -> PropVisual:
	# kind: 0 hoop 1 knife 2 ball 3 fire 4 firework
	var vis : PropVisual
	match prop.kind:
		1: vis = KnifeVisual.new()
		2: vis = BallVisual.new()
		3: vis = FireVisual.new()
		4: vis = FireworkVisual.new()
		_: vis = HoopVisual.new()
	vis.fire_tips = prop.fire_stacks
	vis.position = at
	add_child(vis)
	_visuals[prop] = vis
	return vis

## Fade + free any visual whose prop is no longer live. Done props stay one extra tick (they're
## still in `live` with done == true) so they animate INTO the void first, then drop out of
## `live` next tick and get pruned here.
func _prune_done(live: Array) -> void:
	for prop: PropData in _visuals.keys():
		if prop in live: continue
		var vis : PropVisual = _visuals[prop]
		_visuals.erase(prop)
		if is_instance_valid(vis):
			var tw := vis.create_tween()
			tw.tween_property(vis, "modulate:a", 0.0, 0.15)
			tw.tween_callback(vis.queue_free)

# --- coordinate mapping (content-local, scroll-invariant) ---------------------

## Content-local point of any board slot (either zone; direction-agnostic).
func _slot_point(coord: Vector3i) -> Vector2:
	if not play_area or coord == Vector3i.MIN: return Vector2.ZERO
	return to_local(play_area.slot_center_global(coord))

## Where a freshly spawned prop's visual appears. Travelers with a real path (route >= 2
## slots) stage OFF-BOARD behind their entry slot ALONG the travel axis — countdown/
## ticks_per_slot slot-pitches back (plan §4.2's staged train) — so the burst sits ON its
## row/column line and marches in from the edge in ONE direction. Ballistic props (single
## target) appear at their source card, lifted a little per countdown so a volley isn't one
## stacked blob.
func _staged_point(prop: PropData, origin: Vector3i) -> Vector2:
	if prop.route.size() >= 2:
		var entry := _slot_point(prop.route[0])
		var dir := _slot_point(prop.route[1]) - entry
		if dir.length() >= 1.0:
			# COMPRESS the queue to at most ~1.5 pitches behind entry: the ScrollContainer
			# clips at the play-area rect, so a train staged (countdown/tps) pitches deep put
			# whole bursts INVISIBLY off-screen (hoops seemed to never render). Front prop
			# waits 1 pitch out; the rest queue tightly (0.15 pitch apart) behind it.
			var behind_raw := float(prop.countdown) / maxf(float(prop.ticks_per_slot), 1.0)
			var behind := 1.0 + minf((behind_raw - 1.0) * 0.15, 0.5)
			return entry - dir.normalized() * dir.length() * behind
	var stagger := float(maxi(prop.countdown - prop.ticks_per_slot, 0))
	return _slot_point(origin) - Vector2(0.0, stagger * 6.0)

## One extrapolated slot past the board edge along the visual's last travel direction. The
## last leg's own length IS the local slot pitch (row pitch >> the stacked-card row spacing),
## so reuse it — extrapolating a mere card_separation made props look like they vanished ON
## the last card instead of flying off the board.
func _void_point_of(vis: PropVisual) -> Vector2:
	var dir := vis.target - vis.from
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	var pitch := maxf(dir.length(), CardVisual.card_size_play.x)
	return vis.position + dir.normalized() * pitch

func _spawn_origin_of(prop: PropData) -> Vector3i:
	# Props carry `at` once entered; a same-tick spawn hasn't moved, so pop out of the SOURCE
	# CARD (plan §4.2 — the scored suit card bursts its props). The route head is only a
	# fallback: for row props it is the far board edge, and spawning there made every knife
	# of a meld materialize at one edge point instead of at its own card.
	var game := _game()
	if game and prop.source:
		var v : Vector3i = game.find_data_vec3(prop.source)
		if v != Vector3i.MIN: return v
	if not prop.route.is_empty(): return prop.route[0]
	return Vector3i.MIN

# --- card reactions -----------------------------------------------------------

## Reactions fire per ARRIVAL: every mover entering a card plays that prop's reaction hints
## NOW — a train of knives re-spins the talent once per knife (the old rising-edge-on-a-
## boolean showed only the FIRST prop of a streak: owner report 2026-07-13, "cards don't
## reliably spin"). The JUMP pose additionally HOLDS while any jump-hinting prop occupies the
## card and resets when the last leaves. JUGGLE/BURN are one-shots handed to the status
## visuals; they don't drive the jump/spin pose.
func _update_reactions(live: Array, movers: Array) -> void:
	var game := _game()
	if not game or not play_area: return
	# 1. Arrivals: re-trigger the pose per prop (anim_jump/anim_spin restart cleanly).
	for prop: PropData in movers:
		if prop.done or prop.at == Vector3i.MIN: continue
		var card := game.find_vec3_data(prop.at)
		if not card: continue
		var vis : CardVisual = play_area.data_card.get(card)
		if not vis: continue
		for r: PropData.Reaction in prop.reactions_for(card):
			if r == PropData.Reaction.JUMP: vis.anim_jump()
			elif r == PropData.Reaction.SPIN: vis.anim_spin()
	# 2. JUMP occupancy: which cards still have a jump-hinting prop sitting on them.
	var holding : Dictionary[CardData, bool] = {}
	for prop: PropData in live:
		if prop.done or prop.at == Vector3i.MIN: continue
		var card := game.find_vec3_data(prop.at)
		if not card: continue
		if PropData.Reaction.JUMP in prop.reactions_for(card):
			holding[card] = true
	# 3. Cards whose last jump-holder left return to rest. ONLY tracked (prop-raised) cards
	#    are ever reset — never a pose someone else (the meld-score jump) owns.
	for card: CardData in _reacting.keys():
		if card in holding: continue
		var vis : CardVisual = play_area.data_card.get(card)
		if vis: vis.anim_reset()
		_reacting.erase(card)
	for card: CardData in holding:
		_reacting[card] = true
