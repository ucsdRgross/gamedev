class_name DeckViewer
extends CanvasLayer

const DECK_VIEWER = preload("uid://dnvpthmsneqjl")

## The card under the pointer, handed to the screen that opened this viewer, which relays it to the sidebar exactly as it relays the board's own.
signal info_requested(entry: InfoEntry)

## This viewer closed, so nothing of its is highlighted any more and the sidebar returns to whatever was locked behind it.
signal highlight_cleared

@onready var flow_container: FlowContainer = %FlowContainer
@onready var margin_container: MarginContainer = $MarginContainer
@onready var _scroll: ScrollContainer = $MarginContainer/SmoothScrollContainer
## The X tab sticking out of the window's side, closing this viewer alone; its host sizes it to a touch target.
@onready var close_tab: Button = %CloseTab

var deck : Array[CardData]
## Owns this viewer's listed cards (the shared listing logic; see CardsViewer).
var _cards : CardsViewer

# The viewer on top. Opening another replaces it, unless the opener asks to open over it, and a
# viewer opened over another hands the top back to it on close.
static var _open : DeckViewer = null
## The viewer this one opened over, on top again once this one closes.
var _under : DeckViewer = null
# Focus to restore on close, so keyboard/controller users land back on the button that
# opened the viewer instead of nowhere.
var _return_focus : Control = null
## Where the focus goes on close when the opener is hidden; set by the `HudContainer` hosting this viewer.
var fallback_focus : Control = null

# ⚠ OPAQUE, in the sidebar's and the chooser's one background: nothing behind a viewer shows
# between or under its cards -- the menu's deck picker it opens over least of all.
func _ready() -> void:
	(margin_container.get_node(^"ColorRect") as ColorRect).color = \
			PaletteDB.color(PaletteDB.ROLES.hud_background)
	var gap := PlayArea.viewer_separation_px()
	flow_container.add_theme_constant_override(&"h_separation", gap)
	flow_container.add_theme_constant_override(&"v_separation", gap)

# ⚠ THE OPENER HANDS ITS OWN CONTROL IN: focus is cleared across every viewport of one window. A
# SECOND PRESS OF THAT SAME opener is a close and returns null; any other replaces the viewer, as
# swapping piles does, or opens `over` it, which stays open underneath.
static func show_deck(parent:Node, new_deck:Array[CardData], opener:Control,
		over := false) -> DeckViewer:
	var top : DeckViewer = _open if is_instance_valid(_open) and not _open.is_queued_for_deletion() \
			else null
	if top and (top._return_focus == opener or not over):
		var same_opener : bool = top._return_focus == opener
		top._close()
		if same_opener: return null
		top = null
	var viewer :DeckViewer= DECK_VIEWER.instantiate()
	viewer.deck = new_deck
	viewer._return_focus = opener
	viewer._under = top
	parent.add_child(viewer)
	viewer.update_viewer()
	_open = viewer
	return viewer

# THE OPENER IS ALSO THE CLOSER while its viewer is up, a second press toggling it shut, so it says
# so until the viewer leaves the tree, however it goes. A button freed first takes the connection.
static func read_close_while_open(opener: Button, close_key: StringName, viewer: DeckViewer) -> void:
	if viewer == null: return
	viewer.tree_exiting.connect(opener.set_text.bind(opener.text))
	opener.text = TRANSLATION.find(close_key)

# ⚠ ANNOUNCED BEFORE THE FOCUS IS HANDED BACK: the sidebar falls back to what was under this
# viewer first, so the opener is on screen again by the time the focus goes looking for it.
func _close() -> void:
	_open = _under
	queue_free()
	highlight_cleared.emit()
	_hand_the_focus_back()

# ⚠ THE OPENER CAN BE HIDDEN BY WHAT THIS VIEWER PUBLISHED, so the focus goes to the sidebar's X
# its host set. A viewer faded out with its screen gives no focus, and a list whose pick a leave
# dropped finds neither control on screen.
func _hand_the_focus_back() -> void:
	if not is_instance_valid(_return_focus) or not margin_container.is_visible_in_tree(): return
	if _return_focus.is_visible_in_tree(): _return_focus.grab_focus()
	elif fallback_focus.is_visible_in_tree(): fallback_focus.grab_focus()

