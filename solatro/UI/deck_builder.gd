extends Control

## Deck Maker (owner dev tool): builds card data by hand and saves it to a `PlayerSave` profile.

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

@onready var preview_holder: Control = $HSplitContainer/Control/Preview
@onready var flow_container: FlowContainer = %FlowContainer
@onready var rank_option: OptionButton = $HSplitContainer/Control/RankOption
@onready var rank_option_value: OptionButton = $HSplitContainer/Control/RankOptionValue
@onready var suit_option: OptionButton = $HSplitContainer/Control/SuitOption
@onready var suit_option_value: OptionButton = $HSplitContainer/Control/SuitOptionValue
@onready var skill_option: OptionButton = $HSplitContainer/Control/SkillOption
@onready var randomizer_timer: Timer = $HSplitContainer/Control/RandomizerTimer

## Index-aligned with `skill_option`'s items from index 1; item 0 is "None" and picks `null`.
var skills : Array[CardModifier] = [null]

## The card the option buttons edit -- its visual redraws itself off `CardData.data_changed`.
var preview_data := CardData.new()

func _ready() -> void:
	ControlCard.add_child_control_card(preview_holder, preview_data,
			CardVisual.DisplayContext.DECK_VIEWER)
	add_mods()
	for suit : String in suits:
		suit_option.add_item(suit)
	for rank : String in ranks:
		rank_option.add_item(rank)
	rank_option.select(0)
	_on_rank_option_item_selected(0)
	rank_option_value.select(0)
	_on_rank_option_value_item_selected(0)
	suit_option.select(0)
	_on_suit_option_item_selected(0)
	suit_option_value.select(0)
	_on_suit_option_value_item_selected(0)

func new_PipRank(rank_name: String) -> PipRank:
	match rank_name:
		NUMERAL: return PipRankNumeral.new()
	return null

func add_mods() -> void:
	for skill : CardModifier in ModsList.skills:
		skills.append(skill)
		skill_option.add_item(skill.get_str())

# A copied card's modifier backrefs are WeakRefs, which `duplicate_deep()` does not remap, so the
# copy is relinked before anything reads it.
func _on_add_card_pressed() -> void:
	var data : CardData = preview_data.duplicate_deep()
	GameData.relink_card_backrefs(data)
	if rank_option_value.get_selected_id() == 0:
		data.rank.with_random()
	if suit_option_value.get_selected_id() == 0:
		data.with_suit(PipSuit.random_standard())
	add_card(data)

func add_card(data:CardData) -> void:
	ControlCard.add_child_control_card(flow_container, data,
			CardVisual.DisplayContext.DECK_VIEWER)

func _on_suit_option_item_selected(index: int) -> void:
	suit_option_value.clear()
	for value : String in suits[suit_option.get_item_text(index)]:
		suit_option_value.add_item(value, suits[suit_option.get_item_text(index)][value] as int)

# The suit items' ids are 1-based over `PipSuit.STANDARD`; id 0 is the random entry.
func _on_suit_option_value_item_selected(index: int) -> void:
	if suit_option_value.get_item_id(index) == 0:
		preview_data.with_suit(PipSuit.random_standard())
		randomizer_timer.start()
	else:
		var suit_script : GDScript = PipSuit.STANDARD[suit_option_value.get_item_id(index) - 1]
		preview_data.with_suit(suit_script.new() as PipSuit)

func _on_rank_option_item_selected(index: int) -> void:
	rank_option_value.clear()
	for value : String in ranks[rank_option.get_item_text(index)]:
		rank_option_value.add_item(value, ranks[rank_option.get_item_text(index)][value] as int)

func _on_rank_option_value_item_selected(index: int) -> void:
	if rank_option_value.get_item_id(index) == 0:
		preview_data.with_rank(\
			new_PipRank(rank_option.get_item_text(rank_option.get_selected_id())) \
			.with_random())
		randomizer_timer.start()
	else:
		preview_data.with_rank(\
			new_PipRank(rank_option.get_item_text(rank_option.get_selected_id())) \
			.with_value(rank_option_value.get_item_id(index)))

func _on_skill_option_item_selected(index: int) -> void:
	if index == 0:
		preview_data.with_skill(null)
	elif index == 1:
		randomizer_timer.start()
	else:
		preview_data.with_skill(skills[index-1])

func _on_randomizer_timer_timeout() -> void:
	if rank_option_value.get_selected_id() == 0:
		preview_data.rank.with_random()
		randomizer_timer.start()
	if suit_option_value.get_selected_id() == 0:
		preview_data.with_suit(PipSuit.random_standard())
		randomizer_timer.start()

# ⚠ NEVER WRAP THE SAVE IN `assert()`: release builds strip asserts WITH their side effects, so the
# file would silently never be written in an export.
func _on_save_button_pressed() -> void:
	var profile : PlayerSave = PlayerSave.new()
	for control : ControlCard in flow_container.get_children():
		profile.write_card_data(control.child.data)
	var err := ResourceSaver.save(profile, "user://soltaro_save.tres")
	if err != OK:
		push_error("Deck Maker save failed: %s" % error_string(err))
	print(ProjectSettings.globalize_path("user://soltaro_save.tres"))

func _on_load_button_pressed() -> void:
	for child : Node in flow_container.get_children():
		child.queue_free()
	if ResourceLoader.exists("user://soltaro_save.tres"):
		var profile : PlayerSave = ResourceLoader.load("user://soltaro_save.tres", "PlayerSave")
		for data : CardData in (profile as PlayerSave).read_card_data():
			add_card(data)
