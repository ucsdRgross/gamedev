extends CardEnvironment
class_name Game

signal game_ended

const TEXT_POPUP = preload("res://UI/text_popup.tscn")

#placeholder
@export var deck : Deck = Deck.new()

var state : GameData = GameData.new():
	set(value):
		if state:
			if state.state_changed.is_connected(_on_state_changed):
				state.state_changed.disconnect(_on_state_changed)
			if state.board_changed.is_connected(_on_board_changed):
				state.board_changed.disconnect(_on_board_changed)
		state = value
		state.state_changed.connect(_on_state_changed)
		state.board_changed.connect(_on_board_changed)
		_on_state_changed()

#board mutated (revision bump) -> rebuild the play area; bumps happen only after the
#state is consistent, so a synchronous rebuild always sees a valid board.
#Guard on play_area (assigned via @onready BEFORE _ready runs), NOT is_node_ready():
#_ready is a coroutine, so is_node_ready() stays false through the whole initial
#deal — which would swallow every startup bump and leave the board blank.
func _on_board_changed() -> void:
	if not play_area: return
	#coalesced: any number of bumps this frame -> one rebuild at end of frame
	play_area.queue_rebuild()

var save_history : Array[GameData] = []

var processing : bool = false

@onready var play_area: PlayArea = %PlayArea
@onready var deck_ui: Control = %Deck
@onready var discard_ui: Control = %Discard
@onready var rules_ui: Control = %Rules
@onready var audio_card_placing: AudioStreamPlayer = %AudioCardPlacing
@onready var audio_card_shake: AudioStreamPlayer = %AudioCardShake
@onready var win_screen: Label = %WinScreen
@onready var lose_screen: Label = %LoseScreen
@onready var undo_button: Button = %Undo

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
	#the declaration default bypasses the state setter (setters only run on later
	#assignments), so the INITIAL state's signals must be wired here by hand
	if not state.state_changed.is_connected(_on_state_changed):
		state.state_changed.connect(_on_state_changed)
	if not state.board_changed.is_connected(_on_board_changed):
		state.board_changed.connect(_on_board_changed)
	undo_button.pressed.connect(undo_pressed)
	play_area.data_selected.connect(on_data_selected)
	state.goal = state.goal * (1.1 ** Main.save_info.layer)
	add_deck()
	await run_all_mods(&"on_game_start")
	skill_active_check()
	save_state()
	state.print_board()

func on_data_selected(data:CardData) -> void:
	if processing: return
	#if already holding cards
	if play_area.selected_cards:
		#do nothing if position unchanged
		if (data == play_area.selected_cards[0]
				or find_data_vec3(data) == find_data_vec3(play_area.selected_cards[0]) - Vector3i(0,0,1)):
			play_area.ungrab_cards()
		#dont place within own stack
		elif data not in play_area.selected_cards:
			#attempt placing cards, do nothing if no result
			var stacked := await return_first_data_array_result(&"on_can_place_stack", play_area.selected_cards, data)
			if stacked:
				var onto_data := data
				for moving_data in stacked:
					move_data_ontop_data(moving_data, onto_data, 1, false)
					onto_data = moving_data
				play_area.ungrab_cards()
				save_state()
	else:
		var grabbed := await return_first_data_array_result(&"on_can_grab_stack", data)
		play_area.grab_cards(grabbed)

func _on_state_changed() -> void:
	if not is_node_ready(): return
	(%Goal/Label as Label).text = str(state.goal)
	(%Total/Label as Label).text = str(state.total_score)
	(%MultScore as Label).text = str(state.mult_score)
	(%MultScore/Col as Label).text = str(state.col_total)
	(%MultScore/Row as Label).text = str(state.row_total)

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
		
func _on_next_pressed() -> void:
	if processing:
		return
	processing = true
	await run_all_mods(&"on_next")
	save_state()
	processing = false
	
func save_state() -> void:
	var duplicated_state : GameData = state.duplicate_state()
	save_history.append(duplicated_state)

func undo_pressed() -> void:
	if processing: return
	if play_area.selected_cards: return
	if save_history.size() > 1:
		save_history.resize(save_history.size() - 1) # latest saved state will be current scene
		var prev_game_data : GameData = save_history[-1]
		#we need to duplicate here to prevent changing history if we undo to same state in the future
		state = prev_game_data.duplicate_state()
		play_area.setup_gui()
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

func _on_submit_pressed() -> void:
	if processing:
		return
	processing = true
	await run_all_mods(&"on_run_scorer")
	save_state()
	processing = false

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
	game_ended.emit()

func resize_score_zone(score_zone:Array[BigNumber], size:int) -> void:
	if score_zone.size() < size: score_zone.resize(size)
	for i in score_zone.size():
		if not score_zone[i]: 
			score_zone[i] = BigNumber.new()
			score_zone[i].mantissa = 0

func score_row(result : Scoring.Result, zone:Array, row : int) -> void:
	var score_zone : Array[BigNumber] = state.scores_row_lower
	if zone == state.upper_zone:
		score_zone = state.scores_row_upper
	resize_score_zone(score_zone, row + 1)
	await play_area.popup_meld(result)
	play_area.update_score(score_zone, row, score_zone[row].plus_equals(result.score))
	await play_area.popup_score(result)
	#await play trigger score effects
	play_area.reset_meld(result)

func score_col(result : Scoring.Result, col : int) -> void:
	var score_zone : Array[BigNumber] = state.scores_col
	resize_score_zone(score_zone, col + 1)
	await play_area.popup_meld(result)
	play_area.update_score(score_zone, col, score_zone[col].plus_equals(result.score))
	await play_area.popup_score(result)
	#await play trigger score effects
	play_area.reset_meld(result)

func _on_deck_clicked() -> void:
	DeckViewer.show_deck(self, state.draw_deck)

func _on_discard_clicked() -> void:
	DeckViewer.show_deck(self, state.discard_deck)

func _on_rules_clicked() -> void:
	DeckViewer.show_deck(self, state.rules_deck)
