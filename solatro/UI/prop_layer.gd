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
## game.gd get_delay + the PlayerSettings compress_* knobs for the ramp-up.

signal tick_done                          ## all visuals reached target AND spawns landed

## Whether the current visual tick is still animating. `tick_done` is a persistent signal, so
## an emission that fires BEFORE the Game reaches its `await` (possible once an events-phase
## hook spans frames) would otherwise be missed and hang the await forever. The Game checks
## this through the view seam and only awaits while the tick is genuinely pending — the
## check-then-await is atomic (single-threaded), so no emission can slip between them.
func tick_pending() -> bool:
	return _tick_active

var _visuals : Dictionary[PropData, PropVisual] = {}
## Cards currently HELD in a prop-driven pose, as bitflags (HOLD_JUMP | HOLD_SPIN): JUMP holds
## while a jump-hinting prop OCCUPIES the card; SPIN loops while any spin-hinting prop is
## still INBOUND (on the card or with it in its remaining route — owner spec 2026-07-13:
## keep spinning until no more are coming, then settle once). Only cards a reaction actually
## animated are ever tracked here: props crossing a card with NO reaction must never reset a
## pose they don't own (that stomped the meld-score jump of cards knives merely passed over).
var _reacting : Dictionary[CardData, int] = {}
const HOLD_JUMP := 1
const HOLD_SPIN := 2
## Visuals travelling their void-exit leg: no longer in _visuals (their prop is done) but
## still driven — and re-pinned — every frame by _drive_exiting until they arrive and fade.
var _exiting : Array[PropVisual] = []
var _tick_active : bool = false
## Running spawn count — folded into each batch's formation seed so batches within one run
## draw DIFFERENT (but replay-identical) formations/point subsets.
var _spawn_index : int = 0
## Per-kind formation sets, lazy-loaded from res://Cards/Props/Formations/<kind>.tres
## (PropFormationSet.load_for_kind). null is a valid cached answer: the kind has no
## formation and flies the exact slot line.
var _formation_sets : Dictionary[int, PropFormationSet] = {}
var _formation_checked : Dictionary[int, bool] = {}

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

func _ready() -> void:
	play_area = owner as PlayArea   # the play_area.tscn root
	top_level = false               # ride the scroll container's transform

## The kind's authored formation set, or null (no formation). Tests may pre-seed
## _formation_sets to exercise assignment without touching the shipped .tres files.
func _formation_set(kind: int) -> PropFormationSet:
	if kind not in _formation_checked and kind not in _formation_sets:
		_formation_sets[kind] = PropFormationSet.load_for_kind(kind)
		_formation_checked[kind] = true
	return _formation_sets.get(kind)

func _game() -> Game:
	return CardEnvironment.get_current_game()

## The tick duration, RE-DERIVED every frame — never locked in (see class doc).
func current_tick_seconds() -> float:
	var game := _game()
	return game.get_delay() * SettingsManager.settings.prop_tick_fraction if game else 0.0

## Seconds for a short prop flourish (fade/poof): a FRACTION of the live get_delay, so every
## animation respects the global pacing and the act compression — nothing runs on a fixed
## wall-clock length (owner spec 2026-07-16).
func _anim_secs(fraction: float) -> float:
	var game := _game()
	return (game.get_delay() if game else SettingsManager.settings.base_delay) * fraction

func _process(delta: float) -> void:
	# EVERY visual follows the live board every frame — staged trains and mid-leg waits
	# included, whether or not a tick is running — and void exits keep travelling. Art scale and
	# formation offsets are LIVE settings reads, like the cards' own sizing (owner 2026-07-15:
	# capture-at-spawn ignored mid-run setting changes). Despawn poofs tween scale themselves,
	# so only live + exiting visuals are written here (poofing ones left _visuals already).
	var art_scale := Vector2.ONE \
			* (SettingsManager.settings.card_scale / PropVisual.AUTHORED_CARD_SCALE)
	for vis : PropVisual in _visuals.values():
		vis.scale = art_scale
		_repin(vis)
		_refresh_lane_offset(vis)
	_update_back_halves()
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
		# A cancelled act must not stay held at a manual-step boundary — the run_props loop is
		# parked on tick_done and the cancel can only unwind once it resumes.
		var game := _game()
		var cancelled := game != null and game.act_cancelled
		if manual_step and not _step_queued and not cancelled:
			return                       # hold the finished tick open until step()
		_step_queued = false
		_tick_active = false
		tick_done.emit()                 # a visual tick is never shorter than one frame

