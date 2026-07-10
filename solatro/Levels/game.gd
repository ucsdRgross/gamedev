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
var submits_used : int = 0
var _won : bool = false

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
	submits_used = Main.save_info.game_submits
	state = _runtime_state(save_history[-1])
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
	_begin_action(&"on_next")
	await run_all_mods(&"on_next")
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
## (selection state lives there); Game only guards `processing` and owns the history rewind.
func undo() -> void:
	if processing: return
	if save_history.size() > 1:
		save_history.resize(save_history.size() - 1) # latest saved state will be current scene
		var prev_game_data : GameData = save_history[-1]
		#we need to duplicate here to prevent changing history if we undo to same state in the future
		state = _runtime_state(prev_game_data)
		# History shrank — persist so the reverted state (not the mistake) is what a quit
		# resumes to. Undo is the sanctioned rewind; closing the game is not.
		if RunManager.run != null:
			RunManager.run.game_history = save_history
			RunManager.request_save()
		if view: view.rebuild()  # headless: state reverted; no board to force-rebuild
		debug_validate("undo")
	
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
	_begin_action(&"on_run_scorer")
	await run_all_mods(&"on_run_scorer")
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

## All acts performed: win if the fame requirement was reached. Win feeds fame (FULL score
## incl. overscore); the view shows the win/lose screen + Continue button and calls exit_show().
func _resolve_game() -> void:
	_won = state.has_met_goal()
	if _won:
		RunManager.record_win(state.total_score, state.goal)
	show_resolved.emit(_won, state.total_score, state.goal)

# Leave the show (view-called from Continue): won games hand back to the map, lost games end
# the run.
func exit_show() -> void:
	if _won:
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
	var score_zone : Array[BigNumber]
	if is_row:
		score_zone = state.scores_row_upper if zone == state.upper_zone else state.scores_row_lower
		state.row_total += result.score  # feeds this act's row x col payout (apply_act_score)
	else:
		score_zone = state.scores_col
		state.col_total += result.score
	resize_score_zone(score_zone, index + 1)
	if view: await view.animate_meld(result)
	# plus_equals mutates the gutter accumulator — must run headless too (feeds the packed save)
	var new_score := score_zone[index].plus_equals(result.score)
	if view: view.update_line_score(score_zone, index, new_score)
	if view: await view.show_meld_score(result)
	#await play trigger score effects
	if view: view.reset_meld(result)
