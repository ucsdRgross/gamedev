class_name CardsViewer
extends RefCounted

## Owns the card-list contents of ONE container Control: instantiates a ControlCard, or a PartIcon for a pack's partial cards, per CardData and (optionally) wires an inspector callback fired on hover AND keyboard/controller focus, plus the one MODAL model every viewer shares: a click sticks the sidebar to a card, a later hover borrows the description only while it lasts, keys never reach the screen beneath, and one cancel unsticks and closes together. Composed into each viewer (DeckViewer / ChoiceViewer / MapHoverPanel) — they differ only in their container and whether they inspect, so the listing logic lives here once, rather than copied per viewer. Composition (not a shared base class): the viewers' scene roots differ (CanvasLayer / Control / PanelContainer), and ControlCard stays singular (one card, not a list).

var _container: Node
var _context: CardVisual.DisplayContext
## The controls currently listed, in order; controls[0] is the natural initial-focus target.
var controls: Array[Control] = []
## The card each listed control stands for, which a key press sticks.
var _data_of : Dictionary[Control, CardData] = {}
## The size of one listed control, which every row and column is measured in.
var item_px : Vector2 = CardVisual.preview_window_px()

func _init(container: Node, context := CardVisual.DisplayContext.DECK_VIEWER) -> void:
	_container = container
	_context = context

## Fill the container with one ControlCard per card. `on_inspect(card)` (optional) fires on hover AND focus. Returns the first card (for initial focus), or null when empty. Call clear() first if repopulating.
func populate(cards: Array[CardData], on_inspect := Callable()) -> ControlCard:
	_on_inspect = on_inspect
	for data : CardData in cards:
		_list(ControlCard.add_child_control_card(_container, data, _context), data)
	return controls[0] if controls else null

## Fill the container with one PartIcon per partial card, grouped by kind under each kind's header, every icon in the one cell the list's parts and labels need; `on_inspect(card)` fires on hover AND focus.
func populate_parts(cards: Array[CardData], on_inspect: Callable) -> void:
	_on_inspect = on_inspect
	var icons : Array[PartIcon] = []
	for kind : StringName in PartIcon.KINDS:
		var group := cards.filter(func(data: CardData) -> bool: return PartIcon.kind_of(data) == kind)
		var header := Label.new()
		header.text = TRANSLATION.find(PartIcon.KINDS[kind])
		_container.add_child(header)
		_headers[header] = group.size()
		for data : CardData in group:
			var icon := PartIcon.add_child_part_icon(_container, data)
			icons.append(icon)
			_list(icon, data)
	var cell := PartIcon.cell_of(icons)
	for icon : PartIcon in icons:
		icon.fit(cell)
	item_px = icons[0].get_combined_minimum_size()

func _list(control: Control, data: CardData) -> void:
	controls.append(control)
	if _on_inspect.is_valid():
		inspect_on_highlight(control, data)

