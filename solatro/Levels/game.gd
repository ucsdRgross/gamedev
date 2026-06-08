extends CardEnvironment
class_name Game

signal game_ended

const TEXT_POPUP = preload("res://UI/text_popup.tscn")

#placeholder
@export var deck : Deck

var state : GameData = GameData.new():
	set(value):
		state = value
		state.state_changed.connect(_on_state_changed)
		_on_state_changed()

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
	undo_button.pressed.connect(undo_pressed)
	play_area.data_selected.connect(on_data_selected)
	state.goal = state.goal * (1.1 ** Main.save_info.layer)
	add_deck()
	save_state()
	state.print_board()

func on_data_selected(data:CardData) -> void:
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
	(%Goal/Label as Label).text = str(state.goal)
	(%Total/Label as Label).text = str(state.total_score)
	(%MultScore as Label).text = str(state.mult_score)
	(%MultScore/Col as Label).text = str(state.col_total)
	(%MultScore/Row as Label).text = str(state.row_total)

func add_deck() -> void:
	var saved_rules := Main.save_info.rule_datas
	var saved_deck := Main.save_info.card_datas
	# for testing if data is blank/no saves
	if not saved_rules: saved_rules = self.deck.rule_datas
	if not saved_deck: saved_deck = self.deck.card_datas
	
	state.rules_deck = saved_rules.duplicate(true)
	for data in state.rules_deck:
		data.stage = CardData.Stage.RULES
	state.draw_deck = saved_deck.duplicate(true)
	for data in state.draw_deck:
		data.stage = CardData.Stage.DRAW
	shuffle_deck(state.draw_deck)

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
	
# destination Vector3( 0:1 for upper:lower, row, col)
func move_data_to_coord(moving:CardData, dest:Vector3i, cards_in_stack: int = 1, trigger_mods: bool = true) -> void:
	var dest_zone := get_zone_from_vec3(dest)
	if not (dest.y < dest_zone.size() and dest.z <= dest_zone[dest.y].datas.size()): 
		print("[WARN] move_data_to_coord destination out of bounds. Given:  ", dest, " But actual is") 
		print("upper: ", state.upper_zone)
		print("lower: ", state.lower_zone)
		assert(false, "This probably shouldn't happen!")
		return
	#find location of moving card and extract
	var moving_vec3 : Vector3i = find_data_vec3(moving)
	#ideally player cannot ever trigger self stacking or useless move via moving stack by hand
	#but if modifiers allow destination within moving stack, then cap stacked cards to before dest card
	var onto_card := find_vec3_data(dest - Vector3i(0,0,1))
	var z_dist : int = -1
	if moving_vec3.x == dest.x and moving_vec3.y == dest.y:
		z_dist = dest.z - moving_vec3.z
	if z_dist > 0 and (z_dist < cards_in_stack or cards_in_stack < 0):
		cards_in_stack = z_dist - 1
	var moving_zone := get_zone_from_vec3(moving_vec3)
	var end : int = moving_vec3.z + cards_in_stack if cards_in_stack > -1 else 2147483647
	var moving_stack : Array[CardData] = moving_zone[moving_vec3.y].datas.slice(moving_vec3.z, end)
	var moving_stack_cutoff : Array[CardData] = moving_zone[moving_vec3.y].datas.slice(end)
	moving_zone[moving_vec3.y].datas.resize(moving_vec3.z)
	moving_zone[moving_vec3.y].datas.append_array(moving_stack_cutoff)
	#need to address destination changing due moving zone changing positions of its column
	if moving_vec3.x == dest.x and moving_vec3.y == dest.y and z_dist > -1: 
		dest.z -= cards_in_stack
	
	#find location of destination and insert
	if dest.z < 0:
		dest_zone[dest.y].datas.append_array(moving_stack)
	else:
		var dest_stack_cutoff : Array[CardData] = dest_zone[dest.y].datas.slice(dest.z)
		dest_zone[dest.y].datas.resize(dest.z)
		dest_zone[dest.y].datas.append_array(moving_stack)
		dest_zone[dest.y].datas.append_array(dest_stack_cutoff)
	
	for data in moving_stack:
		data.stage = CardData.Stage.PLAY
	if trigger_mods:
		#check if conditions match dropping card
		if moving_vec3.x == 0 and dest.x == 1:
			await run_all_mods(&"on_card_dropped_on", onto_card, moving_stack)
		await run_all_mods(&"on_stack_cards", moving_stack)

func move_data_to_data_coords(moving:CardData, dest:CardData, cards_in_stack: int = 1, trigger_mods: bool = true) -> void:
	move_data_to_coord(moving, find_data_vec3(dest), cards_in_stack, trigger_mods)

func move_data_ontop_data(moving:CardData, dest:CardData, cards_in_stack: int = 1, trigger_mods: bool = true) -> void:
	move_data_to_coord(moving, find_data_vec3(dest) + Vector3i(0,0,1), cards_in_stack, trigger_mods)

func find_data_vec3(data:CardData) -> Vector3i:
	var upper_type_index :=  state.upper_zone_type.find(data)
	if upper_type_index > -1: return Vector3(0,upper_type_index,-1)
	var lower_type_index :=  state.lower_zone_type.find(data)
	if lower_type_index > -1: return Vector3(1,lower_type_index,-1)
	for col : int in state.upper_zone_type.size():
		var row := state.upper_zone[col].datas.find(data)
		if row > -1:
			return Vector3(0,col,row)
	for col : int in state.lower_zone.size():
		var row := state.lower_zone[col].datas.find(data)
		if row > -1:
			return Vector3(1,col,row)
	return Vector3i.MIN

func find_vec3_data(vec3:Vector3i) -> CardData:
	var zone := get_zone_from_vec3(vec3)
	var col : ArrayCardData = zone.get(vec3.y)
	if not col: return null
	if vec3.z > -1: return col.datas.get(vec3.z)
	return null

func get_zone_from_vec3(vec3 : Vector3i) -> Array[ArrayCardData]:
	if vec3.x == 0: return state.upper_zone 
	return state.lower_zone 
	
func is_data_topmost(data:CardData) -> bool:
	# check if is type
	var col : int = state.lower_zone_type.find(data)
	# if datas is empty the input card must be topmost
	if col >= 0 and state.lower_zone[col].datas.size() == 0:
		return true
	var vec3 := find_data_vec3(data)
	if vec3 == Vector3i.MIN: return false
	var zone := get_zone_from_vec3(vec3)
	var zone_col : ArrayCardData = zone.get(vec3.y)
	if not zone_col: return false
	if data == zone_col.datas[-1]: return true
	return false

#spawns new CARD where deck is
func draw_card() -> CardData:
	if state.draw_deck.size() > 0:
		var data : CardData = state.draw_deck.pop_back()
		data.stage = CardData.Stage.PLAY
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
	get_zone_from_vec3(vec3)[vec3.y].datas.erase(data)
	state.discard_deck.append(data)
	data.stage = CardData.Stage.DISCARD

func return_to_map() -> void:
	run_all_mods(&"on_game_end")
	state.draw_deck.append_array(state.discard_deck)
	for data in state.draw_deck:
		data.stage = CardData.Stage.DRAW
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
		score_zone = state.scores_row_lower
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
