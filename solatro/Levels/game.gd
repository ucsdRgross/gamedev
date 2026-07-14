extends CardEnvironment
class_name Game
## Headless match-logic layer: the single source of truth that mutates only `state`. Owns NO
## UI — every visual/input/HUD concern lives in the injected [GameView] (see the `view` field).
## Runs a full show with `view == null` (unit-testable with no scene); the view only paces
## animations and mirrors state. Communication: reactive signals (Game -> view, fire-and-forget)
## + dependency injection (view injected into Game; Game awaits the view only for pacing).

signal game_ended
## Emitted when the show fails (goal not met after the final act): the whole run is over.
signal run_lost

## Game -> view reactive signals (fire-and-forget; the view binds these). See GameView.
## Fired whenever `state` is (re)assigned so the view can rebind an old state's signals (N9).
signal state_bound(new_state: GameData)
## processing flipped: the view enables/disables input controls.
signal processing_changed(busy: bool)
## The submit button's label text changed (acts remaining).
signal submit_label_changed(text: String)
## The show finished: the view shows the win/lose screen + a Continue button.
signal show_resolved(won: bool, score: int, goal: int)
## Undo pressed at the win/lose screen: the view dismisses the outcome overlay (the undo of
## the final Submit follows through the normal rebuild path).
signal show_unresolved

#placeholder
@export var deck : Deck = Deck.new()

## The paced/visual view. Optional: every touch is guarded `if view:`, and a null view is the
## entire headless story (data already applied, the visual step is simply skipped). Injected by
## GameView (`game.view = self`); left null in unit tests.
var view : GameView = null

var state : GameData = GameData.new():
	set(value):
		state = value
		#UI/HUD no longer lives here (S1 gone): just announce the swap so the view rebinds
		#the new state's signals and drops the old one's (N9 handled in GameView._bind_state).
		state_bound.emit(value)

var save_history : Array[GameData] = []

## Input lock across an async action. The setter announces flips so the view can disable
## controls; no view polling needed. Guarded so a redundant assignment doesn't re-emit.
var processing : bool = false:
	set(value):
		if processing == value: return
		processing = value
		processing_changed.emit(value)

## A show is exactly this many submits ("acts", DESIGN_DOC §2); the goal check runs
## after the last one.
const MAX_SUBMITS := 3
## Acts used this show — FORWARDS to state.submits_used (GameData) so undo/save snapshots
## rewind it with the board. Callers keep the old Game-level API.
var submits_used : int:
	get: return state.submits_used
	set(value): state.submits_used = value
var _won : bool = false
## The show finished and the win/lose screen is up. Undo in this state dismisses the outcome
## and rewinds the final Submit (show_unresolved). Reset by that undo; a fresh _resolve_game
## sets it again.
var _resolved : bool = false
## Undo pressed while an act (Submit/Next) was still resolving: the in-flight resolution
## fast-forwards (get_delay -> 0, score_line/run_props short-circuit) and the performing
## function restores the pre-act board instead of committing. Reset by _begin_act / restore.
var act_cancelled : bool = false
## True only across the cancellable span of _perform_submit/_perform_next — undo() may only
## request a cancel while the act can still unwind.
var _act_cancellable : bool = false

# --- Elapsed-time compression + runaway event cap (SUIT_PROPS_PLAN §1.6) ---
# Long/looping score cascades (prop chains, echoing triggers) shrink their per-step delay as
# real time elapses so a huge act still resolves, and a hard event count cuts an infinite
# chain outright ("the audience went home"). Normal play is untouched (get_delay only
# compresses while `processing`).
const COMPRESS_RATIO := 0.85
const STEP_MS := 1500.0
const MIN_FACTOR := 0.05
const SOFT_MS := 20000.0
const HARD_CAP := 6000
var act_start_ms : int = 0
var act_calls : int = 0
var act_overrun : bool = false

## Reset the compression clock + event counter at the start of a board action.
func _begin_act() -> void:
	act_start_ms = Time.get_ticks_msec()
	act_calls = 0
	act_overrun = false
	act_cancelled = false

## Count one unit of processing (per mod invoked, per prop slot entry); trip the runaway cap.
func note_processing(weight := 1) -> void:
	act_calls += weight
	if act_calls > HARD_CAP:
		act_overrun = true