# ⚠ THE BAR NEVER TAKES CARD WIDTH (owner): a scrolling and a still viewer of the same columns are one
# width. The scroll's own rect must reach the window's right edge, its bar in the frame band there.
## Shows `scroll`'s vertical bar only while `scrolls`, in the frame band beside the card gap `card_margin` keeps on the right.
static func bar_in_the_frame(scroll: ScrollContainer, card_margin: MarginContainer, scrolls: bool) -> void:
	var gap := PlayArea.viewer_separation_px()
	var bar := ceili(scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	assert(bar <= gap, "the scrollbar fits the window's frame band")
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS if scrolls \
			else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	card_margin.add_theme_constant_override(&"margin_right", 2 * gap - (bar if scrolls else 0))

## The width `columns` listed cards take side by side with the list's own gap between them: every viewer sizes a row by it.
func row_px(columns: int) -> float:
	var gap := (_container as Control).get_theme_constant(&"h_separation")
	return columns * item_px.x + (columns - 1) * gap

## The height `rows` listed cards take stacked with the list's own gap between them: every viewer sizes its rows by it.
func column_px(rows: int) -> float:
	var gap := (_container as Control).get_theme_constant(&"v_separation")
	return rows * item_px.y + (rows - 1) * gap

## Each group's header in a parts list, to how many parts it heads; empty for a list of cards.
var _headers : Dictionary[Label, int] = {}

# A HEADER ONE ROW WIDE takes a line of its own, so each group starts a row of its own under it and
# the columns stay the card's width.
## Stretches every header across `columns` cells and returns the height the whole list then takes.
func fit_rows(columns: int) -> float:
	if _headers.is_empty(): return column_px(ceili(float(controls.size()) / columns))
	var gap := (_container as Control).get_theme_constant(&"v_separation")
	var rows := 0
	var headers_px := 0.0
	for header : Label in _headers:
		header.custom_minimum_size.x = row_px(columns)
		rows += ceili(float(_headers[header]) / columns)
		headers_px += header.get_combined_minimum_size().y + gap
	return headers_px + column_px(rows)

## The callback `populate()` wired, kept so a list that has been re-sized can publish through it again.
var _on_inspect : Callable = Callable()

## The listed card the highlight last reached; a viewer announces its own close, so nothing else retires it.
var _highlighted : CardData = null

## Wires one listed control's hover, focus AND click -- also the way a control REPLACING one keeps its place in the list wired.
func inspect_on_highlight(control: Control, data: CardData) -> void:
	_data_of[control] = data
	control.mouse_entered.connect(_enter_highlight.bind(data))
	control.mouse_exited.connect(_leave_highlight)
	control.focus_entered.connect(_publish_highlight.bind(data))
	control.gui_input.connect(_on_card_gui_input.bind(data, control))

## The listed card the player CLICKED, or null while none is: what keeps the sidebar on it while the highlight moves on.
var sticky : CardData = null

## A card became the sticky one, or the sticky one was let go -- the sidebar pins and unpins on this.
signal sticky_changed(stuck: bool)

## A navigation key reached the LIST'S OWN EDGE while a card is stuck: the sidebar is the only place left to go, a separate Control tree the neighbour search never crosses.
signal sidebar_requested

## The pointer is on none of the listed cards any more -- the sidebar goes back to whatever is under this list's highlights.
signal highlight_left

## How many listed cards the pointer is inside: a card gives the highlight up only when the last one does.
var _hovering : int = 0

func _enter_highlight(data: CardData) -> void:
	_hovering += 1
	_publish_highlight(data)

# A HOVER OVERRIDES A STUCK CARD ONLY WHILE IT LASTS: the player can read a long description by
# moving off every card, or on into the sidebar, and find the one they clicked still there.
func _leave_highlight() -> void:
	_hovering -= 1
	if _hovering <= 0: highlight_left.emit()

# A CLICK IS WHAT MAKES A DESCRIPTION STAY, and it is taken here so it never reaches the catcher
# behind the list, which reads a click anywhere else as "close". The second button over the stuck
# card lets it go, as a cancel does, and is left to the catcher, so a deck viewer still closes.
func _on_card_gui_input(event: InputEvent, data: CardData, control: Control) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed: return
	if button.button_index == MOUSE_BUTTON_RIGHT and data == sticky: unstick()
	if button.button_index != MOUSE_BUTTON_LEFT: return
	control.accept_event()
	control.grab_focus()
	stick_to(data)

## Pins the sidebar to `data`: it stays the description's subject until it is let go.
func stick_to(data: CardData) -> void:
	sticky = data
	_publish_highlight(data)

## Lets the stuck card go, so the highlight describes whatever it is on again.
func unstick() -> void:
	if sticky == null: return
	sticky = null
	sticky_changed.emit(false)
	if _hovering <= 0: highlight_left.emit()

## What a viewer must do with one input: KEEP takes it from the screen beneath, CLOSE dismisses the viewer, PASS leaves it alone.
enum Modal { PASS, KEEP, CLOSE }

## The navigation actions a viewer's own list walks on, and the ones the screen beneath would otherwise answer.
const NAVIGATION : Array[StringName] = [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]

# ⚠ REACHED ONLY AFTER THE GUI PASS: an arrow that found a focus neighbour inside the list has
# already moved and never arrives, so what is left is an arrow off the list's own EDGE.
func modal_verdict(event: InputEvent) -> Modal:
	if event.is_action_pressed(&"ui_cancel"): return Modal.CLOSE
# ACCEPT IS THE CLICK'S OWN KEY: it sticks the card the focus is on. Reaching here at all means no
# button took it, so it is swallowed either way rather than reaching the map beneath.
	if event.is_action_pressed(&"ui_accept"):
		for control : Control in controls:
			if control.has_focus(): stick_to(_data_of[control])
		return Modal.KEEP
	for action : StringName in NAVIGATION:
		if not event.is_action_pressed(action, true): continue
# ⚠ REACHED FOR A PRESS PUSHED STRAIGHT INTO THIS PICTURE'S OWN VIEWPORT, which never rises to the
# overlay, so the container's earlier hand-over never sees it -- measured on the map's deck viewer.
		if focus_first(): return Modal.KEEP
		if sticky != null:
			_publish_highlight(sticky)
			sidebar_requested.emit()
		return Modal.KEEP
	return Modal.PASS

# Remembered rather than only relayed: a list that has been re-sized owes the description it
# published the same card again. Only the stuck entry carries the X, so the stuck card's fresh
# description is re-stuck rather than shown as a highlight over its own lock.
func _publish_highlight(data: CardData) -> void:
	_highlighted = data
	_on_inspect.call(data)
	if data == sticky: sticky_changed.emit(true)

# HOW A KEY OR PAD PLAYER ENTERS A LIST THAT OPENED WITH NOTHING FOCUSED. Answers whether it took
# the press, so the caller knows whether the screen beneath may still have it.
func focus_first() -> bool:
	if controls.is_empty() or focus_is_inside(): return false
	controls[0].grab_focus()
	return true

## The viewer's own close tab beside the list, or null: an arrow off the list's edge reaches it, so it counts as inside.
var close_tab : Control = null

## Whether a listed card, or the viewer's close tab, holds the keyboard/pad focus: the one test for "the player is navigating inside this list".
func focus_is_inside() -> bool:
	if close_tab and close_tab.has_focus(): return true
	for control : Control in controls:
		if control.has_focus(): return true
	return false

## Publishes the card the highlight is on again -- nothing to say while a freshly built list has not been pointed at yet.
func republish_highlight() -> void:
	if _highlighted: _publish_highlight(_highlighted)

# A SLOT SWAPPED UNDER THE HIGHLIGHT: the pointer never moved, so what it is on now is whatever took
# the slot -- otherwise the description reads the card that is gone until the player moves.
func rehighlight(replaced: CardData, data: CardData) -> void:
	if sticky == replaced: stick_to(data)
	elif _highlighted == replaced: _publish_highlight(data)

## Remove every listed control (before repopulating, or when the viewer hides). Detaches immediately (not just queue_free) so a same-frame repopulate never shows stale cards.
func clear() -> void:
	for control : Control in controls:
		if is_instance_valid(control):
			if control.get_parent():
				control.get_parent().remove_child(control)
			control.queue_free()
	controls.clear()
	_data_of.clear()
