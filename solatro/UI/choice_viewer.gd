class_name ChoiceViewer
extends Control

const CHOICE_VIEWER := preload("uid://dchj5yt177k0c")

@onready var flex_container: FlexContainer = $FlexContainer

class Data:
	var current_choices : Array[CardData]
	var create_one_choice : Callable
	var rerolls : int
	var choose : int

static func add_to_scene(parent:Node, create_one:Callable, choices:int, choose:int=0) -> ChoiceViewer:
	var data := ChoiceViewer.Data.new()
	data.create_one_choice = create_one
	data.choose = choose
	for i in choices:
		var card_data : CardData = create_one.call()
		if card_data: data.current_choices.append(card_data)
	return add_choices_to_scene(parent, data)

static func add_choices_to_scene(parent:Node, data:Data) -> ChoiceViewer:
	var choice_viewer : ChoiceViewer = CHOICE_VIEWER.instantiate()
	for card in data.current_choices:
		ControlCard.add_child_control_card(
			choice_viewer.flex_container,card,CardVisual.DisplayContext.DECK_VIEWER)
	parent.add_child(choice_viewer)
	return choice_viewer