## Bracket every split prop's two halves around the card the ring is VISUALLY over — the
## structural way a card passes THROUGH a hoop (LAYERING.md). Both half nodes live in the STABLE
## CardLayer (never parented to a card, or they would inherit its jump/drag/float); their
## transform + opacity are mirrored from the PROP each frame (the SINGLE fade/scale source).
##
## The bracket ROW is the prop's own ANCHOR SLOT row (vis.anchor_coord — its current leg's
## slot, updated by every retarget/relocate, so reroute modifiers move the bracket with the
## data); GEOMETRY only decides WHETHER to split: the prop's authored BODY rect (body_size) must
## cover some card's footprint. Never guess the row from what's under the prop — fanned cards
## are a full card tall behind their visible strip, so a ring crossing a SHORT column's empty
## row sat "inside" that column's top card's rect and got bracketed to the wrong row, behind the
## zone header (owner report 2026-07-16). Over NO card at all (row edge, off-board, exiting past
## the edge) the halves are HIDDEN and the PropVisual draws the whole ring itself (PropLayer,
## above cards) — stale half ordering once left the ring floating over the board.
func _update_back_halves() -> void:
	if not play_area: return
	for prop : PropData in _visuals:
		var vis : PropVisual = _visuals[prop]
		if not vis.has_back_half(): continue
		_apply_split(vis)
	# Void exits use the same rule: their anchor stays their last slot, so the ring keeps its
	# row bracket while crossing the last columns and unsplits once its body clears the board.
	for vis : PropVisual in _exiting:
		if is_instance_valid(vis) and vis.has_back_half():
			_apply_split(vis)
	# Transform/opacity mirror for EVERY split prop child — including fading/exiting ones (still
	# children until freed), so both halves fade together with the prop even after it leaves _visuals.
	# Visibility follows each prop's own _split_active (set above; fading props keep their last state).
	for child in get_children():
		var vis := child as PropVisual
		if not vis: continue
		_mirror_half(vis, vis.back_node, vis._split_active)
		_mirror_half(vis, vis.front_node, vis._split_active)

## True while the prop's BODY rect (body_size, authored per kind like card sizes) overlaps any
## board card's footprint. A center-point test read a ring hanging between two cards as "over
## nothing" (props have width — owner spec 2026-07-16); this is the split's ONLY geometry input.
func _body_over_any_card(vis: PropVisual) -> bool:
	var reach := CardVisual.card_size_play * 0.5 + vis.body_size * 0.5 * vis.scale
	for cvis : CardVisual in play_area.data_card.values():
		if not is_instance_valid(cvis) or cvis.get_parent() != play_area.card_layer: continue
		var d := vis.global_position - cvis.global_position
		if absf(d.x) <= reach.x and absf(d.y) <= reach.y:
			return true
	return false

## Copy the prop's live transform/opacity onto one half node (the single fade/scale source); the
## half is visible only while the prop is splitting (else the PropVisual draws the whole body).
func _mirror_half(vis: PropVisual, half: Node2D, active: bool) -> void:
	if not half or not is_instance_valid(half): return
	if half.get_parent() != play_area.card_layer:
		if half.get_parent(): half.get_parent().remove_child(half)
		play_area.card_layer.add_child(half)
	half.global_position = vis.global_position
	half.rotation = vis.rotation
	half.scale = vis.scale
	half.visible = active and vis.visible
	half.modulate = vis.modulate

## Split the prop when its BODY covers any card (_body_over_any_card) and bracket the halves
## around its ANCHOR SLOT's whole ROW (owner spec 2026-07-16): the back half sits anywhere in
## the gap BEFORE the row's first card — behind every card in the row, above every earlier row,
## and therefore IN FRONT of a short column's fanned card poking down through this row — and the
## front half in the gap AFTER its last card — in front of the whole row, below the rows
## beneath. Row-major CardLayer order keeps a row contiguous, so two move_childs suffice, and
## the result is consistent whether the ring threads a card, straddles a column gap, or crosses
## an empty slot. GUARDED and STABLE: the OK positions are RANGES (the inter-row gaps), so
## several split props on one row coexist without per-frame churn; moves account for the node's
## own removal shifting indexes and converge in ≤2 frames.
func _apply_split(vis: PropVisual) -> void:
	var bounds : Array[int] = []
	if vis.anchor_coord != Vector3i.MIN and _body_over_any_card(vis):
		bounds = _row_bounds(vis.anchor_coord)
	var active := not bounds.is_empty()
	vis.set_split_active(active)
	var back := vis.ensure_back()
	var front := vis.ensure_front()
	if not back or not front: return
	for half : Node2D in [back, front]:
		if half.get_parent() != play_area.card_layer:
			if half.get_parent(): half.get_parent().remove_child(half)
			play_area.card_layer.add_child(half)
	if not active: return
	# BACK in the gap between the previous row's last card and this row's first card.
	var lo := bounds[0]
	var bi := back.get_index()
	if bi <= bounds[2] or bi >= lo:
		play_area.card_layer.move_child(back, (lo - 1) if bi < lo else lo)
	# FRONT in the gap between this row's last card and the next row's first card (bounds
	# re-read — the back move above may have shifted the whole row by one).
	bounds = _row_bounds(vis.anchor_coord)
	if bounds.is_empty(): return
	var hi := bounds[1]
	var fi := front.get_index()
	if fi <= hi or fi >= bounds[3]:
		play_area.card_layer.move_child(front, (hi + 1) if fi > hi else hi)

