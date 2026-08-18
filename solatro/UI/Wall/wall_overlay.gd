class_name WallOverlay
extends CanvasLayer
## The persistent overlay -- Back, Forward, Wall (GAP-016, owner-answered a: TOP-LEFT, moved off
## the bottom band that used to sit directly over start_menu's Profile/Options and the map's Deck
## button, making them unreachable by mouse) and the top-right Info toggle (NAMES.md; PLAN.md S35,
## implements B8, F7, F8, F9). Its own CanvasLayer (Q202=a) so it never rides the wall camera,
## mounted at `%Overlay` inside wall.tscn. Owns no navigation state itself -- it only reports presses
## via signals and reflects a FocusStack's shape back out through refresh().

## Emitted when the corresponding control is pressed. `Main` (`Levels/main.gd`) is the consumer of
## all four -- `back_pressed`/`forward_pressed`/`wall_pressed` drive navigation, `info_toggled`
## drives Info mode (CODE_REVIEW.md A2).
signal back_pressed
signal forward_pressed
signal wall_pressed
## `active` is the Info toggle's new pressed state.
signal info_toggled(active: bool)

@onready var _back_button : Button = %BackButton
@onready var _forward_button : Button = %ForwardButton
@onready var _wall_button : Button = %WallButton
@onready var _info_button : Button = %InfoButton

## Localises every label (never a literal string) and wires each control to its signal.
func _ready() -> void:
	_back_button.text = TRANSLATION.find('WALL_BACK')
	_forward_button.text = TRANSLATION.find('WALL_FORWARD')
	_wall_button.text = TRANSLATION.find('WALL_OVERVIEW')
	_info_button.text = TRANSLATION.find('WALL_INFO')
	_back_button.pressed.connect(_on_back_pressed)
	_forward_button.pressed.connect(_on_forward_pressed)
	_wall_button.pressed.connect(_on_wall_pressed)
	_info_button.toggled.connect(_on_info_toggled)

## F8 (Q65=c): Back and Forward VISIBLY disable themselves -- `Button.disabled`, not merely a press
## that silently does nothing -- whenever the given stack has nothing behind/ahead of the current
## picture. Call whenever focus changes; the scene's own defaults (both `disabled = true`) already
## match a fresh stack, so this only needs calling on CHANGE, not at construction.
## S36's own done-when: the Wall button additionally HIDES itself outright (not merely disables)
## while `picture_count` is 1 or fewer -- nothing to overview with just one picture on the wall.
## Defaults to 2 (i.e. visible) so callers that only care about Back/Forward -- F8/F9's own tests --
## are unaffected by the new parameter.
func refresh(stack: FocusStack, picture_count: int = 2) -> void:
	_back_button.disabled = not stack.can_back()
	_forward_button.disabled = not stack.can_forward()
	_wall_button.visible = picture_count > 1

## M3 (ADVERSARIAL_REVIEW): the `wall_info` key's way in. Flips the REAL toggle button rather than
## writing `wall_info_mode` from a second place, so the mode and what the button shows can never
## disagree -- setting `button_pressed` fires `toggled`, and from there a key press and a mouse
## press are the same path.
func toggle_info() -> void:
	_info_button.button_pressed = not _info_button.button_pressed

func _on_back_pressed() -> void:
	back_pressed.emit()

func _on_forward_pressed() -> void:
	forward_pressed.emit()

func _on_wall_pressed() -> void:
	wall_pressed.emit()

func _on_info_toggled(active: bool) -> void:
	info_toggled.emit(active)