## Per-step pacing delay. Normal play returns the base delay untouched; only while a locked
## action is resolving does it shrink toward 0 with elapsed time (read live every frame by the
## view's interpolation, so speed changes apply mid-slot).
func get_delay() -> float:
	# a cancelled act fast-forwards: every remaining animation snaps (read live per frame)
	if act_cancelled:
		return 0.0
	# base returns SettingsManager.settings.base_delay (normal play untouched)
	if not processing:
		return super.get_delay()
	var elapsed := float(Time.get_ticks_msec() - act_start_ms)
	if elapsed > SOFT_MS:
		return 0.0
	return super.get_delay() * maxf(MIN_FACTOR, pow(COMPRESS_RATIO, elapsed / STEP_MS))

#SE1: compare-mod cache stays valid while the same state object is unmutated
func _revision_key() -> Array:
	return [state.get_instance_id(), state.revision]

func get_card_collections() -> Array:
	return [
		state.draw_deck,
		state.upper_zone,
		state.lower_zone,
		state.discard_deck,
		state.upper_zone_type,
		state.lower_zone_type,
		state.rules_deck
	]

func get_rules_collections() -> Array[CardData]:
	return state.rules_deck

func _ready() -> void:
	if not Main.save_info.game_history.is_empty():
		_resume_show()
	else:
		await _start_fresh_show()
	state.print_board()

# A brand new show: build the deck, run the start hook, seed the undo history + disk save.
func _start_fresh_show() -> void:
	# The map node being played sets the fame requirement (RunManager.goal_for).
	state.goal = maxi(Main.save_info.pending_goal, 1)
	submits_used = 0
	_update_submit_label()
	add_deck()
	await run_all_mods(&"on_game_start")
	skill_active_check()
	# Build the initial board GUI now the state is dealt. Needed because PlayArea._ready runs
	# BEFORE this Game exists (the view creates us in its _ready), so PlayArea's own startup
	# setup_gui found no game and skipped the score gutters — including the row buffer control
	# that keeps the play area from shifting when scores first appear. Headless: no-op.
	if view: view.rebuild()
	save_state()          # seed the history with the opening board
	RunManager.save_run() # write it once synchronously so a save exists immediately

# Resume the exact board a quit interrupted: restore the saved undo history, rebuild the
# current runtime state from its top, restore the act count and board UI, and re-sync skill
# active flags WITHOUT re-firing on_active / on_deactive (effects are baked into the state).
func _resume_show() -> void:
	save_history = Main.save_info.game_history
	state = _runtime_state(save_history[-1])
	# AFTER the state swap (submits_used now lives on GameData — assigning before would write
	# into the state being replaced). The run save stays authoritative: snapshots from before
	# the field existed default to 0 and this rescues them.
	submits_used = Main.save_info.game_submits
	_update_submit_label()
	state.revision += 1  # force the play area to rebuild from the restored board
	for data in CardDataIterator.new(self):
		if data.skill:
			data.skill.active = data.skill.is_active()
	# Lock input immediately: the board is restored but must stay untouchable until its visuals
	# (cards AND score gutters) are synced and any interrupted action has replayed. The rest is
	# deferred because the play area hasn't finished its first layout during _ready.
	processing = true
	_resume_after_visuals.call_deferred()

## Deferred tail of resume: sync every board visual from the restored state, then either
## re-show a finished show's outcome, replay an action a quit interrupted, or (plain mid-show
## resume) hand the board back to the player.
func _resume_after_visuals() -> void:
	# headless: no view means no visuals to sync — the state is already restored, so skip
	# straight to the outcome/replay/handoff decision below.
	if view: await view.load_board_visuals()
	print("[resume] board fully loaded: goal=%d total_score=%d submits_used=%d pending_action=%s"
			% [state.goal, state.total_score, submits_used, Main.save_info.pending_action])
	if submits_used >= MAX_SUBMITS:
		_resolve_game()  # fully submitted before the quit — re-show win/lose (input stays locked)
	elif Main.save_info.pending_action != &"":
		await _replay_pending_action(Main.save_info.pending_action)
	else:
		processing = false  # nothing pending — the restored board is live again