# ⚠ NOTHING IS FOCUSED ON OPEN: a focus here is a highlight, and a highlight holds the sidebar
# against the HUD the player still has to reach. The first arrow enters the list instead
# (`HudContainer` hands it over, the two being in different viewports).
func update_viewer() -> void:
	_cards = CardsViewer.new(flow_container)
	_cards.close_tab = close_tab
	_cards.populate(deck, _publish_info)

# The card the highlight reached, drawn at this viewer's own card size.
func _publish_info(data: CardData) -> void:
	PlayArea.highlight_info(data, CardVisual.preview_window_px()).relay_to(info_requested)

# ⚠ THE CLICK-TO-CLOSE CATCHER IS EVERYTHING BESIDE THE SIDEBAR AS IT IS SHOWN, following its
# slide: on the sidebar's own layer this viewer draws above it, whose X, rows and Back must still
# take a click, and where it has slid out the strip it would rest on is outside like any other.
func fit_catcher(shown: Rect2) -> void:
	var picture := get_viewport().get_visible_rect().size
	margin_container.offset_left = shown.position.x
	margin_container.offset_top = shown.position.y
	margin_container.offset_right = shown.end.x - picture.x
	margin_container.offset_bottom = shown.end.y - picture.y

# THE LIST RESTS BESIDE WHERE THE SIDEBAR RESTS, inset by the scene's own padding, then WHOLE COLUMNS
# ONLY, centred: the width no column fits in goes to the side margins in halves. A scrolling list
# gives up its bar's width first, as the chooser's does; the scroll's own minimum is its focus border.
func fit_beside(remaining: Rect2) -> void:
	var catcher := margin_container.get_rect()
	_inset_margin(&"margin_left", remaining.position.x - catcher.position.x)
	_inset_margin(&"margin_top", remaining.position.y - catcher.position.y)
	_inset_margin(&"margin_right", catcher.end.x - remaining.end.x)
	_inset_margin(&"margin_bottom", catcher.end.y - remaining.end.y)
	var left := margin_container.get_theme_constant(&"margin_left")
	var right := margin_container.get_theme_constant(&"margin_right")
	var inner := catcher.size - _scroll.get_combined_minimum_size() - Vector2(left + right,
			margin_container.get_theme_constant(&"margin_top")
			+ margin_container.get_theme_constant(&"margin_bottom"))
	var columns := _whole_columns(inner.x)
	if _cards.column_px(ceili(float(_cards.controls.size()) / columns)) > inner.y:
		inner.x -= _scroll.get_v_scroll_bar().get_combined_minimum_size().x
		columns = _whole_columns(inner.x)
	var spare := inner.x - _cards.row_px(columns)
	margin_container.add_theme_constant_override(&"margin_left", left + floori(spare / 2.0))
	margin_container.add_theme_constant_override(&"margin_right",
			right + floori(spare - floori(spare / 2.0)))

func _whole_columns(width: float) -> int:
	var gap := flow_container.get_theme_constant(&"h_separation")
	return floori((width + gap) / (CardVisual.preview_window_px().x + gap))

## Publishes the card its highlight is on again -- asked by the opener only while a description is UP, so one the player dismissed stays dismissed across a re-fit.
func republish_highlight() -> void:
	_cards.republish_highlight()

## This viewer's listed cards, which carry the modal and sticky model its host wires itself to.
func cards() -> CardsViewer:
	return _cards

## The sidebar's own X asking this viewer to go: one press unsticks and closes together.
func close_from_sidebar() -> void:
	_close()

## The margins the scene authored, read once before the first fit overrides them.
var _authored_margins : Dictionary[StringName, int] = {}

# ⚠ SET FROM THE AUTHORED PADDING, NEVER ADDED TO WHAT IS THERE: this runs again on every slide step
# and window change while the viewer is open.
func _inset_margin(margin: StringName, inset: float) -> void:
	if not _authored_margins.has(margin):
		_authored_margins[margin] = margin_container.get_theme_constant(margin)
	margin_container.add_theme_constant_override(margin, _authored_margins[margin] + ceili(inset))

## Keyboard/controller: the shared modal verdict decides. Mouse click on the margin closes below.
func _unhandled_input(event: InputEvent) -> void:
	var verdict := _cards.modal_verdict(event)
	if verdict == CardsViewer.Modal.PASS: return
	get_viewport().set_input_as_handled()
	if verdict == CardsViewer.Modal.CLOSE: _close()

# EITHER BUTTON: a press outside the list closes, and the second button cancels from anywhere on
# screen, which over this viewer is the same act.
func _on_margin_container_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed: return
	if button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: _close()
