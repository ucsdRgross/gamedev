class_name ChoiceViewer
extends Control

## Modal viewer for pack-opening: shows the generated cards in a square window over its picture, which it keeps inert. choose == 0 is the wired take-all mode ("Take all" force-adds every card via the `confirmed` signal); Data.rerolls/choose stay as plumbing for future choice modifiers. Cards populate synchronously (like DeckViewer) — the no-fly-in guarantee lives in CardVisual (non-PLAY_AREA cards track their anchor exactly), not in per-viewer timing.

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

## The window this viewer draws -- the pack and the chrome around it, so fitting moves them together.
@onready var _layout: Panel = $Layout
## Rerolls left and Take, side by side along the window's foot.
@onready var _bottom_row: HBoxContainer = $Layout/BottomRow

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
## Shared free-reroll pool for the WHOLE pack (any slot may spend it). Seeded from SettingsManager.settings.booster_reroll_pool by BoosterTemplate.on_map_picked.
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
# broadcasts); a plain sync callable resumes immediately
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
	confirm_button.text = TRANSLATION.find('CHOICE_TAKE')
	(_layout.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = 			PaletteDB.color(PaletteDB.ROLES.hud_background)
	confirm_button.grab_focus()
	_populate()

func _populate() -> void:
	_cards = CardsViewer.new(flex_container)
	_cards.populate(data.current_choices, _publish_info)
	_cards.sticky_changed.connect(_follow_the_pick.unbind(1))
	for i in _cards.controls.size():
		_reroll_buttons.append(_add_reroll_button(_cards.controls[i], i))
	_refresh_rerolls()

## Exactly one listed card wears the selection ink: the one the sidebar is stuck to. Its buttons follow, being out of reach while one is.
func _follow_the_pick() -> void:
	for control : ControlCard in _cards.controls:
		control.child.selected = control.child.data == _cards.sticky
	_refresh_rerolls()

## This viewer's listed cards, which carry the modal and sticky model its host wires itself to.
func cards() -> CardsViewer:
	return _cards

# ⚠ THIS PACK CANNOT BE REOPENED ONCE IT IS GONE, so the sidebar's X lets the stuck card go and
# leaves the pack up: Take is the only way to finish it.
func close_from_sidebar() -> void:
	_cards.unstick()

# A cancel reads as a close here as everywhere, and is then SWALLOWED: Take alone finishes this
# pack, so the wall never hears it either.
func _unhandled_input(event: InputEvent) -> void:
	if _stops_at_the_window(event): return
	var verdict := _cards.modal_verdict(event)
	if verdict == CardsViewer.Modal.PASS: return
	if verdict == CardsViewer.Modal.CLOSE: _cards.unstick()
	get_viewport().set_input_as_handled()

# THE WINDOW IS CENTRED IN THE SPACE LEFT BESIDE THE SIDEBAR, never under it. The scale rides
# along, so a re-publish after it is drawn at the size THIS viewer now draws a card.
func fit_beside(remaining: Rect2, window_scale: float) -> void:
	_cards.picture_to_window_scale = window_scale
	var window := remaining
	var side := _square_side()
	if side <= minf(remaining.size.x, remaining.size.y):
		window = Rect2(remaining.get_center() - Vector2.ONE * side / 2.0, Vector2.ONE * side)
	var picture := get_viewport_rect().size
	_layout.offset_left = window.position.x
	_layout.offset_top = window.position.y
	_layout.offset_right = window.end.x - picture.x
	_layout.offset_bottom = window.end.y - picture.y

# The cards sit centred with their Reroll buttons hanging under them and the Rerolls-and-Take row at
# the foot, so the square holds one full row unwrapped with that foot band mirrored above it.
func _square_side() -> float:
	var row := Vector2.ZERO
	for control : ControlCard in _cards.controls.slice(0, SettingsManager.settings.chooser_row_cards):
		var card := control.get_combined_minimum_size()
		row = Vector2(row.x + card.x, maxf(row.y, card.y))
	var foot_band := -_bottom_row.offset_top + REROLL_BUTTON_GAP + REROLL_BUTTON_HEIGHT
	return maxf(row.x + 2.0 * _bottom_row.offset_left, row.y + 2.0 * foot_band)

# ⚠ THE MAP AROUND THE WINDOW STAYS IN VIEW AND ANSWERS NO POINTER: a full-picture STOP control let
# the wheel and the first motion through (measured) and swallowed the wall's pinch, so this viewer
# ignores the pointer and every mouse event stops here -- before the map, in reverse tree order.
func _stops_at_the_window(event: InputEvent) -> bool:
	if not event is InputEventMouse: return false
	get_viewport().set_input_as_handled()
	return true

## Publishes the card its highlight is on again -- asked by the opener only while a description is UP, so one the player dismissed stays dismissed across a re-fit.
func republish_highlight() -> void:
	_cards.republish_highlight()

## One slot's Reroll button, parented to its card and hanging just below it (the flex container lays out the cards only). A focus stop like the card itself — keyboard/controller reach it.
func _add_reroll_button(control: ControlCard, index: int) -> Button:
	var button := Button.new()
	button.text = TRANSLATION.find('CHOICE_REROLL')
	control.add_child(button)
	button.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	button.offset_top = REROLL_BUTTON_GAP
	button.offset_bottom = REROLL_BUTTON_GAP + REROLL_BUTTON_HEIGHT
	button.pressed.connect(func() -> void: await reroll(index))
	return button

## Re-roll ONE shown slot from the same generator that produced it, spending one of the shared pool. Returns false (and changes nothing) when the pool is empty, the index is out of range, or the generator produced nothing. Pure data + a targeted visual swap, so it is testable without driving the buttons.
func reroll(index: int) -> bool:
	if data.rerolls <= 0 or index < 0 or index >= data.current_choices.size():
		return false
# awaited: create_one_choice is a coroutine (BoosterTemplate awaits its pool broadcasts)
	var fresh : CardData = await data.create_one_choice.call()
	if fresh == null:
		return false
	data.current_choices[index] = fresh
	data.rerolls -= 1
	_swap_card_control(index, fresh)
	_refresh_rerolls()
	return true

## Replace only slot `index`'s ControlCard with one showing `card`, keeping its position in the container, its inspector wiring, its Reroll button — and the focus, if it was there.
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

# ⚠ A STICKY DESCRIPTION IS BEING READ, so every button here is out of reach until it is cancelled
# -- pointer and pad alike, or Take fires from under the text the player is still reading.
func _held_by_a_sticky_description() -> bool:
	return _cards.sticky != null

## Update the remaining-rerolls counter and put every button beyond reach that must not be pressed now.
func _refresh_rerolls() -> void:
	if not is_node_ready(): return
	rerolls_label.text = TRANSLATION.find('CHOICE_REROLLS_LEFT') % data.rerolls
	_hold(confirm_button, _held_by_a_sticky_description())
	for button : Button in _reroll_buttons:
		if is_instance_valid(button):
			_hold(button, _held_by_a_sticky_description() or data.rerolls <= 0)

## Puts one button beyond every input mode at once: a disabled button still answers a pad focus, so the focus goes with it.
static func _hold(button: Button, held: bool) -> void:
	button.disabled = held
	button.focus_mode = Control.FOCUS_NONE if held else Control.FOCUS_ALL

# The card the highlight reached, drawn at this viewer's own card size.
func _publish_info(card: CardData) -> void:
	PlayArea.highlight_info(card,
			CardVisual.preview_window_px(_cards.picture_to_window_scale)).relay_to(info_requested)

# Confirming closes this viewer, so it announces the lost highlight the same way the board does: a
# description locked before it opened comes back.
func _on_confirm_pressed() -> void:
	confirmed.emit(data.current_choices)
	queue_free()
	highlight_cleared.emit()