## Re-run a board action a quit interrupted mid-resolution (persisted marker). The restored
## board is the exact pre-action board, and these actions are deterministic — scoring has no
## RNG, draws come from the already-ordered draw_deck — so the replay reproduces the original
## outcome. Board visuals are already loaded (see _resume_after_visuals); input stays locked
## throughout (each _perform_* holds processing).
func _replay_pending_action(action: StringName) -> void:
	print("[resume] replaying interrupted action: %s" % action)
	match action:
		&"on_run_scorer": await _perform_submit()
		&"on_next": await _perform_next()

# Rebuild a live runtime GameData from a saveable history snapshot (independent copy with
# modifier backrefs relinked and BigNumber scores rebuilt).
func _runtime_state(snapshot: GameData) -> GameData:
	var s : GameData = snapshot.duplicate_state()
	s.restore_runtime()
	return s

## Command (view-called): the grabbable stack starting at `data`, or [] if nothing grabs (or
## the board is locked). The view shows the grab; the data query + guard live here so no caller
## can start a grab mid-resolution (review N3).
func try_grab(data: CardData) -> Array[CardData]:
	if processing: return []
	return await return_first_data_array_result(&"on_can_grab_stack", data)

## Command (view-called): try to place `stack` onto `target`. Performs the moves + save_state()
## on success and returns whether anything was placed. Guarded so a locked board rejects.
func try_place(stack: Array[CardData], target: CardData) -> bool:
	if processing: return false
	var stacked := await return_first_data_array_result(&"on_can_place_stack", stack, target)
	if stacked:
		var onto_data := target
		for moving_data in stacked:
			move_data_ontop_data(moving_data, onto_data, 1, false)
			onto_data = moving_data
		save_state()
	return not stacked.is_empty()

func add_deck() -> void:
	var saved_rules := Main.save_info.rule_datas
	var saved_deck := Main.save_info.card_datas
	# for testing if data is blank/no saves
	if not saved_rules: saved_rules = self.deck.get_rules()
	if not saved_deck: saved_deck = self.deck.get_deck()
	
	#Array.duplicate(true) shares Resource elements; duplicate_deep actually copies the
	#cards (with modifier backrefs remapped) so play never mutates the save's cards
	state.rules_deck = saved_rules.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for data in state.rules_deck:
		data.stage = CardData.Stage.RULES
	state.draw_deck = saved_deck.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for data in state.draw_deck:
		data.stage = CardData.Stage.DRAW
	shuffle_deck(state.draw_deck)
	state.revision += 1

func shuffle_deck(datas:Array[CardData]) -> void:
	var new_deck : Array[CardData] = []
	datas.shuffle()
	for data in datas:
		new_deck.append(data)
		await run_all_mods(&"on_append", new_deck, data)
	datas.assign(new_deck)
		
## Command (view-called): advance to the next round.
func next() -> void:
	if processing:
		return
	await _perform_next()

## Resolve a Next action: input-zone stacks drop + decks refill (on_next mods), then commit.
## The board is locked (processing) across the async span and the action is persisted as
## pending first, so a quit mid-resolution replays it verbatim on resume.
func _perform_next() -> void:
	processing = true
	_begin_act()
	_begin_action(&"on_next")
	_act_cancellable = true
	await run_all_mods(&"on_next")
	_act_cancellable = false
	if act_cancelled:
		_restore_pre_act_board("cancelled next")
		return
	save_state()
	processing = false
	
## Commit the current board to the undo history and persist. Every committed action calls
## this, so closing the game can't rewind a mistake — undo is the only way back. The push
## is a serialization-ready snapshot; the disk write is queued on a background thread
## (coalesced) so it never hitches (RunManager.request_save). App-exit flush lives in
## RunManager._exit_tree.
func save_state() -> void:
	save_history.append(state.to_saveable())
	if RunManager.run != null:
		RunManager.run.game_history = save_history
		RunManager.run.game_submits = submits_used
		# An action fully committed: nothing is mid-resolution anymore, so drop any replay
		# marker (see _begin_action). Card moves land here too, harmlessly clearing it.
		RunManager.run.pending_action = &""
		RunManager.request_save()