## The bracket geometry of slot `v`'s row in CardLayer: [row's first card index, row's last card
## index, last card index BEFORE the row, first card index AFTER the row] — i.e. the two
## inter-row gaps _apply_split may place halves in. prev/next default to -1 / child count at the
## board's edges. Empty when the row has no in-layer visuals (nothing to bracket → unsplit).
## Held cards are skipped (they ride lifted at the layer's end and would stretch the row bracket
## over the whole board).
func _row_bounds(v: Vector3i) -> Array[int]:
	var lo := 2147483647
	var hi := -1
	var in_row : Dictionary[Node, bool] = {}
	for rv : CardVisual in play_area.row_card_visuals(v):
		if rv.get_parent() != play_area.card_layer or rv.held: continue
		in_row[rv] = true
		lo = mini(lo, rv.get_index())
		hi = maxi(hi, rv.get_index())
	if hi < 0: return []
	var prev_hi := -1
	var next_lo := play_area.card_layer.get_child_count()
	for child : Node in play_area.card_layer.get_children():
		var cv := child as CardVisual
		if not cv or cv in in_row: continue
		var i := cv.get_index()
		if i < lo: prev_hi = maxi(prev_hi, i)
		elif i > hi: next_lo = mini(next_lo, i)
	return [lo, hi, prev_hi, next_lo]

## Free a split prop's half nodes together with the visual (called from the SAME tween callback
## that frees the prop, so all three disappear on the same frame after fading together via mirror).
func _free_visual(vis: PropVisual) -> void:
	if not is_instance_valid(vis): return
	for half : Node2D in [vis.back_node, vis.front_node]:
		if half and is_instance_valid(half): half.queue_free()
	vis.back_node = null
	vis.front_node = null
	vis.queue_free()

## Follow the live board: shift this visual's whole leg (from/target/position) by however much
## its anchor slot's point moved since last frame. Container relayouts — score labels growing
## as lines bank points, focus resizing rows, rebuilds — move slot centers mid-flight, and
## geometry locked to stale pixels walks a diagonal off its row (owner reports 2026-07-12,
## worst visibly OFF-BOARD where staged/void points had no live slot to follow).
func _repin(vis: PropVisual) -> void:
	if vis.anchor_coord == Vector3i.MIN or not play_area: return
	var live_global := play_area.slot_center_global(vis.anchor_coord)
	if live_global == Vector2.ZERO: return   # defensive only: slot math never returns ZERO now
	var live := to_local(live_global)
	if live.is_equal_approx(vis.anchor_point): return
	var shift := live - vis.anchor_point
	vis.from += shift
	vis.target += shift
	vis.position += shift
	vis.anchor_point = live

## This prop's formation offset in pixels, derived from LIVE settings: the stored point projects
## into the current separation strip (norm_to_strip clamps, so max spread is exactly one card
## even if the separation setting overshoots) and the whole offset scales by the live card_scale.
func _live_lane_offset(vis: PropVisual) -> Vector2:
	if not vis.has_formation_point: return Vector2.ZERO
	var pt := vis.formation_point
	var y := PropFormationSet.norm_to_strip(pt.y, SettingsManager.settings.card_separation_scale) \
			if vis.formation_spread else pt.y
	return Vector2(pt.x, y) * SettingsManager.settings.card_scale

