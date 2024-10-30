extends Control

const CARD = preload("res://Cards/card.tscn")
const CARD_CONTROL = preload("res://UI/card_control.tscn")

@onready var preview_card: Card = $HSplitContainer/Control/Preview/Card
@onready var preview_label: Label = $HSplitContainer/Control/Preview/Label
@onready var flow_container: FlowContainer = %FlowContainer
@onready var rank_option: OptionButton = $HSplitContainer/Control/RankOption
@onready var suit_option: OptionButton = $HSplitContainer/Control/SuitOption
@onready var skill_option: OptionButton = $HSplitContainer/Control/SkillOption
@onready var randomizer_timer: Timer = $HSplitContainer/Control/RandomizerTimer
var skills : Array[CardModifier] = [null]

func _ready() -> void:
	add_mods()
	preview_card.add_data(CardData.new().with_rank(1))
	rank_option.select(0)
	_on_rank_option_item_selected(0)
	suit_option.select(0)
	_on_suit_option_item_selected(0)

func add_mods() -> void:
	var name_skill : Dictionary
	for skill in ModsList.skills:
		name_skill[skill.name] = skill
	var names : Array = name_skill.keys()
	var i : int = 0
	for n : String in names:
		skills.append(name_skill[n])
		skill_option.add_item(n)

func _on_add_card_pressed() -> void:
	var data := preview_card.data.clone(true)
	if rank_option.get_selected_id() == 0:
		data.with_rank(randi() % 13 + 1)
	if suit_option.get_selected_id() == 0:
		data.with_suit(randi() % 4 + 1)
	if skill_option.get_selected_id() == 1:
		preview_card.data.with_skill(skills.pick_random() as CardModifier)
	add_card(data)

func add_card(data:CardData) -> void:
	var card : Card = CARD.instantiate()
	card.add_data(data)			
	card.can_move_anim = false
	card.flipped = false
	var control : Control = CARD_CONTROL.instantiate()
	control.add_child(card)
	flow_container.add_child(control)

func _on_rank_option_item_selected(index: int) -> void:
	if rank_option.get_item_id(index) == 0:
		randomizer_timer.start()
	else:
		preview_card.data.with_rank(rank_option.get_item_id(index))

func _on_suit_option_item_selected(index: int) -> void:
	if suit_option.get_item_id(index) == 0:
		randomizer_timer.start()
	else:
		preview_card.data.with_suit(suit_option.get_item_id(index))

func _on_skill_option_item_selected(index: int) -> void:
	if index == 0:
		preview_card.data.with_skill(null)
	elif index == 1:
		randomizer_timer.start()
	else:
		preview_card.data.with_skill(skills[index-1])

func _on_randomizer_timer_timeout() -> void:
	if rank_option.get_selected_id() == 0:
		preview_card.data.with_rank(randi() % 13 + 1)
		randomizer_timer.start()
	if suit_option.get_selected_id() == 0:
		preview_card.data.with_suit(randi() % 4 + 1)
		randomizer_timer.start()
	if skill_option.get_selected_id() == 1:
		preview_card.data.with_skill(skills.pick_random() as CardModifier)
		randomizer_timer.start()


func _on_save_button_pressed() -> void:
	var profile : PlayerSave = PlayerSave.new()
	for card_control : Control in flow_container.get_children():
		var data := (card_control.get_child(0) as Card).data
		profile.write_card_data(data)
	assert(ResourceSaver.save(profile, "user://soltaro_save.tres", ResourceSaver.FLAG_BUNDLE_RESOURCES) == OK)
	print(ProjectSettings.globalize_path("user://soltaro_save.tres"))

func _on_load_button_pressed() -> void:
	for child in flow_container.get_children():
		child.queue_free()
	if ResourceLoader.exists("user://soltaro_save.tres"):
		#@warning_ignore("untyped_declaration")
		var profile : PlayerSave = ResourceLoader.load("user://soltaro_save.tres", "PlayerSave")
		print(profile)
		for data : CardData in (profile as PlayerSave).read_card_data():
			add_card(data)