## Persist, BEFORE any awaits, that a board-mutating button began resolving. The marker rides
## the (still pre-action) committed board to disk, so a quit mid-resolution replays the action
## from that board on resume instead of letting the player touch it — closing the app can't
## undo a Submit/Next. Uses the async queue (no main-thread hitch); if the quit beats the
## background write the marker is simply lost and resume falls back to the pre-action board,
## the same accepted tradeoff as any other in-flight action.
func _begin_action(action: StringName) -> void:
	if RunManager.run != null:
		RunManager.run.pending_action = action
		RunManager.run.game_history = save_history
		RunManager.run.game_submits = submits_used
		RunManager.request_save()

## Command (view-called): rewind one committed board. The held-cards guard is the VIEW's job
## (selection state lives there); Game owns the history rewind. Three states:
##   - win/lose screen up (_resolved): dismiss the outcome, then rewind the final Submit.
##   - an act is resolving (_act_cancellable): request a cancel — the act fast-forwards and
##     restores the pre-act board itself (_perform_submit/_perform_next).
##   - otherwise locked (resume load / replay tail): ignored.
func undo() -> void:
	if _resolved:
		_resolved = false
		_won = false
		show_unresolved.emit()
		processing = false
		# fall through: pop the final Submit's committed board below
	elif processing:
		# the restore needs a committed board to return to (always true in a real show —
		# _start_fresh_show seeds history — but bare test fixtures may not have one)
		if _act_cancellable and not save_history.is_empty():
			act_cancelled = true
		return
	if save_history.size() > 1:
		save_history.resize(save_history.size() - 1) # latest saved state will be current scene
		var prev_game_data : GameData = save_history[-1]
		#we need to duplicate here to prevent changing history if we undo to same state in the future
		state = _runtime_state(prev_game_data)
		# The restored snapshot carries its own submits_used — refresh the Submit button label
		# so an undo across a Submit shows the act back (state swap bypasses the setter).
		_update_submit_label()
		# History shrank — persist so the reverted state (not the mistake) is what a quit
		# resumes to. Undo is the sanctioned rewind; closing the game is not.
		if RunManager.run != null:
			RunManager.run.game_history = save_history
			RunManager.run.game_submits = submits_used
			RunManager.request_save()
		if view: view.rebuild()  # headless: state reverted; no board to force-rebuild
		debug_validate("undo")

## Undo pressed while an act was resolving: throw away the partially-resolved state and
## restore the last committed board — the pre-act snapshot save_state pushed (the act itself
## only commits at its END, so history's top IS the board from before the button press).
## Mods kept running against the doomed state through the fast-forward unwind; that is safe
## because the whole GameData is replaced here. Nothing is popped from history.
func _restore_pre_act_board(context: String) -> void:
	act_cancelled = false
	state = _runtime_state(save_history[-1])
	_update_submit_label()
	if RunManager.run != null:
		RunManager.run.pending_action = &""   # nothing is mid-resolution anymore
		RunManager.run.game_history = save_history
		RunManager.run.game_submits = submits_used
		RunManager.request_save()
	if view:
		view.abort_props()   # the simulation stopped mid-run; free its stranded visuals
		view.rebuild()
		view.sync_scores()
	processing = false
	debug_validate(context)

# destination Vector3( 0:1 for upper:lower, row, col)
# Legacy Vector3i entry point — thin adapter over Board.move_stack (review §5).
# Prefer move_data_ontop_data / move_stack for new call sites.
func move_data_to_coord(moving:CardData, dest:Vector3i, cards_in_stack: int = 1, trigger_mods: bool = true) -> void:
	await move_stack(moving, cards_in_stack, Board.anchor_from_coord(state, dest), trigger_mods)

# Anchor-based move (§5.2): Board mutates (or rejects, leaving the board untouched),
# Game fires the mod events afterwards, when the board is already consistent.
func move_stack(moving:CardData, count:int, dest:Board.Anchor, trigger_mods: bool = true) -> void:
	var result := Board.move_stack(state, moving, count, dest)
	if result.code == Board.OK_NOOP:
		return
	if result.code != Board.OK:
		push_warning("move_stack rejected: %s (%s -> %s)" \
				% [Board.ERROR_NAMES[result.code], moving, dest])
		debug_validate("rejected move")
		return
	if trigger_mods:
		#check if conditions match dropping card
		if result.src_x == 0 and result.dest_x == 1:
			await run_all_mods(&"on_card_dropped_on", result.onto, result.stack)
		await run_all_mods(&"on_stack_cards", result.stack)
	debug_validate("move %s -> %s" % [moving, dest])

