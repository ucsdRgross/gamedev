class_name WallOverlay
extends CanvasLayer
## The persistent overlay: Back, Forward and Wall in the TOP-LEFT — never the bottom, which would
## sit over start_menu's Profile/Options and the map's Deck button. Its own CanvasLayer so it never
## rides the wall camera, mounted at `%Overlay` inside wall.tscn. Owns no navigation state: it
## reports presses and reflects a `FocusStack` back out through `refresh()`.

## Emitted when the corresponding control is pressed. `Main` consumes all three.
signal back_pressed
signal forward_pressed
signal wall_pressed

@onready var _back_button : Button = %BackButton
@onready var _forward_button : Button = %ForwardButton
@onready var _wall_button : Button = %WallButton

## Localises every label (never a literal string) and wires each control to its signal.
func _ready() -> void:
	_back_button.text = TRANSLATION.find('WALL_BACK')
	_forward_button.text = TRANSLATION.find('WALL_FORWARD')
	_wall_button.text = TRANSLATION.find('WALL_OVERVIEW')
	_back_button.pressed.connect(_on_back_pressed)
	_forward_button.pressed.connect(_on_forward_pressed)
	_wall_button.pressed.connect(_on_wall_pressed)
	_apply_touch_targets()

## Grows every overlay control to at least `WallInput.touch_target_px()` on both axes.
##
## GROWS the authored layout rather than replacing it: each button keeps its authored top-left and
## the row keeps its authored GAP, both read back off the scene rather than re-typed here, so they
## cannot drift from it.
##
## ⚠ `custom_minimum_size` alone does NOT resize a manually-positioned Control until Godot's
## deferred layout pass, so `size` is set explicitly too, and a caller reading `size` straight
## after `_ready()` sees the real one.
func _apply_touch_targets() -> void:
	var target := WallInput.touch_target_px(DisplayServer.screen_get_dpi(),
			WallPicture.settings())
	var row : Array[Button] = [_back_button, _forward_button, _wall_button]
	var gap := row[1].position.x - (row[0].position.x + row[0].size.x)
	var x := row[0].position.x
	for button : Button in row:
		_grow_to(button, target)
		button.position.x = x
		x += button.size.x + gap

func _grow_to(button: Button, target: float) -> void:
	button.size = Vector2(maxf(button.size.x, target), maxf(button.size.y, target))
	button.custom_minimum_size = button.size

## Reflects `stack` back onto the controls. Call whenever focus changes; the scene's defaults
## already match a fresh stack, so this is only needed on CHANGE.
##
## Back and Forward VISIBLY disable (`Button.disabled`) rather than silently doing nothing. The
## Wall button HIDES outright while `picture_count` is 1 or fewer — nothing to overview with one
## picture.
##
## ⚠ `in_wall_view` changes what "can go back" MEANS. `can_back()` asks whether anything sits
## below the current picture, which is the right question only while a picture is focused. In wall
## view Back returns to the picture just left — the stack's top — so it is live whenever the stack
## has ANY entry. Without this the button greys out on cold launch -> Escape while the Escape key
## and joypad Back, which share this handler, still work.
func refresh(stack: FocusStack, picture_count: int = 2, in_wall_view: bool = false) -> void:
	_back_button.disabled = not (stack.current() != &"" if in_wall_view else stack.can_back())
	_forward_button.disabled = not stack.can_forward()
	_wall_button.visible = picture_count > 1

## The grown row's bottom edge, read off the buttons themselves rather than re-typed elsewhere.
func button_band_bottom() -> float:
	return maxf(_back_button.position.y + _back_button.size.y,
			maxf(_forward_button.position.y + _forward_button.size.y,
					_wall_button.position.y + _wall_button.size.y))

func _on_back_pressed() -> void:
	back_pressed.emit()

func _on_forward_pressed() -> void:
	forward_pressed.emit()

func _on_wall_pressed() -> void:
	wall_pressed.emit()
