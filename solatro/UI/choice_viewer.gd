class_name ChoiceViewer
extends Control

## Modal viewer for pack-opening: shows the generated cards over a dimmed backdrop.
## choose == 0 is the wired take-all mode ("Take all" force-adds every card via the
## `confirmed` signal); Data.rerolls/choose stay as plumbing for future choice modifiers.
## Cards are populated one frame after entering the tree so the container is laid out
## before the CardVisuals anchor (otherwise the first card flies in from the origin).
## Hovering/focusing a card explains its parts in the %CardInfo inspector label.

## Fired when the player accepts the shown cards; the viewer frees itself afterwards.
signal confirmed(cards: Array[CardData])

const CHOICE_VIEWER := preload("uid://dchj5yt177k0c")

@onready var flex_container: FlexContainer = $FlexContainer
@onready var confirm_button: Button = %ConfirmButton
@onready var card_info: Label = %CardInfo

var data : Data = null

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
	choice_viewer.data = data
	parent.add_child(choice_viewer)
	return choice_viewer

func _ready() -> void:
	# ui_accept confirms immediately; arrow keys walk the (focusable) cards.
	confirm_button.grab_focus()
	_populate.call_deferred()

func _populate() -> void:
	for card in data.current_choices:
		var control := ControlCard.add_child_control_card(
			flex_container, card, CardVisual.DisplayContext.DECK_VIEWER)
		control.mouse_entered.connect(_on_card_inspected.bind(card))
		control.focus_entered.connect(_on_card_inspected.bind(card))

## Inspector: explain the hovered/focused card's parts using their own descriptions.
func _on_card_inspected(card: CardData) -> void:
	card_info.text = ControlCard.describe_card(card)
	card_info.visible = not card_info.text.is_empty()

func _on_confirm_pressed() -> void:
	confirmed.emit(data.current_choices)
	queue_free()