## Debug-build invariant sweep (ARCHITECTURE_REVIEW.md §5). Report-only.
func debug_validate(context: String) -> void:
	if not OS.is_debug_build(): return
	var violations := state.validate()
	if violations:
		push_warning("state.validate() after %s:\n  %s" % [context, "\n  ".join(violations)])

func move_data_to_data_coords(moving:CardData, dest:CardData, cards_in_stack: int = 1, trigger_mods: bool = true) -> void:
	move_data_to_coord(moving, find_data_vec3(dest), cards_in_stack, trigger_mods)

func move_data_ontop_data(moving:CardData, dest:CardData, cards_in_stack: int = 1, trigger_mods: bool = true) -> void:
	#dest can be a zone header: Board treats OnTop(header) as ColumnStart of its column
	await move_stack(moving, cards_in_stack, Board.Anchor.on_top(dest), trigger_mods)

func find_data_vec3(data:CardData) -> Vector3i:
	var upper_type_index :=  state.upper_zone_type.find(data)
	if upper_type_index > -1: return Vector3i(0,upper_type_index,-1)
	var lower_type_index :=  state.lower_zone_type.find(data)
	if lower_type_index > -1: return Vector3i(1,lower_type_index,-1)
	for col : int in state.upper_zone.size():
		var row := state.upper_zone[col].datas.find(data)
		if row > -1:
			return Vector3i(0,col,row)
	for col : int in state.lower_zone.size():
		var row := state.lower_zone[col].datas.find(data)
		if row > -1:
			return Vector3i(1,col,row)
	return Vector3i.MIN

func find_vec3_data(vec3:Vector3i) -> CardData:
	#explicit bounds checks: Array.get() out of range pushes an engine error (S2)
	var zone := get_zone_from_vec3(vec3)
	if vec3.y < 0 or vec3.y >= zone.size(): return null
	var col : ArrayCardData = zone[vec3.y]
	if not col: return null
	if vec3.z > -1 and vec3.z < col.datas.size(): return col.datas[vec3.z]
	return null

func get_zone_from_vec3(vec3 : Vector3i) -> Array[ArrayCardData]:
	if vec3.x == 0: return state.upper_zone 
	return state.lower_zone 
	
func is_data_topmost(data:CardData) -> bool:
	# zone/type header cards are topmost exactly when their column is empty
	var col : int = state.upper_zone_type.find(data)
	if col >= 0 and col < state.upper_zone.size():
		return state.upper_zone[col].datas.size() == 0
	col = state.lower_zone_type.find(data)
	if col >= 0 and col < state.lower_zone.size():
		return state.lower_zone[col].datas.size() == 0
	var vec3 := find_data_vec3(data)
	if vec3 == Vector3i.MIN: return false
	var zone := get_zone_from_vec3(vec3)
	if vec3.y < 0 or vec3.y >= zone.size(): return false
	var zone_col : ArrayCardData = zone[vec3.y]
	if not zone_col or zone_col.datas.is_empty(): return false
	return data == zone_col.datas[-1]

#spawns new CARD where deck is
func draw_card() -> CardData:
	if state.draw_deck.size() > 0:
		var data : CardData = state.draw_deck.pop_back()
		data.stage = CardData.Stage.PLAY
		state.revision += 1
		return data
	return null

## Command (view-called): perform a Submit act.
func submit() -> void:
	if processing:
		return
	await _perform_submit()

