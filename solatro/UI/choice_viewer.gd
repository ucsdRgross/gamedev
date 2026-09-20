class_name ChoiceViewer
extends Control

## Modal viewer for pack-opening: shows the generated cards over a dimmed backdrop.
## choose == 0 is the wired take-all mode ("Take all" force-adds every card via the
## `confirmed` signal); Data.rerolls/choose stay as plumbing for future choice modifiers.
## Cards populate synchronously (like DeckViewer) — the no-fly-in guarantee lives in
## CardVisual (non-PLAY_AREA cards track their anchor exactly), not in per-viewer timing.

## Fired when the player accepts the shown cards; the viewer frees itself afterwards.
signal confirmed(cards: Array[CardData])

## The card under the pointer, handed to the screen that opened this viewer, which relays it to the sidebar exactly as it relays its own hovers.
signal info_requested(entry: InfoEntry)

## This viewer closed, so nothing of its is highlighted any more and the sidebar returns to whatever was locked behind it.
signal highlight_cleared

const CHOICE_VIEWER := preload("uid://dchj5yt177k0c")

@onready var flex_container: FlexContainer = $Layout/FlexContainer
@onready var confirm_button: Button = %ConfirmButton
@onready var rerolls_label: Label = %RerollsLeft

## Everything this viewer draws over its dimmed backdrop -- the pack and the chrome around it, so fitting moves them together.
@onready var _layout: Control = $Layout

## Reroll button geometry, in pixels below the card it belongs to (no magic numbers in logic).
const REROLL_BUTTON_HEIGHT := 34.0
const REROLL_BUTTON_GAP := 4.0

var data : Data = null
## Owns the listed choice cards (the shared listing logic; see CardsViewer).
var _cards : CardsViewer
## The per-slot Reroll buttons, index-aligned with _cards.controls / data.current_choices.
var _reroll_buttons : Array[Button] = []

class Data:
	var current_choices : Array[CardData]
	var create_one_choice : Callable
	## Shared free-reroll pool for the WHOLE pack (any slot may spend it). Seeded from
	## SettingsManager.settings.booster_reroll_pool by BoosterTemplate.on_map_picked.
	var rerolls : int
	var choose : int

static func add_to_scene(parent:Node, create_one:Callable, choices:int, choose:int=0,
		rerolls:int=0) -> ChoiceViewer:
	var data := ChoiceViewer.Data.new()
	data.create_one_choice = create_one
	data.choose = choose
	data.rerolls = rerolls
	for i in choices:
		# awaited: generators may be coroutines (BoosterTemplate awaits its pool
		# broadcasts, E8); a plain sync callable resumes immediately
		var card_data : CardData = await create_one.call()
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
	_populate()

func _populate() -> void:
	_cards = CardsViewer.new(flex_container)
	_cards.populate(data.current_choices, _publish_info)
	for i in _cards.controls.size():
		_reroll_buttons.append(_add_reroll_button(_cards.controls[i], i))
	_refresh_rerolls()

# ⚠ THIS VIEWER IS A FULL-SCREEN OVERLAY INSIDE ITS PICTURE and would otherwise cover the sidebar,
# so its WHOLE layout -- pack and chrome -- lives in the space left beside it, on ALL FOUR EDGES.
# The scale rides along, so a re-publish after it is drawn at the size THIS viewer now draws a card.
func fit_beside(remaining: Rect2, window_scale: float) -> void:
	_cards.picture_to_window_scale = window_scale
	var picture := get_viewport_rect().size
	_layout.offset_left = remaining.position.x
	_layout.offset_top = remaining.position.y
	_layout.offset_right = remaining.end.x - picture.x
	_layout.offset_bottom = remaining.end.y - picture.y

## Publishes the card its highlight is on again -- asked by the opener only while a description is UP, so one the player dismissed stays dismissed across a re-fit.
func republish_highlight() -> void:
	_cards.republish_highlight()

## One slot's Reroll button, parented to its card and hanging just below it (the flex container
## lays out the cards only). A focus stop like the card itself — keyboard/controller reach it.
func _add_reroll_button(control: ControlCard, index: int) -> Button:
	var button := Button.new()
	button.text = TRANSLATION.find('CHOICE_REROLL')
	control.add_child(button)
	button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	button.offset_top = REROLL_BUTTON_GAP
	button.offset_bottom = REROLL_BUTTON_GAP + REROLL_BUTTON_HEIGHT
	button.pressed.connect(func() -> void: await reroll(index))
	return button

## Re-roll ONE shown slot from the same generator that produced it, spending one of the shared
## pool. Returns false (and changes nothing) when the pool is empty, the index is out of range,
## or the generator produced nothing. Pure data + a targeted visual swap, so it is testable
## without driving the buttons.
func reroll(index: int) -> bool:
	if data.rerolls <= 0 or index < 0 or index >= data.current_choices.size():
		return false
	# awaited: create_one_choice is a coroutine (BoosterTemplate awaits its pool broadcasts, E8)
	var fresh : CardData = await data.create_one_choice.call()
	if fresh == null:
		return false
	data.current_choices[index] = fresh
	data.rerolls -= 1
	_swap_card_control(index, fresh)
	_refresh_rerolls()
	return true

## Replace only slot `index`'s ControlCard with one showing `card`, keeping its position in the
## container, its inspector wiring, its Reroll button — and the focus, if it was there.
func _swap_card_control(index: int, card: CardData) -> void:
	if not is_node_ready() or index >= _cards.controls.size(): return
	var old := _cards.controls[index]
	var replaced : CardData = old.child.data
	var had_focus : bool = _reroll_buttons[index].has_focus()
	flex_container.remove_child(old)
	old.queue_free()
	var control := ControlCard.add_child_control_card(
			flex_container, card, CardVisual.DisplayContext.DECK_VIEWER)
	flex_container.move_child(control, index)
	_cards.inspect_on_highlight(control, card)
	_cards.controls[index] = control
	_cards.rehighlight(replaced, card)
	_reroll_buttons[index] = _add_reroll_button(control, index)
	# Keyboard/controller: the pressed button was just freed — put focus back on its replacement
	# (or on Confirm if this reroll emptied the pool and disabled every button).
	if had_focus:
		if data.rerolls > 0: _reroll_buttons[index].grab_focus()
		else: confirm_button.grab_focus()

## Update the remaining-rerolls counter and gray every button out once the pool is empty.
func _refresh_rerolls() -> void:
	if not is_node_ready(): return
	rerolls_label.text = TRANSLATION.find('CHOICE_REROLLS_LEFT') % data.rerolls
	for button : Button in _reroll_buttons:
		if is_instance_valid(button):
			button.disabled = data.rerolls <= 0

# A HOVER OR A KEY/PAD FOCUS, NEVER A CLICK: a click in this viewer takes the pack, and the lock
# belongs to the board.
func _publish_info(card: CardData) -> void:
	PlayArea.card_info(card, _cards.card_window_px()).relay_to(info_requested)

# Confirming closes this viewer, so it announces the lost highlight the same way the board does: a
# description locked before it opened comes back.
func _on_confirm_pressed() -> void:
	confirmed.emit(data.current_choices)
	highlight_cleared.emit()
	queue_free()
