extends Control

const CARD = preload("res://Cards/card.tscn")
const CARD_CONTROL = preload("res://UI/card_control.tscn")
const STANDARD = "Standard"
const NUMERAL = "Numeral"
const suits : Dictionary[String, Dictionary]= {
	STANDARD : {
		"Random" : 0,
		"Clip" : 1,
		"Peak" : 2,
		"Folk" : 3,
		"Seal" : 4
	}
}
const ranks : Dictionary[String, Dictionary]= {
	NUMERAL : {
		"Random" : 0,
		"1" : 1,
		"2" : 2,
		"3" : 3,
		"4" : 4,
		"5" : 5,
		"6" : 6,
		"7" : 7,
		"8" : 8,
		"9" : 9,
		"10" : 10,
		"J" : 11,
		"Q" : 12,
		"K" : 13,
	}
}

@onready var preview_card: Card = $HSplitContainer/Control/Preview/Card
@onready var preview_label: Label = $HSplitContainer/Control/Preview/Label
@onready var flow_container: FlowContainer = %FlowContainer
@onready var rank_option: OptionButton = $HSplitContainer/Control/RankOption
@onready var rank_option_value: OptionButton = $HSplitContainer/Control/RankOptionValue
@onready var suit_option: OptionButton = $HSplitContainer/Control/SuitOption
@onready var suit_option_value: OptionButton = $HSplitContainer/Control/SuitOptionValue
@onready var skill_option: OptionButton = $HSplitContainer/Control/SkillOption
@onready var randomizer_timer: Timer = $HSplitContainer/Control/RandomizerTimer
var skills : Array[CardModifier] = [null]

func _ready() -> void:
	add_mods()
	for suit in suits:
		suit_option.add_item(suit)
	for rank in ranks:
		rank_option.add_item(rank)
	preview_card.add_data(CardData.new())
	rank_option.select(0)
	_on_rank_option_item_selected(0)
	rank_option_value.select(0)
	_on_rank_option_value_item_selected(0)
	suit_option.select(0)
	_on_suit_option_item_selected(0)
	suit_option_value.select(0)
	_on_suit_option_value_item_selected(0)

func new_PipSuit(name:StringName) -> PipSuit:
	match name: 
		STANDARD: return PipSuit.Standard.new()
	return null

func new_PipRank(name:StringName) -> PipRank:
	match name: 
		NUMERAL: return PipRank.Numeral.new()
	return null

func add_mods() -> void:
	var name_skill : Dictionary
	for skill in ModsList.skills:
		name_skill[skill.get_str()] = skill
	var names : Array = name_skill.keys()
	var i : int = 0
	for n : String in names:
		skills.append(name_skill[n])
		skill_option.add_item(n)

func _on_add_card_pressed() -> void:
	var data : CardData = preview_card.data.duplicate_deep()
	if rank_option_value.get_selected_id() == 0:
		data.rank.with_random()
	if suit_option_value.get_selected_id() == 0:
		data.suit.with_random()
	#if skill_option.get_selected_id() == 1:
		#preview_card.data.with_skill(skills.pick_random() as CardModifier)
	add_card(data)

func add_card(data:CardData) -> void:
	var card : Card = CARD.instantiate()
	card.add_data(data)
	card.can_move_anim = false
	card.flipped = false
	var control : Control = CARD_CONTROL.instantiate()
	control.add_child(card)
	flow_container.add_child(control)

func _on_suit_option_item_selected(index: int) -> void:
	suit_option_value.clear()
	for value : String in suits[suit_option.get_item_text(index)]:
		suit_option_value.add_item(value, suits[suit_option.get_item_text(index)][value] as int)

func _on_suit_option_value_item_selected(index: int) -> void:
	if suit_option_value.get_item_id(index) == 0:
		preview_card.data.with_suit(\
			new_PipSuit(suit_option.get_item_text(suit_option.get_selected_id()))\
			.with_random())
		randomizer_timer.start()
	else:
		preview_card.data.with_suit(\
			new_PipSuit(suit_option.get_item_text(suit_option.get_selected_id()))\
			.with_value(suit_option_value.get_item_id(index)))

func _on_rank_option_item_selected(index: int) -> void:
	rank_option_value.clear()
	for value : String in ranks[rank_option.get_item_text(index)]:
		rank_option_value.add_item(value, ranks[rank_option.get_item_text(index)][value] as int)

func _on_rank_option_value_item_selected(index: int) -> void:
	if rank_option_value.get_item_id(index) == 0:
		preview_card.data.with_rank(\
			new_PipRank(rank_option.get_item_text(rank_option.get_selected_id())) \
			.with_random())
		randomizer_timer.start()
	else:
		preview_card.data.with_rank(\
			new_PipRank(rank_option.get_item_text(rank_option.get_selected_id())) \
			.with_value(rank_option_value.get_item_id(index)))

func _on_skill_option_item_selected(index: int) -> void:
	if index == 0:
		preview_card.data.with_skill(null)
	elif index == 1:
		randomizer_timer.start()
	else:
		preview_card.data.with_skill(skills[index-1])

func _on_randomizer_timer_timeout() -> void:
	if rank_option_value.get_selected_id() == 0:
		preview_card.data.rank.with_random()
		randomizer_timer.start()
	if suit_option_value.get_selected_id() == 0:
		preview_card.data.suit.with_random()
		randomizer_timer.start()
	#if skill_option.get_selected_id() == 1:
		#preview_card.data.with_skill(skills.pick_random() as CardModifier)
		#randomizer_timer.start()


func _on_save_button_pressed() -> void:
	var profile : PlayerSave = PlayerSave.new()
	for card_control : Control in flow_container.get_children():
		var data := (card_control.get_child(0) as Card).data
		profile.write_card_data(data)
	assert(ResourceSaver.save(profile, "user://soltaro_save.tres") == OK)
	print(ProjectSettings.globalize_path("user://soltaro_save.tres"))

func _on_load_button_pressed() -> void:
	for child in flow_container.get_children():
		child.queue_free()
	if ResourceLoader.exists("user://soltaro_save.tres"):
		#@warning_ignore("untyped_declaration")
		var profile : PlayerSave = ResourceLoader.load("user://soltaro_save.tres", "PlayerSave")
		for data : CardData in (profile as PlayerSave).read_card_data():
			add_card(data)