## Resolve a Submit act: run the scorer, bank the row×col payout, clear the lower board, then
## continue or resolve the show. Locked (processing) across the async scoring and persisted as
## pending first, so a quit mid-scoring replays from the pre-submit board on resume (the player
## can't rewind a Submit by killing the app).
func _perform_submit() -> void:
	processing = true
	_begin_act()
	_begin_action(&"on_run_scorer")
	_act_cancellable = true
	await run_all_mods(&"on_run_scorer")
	_act_cancellable = false
	if act_cancelled:
		_restore_pre_act_board("cancelled submit")
		return
	state.apply_act_score()
	# apply_act_score cleared the gutters — resync the labels (headless: no gutters to sync)
	if view: view.sync_scores()
	state.discard_lower_board()
	submits_used += 1  # bump BEFORE save_state so the persisted act count matches the board
	_update_submit_label()
	save_state()
	if submits_used >= MAX_SUBMITS:
		_resolve_game()
		return  # processing stays true: the show is over, no more input
	processing = false

func _update_submit_label() -> void:
	submit_label_changed.emit("Submit (%d act%s left)" \
			% [MAX_SUBMITS - submits_used, "" if MAX_SUBMITS - submits_used == 1 else "s"])

## All acts performed: win if the fame requirement was reached. The view shows the win/lose
## screen + Continue button and calls exit_show(). Fame is NOT banked here — the outcome
## stays undoable until the player commits via Continue (and a quit at the win screen can't
## double-bank on the resume re-show, which calls this again).
func _resolve_game() -> void:
	_won = state.has_met_goal()
	_resolved = true
	show_resolved.emit(_won, state.total_score, state.goal)

# Leave the show (view-called from Continue): won games bank the fame (FULL score incl.
# overscore) and hand back to the map, lost games end the run.
func exit_show() -> void:
	if _won:
		RunManager.record_win(state.total_score, state.goal)
		return_to_map()
	else:
		run_lost.emit()

func discard_data(data: CardData) -> void:
	await run_all_mods(&"on_discard", data)
	var vec3 := find_data_vec3(data)
	#off-board cards (e.g. a column ZoneAdder already popped) skip the zone erase
	if vec3 != Vector3i.MIN and vec3.z > -1:
		get_zone_from_vec3(vec3)[vec3.y].datas.erase(data)
	state.discard_deck.append(data)
	data.stage = CardData.Stage.DISCARD
	state.revision += 1

func return_to_map() -> void:
	await run_all_mods(&"on_game_end")
	#sweep cards still on the board back into the deck (zone/type cards stay with their skills)
	for zone : Array[ArrayCardData] in [state.upper_zone, state.lower_zone]:
		for col in zone:
			state.draw_deck.append_array(col.datas)
			col.datas.clear()
	state.draw_deck.append_array(state.discard_deck)
	state.discard_deck.clear()
	for data in state.draw_deck:
		data.stage = CardData.Stage.DRAW
	state.revision += 1
	Main.save_info.card_datas = state.draw_deck
	RunManager.mark_deck_dirty()  # the run deck changed (board swept back in)
	# The show is over — drop the undo history so Continue won't re-enter this game.
	Main.save_info.game_history = [] as Array[GameData]
	Main.save_info.game_submits = 0
	game_ended.emit()

func resize_score_zone(score_zone:Array[BigNumber], size:int) -> void:
	if score_zone.size() < size: score_zone.resize(size)
	for i in score_zone.size():
		if not score_zone[i]: 
			score_zone[i] = BigNumber.new()
			score_zone[i].mantissa = 0

## Score one row or column (E7: unifies the old score_row/score_col). Data mutation (row/col
## total, BigNumber gutter accumulation) always runs; the visuals are paced through the view and
## simply skipped when headless. `zone` is only read for rows (upper vs lower gutter) — pass the
## upper/lower zone array; it is ignored for columns.
func score_line(result : Scoring.Result, is_row : bool, zone : Array, index : int) -> void:
	# a cancelled act discards its whole state — skip the remaining lines outright
	if act_cancelled: return
	var score_zone : Array[BigNumber]
	if is_row:
		score_zone = state.scores_row_upper if zone == state.upper_zone else state.scores_row_lower
	else:
		score_zone = state.scores_col
	if view: await view.animate_meld(result)
	# THE single line-score write path (shared with prop effects); mutates totals + gutter and
	# animates the label. Must run headless too (feeds the packed save).
	add_line_score(is_row, score_zone, index, result.score)
	if view: await view.show_meld_score(result)
	await _run_score_effects(result)
	if view: view.reset_meld(result)

