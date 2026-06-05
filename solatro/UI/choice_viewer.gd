class_name ChoiceViewer
extends Control

const CHOICE_VIEWER := preload("uid://dchj5yt177k0c")

@onready var flex_container: FlexContainer = $FlexContainer

var create_one_choice : Callable
var rerolls : int
var choose : int

static func add_to_scene(parent:Node, create_one:Callable, choices:int, choose:int=0) -> ChoiceViewer:
	var choice_viewer : ChoiceViewer = CHOICE_VIEWER.instantiate()
	parent.add_child(choice_viewer)
	choice_viewer.create_one_choice = create_one
	choice_viewer.choose = choose
	return choice_viewer