## Follow the live SETTINGS the way _repin follows the live board: re-derive the pixel lane
## offset each frame and shift the whole leg by the delta. Changing card separation mid-run now
## re-spreads formation heights immediately — in lockstep with the cards re-fanning on the same
## settings signal — and changing card scale rescales the offsets (owner report 2026-07-15:
## offsets captured at spawn ignored both).
func _refresh_lane_offset(vis: PropVisual) -> void:
	if not vis.has_formation_point: return
	var live := _live_lane_offset(vis)
	if live.is_equal_approx(vis.lane_offset): return
	var shift := live - vis.lane_offset
	vis.from += shift
	vis.target += shift
	vis.position += shift
	vis.lane_offset = live

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
		vis.scale = Vector2.ONE \
				* (SettingsManager.settings.card_scale / PropVisual.AUTHORED_CARD_SCALE)
		_repin(vis)
		_refresh_lane_offset(vis)
		var span := current_tick_seconds() * vis.span_ticks
		vis.t += (delta / span) if span > 0.0 else 1.0
		vis.position = vis.travel_curve(vis.from, vis.target, minf(vis.t, 1.0))
		if vis.t >= 1.0:
			_exiting.remove_at(i)
			# vis stays a child of this layer through the fade, so _update_back_halves keeps
			# mirroring the fade onto the back node; free both together when it lands.
			var tw := vis.create_tween()
			tw.tween_property(vis, "modulate:a", 0.0,
					_anim_secs(SettingsManager.settings.prop_fade_fraction))
			tw.tween_callback(_free_visual.bind(vis))

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
	var batch_points := _assign_formation_points(spawned)
	for prop : PropData in spawned:
		var origin : Vector3i = prop.at if prop.at != Vector3i.MIN else _spawn_origin_of(prop)
		var vis := _make_visual(prop, Vector2.ZERO)
		# Personal formation point (PropFormationSet, per kind+origin batch), applied to every
		# slot point this prop travels through — a batch reads as a condensed formation, not a
		# single-file line. Stored on the visual in STORED space; the pixel lane_offset is
		# derived from LIVE settings here and every frame after (_refresh_lane_offset). ZERO
		# (exact slot line) for kinds with no authored formation.
		if prop in batch_points:
			var entry : Array = batch_points[prop]
			vis.formation_point = entry[0]
			vis.formation_spread = entry[1]
			vis.has_formation_point = true
		vis.lane_offset = _live_lane_offset(vis)
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

## Cancel path (undo during a resolving act): the simulation stopped mid-run, so no later
## tick will retarget or prune anything — free every visual NOW, drop held poses, and close
## the tick so nothing lingers over the restored board.
func abort_all() -> void:
	for vis : PropVisual in _visuals.values():
		_free_visual(vis)
	_visuals.clear()
	for vis : PropVisual in _exiting:
		_free_visual(vis)
	_exiting.clear()
	# The board rebuild replaces card visuals, but the SPIN loop is an infinite tween — stop
	# held poses explicitly in case a visual survives (rebuild reuse) rather than trust the free.
	for card : CardData in _reacting.keys():
		var vis : CardVisual = play_area.data_card.get(card) if play_area else null
		if vis:
			if _reacting[card] & HOLD_JUMP: vis.anim_reset()
			if _reacting[card] & HOLD_SPIN: vis.anim_spin_stop()
	_reacting.clear()
	_tick_active = false

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
		# The back half stays mirror-pinned through the exit + its final fade (_update_back_halves
		# syncs it while vis is still a child), then frees with vis in _drive_exiting.
		# Exit at the prop's own travel speed (span_ticks = its ticks_per_slot), not the base
		# tick — a 2-ticks-per-slot knife despawning at double speed read as blinking out early.
		vis.retarget(_void_point_of(vis), maxf(vis.span_ticks, 1.0))
		_exiting.append(vis)
	else:
		# Poof in place: scale up + fade. The back node mirrors both (scale+modulate) every frame,
		# then frees with vis — one animation, both halves.
		var poof := _anim_secs(SettingsManager.settings.prop_poof_fraction)
		var tw := vis.create_tween()
		tw.tween_property(vis, "scale", vis.scale * 1.5, poof)
		tw.parallel().tween_property(vis, "modulate:a", 0.0, poof)
		tw.tween_callback(_free_visual.bind(vis))