## Bank `amount` into a row/col gutter + the matching act total; animate the label when a view
## exists. THE single write path for line scores — melds and prop effects both call it.
func add_line_score(is_row: bool, score_zone: Array[BigNumber], index: int, amount: int) -> void:
	resize_score_zone(score_zone, index + 1)
	if is_row:
		state.row_total += amount   # feeds this act's row x col payout (apply_act_score)
	else:
		state.col_total += amount
	var new_score := score_zone[index].plus_equals(amount)
	if view: view.update_line_score(score_zone, index, new_score)

## The row gutter (upper vs lower) a slot coord banks into — prop effects that know only a
## Vector3i use this instead of the zone-array identity check score_line does.
func row_gutter(v: Vector3i) -> Array[BigNumber]:
	return state.scores_row_upper if v.x == 0 else state.scores_row_lower

## Suit-effect phase for one scored meld (SUIT_PROPS_PLAN §1.5). Gather every meld card's suit
## spawners, run the ONE shared prop simulation, then fire the on_score / on_after_score
## broadcast (activates SkillExtraPoint / StampDoubleTrigger / SkillEchoingTrigger — previously
## inert). Fires per meld membership (row + col each), by design. Prop effects only touch
## gutters + card-local statuses, never the zone/deck arrays the outer scorer walks (B10 safe).
func _run_score_effects(result: Scoring.Result) -> void:
	if act_cancelled: return
	var spawners : Array[PropSpawner] = []
	for card in result.meld:
		if card.suit:
			spawners.append_array(card.suit.spawn_props())
	await run_props(spawners)
	for card in result.meld:
		await run_all_mods(&"on_score", card)
	await run_all_mods(&"on_after_score")

# ==============================================================================
# PROP SIMULATION — the tick loop (SUIT_PROPS_PLAN §1.3)
# ==============================================================================
const MAX_TICKS := 2048   # belt-and-braces alongside HARD_CAP for empty-route runaways

## THE prop simulation. Per tick: SPAWN -> MOVE (instant data) -> START the visual tick (not
## awaited) -> EVENTS in parallel with the animation (new-slot props only, 3-phase pass) ->
## FINISH -> await tick completion. The data layer is one step ahead of the visuals (physics
## interpolation); headless (view == null) there is no visual tick, so the WHOLE submit
## resolves in one frame. Deterministic: spawners in spawn order, props in emission order,
## integer ticks. Cut short by act_overrun (runaway cap) or MAX_TICKS.
func run_props(spawners: Array[PropSpawner]) -> void:
	if spawners.is_empty(): return
	var live_props : Array[PropData] = []
	var owner_of : Dictionary = {}   # prop -> its spawner (to release the live slot on finish)
	var tick := 0
	while not live_props.is_empty() or spawners.any(func(s: PropSpawner) -> bool: return s.remaining > 0):
		if act_overrun or act_cancelled or tick >= MAX_TICKS:
			break
		# SPAWN — each due spawner emits up to batch_size, throttled by max_live
		var spawned : Array[PropData] = []
		for sp in spawners:
			if not sp.due(tick): continue
			var emit_count := mini(sp.batch_size, mini(sp.remaining, sp.max_live - sp.live))
			for i in emit_count:
				var p : PropData = sp.factory.call(sp.emitted)
				p.countdown = p.ticks_per_slot + i   # stage the i-th of a batch one tick back
				sp.remaining -= 1
				sp.emitted += 1
				sp.live += 1
				owner_of[p] = sp
				await p.run_mods(&"on_spawned", p, self)
				spawned.append(p)
				live_props.append(p)
		# MOVE — instant, data only; spawn-tick props excluded (no pop-and-teleport)
		var movers : Array[PropData] = []   # props that ENTERED a new slot this tick
		var relocated : Array = []          # (prop, from, to) — view blinks, not tweens
		for p in live_props:
			p.reloc_sink = relocated        # so a hook's teleport() records into this tick
			if p in spawned: continue
			p.countdown -= 1
			if p.countdown > 0: continue    # mid-slot: fires nothing this tick
			if p.route.is_empty():
				p.done = true               # into the void; FINISH handles on_finish
			else:
				p.at = p.route.pop_front()  # route re-read HERE — a hook may have rewritten it
				p.countdown = p.ticks_per_slot
				movers.append(p)
		# START the visual tick — NOT awaited: animation and mods run in parallel
		var tick_done : Signal
		if view: tick_done = view.begin_prop_tick(live_props, spawned, movers, relocated)
		# EVENTS — new-slot props ONLY, in emission order; hooks stay await-light
		for p in movers:
			note_processing()               # per SLOT ENTRY: feeds the runaway cap
			var card := find_vec3_data(p.at)
			if card:                        # slot may have emptied mid-flight
				p.pass_negated = false
				await run_card_mods(card, &"on_prop_passing", p)   # 1: intercept/dodge
				if not p.pass_negated:
					await p.run_mods(&"on_pass_card", p, self, card)  # 2: the effect
				await run_card_mods(card, &"on_prop_passed", p)    # 3: notification
				p.pass_negated = false
		# FINISH — void-arrived props: effect hook, release the spawner slot
		for p in live_props:
			if p.done:
				await p.run_mods(&"on_finish", p, self)
				var sp : PropSpawner = owner_of.get(p)
				if sp: sp.live -= 1
		await skill_active_check()          # once per tick: hooks may flip active states
		# SYNC — tick over when animation AND events are both complete (headless: nothing
		# awaited). tick_done is a persistent signal: if the events phase spanned frames the
		# animation may ALREADY have emitted, so only await while the tick is still pending —
		# awaiting after the emission would hang forever (view.prop_tick_pending doc).
		if view and view.prop_tick_pending(): await tick_done
		live_props = live_props.filter(func(pp: PropData) -> bool: return not pp.done)
		tick += 1

# ==============================================================================
# PATH HELPERS + deterministic sides (SUIT_PROPS_PLAN §1.6) — used by Phase 3 suits
# ==============================================================================

## Replay-stable 50/50 pick for a hoop/knife row side. Hashes only resume-persisted inputs
## (direction affects hook order, so it is data, not RNG).
func entity_side_for_row(v: Vector3i) -> bool:
	return hash([submits_used, save_history.size(), v.x, v.z]) & 1 == 0

## Every slot in v's row (fixed zone x + row z, across columns y), left-to-right or reversed.
func row_slot_path(v: Vector3i, left_to_right: bool) -> Array[Vector3i]:
	var zone := get_zone_from_vec3(v)
	var out : Array[Vector3i] = []
	for col in zone.size():
		out.append(Vector3i(v.x, col, v.z))
	if not left_to_right:
		out.reverse()
	return out

## The remaining slots of coord's row PAST coord in the given direction (exclusive of coord) —
## for mid-flight re-routes (Strongman pushes a prop along a parallel row).
func row_slot_path_from(coord: Vector3i, left_to_right: bool) -> Array[Vector3i]:
	var full := row_slot_path(coord, left_to_right)
	var idx := full.find(coord)
	if idx == -1:
		return full
	return full.slice(idx + 1)

## The slots above v in its column (rows past v toward the far edge). May be EMPTY (v is the
## topmost card) — a firework then banks its column score immediately.
func column_rise_path(v: Vector3i) -> Array[Vector3i]:
	var out : Array[Vector3i] = []
	var col : ArrayCardData = get_zone_from_vec3(v)[v.y]
	for z in range(v.z + 1, col.datas.size()):
		out.append(Vector3i(v.x, v.y, z))
	return out

## Mancala TARGETS for ballistic Ball/Fire: walk below v.z wrapping to the column top,
## collecting `count` eligible cards' coords (each may repeat). Bounded at (count+1) laps so a
## no-eligible-target column terminates. PURE — computed once at spawn.
func mancala_targets(v: Vector3i, count: int, eligible: Callable) -> Array[Vector3i]:
	var out : Array[Vector3i] = []
	var col : ArrayCardData = get_zone_from_vec3(v)[v.y]
	var n := col.datas.size()
	if n == 0 or count <= 0:
		return out
	var pos := v.z
	var steps := 0
	var max_steps := (count + 1) * n
	while out.size() < count and steps < max_steps:
		pos = (pos + 1) % n
		steps += 1
		var coord := Vector3i(v.x, v.y, pos)
		var card := find_vec3_data(coord)
		if card and eligible.call(card):
			out.append(coord)
	return out