## Map this tick's spawns onto their kind's formation points. Spawns are batched by
## (kind, origin) — two melds bursting the same kind on one tick each get their OWN
## formation draw. The seed folds in _spawn_index so successive batches in a run vary but
## the whole run replays identically (offsets are view-only; data never sees them).
## Returns each prop's STORED-space point + spread flag ([point, spread]); pixels are derived
## live per frame from settings (_live_lane_offset), never captured here.
func _assign_formation_points(spawned: Array) -> Dictionary[PropData, Array]:
	var out : Dictionary[PropData, Array] = {}
	var batches : Dictionary[String, Array] = {}
	for prop : PropData in spawned:
		var origin : Vector3i = prop.at if prop.at != Vector3i.MIN else _spawn_origin_of(prop)
		var key := "%d|%s" % [prop.kind, origin]
		if key not in batches: batches[key] = []
		(batches[key] as Array).append(prop)
	for key : String in batches:
		var batch : Array = batches[key]
		var kind := (batch[0] as PropData).kind
		# Hoops NEVER take a formation offset (owner spec 2026-07-15): the ring must always thread
		# the card CENTER — the slot point itself — regardless of separation, or the card can't
		# pass through it (TASK 3a). Their lane_offset stays ZERO even if a set is authored.
		if kind == 0: continue
		var fset := _formation_set(kind)
		if fset == null: continue
		var assign := fset.assignment_for(batch.size(), hash(key) ^ hash(_spawn_index))
		var pts : Array[Vector2] = assign["points"]
		var spread : bool = assign["spread"]
		for i : int in batch.size():
			out[batch[i]] = [pts[i], spread]
	_spawn_index += spawned.size()
	return out

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
	# Live art scale from frame one (re-written every frame in _process; see AUTHORED_CARD_SCALE).
	vis.scale = Vector2.ONE * (SettingsManager.settings.card_scale / PropVisual.AUTHORED_CARD_SCALE)
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
			tw.tween_property(vis, "modulate:a", 0.0,
					_anim_secs(SettingsManager.settings.prop_fade_fraction))
			tw.tween_callback(_free_visual.bind(vis))

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

## Reactions run as HELD group animations, not per-prop restarts (owner spec 2026-07-13:
## "keeps spinning until no more is coming"). JUMP: each arrival re-pulses the pose (a train
## re-hops per prop) AND the raised pose holds while any jump-hinting prop OCCUPIES the card.
## SPIN: the card starts a LOOP (CardVisual.anim_spin_start) when the FIRST spin-hinting prop
## arrives over it — never before (owner report 2026-07-14: cards spun at knife spawn) — and
## keeps looping while more spin props still have it in their remaining route, winding down
## once (anim_spin_stop) when the last has passed; individual knives never restart the spin.
## JUGGLE/BURN are one-shots handed to the status visuals; they don't drive poses.
func _update_reactions(live: Array, movers: Array) -> void:
	var game := _game()
	if not game or not play_area: return
	# 1. JUMP arrivals re-pulse per prop (anim_jump restarts cleanly; spin is hold-driven).
	for prop: PropData in movers:
		if prop.done or prop.at == Vector3i.MIN: continue
		var card := game.find_vec3_data(prop.at)
		if not card: continue
		var vis : CardVisual = play_area.data_card.get(card)
		if not vis: continue
		if PropData.Reaction.JUMP in prop.reactions_for(card):
			vis.anim_jump()
	# 2. Holds. JUMP and SPIN both START on occupancy (prop.at over the card — never before
	#    the first prop arrives); SPIN is additionally SUSTAINED, once started, while the card
	#    is still in any spin-hinting prop's remaining route (more are coming: keep turning).
	var holding : Dictionary[CardData, int] = {}
	for prop: PropData in live:
		if prop.done: continue
		if prop.at != Vector3i.MIN:
			var card := game.find_vec3_data(prop.at)
			if card:
				var reactions := prop.reactions_for(card)
				if PropData.Reaction.JUMP in reactions:
					holding[card] = holding.get(card, 0) | HOLD_JUMP
				if PropData.Reaction.SPIN in reactions:
					holding[card] = holding.get(card, 0) | HOLD_SPIN
		for coord : Vector3i in prop.route:
			var card := game.find_vec3_data(coord)
			if card and (_reacting.get(card, 0) & HOLD_SPIN) \
					and PropData.Reaction.SPIN in prop.reactions_for(card):
				holding[card] = holding.get(card, 0) | HOLD_SPIN
	# 3. Start/hold poses. anim_spin_start self-guards: already-spinning cards keep looping.
	for card: CardData in holding:
		if holding[card] & HOLD_SPIN:
			var vis : CardVisual = play_area.data_card.get(card)
			if vis: vis.anim_spin_start()
	# 4. Release only what WE held and only the pose whose hold ended — never a pose someone
	#    else (the meld-score jump) owns.
	for card: CardData in _reacting.keys():
		var was : int = _reacting[card]
		var now : int = holding.get(card, 0)
		var vis : CardVisual = play_area.data_card.get(card)
		if vis:
			if (was & HOLD_JUMP) and not (now & HOLD_JUMP): vis.anim_reset()
			if (was & HOLD_SPIN) and not (now & HOLD_SPIN): vis.anim_spin_stop()
		if now == 0: _reacting.erase(card)
	for card: CardData in holding:
		_reacting[card] = holding[card]
